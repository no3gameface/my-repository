local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelService = {}
LevelService.__index = LevelService

-- === Config ===
local CardConfig = require(script:WaitForChild("CardConfig"))
local DEFAULT_PICKUP_BASE = CardConfig.DEFAULT_PICKUP_BASE or 10

local function threshold(level)
    local f = CardConfig.LEVEL_THRESHOLD
    return (type(f) == "function") and f(level) or (100 * level)
end

-- Index cards by id for quick lookup (and keep array order for UI)
local CARDS = CardConfig.CARDS or {}
local CARD_BY_ID = {}
for _, c in ipairs(CARDS) do
    CARD_BY_ID[c.id] = c
end

-- === Remotes (owned by LevelService) ===
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name, Remotes.Parent = "Remotes", ReplicatedStorage
local XPChanged = Remotes:FindFirstChild("XPChanged") or Instance.new("RemoteEvent", Remotes)
XPChanged.Name = "XPChanged"
local LevelUp = Remotes:FindFirstChild("LevelUp") or Instance.new("RemoteEvent", Remotes)
LevelUp.Name = "LevelUp"
local LevelChoice = Remotes:FindFirstChild("LevelChoice") or Instance.new("RemoteEvent", Remotes)
LevelChoice.Name = "LevelChoice"

-- ===== State =====
-- rec[plr] = { xp, level, pending, awaiting, pickupBase, pickupMul, auraMul }
local rec = {}

-- ===== Helpers =====
local function effectivePickupRadius(r)
    return (r.pickupBase or DEFAULT_PICKUP_BASE) * (r.pickupMul or 1)
end

local function writeAuraAttributes(plr, mul)
    plr:SetAttribute("AuraRadiusMul", (mul.rad or 1))
    plr:SetAttribute("AuraDamageMul", (mul.dmg or 1))
    plr:SetAttribute("AuraAtkSpeedMul", (mul.atk or 1))
end

local function writePickupRadiusAttr(plr, r)
    plr:SetAttribute("PickupRadius", effectivePickupRadius(r))
end

local function sendProgress(plr, r)
    XPChanged:FireClient(plr, {
        xp = r.xp,
        level = r.level,
        next = threshold(r.level),
    })
end

local function choicesPayload()
    -- Build from master config
    local list = {}
    for _, c in ipairs(CARDS) do
        list[#list + 1] = {
            id = c.id,
            name = c.name,
            color = c.color,
        }
    end
    return list
end

local function sendLevelChoice(plr, r)
    if not r or r.awaiting or (r.pending or 0) <= 0 then
        return
    end
    r.awaiting = true
    LevelUp:FireClient(plr, {
        level = r.level,
        choices = choicesPayload(),
    })
end

-- Apply a chosen card to player's record using config
local function applyCard(plr, r, card)
    if not card then
        return
    end

    -- Custom apply function takes precedence (optional in config)
    if typeof(card.apply) == "function" then
        card.apply(plr, r)
        return
    end

    -- Generic multiplier to a path in the record
    local path = card.stat
    local mult = tonumber(card.mult) or 1
    if typeof(path) == "table" and #path > 0 then
        local t = r
        for i = 1, (#path - 1) do
            local key = path[i]
            t[key] = t[key] or {}
            t = t[key]
        end
        local leaf = path[#path]
        t[leaf] = (t[leaf] or 1) * mult
    end
end

-- ===== Public: AddXP =====
function LevelService.AddXP(plr, amount)
    local r = rec[plr]
    if not r then
        return
    end
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return
    end

    r.xp += amount
    local gained = 0
    while r.xp >= threshold(r.level) do
        r.xp -= threshold(r.level)
        r.level += 1
        gained += 1
    end
    if gained > 0 then
        r.pending = (r.pending or 0) + gained
    end

    sendProgress(plr, r)
    if not r.awaiting and r.pending and r.pending > 0 then
        sendLevelChoice(plr, r)
    end
end

-- ===== Level choice handling =====
LevelChoice.OnServerEvent:Connect(function(plr, choiceId)
    local r = rec[plr]
    if not r then
        return
    end

    local card = CARD_BY_ID[choiceId]
    if not card then
        return
    end

    applyCard(plr, r, card)

    -- Refresh attributes/UI
    r.auraMul = r.auraMul or { rad = 1, dmg = 1, atk = 1 }
    writeAuraAttributes(plr, r.auraMul)
    writePickupRadiusAttr(plr, r)
    sendProgress(plr, r)

    r.awaiting = false
    r.pending = math.max(0, (r.pending or 0) - 1)
    if r.pending > 0 then
        task.defer(sendLevelChoice, plr, r)
    end
end)

-- ===== Init / teardown =====
function LevelService.Init()
    Players.PlayerAdded:Connect(function(plr)
        rec[plr] = {
            xp = 0,
            level = 1,
            pending = 0,
            awaiting = false,
            pickupBase = DEFAULT_PICKUP_BASE,
            pickupMul = 1,
            auraMul = { rad = 1, dmg = 1, atk = 1 },
        }
        writeAuraAttributes(plr, rec[plr].auraMul)
        writePickupRadiusAttr(plr, rec[plr])
        sendProgress(plr, rec[plr])
    end)

    Players.PlayerRemoving:Connect(function(plr)
        rec[plr] = nil
    end)

    for _, plr in ipairs(Players:GetPlayers()) do
        if not rec[plr] then
            rec[plr] = {
                xp = 0,
                level = 1,
                pending = 0,
                awaiting = false,
                pickupBase = DEFAULT_PICKUP_BASE,
                pickupMul = 1,
                auraMul = { rad = 1, dmg = 1, atk = 1 },
            }
            writeAuraAttributes(plr, rec[plr].auraMul)
            writePickupRadiusAttr(plr, rec[plr])
            sendProgress(plr, rec[plr])
        end
    end
end

-- ===== Optional helpers / getters =====
function LevelService.SetPickupRadius(plr, radius)
    local r = rec[plr]
    if not r then
        return
    end
    r.pickupBase = math.max(0, tonumber(radius) or DEFAULT_PICKUP_BASE)
    writePickupRadiusAttr(plr, r)
end

function LevelService.AddPickupRadius(plr, delta)
    local r = rec[plr]
    if not r then
        return
    end
    r.pickupBase = math.max(0, (r.pickupBase or DEFAULT_PICKUP_BASE) + (delta or 0))
    writePickupRadiusAttr(plr, r)
end

function LevelService.GetXP(plr)
    local r = rec[plr]
    return r and r.xp or 0
end

function LevelService.GetLevel(plr)
    local r = rec[plr]
    return r and r.level or 1
end

function LevelService.NextXP(plr)
    local r = rec[plr]
    return r and threshold(r.level) or 100
end

return LevelService
