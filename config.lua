Config = {
    RoleList = {
        ['👮 LSPD'] = {1183541910510518296, 57, nil},
        ['👮 BCSO'] = {1183541910405652580, 52, nil},
        ['👮 SASP'] = {1183541910615363646, 54, nil},
        ['👨‍🚒 Fire'] = {1183541910367912043, 1, nil},
        ['🚑 EMS'] = {1183541910367912041, 63, nil},
    },

    -- Manual command role lookups are cached and rate-limited locally.
    DiscordPermissions = {
        RetryCooldownSeconds = 60,
    },

    -- LonexCAD duty/blip synchronization.
    LonexCADSync = {
        Enabled = true,

        -- Resource folder/name used by the CAD roster fallback.
        CADResourceName = 'lonexcad',
        UseCADRosterFallback = true,

        -- CAD duty sync trusts the department already approved by LonexCAD.
        -- Keep this false so a temporary Badger_Discord_API rate limit cannot
        -- prevent the duty roster/blip from being populated. Manual /bduty and
        -- /bliptag commands still use PoliceEMSActivity's Discord permissions.
        RequirePoliceEMSActivityPermission = false,

        -- Match these values against the CAD department ID, short_name, or name.
        -- Add numeric department IDs here as strings if your CAD uses different names.
        DepartmentMap = {
            ['LSPD'] = '👮 LSPD',
            ['Los Santos Police Department'] = '👮 LSPD',

            ['BCSO'] = '👮 BCSO',
            ["Blaine County Sheriff's Office"] = '👮 BCSO',
            ['Blaine County Sheriff Office'] = '👮 BCSO',

            ['SASP'] = '👮 SASP',
            ['SAHP'] = '👮 SASP',
            ['San Andreas State Police'] = '👮 SASP',
            ['San Andreas Highway Patrol'] = '👮 SASP',

            ['FIRE'] = '👨‍🚒 Fire',
            ['LSFD'] = '👨‍🚒 Fire',
            ['SAFR'] = '👨‍🚒 Fire',
            ['Los Santos Fire Department'] = '👨‍🚒 Fire',
            ['San Andreas Fire Rescue'] = '👨‍🚒 Fire',

            ['EMS'] = '🚑 EMS',
            ['SAMS'] = '🚑 EMS',
            ['Emergency Medical Services'] = '🚑 EMS',
            ['San Andreas Medical Services'] = '🚑 EMS',
        },

        NotifyPlayer = true,
        ManageWeapons = true,
        Debug = true,
    },

    -- How frequently emergency blips update on the map.
    CLIENT_UPDATE_INTERVAL_SECONDS = 3,
}
