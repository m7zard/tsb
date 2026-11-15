local players = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local starterGui = game:GetService("StarterGui")
local httpService = game:GetService("HttpService")
local localPlayer = players.LocalPlayer

if getgenv().uppercutDetectorCleanup then
    pcall(getgenv().uppercutDetectorCleanup)
end

local sessionId = math.random(100000, 999999)
getgenv().uppercutDetectorId = sessionId

local config = {
             enabled = true,
           debugAnim = false,
     cooldownEnabled = true,
           dashDelay = 0.23,
            dashWait = 0,
           dashRetry = 0.06,
        dashCooldown = 5.0,

           loopDelay = 0.3,
        loopDuration = 0.6,
               speed = 60,
           jumpDelay = 0.3,
           jumpForce = 51,
          gyroTorque = 1000000,
               gyroP = 30000,
               gyroD = 500,
            moveMode = "cframe",
             maxStep = 2.5,
         smoothSpeed = 20,
      lockAutoRotate = true,
    usePlatformStand = false,
       noclipEnabled = true,
         noclipRange = 8,

              hotkey = Enum.KeyCode.V,

           camSmooth = true,
      camSmoothDelay = 0,
          camDuration = 1.5,

             guiTitle = "Loop Dash",
            guiAuthor = "Techinified",
}

local uppercutAnimIds = {
      ["10503381238"] = true,
}

local dashAnimIds = {
  ["10479335397"] = true,
  ["10491993682"] = true,
  ["13380255751"] = true,
}

local theme = {
         bg = Color3.fromRGB(15, 15, 14),
       well = Color3.fromRGB(10, 10, 10),
     raised = Color3.fromRGB(28, 28, 26),
       line = Color3.fromRGB(38, 37, 34),
 lineStrong = Color3.fromRGB(66, 64, 58),
       text = Color3.fromRGB(233, 230, 222),
      muted = Color3.fromRGB(131, 127, 118),
        dim = Color3.fromRGB(96, 93, 86),
     accent = Color3.fromRGB(255, 88, 48),
}

local function pickFont(name, fallback)
    local ok, font = pcall(function()
        return Enum.Font[name]
    end)
    if ok and font then
        return font
    end
    return fallback
end

local fonts = {
    label = pickFont("BuilderSansMedium", Enum.Font.GothamMedium),
    title = pickFont("BuilderSansBold", Enum.Font.GothamBold),
    mono = pickFont("RobotoMono", Enum.Font.Code),
}

local charConnections = {}
local sessionConnections = {}
local dashPending = false
local dashStarted = false
local windowEnd = 0
local cycleId = 0
local lastDashTime = -math.huge
local activeRun = nil
local screenGui = nil
local refreshWidgets = function() end

local function isAlive()
    return getgenv().uppercutDetectorId == sessionId
end

local function connect(signal, callback)
    local ok, connection = pcall(function()
        return signal:Connect(callback)
    end)
    if ok and connection then
        table.insert(sessionConnections, connection)
        return connection
    end
    return nil
end

local function disconnectSafe(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function notify(text)
    pcall(function()
        starterGui:SetCore("SendNotification", {
            Title = config.guiTitle,
            Text = text,
            Duration = 2,
        })
    end)
end

local camConnection = nil
local camExecuting = false
local camDashStartTime = 0
local camAttached = false
local camPrevSubject = nil
local camDashId = 0

local function restoreCamera()
    if not camAttached then
        return
    end
    camAttached = false
    pcall(function()
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end
        local character = localPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local subject = camPrevSubject
        if not subject or not subject:IsDescendantOf(workspace) then
            subject = humanoid
        end
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = subject
    end)
    camPrevSubject = nil
end

local function updateCamSmooth(isEnabled)
    if camConnection then
        disconnectSafe(camConnection)
        camConnection = nil
    end
    if not isEnabled then
        restoreCamera()
        return
    end

    local ok, connection = pcall(function()
        return runService.RenderStepped:Connect(function()
            if not isAlive() then
                return
            end
            local camera = workspace.CurrentCamera
            if not camera then
                return
            end
            local character = localPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then
                restoreCamera()
                return
            end

            local elapsed = os.clock() - camDashStartTime
            local inSmoothWindow = camExecuting
                and elapsed >= config.camSmoothDelay
                and elapsed <= config.camSmoothDelay + config.camDuration

            if not inSmoothWindow then
                restoreCamera()
                return
            end

            if not camAttached then
                camPrevSubject = camera.CameraSubject
                camAttached = true
            end
            pcall(function()
                camera.CameraType = Enum.CameraType.Attach
                camera.CameraSubject = root
            end)
        end)
    end)
    if ok then
        camConnection = connection
    end
end

local function camOnDashEnd()
    camExecuting = false
    updateCamSmooth(false)
end

local function camOnDashStart()
    camExecuting = true
    camDashStartTime = os.clock()
    camDashId = camDashId + 1
    local dashId = camDashId
    updateCamSmooth(config.camSmooth)
    task.delay(config.camSmoothDelay + config.camDuration + 0.1, function()
        if camDashId == dashId and isAlive() then
            camOnDashEnd()
        end
    end)
end

local function flatten(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function rotateAroundY(vector, angle)
    return CFrame.Angles(0, angle, 0):VectorToWorldSpace(vector)
end

local function stopPattern()
    local run = activeRun
    if not run then
        return
    end
    activeRun = nil

    disconnectSafe(run.renderConnection)
    disconnectSafe(run.steppedConnection)

    if run.gyro then
        pcall(function()
            run.gyro:Destroy()
        end)
    end

    for part, originalCanCollide in pairs(run.noclipParts) do
        pcall(function()
            if part.Parent then
                part.CanCollide = originalCanCollide
            end
        end)
    end
    table.clear(run.noclipParts)

    local humanoid = run.humanoid
    if humanoid and humanoid.Parent then
        pcall(function()
            if run.changedAutoRotate then
                humanoid.AutoRotate = true
            end
            if run.changedPlatformStand then
                humanoid.PlatformStand = false
            end
        end)
    end
end

local function getPatternVelocity(run, time)
    local angle = 2 * math.pi * (time / run.duration)
    return rotateAroundY(run.forward, -run.sideSign * angle) * config.speed
end

local function startPattern(character, humanoid, rootPart)
    stopPattern()
    if not isAlive() or not config.enabled then
        return
    end
    if character ~= localPlayer.Character or humanoid.Health <= 0 or not rootPart.Parent then
        return
    end

    local forward = flatten(rootPart.CFrame.LookVector)
    if forward.Magnitude <= 0.015 then
        return
    end
    forward = forward.Unit
    local sideSign = 1
    if math.random(2) == 1 then
        sideSign = -1
    end

    local startVelocity = rootPart.AssemblyLinearVelocity
    local run = {
        humanoid = humanoid,
        forward = forward,
        sideSign = sideSign,
        elapsed = 0,
        duration = config.loopDuration,
        velocity = Vector3.new(startVelocity.X, 0, startVelocity.Z),
        noclipParts = {},
        changedAutoRotate = false,
        changedPlatformStand = false,
    }
    activeRun = run

    if config.debugAnim then
        print("[loopDash]", "side", sideSign, "duration", run.duration)
    end

    pcall(function()
        if config.lockAutoRotate and humanoid.AutoRotate then
            humanoid.AutoRotate = false
            run.changedAutoRotate = true
        end
        if config.usePlatformStand and not humanoid.PlatformStand then
            humanoid.PlatformStand = true
            run.changedPlatformStand = true
        end
    end)

    local gyroOk, gyro = pcall(function()
        local bodyGyro = Instance.new("BodyGyro")
        bodyGyro.MaxTorque = Vector3.new(0, config.gyroTorque, 0)
        bodyGyro.P = config.gyroP
        bodyGyro.D = config.gyroD
        bodyGyro.CFrame = rootPart.CFrame
        bodyGyro.Parent = rootPart
        return bodyGyro
    end)
    if gyroOk then
        run.gyro = gyro
    end

    if config.noclipEnabled then
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = { character }
        local steppedOk, steppedConnection = pcall(function()
            return runService.Stepped:Connect(function()
                if activeRun ~= run or not rootPart.Parent then
                    return
                end
                local nearbyParts = workspace:GetPartBoundsInRadius(rootPart.Position, config.noclipRange, overlapParams)
                for _, part in ipairs(nearbyParts) do
                    if part.CanCollide then
                        local model = part:FindFirstAncestorOfClass("Model")
                        if model and model ~= character and model:FindFirstChildOfClass("Humanoid") then
                            run.noclipParts[part] = true
                            part.CanCollide = false
                        end
                    end
                end
            end)
        end)
        if steppedOk then
            run.steppedConnection = steppedConnection
        end
    end

    local renderOk, renderConnection = pcall(function()
        return runService.RenderStepped:Connect(function(dt)
            if activeRun ~= run then
                return
            end
            if not isAlive()
                or not config.enabled
                or character ~= localPlayer.Character
                or humanoid.Health <= 0
                or not rootPart.Parent then
                stopPattern()
                return
            end

            dt = math.min(dt, 0.1)
            run.elapsed = run.elapsed + dt
            if run.elapsed >= run.duration then
                stopPattern()
                return
            end

            local desiredVelocity = getPatternVelocity(run, run.elapsed)
            if run.gyro then
                run.gyro.CFrame = CFrame.lookAt(Vector3.zero, desiredVelocity)
            end
            local alpha = 1 - math.exp(-config.smoothSpeed * dt)
            run.velocity = run.velocity:Lerp(desiredVelocity, alpha)

            local physicsVelocity = rootPart.AssemblyLinearVelocity
            local flatPhysics = Vector3.new(physicsVelocity.X, 0, physicsVelocity.Z)

            if config.moveMode == "velocity" then
                local delta = run.velocity - flatPhysics
                local limit = config.maxStep / math.max(dt, 0.001)
                if delta.Magnitude > limit then
                    delta = delta.Unit * limit
                end
                if delta.Magnitude * dt <= 0.015 then
                    return
                end
                rootPart.AssemblyLinearVelocity = Vector3.new(
                    flatPhysics.X + delta.X,
                    physicsVelocity.Y,
                    flatPhysics.Z + delta.Z
                )
            else
                local direction = (run.velocity - flatPhysics) * dt
                if direction.Magnitude <= 0.015 then
                    return
                end
                if direction.Magnitude > config.maxStep then
                    direction = direction.Unit * config.maxStep
                end
                rootPart.CFrame = rootPart.CFrame + direction
            end
        end)
    end)
    if renderOk then
        run.renderConnection = renderConnection
    else
        stopPattern()
    end
end

local function setEnabled(value)
    config.enabled = value
    if not value then
        pcall(stopPattern)
        pcall(camOnDashEnd)
    end
    refreshWidgets()
end

local function resolveGuiParent()
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then
            return result
        end
    end
    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and coreGui then
        return coreGui
    end
    return localPlayer:WaitForChild("PlayerGui")
end

local function buildUI()
    local windowWidth, windowHeight = 300, 324
    local headerHeight, tabsHeight = 34, 26
    local pad = 12
    local tabWidth = 66

    local function create(className, props, parent)
        local instance = Instance.new(className)
        for key, value in pairs(props) do
            instance[key] = value
        end
        instance.Parent = parent
        return instance
    end

    local function addCorner(parent, radius)
        return create("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
    end

    local function addStroke(parent, color)
        return create("UIStroke", {
            Color = color,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, parent)
    end

    local function addPadding(parent, left, right, top, bottom)
        return create("UIPadding", {
            PaddingLeft = UDim.new(0, left),
            PaddingRight = UDim.new(0, right),
            PaddingTop = UDim.new(0, top),
            PaddingBottom = UDim.new(0, bottom),
        }, parent)
    end

    local function addList(parent, gap)
        return create("UIListLayout", {
            Padding = UDim.new(0, gap),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, parent)
    end

    local function makeText(parent, props)
        local merged = {
            BackgroundTransparency = 1,
            Font = fonts.label,
            TextSize = 12,
            TextColor3 = theme.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "",
        }
        for key, value in pairs(props) do
            merged[key] = value
        end
        return create("TextLabel", merged, parent)
    end

    local function bindHover(button, onEnter, onLeave)
        connect(button.MouseEnter, onEnter)
        connect(button.MouseLeave, onLeave)
    end

    local order = 0
    local function nextOrder()
        order = order + 1
        return order
    end

    local activeDrag = nil

    local function endDrag()
        local drag = activeDrag
        activeDrag = nil
        if drag and drag.finish then
            drag.finish()
        end
    end

    local function startDrag(input, onMove, onFinish)
        endDrag()
        activeDrag = {input = input, move = onMove, finish = onFinish}
    end

    connect(userInputService.InputChanged, function(input)
        if not activeDrag then
            return
        end
        local kind = input.UserInputType
        local moving = kind == Enum.UserInputType.MouseMovement
            or (kind == Enum.UserInputType.Touch and input == activeDrag.input)
        if not moving then
            return
        end
        if activeDrag.input.UserInputType == Enum.UserInputType.MouseButton1
            and not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            endDrag()
            return
        end
        activeDrag.move(input.Position)
    end)

    connect(userInputService.InputEnded, function(input)
        if not activeDrag then
            return
        end
        if activeDrag.input.UserInputType == Enum.UserInputType.Touch then
            if input == activeDrag.input then
                endDrag()
            end
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            endDrag()
        end
    end)

    screenGui = create("ScreenGui", {
        Name = "LoopDash",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 50,
    }, nil)
    local parentOk = pcall(function()
        screenGui.Parent = resolveGuiParent()
    end)
    if not parentOk or not screenGui.Parent then
        pcall(function()
            screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
        end)
    end

    local mainFrame = create("Frame", {
        Name = "Window",
        Size = UDim2.fromOffset(windowWidth, windowHeight),
        Position = UDim2.new(0, 24, 0.5, -math.floor(windowHeight / 2)),
        BackgroundColor3 = theme.bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, screenGui)
    addCorner(mainFrame, 6)
    addStroke(mainFrame, theme.line)

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, headerHeight),
        BackgroundTransparency = 1,
        Active = true,
    }, mainFrame)

    local stateMark = create("Frame", {
        Size = UDim2.fromOffset(8, 8),
        Position = UDim2.new(0, 14, 0.5, -4),
        BackgroundColor3 = theme.dim,
        BorderSizePixel = 0,
    }, header)

    local titleText = config.guiTitle
    if config.guiAuthor ~= "" then
        titleText = titleText .. '  <font size="11" color="rgb(131,127,118)">by ' .. config.guiAuthor .. "</font>"
    end
    makeText(header, {
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.fromOffset(150, headerHeight),
        Font = fonts.title,
        TextSize = 13,
        RichText = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = titleText,
    })

    local function makeHeaderButton(text, offsetX)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(26, 26),
            Position = UDim2.new(1, offsetX, 0.5, -13),
            BackgroundColor3 = theme.raised,
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = theme.muted,
            Font = fonts.mono,
            TextSize = 16,
            AutoButtonColor = false,
        }, header)
        addCorner(button, 4)
        bindHover(button, function()
            button.BackgroundTransparency = 0
        end, function()
            button.BackgroundTransparency = 1
        end)
        return button
    end

    local minimizeButton = makeHeaderButton("–", -62)
    local closeButton = makeHeaderButton("×", -34)

    create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = theme.line,
        BorderSizePixel = 0,
    }, header)

    local body = create("Frame", {
        Name = "Body",
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 1, -headerHeight),
        BackgroundTransparency = 1,
    }, mainFrame)

    local tabsBar = create("Frame", {
        Size = UDim2.new(1, 0, 0, tabsHeight),
        BackgroundTransparency = 1,
    }, body)
    create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = theme.line,
        BorderSizePixel = 0,
    }, tabsBar)
    local tabUnderline = create("Frame", {
        Size = UDim2.fromOffset(tabWidth, 2),
        Position = UDim2.new(0, pad, 1, -2),
        BackgroundColor3 = theme.accent,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, tabsBar)

    local tabButtons = {}
    local function makeTab(key, text, index)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(tabWidth, tabsHeight - 1),
            Position = UDim2.fromOffset(pad + (index - 1) * tabWidth, 0),
            BackgroundTransparency = 1,
            Text = text,
            Font = fonts.mono,
            TextSize = 10,
            TextColor3 = theme.muted,
            AutoButtonColor = false,
        }, tabsBar)
        tabButtons[key] = {button = button, index = index}
        return button
    end
    local settingsTab = makeTab("settings", "SETTINGS", 1)
    local cameraTab = makeTab("camera", "CAMERA", 2)
    local configsTab = makeTab("configs", "CONFIGS", 3)

    local statusLabel = makeText(tabsBar, {
        Position = UDim2.new(1, -(pad + 84), 0, 0),
        Size = UDim2.fromOffset(84, tabsHeight - 1),
        Font = fonts.mono,
        TextSize = 10,
        TextColor3 = theme.accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local pagesHolder = create("Frame", {
        Position = UDim2.fromOffset(0, tabsHeight),
        Size = UDim2.new(1, 0, 1, -tabsHeight),
        BackgroundTransparency = 1,
    }, body)

    local function makeScrollPage(name, visible)
        local page = create("ScrollingFrame", {
            Name = name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = theme.lineStrong,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = visible,
        }, pagesHolder)
        addList(page, 2)
        addPadding(page, pad, pad, 4, 10)
        return page
    end

    local settingsPage = makeScrollPage("Settings", true)
    local cameraPage = makeScrollPage("Camera", false)
    local configsPage = create("Frame", {
        Name = "Configs",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, pagesHolder)
    local pageList = {settings = settingsPage, camera = cameraPage, configs = configsPage}

    local function switchTab(name)
        for key, page in pairs(pageList) do
            page.Visible = key == name
        end
        for key, tab in pairs(tabButtons) do
            tab.button.TextColor3 = key == name and theme.text or theme.muted
        end
        local info = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        tweenService:Create(tabUnderline, info, {
            Position = UDim2.new(0, pad + (tabButtons[name].index - 1) * tabWidth, 1, -2),
        }):Play()
    end

    connect(settingsTab.MouseButton1Click, function()
        switchTab("settings")
    end)
    connect(cameraTab.MouseButton1Click, function()
        switchTab("camera")
    end)
    connect(configsTab.MouseButton1Click, function()
        switchTab("configs")
    end)

    local refreshers = {}
    refreshWidgets = function()
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end

    local derived = {}
    local function syncDerived()
        for _, entry in ipairs(derived) do
            entry.setDim(entry.isDimmed())
        end
    end
    table.insert(refreshers, syncDerived)

    local function dimWhen(setDim, isDimmed)
        table.insert(derived, {setDim = setDim, isDimmed = isDimmed})
    end

    local function makeSection(parent, title)
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            LayoutOrder = nextOrder(),
        }, parent)
        create("Frame", {
            Position = UDim2.fromOffset(0, 13),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = theme.line,
            BorderSizePixel = 0,
        }, holder)
        local text = makeText(holder, {
            Position = UDim2.fromOffset(0, 6),
            Size = UDim2.fromOffset(0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 0,
            BackgroundColor3 = theme.bg,
            Font = fonts.mono,
            TextSize = 10,
            TextColor3 = theme.muted,
            Text = title,
        })
        addPadding(text, 8, 8, 0, 0)
    end

    local function makeToggle(parent, title, getter, setter)
        local row = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = theme.raised,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = nextOrder(),
        }, parent)
        addCorner(row, 4)

        makeText(row, {
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.new(1, -60, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = title,
        })

        local track = create("Frame", {
            Size = UDim2.fromOffset(28, 14),
            Position = UDim2.new(1, -36, 0.5, -7),
            BorderSizePixel = 0,
        }, row)
        addCorner(track, 2)
        local trackStroke = addStroke(track, theme.lineStrong)
        local knob = create("Frame", {
            Size = UDim2.fromOffset(10, 10),
            BorderSizePixel = 0,
        }, track)
        addCorner(knob, 1)

        local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local function refresh(animate)
            local on = getter()
            local trackColor = on and theme.accent or theme.well
            local strokeColor = on and theme.accent or theme.lineStrong
            local knobColor = on and theme.bg or theme.muted
            local knobPosition = on and UDim2.fromOffset(16, 2) or UDim2.fromOffset(2, 2)
            if animate then
                tweenService:Create(track, info, {BackgroundColor3 = trackColor}):Play()
                tweenService:Create(trackStroke, info, {Color = strokeColor}):Play()
                tweenService:Create(knob, info, {BackgroundColor3 = knobColor, Position = knobPosition}):Play()
            else
                track.BackgroundColor3 = trackColor
                trackStroke.Color = strokeColor
                knob.BackgroundColor3 = knobColor
                knob.Position = knobPosition
            end
        end

        refresh(false)
        table.insert(refreshers, function()
            refresh(false)
        end)
        connect(row.MouseButton1Click, function()
            setter(not getter())
            refresh(true)
            syncDerived()
        end)
        bindHover(row, function()
            row.BackgroundTransparency = 0
        end, function()
            row.BackgroundTransparency = 1
        end)
    end

    local function makeSelector(parent, title, options, getter, setter)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 46),
            BackgroundTransparency = 1,
            LayoutOrder = nextOrder(),
        }, parent)

        makeText(row, {
            Position = UDim2.fromOffset(8, 2),
            Size = UDim2.new(1, -16, 0, 18),
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = title,
        })

        local holder = create("Frame", {
            Position = UDim2.fromOffset(8, 22),
            Size = UDim2.new(1, -16, 0, 20),
            BackgroundColor3 = theme.well,
            BorderSizePixel = 0,
        }, row)
        addCorner(holder, 3)
        addStroke(holder, theme.line)

        local buttons = {}
        local count = #options

        local function refresh()
            for _, option in ipairs(options) do
                local selected = getter() == option
                local button = buttons[option]
                button.BackgroundTransparency = selected and 0 or 1
                button.TextColor3 = selected and theme.bg or theme.muted
            end
        end

        for index, option in ipairs(options) do
            local button = create("TextButton", {
                Size = UDim2.new(1 / count, -2, 1, -2),
                Position = UDim2.new((index - 1) / count, 1, 0, 1),
                BackgroundColor3 = theme.accent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = option,
                Font = fonts.mono,
                TextSize = 10,
                TextColor3 = theme.muted,
                AutoButtonColor = false,
            }, holder)
            addCorner(button, 2)
            buttons[option] = button
            connect(button.MouseButton1Click, function()
                setter(option)
                refresh()
                syncDerived()
            end)
        end

        refresh()
        table.insert(refreshers, refresh)
    end

    local function makeSlider(parent, title, minValue, maxValue, step, getter, setter, formatter)
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundTransparency = 1,
            LayoutOrder = nextOrder(),
        }, parent)

        local titleLabel = makeText(row, {
            Position = UDim2.fromOffset(8, 2),
            Size = UDim2.new(1, -84, 0, 18),
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = title,
        })

        local valueBox = create("TextBox", {
            Position = UDim2.new(1, -68, 0, 2),
            Size = UDim2.fromOffset(60, 18),
            BackgroundColor3 = theme.well,
            BorderSizePixel = 0,
            Font = fonts.mono,
            TextSize = 11,
            TextColor3 = theme.muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            ClearTextOnFocus = true,
            Text = "",
        }, row)
        addCorner(valueBox, 3)
        local valueStroke = addStroke(valueBox, theme.line)

        local hit = create("TextButton", {
            Position = UDim2.fromOffset(8, 22),
            Size = UDim2.new(1, -16, 0, 14),
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
        }, row)
        local track = create("Frame", {
            Position = UDim2.new(0, 0, 0.5, -1),
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = theme.line,
            BorderSizePixel = 0,
        }, hit)
        local fill = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = theme.accent,
            BorderSizePixel = 0,
        }, track)
        local handle = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.fromOffset(4, 12),
            BackgroundColor3 = theme.text,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, hit)
        addCorner(handle, 1)

        local function refresh()
            local value = getter()
            valueBox.Text = (formatter and formatter(value)) or tostring(value)
            local fraction = math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
            fill.Size = UDim2.fromScale(fraction, 1)
            handle.Position = UDim2.fromScale(fraction, 0.5)
        end

        local function commit(number)
            local snapped = minValue + math.floor((number - minValue) / step + 0.5) * step
            setter(math.clamp(math.floor(snapped * 1000 + 0.5) / 1000, minValue, maxValue))
            refresh()
            syncDerived()
        end

        local function valueFromX(x)
            local width = hit.AbsoluteSize.X
            if width <= 0 then
                return nil
            end
            local fraction = math.clamp((x - hit.AbsolutePosition.X) / width, 0, 1)
            return minValue + fraction * (maxValue - minValue)
        end

        local function setDim(dimmed)
            local transparency = dimmed and 0.55 or 0
            titleLabel.TextTransparency = transparency
            valueBox.TextTransparency = transparency
            fill.BackgroundTransparency = transparency
            handle.BackgroundTransparency = transparency
        end

        refresh()
        table.insert(refreshers, refresh)

        connect(hit.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            startDrag(input, function(point)
                local number = valueFromX(point.X)
                if number then
                    commit(number)
                end
            end, function()
                parent.ScrollingEnabled = true
                handle.BackgroundColor3 = theme.text
            end)
            parent.ScrollingEnabled = false
            handle.BackgroundColor3 = theme.accent
            local number = valueFromX(input.Position.X)
            if number then
                commit(number)
            end
        end)

        connect(valueBox.Focused, function()
            valueStroke.Color = theme.accent
            valueBox.TextColor3 = theme.text
        end)
        connect(valueBox.FocusLost, function()
            valueStroke.Color = theme.line
            valueBox.TextColor3 = theme.muted
            local cleaned = valueBox.Text:gsub(",", "."):gsub("[^%d%.]", "")
            local number = tonumber(cleaned)
            if number then
                commit(number)
            else
                refresh()
            end
        end)

        return setDim
    end

    local function seconds(value)
        return string.format("%.2fs", value)
    end

    local function whole(value)
        return string.format("%d", value)
    end

    local function secondsFine(value)
        return string.format("%.3fs", value)
    end

    makeSection(settingsPage, "TECH")
    makeToggle(settingsPage, "Loop Dash", function()
        return config.enabled
    end, function(value)
        setEnabled(value)
    end)
    makeToggle(settingsPage, "Dash Cooldown", function()
        return config.cooldownEnabled
    end, function(value)
        config.cooldownEnabled = value
    end)
    makeToggle(settingsPage, "NoClip", function()
        return config.noclipEnabled
    end, function(value)
        config.noclipEnabled = value
    end)

    makeSection(settingsPage, "TIMING")
    makeSlider(settingsPage, "Dash Delay", 0, 1, 0.001, function()
        return config.dashDelay
    end, function(value)
        config.dashDelay = value
    end, secondsFine)
    makeSlider(settingsPage, "Loop Delay", 0, 1, 0.001, function()
        return config.loopDelay
    end, function(value)
        config.loopDelay = value
    end, secondsFine)
    makeSlider(settingsPage, "Loop Time", 0, 2, 0.01, function()
        return config.loopDuration
    end, function(value)
        config.loopDuration = value
    end, seconds)
    makeSlider(settingsPage, "Jump Delay", 0, 1, 0.001, function()
        return config.jumpDelay
    end, function(value)
        config.jumpDelay = value
    end, secondsFine)
    makeToggle(settingsPage, "Smooth", function()
        return config.camSmooth
    end, function(value)
        config.camSmooth = value
        if not value then
            updateCamSmooth(false)
        end
    end)
    dimWhen(makeSlider(settingsPage, "Smooth Time", 0.2, 3, 0.1, function()
        return config.camDuration
    end, function(value)
        config.camDuration = value
    end, seconds), function()
        return not config.camSmooth
    end)
    dimWhen(makeSlider(settingsPage, "Smooth Delay", 0, 1, 0.05, function()
        return config.camSmoothDelay
    end, function(value)
        config.camSmoothDelay = value
    end, seconds), function()
        return not config.camSmooth
    end)

    makeSection(settingsPage, "MOTION")
    makeSlider(settingsPage, "Jump Force", 0, 100, 1, function()
        return config.jumpForce
    end, function(value)
        config.jumpForce = value
    end, whole)

    local capturingHotkey = false

    if userInputService.KeyboardEnabled then
        makeSection(cameraPage, "INPUT")
        local hotkeyRow = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = theme.raised,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = nextOrder(),
        }, cameraPage)
        addCorner(hotkeyRow, 4)
        makeText(hotkeyRow, {
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.new(1, -108, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "toggle tech hotkey:",
        })
        local keyBox = makeText(hotkeyRow, {
            Position = UDim2.new(1, -92, 0.5, -9),
            Size = UDim2.fromOffset(84, 18),
            BackgroundTransparency = 0,
            BackgroundColor3 = theme.well,
            Font = fonts.mono,
            TextSize = 10,
            TextColor3 = theme.muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        addCorner(keyBox, 3)
        local keyStroke = addStroke(keyBox, theme.line)

        local function refreshHotkey()
            if capturingHotkey then
                keyBox.Text = "press key"
                keyBox.TextColor3 = theme.accent
                keyStroke.Color = theme.accent
            else
                keyBox.Text = config.hotkey.Name
                keyBox.TextColor3 = theme.muted
                keyStroke.Color = theme.line
            end
        end

        refreshHotkey()
        table.insert(refreshers, refreshHotkey)
        connect(hotkeyRow.MouseButton1Click, function()
            capturingHotkey = true
            refreshHotkey()
        end)
        bindHover(hotkeyRow, function()
            hotkeyRow.BackgroundTransparency = 0
        end, function()
            hotkeyRow.BackgroundTransparency = 1
        end)
    end

    connect(userInputService.InputBegan, function(input, processed)
        if not isAlive() then
            return
        end
        if capturingHotkey then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode ~= Enum.KeyCode.Escape then
                    config.hotkey = input.KeyCode
                end
                capturingHotkey = false
                refreshWidgets()
            end
            return
        end
        if processed then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == config.hotkey then
            setEnabled(not config.enabled)
            notify(config.enabled and "Enabled" or "Disabled")
        end
    end)

    local maxSlots = 5
    local namesFile = "UppercutPatternGuiConfigNames.json"

    local schema = {
        {key = "enabled", kind = "boolean"},
        {key = "cooldownEnabled", kind = "boolean"},
        {key = "noclipEnabled", kind = "boolean"},
        {key = "dashDelay", kind = "number", min = 0, max = 1},
        {key = "loopDelay", kind = "number", min = 0, max = 1},
        {key = "loopDuration", kind = "number", min = 0, max = 2},
        {key = "jumpDelay", kind = "number", min = 0, max = 1},
        {key = "jumpForce", kind = "number", min = 0, max = 100},
        {key = "camSmooth", kind = "boolean"},
        {key = "camSmoothDelay", kind = "number", min = 0, max = 1},
        {key = "camDuration", kind = "number", min = 0.2, max = 3},
        {key = "hotkey", kind = "keycode"},
    }

    local function slotFile(slot)
        return "UppercutPatternGuiConfig" .. slot .. ".json"
    end

    local function readSlot(slot)
        local ok, data = pcall(function()
            return httpService:JSONDecode(readfile(slotFile(slot)))
        end)
        if ok and type(data) == "table" then
            return data
        end
        return nil
    end

    local customNames = {}
    do
        local ok, data = pcall(function()
            return httpService:JSONDecode(readfile(namesFile))
        end)
        if ok and type(data) == "table" then
            for slot = 1, maxSlots do
                local name = data[tostring(slot)]
                if type(name) == "string" and name ~= "" then
                    customNames[slot] = name
                end
            end
        end
    end

    local function saveNames()
        local out = {}
        for slot = 1, maxSlots do
            if customNames[slot] then
                out[tostring(slot)] = customNames[slot]
            end
        end
        pcall(function()
            writefile(namesFile, httpService:JSONEncode(out))
        end)
    end

    local function commitName(slot, text)
        local trimmed = tostring(text):match("^%s*(.-)%s*$")
        local default = "Config " .. slot
        if trimmed == "" or trimmed == default then
            customNames[slot] = nil
            trimmed = default
        else
            customNames[slot] = trimmed
        end
        saveNames()
        return trimmed
    end

    local statusToken = 0
    local function showStatus(text)
        statusToken = statusToken + 1
        local token = statusToken
        statusLabel.Text = text
        task.delay(2, function()
            if token == statusToken and statusLabel.Parent then
                statusLabel.Text = ""
            end
        end)
    end

    local function applyConfig(data)
        local applied = 0
        for _, entry in ipairs(schema) do
            local value = data[entry.key]
            if entry.kind == "boolean" then
                if type(value) == "string" then
                    local lowered = value:lower()
                    if lowered == "true" then
                        value = true
                    elseif lowered == "false" then
                        value = false
                    end
                end
                if type(value) == "boolean" then
                    if entry.key == "enabled" then
                        setEnabled(value)
                    else
                        config[entry.key] = value
                    end
                    applied = applied + 1
                end
            elseif entry.kind == "number" then
                if type(value) == "string" then
                    value = tonumber(value)
                end
                if type(value) == "number" then
                    config[entry.key] = math.clamp(value, entry.min, entry.max)
                    applied = applied + 1
                end
            elseif entry.kind == "keycode" then
                if type(value) == "string" then
                    local ok, code = pcall(function()
                        return Enum.KeyCode[value]
                    end)
                    if ok and code then
                        config[entry.key] = code
                        applied = applied + 1
                    end
                end
            end
        end
        if not config.camSmooth then
            updateCamSmooth(false)
        end
        refreshWidgets()
        return applied
    end

    addList(configsPage, 6)
    addPadding(configsPage, pad, pad, 10, 10)

    local pasteRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(),
    }, configsPage)

    local pasteBox = create("TextBox", {
        Size = UDim2.new(1, -62, 1, 0),
        BackgroundColor3 = theme.well,
        BorderSizePixel = 0,
        TextColor3 = theme.text,
        PlaceholderColor3 = theme.dim,
        PlaceholderText = "Paste config here",
        Text = "",
        Font = fonts.label,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, pasteRow)
    addCorner(pasteBox, 3)
    local pasteStroke = addStroke(pasteBox, theme.line)
    addPadding(pasteBox, 8, 6, 0, 0)

    connect(pasteBox.Focused, function()
        pasteStroke.Color = theme.accent
    end)
    connect(pasteBox.FocusLost, function()
        pasteStroke.Color = theme.line
    end)

    local applyColor = theme.accent
    local applyHoverColor = theme.accent:Lerp(Color3.new(1, 1, 1), 0.18)
    local applyButton = create("TextButton", {
        Size = UDim2.new(0, 56, 1, 0),
        Position = UDim2.new(1, -56, 0, 0),
        BackgroundColor3 = applyColor,
        BorderSizePixel = 0,
        TextColor3 = theme.bg,
        Font = fonts.mono,
        TextSize = 10,
        Text = "APPLY",
        AutoButtonColor = false,
    }, pasteRow)
    addCorner(applyButton, 3)
    bindHover(applyButton, function()
        applyButton.BackgroundColor3 = applyHoverColor
    end, function()
        applyButton.BackgroundColor3 = applyColor
    end)

    connect(applyButton.MouseButton1Click, function()
        local text = tostring(pasteBox.Text)
        text = text:gsub("“", '"'):gsub("”", '"'):gsub("‘", "'"):gsub("’", "'")
        text = text:match("^%s*(.-)%s*$")
        if text == "" then
            showStatus("Paste first")
            return
        end
        if text:sub(1, 1) ~= "{" then
            text = "{" .. text .. "}"
        end
        local ok, data = pcall(function()
            return httpService:JSONDecode(text)
        end)
        if not ok or type(data) ~= "table" then
            showStatus("Invalid config")
            return
        end
        if applyConfig(data) == 0 then
            showStatus("No fields")
            return
        end
        showStatus("Applied")
    end)

    for slot = 1, maxSlots do
        local row = create("Frame", {
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            LayoutOrder = nextOrder(),
        }, configsPage)

        local mark = makeText(row, {
            Size = UDim2.new(0, 18, 1, 0),
            Font = fonts.mono,
            TextSize = 10,
            TextColor3 = readSlot(slot) and theme.accent or theme.dim,
            Text = string.format("%02d", slot),
        })

        local nameBox = create("TextBox", {
            Position = UDim2.fromOffset(22, 0),
            Size = UDim2.new(1, -(22 + 112 + 4), 1, 0),
            BackgroundColor3 = theme.well,
            BorderSizePixel = 0,
            TextColor3 = theme.text,
            PlaceholderColor3 = theme.dim,
            Font = fonts.label,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            TextTruncate = Enum.TextTruncate.AtEnd,
            PlaceholderText = "Config " .. slot,
            Text = "Config " .. slot,
        }, row)
        addCorner(nameBox, 3)
        local nameStroke = addStroke(nameBox, theme.line)
        addPadding(nameBox, 8, 6, 0, 0)

        connect(nameBox.Focused, function()
            nameStroke.Color = theme.accent
        end)
        connect(nameBox.FocusLost, function()
            nameStroke.Color = theme.line
            nameBox.Text = commitName(slot, nameBox.Text)
        end)
        connect(nameBox:GetPropertyChangedSignal("Text"), function()
            if not nameBox:IsFocused() then
                return
            end
            local trimmed = tostring(nameBox.Text):match("^%s*(.-)%s*$")
            if trimmed == "" or trimmed == "Config " .. slot then
                customNames[slot] = nil
            else
                customNames[slot] = trimmed
            end
            saveNames()
        end)

        if customNames[slot] then
            nameBox.Text = customNames[slot]
        else
            local data = readSlot(slot)
            if data and type(data.ConfigName) == "string" and data.ConfigName ~= "" then
                nameBox.Text = data.ConfigName
                customNames[slot] = data.ConfigName
            end
        end

        local function makeSlotButton(text, index)
            local button = create("TextButton", {
                Size = UDim2.new(0, 36, 1, 0),
                Position = UDim2.new(1, -112 + (index - 1) * 38, 0, 0),
                BackgroundColor3 = theme.raised,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                TextColor3 = theme.muted,
                Font = fonts.mono,
                TextSize = 10,
                Text = text,
                AutoButtonColor = false,
            }, row)
            addCorner(button, 3)
            local hovered, armed = false, false
            local function render()
                if armed then
                    button.BackgroundColor3 = theme.accent
                    button.BackgroundTransparency = 0
                    button.TextColor3 = theme.bg
                else
                    button.BackgroundColor3 = theme.raised
                    button.BackgroundTransparency = hovered and 0 or 1
                    button.TextColor3 = hovered and theme.text or theme.muted
                end
            end
            bindHover(button, function()
                hovered = true
                render()
            end, function()
                hovered = false
                render()
            end)
            return button, function(value)
                armed = value
                render()
            end
        end

        local saveButton = makeSlotButton("SAVE", 1)
        local loadButton = makeSlotButton("LOAD", 2)
        local deleteButton, setDeleteArmed = makeSlotButton("DEL", 3)

        connect(saveButton.MouseButton1Click, function()
            local name = commitName(slot, nameBox.Text)
            nameBox.Text = name
            local data = {ConfigName = name}
            for _, entry in ipairs(schema) do
                if entry.kind == "keycode" then
                    data[entry.key] = config[entry.key].Name
                else
                    data[entry.key] = config[entry.key]
                end
            end
            local ok = pcall(function()
                writefile(slotFile(slot), httpService:JSONEncode(data))
            end)
            if ok then
                mark.TextColor3 = theme.accent
            end
            showStatus(ok and "Saved" or "Save failed")
        end)

        connect(loadButton.MouseButton1Click, function()
            local data = readSlot(slot)
            if not data then
                showStatus("Empty slot")
                return
            end
            applyConfig(data)
            if not customNames[slot] and type(data.ConfigName) == "string" and data.ConfigName ~= "" then
                customNames[slot] = data.ConfigName
                nameBox.Text = data.ConfigName
                saveNames()
            end
            showStatus("Loaded")
        end)

        local deleteToken = 0
        local deleteArmed = false
        connect(deleteButton.MouseButton1Click, function()
            if not deleteArmed then
                deleteArmed = true
                deleteToken = deleteToken + 1
                local token = deleteToken
                deleteButton.Text = "SURE?"
                setDeleteArmed(true)
                task.delay(2, function()
                    if token == deleteToken and deleteArmed and deleteButton.Parent then
                        deleteArmed = false
                        deleteButton.Text = "DEL"
                        setDeleteArmed(false)
                    end
                end)
                return
            end
            deleteArmed = false
            deleteToken = deleteToken + 1
            deleteButton.Text = "DEL"
            setDeleteArmed(false)
            local hasFile = readSlot(slot) ~= nil
            local hasName = customNames[slot] ~= nil
            if not hasFile and not hasName then
                showStatus("Empty slot")
                return
            end
            local ok = true
            if hasFile then
                ok = pcall(function()
                    delfile(slotFile(slot))
                end)
            end
            if ok then
                customNames[slot] = nil
                saveNames()
                nameBox.Text = "Config " .. slot
                mark.TextColor3 = theme.dim
                showStatus("Deleted")
            else
                showStatus("Delete failed")
            end
        end)
    end

    switchTab("settings")
    syncDerived()

    local closeArmedUntil = 0
    local stateColors = {
        OFF = theme.dim,
        READY = theme.text,
        ARMED = theme.accent,
        PATTERN = theme.accent,
        CD = theme.muted,
    }

    connect(runService.Heartbeat, function()
        local now = os.clock()
        local remaining = config.dashCooldown - (now - lastDashTime)
        local cooldownActive = config.cooldownEnabled
            and remaining > 0
            and not workspace:GetAttribute("NoDashCooldown")

        local state
        if not config.enabled then
            state = "OFF"
        elseif activeRun then
            state = "PATTERN"
        elseif dashPending then
            state = "ARMED"
        elseif cooldownActive then
            state = "CD"
        else
            state = "READY"
        end

        local stateColor = stateColors[state]
        if stateMark.BackgroundColor3 ~= stateColor then
            stateMark.BackgroundColor3 = stateColor
        end
        stateMark.BackgroundTransparency = (state == "ARMED" and math.floor(now * 8) % 2 == 1) and 0.65 or 0

        local closeColor = now < closeArmedUntil and theme.accent or theme.muted
        if closeButton.TextColor3 ~= closeColor then
            closeButton.TextColor3 = closeColor
        end
    end)

    local minimized = false
    connect(minimizeButton.MouseButton1Click, function()
        minimized = not minimized
        minimizeButton.Text = minimized and "+" or "–"
        if not minimized then
            body.Visible = true
        end
        local tween = tweenService:Create(mainFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(windowWidth, minimized and headerHeight or windowHeight),
        })
        tween.Completed:Connect(function()
            if minimized then
                body.Visible = false
            end
        end)
        tween:Play()
    end)

    connect(closeButton.MouseButton1Click, function()
        local now = os.clock()
        if now < closeArmedUntil then
            pcall(getgenv().uppercutDetectorCleanup)
            return
        end
        closeArmedUntil = now + 2
        notify("Tap close again to close the UI")
    end)

    connect(header.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local originPosition = mainFrame.Position
        local originAbsolute = mainFrame.AbsolutePosition
        local startPoint = input.Position
        startDrag(input, function(point)
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or screenGui.AbsoluteSize
            local targetX = math.clamp(originAbsolute.X + (point.X - startPoint.X), 40 - windowWidth, viewport.X - 40)
            local targetY = math.clamp(originAbsolute.Y + (point.Y - startPoint.Y), 0, viewport.Y - headerHeight)
            mainFrame.Position = UDim2.new(
                originPosition.X.Scale, originPosition.X.Offset + (targetX - originAbsolute.X),
                originPosition.Y.Scale, originPosition.Y.Offset + (targetY - originAbsolute.Y)
            )
        end)
    end)
end

local function getAnimationId(animation)
    if not animation then
        return nil
    end
    return tostring(animation.AnimationId):match("%d+")
end

local function fireDash(character)
    local communicate = character and character:FindFirstChild("Communicate")
    if not communicate then
        return
    end
    pcall(function()
        communicate:FireServer({
            Dash = Enum.KeyCode.W,
            Key = Enum.KeyCode.Q,
            Goal = "KeyPress",
        })
    end)
end

local function onDashStart(track)
    if config.debugAnim then
        print("[uppercutDetector] dash started", getAnimationId(track.Animation))
    end
    pcall(camOnDashStart)
end

local function waitUntil(moment)
    local remaining = moment - os.clock()
    if remaining > 0 then
        task.wait(remaining)
    end
end

local function cycleActive(id, character, humanoid)
    return isAlive()
        and config.enabled
        and cycleId == id
        and character == localPlayer.Character
        and humanoid.Health > 0
end

local function runLoop(id, character, humanoid, rootPart, startTime)
    waitUntil(startTime + config.loopDelay)
    if config.loopDuration > 0 and cycleActive(id, character, humanoid) then
        pcall(startPattern, character, humanoid, rootPart)
    end
end

local function runJump(id, character, humanoid, rootPart, startTime)
    waitUntil(startTime + config.jumpDelay)
    if config.jumpForce > 0 and cycleActive(id, character, humanoid) and rootPart.Parent then
        local velocity = rootPart.AssemblyLinearVelocity
        rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, config.jumpForce, velocity.Z)
    end
end

local function onAnimation(character, humanoid, rootPart, track)
    if not isAlive() then
        return
    end
    local animationId = getAnimationId(track.Animation)
    if not animationId then
        return
    end
    if config.debugAnim then
        print("[uppercutDetector] anim", animationId)
    end
    if not config.enabled then
        if dashAnimIds[animationId] then
            lastDashTime = os.clock()
        end
        return
    end

    if uppercutAnimIds[animationId] then
        if dashPending then
            return
        end
        if config.cooldownEnabled
            and not workspace:GetAttribute("NoDashCooldown")
            and os.clock() - lastDashTime < config.dashCooldown then
            return
        end
        local startTime = os.clock()
        cycleId = cycleId + 1
        local id = cycleId
        dashPending = true
        dashStarted = false
        windowEnd = startTime + config.dashDelay + config.dashWait
        task.spawn(runLoop, id, character, humanoid, rootPart, startTime)
        task.spawn(runJump, id, character, humanoid, rootPart, startTime)
        waitUntil(startTime + config.dashDelay)
        local deadline = os.clock() + config.dashWait
        while not dashStarted and os.clock() < deadline do
            if not cycleActive(id, character, humanoid) then
                break
            end
            fireDash(character)
            task.wait(config.dashRetry)
        end
        if cycleId == id then
            dashPending = false
        end
        return
    end

    if dashAnimIds[animationId] then
        lastDashTime = os.clock()
        dashStarted = true
        if os.clock() <= windowEnd then
            windowEnd = 0
            onDashStart(track)
        end
    end
end

local function disconnectCharConnections()
    for _, connection in ipairs(charConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(charConnections)
end

local function onCharacter(character)
    disconnectCharConnections()
    dashPending = false
    windowEnd = 0
    pcall(stopPattern)
    pcall(camOnDashEnd)
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    if not isAlive() or character ~= localPlayer.Character then
        return
    end
    disconnectCharConnections()
    table.insert(charConnections, humanoid.AnimationPlayed:Connect(function(track)
        task.spawn(onAnimation, character, humanoid, rootPart, track)
    end))
end

local characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character)
    task.spawn(onCharacter, character)
end)

getgenv().uppercutDetectorCleanup = function()
    if getgenv().uppercutDetectorId == sessionId then
        getgenv().uppercutDetectorId = nil
    end
    pcall(function()
        characterAddedConnection:Disconnect()
    end)
    disconnectCharConnections()
    for _, connection in ipairs(sessionConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(sessionConnections)
    pcall(stopPattern)
    pcall(camOnDashEnd)
    if screenGui then
        pcall(function()
            screenGui:Destroy()
        end)
        screenGui = nil
    end
end

local uiOk, uiError = pcall(buildUI)
if not uiOk then
    warn("[loopDash] gui failed:", uiError)
end

if localPlayer.Character then
    task.spawn(onCharacter, localPlayer.Character)
end