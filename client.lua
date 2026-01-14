AddEventHandler('playerSpawned', function() 
	-- The player has spawned, we gotta set their perms up
	TriggerServerEvent('PoliceEMSActivity:RegisterUser'); 
end)
function giveWeapon(hash)
    GiveWeaponToPed(GetPlayerPed(-1), GetHashKey(hash), 999, false, false)
end
RegisterNetEvent('PoliceEMSActivity:GiveWeapons')
AddEventHandler('PoliceEMSActivity:GiveWeapons', function()
end)
RegisterNetEvent('PoliceEMSActivity:TakeWeapons')
AddEventHandler('PoliceEMSActivity:TakeWeapons', function()
	-- Remove weapons and armor
	SetPedArmour(GetPlayerPed(-1), 0)
	RemoveAllPedWeapons(GetPlayerPed(-1), true);
end)
