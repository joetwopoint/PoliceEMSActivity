# PoliceEMSActivity
A simple EMS Activity Blip Fivem script that has some other features too
## Documentation
https://docs.badger.store/fivem-discord-scripts/policeemsactivity
## Integrations (exports / state bags)
This build exposes duty state so other standalone resources can check if a player is on duty.

### Server exports
- `exports['PoliceEMSActivity']:IsOnDuty(src)` -> boolean
- `exports['PoliceEMSActivity']:GetDutyTag(src)` -> string|nil (current blip tag)

### State bags (client + server)
When a player toggles duty, the server sets these synced state keys:
- `Player(src).state.pea_onDuty` -> true/false
- `Player(src).state.pea_blipTag` -> string|false

Client scripts can read:
- `LocalPlayer.state.pea_onDuty`
- `LocalPlayer.state.pea_blipTag`

### Event
- `PoliceEMSActivity:DutyChanged` (server event): (src, isOnDuty, blipTag)
