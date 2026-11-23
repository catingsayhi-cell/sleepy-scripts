if getgenv().SleepyLoaded then
    return warn("[Sleepy] Already loaded. Unload first or reload UI.")
end
getgenv().SleepyLoaded = true

local Library
local ok, lib = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/ofugii/Unnamed-Linoria/main/Library.lua"))()
end)
if ok and lib then
    Library = lib
else
    local ok2, lib2 = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/lnxcz/LinoriaLib/main/Library.lua"))()
    end)
    if ok2 and lib2 then
        Library = lib2
    else
        getgenv().SleepyLoaded = nil
        return warn("[Sleepy] Failed to load UI library from both sources.")
    end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local isActive = true
local connections = {}
local espObjects = {}

local function addConn(conn)
    table.insert(connections, conn)
    return conn
end

local Config = {
    Aimbot = false, AimPart = "Head", AimSmooth = 0.3, AimFOV = 150, AimTeam = true,
    ESPBox = false, ESPName = false,
    HitboxEnabled = false, HitboxSize = 5,
    AntiFling = false, AntiVoid = false,
    WalkSpeed = 16, JumpPower = 50,
    Fly = false, FlySpeed = 60,
    AntiAFK = true,
}

local function isAlive(plr)
    local char = plr.Character
    if not char or not char.Parent then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isTeammate(plr)
    if not Config.AimTeam then return false end
    local a, b = LP.Team, plr.Team
    return a ~= nil and b ~= nil and a == b
end

local function getClosestPlayer(fov, partName)
    local center = Camera.ViewportSize / 2
    if center.X <= 0 or center.Y <= 0 then return nil end

    local bestPart, bestScore = nil, fov or math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAlive(plr) and not isTeammate(plr) then
            local char = plr.Character
            local part = char:FindFirstChild(partName) or char:FindFirstChild("HumanoidRootPart")
            if part then
                local screen, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local dist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                    if dist < bestScore then
                        bestScore = dist
                        bestPart = part
                    end
                end
            end
        end
    end
    return bestPart
end

local function getBoundingBox(char)
    local parts = {}
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
            table.insert(parts, v)
        end
    end
    if #parts == 0 then return nil end

    local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
    for _, p in ipairs(parts) do
        local cf, size = p.CFrame, p.Size
        for _, corner in ipairs({
            cf * Vector3.new(1, 1, 1) * size / 2,
            cf * Vector3.new(-1, 1, 1) * size / 2,
            cf * Vector3.new(1, -1, 1) * size / 2,
            cf * Vector3.new(1, 1, -1) * size / 2,
            cf * Vector3.new(-1, -1, 1) * size / 2,
            cf * Vector3.new(-1, 1, -1) * size / 2,
            cf * Vector3.new(1, -1, -1) * size / 2,
            cf * Vector3.new(-1, -1, -1) * size / 2,
        }) do
            minV = Vector3.new(math.min(minV.X, corner.X), math.min(minV.Y, corner.Y), math.min(minV.Z, corner.Z))
            maxV = Vector3.new(math.max(maxV.X, corner.X), math.max(maxV.Y, corner.Y), math.max(maxV.Z, corner.Z))
        end
    end
    return minV, maxV
end

local function clearEsp()
    for _, obj in pairs(espObjects) do
        pcall(function() obj:Remove() end)
    end
    espObjects = {}
end

RunService:BindToRenderStep("SleepyAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not isActive then return end
    if Config.Aimbot and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local part = getClosestPlayer(Config.AimFOV, Config.AimPart)
        if part then
            local current = Camera.CFrame
            local desired = CFrame.lookAt(current.Position, part.Position)
            local alpha = 1 - math.pow(1 - Config.AimSmooth, dt * 60)
            Camera.CFrame = current:Lerp(desired, alpha)
        end
    end
end)

local function renderEsp()
    if not Config.ESPBox and not Config.ESPName then
        if next(espObjects) then clearEsp() end
        return
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP or not isAlive(plr) then
            if espObjects[plr] then
                pcall(function() espObjects[plr]:Remove() end)
                espObjects[plr] = nil
            end
            continue
        end

        if espObjects[plr] then continue end

        local hl = Instance.new("Highlight")
        hl.Name = "SleepyHL"
        hl.FillTransparency = 1
        hl.OutlineTransparency = 1
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee = plr.Character
        hl.Parent = CoreGui
        espObjects[plr] = hl
    end

    for plr, obj in pairs(espObjects) do
        local alive = plr and plr.Parent and isAlive(plr)
        if not alive then
            pcall(function() obj:Remove() end)
            espObjects[plr] = nil
        elseif Config.ESPBox then
            obj.FillColor = Color3.fromRGB(255, 255, 255)
            obj.FillTransparency = 0.6
            obj.OutlineColor = Color3.fromRGB(255, 255, 255)
            obj.OutlineTransparency = 0
        elseif Config.ESPName then
            obj.FillColor = Color3.fromRGB(120, 180, 255)
            obj.FillTransparency = 0.7
            obj.OutlineColor = Color3.fromRGB(120, 180, 255)
            obj.OutlineTransparency = 0
        else
            obj.FillTransparency = 1
            obj.OutlineTransparency = 1
        end
    end
end

local function applyHitboxes()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local char = plr.Character
        if not char then continue end
        for _, partName in ipairs({"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso"}) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                if Config.HitboxEnabled then
                    if not part:GetAttribute("SleepyOrigSize") then
                        part:SetAttribute("SleepyOrigSize", part.Size)
                        part:SetAttribute("SleepyOrigTrans", part.Transparency)
                    end
                    part.Size = Vector3.new(Config.HitboxSize, Config.HitboxSize, Config.HitboxSize)
                    part.Transparency = 0.5
                    part.CanCollide = false
                else
                    local origSize = part:GetAttribute("SleepyOrigSize")
                    local origTrans = part:GetAttribute("SleepyOrigTrans")
                    if origSize then
                        part.Size = origSize
                        part.Transparency = origTrans or 0
                        part:SetAttribute("SleepyOrigSize", nil)
                        part:SetAttribute("SleepyOrigTrans", nil)
                    end
                end
            end
        end
    end
end

addConn(RunService.Heartbeat:Connect(function()
    if not isActive then return end
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")

    if hum then
        if hum.WalkSpeed ~= Config.WalkSpeed then hum.WalkSpeed = Config.WalkSpeed end
        if hum.JumpPower ~= Config.JumpPower then hum.JumpPower = Config.JumpPower end
    end

    if hrp then
        if Config.AntiFling and hrp.AssemblyLinearVelocity.Magnitude > 100 then
            pcall(function() hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity.Unit * 50 end)
        end
        if Config.AntiVoid and hrp.Position.Y < -50 then
            pcall(function()
                hrp.CFrame = CFrame.new(0, 50, 0)
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end)
        end
    end

    renderEsp()
    if Config.HitboxEnabled or next(espObjects) == nil then
        applyHitboxes()
    end
end))

local flyVel, flyGyro
task.spawn(function()
    while task.wait(0.1) do
        if not isActive then break end
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if Config.Fly and hrp then
            if not flyVel then
                flyVel = Instance.new("BodyVelocity")
                flyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                flyVel.P = 1250
                flyVel.Parent = hrp
                flyGyro = Instance.new("BodyGyro")
                flyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
                flyGyro.P = 3000
                flyGyro.D = 500
                flyGyro.Parent = hrp
            end
            local camCF = Camera.CFrame
            local move = Vector3.new(0, 0, 0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0, 1, 0) end
            flyVel.Velocity = move.Magnitude > 0 and move.Unit * Config.FlySpeed or Vector3.new(0, 0, 0)
            flyGyro.CFrame = camCF
        elseif flyVel then
            flyVel:Destroy(); flyVel = nil
            if flyGyro then flyGyro:Destroy(); flyGyro = nil end
        end
    end
end)

task.spawn(function()
    while task.wait(5) do
        if not isActive then break end
        if Config.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end
end)

local Window = Library:CreateWindow({
    Title = "Sleepy Enhancements",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Combat = Window:AddTab("Combat"),
    Visuals = Window:AddTab("Visuals"),
    Protection = Window:AddTab("Protection"),
    Movement = Window:AddTab("Movement"),
    Misc = Window:AddTab("Misc"),
    Settings = Window:AddTab("Settings"),
}

local function tryInit(name, fn)
    local ok, err = pcall(fn)
    if not ok then warn("[Sleepy] tab init failed (" .. name .. "):", err) end
end

tryInit("Combat", function()
    local aimGroup = Tabs.Combat:AddLeftGroupbox("Aimbot")
    aimGroup:AddToggle("Aimbot", { Text = "Enable Aimbot", Default = Config.Aimbot, Callback = function(v) Config.Aimbot = v end })
    aimGroup:AddDropdown("AimPart", { Text = "Aim Part", Values = {"Head", "HumanoidRootPart"}, Default = Config.AimPart, Callback = function(v) Config.AimPart = v end })
    aimGroup:AddSlider("AimFOV", { Text = "FOV", Min = 20, Max = 600, Default = Config.AimFOV, Callback = function(v) Config.AimFOV = v end })
    aimGroup:AddSlider("AimSmooth", { Text = "Smoothness", Min = 0.1, Max = 0.9, Default = Config.AimSmooth, Rounding = 1, Callback = function(v) Config.AimSmooth = v end })
    aimGroup:AddToggle("AimTeam", { Text = "Team Check", Default = Config.AimTeam, Callback = function(v) Config.AimTeam = v end })

    local hitboxGroup = Tabs.Combat:AddLeftGroupbox("Hitbox")
    hitboxGroup:AddToggle("HitboxEnabled", { Text = "Enable Hitbox Expander", Default = Config.HitboxEnabled, Callback = function(v) Config.HitboxEnabled = v end })
    hitboxGroup:AddSlider("HitboxSize", { Text = "Hitbox Size", Min = 2, Max = 20, Default = Config.HitboxSize, Callback = function(v) Config.HitboxSize = v end })
end)

tryInit("Visuals", function()
    local espGroup = Tabs.Visuals:AddLeftGroupbox("ESP")
    espGroup:AddToggle("ESPBox", { Text = "Box ESP", Default = Config.ESPBox, Callback = function(v) Config.ESPBox = v end })
    espGroup:AddToggle("ESPName", { Text = "Name ESP", Default = Config.ESPName, Callback = function(v) Config.ESPName = v end })
end)

tryInit("Protection", function()
    local protGroup = Tabs.Protection:AddLeftGroupbox("Protection")
    protGroup:AddToggle("AntiFling", { Text = "Anti-Fling", Default = Config.AntiFling, Callback = function(v) Config.AntiFling = v end })
    protGroup:AddToggle("AntiVoid", { Text = "Anti-Void", Default = Config.AntiVoid, Callback = function(v) Config.AntiVoid = v end })
end)

tryInit("Movement", function()
    local moveGroup = Tabs.Movement:AddLeftGroupbox("Movement")
    moveGroup:AddSlider("WalkSpeed", { Text = "WalkSpeed", Min = 16, Max = 100, Default = Config.WalkSpeed, Callback = function(v) Config.WalkSpeed = v end })
    moveGroup:AddSlider("JumpPower", { Text = "JumpPower", Min = 50, Max = 150, Default = Config.JumpPower, Callback = function(v) Config.JumpPower = v end })

    local flyGroup = Tabs.Movement:AddLeftGroupbox("Fly")
    flyGroup:AddToggle("Fly", { Text = "Fly (WASD + Space/Ctrl)", Default = Config.Fly, Callback = function(v) Config.Fly = v end })
    flyGroup:AddSlider("FlySpeed", { Text = "Fly Speed", Min = 10, Max = 200, Default = Config.FlySpeed, Callback = function(v) Config.FlySpeed = v end })
end)

tryInit("Misc", function()
    local miscGroup = Tabs.Misc:AddLeftGroupbox("Misc")
    miscGroup:AddToggle("AntiAFK", { Text = "Anti-AFK", Default = Config.AntiAFK, Callback = function(v) Config.AntiAFK = v end })
end)

tryInit("Settings", function()
    local settingsGroup = Tabs.Settings:AddLeftGroupbox("Script Control")

    settingsGroup:AddButton({
        Text = "UNLOAD SCRIPT (STOP)",
        Func = function()
            isActive = false
            pcall(function() RunService:UnbindFromRenderStep("SleepyAim") end)
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            if flyVel then pcall(function() flyVel:Destroy() end) end
            if flyGyro then pcall(function() flyGyro:Destroy() end) end
            clearEsp()
            pcall(function() applyHitboxes() end)
            Library:Notify({ Title = "Stopped", Content = "Script unloaded.", Duration = 3 })
            task.wait(0.5)
            pcall(function() Library:Unload() end)
            getgenv().SleepyLoaded = nil
        end
    })

    settingsGroup:AddLabel("Hide Menu Key: RightShift")
end)

addConn(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not isActive then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        pcall(function() Library:Toggle() end)
    end
end))

task.delay(1.5, function()
    pcall(function()
        Library:ModifyTheme({
            { "Menu Accent", "Accent", Color3.fromRGB(255, 255, 255) },
            { "Slider", "Fill", Color3.fromRGB(255, 255, 255) },
            { "Button", "Main", Color3.fromRGB(240, 240, 240) },
            { "Button", "Text", Color3.fromRGB(20, 20, 20) },
        })
    end)
end)

Library:Notify({
    Title = "Sleepy Enhancements",
    Content = "v12 Loaded. RightShift to hide. World saved.",
    Duration = 5,
})
