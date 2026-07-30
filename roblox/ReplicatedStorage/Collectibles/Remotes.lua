-- ReplicatedStorage/Collectibles/Remotes.lua
-- Creates (server) or waits for (client) the RemoteEvent/RemoteFunction
-- shared by all three collection systems. Require this same module from
-- server and client code instead of poking ReplicatedStorage directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "CollectibleRemotes"

local Remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local function getOrCreate(className, name)
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = folder
		return inst
	end

	-- Client -> Server: "give me my current ownership/claim data for every category"
	Remotes.Sync = getOrCreate("RemoteFunction", "SyncFunction")
	-- Server -> Client: push notifications (item collected, sheet completed, reward granted, resync)
	Remotes.Notify = getOrCreate("RemoteEvent", "NotifyEvent")
else
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	Remotes.Sync = folder:WaitForChild("SyncFunction")
	Remotes.Notify = folder:WaitForChild("NotifyEvent")
end

return Remotes
