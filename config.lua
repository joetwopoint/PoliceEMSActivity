Config = {
    RoleList = { 
        ['👮 LSPD'] = {1183541910510518296, 57, nil},
        ['👮 BCSO'] = {1183541910405652580, 52, nil},
        ['👮 SASP'] = {1183541910615363646, 54, nil},
        ['👨‍🚒 Fire'] = {1183541910367912043, 1,  nil},
        ['🚑 EMS'] = {1183541910367912041, 63, nil},
    },
    -- Loading-screen Discord total member count.
    -- This drives "people in the email system". It is separate from the online/in-state FiveM count.
    LOADING_SCREEN_DISCORD_GUILD_ID = '1183541910091079823',

    -- Optional: put only the invite code here, not the full URL. Example: discord.gg/abc123 -> 'abc123'.
    -- If this is blank, the script will try the Discord widget invite, then public guild preview.
    -- For the most reliable grand total, use this invite code or the bot token convar below.
    LOADING_SCREEN_DISCORD_INVITE_CODE = '',

    -- Emergency/manual fallback. Leave nil for automatic tracking.
    -- Example only if needed: LOADING_SCREEN_DISCORD_MEMBER_COUNT_OVERRIDE = 1234,
    LOADING_SCREEN_DISCORD_MEMBER_COUNT_OVERRIDE = nil,

    -- Optional private/reliable path: set a convar in server.cfg instead of pasting your bot token here:
    -- set discord_bot_token "YOUR_BOT_TOKEN"
    -- The bot must be in the guild. If blank/unavailable, the script falls back to invite/widget counts.
    LOADING_SCREEN_DISCORD_BOT_TOKEN = '',
    LOADING_SCREEN_DISCORD_BOT_TOKEN_CONVAR = 'discord_bot_token',

    -- How often PoliceEMSActivity refreshes the Discord total count for the loading screen.
    LOADING_SCREEN_DISCORD_REFRESH_SECONDS = 300,

    CLIENT_UPDATE_INTERVAL_SECONDS = 3, -- How frequently should the blips on the map update??
}
