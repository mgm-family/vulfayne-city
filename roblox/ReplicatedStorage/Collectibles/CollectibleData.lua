-- ReplicatedStorage/Collectibles/CollectibleData.lua
-- Small shared helper used by the Seal / Oopart / Antique data modules.
--
-- Data shape produced by SealData / OopartData / AntiqueData:
-- {
--   CategoryId = "Seal",              -- short unique id: DataStore name, tag prefix, item id prefix
--   CategoryName = "シール",           -- Japanese display name shown in the UI
--   Sheets = {
--     [1] = {
--       Name = "PD（警察）記章シール",
--       Reward = { Kind = "Currency", Amount = 300000, DisplayName = "...", Description = "..." },
--       Items = {
--         [1] = { Name = "...", Description = "...", Image = "rbxassetid://0" },
--         ... (9 total)
--       },
--     },
--     ... (10 total)
--   },
-- }

local SHEETS_PER_CATEGORY = 10
local ITEMS_PER_SHEET = 9

local CollectibleData = {}
CollectibleData.SHEETS_PER_CATEGORY = SHEETS_PER_CATEGORY
CollectibleData.ITEMS_PER_SHEET = ITEMS_PER_SHEET

-- Validates the sheet/item counts and stamps a stable Id (e.g. "Seal_S1_I1")
-- plus SheetIndex/ItemIndex onto every item, in place. Called once at the
-- bottom of each data module.
function CollectibleData.Finalize(data)
	assert(#data.Sheets == SHEETS_PER_CATEGORY, data.CategoryId .. ": expected " .. SHEETS_PER_CATEGORY .. " sheets")
	for sheetIndex, sheet in ipairs(data.Sheets) do
		assert(
			#sheet.Items == ITEMS_PER_SHEET,
			string.format("%s sheet %d: expected %d items", data.CategoryId, sheetIndex, ITEMS_PER_SHEET)
		)
		for itemIndex, item in ipairs(sheet.Items) do
			item.Id = string.format("%s_S%d_I%d", data.CategoryId, sheetIndex, itemIndex)
			item.SheetIndex = sheetIndex
			item.ItemIndex = itemIndex
		end
	end
	return data
end

return CollectibleData
