-- client/main.lua
-- Registers an ox_target pickup zone for every antique the player neither
-- owns (registered) nor already carries as a raw antique item, draws a
-- glow marker nearby, spawns the collector NPC (hand-in + reward), and
-- drives the NUI album (opened by using the vay_zukan_antique item).

local QBCore = exports['qb-core']:GetCoreObject()

local MARKER_DRAW_DISTANCE = 25.0
local MARKER_COLOR = { 201, 162, 39 } -- Zukan.ThemeColor (#c9a227) as RGB

local State = { Owned = {}, Claimed = {} }
local HeldRaw = {} -- [itemId] = true, currently carrying the unregistered antique
local ActiveZones = {} -- [itemId] = ox_target zone name
local NpcPed = nil
local uiOpen = false
local initialized = false

SetNuiFocus(false, false) -- resource-start NUI focus reset

--------------------------------------------------------------------------
-- NUI payload (built once)
--------------------------------------------------------------------------

local SerializedSheets = {}
for i, sheet in ipairs(Zukan.Sheets) do
	local items = {}
	for j, item in ipairs(sheet.Items) do
		items[j] = { Id = item.Id, Name = item.Name, Description = item.Description }
	end
	SerializedSheets[i] = {
		Name = sheet.Name,
		Reward = { DisplayName = sheet.Reward.DisplayName, Description = sheet.Reward.Description },
		Items = items,
	}
end

--------------------------------------------------------------------------
-- pickup zones
--------------------------------------------------------------------------

-- "spoken for": either already registered in the album, or currently
-- sitting in the player's pocket waiting to be handed to the NPC.
local function isSpokenFor(itemId)
	return State.Owned[itemId] == true or HeldRaw[itemId] == true
end

local function refreshHeldRawFromInventory()
	HeldRaw = {}
	local ok, slots = pcall(function()
		return exports.ox_inventory:Search('slots', Zukan.RawItem)
	end)
	if not ok or not slots then
		return
	end
	for _, slot in ipairs(slots) do
		if slot.metadata and slot.metadata.itemId then
			HeldRaw[slot.metadata.itemId] = true
		end
	end
end

local function registerItemZone(item)
	if isSpokenFor(item.Id) then
		return
	end
	local zoneName = 'vay_zukan_antique_' .. item.Id
	exports.ox_target:addSphereZone({
		coords = item.Coords,
		radius = 1.2,
		name = zoneName,
		debug = false,
		options = {
			{
				icon = 'fa-solid fa-hand',
				label = ('骨董品：%s を拾う'):format(item.Name),
				onSelect = function()
					TriggerServerEvent('vay_zukan_antique:pickup', item.Id)
				end,
			},
		},
	})
	ActiveZones[item.Id] = zoneName
end

local function removeItemZone(itemId)
	local zoneName = ActiveZones[itemId]
	if zoneName then
		exports.ox_target:removeZone(zoneName)
		ActiveZones[itemId] = nil
	end
end

local function registerAllZones()
	for _, sheet in ipairs(Zukan.Sheets) do
		for _, item in ipairs(sheet.Items) do
			registerItemZone(item)
		end
	end
end

-- Glow marker for nearby collectible antiques.
CreateThread(function()
	while true do
		local sleep = 500
		local coords = GetEntityCoords(PlayerPedId())

		for itemId in pairs(ActiveZones) do
			local item = Zukan.ItemsById[itemId]
			local dist = #(coords - item.Coords)
			if dist < MARKER_DRAW_DISTANCE then
				sleep = 0
				DrawMarker(
					28, item.Coords.x, item.Coords.y, item.Coords.z - 0.9,
					0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.4,
					MARKER_COLOR[1], MARKER_COLOR[2], MARKER_COLOR[3], 160,
					true, false, 2, false, nil, nil, false
				)
			end
		end

		Wait(sleep)
	end
end)

--------------------------------------------------------------------------
-- NPC (antique hand-in + reward, same interaction)
--------------------------------------------------------------------------

local function spawnNpc()
	local npc = Zukan.Npc
	local model = GetHashKey(npc.Model)
	lib.requestModel(model)

	NpcPed = CreatePed(4, model, npc.Coords.x, npc.Coords.y, npc.Coords.z - 1.0, npc.Coords.w, false, true)
	SetEntityInvincible(NpcPed, true)
	FreezeEntityPosition(NpcPed, true)
	SetBlockingOfNonTemporaryEvents(NpcPed, true)
	TaskStartScenarioInPlace(NpcPed, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
	SetModelAsNoLongerNeeded(model)

	exports.ox_target:addLocalEntity(NpcPed, {
		{
			icon = 'fa-solid fa-comment',
			label = '骨董品を納品する',
			onSelect = function()
				TriggerServerEvent('vay_zukan_antique:talk')
			end,
		},
	})
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
		SendNUIMessage({
			action = 'open',
			category = { CategoryName = Zukan.CategoryName, ThemeColor = Zukan.ThemeColor, ThemeColorBright = Zukan.ThemeColorBright },
			sheets = SerializedSheets,
			state = State,
		})
	else
		SendNUIMessage({ action = 'close' })
	end
end

local function hasZukanItem()
	local ok, count = pcall(function()
		return exports.ox_inventory:Search('count', Zukan.ZukanItem)
	end)
	return ok and count ~= nil and count > 0
end

-- Called by ox_inventory when the vay_zukan_antique item is used.
exports('useZukan', function(_data, _slot)
	if not initialized then
		lib.notify({ description = '図鑑を読み込み中です。少し待ってから試してください。', type = 'error' })
		return
	end
	toggleUI()
end)

-- Convenience keybind, gated behind actually owning the item.
RegisterCommand('vay_zukan_antique', function()
	if not initialized then
		return
	end
	if not hasZukanItem() then
		lib.notify({ description = '「骨董品図鑑」を持っていないと開けません。', type = 'error' })
		return
	end
	toggleUI()
end, false)
RegisterKeyMapping('vay_zukan_antique', '骨董品図鑑を開閉', 'keyboard', 'F8')

RegisterNUICallback('close', function(_, cb)
	uiOpen = false
	SetNuiFocus(false, false)
	cb('ok')
end)

--------------------------------------------------------------------------
-- server -> client events
--------------------------------------------------------------------------

RegisterNetEvent('vay_zukan_antique:itemPickedUp', function(payload)
	HeldRaw[payload.ItemId] = true
	removeItemZone(payload.ItemId)
	lib.notify({ description = ('未鑑定の「%s」を手に入れた。コレクターNPCに納品しよう。'):format(payload.Name), type = 'success' })
end)

RegisterNetEvent('vay_zukan_antique:turnedIn', function(payload)
	for _, entry in ipairs(payload.Registered) do
		State.Owned[entry.ItemId] = true
		HeldRaw[entry.ItemId] = nil
		removeItemZone(entry.ItemId)
	end
	if #payload.Registered > 0 then
		lib.notify({ description = ('%d件の骨董品を図鑑に登録した！'):format(#payload.Registered), type = 'success' })
	else
		lib.notify({ description = '納品できる骨董品を持っていません。', type = 'error' })
	end

	for _, entry in ipairs(payload.Granted) do
		State.Claimed[entry.SheetIndex] = true
		lib.notify({ description = ('景品「%s」を受け取った！'):format(entry.Reward.DisplayName), type = 'success', duration = 6000 })
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

	uiOpen = false
	SetNuiFocus(false, false)

	local ok, snapshot = pcall(function()
		return lib.callback.await('vay_zukan_antique:getSync', false)
	end)
	if ok and snapshot then
		State = snapshot
	end

	refreshHeldRawFromInventory()
	registerAllZones()
	spawnNpc()

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
	if NpcPed then
		DeleteEntity(NpcPed)
	end
end)

--------------------------------------------------------------------------
-- dev helper: stand where you want a target/NPC and run this to grab
-- ready-to-paste coordinates for shared/data.lua
--------------------------------------------------------------------------

RegisterCommand('vay_zukan_antique_getcoord', function()
	local coords = GetEntityCoords(PlayerPedId())
	local heading = GetEntityHeading(PlayerPedId())
	local vec3Text = ('vector3(%.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z)
	local vec4Text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, heading)
	print(('[vay_zukan_antique] item Coords: %s | NPC Coords: %s'):format(vec3Text, vec4Text))
	TriggerEvent('chat:addMessage', {
		args = { '^3[vay_zukan_antique]', ('item: %s\nNPC: %s'):format(vec3Text, vec4Text) },
	})
end, false)
