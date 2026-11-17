--[[ Throw Food For Animals | custom auto farm
     Self contained, keyless. RightShift = toggle menu ]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local RunService= game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local VIM       = game:GetService("VirtualInputManager")
local VU        = game:GetService("VirtualUser")
local LP        = Players.LocalPlayer

if getgenv and getgenv().TFFA_Unload then pcall(getgenv().TFFA_Unload) end

local conns = {}
local function bind(c) conns[#conns+1] = c return c end

local Remotes = RS:WaitForChild("Remotes", 30)

local function invoke(name, ...)
    local r = Remotes and Remotes:FindFirstChild(name)
    if not r or not r:IsA("RemoteFunction") then return nil end
    local a = table.pack(...)
    local ok, res = pcall(function() return r:InvokeServer(table.unpack(a, 1, a.n)) end)
    if ok then return res end
end
local function good(res) return type(res) == "table" and res.Ok == true end

-- state
local flags = {
    autoThrow = false, fullAuto = false, autoTrain = false, autoBonus = true,
    autoPlace = false, autoSell = false, autoUpgrade = false, autoFood = false,
    autoClaim = false, antiAfk = true, speed = false, jump = false,
    infJump = false, noclip = false,
}
local cfg = {tapPoint = 0.9, throwsPerCycle = 10, trainSeconds = 30, sellEvery = 10, upEvery = 6}
local stats = {throws = 0, perfect = 0, fails = 0, sells = 0}
local alive = true
local training = false

-- controllers / data
local ThrowController, ClientState, Data
task.spawn(function()
    pcall(function()
        local ctl = LP:WaitForChild("PlayerScripts", 30):WaitForChild("Client", 30):WaitForChild("Controllers", 30)
        ThrowController = require(ctl:WaitForChild("ThrowController", 30))
        ClientState     = require(ctl:WaitForChild("ClientState", 30))
        Data            = require(ctl:WaitForChild("DataController", 30))
    end)
end)

local function get(key)
    if not Data then return nil end
    local ok, v = pcall(function() return Data:Get(key) end)
    if ok then return v end
end

local function root()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function myPlot()
    local idx = LP:GetAttribute("PlotIndex")
    local plots = workspace:FindFirstChild("Plots")
    return idx and plots and plots:FindFirstChild(tostring(idx))
end

-- throw tapping
local function tapScreen()
    local vp = workspace.CurrentCamera.ViewportSize
    local x, y = vp.X * 0.62, vp.Y * 0.42
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
end

local function findMeter()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, d in ipairs(pg:GetDescendants()) do
        if d.Name == "Meter" and d:FindFirstChild("Bar") and d.Bar:FindFirstChild("Marker") then
            return d
        end
    end
end

do
    local meter, tapped, born, lastU
    bind(RunService.RenderStepped:Connect(function()
        if not flags.autoThrow then meter = nil return end
        if meter and not meter.Parent then meter, tapped = nil, false end
        if not meter then
            meter = findMeter()
            if not meter then return end
            tapped, born, lastU = false, os.clock(), 0
        end
        if tapped then return end
        local u = 1 - meter.Bar.Marker.Position.Y.Scale
        local rising = u > lastU + 0.0004
        lastU = u
        if os.clock() - born > 0.35 and rising and u >= cfg.tapPoint then
            tapped = true
            tapScreen()
            task.delay(0.15, function()
                local final = 1 - meter.Bar.Marker.Position.Y.Scale
                if final >= 0.93 then
                    stats.perfect += 1
                else
                    cfg.tapPoint = math.min(0.96, cfg.tapPoint + 0.01)
                end
            end)
        end
    end))
end

local function startTraining()
    if training then return end
    training = good(invoke("Training_Start"))
end
local function stopTraining()
    if not training then return end
    invoke("Training_Stop")
    training = false
end

local function throwOnce()
    if training then stopTraining() end
    if not ThrowController or not ThrowController.Start then return false end
    if ClientState and (ClientState.Busy or ClientState.OfflineOpen) then
        task.wait(0.4) return false
    end
    local ok = pcall(ThrowController.Start)
    if ok then stats.throws += 1 else stats.fails += 1 end
    task.wait(0.3)
    return ok
end

-- main loop
task.spawn(function()
    local done, trainStart = 0, nil
    while alive do
        if flags.fullAuto then
            if done < cfg.throwsPerCycle then
                throwOnce() done += 1 trainStart = nil
            else
                trainStart = trainStart or os.clock()
                startTraining() task.wait(1)
                if os.clock() - trainStart >= cfg.trainSeconds then
                    stopTraining() done = 0
                end
            end
        elseif flags.autoThrow then
            throwOnce() done, trainStart = 0, nil
        elseif flags.autoTrain then
            startTraining() task.wait(1)
        else
            stopTraining() done, trainStart = 0, nil task.wait(0.4)
        end
    end
end)

-- training x2 bonus
do
    local ev = Remotes:FindFirstChild("Training_Bonus")
    if ev and ev:IsA("RemoteEvent") then
        bind(ev.OnClientEvent:Connect(function(payload)
            if not flags.autoBonus then return end
            local id = type(payload) == "table" and payload.Id or payload
            if id ~= nil then task.spawn(invoke, "Training_TapBonus", id) end
        end))
    end
end

local function loop(flag, interval, fn)
    task.spawn(function()
        while alive do
            if flags[flag] then pcall(fn) end
            task.wait(type(interval) == "function" and interval() or interval)
        end
    end)
end

-- placing animals on your plot
local function spot(plot, n)
    local s = plot.Size
    local x = ((n * 0.618) % 1 - 0.5) * (s.X - 8)
    local z = ((n * 0.382 + 0.17) % 1 - 0.5) * (s.Z - 8)
    return plot.Position + Vector3.new(x, s.Y / 2 + 0.5, z)
end

loop("autoPlace", 2.5, function()
    invoke("Plot_EquipBest")
    local plot, bp = myPlot(), LP:FindFirstChildOfClass("Backpack")
    if not (plot and bp) then return end
    local n = 0
    for _, tool in ipairs(bp:GetChildren()) do
        local key = tool:IsA("Tool") and tool:GetAttribute("EggKey")
        if key then
            n += 1
            local res = invoke("Egg_Place", key, spot(plot, n))
            if type(res) == "table" and not res.Ok then break end
            task.wait(0.2)
        end
    end
end)

loop("autoSell", function() return cfg.sellEvery end, function()
    if good(invoke("Plot_SellAll")) then stats.sells += 1 end
end)

loop("autoUpgrade", function() return cfg.upEvery end, function()
    invoke("Stand_Upgrade")
    invoke("Plot_UpgradeFence")
end)

loop("autoFood", 6, function()
    local equipped = tonumber(get("EquippedFood")) or 1
    for i = equipped + 1, equipped + 4 do
        local r = invoke("Shop_Buy", i)
        if good(r) then invoke("Shop_Equip", i) break end
    end
end)

loop("autoClaim", 25, function()
    invoke("Offline_Claim")
    if get("FreeAnimalClaimed") ~= true then invoke("Shop_ClaimFree") end
end)

loop("antiAfk", 40, function()
    VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
    task.wait(0.05)
    VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
end)

bind(LP.Idled:Connect(function()
    if flags.antiAfk then
        pcall(function()
            VU:CaptureController()
            VU:ClickButton2(Vector2.new())
        end)
    end
end))

bind(RunService.Stepped:Connect(function()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        if flags.speed then hum.WalkSpeed = cfg.speed or 40 end
        if flags.jump then
            hum.UseJumpPower = true
            hum.JumpPower = cfg.jumpPower or 90
        end
    end
    if flags.noclip and char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end
end))

bind(UIS.JumpRequest:Connect(function()
    if flags.infJump then
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

-- ===== UI =====
local function buildUI()
    local parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")
    local sg = Instance.new("ScreenGui")
    sg.Name, sg.ResetOnSpawn, sg.IgnoreGuiInset = "TFFA_UI", false, true
    sg.Parent = parent

    local win = Instance.new("Frame")
    win.Size = UDim2.fromOffset(255, 400)
    win.Position = UDim2.new(0, 20, 0, 90)
    win.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    win.BorderSizePixel = 0
    win.Active = true
    win.Parent = sg
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 8)
    local st = Instance.new("UIStroke", win)
    st.Color = Color3.fromRGB(55, 55, 65)

    local head = Instance.new("Frame")
    head.Size = UDim2.new(1, 0, 0, 32)
    head.BackgroundTransparency = 1
    head.Parent = win

    local ttl = Instance.new("TextLabel")
    ttl.Size = UDim2.new(1, -70, 1, 0)
    ttl.Position = UDim2.fromOffset(10, 0)
    ttl.BackgroundTransparency = 1
    ttl.Font = Enum.Font.GothamBold
    ttl.TextSize = 13
    ttl.TextColor3 = Color3.fromRGB(235, 235, 240)
    ttl.TextXAlignment = Enum.TextXAlignment.Left
    ttl.Text = "TFFA  |  auto farm"
    ttl.Parent = head

    local function hbtn(text, x, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(26, 20)
        b.Position = UDim2.new(1, x, 0, 6)
        b.BackgroundColor3 = Color3.fromRGB(45, 45, 54)
        b.TextColor3 = Color3.fromRGB(230, 230, 235)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Text = text
        b.Parent = head
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -42)
    scroll.Position = UDim2.fromOffset(8, 36)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new()
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = win
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 5)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = scroll

    local function row(h)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, h)
        f.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
        f.BorderSizePixel = 0
        f.Parent = scroll
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
        return f
    end

    local function section(text)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 20)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.GothamBold
        l.TextSize = 11
        l.TextColor3 = Color3.fromRGB(120, 170, 255)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = string.upper(text)
        l.Parent = scroll
        return l
    end

    local function toggle(text, default, cb)
        local f = row(30)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -60, 1, 0)
        l.Position = UDim2.fromOffset(9, 0)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Gotham
        l.TextSize = 12
        l.TextColor3 = Color3.fromRGB(225, 225, 230)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = text
        l.Parent = f
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(38, 18)
        b.Position = UDim2.new(1, -46, 0.5, -9)
        b.BackgroundColor3 = Color3.fromRGB(55, 55, 64)
        b.TextColor3 = Color3.fromRGB(200, 200, 205)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.Text = "OFF"
        b.Parent = f
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        local state = default
        local function paint()
            b.Text = state and "ON" or "OFF"
            b.BackgroundColor3 = state and Color3.fromRGB(60, 160, 95) or Color3.fromRGB(55, 55, 64)
            b.TextColor3 = state and Color3.fromRGB(240, 255, 245) or Color3.fromRGB(200, 200, 205)
        end
        paint()
        cb(state)
        b.MouseButton1Click:Connect(function()
            state = not state
            paint()
            cb(state)
        end)
    end

    local function number(text, default, cb)
        local f = row(30)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -70, 1, 0)
        l.Position = UDim2.fromOffset(9, 0)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Gotham
        l.TextSize = 12
        l.TextColor3 = Color3.fromRGB(225, 225, 230)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = text
        l.Parent = f
        local box = Instance.new("TextBox")
        box.Size = UDim2.fromOffset(50, 18)
        box.Position = UDim2.new(1, -58, 0.5, -9)
        box.BackgroundColor3 = Color3.fromRGB(45, 45, 54)
        box.TextColor3 = Color3.fromRGB(235, 235, 240)
        box.Font = Enum.Font.Gotham
        box.TextSize = 11
        box.Text = tostring(default)
        box.Parent = f
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
        box.FocusLost:Connect(function()
            local v = tonumber(box.Text)
            if v then cb(v) else box.Text = tostring(default) end
        end)
    end

    local function button(text, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 28)
        b.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
        b.TextColor3 = Color3.fromRGB(230, 230, 235)
        b.Font = Enum.Font.Gotham
        b.TextSize = 12
        b.Text = text
        b.Parent = scroll
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(cb)
    end

    section("Farm")
    toggle("Auto perfect throw", false, function(v) flags.autoThrow = v end)
    toggle("Full auto farm (throw + train)", false, function(v) flags.fullAuto = v end)
    number("Throws per cycle", 10, function(v) cfg.throwsPerCycle = math.floor(v) end)
    number("Train seconds", 30, function(v) cfg.trainSeconds = math.floor(v) end)
    toggle("Auto train only", false, function(v) flags.autoTrain = v end)
    toggle("Auto training x2 bonus", true, function(v) flags.autoBonus = v end)
    number("Tap point 0.8-0.96", 0.9, function(v) cfg.tapPoint = math.clamp(v, 0.8, 0.96) end)

    section("Economy")
    toggle("Auto place best animals", false, function(v) flags.autoPlace = v end)
    toggle("Auto sell animals", false, function(v) flags.autoSell = v end)
    number("Sell check (s)", 10, function(v) cfg.sellEvery = math.max(2, v) end)
    toggle("Auto upgrade stand + fence", false, function(v) flags.autoUpgrade = v end)
    toggle("Auto buy / equip food", false, function(v) flags.autoFood = v end)
    toggle("Auto claim gifts + offline cash", false, function(v) flags.autoClaim = v end)

    section("Player")
    toggle("Anti AFK", true, function(v) flags.antiAfk = v end)
    toggle("Walk speed", false, function(v)
        flags.speed = v
        if not v then
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = 16 end
        end
    end)
    number("Speed value", 40, function(v) cfg.speed = v end)
    toggle("Jump power", false, function(v) flags.jump = v end)
    number("Jump value", 90, function(v) cfg.jumpPower = v end)
    toggle("Infinite jump", false, function(v) flags.infJump = v end)
    toggle("Noclip", false, function(v) flags.noclip = v end)

    section("Teleport")
    button("My plot", function()
        local plot, hrp = myPlot(), root()
        if plot and hrp then hrp.CFrame = CFrame.new(plot.Position + Vector3.new(0, 6, 0)) end
    end)
    button("Sell stand", function()
        local s = workspace:FindFirstChild("SellStand") or workspace:FindFirstChild("Sell")
        local hrp = root()
        if s and hrp then hrp.CFrame = CFrame.new((s:IsA("BasePart") and s.Position or s:GetPivot().Position) + Vector3.new(0, 6, 0)) end
    end)

    section("Session")
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 34)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(170, 170, 180)
    lbl.TextWrapped = true
    lbl.Text = "starting..."
    lbl.Parent = scroll
    task.spawn(function()
        while alive do
            task.wait(2)
            pcall(function()
                lbl.Text = string.format("throws %d  perfect %d  fails %d  sells %d", stats.throws, stats.perfect, stats.fails, stats.sells)
            end)
        end
    end)

    -- drag
    local drag, start
    head.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag, start = true, i.Position
        end
    end)
    bind(UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            start = i.Position
            win.Position = UDim2.new(0, win.AbsolutePosition.X + d.X, 0, win.AbsolutePosition.Y + d.Y)
        end
    end))
    bind(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = false
        end
    end))

    local minimized = false
    hbtn("–", -58, function()
        minimized = not minimized
        scroll.Visible = not minimized
        win.Size = minimized and UDim2.fromOffset(255, 32) or UDim2.fromOffset(255, 400)
    end)
    hbtn("x", -28, function()
        if getgenv and getgenv().TFFA_Unload then getgenv().TFFA_Unload() end
    end)

    return sg
end

local ui = buildUI()

-- unload
local function unload()
    alive = false
    for k in pairs(flags) do flags[k] = false end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(stopTraining)
    pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed, hum.JumpPower = 16, 50 end
    end)
    pcall(function() ui:Destroy() end)
end
if getgenv then getgenv().TFFA_Unload = unload end
