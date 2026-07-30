-- StarterPlayer/StarterPlayerScripts/Collectibles/TargetHider.client.lua
-- Hides collectible targets this player has already picked up. Every
-- client runs this independently: an item stays visible/interactable for
-- anyone who hasn't collected it, and disappears only for players who
-- already have it -- including right after rejoining, since ownership is
-- loaded from the server and synced in on spawn.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(ReplicatedStorage.Collectibles.ClientState)

local TARGET_TAG = "CollectibleTarget"

local function hide(part)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	local light = part:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = false
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
end

local function tryHide(part)
	local categoryId = part:GetAttribute("CollectibleCategoryId")
	local itemId = part:GetAttribute("CollectibleItemId")
	if categoryId and itemId and ClientState.IsOwned(categoryId, itemId) then
		hide(part)
	end
end

local function refreshAll()
	for _, part in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		tryHide(part)
	end
end

ClientState.Init()
refreshAll()

ClientState.OnUpdate(function(payload)
	if payload.Type == "ItemCollected" then
		for _, part in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
			if part:GetAttribute("CollectibleItemId") == payload.ItemId then
				hide(part)
			end
		end
	elseif payload.Type == "Sync" or payload.Type == "InitialSync" then
		refreshAll()
	end
end)

CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(tryHide)
