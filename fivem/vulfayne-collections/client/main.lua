-- client/main.lua
-- Registers ox_target pickup zones for every not-yet-owned item, draws a
-- glow marker when the player is nearby, spawns the three reward NPCs,
-- and drives the NUI album (open/close, pushes item data + progress).

local QBCore = exports['qb-core']:GetCoreObject()

local CATEGORY_ORDER = { 'Seal', 'Oopart', 'Antique' }
local CATEGORY_COLOR = {
	Seal = { 230, 200, 90 },    -- gold, matches the PD/seal palette on the site
	Oopart = { 150, 110, 220 }, -- violet, ties into the twin-moon lore
	Antique = { 190, 140, 80 }, -- aged brass/antique brown
}
local MARKER_DRAW_DISTANCE = 25.0

local State = {}     -- [categoryId] = { Owned = {[itemId]=true}, Claimed = {[sheetIndex]=true} }
local ItemsById = {} -- [categoryId][itemId] = item
local ActiveZones = {} -- [categoryId][itemId] = ox_target zone name (only present while pickable)
local NpcPeds = {}
local uiOpen = false
local initialized = false

for categoryId, catData in pairs(VulfayneCollectibles.Categories) do
	local lookup = {}
	for _, sheet in ipairs(catData.Sheets) do
		for _, item in ipairs(sheet.Items) do
			lookup[item.Id] = item
		end
	end
	ItemsById[categoryId] = lookup
end

--------------------------------------------------------------------------
-- NUI payload (built once: item Coords aren't needed client-UI-side and
-- vector3/vector4 values don't survive SendNUIMessage's JSON encoding well)
--------------------------------------------------------------------------

local SerializedCategories = {}
for _, categoryId in ipairs(CATEGORY_ORDER) do
	local catData = VulfayneCollectibles.Categories[categoryId]
	local sheets = {}
	for i, sheet in ipairs(catData.Sheets) do
		local items = {}
		for j, item in ipairs(sheet.Items) do
			items[j] = { Id = item.Id, Name = item.Name, Description = item.Description }
		end
		sheets[i] = {
			Name = sheet.Name,
			Reward = { DisplayName = sheet.Reward.DisplayName, Description = sheet.Reward.Description },
			Items = items,
		}
	end
	SerializedCategories[#SerializedCategories + 1] = {
		CategoryId = categoryId,
		CategoryName = catData.CategoryName,
		Sheets = sheets,
	}
end

--------------------------------------------------------------------------
-- pickup zones
--------------------------------------------------------------------------

local function isOwned(categoryId, itemId)
	local cat = State[categoryId]
	return cat ~= nil and cat.Owned[itemId] == true
end

local function registerItemZone(categoryId, catData, item)
	if isOwned(categoryId, item.Id) then
		return
	end
	local zoneName = ('vulfayne_%s_%s'):format(categoryId, item.Id)
	exports.ox_target:addSphereZone({
		coords = item.Coords,
		radius = 1.2,
		name = zoneName,
		debug = false,
		options = {
			{
				icon = 'fa-solid fa-hand',
				label = ('%s：%s を拾う'):format(catData.CategoryName, item.Name),
				onSelect = function()
					TriggerServerEvent('vulfayne_collect:pickup', categoryId, item.Id)
				end,
			},
		},
	})
	ActiveZones[categoryId] = ActiveZones[categoryId] or {}
	ActiveZones[categoryId][item.Id] = zoneName
end

local function removeItemZone(categoryId, itemId)
	local zones = ActiveZones[categoryId]
	local zoneName = zones and zones[itemId]
	if zoneName then
		exports.ox_target:removeZone(zoneName)
		zones[itemId] = nil
	end
end

local function registerAllZones()
	for _, categoryId in ipairs(CATEGORY_ORDER) do
		local catData = VulfayneCollectibles.Categories[categoryId]
		for _, sheet in ipairs(catData.Sheets) do
			for _, item in ipairs(sheet.Items) do
				registerItemZone(categoryId, catData, item)
			end
		end
	end
end

-- Glow marker for nearby uncollected items. Only draws within
-- MARKER_DRAW_DISTANCE, and only sleeps 0ms while something is actually
-- close, so this stays cheap with ~270 possible pickups loaded at once.
CreateThread(function()
	while true do
		local sleep = 500
		local ped = PlayerPedId()
		local coords = GetEntityCoords(ped)

		for categoryId, zones in pairs(ActiveZones) do
			local color = CATEGORY_COLOR[categoryId] or { 255, 255, 255 }
			local items = ItemsById[categoryId]
			for itemId in pairs(zones) do
				local item = items[itemId]
				local dist = #(coords - item.Coords)
				if dist < MARKER_DRAW_DISTANCE then
					sleep = 0
					DrawMarker(
						28, item.Coords.x, item.Coords.y, item.Coords.z - 0.9,
						0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.4,
						color[1], color[2], color[3], 160,
						true, false, 2, false, nil, nil, false
					)
				end
			end
		end

		Wait(sleep)
	end
end)

--------------------------------------------------------------------------
-- NPCs
--------------------------------------------------------------------------

local function spawnNpc(categoryId, catData)
	local npc = catData.Npc
	local model = GetHashKey(npc.Model)
	lib.requestModel(model)

	local ped = CreatePed(4, model, npc.Coords.x, npc.Coords.y, npc.Coords.z - 1.0, npc.Coords.w, false, true)
	SetEntityInvincible(ped, true)
	FreezeEntityPosition(ped, true)
	SetBlockingOfNonTemporaryEvents(ped, true)
	TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
	SetModelAsNoLongerNeeded(model)

	exports.ox_target:addLocalEntity(ped, {
		{
			icon = 'fa-solid fa-comment',
			label = catData.CategoryName .. 'コレクターに話す',
			onSelect = function()
				TriggerServerEvent('vulfayne_collect:talk', categoryId)
			end,
		},
	})

	NpcPeds[categoryId] = ped
end

--------------------------------------------------------------------------
-- NUI
--------------------------------------------------------------------------

local function pushState()
	if uiOpen then
		SendNUIMessage({ action = 'state', state = State })
	end
end

local function toggleUI()
	uiOpen = not uiOpen
	SetNuiFocus(uiOpen, uiOpen)
	if uiOpen then
		SendNUIMessage({ action = 'open', categories = SerializedCategories, state = State })
	else
		SendNUIMessage({ action = 'close' })
	end
end

RegisterCommand('vulfayne_zukan', function()
	if not initialized then
		return
	end
	toggleUI()
end, false)
RegisterKeyMapping('vulfayne_zukan', '収集図鑑を開閉', 'keyboard', 'F6')

RegisterNUICallback('close', function(_, cb)
	uiOpen = false
	SetNuiFocus(false, false)
	cb('ok')
end)

--------------------------------------------------------------------------
-- server -> client events
--------------------------------------------------------------------------

RegisterNetEvent('vulfayne_collect:itemCollected', function(payload)
	local cat = State[payload.CategoryId]
	if cat then
		cat.Owned[payload.ItemId] = true
	end
	removeItemZone(payload.CategoryId, payload.ItemId)
	lib.notify({ description = ('「%s」を手に入れた！'):format(payload.Name), type = 'success' })
	pushState()
end)

RegisterNetEvent('vulfayne_collect:sheetCompleted', function(payload)
	lib.notify({ description = ('「%s」コンプリート！ NPCに話しかけよう'):format(payload.SheetName), type = 'inform', duration = 6000 })
end)

RegisterNetEvent('vulfayne_collect:rewardGranted', function(payload)
	local cat = State[payload.CategoryId]
	for _, entry in ipairs(payload.Granted) do
		if cat then
			cat.Claimed[entry.SheetIndex] = true
		end
		lib.notify({ description = ('景品「%s」を受け取った！'):format(entry.Reward.DisplayName), type = 'success', duration = 6000 })
	end
	if #payload.Granted == 0 then
		lib.notify({ description = 'まだ景品交換できるシートがありません。', type = 'error' })
	end
	pushState()
end)

--------------------------------------------------------------------------
-- init
--------------------------------------------------------------------------

local function init()
	if initialized then
		return
	end

	local ok, snapshot = pcall(function()
		return lib.callback.await('vulfayne_collect:getSync', false)
	end)
	if ok and snapshot then
		State = snapshot
	end
	for _, categoryId in ipairs(CATEGORY_ORDER) do
		State[categoryId] = State[categoryId] or { Owned = {}, Claimed = {} }
	end

	registerAllZones()
	for _, categoryId in ipairs(CATEGORY_ORDER) do
		spawnNpc(categoryId, VulfayneCollectibles.Categories[categoryId])
	end

	initialized = true
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
	init()
end)

CreateThread(function()
	if QBCore.Functions.GetPlayerData().citizenid then
		init() -- resource (re)started while already logged in
	end
end)

AddEventHandler('onResourceStop', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then
		return
	end
	for _, ped in pairs(NpcPeds) do
		DeleteEntity(ped)
	end
end)

--------------------------------------------------------------------------
-- dev helper: stand where you want a target/NPC and run this to grab
-- ready-to-paste coordinates for shared/<category>_data.lua
--------------------------------------------------------------------------

RegisterCommand('vulfayne_getcoord', function()
	local ped = PlayerPedId()
	local coords = GetEntityCoords(ped)
	local heading = GetEntityHeading(ped)
	local vec3Text = ('vector3(%.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z)
	local vec4Text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, heading)
	print(('[vulfayne-collections] item Coords: %s | NPC Coords: %s'):format(vec3Text, vec4Text))
	TriggerEvent('chat:addMessage', {
		args = { '^3[vulfayne-collections]', ('item: %s\nNPC: %s'):format(vec3Text, vec4Text) },
	})
end, false)
