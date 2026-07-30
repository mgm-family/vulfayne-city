-- shared/data_helpers.lua
-- Shared (client+server) helpers for the three collection data sets.
-- FiveM has no `require`, so category data is published as globals under
-- the VulfayneCollectibles namespace instead of returned modules.

VulfayneCollectibles = VulfayneCollectibles or {}
VulfayneCollectibles.Categories = {}

local SHEETS_PER_CATEGORY = 10
local ITEMS_PER_SHEET = 9

VulfayneCollectibles.SHEETS_PER_CATEGORY = SHEETS_PER_CATEGORY
VulfayneCollectibles.ITEMS_PER_SHEET = ITEMS_PER_SHEET

-- Deterministic string -> integer hash used to seed the temporary
-- fallback layout for any item that doesn't have a hand-placed `Coords`.
local function hashString(str)
	local hash = 0
	for i = 1, #str do
		hash = (hash * 31 + string.byte(str, i)) % 2147483647
	end
	return hash
end
VulfayneCollectibles.HashString = hashString

-- IMPORTANT: unlike a flat Roblox baseplate, GTA's map has real buildings
-- and terrain height, so a purely mathematical scatter cannot reliably
-- avoid placing an item inside a wall or underground. This fallback only
-- exists so the resource is testable out of the box. Give every item a
-- real `Coords = vector3(x, y, z)` before going live -- stand at the spot
-- in-game and run `/vulfayne_getcoord` (see client/main.lua) to grab one.
local function fallbackCoords(itemId, regionCenter, regionRadius)
	local rng = hashString(itemId)
	local angle = (rng % 3600) / 3600.0 * (2 * math.pi)
	local distance = regionRadius * (0.1 + ((rng // 7) % 1000) / 1000.0 * 0.9)
	local height = 2.0 + ((rng // 13) % 400) / 10.0 -- +2.0 to +42.0
	return vector3(
		regionCenter.x + math.cos(angle) * distance,
		regionCenter.y + math.sin(angle) * distance,
		regionCenter.z + height
	)
end

-- Validates sheet/item counts, stamps a stable Id ("Seal_S1_I1") onto
-- every item, fills in a fallback Coords for anything left unset, and
-- registers the finished table under VulfayneCollectibles.Categories.
function VulfayneCollectibles.Finalize(data)
	assert(#data.Sheets == SHEETS_PER_CATEGORY, data.CategoryId .. ": expected " .. SHEETS_PER_CATEGORY .. " sheets")

	local regionCenter = data.RegionCenter or vector3(0.0, 0.0, 30.0)
	local regionRadius = data.RegionRadius or 400.0
	local unplaced = 0

	for sheetIndex, sheet in ipairs(data.Sheets) do
		assert(
			#sheet.Items == ITEMS_PER_SHEET,
			("%s sheet %d: expected %d items"):format(data.CategoryId, sheetIndex, ITEMS_PER_SHEET)
		)
		for itemIndex, item in ipairs(sheet.Items) do
			item.Id = ("%s_S%d_I%d"):format(data.CategoryId, sheetIndex, itemIndex)
			item.SheetIndex = sheetIndex
			item.ItemIndex = itemIndex
			if not item.Coords then
				item.Coords = fallbackCoords(item.Id, regionCenter, regionRadius)
				unplaced += 1
			end
		end
	end

	if unplaced > 0 then
		print(("^3[vulfayne-collections] %s: %d/%d items still use a temporary fallback position. Place real Coords before launch (see README).^0")
			:format(data.CategoryId, unplaced, SHEETS_PER_CATEGORY * ITEMS_PER_SHEET))
	end

	data.Npc = data.Npc or {}
	data.Npc.Model = data.Npc.Model or 'a_m_y_business_01'
	if not data.Npc.Coords then
		data.Npc.Coords = vector4(regionCenter.x, regionCenter.y, regionCenter.z, 0.0)
		print(("^3[vulfayne-collections] %s: NPC has no real Coords yet, using a temporary fallback. Set data.Npc.Coords before launch.^0")
			:format(data.CategoryId))
	end

	VulfayneCollectibles.Categories[data.CategoryId] = data
	return data
end
