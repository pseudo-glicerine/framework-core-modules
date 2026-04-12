--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local PlayerLoadedEvent = ReplicatedStorage.Comm.Events.PlayerLoaded

local PlayerService = {
	PlayerLoaded = GoodSignal.new(),
	PlayerAdded = Players.PlayerAdded,
	PlayerRemoving = Players.PlayerRemoving,
}
type PlayerService = typeof(PlayerService)

function PlayerService.Init(self: PlayerService)
	self.Players = {}
	self.CharacterConnections = {}

	self.PlayerAddedConnection = self.PlayerAdded:Connect(function(player: Player)
		self:SetupPlayer(player)
	end)

	self.PlayerRemovingConnection = self.PlayerRemoving:Connect(function(player: Player)
		if self.CharacterConnections[player] then
			self.CharacterConnections[player]:Disconnect()
			self.CharacterConnections[player] = nil
		end
	end)

	for _, player in Players:GetPlayers() do
		if not self.Players[player.Name] then
			self:SetupPlayer(player)
		end
	end
end

function PlayerService.Start(self: PlayerService)
	PlayerLoadedEvent.OnServerEvent:Connect(function(player: Player)
		if not self.Players[player.Name] then
			self:WaitForPlayer(player.Name)
		end

		if not self.Players[player.Name].Loaded then
			self.Players[player.Name].Loaded = true
			self.PlayerLoaded:Fire(player)
		end
	end)
end

function PlayerService.SetupPlayer(self: PlayerService, player: Player)
	self.Players[player.Name] = {
		PlayerInstance = player,
		Loaded = false, -- // client must fire an event that determines if specified player's controllers are loaded properly
	}
	
	self.CharacterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Player"
			end
		end
	end)
end

function PlayerService.GetRandomPlayer(self: PlayerService, exclude: { Player }?): Player?
	for _, playerData in self.Players do
		if playerData.PlayerInstance:IsA("Player") then
			if exclude then
				if table.find(exclude, playerData.PlayerInstance) then
					continue
				end
			end

			return playerData.PlayerInstance
		end
	end

	return nil
end

function PlayerService.IsPlayerLoaded(self: PlayerService, player: Player)		-- // currently useless
	if self.Players[player.Name] then
		return self.Players[player.Name].Loaded
	end

	return false
end

function PlayerService.GetPlayerByName(self: PlayerService, playerName: string): Player?
	print(self.Players)

	if self.Players[playerName] then
		return self.Players[playerName].PlayerInstance
	end

	return nil
end

function PlayerService.KickAllPlayers(self: PlayerService, kickMessage: string?)
	for _, playerData in self.Players do
		if playerData.PlayerInstance then
			playerData.PlayerInstance:Kick(kickMessage or "Error ")
		end
	end
end

function PlayerService.WaitForPlayer(self: PlayerService, playerName: string)
	while self.Players[playerName] == nil do
		task.wait(0.05)
	end
end

function PlayerService.WaitForLoaded(self: PlayerService, player: Player)
	self:WaitForPlayer(player.Name)

	while self.Players[player.Name].Loaded ~= true do
		task.wait(0.05)
	end
end

function PlayerService.GetPlayers(self: PlayerService)
	local playerList = {}
	for _, playerData in self.Players do
		if playerData.PlayerInstance:IsDescendantOf(Players) then
			table.insert(playerList, playerData.PlayerInstance)
		end
	end

	return playerList
end

--[[function PlayerService.GetLoadedPlayers(self: PlayerService)
	local loadedPlayers = {}
	for player, playerData in self.Players do
		if playerData.Loaded then
			table.insert(loadedPlayers, player)
		end
	end

	return loadedPlayers
end]]

return PlayerService
