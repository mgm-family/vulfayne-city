-- ReplicatedStorage/Collectibles/ClientState.lua
-- Client-only singleton that mirrors the local player's collectible
-- ownership/claim data and lets other LocalScripts (target hiding, the
-- album UI) subscribe to updates without each re-implementing the remote
-- plumbing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Collectibles.Remotes)

local ClientState = {}
ClientState.Categories = {} -- [categoryId] = { Owned = {[itemId]=true}, Claimed = {[sheetIndex]=true} }

local listeners = {}

-- Subscribe to every update pushed from the server. Returns an unsubscribe function.
function ClientState.OnUpdate(callback)
	table.insert(listeners, callback)
	return function()
		local i = table.find(listeners, callback)
		if i then
			table.remove(listeners, i)
		end
	end
end

local function fire(payload)
	for _, callback in ipairs(listeners) do
		task.spawn(callback, payload)
	end
end

local function mergeSync(categoryId, owned, claimed)
	ClientState.Categories[categoryId] = { Owned = owned or {}, Claimed = claimed or {} }
end

local initialized = false
function ClientState.Init()
	if initialized then
		return
	end
	initialized = true

	local ok, snapshot = pcall(function()
		return Remotes.Sync:InvokeServer()
	end)
	if ok and snapshot then
		for categoryId, catData in pairs(snapshot) do
			mergeSync(categoryId, catData.Owned, catData.Claimed)
		end
	end
	fire({ Type = "InitialSync" })

	Remotes.Notify.OnClientEvent:Connect(function(payload)
		if payload.Type == "Sync" then
			mergeSync(payload.CategoryId, payload.Owned, payload.Claimed)
			fire(payload)
		elseif payload.Type == "ItemCollected" then
			local cat = ClientState.Categories[payload.CategoryId]
			if not cat then
				cat = { Owned = {}, Claimed = {} }
				ClientState.Categories[payload.CategoryId] = cat
			end
			cat.Owned[payload.ItemId] = true
			fire(payload)
		elseif payload.Type == "SheetCompleted" then
			fire(payload)
		elseif payload.Type == "RewardGranted" then
			local cat = ClientState.Categories[payload.CategoryId]
			if cat then
				for _, entry in ipairs(payload.Granted) do
					cat.Claimed[entry.SheetIndex] = true
				end
			end
			fire(payload)
		end
	end)
end

function ClientState.IsOwned(categoryId, itemId)
	local cat = ClientState.Categories[categoryId]
	return cat ~= nil and cat.Owned[itemId] == true
end

function ClientState.IsClaimed(categoryId, sheetIndex)
	local cat = ClientState.Categories[categoryId]
	return cat ~= nil and cat.Claimed[sheetIndex] == true
end

return ClientState
