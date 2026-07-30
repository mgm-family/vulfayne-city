-- server/main.lua
-- Seal is the simple case: the target itself registers the item directly
-- (no held item, no hand-in). The NPC here only grants a sheet's reward.
-- Persists per citizenid via oxmysql. Run sql/install.sql once first.

local QBCore = exports['qb-core']:GetCoreObject()

local PICKUP_MAX_DISTANCE = 15.0
local TALK_MAX_DISTANCE = 15.0

local PlayerCache = {} -- [source] = { citizenid = string, Owned = {}, Claimed = {} }

local function isSheetComplete(ownedSet, sheetIndex)
	local sheet = Zukan.Sheets[sheetIndex]
	for _, item in ipairs(sheet.Items) do
		if not ownedSet[item.Id] then
			return false
		end
	end
	return true
end

local function loadPlayer(src, citizenid)
	local row = MySQL.single.await('SELECT owned, claimed FROM vay_zukan_seal WHERE citizenid = ?', { citizenid })
	PlayerCache[src] = {
		citizenid = citizenid,
		Owned = (row and json.decode(row.owned)) or {},
		Claimed = (row and json.decode(row.claimed)) or {},
	}
end

local function savePlayer(src)
	local cache = PlayerCache[src]
	if not cache then
		return
	end
	MySQL.update(
		[[INSERT INTO vay_zukan_seal (citizenid, owned, claimed) VALUES (?, ?, ?)
		  ON DUPLICATE KEY UPDATE owned = VALUES(owned), claimed = VALUES(claimed)]],
		{ cache.citizenid, json.encode(cache.Owned), json.encode(cache.Claimed) }
	)
end

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
	loadPlayer(Player.PlayerData.source, Player.PlayerData.citizenid)
end)

AddEventHandler('playerDropped', function()
	PlayerCache[source] = nil
end)

lib.callback.register('vay_zukan_seal:getSync', function(src)
	local cache = PlayerCache[src]
	if not cache then
		return { Owned = {}, Claimed = {} }
	end
	return { Owned = cache.Owned, Claimed = cache.Claimed }
end)

--------------------------------------------------------------------------
-- pickup (direct registration -- no item involved)
--------------------------------------------------------------------------

RegisterNetEvent('vay_zukan_seal:pickup', function(itemId)
	local src = source
	local cache = PlayerCache[src]
	local item = Zukan.ItemsById[itemId]
	if not cache or not item or cache.Owned[itemId] then
		return
	end

	local ped = GetPlayerPed(src)
	if #(GetEntityCoords(ped) - item.Coords) > PICKUP_MAX_DISTANCE then
		return
	end

	cache.Owned[itemId] = true
	savePlayer(src)

	TriggerClientEvent('vay_zukan_seal:itemCollected', src, {
		ItemId = item.Id,
		SheetIndex = item.SheetIndex,
		Name = item.Name,
	})

	if not cache.Claimed[item.SheetIndex] and isSheetComplete(cache.Owned, item.SheetIndex) then
		TriggerClientEvent('vay_zukan_seal:sheetCompleted', src, {
			SheetIndex = item.SheetIndex,
			SheetName = Zukan.Sheets[item.SheetIndex].Name,
		})
	end
end)

--------------------------------------------------------------------------
-- NPC reward
--------------------------------------------------------------------------

RegisterNetEvent('vay_zukan_seal:talk', function()
	local src = source
	local cache = PlayerCache[src]
	if not cache then
		return
	end

	local Player = QBCore.Functions.GetPlayer(src)
	if not Player then
		return
	end

	local ped = GetPlayerPed(src)
	local npcCoords = vector3(Zukan.Npc.Coords.x, Zukan.Npc.Coords.y, Zukan.Npc.Coords.z)
	if #(GetEntityCoords(ped) - npcCoords) > TALK_MAX_DISTANCE then
		return
	end

	local granted = {}
	for sheetIndex, sheet in ipairs(Zukan.Sheets) do
		if not cache.Claimed[sheetIndex] and isSheetComplete(cache.Owned, sheetIndex) then
			cache.Claimed[sheetIndex] = true
			local reward = sheet.Reward
			if reward.Kind == 'Money' then
				Player.Functions.AddMoney(reward.Account or 'bank', reward.Amount, 'vay-zukan-seal-reward')
			end
			granted[#granted + 1] = { SheetIndex = sheetIndex, SheetName = sheet.Name, Reward = reward }
		end
	end

	if #granted > 0 then
		savePlayer(src)
	end

	TriggerClientEvent('vay_zukan_seal:rewardGranted', src, { Granted = granted })
end)
