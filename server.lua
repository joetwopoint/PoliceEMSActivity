-- CONFIG --
roleList = Config.RoleList;

-- CODE --
Citizen.CreateThread(function()
	while true do 
		-- We wait a second and add it to their timeTracker 
		Wait(1000); -- Wait a second
		for k, v in pairs(timeTracker) do 
			timeTracker[k] = timeTracker[k] + 1;
		end 
	end 
end)
timeTracker = {}
hasPerms = {}
permTracker = {}
activeBlip = {}
onDuty = {}

local function buildPoliceEMSActivityDutyStats()
	-- This is the only source of truth for the loading screen on-duty box.
	-- It uses PoliceEMSActivity's own onDuty table and activeBlip selections.
	local departmentsByLabel = {}
	local departmentsArray = {}

	for label, _ in pairs(roleList) do
		departmentsByLabel[label] = {
			label = label,
			count = 0,
			names = {}
		}
	end

	for src, _ in pairs(onDuty) do
		local tag = activeBlip[src]
		if tag ~= nil and departmentsByLabel[tag] ~= nil then
			local dept = departmentsByLabel[tag]
			dept.count = dept.count + 1
			local playerName = GetPlayerName(tonumber(src))
			if playerName ~= nil then
				table.insert(dept.names, playerName)
			end
		end
	end

	for label, dept in pairs(departmentsByLabel) do
		if dept.count > 0 then
			table.insert(departmentsArray, dept)
		end
	end

	return {
		type = 'dutyStats',
		source = 'PoliceEMSActivity',
		updatedAt = os.time(),
		departments = departmentsArray
	}
end

local function broadcastDutyStats()
	-- Kept as a lightweight optional path for loading screens that support messages.
	-- The main display path is the PoliceEMSActivity HTTP endpoint below.
	if SendLoadingScreenMessage == nil then
		return
	end

	SendLoadingScreenMessage(json.encode(buildPoliceEMSActivityDutyStats()))
end

local function sendJsonResponse(res, status, body)
	res.writeHead(status, {
		['Content-Type'] = 'application/json',
		['Access-Control-Allow-Origin'] = '*',
		['Access-Control-Allow-Methods'] = 'GET, OPTIONS',
		['Access-Control-Allow-Headers'] = 'Content-Type',
		['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
	})
	res.send(json.encode(body))
end

SetHttpHandler(function(req, res)
	if req.method == 'OPTIONS' then
		return sendJsonResponse(res, 200, { ok = true })
	end

	local path = req.path or ''

	if path == '/policeemsactivity-duty.json'
		or path == '/PoliceEMSActivity/duty.json'
		or path == '/PoliceEMSActivity/policeemsactivity-duty.json'
		or path == '/duty.json' then
		return sendJsonResponse(res, 200, buildPoliceEMSActivityDutyStats())
	end

	return sendJsonResponse(res, 404, { error = 'Not found' })
end)

prefix = '^9[^5Badger-Blips^9] ^3';

local function getChatColorFromBlipTag(src)
	local tag = activeBlip[src]
	if tag ~= nil and roleList[tag] ~= nil then
		local blipColor = roleList[tag][2]
		if blipColor == 1 then
			-- Fire (red)
			return '^1'
		elseif blipColor == 3 then
			-- LEO (blue)
			return '^4'
		elseif blipColor == 5 then
			-- EMS (yellow)
			return '^3'
		elseif blipColor == 52 then
			-- BP (green-ish)
			return '^2'
		end
	end
	-- fallback
	return '^0'
end

local function getDeptLabelFromBlipTag(src)
	local tag = activeBlip[src]
	if tag ~= nil then
		local firstSpace = string.find(tag, " ")
		if firstSpace then
			return string.sub(tag, firstSpace + 1)
		end
		return tag
	end
	return 'Unknown'
end


AddEventHandler("playerDropped", function()
	if onDuty[source] ~= nil then 
		local tag = activeBlip[source];
		local webHook = roleList[activeBlip[source]][3];
		if webHook ~= nil then 
			local time = timeTracker[source];
			local now = os.time();
			local startPlusNow = now + time;
			local minutesActive = os.difftime(now, startPlusNow) / 60;
			minutesActive = math.floor(math.abs(minutesActive))
			sendToDisc('Player ' .. GetPlayerName(source) .. ' is now off duty', 'Player ' .. GetPlayerName(source) .. ' has gone off duty as ' .. tag, 
			'Duration: ' .. minutesActive .. ' minutes',
				webHook, 16711680)
		end 
	end
	timeTracker[source] = nil;
	onDuty[source] = nil;
	broadcastDutyStats();
	permTracker[source] = nil;
	hasPerms[source] = nil;
	activeBlip[source] = nil;
	-- Remove them from Blips:
	TriggerEvent('eblips:remove', source)
end)
function sendToDisc(title, message, footer, webhookURL, color)
	local embed = {}
	embed = {
		{
			["color"] = color, -- GREEN = 65280 --- RED = 16711680
			["title"] = "**".. title .."**",
			["description"] = "** " .. message ..  " **",
			["footer"] = {
			["text"] = footer,
			},
		}
	}
	-- Start
	-- TODO Input Webhook
	PerformHttpRequest(webhookURL, 
	function(err, text, headers) end, 'POST', json.encode({username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
  -- END
end
RegisterCommand('bduty', function(source, args, rawCommand)
	-- The /blip command to toggle on and off the cop blip  
	if hasPerms[source] ~= nil then 
		if onDuty[source] == nil then 
			local colorr = roleList[activeBlip[source]][2];
			local tag = activeBlip[source];
			local webHook = roleList[activeBlip[source]][3];
			if webHook ~= nil then
				sendToDisc('Player ' .. GetPlayerName(source) .. ' is now on duty', 'Player ' .. GetPlayerName(source) .. ' has gone on duty as ' .. tag, '',
					webHook, 65280)
			end
			TriggerEvent('eblips:add', {name = tag .. GetPlayerName(source), src = source, color = colorr}); 
			sendMsg(source, 'You have toggled your emergency blip ^2ON ^3and your Blip-Tag is: ' .. tag)
			onDuty[source] = true;
			broadcastDutyStats();
			timeTracker[source] = 0;
			TriggerClientEvent('PoliceEMSActivity:GiveWeapons', source);
		else 
			onDuty[source] = nil;
			broadcastDutyStats();
			local tag = activeBlip[source];
			local webHook = roleList[activeBlip[source]][3];
			if webHook ~= nil then
				local time = timeTracker[source];
				local now = os.time();
				local startPlusNow = now + time;
				local minutesActive = os.difftime(now, startPlusNow) / 60;
				minutesActive = math.floor(math.abs(minutesActive))
				sendToDisc('Player ' .. GetPlayerName(source) .. ' is now off duty', 'Player ' .. GetPlayerName(source) .. ' has gone off duty as ' .. tag, 
				'Duration: ' .. minutesActive .. ' minutes',
					webHook, 16711680)
			end
			TriggerClientEvent('PoliceEMSActivity:TakeWeapons', source);
			timeTracker[source] = nil;
			sendMsg(source, 'You have toggled your emergency blip ^1OFF')
			TriggerEvent('eblips:remove', source)
		end
	else 
		-- You are not a cop, you must be a cop in our discord to use it 
		sendMsg(source, '^1ERROR: You must be an LEO on our discord to use this...')
	end
end)
RegisterCommand('cops', function(source, args, rawCommand) 
	-- Prints the active cops online with a /blip that is on 
	sendMsg(source, 'The active cops on are:')
	for id, _ in pairs(onDuty) do 
		local chatColor = getChatColorFromBlipTag(id)
		local deptLabel = getDeptLabelFromBlipTag(id)
		local name = GetPlayerName(id)
		TriggerClientEvent('chatMessage', source, '^9[^4' .. id .. '^9] ' .. chatColor .. deptLabel .. ' | ' .. name);
	end
end)
function sendMsg(src, msg) 
	TriggerClientEvent('chatMessage', src, prefix .. msg);
end
RegisterCommand('bliptag', function(source, args, rawCommand)
	-- The /blipTag command to toggle on and off the cop blip 
	if hasPerms[source] ~= nil then 
		if #args == 0 then 
			-- List out which ones they have access to 
			sendMsg(source, 'You have access to the following Blip-Tags:');
			for i = 1, #permTracker[source] do 
				-- List 
				TriggerClientEvent('chatMessage', source, '^9[^4' .. i .. '^9] ^0' .. permTracker[source][i]);
			end
		else 
			-- Choose their bliptag 
			local selection = args[1];
			if tonumber(selection) ~= nil then 
				local sel = tonumber(selection);
				local theirBlips = permTracker[source];
				if sel <= #theirBlips then
					-- Set up their tag
					local tag = activeBlip[source];
					local webHook = roleList[activeBlip[source]][3];
					if onDuty[source] ~= nil then 
						local time = timeTracker[source];
						local now = os.time();
						local startPlusNow = now + time;
						local minutesActive = os.difftime(now, startPlusNow) / (60);
						minutesActive = math.floor(math.abs(minutesActive))
						sendToDisc('Player ' .. GetPlayerName(source) .. ' is now off duty', 'Player ' .. GetPlayerName(source) 
							.. ' has gone off duty as ' .. tag, 'Duration: ' .. minutesActive,
							webHook, 16711680)
						timeTracker[source] = 0;
					end
					activeBlip[source] = permTracker[source][sel];
					sendMsg(source, 'You have set your Blip-Tag to ^1' .. permTracker[source][sel]);
					if onDuty[source] ~= nil then 
						tag = activeBlip[source];
						webHook = roleList[activeBlip[source]][3];
						sendToDisc('Player ' .. GetPlayerName(source) .. ' is now on duty', 'Player ' .. GetPlayerName(source) .. ' has gone on duty as ' .. tag, '',
							webHook, 65280) 
						local colorr = roleList[activeBlip[source]][2]
						TriggerEvent('eblips:remove', source)
						TriggerEvent('eblips:add', {name = tag .. GetPlayerName(source), src = source, color = colorr});
					end
				else 
					-- That is not a valid selection 
					sendMsg(source, '^1ERROR: That is not a valid selection...')
				end
			else 
				-- Not a number 
				sendMsg(source, '^1ERROR: That is not a number...')
			end
		end
	else 
		-- You are not a cop, you must be a cop in our discord to use this 
		sendMsg(source, '^1ERROR: You must be an LEO on our discord to use this...')
	end 
end)


RegisterNetEvent('PoliceEMSActivity:RegisterUser')
AddEventHandler('PoliceEMSActivity:RegisterUser', function()
	local src = source
	for k, v in ipairs(GetPlayerIdentifiers(src)) do
			if string.sub(v, 1, string.len("discord:")) == "discord:" then
				identifierDiscord = v
			end
	end
	local perms = {}
	if identifierDiscord then
		local roleIDs = exports.Badger_Discord_API:GetDiscordRoles(src)
		if not (roleIDs == false) then
			for k, v in pairs(roleList) do
				for j = 1, #roleIDs do
					if exports.Badger_Discord_API:CheckEqual(v[1], roleIDs[j]) then
						table.insert(perms, k);
						activeBlip[src] = k;
						hasPerms[src] = true;
						print("[PEA] Gave Perms Sucessfully")
					end
				end
			end
			permTracker[src] = perms;
		else
			print("[PoliceEMSActivity] " .. GetPlayerName(src) .. " has not gotten their permissions cause roleIDs == false")
		end
	else
		print("[PoliceEMSActivity] " .. GetPlayerName(src) .. " has not gotten their permissions cause discord was not detected...")
	end
	permTracker[src] = perms; 
	broadcastDutyStats();
end)
