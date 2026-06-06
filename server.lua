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

local discordMemberCountCache = {
	ok = false,
	memberCount = nil,
	onlineCount = nil,
	source = 'not-loaded',
	updatedAt = 0,
	error = 'Discord total count has not loaded yet.'
}

local function trimString(value)
	return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function getConfigString(name, defaultValue)
	if Config ~= nil and Config[name] ~= nil then
		return trimString(Config[name])
	end
	return trimString(defaultValue or '')
end

local function getConfigNumber(name, defaultValue)
	if Config ~= nil and Config[name] ~= nil and tonumber(Config[name]) ~= nil then
		return tonumber(Config[name])
	end
	return tonumber(defaultValue)
end

local function parseDiscordInviteCode(value)
	local invite = trimString(value)
	if invite == '' then return '' end

	invite = invite:gsub('https://discord%.gg/', '')
	invite = invite:gsub('http://discord%.gg/', '')
	invite = invite:gsub('https://discord%.com/invite/', '')
	invite = invite:gsub('http://discord%.com/invite/', '')
	invite = invite:gsub('discord%.gg/', '')
	invite = invite:gsub('discord%.com/invite/', '')

	local queryStart = invite:find('?', 1, true)
	if queryStart ~= nil then
		invite = invite:sub(1, queryStart - 1)
	end

	return trimString(invite)
end

local function updateDiscordMemberCountCache(ok, data)
	data = data or {}
	discordMemberCountCache = {
		ok = ok == true,
		memberCount = data.memberCount,
		onlineCount = data.onlineCount,
		source = data.source or 'unknown',
		updatedAt = os.time(),
		error = data.error
	}

	if ok == true then
		print('[PoliceEMSActivity LoadingScreen] Discord member count updated: ' .. tostring(data.memberCount) .. ' via ' .. tostring(data.source or 'unknown'))
	else
		print('[PoliceEMSActivity LoadingScreen] Discord member count failed via ' .. tostring(data.source or 'unknown') .. ': ' .. tostring(data.error or 'unknown error'))
	end
end

local function decodeDiscordJson(body)
	if body == nil or body == '' then return nil end
	local ok, decoded = pcall(json.decode, body)
	if ok and type(decoded) == 'table' then
		return decoded
	end
	return nil
end


local function requestDiscordCountFromGuildPreview(guildId, reason)
	guildId = trimString(guildId)
	if guildId == '' then
		updateDiscordMemberCountCache(false, {
			source = 'discord-guild-preview',
			error = 'LOADING_SCREEN_DISCORD_GUILD_ID is blank.' .. (reason and (' ' .. reason) or '')
		})
		return
	end

	-- Public guild preview can return approximate counts for some discoverable/public guilds.
	-- It is only a fallback; bot token or invite code is more reliable.
	PerformHttpRequest('https://discord.com/api/v10/guilds/' .. guildId .. '/preview', function(statusCode, body)
		local decoded = decodeDiscordJson(body)
		if (tonumber(statusCode) or 0) >= 200 and (tonumber(statusCode) or 0) < 300 and decoded ~= nil and decoded.approximate_member_count ~= nil then
			updateDiscordMemberCountCache(true, {
				memberCount = tonumber(decoded.approximate_member_count),
				onlineCount = tonumber(decoded.approximate_presence_count),
				source = 'discord-guild-preview'
			})
		else
			updateDiscordMemberCountCache(false, {
				source = 'discord-guild-preview',
				error = 'Discord guild preview failed. HTTP ' .. tostring(statusCode) .. '. Set LOADING_SCREEN_DISCORD_INVITE_CODE or discord_bot_token for a real total.' .. (reason and (' ' .. reason) or '')
			})
		end
	end, 'GET', '', { ['Content-Type'] = 'application/json' })
end

local function requestDiscordCountFromConfiguredInviteOrWidget(reason)
	local configuredInvite = parseDiscordInviteCode(getConfigString('LOADING_SCREEN_DISCORD_INVITE_CODE', ''))
	if configuredInvite ~= '' then
		PerformHttpRequest('https://discord.com/api/v10/invites/' .. configuredInvite .. '?with_counts=true', function(statusCode, body)
			local decoded = decodeDiscordJson(body)
			if (tonumber(statusCode) or 0) >= 200 and (tonumber(statusCode) or 0) < 300 and decoded ~= nil and decoded.approximate_member_count ~= nil then
				updateDiscordMemberCountCache(true, {
					memberCount = tonumber(decoded.approximate_member_count),
					onlineCount = tonumber(decoded.approximate_presence_count),
					source = 'discord-invite-count'
				})
			else
				updateDiscordMemberCountCache(false, {
					source = 'discord-invite-count',
					error = 'Discord invite count failed. HTTP ' .. tostring(statusCode) .. (reason and ('; ' .. reason) or '')
				})
			end
		end, 'GET', '', { ['Content-Type'] = 'application/json' })
		return
	end

	local guildId = getConfigString('LOADING_SCREEN_DISCORD_GUILD_ID', '')
	if guildId == '' then
		updateDiscordMemberCountCache(false, {
			source = 'discord-widget-invite',
			error = 'LOADING_SCREEN_DISCORD_GUILD_ID is blank.'
		})
		return
	end

	PerformHttpRequest('https://discord.com/api/guilds/' .. guildId .. '/widget.json', function(statusCode, body)
		local decoded = decodeDiscordJson(body)
		local inviteCode = ''
		if (tonumber(statusCode) or 0) >= 200 and (tonumber(statusCode) or 0) < 300 and decoded ~= nil and decoded.instant_invite ~= nil then
			inviteCode = parseDiscordInviteCode(decoded.instant_invite)
		end

		if inviteCode == '' then
			requestDiscordCountFromGuildPreview(guildId, 'Discord widget did not return an invite link.' .. (reason and (' ' .. reason) or ''))
			return
		end

		PerformHttpRequest('https://discord.com/api/v10/invites/' .. inviteCode .. '?with_counts=true', function(inviteStatusCode, inviteBody)
			local inviteDecoded = decodeDiscordJson(inviteBody)
			if (tonumber(inviteStatusCode) or 0) >= 200 and (tonumber(inviteStatusCode) or 0) < 300 and inviteDecoded ~= nil and inviteDecoded.approximate_member_count ~= nil then
				updateDiscordMemberCountCache(true, {
					memberCount = tonumber(inviteDecoded.approximate_member_count),
					onlineCount = tonumber(inviteDecoded.approximate_presence_count),
					source = 'discord-widget-invite-count'
				})
			else
				updateDiscordMemberCountCache(false, {
					source = 'discord-widget-invite-count',
					error = 'Discord widget invite count failed. HTTP ' .. tostring(inviteStatusCode) .. (reason and ('; ' .. reason) or '')
				})
			end
		end, 'GET', '', { ['Content-Type'] = 'application/json' })
	end, 'GET', '', { ['Content-Type'] = 'application/json' })
end

local function refreshDiscordMemberCount()
	local overrideCount = getConfigNumber('LOADING_SCREEN_DISCORD_MEMBER_COUNT_OVERRIDE', nil)
	if overrideCount ~= nil and overrideCount >= 0 then
		updateDiscordMemberCountCache(true, {
			memberCount = math.floor(overrideCount),
			onlineCount = nil,
			source = 'manual-override'
		})
		return
	end

	local guildId = getConfigString('LOADING_SCREEN_DISCORD_GUILD_ID', '')
	local token = getConfigString('LOADING_SCREEN_DISCORD_BOT_TOKEN', '')
	local tokenConvar = getConfigString('LOADING_SCREEN_DISCORD_BOT_TOKEN_CONVAR', 'discord_bot_token')

	if token == '' and tokenConvar ~= '' then
		token = trimString(GetConvar(tokenConvar, ''))
	end

	if guildId ~= '' and token ~= '' then
		PerformHttpRequest('https://discord.com/api/v10/guilds/' .. guildId .. '?with_counts=true', function(statusCode, body)
			local decoded = decodeDiscordJson(body)
			local memberCount = nil
			local onlineCount = nil

			if decoded ~= nil then
				memberCount = tonumber(decoded.member_count) or tonumber(decoded.approximate_member_count)
				onlineCount = tonumber(decoded.approximate_presence_count)
			end

			if (tonumber(statusCode) or 0) >= 200 and (tonumber(statusCode) or 0) < 300 and memberCount ~= nil then
				updateDiscordMemberCountCache(true, {
					memberCount = memberCount,
					onlineCount = onlineCount,
					source = 'discord-bot-guild-count'
				})
			else
				requestDiscordCountFromConfiguredInviteOrWidget('Bot guild count failed. HTTP ' .. tostring(statusCode) .. '.')
			end
		end, 'GET', '', {
			['Authorization'] = 'Bot ' .. token,
			['Content-Type'] = 'application/json'
		})
		return
	end

	requestDiscordCountFromConfiguredInviteOrWidget(nil)
end

local function getDiscordMemberCountPayload()
	return {
		type = 'discordMemberCount',
		source = discordMemberCountCache.source,
		ok = discordMemberCountCache.ok,
		memberCount = discordMemberCountCache.memberCount,
		member_count = discordMemberCountCache.memberCount,
		approximate_member_count = discordMemberCountCache.memberCount,
		onlineCount = discordMemberCountCache.onlineCount,
		updatedAt = discordMemberCountCache.updatedAt,
		error = discordMemberCountCache.error
	}
end

Citizen.CreateThread(function()
	Wait(2500)
	while true do
		refreshDiscordMemberCount()
		local refreshSeconds = getConfigNumber('LOADING_SCREEN_DISCORD_REFRESH_SECONDS', 300)
		if refreshSeconds == nil or refreshSeconds < 60 then refreshSeconds = 300 end
		Wait(math.floor(refreshSeconds * 1000))
	end
end)

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

	if path == '/discord-member-count.json'
		or path == '/discord-count.json'
		or path == '/PoliceEMSActivity/discord-member-count.json'
		or path == '/PoliceEMSActivity/discord-count.json'
		or string.find(path, 'discord%-member%-count%.json') ~= nil
		or string.find(path, 'discord%-count%.json') ~= nil then
		if discordMemberCountCache.ok ~= true and (os.time() - (discordMemberCountCache.updatedAt or 0)) > 30 then
			refreshDiscordMemberCount()
		end
		return sendJsonResponse(res, discordMemberCountCache.ok and 200 or 503, getDiscordMemberCountPayload())
	end

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
