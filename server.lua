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

-- Duty time persistence (total hours per player)
local totalTime = {}
local DUTY_TIME_FILE = "duty_times.json"

local function loadTotalTimes()
    local data = LoadResourceFile(GetCurrentResourceName(), DUTY_TIME_FILE)
    if data then
        local ok, decoded = pcall(json.decode, data)
        if ok and type(decoded) == "table" then
            totalTime = decoded
        else
            totalTime = {}
        end
    end
end

local function saveTotalTimes()
    if totalTime then
        SaveResourceFile(GetCurrentResourceName(), DUTY_TIME_FILE, json.encode(totalTime), -1)
    end
end

local function getIdentifier(src)
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and (string.sub(id, 1, 7) == "license" or string.sub(id, 1, 5) == "steam") then
            return id
        end
    end
    return "src:" .. tostring(src)
end

local function formatTime(seconds)
    seconds = tonumber(seconds) or 0
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%dh %02dm %02ds", hours, minutes, secs)
    else
        return string.format("%dm %02ds", minutes, secs)
    end
end

prefix = '^9[^5Badger-Blips^9] ^3';

local function getDeptLabelFromTag(tag)
    if not tag then return 'Unknown' end
    local firstSpace = string.find(tag, " ")
    if firstSpace then
        return string.sub(tag, firstSpace + 1)
    end
    return tag
end

AddEventHandler("playerDropped", function()
    if onDuty[source] ~= nil then 
        local tag = activeBlip[source]
        local webHook = roleList[tag] and roleList[tag][3] or nil
        if webHook ~= nil then
            -- Use the central off-duty logger to track session + total time
            handleOffDutyLogging(source, tag, webHook, 16711680)
        else
            timeTracker[source] = nil
        end
    end
    -- Clean up state
    timeTracker[source] = nil
    onDuty[source] = nil
    permTracker[source] = nil
    hasPerms[source] = nil
    activeBlip[source] = nil
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

-- Send duty logs to both the department-specific webhook and the global all-departments webhook
function sendDutyLog(title, message, footer, deptWebhook, color)
    color = color or 16711680

    -- Department-specific webhook
    if deptWebhook and deptWebhook ~= '' then
        sendToDisc(title, message, footer, deptWebhook, color)
    end

    -- Global "all departments" webhook
    if Config.AllDeptsWebhook ~= nil and Config.AllDeptsWebhook ~= '' then
        sendToDisc(title, message, footer, Config.AllDeptsWebhook, color)
    end
end

-- Centralized off-duty logging that also updates total time
function handleOffDutyLogging(src, tag, webHook, color)
    local sessionSeconds = timeTracker[src] or 0
    local identifier = getIdentifier(src)
    local prevTotal = totalTime[identifier] or 0
    local newTotal = prevTotal + sessionSeconds

    totalTime[identifier] = newTotal
    saveTotalTimes()

    local sessionStr = formatTime(sessionSeconds)
    local totalStr = formatTime(newTotal)
    local dept = getDeptLabelFromTag(tag)

    local title = 'Player ' .. GetPlayerName(src) .. ' is now off duty'
    local message =
        'Player ' .. GetPlayerName(src) .. ' has gone off duty as ' .. tostring(tag) ..
        '\nDepartment: ' .. dept ..
        '\nSession time: ' .. sessionStr ..
        '\nTotal logged time: ' .. totalStr

    sendDutyLog(title, message, 'Duty Time Logger', webHook, color or 16711680)

    timeTracker[src] = nil
end

-- Load existing duty totals on resource start
loadTotalTimes()

RegisterCommand('bduty', function(source, args, rawCommand)
	-- Use: /bduty [tpd|pcso|azdps|fire|ems|bp|off]
	if hasPerms[source] == nil then
		-- You are not a cop, you must be a cop in our discord to use it 
		sendMsg(source, '^1ERROR: You must be an LEO on our discord to use this...')
		return
	end

	if #args == 0 then
		sendMsg(source, '^3Usage: /bduty [tpd|pcso|azdps|fire|ems|bp|off]')
		return
	end

	local sub = string.lower(tostring(args[1] or ''))

	-- Handle turning off duty explicitly
	if sub == 'off' then
		if onDuty[source] == nil then
			sendMsg(source, '^1ERROR: You are not currently on duty.')
			return
		end

		local tag = activeBlip[source]
		local webHook = tag and roleList[tag] and roleList[tag][3] or nil
		if webHook ~= nil then
			handleOffDutyLogging(source, tag, webHook, 16711680)
		else
			timeTracker[source] = nil
		end

		onDuty[source] = nil
		TriggerClientEvent('PoliceEMSActivity:TakeWeapons', source)
		sendMsg(source, 'You have toggled your emergency blip ^1OFF')
		TriggerEvent('eblips:remove', source)
		return
	end

	-- Map department shorthand to roleList tags
	local aliasToTag = {
		['tpd'] = '👮 TPD',
		['pcso'] = '👮 PCSO',
		['azdps'] = '👮 AZDPS',
		['fire'] = '👨‍🚒 Fire',
		['ems'] = '👨‍🚒🚑 EMS',
		['bp'] = '👮 BP',
		['borderpatrol'] = '👮 BP',
	}

	local deptTag = aliasToTag[sub]
	if not deptTag then
		sendMsg(source, '^1ERROR: Unknown department. Use: tpd, pcso, azdps, fire, ems, bp, or off.')
		return
	end

	-- Check they actually have permission for this department
	local theirBlips = permTracker[source] or {}
	local allowed = false
	for i = 1, #theirBlips do
		if theirBlips[i] == deptTag then
			allowed = true
			break
		end
	end

	if not allowed then
		sendMsg(source, '^1ERROR: You do not have permission for ' .. deptTag .. '.')
		return
	end

	-- If already on duty with this dept, treat as OFF toggle
	if onDuty[source] ~= nil and activeBlip[source] == deptTag then
		local tag = activeBlip[source]
		local webHook = roleList[tag] and roleList[tag][3] or nil
		if webHook ~= nil then
			handleOffDutyLogging(source, tag, webHook, 16711680)
		else
			timeTracker[source] = nil
		end

		onDuty[source] = nil
		TriggerClientEvent('PoliceEMSActivity:TakeWeapons', source)
		sendMsg(source, 'You have toggled your emergency blip ^1OFF')
		TriggerEvent('eblips:remove', source)
		return
	end

	-- If on duty in another dept, log that one off first
	if onDuty[source] ~= nil and activeBlip[source] ~= nil and activeBlip[source] ~= deptTag then
		local oldTag = activeBlip[source]
		local oldWebhook = roleList[oldTag] and roleList[oldTag][3] or nil
		if oldWebhook ~= nil then
			handleOffDutyLogging(source, oldTag, oldWebhook, 16711680)
		else
			timeTracker[source] = nil
		end
		TriggerEvent('eblips:remove', source)
	end

	-- Now place them on duty with the requested department
	activeBlip[source] = deptTag
	onDuty[source] = true
	timeTracker[source] = 0

	local tag = deptTag
	local webHook = roleList[tag] and roleList[tag][3] or nil
	if webHook ~= nil then
		local dept = getDeptLabelFromTag(tag)
		local title = 'Player ' .. GetPlayerName(source) .. ' is now on duty'
		local message = 'Player ' .. GetPlayerName(source) .. ' has gone on duty as ' .. tag .. '\nDepartment: ' .. dept
		sendDutyLog(title, message, 'Duty Time Logger', webHook, 65280)
	end

	local colorr = roleList[tag][2]
	TriggerEvent('eblips:add', {name = tag .. GetPlayerName(source), src = source, color = colorr})
	local dept = getDeptLabelFromTag(tag)
	sendMsg(source, 'You have toggled your emergency blip ^2ON ^3as ' .. dept)
	TriggerClientEvent('PoliceEMSActivity:GiveWeapons', source)
end)
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
	return '^0'
end

local function getDeptLabelFromBlipTag(src)
	local tag = activeBlip[src]
	if not tag then return 'Unknown' end
	local firstSpace = string.find(tag, " ")
	if firstSpace then
		return string.sub(tag, firstSpace + 1)
	end
	return tag
end

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
					local oldTag = activeBlip[source]
					local oldWebHook = oldTag and roleList[oldTag] and roleList[oldTag][3] or nil
					if onDuty[source] ~= nil then 
						if oldWebHook ~= nil then
							handleOffDutyLogging(source, oldTag, oldWebHook, 16711680)
						else
							timeTracker[source] = nil
						end
					end
					activeBlip[source] = permTracker[source][sel]
					sendMsg(source, 'You have set your Blip-Tag to ^1' .. permTracker[source][sel])
					if onDuty[source] ~= nil then 
						-- Restart their duty time for the new department
						timeTracker[source] = 0
						local tag = activeBlip[source]
						local webHook = roleList[tag] and roleList[tag][3] or nil
						if webHook ~= nil then
							local dept = getDeptLabelFromTag(tag)
							local title = 'Player ' .. GetPlayerName(source) .. ' is now on duty'
							local message = 'Player ' .. GetPlayerName(source) .. ' has gone on duty as ' .. tag .. '\nDepartment: ' .. dept
							sendDutyLog(title, message, 'Duty Time Logger', webHook, 65280)
						end
						local colorr = roleList[tag][2]
						TriggerEvent('eblips:remove', source)
						TriggerEvent('eblips:add', {name = tag .. GetPlayerName(source), src = source, color = colorr})
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
end)
