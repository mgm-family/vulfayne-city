-- server/main.lua
-- Persists each player's collectible progress (oxmysql, keyed by
-- citizenid), grants an item on pickup, and hands out a sheet's reward
-- when the matching NPC is talked to. Run sql/install.sql once before
-- starting this resource.

local QBCore = exports['qb-core']:GetCoreObject()

local PICKUP_MAX_DISTANCE = 15.0
local TALK_MAX_DISTANCE = 15.0

local ItemsById = {} -- [categoryId][itemId] = item
for categoryId, catData in pairs(VulfayneCollectibles.Categories) do
	local lookup = {}
	for _, sheet in ipairs(catData.Sheets) do
		for _, item in ipairs(sheet.Items) do
			lookup[item.Id] = item
		end
	end
	ItemsById[categoryId] = lookup
end

local PlayerCache = {} -- [source] = { citizenid = string, data = { [categoryId] = { Owned = {}, Claimed = {} } } }

local function emptyPlayerData()
	local data = {}
	for categoryId in pairs(VulfayneCollectibles.Categories) do
		data[categoryId] = { Owned = {}, Claimed = {} }
	end
	return data
end

local function isSheetComplete(categoryId, ownedSet, sheetIndex)
	local sheet = VulfayneCollectibles.Categories[categoryId].Sheets[sheetIndex]
	for _, item in ipairs(sheet.Items) do
		if not ownedSet[item.Id] then
			return false
		end
	end
	return true
end

local function loadPlayer(src, citizenid)
	local rows = MySQL.query.await('SELECT category, owned, claimed FROM vulfayne_collectibles WHERE citizenid = ?', { citizenid })
	local data = emptyPlayerData()
	for _, row in ipairs(rows or {}) do
		if data[row.category] then
			data[row.category].Owned = json.decode(row.owned) or {}
			data[row.category].Claimed = json.decode(row.claimed) or {}
		end
	end
	PlayerCache[src] = { citizenid = citizenid, data = data }
end

local function saveCategory(src, categoryId)
	local cache = PlayerCache[src]
	if not cache then
		return
	end
	local cat = cache.data[categoryId]
	MySQL.update(
		[[INSERT INTO vulfayne_collectibles (citizenid, category, owned, claimed) VALUES (?, ?, ?, ?)
		  ON DUPLICATE KEY UPDATE owned = VALUES(owned), claimed = VALUES(claimed)]],
		{ cache.citizenid, categoryId, json.encode(cat.Owned), json.encode(cat.Claimed) }
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

lib.callback.register('vulfayne_collect:getSync', function(src)
	local cache = PlayerCache[src]
	if not cache then
		return emptyPlayerData()
	end
	return cache.data
end)

--------------------------------------------------------------------------
-- pickup
--------------------------------------------------------------------------

RegisterNetEvent('vulfayne_collect:pickup', function(categoryId, itemId)
	local src = source
	local cache = PlayerCache[src]
	local item = ItemsById[categoryId] and ItemsById[categoryId][itemId]
	if not cache or not item then
		return
	end

	local cat = cache.data[categoryId]
	if cat.Owned[itemId] then
		return
	end

	local ped = GetPlayerPed(src)
	local dist = #(GetEntityCoords(ped) - item.Coords)
	if dist > PICKUP_MAX_DISTANCE then
		return
	end

	cat.Owned[itemId] = true
	saveCategory(src, categoryId)

	TriggerClientEvent('vulfayne_collect:itemCollected', src, {
		CategoryId = categoryId,
		ItemId = item.Id,
		SheetIndex = item.SheetIndex,
		Name = item.Name,
	})

	if not cat.Claimed[item.SheetIndex] and isSheetComplete(categoryId, cat.Owned, item.SheetIndex) then
		local sheet = VulfayneCollectibles.Categories[categoryId].Sheets[item.SheetIndex]
		TriggerClientEvent('vulfayne_collect:sheetCompleted', src, {
			CategoryId = categoryId,
			SheetIndex = item.SheetIndex,
			SheetName = sheet.Name,
		})
	end
end)

--------------------------------------------------------------------------
-- NPC reward
--------------------------------------------------------------------------

RegisterNetEvent('vulfayne_collect:talk', function(categoryId)
	local src = source
	local cache = PlayerCache[src]
	local data = VulfayneCollectibles.Categories[categoryId]
	if not cache or not data then
		return
	end

	local Player = QBCore.Functions.GetPlayer(src)
	if not Player then
		return
	end

	local ped = GetPlayerPed(src)
	local npcCoords = vector3(data.Npc.Coords.x, data.Npc.Coords.y, data.Npc.Coords.z)
	if #(GetEntityCoords(ped) - npcCoords) > TALK_MAX_DISTANCE then
		return
	end

	local cat = cache.data[categoryId]
	local granted = {}

	for sheetIndex, sheet in ipairs(data.Sheets) do
		if not cat.Claimed[sheetIndex] and isSheetComplete(categoryId, cat.Owned, sheetIndex) then
			cat.Claimed[sheetIndex] = true
			local reward = sheet.Reward
			if reward.Kind == 'Money' then
				Player.Functions.AddMoney(reward.Account or 'bank', reward.Amount, 'vulfayne-collectible-reward')
			end
			granted[#granted + 1] = { SheetIndex = sheetIndex, SheetName = sheet.Name, Reward = reward }
		end
	end

	if #granted > 0 then
		saveCategory(src, categoryId)
	end

	TriggerClientEvent('vulfayne_collect:rewardGranted', src, { CategoryId = categoryId, Granted = granted })
end)
