--// Services \\--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Player = game:GetService("Players").LocalPlayer
local RunService = game:GetService("RunService")

local GameTypes = require(ReplicatedStorage.Modules.Game.GameTypes)

local DataService = require(ReplicatedStorage.Modules.Data.DataServiceClient)
local EggInfo = require(ReplicatedStorage.Modules.Eggs.Info)
local Network = require(ReplicatedStorage.Network)
local MarketIds = require(ReplicatedStorage.Modules.Game.Globals.MarketIds)

local ViewportHandler = require(ReplicatedStorage.Modules.UI.Utils.ViewportHandler)
local SoundPlayer = require(ReplicatedStorage.Modules.Utils.SoundPlayer)
local UIParticles = require(ReplicatedStorage.Modules.UI.Utils.UIParticles)

--// Instances \\--

local Assets = ReplicatedStorage.Assets
local EggModels = Assets.Models.EggModels

local PlayerGui = Player:WaitForChild("PlayerGui") :: typeof(game.StarterGui)
local HatchScreen = PlayerGui:WaitForChild("HatchScreen")

local Template = HatchScreen.Templates.EggViewport
local PetNameTemplate = HatchScreen.Templates.PetName
local RarityTemplates = HatchScreen.Templates.Rarities

local Darkness = HatchScreen.Darkness

local SFX = SoundService.SFX
local HatchSFX = SFX.Hatching

--// Constants \\--

local EGG_CFRAME = CFrame.Angles(0, math.rad(65), 0)

local INDEX_POSITIONS = {
	[1] = {
		[1] = UDim2.fromScale(0.5, 0.5),
	},
	[3] = {
		[1] = UDim2.fromScale(0.5, 0.5),
		[2] = UDim2.fromScale(0.25, 0.5),
		[3] = UDim2.fromScale(0.75, 0.5),
	},
	[4] = {
		[1] = UDim2.fromScale(0.15, 0.5),
		[2] = UDim2.fromScale(0.385, 0.5),
		[3] = UDim2.fromScale(0.618, 0.5),
		[4] = UDim2.fromScale(0.85, 0.5),
	},
}

--// Variables \\--

--// Auxiliary Functions \\--

local function isFastHatchEnabled(): boolean
	-- do return false end
	local data = DataService:GetData()
	if not data then return false end

	if data.OwnedGamepasses then
		if data.OwnedGamepasses[tostring(MarketIds.FastEggOpen.GamepassId)] then return true end
	end
	return false
end

local function DarknessFadeIn()
	Darkness.BackgroundTransparency = 1
	Darkness.Visible = true

	local tween = TweenService:Create(Darkness, TweenInfo.new(0.1), { BackgroundTransparency = 0.8 })
	tween:Play()
	-- tween.Completed:Wait()
end

local function DarknessFadeOut()
	local tween = TweenService:Create(Darkness, TweenInfo.new(0.1), { BackgroundTransparency = 1 })
	tween:Play()

	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			Darkness.Visible = false
			HatchScreen.Enabled = false
		end
	end)
end

local function ClearHatchViewports()
	for _, child in HatchScreen:GetChildren() do
		if child:IsA("ViewportFrame") and child.Name ~= "Template" then child:Destroy() end
	end
end

local function ThrowAwayViewport(viewport: typeof(Template))
	local tween = TweenService:Create(viewport, TweenInfo.new(0.1), { Size = UDim2.new(0, 0, 0, 0) })
	tween:Play()
	tween.Completed:Once(function()
		viewport:Destroy()
	end)
end

local function ThrowAllViewports()
	for _, child in HatchScreen:GetChildren() do
		if child:IsA("ViewportFrame") and child.Name ~= "Template" then ThrowAwayViewport(child) end
	end
end

local function SetupHatchViewport(viewport: ViewportFrame, model: Model, index: number, formation: number)
	local clone = model:Clone()
	clone:PivotTo(EGG_CFRAME)
	clone.Parent = viewport

	viewport.ZIndex = 100 - index

	if INDEX_POSITIONS[formation] and INDEX_POSITIONS[formation][index] then
		viewport.Position = INDEX_POSITIONS[formation][index]
	else
		viewport.Position = UDim2.fromScale(math.random(), math.random())
	end
end

local function DisplayItem(item: GameTypes.EggItem, viewport: typeof(Template)): typeof(Template)
	local model = EggInfo.GetModel(item)
	if not model then
		warn(`Could not find egg model for`, item)
		return
	end

	local particleConfig = UIParticles.Config.new()
	particleConfig.Position = viewport.AbsolutePosition
	particleConfig.Color = if item.Info.Rarity == "Exclusive" then "Random" else EggInfo.GetRarityColor(item.Info.Rarity)

	task.spawn(UIParticles.emitConfetti, particleConfig, 30)

	local modelViewport = Template:Clone()
	modelViewport.Name = `HatchViewport_{item.Name}`
	modelViewport.Position = viewport.Position
	modelViewport.Size = viewport.Size
	modelViewport.ZIndex = viewport.ZIndex
	modelViewport.Parent = HatchScreen

	local petNameTemplate = PetNameTemplate:Clone()
	petNameTemplate.Text = item.Name
	petNameTemplate.Parent = modelViewport

	local rarityTemplate = RarityTemplates:FindFirstChild(item.Info.Rarity)
	if rarityTemplate then
		local rarityClone = rarityTemplate:Clone()
		rarityClone.Parent = modelViewport
	end

	if item.Deleted then
		local deletedLabel = HatchScreen.Templates.Deleted:Clone()
		deletedLabel.Parent = modelViewport
	end

	if item.Mutation and item.Mutation ~= "Normal" then
		local mutationLabel = HatchScreen.Templates.Mutation:Clone()
		mutationLabel.Text = item.Mutation

		for _, gradient in mutationLabel:GetChildren() do
			if gradient:IsA("UIGradient") then
				gradient.Enabled = gradient.Name == item.Mutation
			end
		end

		mutationLabel.Parent = modelViewport
	end

	local options = ViewportHandler.Options.new()
	options.FieldOfView = 50

	local handler = ViewportHandler.new(modelViewport, model, options)
	handler.Rotation = CFrame.Angles(0, math.rad(-25), 0)
	handler:StartSpin()

	TweenService:Create(modelViewport, TweenInfo.new(0.2), { Size = Template.Size }):Play()

	task.delay(0.2, function()
		HatchScreen:SetAttribute("Completed", true)
	end)

	return modelViewport
end

local function AnimateEgg(viewport: typeof(Template), item: GameTypes.EggItem, isFastHatch: boolean)
	local size = viewport.Size
	viewport.Size = UDim2.new(0, 0, 0, 0)

	local tweenIn = TweenService:Create(viewport, TweenInfo.new(0.1), { Size = size })
	tweenIn:Play()

	if isFastHatch then
		tweenIn.Completed:Wait()
	else
		task.wait(0.5)
	end

	-- animated rotation shake effect with increasingly larger offsets
	local totalRotations = if isFastHatch then 2 else 8
	for i = 1, totalRotations do
		local angle = 5 + i * 8
		local tweenRotate = TweenService:Create(viewport, TweenInfo.new(0.1), { Rotation = angle })
		tweenRotate:Play()

		if tweenRotate.PlaybackState == Enum.PlaybackState.Playing then
			tweenRotate.Completed:Wait()
			HatchSFX.EggWobble:Play()
		end

		local tweenRotateBack = TweenService:Create(viewport, TweenInfo.new(0.1), { Rotation = -angle })
		tweenRotateBack:Play()

		if tweenRotateBack.PlaybackState == Enum.PlaybackState.Playing then
			tweenRotateBack.Completed:Wait()
			HatchSFX.EggWobble:Play()
		end
	end

	local tweenReset = TweenService:Create(viewport, TweenInfo.new(0.1 / 2), { Rotation = 0 })
	tweenReset:Play()
	tweenReset.Completed:Wait()

	if not isFastHatch then task.wait(0.1) end

	if item.Info.Rarity == "Exclusive" or item.Info.Rarity == "Brainrot God" then
		HatchSFX.UltraRareHatch:Play()
	elseif item.Info.Rarity == "Mythical" or item.Info.Rarity == "Legendary" then
		HatchSFX.RareHatch:Play()
	else
		HatchSFX.EggHatch:Play()
	end
	-- HatchSFX.EggHatch:Play()

	-- if not isFastHatch then
		local implode = TweenService:Create(viewport, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Size = UDim2.new(0, 0, 0, 0) })
		implode:Play()
		implode.Completed:Wait()
	-- end

	task.spawn(DisplayItem, item, viewport)

	local explodeTime = if isFastHatch then 0.2 else 0.4
	local explode = TweenService:Create(viewport, TweenInfo.new(explodeTime), { Size = UDim2.fromScale(2, 2), ImageTransparency = 1 })
	explode:Play()
	explode.Completed:Wait()
end

--// Functions \\--

local function PlayHatchAnimation(egg: Model, items: { GameTypes.EggItem }, hatchPerks: {}?)
	ClearHatchViewports()
	DarknessFadeIn()
	HatchScreen.Enabled = true
	HatchScreen:SetAttribute("Completed", false)

	local isFastHatch = isFastHatchEnabled()
	
	if Player:GetAttribute("AutoHatching") then
		HatchScreen.Auto.Visible = true
	else
		HatchScreen.Auto.Visible = false
	end

	print(hatchPerks)
	for _, perk in HatchScreen.Perks:GetChildren() do
		if perk:IsA("Frame") then
			perk.Visible = if hatchPerks and hatchPerks[perk.Name] then true else false
			print(perk.Name, perk.Visible)
		end
	end

	for index, item in items do
		local viewport = Template:Clone()
		viewport.Name = `EggViewport_{index}`
		viewport.Parent = HatchScreen

		local eggModel = EggModels:FindFirstChild(egg.Name)
		if not eggModel then
			warn(`Could not find egg model for`, egg)
			continue
		end

		SetupHatchViewport(viewport, eggModel, index, #items)

		task.spawn(AnimateEgg, viewport, item, isFastHatch)
	end

	local maxWait = if isFastHatch then 2.5 else 6
	local elapsed = 0

	while elapsed < maxWait do
		elapsed += task.wait()
	end

	HatchScreen.Auto.Visible = false

	ThrowAllViewports()
	task.wait(0.1)
	DarknessFadeOut()
end

--// Setup \\--

--// Return \\--

return {
	PlayHatchAnimation = PlayHatchAnimation,
	DarknessFadeIn = DarknessFadeIn,
	DarknessFadeOut = DarknessFadeOut,
}
