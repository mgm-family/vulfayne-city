-- ServerScriptService/Collectibles/CollectionServer.server.lua
-- Boots the three collection systems: シール (Seal), オーパーツ (Oopart),
-- 骨董品 (Antique). Place the matching reward NPC (a Model with a
-- PrimaryPart, or a single Part) anywhere in Workspace before players
-- start clearing sheets -- see README.md for the marker-based target
-- placement convention and how to plug in real rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Collectibles.Remotes)
local SealData = require(ReplicatedStorage.Collectibles.SealData)
local OopartData = require(ReplicatedStorage.Collectibles.OopartData)
local AntiqueData = require(ReplicatedStorage.Collectibles.AntiqueData)
local CollectionManager = require(script.Parent.CollectionManager)

local seal = CollectionManager.new(SealData, {
	RegionCenter = Vector3.new(0, 0, 0),
	RegionRadius = 1200,
	TargetColor = Color3.fromRGB(230, 200, 90), -- gold, matches the PD/seal palette on the site
	NpcName = "SealCollectorNPC",
})

local oopart = CollectionManager.new(OopartData, {
	RegionCenter = Vector3.new(0, 0, 0),
	RegionRadius = 1800,
	TargetColor = Color3.fromRGB(150, 110, 220), -- violet, ties into the twin-moon lore
	NpcName = "OopartCollectorNPC",
})

local antique = CollectionManager.new(AntiqueData, {
	RegionCenter = Vector3.new(0, 0, 0),
	RegionRadius = 1000,
	TargetColor = Color3.fromRGB(190, 140, 80), -- aged brass/antique brown
	NpcName = "AntiqueCollectorNPC",
})

seal:Init()
oopart:Init()
antique:Init()

Remotes.Sync.OnServerInvoke = function(player)
	return {
		[SealData.CategoryId] = seal:GetSnapshot(player),
		[OopartData.CategoryId] = oopart:GetSnapshot(player),
		[AntiqueData.CategoryId] = antique:GetSnapshot(player),
	}
end
