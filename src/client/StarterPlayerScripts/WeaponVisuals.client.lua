-- LOCATION: StarterPlayer/StarterPlayerScripts/WeaponVisuals.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Visuals = Remotes:WaitForChild("WeaponVisuals")

-- [userId] = { aura = { adorn=..., baseRadius=number, current=number, color=Color3 } }
local active = {}

local function getPlayerByUserId(uid)
    return Players:GetPlayerByUserId(uid)
end

local function getCharacterByUserId(uid)
    local plr = getPlayerByUserId(uid)
    return plr and plr.Character or nil
end

local function getAuraMulFor(uid)
    local plr = getPlayerByUserId(uid)
    if not plr then
        return 1
    end
    return plr:GetAttribute("AuraRadiusMul") or 1
end

local function ensureAura(uid, baseRadius, color)
    active[uid] = active[uid] or {}
    if active[uid].aura and active[uid].aura.adorn then
        -- update base + color; radius will be smoothed in RenderStepped
        active[uid].aura.baseRadius = baseRadius
        active[uid].aura.color = color
        active[uid].aura.adorn.Color3 = color
        return
    end

    local char = getCharacterByUserId(uid)
    if not char then
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    local adorn = Instance.new("CylinderHandleAdornment")
    adorn.Name = "AuraVisual"
    adorn.Adornee = hrp
    adorn.Radius = baseRadius
    adorn.Height = 0.15
    adorn.Color3 = color
    adorn.Transparency = 0.8

    adorn.ZIndex = 1
    adorn.AlwaysOnTop = false
    -- lower & rotate flat
    adorn.CFrame = CFrame.new(0, -2.6, 0) * CFrame.Angles(math.rad(-90), 0, 0)
    adorn.Parent = hrp

    active[uid].aura = {
        adorn = adorn,
        baseRadius = baseRadius,
        current = baseRadius, -- visual current radius (for smoothing)
        color = color,
    }
end

local function removeAura(uid)
    if active[uid] and active[uid].aura then
        local adorn = active[uid].aura.adorn
        if adorn then
            adorn:Destroy()
        end
        active[uid].aura = nil
    end
end

local function clearForUser(uid)
    if active[uid] then
        for _, rec in pairs(active[uid]) do
            if rec.adorn then
                rec.adorn:Destroy()
            end
        end
    end
    active[uid] = nil
end

-- Smoothly ease current -> target using exponential decay
local function expEase(current, target, speed, dt)
    -- alpha = 1 - e^(-k*dt)
    local alpha = 1 - math.exp(-math.max(0, speed) * math.max(0, dt))
    return current + (target - current) * alpha
end

-- Visual update loop
RunService.RenderStepped:Connect(function(dt)
    for uid, slots in pairs(active) do
        -- if character despawned, clean
        local char = getCharacterByUserId(uid)
        if not char then
            removeAura(uid)
        else
            local aura = slots.aura
            if aura and aura.adorn and aura.adorn.Parent then
                -- target = baseRadius * multiplier (replicated Player Attribute)
                local mul = getAuraMulFor(uid)
                local target = (aura.baseRadius or aura.current or 12) * (mul or 1)

                -- smooth towards target
                aura.current = expEase(aura.current or target, target, 12, dt) -- speed=12 looks snappy

                -- apply
                aura.adorn.Radius = aura.current
            end
        end
    end
end)

Visuals.OnClientEvent:Connect(function(msg)
    if msg.action == "equip" and msg.weaponId == "Aura" then
        local p = msg.params or {}
        -- store the BASE radius from server (weapon config), visuals will multiply by AuraRadiusMul
        local base = p.Radius or 12
        local color = p.Color or Color3.fromRGB(41, 214, 241)
        ensureAura(msg.userId, base, color)

    elseif msg.action == "unequip" and msg.weaponId == "Aura" then
        removeAura(msg.userId)

    elseif msg.action == "clearForUser" then
        clearForUser(msg.userId)
    end
end)

-- Keep visuals alive when characters respawn
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        local uid = plr.UserId
        local rec = active[uid] and active[uid].aura
        if rec and rec.baseRadius and rec.color then
            -- re-create adorn on new character
            ensureAura(uid, rec.baseRadius, rec.color)
        end
    end)
end)
