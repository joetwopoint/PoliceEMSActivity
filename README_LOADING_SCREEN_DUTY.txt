This PoliceEMSActivity copy is patched to expose live on-duty counts for the loading screen.

Endpoint format:
  http://YOUR_SERVER_IP:30120/PoliceEMSActivity/policeemsactivity-duty.json

The "PoliceEMSActivity" part must match the actual resource folder name.

Restart order:
  ensure Badger_Discord_API
  ensure PoliceEMSActivity
  ensure twopoint-loadingscreen

The loading screen polls this endpoint every 5 minutes.


Discord / email-system total endpoint:
  http://YOUR_SERVER_IP:30120/PoliceEMSActivity/discord-member-count.json

This endpoint is used by the loading screen for the grand total Discord member count. It does not use widget presence_count, so it should not show only online users.

Recommended server.cfg option:
  set discord_bot_token "YOUR_DISCORD_BOT_TOKEN"

Alternative without a bot token: set LOADING_SCREEN_DISCORD_INVITE_CODE in PoliceEMSActivity/config.lua. If you leave both the bot token and invite code blank, the script tries public fallbacks, but private/non-discoverable Discords may still show `--`.

Discord count refresh interval:
  LOADING_SCREEN_DISCORD_REFRESH_SECONDS = 300


If you need a temporary displayed number while setting up Discord API access, set `LOADING_SCREEN_DISCORD_MEMBER_COUNT_OVERRIDE = 1234` in `PoliceEMSActivity/config.lua`, then restart `PoliceEMSActivity`. Leave it as `nil` for automatic tracking.
