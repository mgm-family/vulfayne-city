-- client/main.lua
-- Registers an ox_target pickup zone for every not-yet-owned seal (direct
-- registration, no item involved), draws a glow marker nearby, spawns the
-- reward NPC, and drives the NUI album (opened by using the vay_zukan_seal
-- item).

local QBCore = exports['qb-core']:GetCoreObject()

local MARKER_DRAW_DISTANCE = 25.0
local MARKER_COLOR = { 75, 106, 138 } -- Zukan.ThemeColor (#4b6a8a) as RGB

local State = { Owned = {}, Claimed = {} }
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

local function isOwned(itemId)
	return State.Owned[itemId] == true
end

local function registerItemZone(item)
	if isOwned(item.Id) then
		return
	end
	local zoneName = 'vay_zukan_seal_' .. item.Id
	exports.ox_target:addSphereZone({
		coords = item.Coords,
		radius = 1.2,
		name = zoneName,
		debug = false,
		options = {
			{
				icon = 'fa-solid fa-hand',
				label = ('シール：%s を拾う'):format(item.Name),
				onSelect = function()
					TriggerServerEvent('vay_zukan_seal:pickup', item.Id)
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

-- Glow marker for nearby unregistered seals.
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
-- NPC (reward only)
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
			label = 'シールコレクターに話す',
			onSelect = function()
				TriggerServerEvent('vay_zukan_seal:talk')
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

-- Called by ox_inventory when the vay_zukan_seal item is used.
exports('useZukan', function(_data, _slot)
	if not initialized then
		lib.notify({ description = '図鑑を読み込み中です。少し待ってから試してください。', type = 'error' })
		return
	end
	toggleUI()
end)

-- Convenience keybind, gated behind actually owning the item.
RegisterCommand('vay_zukan_seal', function()
	if not initialized then
		return
	end
	if not hasZukanItem() then
		lib.notify({ description = '「シール図鑑」を持っていないと開けません。', type = 'error' })
		return
	end
	toggleUI()
end, false)
RegisterKeyMapping('vay_zukan_seal', 'シール図鑑を開閉', 'keyboard', 'F6')

RegisterNUICallback('close', function(_, cb)
	uiOpen = false
	SetNuiFocus(false, false)
	cb('ok')
end)

--------------------------------------------------------------------------
-- server -> client events
--------------------------------------------------------------------------

RegisterNetEvent('vay_zukan_seal:itemCollected', function(payload)
	State.Owned[payload.ItemId] = true
	removeItemZone(payload.ItemId)
	lib.notify({ description = ('「%s」を手に入れた！'):format(payload.Name), type = 'success' })
	pushState()
end)

RegisterNetEvent('vay_zukan_seal:sheetCompleted', function(payload)
	lib.notify({ description = ('「%s」コンプリート！ NPCに話しかけよう'):format(payload.SheetName), type = 'inform', duration = 6000 })
end)

RegisterNetEvent('vay_zukan_seal:rewardGranted', function(payload)
	for _, entry in ipairs(payload.Granted) do
		State.Claimed[entry.SheetIndex] = true
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

	uiOpen = false
	SetNuiFocus(false, false)

	local ok, snapshot = pcall(function()
		return lib.callback.await('vay_zukan_seal:getSync', false)
	end)
	if ok and snapshot then
		State = snapshot
	end

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

RegisterCommand('vay_zukan_seal_getcoord', function()
	local coords = GetEntityCoords(PlayerPedId())
	local heading = GetEntityHeading(PlayerPedId())
	local vec3Text = ('vector3(%.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z)
	local vec4Text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, heading)
	print(('[vay_zukan_seal] item Coords: %s | NPC Coords: %s'):format(vec3Text, vec4Text))
	TriggerEvent('chat:addMessage', {
		args = { '^3[vay_zukan_seal]', ('item: %s\nNPC: %s'):format(vec3Text, vec4Text) },
	})
end, false)
