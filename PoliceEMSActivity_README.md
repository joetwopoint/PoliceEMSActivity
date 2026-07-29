# PoliceEMSActivity

[![FiveM](https://img.shields.io/badge/FiveM-Cerulean-orange.svg)](https://fivem.net/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A FiveM emergency-services duty and blip resource for law enforcement, fire, and EMS personnel. It supports Discord role permissions, shared emergency blips, manual duty commands, optional LonexCAD synchronization, duty webhooks, and category-based on-duty totals.

## Latest Changes

The `/cops` command has been updated to show only the number of personnel on duty in each emergency-service category:

```text
Currently on duty:
LEO: 6
FIRE: 3
EMS: 2
```

The command no longer displays:

- Individual player names
- Player server IDs
- Separate law-enforcement department rosters
- A line for every person currently on duty

Law-enforcement departments such as LSPD, BCSO, SASP, SAHP, sheriff, police, highway patrol, and state police are combined under **LEO**. Fire and rescue departments are counted under **FIRE**, while EMS, medical, and ambulance departments are counted under **EMS**.

The same category-count output is available through `/peacops`, which can be used when another resource already registers `/cops`.

## Features

- Discord role-based access for manual duty commands
- On-duty and off-duty emergency blip toggling
- Shared live map blips for active emergency personnel
- Configurable department tags, Discord roles, blip colors, and webhooks
- Optional LonexCAD duty and department synchronization
- Combined LEO, FIRE, and EMS counts through `/cops`
- Duplicate-safe roster merging between manual duty and CAD duty data
- Automatic cleanup when a player disconnects
- Permission caching and retry cooldowns
- JSON duty-status endpoints for loading screens or other resources
- Debug and permission-refresh commands

## Requirements

- A working FiveM server using the Cerulean resource format
- [`Badger_Discord_API`](https://github.com/JaredScar/Badger_Discord_API) for Discord role checks used by manual commands
- `lonexcad` only when LonexCAD synchronization is enabled

The emergency blip client and server scripts are included with this resource.

## Installation

1. Place the `PoliceEMSActivity` folder inside your server's resources directory.
2. Configure the Discord roles and departments in `config.lua`.
3. Configure LonexCAD synchronization or disable it when it is not used.
4. Add the required resources to `server.cfg` in the correct order.

```cfg
ensure Badger_Discord_API
ensure lonexcad
ensure PoliceEMSActivity
```

When LonexCAD is not used, disable it in `config.lua` and remove its `ensure` line:

```lua
LonexCADSync = {
    Enabled = false,
}
```

## Configuration

### Department Roles

Each entry in `Config.RoleList` uses the following structure:

```lua
['Department Tag'] = {
    DiscordRoleId,
    BlipColor,
    WebhookUrl
}
```

Example:

```lua
Config = {
    RoleList = {
        ['👮 LSPD'] = {123456789012345678, 57, nil},
        ['👮 BCSO'] = {123456789012345678, 52, nil},
        ['👮 SASP'] = {123456789012345678, 54, nil},
        ['👨‍🚒 Fire'] = {123456789012345678, 1, nil},
        ['🚑 EMS'] = {123456789012345678, 63, nil},
    }
}
```

Set the third value to `nil` when duty webhooks are not required.

### Discord Permission Cache

```lua
DiscordPermissions = {
    RetryCooldownSeconds = 60,
}
```

Manual Discord-role requests are cached and rate-limited to reduce unnecessary requests and handle temporary Discord or API rate limits.

### LonexCAD Synchronization

```lua
LonexCADSync = {
    Enabled = true,
    CADResourceName = 'lonexcad',
    UseCADRosterFallback = true,
    RequirePoliceEMSActivityPermission = false,
    NotifyPlayer = true,
    ManageWeapons = true,
    Debug = false,
}
```

| Setting | Description |
| --- | --- |
| `Enabled` | Enables or disables CAD duty synchronization. |
| `CADResourceName` | Resource name used to access the CAD exports. |
| `UseCADRosterFallback` | Allows `/cops` to merge the CAD roster with the local duty roster. |
| `RequirePoliceEMSActivityPermission` | Requires the mapped PoliceEMSActivity Discord role before accepting CAD duty. |
| `NotifyPlayer` | Sends duty-sync status messages to the player. |
| `ManageWeapons` | Runs the configured weapon and armor handlers when duty changes. |
| `Debug` | Prints CAD synchronization and roster information to the server console. |

### CAD Department Mapping

`DepartmentMap` connects LonexCAD department IDs, short names, or full names to a configured PoliceEMSActivity tag.

```lua
DepartmentMap = {
    ['LSPD'] = '👮 LSPD',
    ['Los Santos Police Department'] = '👮 LSPD',
    ['BCSO'] = '👮 BCSO',
    ['SASP'] = '👮 SASP',
    ['FIRE'] = '👨‍🚒 Fire',
    ['EMS'] = '🚑 EMS',
}
```

Add the numeric CAD department ID as a string when a department cannot be identified by its name or short name.

### Blip Update Interval

```lua
CLIENT_UPDATE_INTERVAL_SECONDS = 3
```

This controls how frequently active emergency-personnel coordinates are sent to clients.

## Commands

| Command | Description |
| --- | --- |
| `/bduty` | Toggles manual emergency duty on or off. Access is based on configured Discord roles. |
| `/bliptag` | Lists the blip tags available to the player. |
| `/bliptag <number>` | Selects one of the player's permitted blip tags. |
| `/cops` | Shows the total number on duty under LEO, FIRE, and EMS. |
| `/peacops` | Alias for `/cops` when another resource uses the same command name. |
| `/pearefreshperms` | Forces a fresh Discord permission lookup for the player. |
| `/peadutydebug` | Shows local, merged-roster, and LonexCAD roster counts for troubleshooting. |

## Category Counting

The `/cops` and `/peacops` commands build a deduplicated roster from:

1. PoliceEMSActivity's dedicated duty roster
2. The legacy local `onDuty` table
3. LonexCAD's on-duty officer roster when the fallback is enabled

Each online player is counted once, even when the player appears in both local and CAD duty data.

The category is determined from the mapped department tag:

- **FIRE:** tags containing fire or rescue terms
- **EMS:** tags containing EMS, medical, or ambulance terms
- **LEO:** tags containing police, sheriff, highway patrol, state police, trooper, LSPD, BCSO, SASP, SAHP, or LEO terms

Any configured emergency role that does not match FIRE or EMS is treated as LEO. This allows newly added law-enforcement departments to be counted without editing the command logic.

## LonexCAD Exports

### Set Duty from CAD

```lua
local success, result = exports['PoliceEMSActivity']:SetDutyFromCAD(
    source,
    true,
    {
        id = '1',
        shortName = 'LSPD',
        name = 'Los Santos Police Department'
    }
)
```

Set the second argument to `false` to take the player off duty.

### Get Duty State

```lua
local dutyState = exports['PoliceEMSActivity']:GetDutyState(source)

print(dutyState.onDuty)
print(dutyState.tag)
print(dutyState.inRoster)
```

## Duty JSON Endpoints

The resource provides the same duty data through the following paths on the FiveM HTTP server:

```text
/policeemsactivity-duty.json
/PoliceEMSActivity/duty.json
/PoliceEMSActivity/policeemsactivity-duty.json
/duty.json
```

Example response:

```json
{
  "type": "dutyStats",
  "source": "PoliceEMSActivity",
  "updatedAt": 1770000000,
  "departments": [
    {
      "label": "👮 LSPD",
      "count": 3,
      "names": ["Example Player"]
    }
  ]
}
```

These endpoints retain department-level data for compatible loading screens and integrations. The simplified LEO, FIRE, and EMS totals apply specifically to the `/cops` and `/peacops` chat commands.

## Troubleshooting

### `/cops` shows zero for every category

- Confirm players are actually on duty.
- Confirm LonexCAD is started when CAD roster fallback is enabled.
- Confirm each CAD department maps to a valid `Config.RoleList` tag.
- Run `/peadutydebug` and review the local, roster, and CAD counts.
- Enable `LonexCADSync.Debug` temporarily for additional server-console details.

### Manual duty commands deny access

- Confirm `Badger_Discord_API` is started before PoliceEMSActivity.
- Confirm the player has a Discord identifier connected to FiveM.
- Confirm the Discord role IDs in `Config.RoleList` are correct.
- Run `/pearefreshperms` after changing Discord roles.

### Duplicate personnel

The category-count command deduplicates players by server ID. Confirm any custom duty integration passes the correct player source when adding or synchronizing duty records.

## Resource Structure

```text
PoliceEMSActivity/
├── EmergencyBlips/
│   ├── cl_emergencyblips.lua
│   └── sv_emergencyblips.lua
├── client.lua
├── config.lua
├── fxmanifest.lua
├── server.lua
├── LICENSE
└── README.md
```

## License

This project is distributed under the MIT License. See [LICENSE](LICENSE) for the full license text.

## Credits

- Original PoliceEMSActivity resource by JaredScar
- Emergency blip system by minipunch
