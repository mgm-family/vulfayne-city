-- server/main.lua
-- Oopart: the target grants a raw, unidentified relic item
-- (Zukan.RawItem, metadata-tagged with which specific piece it is).
-- Handing it to the collector NPC is what actually registers it in the
-- album and removes the item. Held raw items are wiped on every server
-- restart (via a resource-scoped KVP boot marker) so their targets
-- become collectible again -- see sweepRawItemsIfNewBoot(). Persists
-- registered progress per citizenid via oxmysql; run sql/install.sql once.

local QBCore = exports['qb-core']:GetCoreObject()

local PICKUP_MAX_DISTANCE = 15.0
local TALK_MAX_DISTANCE = 15.0

-- Regenerated every time this resource starts. Used to detect "have I
-- swept this player's held-but-unregistered relics since the last
-- restart" without needing any new SQL table.
local BootId = ('%d_%d'):format(os.time(), math.random(1, 999999))

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
	local row = MySQL.single.await('SELECT owned, claimed FROM vay_zukan_oopart WHERE citizenid = ?', { citizenid })
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
		[[INSERT INTO vay_zukan_oopart (citizenid, owned, claimed) VALUES (?, ?, ?)
		  ON DUPLICATE KEY UPDATE owned = VALUES(owned), claimed = VALUES(claimed)]],
		{ cache.citizenid, json.encode(cache.Owned), json.encode(cache.Claimed) }
	)
end

-- Wipes any held-but-unregistered relics the first time this citizenid is
-- seen after a resource restart, so their targets reappear as collectible.
-- Normal reconnects within the same server uptime are left untouched.
local function sweepRawItemsIfNewBoot(src, citizenid)
	local kvpKey = 'boot_' .. citizenid
	if GetResourceKvpString(kvpKey) == BootId then
		return
	end
	local slots = exports.ox_inventory:Search(src, 'slots', Zukan.RawItem)
	for _, slot in ipairs(slots or {}) do
		exports.ox_inventory:RemoveItem(src, Zukan.RawItem, slot.count, slot.metadata, slot.slot)
	end
	SetResourceKvp(kvpKey, BootId)
end

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
	local src, citizenid = Player.PlayerData.source, Player.PlayerData.citizenid
	loadPlayer(src, citizenid)
	sweepRawItemsIfNewBoot(src, citizenid)
end)

AddEventHandler('playerDropped', function()
	PlayerCache[source] = nil
end)

lib.callback.register('vay_zukan_oopart:getSync', function(src)
	local cache = PlayerCache[src]
	if not cache then
		return { Owned = {}, Claimed = {} }
	end
	return { Owned = cache.Owned, Claimed = cache.Claimed }
end)

--------------------------------------------------------------------------
-- pickup (grants the raw relic item, does NOT register by itself)
--------------------------------------------------------------------------

RegisterNetEvent('vay_zukan_oopart:pickup', function(itemId)
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

	-- don't hand out a second copy of the same piece while one is still held
	for _, slot in ipairs(exports.ox_inventory:Search(src, 'slots', Zukan.RawItem) or {}) do
		if slot.metadata and slot.metadata.itemId == itemId then
			return
		end
	end

	local added = exports.ox_inventory:AddItem(src, Zukan.RawItem, 1, {
		itemId = item.Id,
		label = item.Name .. '（未鑑定）',
		description = item.Description,
	})

	if added then
		TriggerClientEvent('vay_zukan_oopart:itemPickedUp', src, { ItemId = item.Id, Name = item.Name })
	end
end)

--------------------------------------------------------------------------
-- NPC: registers every held relic, then grants any newly-completed
-- sheet's reward, in the same interaction.
--------------------------------------------------------------------------

RegisterNetEvent('vay_zukan_oopart:talk', function()
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

	-- 1) register every held relic
	local registered = {}
	for _, slot in ipairs(exports.ox_inventory:Search(src, 'slots', Zukan.RawItem) or {}) do
		local itemId = slot.metadata and slot.metadata.itemId
		local item = itemId and Zukan.ItemsById[itemId]
		if item and not cache.Owned[itemId] then
			cache.Owned[itemId] = true
			registered[#registered + 1] = { ItemId = item.Id, SheetIndex = item.SheetIndex, Name = item.Name }
			exports.ox_inventory:RemoveItem(src, Zukan.RawItem, 1, slot.metadata, slot.slot)
		end
	end

	-- 2) grant any sheet that just became complete
	local granted = {}
	for sheetIndex, sheet in ipairs(Zukan.Sheets) do
		if not cache.Claimed[sheetIndex] and isSheetComplete(cache.Owned, sheetIndex) then
			cache.Claimed[sheetIndex] = true
			local reward = sheet.Reward
			if reward.Kind == 'Money' then
				Player.Functions.AddMoney(reward.Account or 'bank', reward.Amount, 'vay-zukan-oopart-reward')
			end
			granted[#granted + 1] = { SheetIndex = sheetIndex, SheetName = sheet.Name, Reward = reward }
		end
	end

	if #registered > 0 or #granted > 0 then
		savePlayer(src)
	end

	TriggerClientEvent('vay_zukan_oopart:turnedIn', src, { Registered = registered, Granted = granted })
end)
