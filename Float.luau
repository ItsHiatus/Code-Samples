--// Services \\--

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Player = game:GetService("Players").LocalPlayer

--// Instances \\--

--// Variables \\--

local Floaters = {}

--// Functions \\--

local function IsCloseToPlayer(position: Vector3): boolean
    local character = Player.Character
    if not character then return false end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end

    return (humanoidRootPart.Position - position).Magnitude <= 100
end

--// Setup \\--

CollectionService:GetInstanceAddedSignal("EggFloat"):Connect(function(egg: Model)
    Floaters[egg] = egg:GetPivot()
end)
for _, egg in CollectionService:GetTagged("EggFloat") do
    Floaters[egg] = egg:GetPivot()
end

RunService.Heartbeat:Connect(function()
    local time = tick()
    local offset = math.sin(time * 2) * 0.5

    local cframeOffset = CFrame.new(0, offset, 0)
    local angle = CFrame.Angles(0, math.rad(time * 20 % 360), 0)

    for egg, cframe in pairs(Floaters) do
        if IsCloseToPlayer(cframe.Position) then
            local newCFrame = cframe * cframeOffset * angle
            egg:PivotTo(newCFrame)
        end
    end
end)

--// Return \\--

return {
    Eggs = Floaters,
}