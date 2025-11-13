--// Services \\--

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Player = game:GetService("Players").LocalPlayer

local EggInfo = require(ReplicatedStorage.Modules.Eggs.Info)
local HatchAnimation = require(ReplicatedStorage.Modules.Eggs.HatchAnimation)
local EggFloatHandler = require(ReplicatedStorage.Modules.Eggs.Float)

local Network = require(ReplicatedStorage.Network)
local DataService = require(ReplicatedStorage.Modules.Data.DataServiceClient)
local MarketIds = require(ReplicatedStorage.Modules.Game.Globals.MarketIds)
local GameTypes = require(ReplicatedStorage.Modules.Game.GameTypes)

local Integer = require(ReplicatedStorage.Modules.Utils.Integer)
local Currencies = require(ReplicatedStorage.Modules.Game.Globals.Currencies)
local ViewportHandler = require(ReplicatedStorage.Modules.UI.Utils.ViewportHandler)
local SoundPlayer = require(ReplicatedStorage.Modules.Utils.SoundPlayer)
local TableUtils = require(ReplicatedStorage.Modules.Utils.Table)

local GetProductInfo = require(ReplicatedStorage.Modules.Utils.GetProductInfo)

local HUDHandler = require(ReplicatedStorage.Modules.UI.Handlers.HUD)
local Notification = require(ReplicatedStorage.Modules.UI.Handlers.Notification)
local OpenPage = require(ReplicatedStorage.Modules.UI.Handlers.OpenPage)

--// Instances \\--

local PlayerGui = Player:WaitForChild("PlayerGui") :: typeof(game.StarterGui)
local EggScreen = PlayerGui:WaitForChild("EggScreen")
local Frame = EggScreen.Frame

local Assets = ReplicatedStorage.Assets

local Camera = workspace.CurrentCamera
local Mouse = Player:GetMouse()

--// Constants \\--

local MAX_DISTANCE = 15

local SHOW_EGG_FRAME_TWEEN = TweenService:Create(EggScreen.Frame, TweenInfo.new(0.1), { Size = EggScreen.Frame.Size })
local HIDE_EGG_FRAME_TWEEN = TweenService:Create(EggScreen.Frame, TweenInfo.new(0.15), { Size = UDim2.new(0, 0, 0, 0) })

--// Variables \\--

local prevEgg: Model?
local hatchCooldown = 0

--// Auxiliary Functions \\--

-- local part = Instance.new("Part")
-- part.Size = Vector3.new(0.2, 0.2, 0.2)
-- part.Color = Color3.new(1, 0, 0)
-- part.Anchored = true
-- part.CanCollide = false
-- part.CanQuery = false
-- part.Parent = workspace

-- local highlight = Instance.new("Highlight")
-- highlight.FillColor = Color3.fromRGB(255, 0, 0)
-- highlight.OutlineTransparency = 1
-- highlight.Parent = part

local function GetTargetEgg(): Model?
	-- local params = RaycastParams.new()
	-- params.FilterType = Enum.RaycastFilterType.Exclude
	-- params.FilterDescendantsInstances = { Player.Character }
	-- params.CollisionGroup = "PlayerIgnore"

	-- local result = workspace:Raycast(Camera.CFrame.Position, Camera.CFrame.LookVector * MAX_DISTANCE, params)
	-- if result and result.Instance then
	-- 	part.Position = result.Position

	-- 	local egg = result.Instance:FindFirstAncestorOfClass("Model")
	-- 	if egg and egg:HasTag("HatchableEgg") then return egg end

	-- 	if egg then
	-- 		egg = egg:FindFirstAncestorOfClass("Model")
	-- 		if egg and egg:HasTag("HatchableEgg") then return egg end
	-- 	end
	-- end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { Player.Character }
	overlapParams.CollisionGroup = "PlayerIgnore"

	local parts = workspace:GetPartBoundsInBox(Player.Character.HumanoidRootPart.CFrame, Vector3.one * 8, overlapParams)
	local eggsInArea = {}
	for _, p in parts do
		local egg = p:FindFirstAncestorOfClass("Model")
		if egg and egg:HasTag("HatchableEgg") then
			eggsInArea[egg] = egg:GetPivot().Position
			-- return egg
		end
	end

	local closestEgg: Model?
	local closestDistance = math.huge
	for egg, position in eggsInArea do
		local distance = (Camera.CFrame.Position - position).Magnitude
		if distance < closestDistance then
			closestDistance = distance
			closestEgg = egg
		end
	end

	return closestEgg
end

local function ClearList(list: Frame)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function Animate(pet: Model)
	local animations = Assets.Animations.Brainrots:FindFirstChild(pet.Name)
	if not animations then return end

	local idleAnimation = animations:FindFirstChild("Idle")
	if not idleAnimation then return end

	local humanoid = pet:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	local idleTrack = animator:LoadAnimation(idleAnimation)
	idleTrack.Looped = true
	idleTrack:Play()

	pet.Destroying:Connect(function()
		idleTrack:Destroy()
	end)
end

local function GetPlayerMultiHatchAmount(eggInfo: GameTypes.EggInfo): number
	local data = DataService:GetData()
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

local function SetupPetViewport(frame, item: GameTypes.EggItem)
	local model = EggInfo.GetModel(item)
	if model then
		local options = ViewportHandler.Options.new()
		options.FieldOfView = 30
		options.CameraRaise = 1
		options.UseWorldModel = true

		local viewportFrame = frame:FindFirstChildOfClass("ViewportFrame")

		local viewport = ViewportHandler.new(viewportFrame, model, options)
		viewport.Rotation = CFrame.Angles(0, math.rad(30), 0)
		viewport:_updateCamera()

		viewportFrame.BackgroundTransparency = 1
		viewportFrame.Size = UDim2.fromScale(1.1, 1.1)
		viewportFrame.ZIndex = 0
		viewportFrame.Visible = true

		task.defer(Animate, viewport.Model)
	end
end

local function UpdateBillboard(egg: Model)
	local eggInfo = EggInfo.GetEggInfo(egg.Name)
	if not eggInfo then
		print(`No egg info found for`, egg)
		return
	end

	Frame.PetsBackground.Cost.Value.Text = Integer.Abbreviate(eggInfo.Price, 2)
	Frame.PetsBackground.Cost.Icon.Image = Currencies[eggInfo.Type].Icon or ""

	local petsFrame = Frame.PetsBackground.PetsFrame
	local templates = petsFrame.Templates

	ClearList(petsFrame)

	for i, item in eggInfo.Items do
		local petName = item.Name
		local rarity = item.Info.Rarity

		local petTemplate = templates:FindFirstChild(rarity):Clone()
		petTemplate.Name = petName
		petTemplate:FindFirstChild("Name").Text = petName
		petTemplate.Rarity.Text = `{item.Chance}%`

		if item.Info.Icon then
			petTemplate.PetIcon.Image = item.Info.Icon
			petTemplate.PetIcon.Visible = true
		else
			SetupPetViewport(petTemplate, item)
		end

		petTemplate.LayoutOrder = i
		petTemplate.Parent = petsFrame

		-- Add auto delete
		local data = DataService:GetData()
		if data then
			if data.AutoDelete[egg.Name] and data.AutoDelete[egg.Name][petName] then
				local deleteFrame = templates.DeleteFrame:Clone()
				deleteFrame.Parent = petTemplate
			end
		end

		petTemplate.Activated:Connect(function()
			local data = DataService:GetData()
			if not data then return end

			local autoDeleteState = data.AutoDelete[egg.Name] and data.AutoDelete[egg.Name][petName] or false
			local newState = not autoDeleteState

			local success, result = Network.ToggleAutoDelete:InvokeServer(egg.Name, petName, newState)
			if success then
				if result then
					local deleteFrame = templates.DeleteFrame:Clone()
					deleteFrame.Parent = petTemplate
				else
					local deleteFrame = petTemplate:FindFirstChild("DeleteFrame")
					if deleteFrame then deleteFrame:Destroy() end
				end
			else
				print("Failed to toggle auto delete for", petName)
			end
		end)
	end
end

local function ShowEggFrame()
	EggScreen.Enabled = true
	SHOW_EGG_FRAME_TWEEN:Play()
end

local function HideEggFrame()
	HIDE_EGG_FRAME_TWEEN:Play()
	local state = HIDE_EGG_FRAME_TWEEN.Completed:Wait()
	if state == Enum.PlaybackState.Completed then EggScreen.Enabled = false end
end

local function HatchEgg(multiple: boolean?, eggOverride: Model?): boolean?
	local data = DataService:GetData()
	if not data then return end

	local egg = eggOverride or prevEgg
	if not egg then return end

	local eggInfo = EggInfo.GetEggInfo(egg.Name)
	if not eggInfo then
		print(`No egg info found for`, egg)
		return
	end

	local amount = if not multiple then 1 else GetPlayerMultiHatchAmount(eggInfo)
	if TableUtils.Count(data.Inventory.Pets) + amount > data.PetInventoryLimit then
		print("Not enough space in pet inventory to hatch that many pets.")
		Notification.Error("Not enough space in inventory!")
		return
	end

	if multiple and not MarketIds.RobuxEggs[egg.Name] then
		local ownsTriple = data.OwnedGamepasses[tostring(MarketIds.TripleHatch.GamepassId)]
		local ownsQuadruple = data.OwnedGamepasses[tostring(MarketIds.QuadrupleHatch.GamepassId)]
		if not (ownsTriple or ownsQuadruple) then
			print("You do not own any Multi-Hatch gamepass.")
			MarketplaceService:PromptGamePassPurchase(Player, MarketIds.TripleHatch.GamepassId)
			return
		end
	end

	if not MarketIds.RobuxEggs[egg.Name] then
		local totalCost = eggInfo.Price * amount
		if not data.Currency.Standard or data.Currency.Standard < totalCost then
			print("Not enough coins to hatch egg.")
			Notification.Error("Not enough coins!")
			return
		end
	end

	if os.clock() < hatchCooldown then
		print("HatchEgg: On cooldown")
		Notification.Error(`Please wait {Integer.PadFloat(hatchCooldown - os.clock(), 2)} seconds before hatching again.`)
		return
	end

	hatchCooldown = math.huge

	HideEggFrame()

	HatchAnimation.DarknessFadeIn()
	HUDHandler.ToggleHUD(false)

	if multiple then
		Network.HatchEggMulti:FireServer(egg.Name)
	else
		Network.HatchEgg:FireServer(egg.Name)
	end
	return true
end

local function OnItemsReceived(success: boolean, eggName: string, items: { GameTypes.EggItem }?, hatchPerks: {}?, ignoreAutoHatch: boolean?)
	if success and items then
		if MarketIds.RobuxEggs[eggName] then task.wait(0.5) end

		local egg = EggInfo.GetEggFromName(eggName) :: Model
		HatchAnimation.PlayHatchAnimation(egg, items, hatchPerks)

		if prevEgg == egg then ShowEggFrame() end
		Player:SetAttribute("EggHatched", true)
	else
		HatchAnimation.DarknessFadeOut()
		print("HatchEgg: Failed to hatch egg")
	end

	HUDHandler.ToggleHUD(true)

	hatchCooldown = os.clock() + 0.1

	if success and items and Player:GetAttribute("AutoHatching") and not ignoreAutoHatch then
		task.wait(0.3)

		local isMulti = #items > 1
		local targetEgg = GetTargetEgg()
		if not targetEgg or targetEgg.Name ~= eggName then
			Player:SetAttribute("AutoHatching", false)
			return
		end

		HatchEgg(isMulti)
	end
end

--// Setup \\--

HideEggFrame()
Frame.Visible = true

do -- Hatching
	local function toggleAutoHatch()
		local targetEgg = GetTargetEgg()
		if not targetEgg then return end

		local autoHatch = not Player:GetAttribute("AutoHatching")
		Player:SetAttribute("AutoHatching", autoHatch)

		if not autoHatch then return end
		
		-- start hatching immediately
		local data = DataService:GetData()
		if not data then return end

		local ownsMultiHatch = data.OwnedGamepasses[tostring(MarketIds.TripleHatch.GamepassId)] or data.OwnedGamepasses[tostring(MarketIds.QuadrupleHatch.GamepassId)]
		if not HatchEgg(ownsMultiHatch) then
			Player:SetAttribute("AutoHatching", false)
		end
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.E then
			HatchEgg()
		elseif input.KeyCode == Enum.KeyCode.R then
			HatchEgg(true)
		elseif input.KeyCode == Enum.KeyCode.Q then
			local targetEgg = GetTargetEgg()
			if targetEgg then toggleAutoHatch() end
		end
	end)

	Frame.BottomButtonsFrame.OpenButton.Activated:Connect(function()
		HatchEgg()
	end)
	Frame.BottomButtonsFrame.MultiButton.Activated:Connect(function()
		HatchEgg(true)
	end)

	Network.HatchEggResult.OnClientEvent:Connect(OnItemsReceived)
	Network.ServerInitiatedHatch.OnClientEvent:Connect(function(eggName: string, results: { GameTypes.EggItem }, hatchPerks: {}?)
		hatchCooldown = math.huge

		HideEggFrame()

		HatchAnimation.DarknessFadeIn()
		HUDHandler.ToggleHUD(false)

		OnItemsReceived(true, eggName, results, hatchPerks, true)
	end)

	local autoButton = Frame.BottomButtonsFrame.AutoButton
	local cancelAutoButton = PlayerGui:WaitForChild("HatchScreen").Auto

	local function toggleAutoButton()
		if Player:GetAttribute("AutoHatching") then
			autoButton.Mention.TextColor3 = Color3.fromRGB(0, 255, 0)
			autoButton.Key.TextColor3 = Color3.fromRGB(0, 255, 0)
		else
			autoButton.Mention.TextColor3 = Color3.fromRGB(255, 255, 255)
			autoButton.Key.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end

	autoButton.Activated:Connect(toggleAutoHatch)

	cancelAutoButton.Activated:Connect(function()
		Player:SetAttribute("AutoHatching", false)
		cancelAutoButton.Visible = false
	end)

	Player:GetAttributeChangedSignal("AutoHatching"):Connect(toggleAutoButton)
	toggleAutoButton()
end

do -- Gamepass buttons
	local buttons = {}

	local function updateButtons()
		local data = DataService:GetData()
		if not data then return end

		for _, button in buttons do
			local gamepassId = button:GetAttribute("GamepassId") :: string
			if gamepassId and data.OwnedGamepasses[tostring(gamepassId)] then
				button.Owned.Visible = true
				button.Interactable = false
			else
				button.Owned.Visible = false
				button.Interactable = true
			end
		end
	end

	for _, button in Frame.RightButtonsFrame:GetChildren() do
		if button:IsA("GuiButton") then
			local gamepassId = button:GetAttribute("GamepassId")
			if not gamepassId then
				warn(button, `does not have GamepassId attribute specified. Ignored.`)
				button.Visible = false
				continue
			end

			table.insert(buttons, button)

			button.Activated:Connect(function()
				local data = DataService:GetData()
				if not data then return end

				if data.OwnedGamepasses[tostring(gamepassId)] then
					return
				else
					MarketplaceService:PromptGamePassPurchase(Player, gamepassId)
				end
			end)

			task.defer(function()
				local productInfo = GetProductInfo(gamepassId, Enum.InfoType.GamePass)
				if not productInfo then
					warn(`Failed to get product info for gamepass ID {gamepassId}`)
					return
				end

				button.Mention.Text = `\u{E002} {Integer.Pad(tonumber(productInfo.PriceInRobux) or 0)}`
			end)
		end
	end

	DataService:AddDataLoadedCallback(updateButtons)
	DataService:ListenToChange("OwnedGamepasses", updateButtons)
	updateButtons()
end

RunService.Heartbeat:Connect(function()
	local targetEgg = GetTargetEgg()
	if targetEgg and os.clock() > hatchCooldown then
		if prevEgg ~= targetEgg then
			prevEgg = targetEgg
			ShowEggFrame()
			UpdateBillboard(targetEgg)
		end
	else
		prevEgg = nil
		HideEggFrame()
	end
end)

do -- Hide under policy
	local originalParents = {}
	local function UpdatePaidEggVisibility()
		local arePaidRandomItemsRestricted = Player:GetAttribute("ArePaidRandomItemsRestricted")

		for _, egg in CollectionService:GetTagged("RobuxEgg") do
			if arePaidRandomItemsRestricted then
				if not originalParents[egg] then
					originalParents[egg] = egg.Parent
				end
				egg.Parent = ReplicatedStorage
			elseif egg.Parent == ReplicatedStorage then
				egg.Parent = originalParents[egg] or workspace
			end
		end
	end

	Player:GetAttributeChangedSignal("ArePaidRandomItemsRestricted"):Connect(UpdatePaidEggVisibility)
	UpdatePaidEggVisibility()
end

--// Return \\--

return {
	SetupPetViewport = SetupPetViewport,
	HatchEgg = HatchEgg,
}
