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

-- Load Discord permissions only when a manual command needs them.
-- This avoids one Badger/Discord request per player during resource restart.
local permissionLastAttempt = {}

-- Dedicated roster used by /cops. Keeping this separate from the blip table
-- prevents CAD-synced duty entries from being missed by the command.
local dutyRoster = {}
local resolveLonexCADTag

local function normalizePlayerSource(src)
	return tonumber(src) or src
end

local function setDutyRosterEntry(src, tag, dutySource)
	src = normalizePlayerSource(src)
	dutyRoster[src] = {
		tag = tag,
		name = GetPlayerName(src) or ('Player ' .. tostring(src)),
		since = os.time(),
		source = dutySource or 'unknown'
	}
end

local function removeDutyRosterEntry(src)
	src = normalizePlayerSource(src)
	dutyRoster[src] = nil
end

local function getLonexCADRoster()
	local syncConfig = Config.LonexCADSync or {}
	if syncConfig.UseCADRosterFallback == false then
		return nil, 'disabled'
	end

	local cadResourceName = syncConfig.CADResourceName or 'lonexcad'
	if GetResourceState(cadResourceName) ~= 'started' then
		return nil, 'cad_resource_not_started:' .. cadResourceName
	end

	local ok, roster = pcall(function()
		return exports[cadResourceName]:GetOnDutyOfficers()
	end)
	if not ok then
		return nil, tostring(roster)
	end
	if type(roster) ~= 'table' then
		return nil, 'cad_roster_invalid'
	end

	return roster
end

local function getDutyRosterSnapshot()
	local entries = {}
	local seen = {}

	-- Prefer the dedicated roster populated by both CAD sync and /bduty.
	for rawId, rosterEntry in pairs(dutyRoster) do
		local id = normalizePlayerSource(rawId)
		local playerName = GetPlayerName(id)
		if playerName ~= nil then
			local tag = (rosterEntry and rosterEntry.tag) or activeBlip[id] or activeBlip[rawId]
			table.insert(entries, { id = id, name = playerName, tag = tag })
			seen[tostring(id)] = true
		else
			-- Remove stale entries rather than letting one disconnected player break /cops.
			dutyRoster[rawId] = nil
		end
	end

	-- Backward-compatible fallback for any older/manual code that only writes onDuty.
	for rawId, _ in pairs(onDuty) do
		local id = normalizePlayerSource(rawId)
		if not seen[tostring(id)] then
			local playerName = GetPlayerName(id)
			if playerName ~= nil then
				table.insert(entries, {
					id = id,
					name = playerName,
					tag = activeBlip[id] or activeBlip[rawId]
				})
				seen[tostring(id)] = true
			end
		end
	end


	-- Merge LonexCAD's authoritative roster so /cops does not depend only
	-- on PoliceEMSActivity's in-memory duty table.
	local cadRoster, cadRosterError = getLonexCADRoster()
	if cadRoster ~= nil then
		for rawId, officer in pairs(cadRoster) do
			local id = normalizePlayerSource((type(officer) == 'table' and officer.source) or rawId)
			local playerName = GetPlayerName(id)
			if playerName ~= nil then
				local department = {
					id = type(officer) == 'table' and officer.departmentId or nil,
					name = type(officer) == 'table' and officer.departmentName or nil,
					shortName = type(officer) == 'table' and officer.departmentShortName or nil
				}
				local mappedTag = nil
				if resolveLonexCADTag ~= nil then
					mappedTag = select(1, resolveLonexCADTag(department))
				end
				local tag = activeBlip[id] or mappedTag
					or (type(officer) == 'table' and (officer.departmentShortName or officer.departmentName))
					or 'Unknown'

				if not seen[tostring(id)] then
					table.insert(entries, { id = id, name = playerName, tag = tag })
					seen[tostring(id)] = true
				end
			end
		end
	elseif (Config.LonexCADSync or {}).Debug then
		print('[PoliceEMSActivity] Unable to read LonexCAD roster: ' .. tostring(cadRosterError))
	end

	table.sort(entries, function(a, b)
		local aId = tonumber(a.id) or 0
		local bId = tonumber(b.id) or 0
		return aId < bId
	end)

	return entries
end

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
	removeDutyRosterEntry(source);
	broadcastDutyStats();
	permTracker[source] = nil;
	permissionLastAttempt[source] = nil;
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


-- ---------------------------------------------------------------------------
-- LonexCAD integration

local function normalizeDepartmentValue(value)
	if value == nil then return nil end
	return tostring(value):lower():gsub('[^%w]', '')
end

local function getPermissionRetryCooldown()
	local cfg = Config.DiscordPermissions or {}
	return tonumber(cfg.RetryCooldownSeconds) or 60
end

local function refreshUserPermissions(src, force)
	src = tonumber(src)
	if not src or GetPlayerName(src) == nil then
		return {}, 'player_not_online'
	end

	local cachedPerms = permTracker[src]
	local now = os.time()
	local lastAttempt = permissionLastAttempt[src] or 0
	if force ~= true and lastAttempt > 0 and (now - lastAttempt) < getPermissionRetryCooldown() then
		return cachedPerms or {}, 'permission_retry_cooldown'
	end
	permissionLastAttempt[src] = now

	local discordIdentifier = nil
	for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
		if string.sub(identifier, 1, string.len('discord:')) == 'discord:' then
			discordIdentifier = identifier
			break
		end
	end

	if discordIdentifier == nil then
		return cachedPerms or {}, 'discord_not_detected'
	end

	if GetResourceState('Badger_Discord_API') ~= 'started' then
		return cachedPerms or {}, 'badger_discord_api_not_started'
	end

	local ok, roleIDs = pcall(function()
		return exports['Badger_Discord_API']:GetDiscordRoles(src)
	end)
	if not ok or type(roleIDs) ~= 'table' then
		-- Keep any previous successful cache during a temporary Discord rate limit.
		return cachedPerms or {}, 'discord_roles_unavailable'
	end

	local perms = {}
	for tag, roleData in pairs(roleList) do
		for i = 1, #roleIDs do
			if exports['Badger_Discord_API']:CheckEqual(roleData[1], roleIDs[i]) then
				table.insert(perms, tag)
				break
			end
		end
	end

	permTracker[src] = perms
	hasPerms[src] = (#perms > 0) and true or nil

	local currentTagAllowed = false
	for _, tag in ipairs(perms) do
		if tag == activeBlip[src] then
			currentTagAllowed = true
			break
		end
	end
	if not currentTagAllowed and #perms > 0 then
		activeBlip[src] = perms[1]
	end

	return perms, (#perms > 0) and nil or 'no_matching_roles'
end

local function ensureUserPermissions(src, force)
	local perms = permTracker[src]
	if force ~= true and type(perms) == 'table' and #perms > 0 then
		return perms
	end
	return refreshUserPermissions(src, force)
end

local function playerHasTagPermission(src, tag)
	local perms = select(1, ensureUserPermissions(src, false))
	for _, allowedTag in ipairs(perms or {}) do
		if allowedTag == tag then
			return true
		end
	end
	return false
end

resolveLonexCADTag = function(department)
	local syncConfig = Config.LonexCADSync or {}
	local configuredMap = syncConfig.DepartmentMap or {}
	local normalizedMap = {}

	for departmentKey, tag in pairs(configuredMap) do
		normalizedMap[normalizeDepartmentValue(departmentKey)] = tag
	end

	local candidates = {}
	if department then
		if department.id ~= nil then table.insert(candidates, department.id) end
		if department.shortName ~= nil then table.insert(candidates, department.shortName) end
		if department.short_name ~= nil then table.insert(candidates, department.short_name) end
		if department.name ~= nil then table.insert(candidates, department.name) end
	end

	for _, candidate in ipairs(candidates) do
		local normalized = normalizeDepartmentValue(candidate)
		if normalized and normalizedMap[normalized] then
			return normalizedMap[normalized], candidate
		end
	end

	-- Common-name fallback. Exact DepartmentMap entries still take priority.
	for _, candidate in ipairs(candidates) do
		local normalized = normalizeDepartmentValue(candidate) or ''
		if normalized:find('fire', 1, true) or normalized:find('rescue', 1, true) then
			return '👨‍🚒 Fire', candidate
		elseif normalized:find('ems', 1, true) or normalized:find('medical', 1, true) or normalized:find('ambulance', 1, true) then
			return '🚑 EMS', candidate
		elseif normalized:find('sheriff', 1, true) or normalized:find('bcso', 1, true) then
			return '👮 BCSO', candidate
		elseif normalized:find('statepolice', 1, true) or normalized:find('highwaypatrol', 1, true)
			or normalized:find('sasp', 1, true) or normalized:find('sahp', 1, true) then
			return '👮 SASP', candidate
		elseif normalized:find('police', 1, true) or normalized:find('lspd', 1, true) then
			return '👮 LSPD', candidate
		end
	end

	return nil, nil
end

local function dutyMinutes(src)
	return math.floor((tonumber(timeTracker[src]) or 0) / 60)
end

local function sendDutyWebhook(src, isOnDuty, tag)
	local roleData = tag and roleList[tag]
	local webhook = roleData and roleData[3]
	local playerName = GetPlayerName(src) or ('Player ' .. tostring(src))
	if webhook == nil then return end

	if isOnDuty then
		sendToDisc(
			'Player ' .. playerName .. ' is now on duty',
			'Player ' .. playerName .. ' has gone on duty as ' .. tag,
			'',
			webhook,
			65280
		)
	else
		sendToDisc(
			'Player ' .. playerName .. ' is now off duty',
			'Player ' .. playerName .. ' has gone off duty as ' .. tag,
			'Duration: ' .. dutyMinutes(src) .. ' minutes',
			webhook,
			16711680
		)
	end
end

local function setDutyFromCAD(src, shouldBeOnDuty, department)
	src = tonumber(src)
	local syncConfig = Config.LonexCADSync or {}
	if syncConfig.Enabled ~= true then
		return false, 'sync_disabled'
	end
	if not src or GetPlayerName(src) == nil then
		return false, 'player_not_online'
	end

	if shouldBeOnDuty then
		local tag, matchedValue = resolveLonexCADTag(department or {})
		if tag == nil then
			local message = ('No PoliceEMSActivity mapping exists for CAD department id=%s short=%s name=%s')
				:format(
					tostring(department and department.id),
					tostring(department and (department.shortName or department.short_name)),
					tostring(department and department.name)
				)
			print('[PoliceEMSActivity] ' .. message)
			if syncConfig.NotifyPlayer then
				sendMsg(src, '^1CAD duty sync failed: department is not mapped in config.lua.')
			end
			return false, 'department_not_mapped'
		end

		if roleList[tag] == nil then
			print(('[PoliceEMSActivity] CAD mapping points to missing RoleList tag: %s'):format(tag))
			return false, 'mapped_tag_missing'
		end

		if syncConfig.RequirePoliceEMSActivityPermission ~= false and not playerHasTagPermission(src, tag) then
			print(('[PoliceEMSActivity] Player %s lacks permission for CAD-mapped tag %s.'):format(src, tag))
			if syncConfig.NotifyPlayer then
				sendMsg(src, '^1CAD duty sync denied: you do not have the Discord role for ' .. tag .. '.')
			end
			return false, 'missing_tag_permission'
		end

		local wasOnDuty = onDuty[src] ~= nil
		local previousTag = activeBlip[src]

		-- Reconciliation may report the same duty state repeatedly. Keep this
		-- idempotent so polling does not recreate blips, resend webhooks, or
		-- spam the player every few seconds.
		if wasOnDuty and previousTag == tag then
			setDutyRosterEntry(src, tag, 'lonexcad_reconcile')
			return true, tag
		end

		if wasOnDuty and previousTag and previousTag ~= tag then
			sendDutyWebhook(src, false, previousTag)
			timeTracker[src] = 0
		end

		activeBlip[src] = tag
		onDuty[src] = true
		setDutyRosterEntry(src, tag, 'lonexcad')
		if not wasOnDuty then
			timeTracker[src] = 0
			sendDutyWebhook(src, true, tag)
			if syncConfig.ManageWeapons ~= false then
				TriggerClientEvent('PoliceEMSActivity:GiveWeapons', src)
			end
		elseif previousTag ~= tag then
			sendDutyWebhook(src, true, tag)
		end

		local roleData = roleList[tag]
		TriggerEvent('eblips:remove', src)
		TriggerEvent('eblips:add', {
			name = tag .. ' | ' .. (GetPlayerName(src) or tostring(src)),
			src = src,
			color = roleData[2]
		})
		broadcastDutyStats()

		if syncConfig.NotifyPlayer then
			sendMsg(src, 'CAD synced your emergency blip ^2ON ^3with Blip-Tag: ' .. tag)
		end
		if syncConfig.Debug then
			print(('[PoliceEMSActivity] CAD duty ON: player=%s tag=%s matched=%s'):format(src, tag, tostring(matchedValue)))
		end
		return true, tag
	end

	local tag = activeBlip[src]
	if onDuty[src] ~= nil then
		sendDutyWebhook(src, false, tag)
		if syncConfig.ManageWeapons ~= false then
			TriggerClientEvent('PoliceEMSActivity:TakeWeapons', src)
		end
	end

	onDuty[src] = nil
	timeTracker[src] = nil
	removeDutyRosterEntry(src)
	TriggerEvent('eblips:remove', src)
	broadcastDutyStats()

	if syncConfig.NotifyPlayer then
		sendMsg(src, 'CAD synced your emergency blip ^1OFF')
	end
	if syncConfig.Debug then
		print(('[PoliceEMSActivity] CAD duty OFF: player=%s'):format(src))
	end
	return true
end

exports('SetDutyFromCAD', function(src, shouldBeOnDuty, department)
	return setDutyFromCAD(src, shouldBeOnDuty == true, department or {})
end)

exports('GetDutyState', function(src)
	src = tonumber(src)
	return {
		onDuty = src ~= nil and onDuty[src] ~= nil or false,
		tag = src ~= nil and activeBlip[src] or nil,
		inRoster = src ~= nil and dutyRoster[src] ~= nil or false
	}
end)

RegisterCommand('bduty', function(source, args, rawCommand)
	-- Manual duty remains Discord-role restricted, with an on-demand lookup.
	local manualPerms = select(1, ensureUserPermissions(source, false))
	if #manualPerms > 0 then 
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
			setDutyRosterEntry(source, tag, 'bduty');
			broadcastDutyStats();
			timeTracker[source] = 0;
			TriggerClientEvent('PoliceEMSActivity:GiveWeapons', source);
		else 
			onDuty[source] = nil;
			removeDutyRosterEntry(source);
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
local function getDutyCategory(tag)
	local normalizedTag = normalizeDepartmentValue(tag) or ''

	-- Prefer explicit Fire/EMS wording before the general LEO fallback.
	if normalizedTag:find('fire', 1, true) or normalizedTag:find('rescue', 1, true) then
		return 'FIRE'
	elseif normalizedTag:find('ems', 1, true)
		or normalizedTag:find('medical', 1, true)
		or normalizedTag:find('ambulance', 1, true) then
		return 'EMS'
	elseif normalizedTag:find('police', 1, true)
		or normalizedTag:find('sheriff', 1, true)
		or normalizedTag:find('highwaypatrol', 1, true)
		or normalizedTag:find('statepolice', 1, true)
		or normalizedTag:find('trooper', 1, true)
		or normalizedTag:find('leo', 1, true)
		or normalizedTag:find('lspd', 1, true)
		or normalizedTag:find('bcso', 1, true)
		or normalizedTag:find('sasp', 1, true)
		or normalizedTag:find('sahp', 1, true) then
		return 'LEO'
	end

	-- Any configured emergency role not identified as Fire/EMS is treated as LEO.
	-- This keeps newly-added police departments counted without changing /cops again.
	if tag ~= nil and roleList[tag] ~= nil then
		return 'LEO'
	end

	return nil
end

local function showOnDutyRoster(source)
	local entries = getDutyRosterSnapshot()
	local counts = {
		LEO = 0,
		FIRE = 0,
		EMS = 0
	}

	for _, entry in ipairs(entries) do
		local category = getDutyCategory(entry.tag)
		if category ~= nil then
			counts[category] = counts[category] + 1
		end
	end

	sendMsg(source, '^3Currently on duty:')
	sendMsg(source, ('^4LEO: ^2%s'):format(counts.LEO))
	sendMsg(source, ('^1FIRE: ^2%s'):format(counts.FIRE))
	sendMsg(source, ('^3EMS: ^2%s'):format(counts.EMS))
end

RegisterCommand('cops', function(source, args, rawCommand)
	showOnDutyRoster(source)
end)

-- Useful if another resource on the server also registers /cops.
RegisterCommand('peacops', function(source, args, rawCommand)
	showOnDutyRoster(source)
end)


RegisterCommand('peadutydebug', function(source)
	local localDutyCount = 0
	local rosterCount = 0
	for _ in pairs(onDuty) do localDutyCount = localDutyCount + 1 end
	for _ in pairs(dutyRoster) do rosterCount = rosterCount + 1 end
	local cadRoster, cadError = getLonexCADRoster()
	local cadCount = 0
	if cadRoster then
		for _ in pairs(cadRoster) do cadCount = cadCount + 1 end
	end
	local message = ('PEA duty debug: local=%s roster=%s lonexcad=%s resource=%s')
		:format(localDutyCount, rosterCount, cadCount, tostring((Config.LonexCADSync or {}).CADResourceName or 'lonexcad'))
	if cadError then message = message .. ' error=' .. tostring(cadError) end
	if source == 0 then
		print('[PoliceEMSActivity] ' .. message)
	else
		sendMsg(source, message)
	end
end)

function sendMsg(src, msg) 
	TriggerClientEvent('chatMessage', src, prefix .. msg);
end
RegisterCommand('bliptag', function(source, args, rawCommand)
	-- Manual tag selection loads Discord roles only when requested.
	local manualPerms = select(1, ensureUserPermissions(source, false))
	if #manualPerms > 0 then 
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
					if onDuty[source] ~= nil then
						setDutyRosterEntry(source, activeBlip[source], 'bliptag')
					end
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


-- Compatibility event retained for older clients. It deliberately does not
-- call Discord, preventing a burst of role requests after a resource restart.
RegisterNetEvent('PoliceEMSActivity:RegisterUser')
AddEventHandler('PoliceEMSActivity:RegisterUser', function()
	broadcastDutyStats()
end)

RegisterCommand('pearefreshperms', function(source)
	if source == 0 then
		print('[PoliceEMSActivity] /pearefreshperms must be run in game.')
		return
	end
	local perms, reason = ensureUserPermissions(source, true)
	if #perms > 0 then
		sendMsg(source, ('Loaded ^2%s^3 Police/Fire/EMS permission(s).'):format(#perms))
	else
		sendMsg(source, '^1Could not load Discord roles: ' .. tostring(reason or 'no matching roles'))
	end
end)
