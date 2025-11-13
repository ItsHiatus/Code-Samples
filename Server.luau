--// Services \\--

local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local Network = require(ReplicatedStorage.Network)
local DataService = require(ReplicatedStorage.Modules.Data.DataServiceServer)
local GameTypes = require(ReplicatedStorage.Modules.Game.GameTypes)

local EggInfo = require(ReplicatedStorage.Modules.Eggs.Info)
local PetInfo = require(ReplicatedStorage.Modules.Game.Globals.Pets)
local Currencies = require(ReplicatedStorage.Modules.Game.Globals.Currencies)
local Rarities = require(ReplicatedStorage.Modules.Game.Globals.Rarities)

local PetMutations = require(ReplicatedStorage.Modules.Brainrots.Mutations)

local MarketIds = require(ReplicatedStorage.Modules.Game.Globals.MarketIds)
local QuestEventKind = require(ReplicatedStorage.Modules.Quests.QuestsData.QuestEventKind)
local ServerAnnouncements = require(ReplicatedStorage.Modules.ServerAnnouncements.ServerController)
local QuestHandler = require(ReplicatedStorage.Modules.Quests.Server)

local BoostController = require(ReplicatedStorage.Modules.Boosts.BoostController)
local Integer = require(ReplicatedStorage.Modules.Utils.Integer)

--// Constants \\--

--// Variables \\--

local RobuxPurchaseThreads: { [Player]: { Thread: thread, EggName: string, StartTime: number, WasPurchased: boolean, Items: { GameTypes.EggItem }? } } = {}

--// Instances \\--

--// Auxiliary Functions \\--

local function GetPlayerMultiHatchAmount(player: Player, eggInfo: GameTypes.EggInfo?)
	local data = DataService:GetPlayerData(player)
	if not data then return 1 end

	if eggInfo.Type == "Robux" then return 3 end

	local amount = 1
	if data.OwnedGamepasses then
		if data.OwnedGamepasses[tostring(MarketIds.QuadrupleHatch.GamepassId)] then
			amount = 4
		elseif data.OwnedGamepasses[tostring(MarketIds.TripleHatch.GamepassId)] then
			amount = 3
		end
	end
	return amount
end

--// Functions \\--

local function ActivatePotions(player: Player)
	if BoostController.IsBoostIdle(player, "GoldPotion") then BoostController.ActivateBoost(player, "GoldPotion") end
	if BoostController.IsBoostIdle(player, "DiamondPotion") then BoostController.ActivateBoost(player, "DiamondPotion") end
end

local function ReleaseRobuxPurchaseThread(player: Player, eggName: string, result: { GameTypes.EggItem }?)
	local purchaseData = RobuxPurchaseThreads[player]
	if purchaseData and purchaseData.EggName == eggName then
		purchaseData.WasPurchased = result ~= nil
		purchaseData.Items = result
		coroutine.resume(purchaseData.Thread)
	end
end

local function HatchEgg(player: Player, eggInfo: GameTypes.EggInfo, amount: number): (boolean, { GameTypes.EggItem }?, { [string]: boolean }?)
	--print("Hatching Egg")
	local data = DataService:GetPlayerData(player)
	if not data then return false end

	ActivatePotions(player)

	local canHatchMutated = data.OwnedGamepasses[tostring(MarketIds.MutatedHatch.GamepassId)] == true
	local shouldIgnoreBoosts = eggInfo.Type == "Robux"
	local luck = DataService:GetPetLuck(player, shouldIgnoreBoosts)
	-- print(luck)

	local items = EggInfo.GetRandomItem(eggInfo, amount, luck, canHatchMutated)
	if not items then
		warn(`HatchEgg: No items returned from GetRandomItem for egg {eggInfo.Name}`)
		ReleaseRobuxPurchaseThread(player, eggInfo.Name, nil)
		return false
	end

	local isDiamondPotionActive = not shouldIgnoreBoosts and BoostController.IsBoostActive(player, "DiamondPotion")
	local isGoldPotionActive = not shouldIgnoreBoosts and BoostController.IsBoostActive(player, "GoldPotion")

	for _, item in items do
		if isDiamondPotionActive then
			item.Mutation = "Diamond"
		elseif isGoldPotionActive then
			item.Mutation = "Golden"
		end

		if item.Info and not DataService:ShouldAutoDeletePet(player, eggInfo.Name, item.Info.Name) then
			DataService:AddNewPet(player, item.Info, item.Mutation)
		else
			item.Deleted = true
		end

		local rarity = PetInfo[item.Info.Name].Rarity
		if rarity == "Legendary" or rarity == "Mythical" then
			local options = ServerAnnouncements.Options.Server()
			options.MsgColor = Rarities[rarity].Color:ToHex()
			options.Sender = ""
			ServerAnnouncements.ChatAnnounce(`{player.DisplayName} just hatched a {rarity} {item.Info.Name}!`, options)
		elseif rarity == "Brainrot God" then
			local options = ServerAnnouncements.Options.Global()
			options.MsgColor = Rarities[rarity].Color:ToHex()

			ServerAnnouncements.ChatAnnounce(`@{player.Name} just hatched a {rarity} {item.Info.Name}!`, options)
		elseif rarity == "Exclusive" and item.Info.Type == "Huge" then
			local options = ServerAnnouncements.Options.Server()
			options.MsgColor = Color3.fromRGB(6, 218, 255):ToHex()
			options.Sender = ""
			ServerAnnouncements.ChatAnnounce(`{player.DisplayName} just hatched an {rarity} {item.Info.Name}!`, options)
		end
	end

	ReleaseRobuxPurchaseThread(player, eggInfo.Name, items)
	QuestHandler.submitQuestEvent(player, QuestEventKind.PLAYER_OPENED_EGG, { Amount = amount })

	DataService:UpdateEggsHatched(player, amount)

	-- keep track of any hatch perks used
	local hatchPerks = {}
	if canHatchMutated then hatchPerks["MutatedHatch"] = true end
	if amount == 4 then
		hatchPerks["QuadrupleHatch"] = true
	elseif amount == 3 then
		hatchPerks["TripleHatch"] = true
	end
	if isDiamondPotionActive then
		hatchPerks["DiamondPotion"] = true
	elseif isGoldPotionActive then
		hatchPerks["GoldPotion"] = true
	end
	if not shouldIgnoreBoosts then
		if data.OwnedGamepasses[tostring(MarketIds.Lucky.GamepassId)] == true then hatchPerks["Lucky"] = true end
		if data.OwnedGamepasses[tostring(MarketIds.SuperLucky.GamepassId)] == true then hatchPerks["SuperLucky"] = true end

		if BoostController.IsBoostActive(player, "LuckBoost") then
			hatchPerks["LuckBoost"] = true
		end
		if BoostController.IsBoostActive(player, "SuperLuckBoost") then
			hatchPerks["SuperLuckBoost"] = true
		end
	end

	print(hatchPerks)
	print(BoostController.GetActiveBoosts(player))

	return true, items, hatchPerks
end

local function PromptHatchEgg(player: Player, eggName: string, multiple: boolean?): (boolean, { GameTypes.EggItem }?, { [string]: boolean }?)
	local data = DataService:GetPlayerData(player)
	if not data then return false end

	local eggInfo = EggInfo.GetEggInfo(eggName)
	if not eggInfo then
		warn(`HatchEgg: No egg info found for egg name {eggName}`)
		return false
	end

	if MarketIds.RobuxEggs[eggName] then -- Robux egg
		if not DataService:HasEnoughPetInventorySpace(player, if multiple then 3 else 1) then
			warn(`HatchEgg: Player {player.Name} does not have enough pet inventory space`)
			return false
		end

		local id = if multiple then MarketIds.RobuxEggs[eggName].Triple else MarketIds.RobuxEggs[eggName].Single
		MarketplaceService:PromptProductPurchase(player, id)

		RobuxPurchaseThreads[player] = {
			Thread = coroutine.running(),
			EggName = eggName,
			StartTime = os.clock(),
			WasPurchased = false,
			Items = nil,
		}

		coroutine.yield()

		local purchaseData = RobuxPurchaseThreads[player]
		RobuxPurchaseThreads[player] = nil

		if purchaseData and purchaseData.WasPurchased then
			Network.PlaySound:FireClient(player, SoundService.SFX.Purchase.Coin)
			return true, purchaseData.Items
		else
			Network.Notification:FireClient(player, "Purchase cancelled.", { Type = "Error" })
			return false
		end
	else -- Free/Coins egg
		local amount = if not multiple then 1 else GetPlayerMultiHatchAmount(player, eggInfo)

		if not DataService:HasEnoughPetInventorySpace(player, amount) then
			warn(`HatchEgg: Player {player.Name} does not have enough pet inventory space to hatch {amount}x {eggName} eggs`)
			Network.Notification:FireClient(player, "Not enough pet inventory space to hatch eggs.", { Type = "Error" })
			return false
		end

		local cost = eggInfo.Price * amount
		local currency = Currencies[eggInfo.Type].RealName

		if not DataService:HasEnoughCurrency(player, currency, cost) then
			if amount > 1 then
				amount = 1
				cost = eggInfo.Price

				if not DataService:HasEnoughCurrency(player, currency, cost) then
					-- warn(`HatchEgg: Player {player.Name} does not have enough {currency} to hatch {amount}x {eggName} eggs`)
					Network.Notification:FireClient(player, "Not enough " .. currency .. " to hatch egg.", { Type = "Error" })
					return false
				end
			else
				-- warn(`HatchEgg: Player {player.Name} does not have enough {currency} to hatch {amount}x {eggName} eggs`)
				Network.Notification:FireClient(player, "Not enough " .. currency .. " to hatch egg.", { Type = "Error" })
				return false
			end
		end

		local success, items, hatchPerks = HatchEgg(player, eggInfo, amount)
		if success then
			DataService:ReduceCurrency(player, currency, cost)
			return true, items, hatchPerks
		else
			return false
		end
	end
end

local function ToggleAutoDelete(player: Player, eggName: string, petName: string, state: boolean)
	return DataService:ToggleAutoDeletePet(player, eggName, petName, state)
end

--// Setup \\--

Network.HatchEgg.OnServerEvent:Connect(function(player: Player, eggName: string)
	local success, result, hatchPerks = PromptHatchEgg(player, eggName)
	Network.HatchEggResult:FireClient(player, success, eggName, result, hatchPerks)
end)
Network.HatchEggMulti.OnServerEvent:Connect(function(player: Player, eggName: string)
	local success, result, hatchPerks = PromptHatchEgg(player, eggName, true)
	Network.HatchEggResult:FireClient(player, success, eggName, result, hatchPerks)
end)

Network.ToggleAutoDelete.OnServerInvoke = ToggleAutoDelete

Players.PlayerRemoving:Connect(function(player: Player)
	local purchaseData = RobuxPurchaseThreads[player]
	if not purchaseData then return end

	local thread = purchaseData.Thread
	coroutine.close(thread)
	RobuxPurchaseThreads[player] = nil
end)

do -- egg price display setup
	for _, eggStand in CollectionService:GetTagged("HatchableEgg") do
		local sign = eggStand:FindFirstChild("Sign")
		if not sign then
			print(eggStand, "is missing a Sign")
			continue
		end

		local eggName = eggStand.Name
		local textLabel = sign.SignPart.SurfaceGui.Cost.Value

		if textLabel:HasTag("RobuxValue") then continue end

		local eggInfo = EggInfo.GetEggInfo(eggName)
		if not eggInfo then
			warn(`Egg price display setup: No egg info found for egg name {eggName}`)
			continue
		end

		textLabel.Text = Integer.Abbreviate(eggInfo.Price, 2)
	end
end

--// Return \\--

return {
	HatchEgg = HatchEgg,
	PromptHatchEgg = PromptHatchEgg,
	ReleaseRobuxPurchaseThread = ReleaseRobuxPurchaseThread,
	EggInfo = EggInfo,
}
