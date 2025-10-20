local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LevelUp = Remotes:WaitForChild("LevelUp")
local LevelChoice = Remotes:WaitForChild("LevelChoice")
local XPChanged = Remotes:WaitForChild("XPChanged")

local function req(name)
    local mods = ReplicatedStorage:FindFirstChild("Modules")
    if mods and mods:FindFirstChild(name) then
        return require(mods[name])
    end
    local m = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name, true)
    assert(m and m:IsA("ModuleScript"), ("Module '%s' not found"):format(name))
    return require(m)
end

local LevelUI = req("LevelUI")
local LevelChoiceUI = req("LevelChoiceUI")

local bar = LevelUI.new(playerGui)
local chooser = LevelChoiceUI.new(playerGui)

local DEFAULT_CHOICES = {
    { id = "AURA_RADIUS", name = "Aura Size", color = Color3.fromRGB(0, 170, 255) },
    { id = "AURA_DAMAGE", name = "Aura Damage", color = Color3.fromRGB(255, 120, 0) },
    { id = "AURA_SPEED", name = "Aura Attack Speed", color = Color3.fromRGB(140, 100, 255) },
    { id = "PICKUP_MULT", name = "Pickup Range ×", color = Color3.fromRGB(0, 200, 100) },
}

local function normalizePayload(p)
    p = p or {}
    local list = p.choices
    if typeof(list) ~= "table" or #list == 0 then
        list = DEFAULT_CHOICES
    end
    return { choices = list }
end

XPChanged.OnClientEvent:Connect(function(payload)
    bar:SetProgress(payload.xp, payload.level, payload.next)
end)

-- Queue + show
local queue = {}
local showing = false
local lastShowTick = 0

local function showNext()
    if showing or #queue == 0 then
        return
    end
    showing = true
    lastShowTick = os.clock()

    local payload = table.remove(queue, 1)
    local norm = normalizePayload(payload)

    chooser:Show(norm.choices, function(choiceId)
        LevelChoice:FireServer(choiceId)
        task.defer(function()
            showing = false
            showNext()
        end)
    end)
end

-- Safety: if we somehow queued but didn’t show (UI got hidden by something),
-- force it after 0.5s.
RunService.RenderStepped:Connect(function()
    if not showing and #queue > 0 and (os.clock() - lastShowTick) > 0.5 then
        print("[LevelFlow] watchdog kick — forcing next dialog")
        showNext()
    end
end)

LevelUp.OnClientEvent:Connect(function(payload)
    table.insert(queue, payload or {})
    print(('[LevelFlow] LevelUp received; queued=%d'):format(#queue))
    if not showing then
        task.defer(showNext)
    end
end)
