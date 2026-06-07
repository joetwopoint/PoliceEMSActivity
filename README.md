PoliceEMSActivity Loading Screen Duty Bridge

This patched PoliceEMSActivity resource exposes one loading-screen endpoint for live duty status only.

Duty endpoint:
  http://YOUR_SERVER_IP:30120/PoliceEMSActivity/policeemsactivity-duty.json

Example response when units are on duty:
  {
    "type": "dutyStats",
    "source": "PoliceEMSActivity",
    "updatedAt": 1730000000,
    "departments": [
      { "label": "👮 LSPD", "count": 2, "names": ["Player One", "Player Two"] }
    ]
  }

Notes:
- Discord invite/member-count logic is not handled by PoliceEMSActivity.
- Discord card/member totals are configured only in twopoint-loadingscreen/html/script.js.
- Duty status still uses PoliceEMSActivity's /bduty command and Config.RoleList role mapping.
- Start Badger_Discord_API before PoliceEMSActivity.
