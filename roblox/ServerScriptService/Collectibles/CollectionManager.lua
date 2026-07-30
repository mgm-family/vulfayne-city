-- ServerScriptService/Collectibles/CollectionManager.lua
-- Generic server-side engine shared by the Seal / Oopart / Antique
-- collection systems. One instance of this per category (see
-- CollectionServer.server.lua). Responsible for:
--   * spawning the 90 hidden pickup targets for a category
--   * per-player DataStore persistence of what's been collected/claimed
--   * granting an item when a player interacts with its target
--   * handling the reward NPC (grants any newly-completed sheet's reward)

local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Collectibles.Remotes)

local TARGET_TAG = "CollectibleTarget"
local MARKERS_FOLDER_NAME = "CollectibleMarkers"
local TARGETS_FOLDER_NAME = "CollectibleTargets"
local AUTOSAVE_INTERVAL = 60

local CollectionManager = {}
CollectionManager.__index = CollectionManager

-- Deterministic string -> number hash (used to seed the fallback layout).
local function hashString(str)
	local hash = 0
	for i = 1, #str do
		hash = (hash * 31 + string.byte(str, i)) % 2147483647
	end
	return hash
end

-- Procedurally scatters items that have no manual marker across a wide
-- area, with varied height so some feel like rooftop / back-alley /
-- basement hiding spots. Deterministic per item id, so the layout is
-- stable across server restarts even without a marker. Once the real map
-- is available in Studio, drop a Part or Attachment named after the
-- item's Id (e.g. "Seal_S1_I1") inside Workspace.CollectibleMarkers to
-- override any single item's position -- see the README.
local function fallbackCFrame(itemId, regionCenter, regionRadius)
	local rng = Random.new(hashString(itemId))
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(regionRadius * 0.1, regionRadius)
	local height = rng:NextNumber(4, 55)
	local offset = Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
	return CFrame.new(regionCenter + offset)
end

local function findMarker(itemId)
	local folder = Workspace:FindFirstChild(MARKERS_FOLDER_NAME)
	if not folder then
		return nil
	end
	local marker = folder:FindFirstChild(itemId, true)
	if marker and (marker:IsA("BasePart") or marker:IsA("Attachment")) then
		return marker
	end
	return nil
end

-- data: one of SealData / OopartData / AntiqueData (already Finalize()'d)
-- config: {
--   RegionCenter = Vector3,  -- fallback scatter center (default origin)
--   RegionRadius = number,   -- fallback scatter radius in studs
--   TargetColor = Color3,    -- pickup glow color
--   NpcName = string,        -- name of the reward NPC to find in Workspace
--   OnGrantReward = function(player, reward, sheetIndex, data) -- optional, overrides default reward handling
-- }
function CollectionManager.new(data, config)
	config = config or {}
	local self = setmetatable({}, CollectionManager)

	self.Data = data
	self.RegionCenter = config.RegionCenter or Vector3.new(0, 0, 0)
	self.RegionRadius = config.RegionRadius or 1500
	self.TargetColor = config.TargetColor or Color3.fromRGB(230, 200, 90)
	self.NpcName = config.NpcName or (data.CategoryId .. "CollectorNPC")
	self.OnGrantReward = config.OnGrantReward

	self.Store = DataStoreService:GetDataStore("Collectibles_" .. data.CategoryId .. "_v1")
	self.PlayerData = {} -- [player] = { Owned = {[itemId]=true}, Claimed = {[sheetIndex]=true} }
	self.Dirty = {} -- [player] = true, needs saving

	local targetsFolder = Workspace:FindFirstChild(TARGETS_FOLDER_NAME)
	if not targetsFolder then
		targetsFolder = Instance.new("Folder")
		targetsFolder.Name = TARGETS_FOLDER_NAME
		targetsFolder.Parent = Workspace
	end
	self.CategoryFolder = Instance.new("Folder")
	self.CategoryFolder.Name = data.CategoryId
	self.CategoryFolder.Parent = targetsFolder

	return self
end

function CollectionManager:_load(player)
	local key = "Player_" .. player.UserId
	local ok, result = pcall(function()
		return self.Store:GetAsync(key)
	end)
	local saved = ok and result or nil
	self.PlayerData[player] = {
		Owned = (saved and saved.Owned) or {},
		Claimed = (saved and saved.Claimed) or {},
	}
	Remotes.Notify:FireClient(player, {
		Type = "Sync",
		CategoryId = self.Data.CategoryId,
		Owned = self.PlayerData[player].Owned,
		Claimed = self.PlayerData[player].Claimed,
	})
end

function CollectionManager:_save(player, userId)
	local data = self.PlayerData[player]
	if not data then
		return
	end
	local key = "Player_" .. userId
	local ok, err = pcall(function()
		self.Store:SetAsync(key, data)
	end)
	if not ok then
		warn(("[%s] failed to save data for %d: %s"):format(self.Data.CategoryId, userId, tostring(err)))
	end
	self.Dirty[player] = nil
end

function CollectionManager:GetSnapshot(player)
	local data = self.PlayerData[player]
	if not data then
		return { Owned = {}, Claimed = {} }
	end
	return { Owned = data.Owned, Claimed = data.Claimed }
end

function CollectionManager:_isSheetComplete(player, sheetIndex)
	local owned = self.PlayerData[player].Owned
	local sheet = self.Data.Sheets[sheetIndex]
	for _, item in ipairs(sheet.Items) do
		if not owned[item.Id] then
			return false
		end
	end
	return true
end

function CollectionManager:_grantItem(player, item)
	local pdata = self.PlayerData[player]
	if not pdata or pdata.Owned[item.Id] then
		return
	end
	pdata.Owned[item.Id] = true
	self.Dirty[player] = true

	Remotes.Notify:FireClient(player, {
		Type = "ItemCollected",
		CategoryId = self.Data.CategoryId,
		ItemId = item.Id,
		SheetIndex = item.SheetIndex,
		ItemIndex = item.ItemIndex,
		Name = item.Name,
	})

	local sheetIndex = item.SheetIndex
	if not pdata.Claimed[sheetIndex] and self:_isSheetComplete(player, sheetIndex) then
		Remotes.Notify:FireClient(player, {
			Type = "SheetCompleted",
			CategoryId = self.Data.CategoryId,
			SheetIndex = sheetIndex,
			SheetName = self.Data.Sheets[sheetIndex].Name,
		})
	end
end

function CollectionManager:_spawnTarget(item)
	local cframe
	local marker = findMarker(item.Id)
	if marker then
		cframe = marker:IsA("Attachment") and marker.WorldCFrame or marker.CFrame
	else
		cframe = fallbackCFrame(item.Id, self.RegionCenter, self.RegionRadius)
	end

	local part = Instance.new("Part")
	part.Name = item.Id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.Color = self.TargetColor
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CFrame = cframe
	part:SetAttribute("CollectibleItemId", item.Id)
	part:SetAttribute("CollectibleCategoryId", self.Data.CategoryId)
	CollectionService:AddTag(part, TARGET_TAG)

	local light = Instance.new("PointLight")
	light.Color = self.TargetColor
	light.Range = 8
	light.Brightness = 2
	light.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "拾う"
	prompt.ObjectText = ("%s / %s"):format(self.Data.CategoryName, item.Name)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(playerWhoTriggered)
		local pdata = self.PlayerData[playerWhoTriggered]
		if pdata and not pdata.Owned[item.Id] then
			self:_grantItem(playerWhoTriggered, item)
		end
	end)

	part.Parent = self.CategoryFolder
end

function CollectionManager:_setupNpc()
	local npc = Workspace:FindFirstChild(self.NpcName, true)
	if not npc then
		warn(("[%s] no NPC named '%s' found in Workspace. Place one before players try to claim rewards."):format(
			self.Data.CategoryId, self.NpcName))
		return
	end

	local anchor = npc
	if npc:IsA("Model") then
		anchor = npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart")
	end
	if not anchor then
		warn(("[%s] NPC '%s' has no BasePart to attach a ProximityPrompt to."):format(self.Data.CategoryId, self.NpcName))
		return
	end

	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "話す"
		prompt.ObjectText = self.Data.CategoryName .. "コレクター"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 10
		prompt.Parent = anchor
	end

	prompt.Triggered:Connect(function(player)
		self:_talkToNpc(player)
	end)
end

function CollectionManager:_talkToNpc(player)
	local pdata = self.PlayerData[player]
	if not pdata then
		return
	end

	local granted = {}
	for sheetIndex, sheet in ipairs(self.Data.Sheets) do
		if not pdata.Claimed[sheetIndex] and self:_isSheetComplete(player, sheetIndex) then
			pdata.Claimed[sheetIndex] = true
			self.Dirty[player] = true
			self:_grantReward(player, sheet.Reward, sheetIndex)
			table.insert(granted, { SheetIndex = sheetIndex, SheetName = sheet.Name, Reward = sheet.Reward })
		end
	end

	Remotes.Notify:FireClient(player, {
		Type = "RewardGranted",
		CategoryId = self.Data.CategoryId,
		Granted = granted,
	})
end

function CollectionManager:_grantReward(player, reward, sheetIndex)
	if self.OnGrantReward then
		local ok, err = pcall(self.OnGrantReward, player, reward, sheetIndex, self.Data)
		if not ok then
			warn(("[%s] OnGrantReward errored: %s"):format(self.Data.CategoryId, tostring(err)))
		end
		return
	end

	-- Default handling: pay out to a leaderstats.Money NumberValue if one
	-- exists. Wire `OnGrantReward` in CollectionServer.server.lua to hook
	-- this up to your own economy/inventory system instead.
	if reward.Kind == "Currency" then
		local leaderstats = player:FindFirstChild("leaderstats")
		local money = leaderstats and leaderstats:FindFirstChild("Money")
		if money and money:IsA("NumberValue") then
			money.Value += reward.Amount
		else
			warn(("[%s] %s cleared sheet %d but no leaderstats.Money exists to pay out %d"):format(
				self.Data.CategoryId, player.Name, sheetIndex, reward.Amount))
		end
	end
end

function CollectionManager:Init()
	for _, sheet in ipairs(self.Data.Sheets) do
		for _, item in ipairs(sheet.Items) do
			self:_spawnTarget(item)
		end
	end

	self:_setupNpc()

	Players.PlayerAdded:Connect(function(player)
		self:_load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_load(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if self.Dirty[player] then
			self:_save(player, player.UserId)
		end
		self.PlayerData[player] = nil
		self.Dirty[player] = nil
	end)

	game:BindToClose(function()
		for player in pairs(self.PlayerData) do
			if self.Dirty[player] then
				self:_save(player, player.UserId)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in pairs(self.Dirty) do
				if player.Parent then
					self:_save(player, player.UserId)
				end
			end
		end
	end)
end

return CollectionManager
