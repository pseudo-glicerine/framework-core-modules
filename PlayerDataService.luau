local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local MonetizationStoreDataTemplate = require(ServerScriptService.Server.Data.MonetizationStoreDataTemplate)
local PlayerDataTemplate = require(ServerScriptService.Server.Data.PlayerDataTemplate)

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local KICK_ON_ERROR = true
local DEV_MODE = false

type DataKey = string | number
type DataPath = { DataKey }
type DataTable = {
	[AllowedKey]: AllowedValue,
}
export type AllowedKey = string | number
export type AllowedValue = string | number | boolean | DataTable

export type PlayerInfo = Player | string

export type ScopeControl = {
	Set: (self: ScopeControl, dataKey: DataKey?, value: AllowedValue) -> AllowedValue,
	Get: (self: ScopeControl, dataPath: DataPath) -> AllowedValue?,
	Clear: (self: ScopeControl) -> nil,
	Remove: (self: ScopeControl) -> nil,
}

local PlayerDataService = {}
type PlayerDataService = typeof(PlayerDataService)

function PlayerDataService.Init(self: PlayerDataService)
	self.PlayerProfileStore = ProfileStore.New("PlayerProfiles", PlayerDataTemplate)
	self.MonetizationProfileStore = ProfileStore.New("MonetizationStore", MonetizationStoreDataTemplate)

	self.Profiles = {}
	--self.SaveQueue = {}

	if DEV_MODE then
		self.PlayerProfileStore = self.PlayerProfileStore.Mock
	end
end

function PlayerDataService.Start(self: PlayerDataService)
	Players.PlayerAdded:Connect(function(player: Player)
		self:CreateProfile(player, function()
			if KICK_ON_ERROR then
				player:Kick("[DATA ERROR] Your data wasn't loaded properly. Please report this error to the developer")
			end
		end)
	end)
end

local function getPlayerUserId(player: PlayerInfo): number?
	if typeof(player) == "Instance" then
		if player:IsA("Player") then
			return player.UserId
		end
	elseif typeof(player) == "string" then
		return Players:GetUserIdFromNameAsync(player)
	end

	return nil
end

local function convertInTable(value)
	return { value }
end

local function isValidType(value: any)
	if type(value) == "string" then
		return true
	end

	if type(value) == "number" then
		return true
	end

	if type(value) == "boolean" then
		return true
	end

	if type(value) == "table" then
		for k, v in pairs(value) do
			if not isValidType(k) then
				return false
			end

			if not isValidType(v) then
				return false
			end
		end

		return true
	end

	return false
end

function PlayerDataService.CreateProfile(self: PlayerDataService, player: PlayerInfo, onError: () -> ...any)
	local playerUserId = getPlayerUserId(player)
	if not playerUserId then
		return false
	end

	local playerProfile = self.PlayerProfileStore:StartSessionAsync("Player_" .. playerUserId, {
		Cancel = function()
			if typeof(player) ~= "Instance" then
				return true
			end

			return not player:IsDescendantOf(game:GetService("Players"))
		end,
	})
	if not playerProfile then
		onError()
		return false
	end

	playerProfile:AddUserId(playerUserId)
	playerProfile:Reconcile()

	playerProfile.OnSessionEnd:Connect(function()
		if typeof(player) == "Instance" then
			if player:IsA("Player") then
				player:Kick("Your profile's session has ended")
			end
		end
	end)

	if typeof(player) == "Instance" then
		if player:IsA("Player") then
			if not player:IsDescendantOf(game:GetService("Players")) then
				playerProfile:EndSession()
			end
		end
	end

	self.Profiles[playerUserId] = playerProfile

	return true
end

function PlayerDataService.DestroyProfile(self: PlayerDataService, player: PlayerInfo)
	local playerUserId = getPlayerUserId(player)
	if not playerUserId then
		return
	end

	if self.Profiles[playerUserId] then
		self.Profiles[playerUserId]:EndSession()
		self.Profiles[playerUserId] = nil
	end
end

function PlayerDataService.HasProfile(self: PlayerDataService, player: PlayerInfo)
	local playerUserId = getPlayerUserId(player)
	if not playerUserId then
		return
	end

	if self.Profiles[playerUserId] then
		return true
	end

	return false
end

function PlayerDataService.WaitForProfile(self: PlayerDataService, player: PlayerInfo)
	local playerUserId = getPlayerUserId(player)
	if not playerUserId then
		return
	end

	repeat
		task.wait(0.01)
	until self.Profiles[playerUserId] ~= nil
end

function PlayerDataService.SavePlayer(self: PlayerDataService, player: PlayerInfo)
	local playerUserId = getPlayerUserId(player)
	if not playerUserId then
		return
	end

	if self.Profiles[playerUserId] then
		self.Profiles[playerUserId]:Save()
	end
end

function PlayerDataService.CreateScope(self: PlayerDataService, player: PlayerInfo, scopeName: string): ScopeControl?
	local playerUserId = getPlayerUserId(player)
	if not playerUserId then
		return
	end

	local playerProfile = self.Profiles[playerUserId]
	if not playerProfile then
		return
	end

	local profileData = playerProfile.Data
	if profileData[scopeName] then
		return
	end

	profileData[scopeName] = {}

	return self:GetScope(player, scopeName)
end

function PlayerDataService.GetScope(self: PlayerDataService, player: PlayerInfo, scopeName: string): ScopeControl?
	local playerUserId = getPlayerUserId(player)
	if not playerUserId then
		return
	end

	local playerProfile = self.Profiles[playerUserId]
	if not playerProfile then
		return
	end

	local profileData = playerProfile.Data
	if not profileData[scopeName] then
		return
	end

	return table.freeze({
		Set = function(_, dataKey: DataKey?, value: AllowedValue): AllowedValue?
			assert(isValidType(value), `Provided value has unallowed type or includes objects with unallowed types`)

			if dataKey ~= nil then
				assert(isValidType(dataKey), `Provided data key has unallowed type`)
				profileData[scopeName][dataKey] = value
			else
				table.insert(profileData[scopeName], value)
			end

			return value
		end,
		Get = function(_, dataPath: DataPath?, default: any)
			if dataPath ~= nil and type(dataPath) ~= "table" then
				dataPath = convertInTable(dataPath)
			else
				return profileData[scopeName] or default
			end

			local currentData = profileData[scopeName]
			for _, dataKey in dataPath do
				if type(currentData) ~= "table" then
					break
				end

				local currentPoint = currentData[dataKey]
				if currentPoint ~= nil then
					currentData = currentPoint
					continue
				else
					break
				end
			end

			if currentData == profileData[scopeName] then
				currentData = default
			end

			return currentData
		end,
		Clear = function(_)
			profileData[scopeName] = {}
		end,
		Remove = function(_)
			profileData[scopeName] = nil
		end,
	} :: ScopeControl)
end

--[[function PlayerDataService.SetPlayerDataInScope(
	self: PlayerDataService,
	player: Player,
	scope: string,
	dataKey: string,
	value: number | string | {},
	index: any
)
	local playerProfile = self.Profiles[player]
	local playerData = playerProfile.Data

	local dataInScope = playerData[scope]
	if not dataInScope then
		return
	end

	if dataInScope[dataKey] ~= nil then
		if type(dataInScope[dataKey]) ~= "table" then
			dataInScope[dataKey] = value
		else
			if index then
				if dataInScope[dataKey][index] then
					dataInScope[dataKey][index] = value
				end
			end
		end
	end

	return value
end]]

--[[function PlayerDataService.GetPlayerDataInScope(
	self: PlayerDataService,
	player: Player,
	scope: string,
	dataKey: string?,
	index: any
)
	local playerProfile = self.Profiles[player]
	local playerData = playerProfile.Data

	if playerData[scope] then
		if dataKey then
			if playerData[scope][dataKey] then
				if playerData[scope][dataKey][index] then
					return playerData[scope][dataKey][index]
				end

				return playerData[scope][dataKey]
			end
		else
			return playerData[scope]
		end
	end

	return nil
end]]

return PlayerDataService
