--[[ Sleepy Enhancements v4 — Rivals (crash-hardened)
     RightShift — menu
     Startup is now safe: no CoreGui sweep, lazy ESP/FOV/hitbox,
     one heartbeat, everything pcall'd, re-run cleanup.
]]

-- ============================================================
-- 0. RE-RUN CLEANUP
-- ============================================================
if _G.SleepyEnhancements and _G.SleepyEnhancements.Cleanup then
    pcall(_G.SleepyEnhancements.Cleanup)
end
_G.SleepyEnhancements = { Connections = {}, RenderBinds = {}, Drawings = {}, Cleanup = nil }

-- ============================================================
-- 1. LIBRARY LOAD (with fallbacks)
-- ============================================================
local LibSources = {
    "https://raw.githubusercontent.com/ofugii/Unnamed-Linoria/main/",
    "https://raw.githubusercontent.com/lnxcz/LinoriaLib/main/",
    "https://raw.githubusercontent.com/NoTwistedHere/Linoria/main/",
}

local Library, ThemeManager, SaveManager
for _, src in ipairs(LibSources) do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(src .. "Library.lua"))()
    end)
    if ok and lib then
        Library = lib
        pcall(function()
            ThemeManager = loadstring(game:HttpGet(src .. "addons/ThemeManager.lua"))()
        end)
        pcall(function()
            SaveManager = loadstring(game:HttpGet(src .. "addons/SaveManager.lua"))()
        end)
        break
    end
end

if not Library then
    return warn("[Sleepy] library load failed — check executor/connection.")
end

-- ============================================================
-- 2. SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local VirtualUser       = game:GetService("VirtualUser")

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local HAS_DRAWING = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function")

-- ============================================================
-- 3. CONFIG
-- ============================================================
local Config = {
    -- Aim
    AimBot        = false,
    AimPart       = "Head",
    AimFOV        = 150,
    AimSmooth     = 0.45,
    AimPrediction = 0.06,
    AimTeamCheck  = true,
    AimWallCheck  = false,
    AimSticky     = 0.15,
    AimShowFOV    = true,
    AimFOVColor   = Color3.fromRGB(255, 255, 255),
    -- Silent
    SilentAim     = false,
    SilentPart    = "HumanoidRootPart",
    SilentHitChance = 100,
    -- Rage
    RageBot       = false,
    RageFireRate  = 0.05,
    RagePart      = "Head",
    RageTeleport  = false,
    -- Skin
    SkinChanger   = false,
    SelectedSkin  = "Default",
    -- Spoofer
    Spoofer       = false,
    SpoofedUserId = 123456789,
    -- ESP
    ESPBox    = false,
    ESPName   = false,
    ESPHealth = false,
    ESPTracer = false,
    ESPColor  = Color3.fromRGB(255, 255, 255),
    -- Hitbox
    HitboxEnabled = false,
    HitboxSize    = 5,
    -- Parry
    AutoParry  = false,
    ParryRange = 12,
    -- Misc
    AntiAFK    = true,
    WalkSpeed  = 16,
    JumpPower  = 50,
    Noclip     = false,
    Fly        = false,
    FlySpeed   = 60,
    -- Throttle
    ESPThrottle    = 1 / 20,
    HitboxThrottle = 1 / 10,
}

local aimHeld     = false
local aimBindName = "MB2"

-- ============================================================
-- 4. HELPERS (pure)
-- ============================================================
local function getChar(plr) return plr and plr.Character end
local function getHum(plr)  local c = getChar(plr); return c and c:FindFirstChildOfClass("Humanoid") end
local function getHRP(plr)  local c = getChar(plr); return c and c:FindFirstChild("HumanoidRootPart") end

local function isAlive(plr)
    local h = getHum(plr); return h ~= nil and h.Health > 0
end

local function isTeammate(plr)
    if not Config.AimTeamCheck then return false end
    local a, b = LP.Team, plr.Team
    return a ~= nil and b ~= nil and a == b
end

local function hasLOS(part)
    if not Config.AimWallCheck then return true end
    if not part or not part.Parent then return false end
    local origin = Camera.CFrame.Position
    local ok, hit = pcall(function()
        return Workspace:FindPartOnRayWithIgnoreList(
            Ray.new(origin, part.Position - origin),
            { LP.Character, Camera }
        )
    end)
    if not ok then return true end
    return hit == nil or hit:IsDescendantOf(part.Parent)
end

local function viewportCenter()
    local vp = Camera.ViewportSize
    local insetY = 0
    pcall(function() insetY = GuiService:GetGuiInset().Y end)
    return Vector2.new(vp.X * 0.5, vp.Y * 0.5 + insetY * 0.5)
end

local function screenDist(worldPos)
    local s, on = Camera:WorldToViewportPoint(worldPos)
    if not on or s.Z <= 0 then return math.huge end
    local d = Vector2.new(s.X, s.Y) - viewportCenter()
    return d.Magnitude
end

local function getAimPart(plr, name)
    local c = getChar(plr)
    if not c then return nil end
    return c:FindFirstChild(name) or c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
-- 5. INPUT
-- ============================================================
local function parseBind(name)
    if name == "MB1" then return Enum.UserInputType.MouseButton1 end
    if name == "MB2" then return Enum.UserInputType.MouseButton2 end
    if name == "MB3" then return Enum.UserInputType.MouseButton3 end
    if Enum.KeyCode[name] then return Enum.KeyCode[name] end
    return Enum.UserInputType.MouseButton2
end

local function bindDown()
    local b = parseBind(aimBindName)
    if b.EnumType == Enum.UserInputType then
        return UserInputService:IsMouseButtonPressed(b)
    end
    return UserInputService:IsKeyDown(b)
end

local inputBeganConn = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    local b = parseBind(aimBindName)
    if input.UserInputType == b or input.KeyCode == b then aimHeld = true end
    if Config.SilentAim and input.UserInputType == Enum.UserInputType.MouseButton1 then
        task.spawn(function() pcall(silentFire) end)
    end
end)
table.insert(_G.SleepyEnhancements.Connections, inputBeganConn)

local inputEndedConn = UserInputService.InputEnded:Connect(function(input)
    local b = parseBind(aimBindName)
    if input.UserInputType == b or input.KeyCode == b then aimHeld = false end
end)
table.insert(_G.SleepyEnhancements.Connections, inputEndedConn)

-- ============================================================
-- 6. AIMBOT (BindToRenderStep Camera+1, guarded)
-- ============================================================
local stickyTarget, stickyUntil = nil, 0

local function findAimTarget()
    if stickyTarget and tick() < stickyUntil
       and isAlive(stickyTarget) and not isTeammate(stickyTarget) then
        local p = getAimPart(stickyTarget, Config.AimPart)
        if p and p.Parent and hasLOS(p) and screenDist(p.Position) <= Config.AimFOV then
            return p
        end
    end
    local best, bestPart, bestScore = nil, nil, Config.AimFOV
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) and not isTeammate(plr) then
            local p = getAimPart(plr, Config.AimPart)
            if p and hasLOS(p) then
                local sc = screenDist(p.Position)
                if sc < bestScore then
                    bestScore, best, bestPart = sc, plr, p
                end
            end
        end
    end
    if best then
        stickyTarget = best
        stickyUntil = tick() + Config.AimSticky
    end
    return bestPart
end

local function aimStep(dt)
    if not Config.AimBot then return end
    if not (aimHeld or bindDown()) then return end
    local part = findAimTarget()
    if not part then return end

    local origin = Camera.CFrame.Position
    local aimPos = part.Position
    if Config.AimPrediction > 0 then
        local v = part.AssemblyLinearVelocity
        if v then aimPos = aimPos + v * Config.AimPrediction end
    end
    local delta = aimPos - origin
    if delta.Magnitude < 0.1 then return end
    if math.abs(delta.Unit.Y) > 0.995 then return end

    local desired = CFrame.lookAt(origin, aimPos, Camera.CFrame.UpVector)
    local alpha = 1 - math.pow(1 - Config.AimSmooth, dt * 60)
    Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)
end

pcall(function()
    RunService:UnbindFromRenderStep("Sleepy_AimCamera")
end)
pcall(function()
    RunService:BindToRenderStep("Sleepy_AimCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
        pcall(aimStep, dt)
    end)
end)
table.insert(_G.SleepyEnhancements.RenderBinds, "Sleepy_AimCamera")

-- ============================================================
-- 7. SILENT AIM (defined early for input hook)
-- ============================================================
function silentFire()
    if not Config.SilentAim then return end
    if math.random(1, 100) > Config.SilentHitChance then return end
    local bestPart, bestScore = nil, Config.AimFOV
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) and not isTeammate(plr) then
            local p = getAimPart(plr, Config.SilentPart)
            if p then
                local sc = screenDist(p.Position)
                if sc < bestScore then bestScore, bestPart = sc, p end
            end
        end
    end
    if not bestPart then return end
    local old = Camera.CFrame
    Camera.CFrame = CFrame.lookAt(old.Position, bestPart.Position, old.UpVector)
    RunService.RenderStepped:Wait()
    Camera.CFrame = old
end

-- ============================================================
-- 8. FOV CIRCLE (lazy, guarded)
-- ============================================================
local fovCircle = nil
local function ensureFOV()
    if fovCircle then return fovCircle end
    if not HAS_DRAWING then return nil end
    local ok, c = pcall(function()
        local d = Drawing.new("Circle")
        d.Thickness = 1.5
        d.Filled = false
        d.Transparency = 1
        d.Color = Config.AimFOVColor
        d.Visible = false
        return d
    end)
    if ok and c then
        fovCircle = c
        table.insert(_G.SleepyEnhancements.Drawings, c)
    end
    return fovCircle
end

-- ============================================================
-- 9. ESP (lazy, guarded)
-- ============================================================
local espCache = {}

local function makeESP(plr)
    if espCache[plr] then return end
    if not HAS_DRAWING then return end
    local e = {}
    local ok = pcall(function()
        local box = Drawing.new("Square")
        box.Thickness = 1.5; box.Filled = false; box.Transparency = 1
        box.Color = Config.ESPColor; box.Visible = false
        e.box = box

        local name = Drawing.new("Text")
        name.Size = 14; name.Center = true; name.Outline = true
        name.OutlineColor = Color3.new(0, 0, 0)
        name.Color = Config.ESPColor; name.Visible = false
        e.name = name

        local hp = Drawing.new("Text")
        hp.Size = 14; hp.Center = true; hp.Outline = true
        hp.OutlineColor = Color3.new(0, 0, 0)
        hp.Color = Color3.new(0, 1, 0); hp.Visible = false
        e.health = hp

        local tr = Drawing.new("Line")
        tr.Thickness = 1.5; tr.Transparency = 1
        tr.Color = Config.ESPColor; tr.Visible = false
        e.tracer = tr
    end)
    if not ok then return end
    espCache[plr] = e
    table.insert(_G.SleepyEnhancements.Drawings, e.box)
    table.insert(_G.SleepyEnhancements.Drawings, e.name)
    table.insert(_G.SleepyEnhancements.Drawings, e.health)
    table.insert(_G.SleepyEnhancements.Drawings, e.tracer)
end

local function removeESP(plr)
    local e = espCache[plr]
    if not e then return end
    for _, d in pairs(e) do pcall(function() d:Remove() end) end
    espCache[plr] = nil
end

local function hideESP(e)
    e.box.Visible = false; e.name.Visible = false
    e.health.Visible = false; e.tracer.Visible = false
end

local espErrorCount = 0
local function updateESP()
    if not HAS_DRAWING then return end
    local wantBox, wantName = Config.ESPBox, Config.ESPName
    local wantHp, wantTracer = Config.ESPHealth, Config.ESPTracer
    local active = wantBox or wantName or wantHp or wantTracer

    for plr, e in pairs(espCache) do
        if not active or not isAlive(plr) then
            hideESP(e)
        else
            local c = getChar(plr)
            local head = c and c:FindFirstChild("Head")
            local hrp  = c and c:FindFirstChild("HumanoidRootPart")
            local hum  = c and c:FindFirstChildOfClass("Humanoid")
            if not (head and hrp and hum) then
                hideESP(e)
            else
                local sp,  on  = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local sp2, on2 = Camera:WorldToViewportPoint(hrp.Position  - Vector3.new(0, 3, 0))
                if on and on2 then
                    local h = sp2.Y - sp.Y
                    local w = h * 0.55
                    local team = isTeammate(plr)
                    e.box.Size = Vector2.new(w, h)
                    e.box.Position = Vector2.new(sp.X - w * 0.5, sp.Y)
                    e.box.Visible = wantBox and not team
                    e.name.Text = plr.Name
                    e.name.Position = Vector2.new(sp.X, sp.Y - 16)
                    e.name.Visible = wantName and not team
                    e.health.Text = tostring(math.floor(hum.Health))
                    e.health.Position = Vector2.new(sp.X - w * 0.5 - 18, sp.Y)
                    e.health.Color = Color3.fromRGB(
                        255 - hum.Health * 2.55,
                        hum.Health * 2.55, 0
                    )
                    e.health.Visible = wantHp and not team
                    local ctr = viewportCenter()
                    e.tracer.From = Vector2.new(ctr.X, Camera.ViewportSize.Y)
                    e.tracer.To = Vector2.new(sp.X, sp.Y)
                    e.tracer.Visible = wantTracer and not team
                else
                    hideESP(e)
                end
            end
        end
    end
end

-- ============================================================
-- 10. HITBOX (only when enabled, capped work)
-- ============================================================
local hitboxCache = setmetatable({}, { __mode = "k" })

local function restoreAllHitboxes()
    for part, size in pairs(hitboxCache) do
        pcall(function()
            if part and part.Parent then
                part.Size = size
                part.Transparency = 0
            end
        end)
    end
    hitboxCache = setmetatable({}, { __mode = "k" })
end

local function applyHitbox()
    if not Config.HitboxEnabled then return end
    local scale = Config.HitboxSize / 2
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) and not isTeammate(plr) then
            local c = getChar(plr)
            if c then
                for _, part in ipairs(c:GetDescendants()) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        if not hitboxCache[part] then
                            hitboxCache[part] = part.Size
                        end
                        local want = hitboxCache[part] * scale
                        if part.Size ~= want then
                            pcall(function()
                                part.Size = want
                                part.Transparency = 0.7
                                part.CanCollide = false
                            end)
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================
-- 11. AUTO PARRY
-- ============================================================
local parryRemote
pcall(function()
    for _, name in ipairs({"Parry", "Block", "Combat", "ParryRemote"}) do
        local f = ReplicatedStorage:FindFirstChild(name, true)
        if f and (f:IsA("RemoteEvent") or f:IsA("RemoteFunction")) then
            parryRemote = f
            break
        end
    end
end)

local lastParry = 0
local function tryParry()
    if not Config.AutoParry or not parryRemote then return end
    if tick() - lastParry < 0.15 then return end
    local myHrp = getHRP(LP)
    if not myHrp then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) then
            local hrp = getHRP(plr)
            if hrp and (hrp.Position - myHrp.Position).Magnitude <= Config.ParryRange then
                pcall(function() parryRemote:FireServer() end)
                lastParry = tick()
                return
            end
        end
    end
end

-- ============================================================
-- 12. RAGEBOT (threaded, stoppable)
-- ============================================================
local rageThread
local function startRageBot()
    if rageThread then return end
    Config.RageBot = true
    rageThread = task.spawn(function()
        while Config.RageBot do
            local bestPart, bestScore = nil, math.huge
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and isAlive(plr) then
                    local p = getAimPart(plr, Config.RagePart)
                    if p then
                        local sc = screenDist(p.Position)
                        if sc < bestScore then bestScore, bestPart = sc, p end
                    end
                end
            end
            if bestPart then
                if Config.RageTeleport then
                    local hrp = getHRP(LP)
                    if hrp then
                        pcall(function()
                            hrp.CFrame = bestPart.CFrame * CFrame.new(0, 2, 4)
                        end)
                    end
                end
                local old = Camera.CFrame
                Camera.CFrame = CFrame.lookAt(old.Position, bestPart.Position, old.UpVector)
                task.wait(Config.RageFireRate)
                Camera.CFrame = old
            end
            task.wait(Config.RageFireRate)
        end
        rageThread = nil
    end)
end

local function stopRageBot()
    Config.RageBot = false
    if rageThread then
        pcall(task.cancel, rageThread)
        rageThread = nil
    end
end

-- ============================================================
-- 13. SKINCHANGER
-- ============================================================
local SKINS = {
    Default = { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(200,200,200) },
    Neon    = { Material = Enum.Material.Neon,          Color = Color3.fromRGB(180,80,255) },
    Gold    = { Material = Enum.Material.Metal,         Color = Color3.fromRGB(255,200,50) },
    Crimson = { Material = Enum.Material.Neon,          Color = Color3.fromRGB(220,30,30) },
    Void    = { Material = Enum.Material.ForceField,    Color = Color3.fromRGB(20,20,40) },
    Ice     = { Material = Enum.Material.Glass,         Color = Color3.fromRGB(180,220,255) },
    Toxic   = { Material = Enum.Material.Neon,          Color = Color3.fromRGB(120,255,50) },
}

local function applySkin(name)
    local c = getChar(LP)
    if not c then return end
    local def = SKINS[name] or SKINS.Default
    for _, tool in ipairs(c:GetChildren()) do
        if tool:IsA("Tool") then
            local handle = tool:FindFirstChild("Handle")
            if handle then
                pcall(function()
                    handle.Material = def.Material
                    handle.Color = def.Color
                end)
            end
        end
    end
end

-- ============================================================
-- 14. SPOOFER (one-time hook)
-- ============================================================
local spoofHooked = false
local function enableSpoofer()
    if spoofHooked or not (setmetatable and getrawmetatable) then return end
    local ok = pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        local oldIndex = mt.__index
        mt.__index = newcclosure(function(self, key)
            if self == LP and key == "UserId" and Config.Spoofer then
                return Config.SpoofedUserId
            end
            return oldIndex(self, key)
        end)
        setreadonly(mt, true)
    end)
    spoofHooked = ok
end

-- ============================================================
-- 15. NOCLIP (apply once on toggle — not per-frame)
-- ============================================================
local function applyNoclip()
    local c = getChar(LP)
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function() part.CanCollide = not Config.Noclip end)
        end
    end
end

-- ============================================================
-- 16. FLY
-- ============================================================
local flyBodyVel, flyBodyGyro
local function stopFly()
    if flyBodyVel then pcall(function() flyBodyVel:Destroy() end); flyBodyVel = nil end
    if flyBodyGyro then pcall(function() flyBodyGyro:Destroy() end); flyBodyGyro = nil end
end

local function startFly()
    stopFly()
    local hrp = getHRP(LP)
    if not hrp then return end
    pcall(function()
        flyBodyVel = Instance.new("BodyVelocity")
        flyBodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        flyBodyVel.Velocity = Vector3.zero
        flyBodyVel.Parent = hrp

        flyBodyGyro = Instance.new("BodyGyro")
        flyBodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
        flyBodyGyro.CFrame = hrp.CFrame
        flyBodyGyro.Parent = hrp
    end)
end

-- ============================================================
-- 17. UI
-- ============================================================
local Window = Library:CreateWindow({
    Title = "Sleepy Enhancements",
    Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2,
})

local Tabs = {
    Combat   = Window:AddTab("Combat"),
    Visuals  = Window:AddTab("Visuals"),
    Skins    = Window:AddTab("Skins"),
    Misc     = Window:AddTab("Misc"),
    Settings = Window:AddTab("Settings"),
}

-- ---------- COMBAT ----------
local aimGroup = Tabs.Combat:AddLeftGroupbox("Aimbot")
aimGroup:AddToggle("AimBot", { Text = "Aimbot", Default = Config.AimBot, Callback = function(v) Config.AimBot = v end })
aimGroup:AddDropdown("AimPart", { Text = "Aim Part", Values = {"Head","HumanoidRootPart","UpperTorso"}, Default = Config.AimPart, Callback = function(v) Config.AimPart = v end })
aimGroup:AddSlider("AimFOV", { Text = "FOV (px)", Min = 20, Max = 600, Default = Config.AimFOV, Rounding = 0, Callback = function(v) Config.AimFOV = v end })
aimGroup:AddSlider("AimSmooth", { Text = "Smoothness", Min = 0.05, Max = 0.95, Default = Config.AimSmooth, Rounding = 2, Callback = function(v) Config.AimSmooth = v end })
aimGroup:AddSlider("AimPrediction", { Text = "Prediction", Min = 0, Max = 0.4, Default = Config.AimPrediction, Rounding = 2, Callback = function(v) Config.AimPrediction = v end })
aimGroup:AddSlider("AimSticky", { Text = "Sticky (s)", Min = 0, Max = 0.5, Default = Config.AimSticky, Rounding = 2, Callback = function(v) Config.AimSticky = v end })
aimGroup:AddToggle("AimTeam", { Text = "Team Check", Default = Config.AimTeamCheck, Callback = function(v) Config.AimTeamCheck = v end })
aimGroup:AddToggle("AimWall", { Text = "Wall Check", Default = Config.AimWallCheck, Callback = function(v) Config.AimWallCheck = v end })
aimGroup:AddToggle("AimFOVShow", { Text = "Show FOV Circle", Default = Config.AimShowFOV, Callback = function(v) Config.AimShowFOV = v end })
aimGroup:AddColorPicker("AimFOVColor", { Text = "FOV Color", Default = Config.AimFOVColor, Callback = function(v)
    Config.AimFOVColor = v
    if fovCircle then pcall(function() fovCircle.Color = v end) end
end })
local aimKeyPicker = aimGroup:AddKeyPicker("AimKey", {
    Text = "Aim Bind",
    Default = "MB2",
    Mode = "Hold",
    NoUI = false,
    SyncToggleEvent = false,
    Callback = function(v)
        if type(v) == "table" and v.Value then
            aimBindName = v.Value
        elseif type(v) == "string" then
            aimBindName = v
        end
    end,
})
if aimKeyPicker then
    pcall(function()
        if aimKeyPicker.Value then aimBindName = aimKeyPicker.Value end
    end)
end

local silentGroup = Tabs.Combat:AddRightGroupbox("Silent Aim")
silentGroup:AddToggle("SilentAim", { Text = "Silent Aim", Default = Config.SilentAim, Callback = function(v) Config.SilentAim = v end })
silentGroup:AddDropdown("SilentPart", { Text = "Hit Part", Values = {"Head","HumanoidRootPart","UpperTorso"}, Default = Config.SilentPart, Callback = function(v) Config.SilentPart = v end })
silentGroup:AddSlider("SilentChance", { Text = "Hit Chance %", Min = 1, Max = 100, Default = Config.SilentHitChance, Rounding = 0, Callback = function(v) Config.SilentHitChance = v end })

local rageGroup = Tabs.Combat:AddLeftGroupbox("RageBot")
rageGroup:AddToggle("RageBot", { Text = "RageBot", Default = Config.RageBot, Callback = function(v)
    if v then startRageBot() else stopRageBot() end
end })
rageGroup:AddSlider("RageRate", { Text = "Fire Rate (s)", Min = 0.005, Max = 0.2, Default = Config.RageFireRate, Rounding = 3, Callback = function(v) Config.RageFireRate = v end })
rageGroup:AddDropdown("RagePart", { Text = "Hit Part", Values = {"Head","HumanoidRootPart","UpperTorso"}, Default = Config.RagePart, Callback = function(v) Config.RagePart = v end })
rageGroup:AddToggle("RageTeleport", { Text = "Teleport-behind", Default = Config.RageTeleport, Callback = function(v) Config.RageTeleport = v end })

local parryGroup = Tabs.Combat:AddRightGroupbox("Auto Parry")
parryGroup:AddToggle("AutoParry", { Text = "Auto Parry", Default = Config.AutoParry, Callback = function(v) Config.AutoParry = v end })
parryGroup:AddSlider("ParryRange", { Text = "Range", Min = 3, Max = 30, Default = Config.ParryRange, Rounding = 0, Callback = function(v) Config.ParryRange = v end })
parryGroup:AddLabel(parryRemote and ("Remote: " .. parryRemote.Name) or "Remote: NOT FOUND")

-- ---------- VISUALS ----------
local espGroup = Tabs.Visuals:AddLeftGroupbox("ESP")
espGroup:AddToggle("ESPBox",    { Text = "Box",    Default = Config.ESPBox,    Callback = function(v) Config.ESPBox = v end })
espGroup:AddToggle("ESPName",   { Text = "Name",   Default = Config.ESPName,   Callback = function(v) Config.ESPName = v end })
espGroup:AddToggle("ESPHealth", { Text = "Health", Default = Config.ESPHealth, Callback = function(v) Config.ESPHealth = v end })
espGroup:AddToggle("ESPTracer", { Text = "Tracer", Default = Config.ESPTracer, Callback = function(v) Config.ESPTracer = v end })
espGroup:AddColorPicker("ESPColor", { Text = "ESP Color", Default = Config.ESPColor, Callback = function(v)
    Config.ESPColor = v
    for _, e in pairs(espCache) do
        pcall(function()
            e.box.Color = v; e.name.Color = v; e.tracer.Color = v
        end)
    end
end })

local hitboxGroup = Tabs.Visuals:AddRightGroupbox("Hitbox Expander")
hitboxGroup:AddToggle("HitboxEnabled", { Text = "Enable", Default = Config.HitboxEnabled, Callback = function(v)
    Config.HitboxEnabled = v
    if not v then restoreAllHitboxes() end
end })
hitboxGroup:AddSlider("HitboxSize", { Text = "Size", Min = 2, Max = 20, Default = Config.HitboxSize, Rounding = 1, Callback = function(v) Config.HitboxSize = v end })

-- ---------- SKINS ----------
local skinGroup = Tabs.Skins:AddLeftGroupbox("Skinchanger")
skinGroup:AddToggle("SkinChanger", { Text = "Enable", Default = Config.SkinChanger, Callback = function(v)
    Config.SkinChanger = v
    if v then applySkin(Config.SelectedSkin) end
end })
skinGroup:AddDropdown("SkinSelect", {
    Text = "Skin",
    Values = {"Default","Neon","Gold","Crimson","Void","Ice","Toxic"},
    Default = Config.SelectedSkin,
    Callback = function(v)
        Config.SelectedSkin = v
        if Config.SkinChanger then applySkin(v) end
    end,
})
skinGroup:AddButton({ Text = "Reset to Default", Func = function() applySkin("Default") end })
skinGroup:AddLabel("Client-side: material/color of tool handle")

-- ---------- MISC ----------
local spoofGroup = Tabs.Misc:AddLeftGroupbox("Spoofer")
spoofGroup:AddToggle("Spoofer", { Text = "UserId Spoof", Default = Config.Spoofer, Callback = function(v)
    Config.Spoofer = v
    if v then enableSpoofer() end
end })
spoofGroup:AddInput("SpoofedId", { Text = "UserId", Default = tostring(Config.SpoofedUserId), Callback = function(v) Config.SpoofedUserId = tonumber(v) or Config.SpoofedUserId end })
spoofGroup:AddLabel("HWID: external tool (ByGone / ARES)")

local moveGroup = Tabs.Misc:AddRightGroupbox("Movement")
moveGroup:AddToggle("AntiAFK", { Text = "Anti-AFK", Default = Config.AntiAFK, Callback = function(v) Config.AntiAFK = v end })
moveGroup:AddSlider("WalkSpeed", { Text = "WalkSpeed", Min = 16, Max = 200, Default = Config.WalkSpeed, Rounding = 0, Callback = function(v) Config.WalkSpeed = v end })
moveGroup:AddSlider("JumpPower", { Text = "JumpPower", Min = 50, Max = 300, Default = Config.JumpPower, Rounding = 0, Callback = function(v) Config.JumpPower = v end })
moveGroup:AddToggle("Noclip", { Text = "Noclip", Default = Config.Noclip, Callback = function(v)
    Config.Noclip = v
    applyNoclip()
end })
moveGroup:AddToggle("Fly", { Text = "Fly", Default = Config.Fly, Callback = function(v)
    Config.Fly = v
    if v then startFly() else stopFly() end
end })
moveGroup:AddSlider("FlySpeed", { Text = "Fly Speed", Min = 10, Max = 200, Default = Config.FlySpeed, Rounding = 0, Callback = function(v) Config.FlySpeed = v end })

-- ---------- SETTINGS ----------
if ThemeManager then
    pcall(function()
        ThemeManager:SetLibrary(Library)
        ThemeManager:SetFolder("SleepyEnhancements/Rivals")
        ThemeManager:ApplyToTab(Tabs.Settings)
    end)
end
if SaveManager then
    pcall(function()
        SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({
            "MenuToggle","AimBot","SilentAim","RageBot","AutoParry",
            "HitboxEnabled","Noclip","Fly",
        })
        SaveManager:SetFolder("SleepyEnhancements/Rivals/Configs")
        SaveManager:BuildConfigSection(Tabs.Settings)
    end)
end

-- ============================================================
-- 18. WHITE THEME — ModifyTheme ONLY (no CoreGui sweep!)
-- ============================================================
pcall(function()
    Library:ModifyTheme({
        {"Menu Accent", "Accent",      Color3.fromRGB(255, 255, 255)},
        {"Menu Accent", "AccentDark",  Color3.fromRGB(220, 220, 220)},
        {"Menu Accent", "AccentLight", Color3.fromRGB(255, 255, 255)},
        {"Slider", "Fill",             Color3.fromRGB(255, 255, 255)},
        {"Slider", "Empty",            Color3.fromRGB(70, 70, 70)},
        {"Toggles", "Border",          Color3.fromRGB(255, 255, 255)},
        {"Button", "Main",             Color3.fromRGB(240, 240, 240)},
        {"Button", "Hover",            Color3.fromRGB(255, 255, 255)},
        {"Button", "Press",            Color3.fromRGB(200, 200, 200)},
        {"Button", "Text",             Color3.fromRGB(20, 20, 20)},
        {"Dropdown", "Border",         Color3.fromRGB(255, 255, 255)},
        {"TextBox",  "Border",         Color3.fromRGB(255, 255, 255)},
        {"KeyPicker", "Border",        Color3.fromRGB(255, 255, 255)},
    })
end)

-- ============================================================
-- 19. PLAYER LIFECYCLE
-- ============================================================
local function onPlayerAdded(plr)
    if plr ~= LP and HAS_DRAWING then makeESP(plr) end
end
local function onPlayerRemoving(plr)
    removeESP(plr)
end
for _, p in ipairs(Players:GetPlayers()) do onPlayerAdded(p) end
table.insert(_G.SleepyEnhancements.Connections,
    Players.PlayerAdded:Connect(onPlayerAdded))
table.insert(_G.SleepyEnhancements.Connections,
    Players.PlayerRemoving:Connect(onPlayerRemoving))

-- reapply noclip/skin on respawn
local function onCharacterAdded()
    task.wait(0.5)
    if Config.Noclip then applyNoclip() end
    if Config.SkinChanger then applySkin(Config.SelectedSkin) end
    if Config.Fly then startFly() end
end
local charConn = LP.CharacterAdded:Connect(onCharacterAdded)
table.insert(_G.SleepyEnhancements.Connections, charConn)

-- ============================================================
-- 20. HEARTBEAT (single loop, guarded, throttled)
-- ============================================================
local accESP, accHitbox, accParry, accAFK = 0, 0, 0, 0

local hbConn = RunService.Heartbeat:Connect(function(dt)
    -- movement
    local c = getChar(LP)
    if c then
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hum then
            if hum.WalkSpeed ~= Config.WalkSpeed then hum.WalkSpeed = Config.WalkSpeed end
            if hum.JumpPower  ~= Config.JumpPower then hum.JumpPower = Config.JumpPower end
        end
    end

    -- fly
    if Config.Fly and flyBodyVel then
        local camCF = Camera.CFrame
        local move = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - camCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + camCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0,1,0) end
        pcall(function()
            flyBodyVel.Velocity = move.Magnitude > 0 and move.Unit * Config.FlySpeed or Vector3.zero
        end)
    end

    -- ESP
    accESP = accESP + dt
    if accESP >= Config.ESPThrottle then
        accESP = 0
        pcall(updateESP)
        if Config.AimShowFOV and (Config.AimBot or Config.SilentAim) then
            local c2 = ensureFOV()
            if c2 then
                local ctr = viewportCenter()
                c2.Position = ctr
                c2.Radius = Config.AimFOV
                c2.Color = Config.AimFOVColor
                c2.Visible = true
            end
        elseif fovCircle then
            fovCircle.Visible = false
        end
    end

    -- hitbox (only work if enabled)
    if Config.HitboxEnabled then
        accHitbox = accHitbox + dt
        if accHitbox >= Config.HitboxThrottle then
            accHitbox = 0
            pcall(applyHitbox)
        end
    end

    -- parry
    if Config.AutoParry then
        accParry = accParry + dt
        if accParry >= 0.05 then
            accParry = 0
            pcall(tryParry)
        end
    end

    -- anti-afk
    accAFK = accAFK + dt
    if accAFK >= 60 then
        accAFK = 0
        if Config.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end
end)
table.insert(_G.SleepyEnhancements.Connections, hbConn)

-- ============================================================
-- 21. CLEANUP HANDLER (for re-runs)
-- ============================================================
_G.SleepyEnhancements.Cleanup = function()
    for _, c in ipairs(_G.SleepyEnhancements.Connections) do pcall(function() c:Disconnect() end) end
    for _, name in ipairs(_G.SleepyEnhancements.RenderBinds) do
        pcall(function() RunService:UnbindFromRenderStep(name) end)
    end
    for _, d in ipairs(_G.SleepyEnhancements.Drawings) do pcall(function() d:Remove() end) end
    stopRageBot(); stopFly(); restoreAllHitboxes()
    _G.SleepyEnhancements = nil
end

-- ============================================================
-- 22. AUTOLOAD (deferred, guarded, silent)
-- ============================================================
task.defer(function()
    if not SaveManager then return end
    pcall(function() SaveManager:LoadAutoloadConfig() end)
end)

-- ============================================================
-- 23. READY
-- ============================================================
pcall(function()
    Library:Notify({
        Title = "Sleepy Enhancements",
        Content = "Loaded. RightShift — menu.",
        Duration = 5,
    })
end)
