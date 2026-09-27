--[[
╔══════════════════════════════════════════════════════════════════╗
║                         JHAYDEE                                  ║
║              Rendered Eggs ESP + Teleport                        ║
║                                                                  ║
║ • ESP all Models inside workspace.RenderedEggs                   ║
║ • Show name + distance at any range                              ║
║ • Group Eggs by name                                             ║
║ • Collapse / expand groups                                       ║
║ • Global ESP ON/OFF                                              ║
║ • Per-Egg-type ESP ON/OFF                                        ║
║ • Search Eggs                                                    ║
║ • Direct TP button for each Egg                                  ║
║ • Newly spawned Eggs are detected automatically                  ║
║ • Automatically find the LocalPlayer plot using Data.Owner       ║
║ • workspace.Plots is scanned at most 2 times                     ║
║ • TP 10 studs above the Egg / Baseplate                          ║
║ • No script-side teleport distance limit                         ║
╚══════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local RenderedEggs = workspace:FindFirstChild("RenderedEggs")
local Plots = workspace:FindFirstChild("Plots")

if not RenderedEggs then
    warn("[JHAYDEE] workspace.RenderedEggs was not found")
    return
end

if not Plots then
    warn("[JHAYDEE] workspace.Plots was not found")
end


--==============================================================
-- SETTINGS
--==============================================================

local UPDATE_RATE = 0.20
local HEIGHT_OFFSET = 10
local SHOW_HIGHLIGHT = true


--==============================================================
-- STATE
--==============================================================

local Running = true
local GlobalESPEnabled = true
local PanelVisible = true

local ESPs = {}
local EggEntries = {}
local EggGroups = {}
local Connections = {}

local Character = nil
local RootPart = nil

local PlotScanCount = 0
local CachedMyPlot = nil
local CachedBaseplate = nil
local MAX_PLOT_SCANS = 2

local updateSearch = nil
local getEggTopCFrame = nil
local safeTeleport = nil


--==============================================================
-- UTILITY
--==============================================================

local function isFiniteNumber(value)
    return typeof(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function isValidPosition(position)
    if typeof(position) ~= "Vector3" then
        return false
    end
    return isFiniteNumber(position.X)
        and isFiniteNumber(position.Y)
        and isFiniteNumber(position.Z)
end

local function getCharacter()
    Character = LocalPlayer.Character
    if not Character then
        RootPart = nil
        return nil
    end
    RootPart = Character:FindFirstChild("HumanoidRootPart")
        or Character:FindFirstChild("UpperTorso")
        or Character:FindFirstChild("Torso")
    return Character
end

getCharacter()

Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function(character)
    Character = character
    RootPart = character:WaitForChild("HumanoidRootPart", 10)
end)

local function getRootPart(model)
    if not model or not model:IsA("Model") then
        return nil
    end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end
    local root = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("RootPart")
        or model:FindFirstChild("Handle")
    if root and root:IsA("BasePart") then
        return root
    end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getEggTypeEnabled(model)
    if not model then return true end
    local group = EggGroups[model.Name]
    if group then
        return group.TypeESPEnabled
    end
    return true
end


--==============================================================
-- COLORS (modern dark theme)
--==============================================================

local Colors = {
    Background   = Color3.fromRGB(6, 10, 22),
    Surface      = Color3.fromRGB(10, 18, 38),
    SurfaceAlt   = Color3.fromRGB(14, 28, 55),
    Border       = Color3.fromRGB(0, 180, 255),
    Accent       = Color3.fromRGB(0, 200, 255),
    AccentSoft   = Color3.fromRGB(0, 140, 220),
    Text         = Color3.fromRGB(220, 245, 255),
    TextDim      = Color3.fromRGB(120, 180, 220),
    Success      = Color3.fromRGB(0, 230, 180),
    Danger       = Color3.fromRGB(255, 60, 100),
    Info         = Color3.fromRGB(0, 170, 255),
}


--==============================================================
-- GUI
--==============================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "JHAYDEE"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui


--==============================================================
-- FLOATING TOGGLE BUTTON
--==============================================================

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "ToggleButton"
ToggleBtn.Size = UDim2.new(0, 46, 0, 46)
ToggleBtn.Position = UDim2.new(0, 18, 0.28, 0)
ToggleBtn.AnchorPoint = Vector2.new(0, 0.5)
ToggleBtn.BackgroundColor3 = Colors.Accent
ToggleBtn.Text = "J"
ToggleBtn.TextColor3 = Color3.new(1, 1, 1)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 22
ToggleBtn.AutoButtonColor = false
ToggleBtn.Parent = ScreenGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 14)
ToggleCorner.Parent = ToggleBtn

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(0, 220, 255)
ToggleStroke.Thickness = 2
ToggleStroke.Transparency = 0.25
ToggleStroke.Parent = ToggleBtn


--==============================================================
-- MAIN PANEL (smaller)
--==============================================================

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 300, 0, 400)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3 = Colors.Background
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Visible = true
Main.Parent = ScreenGui

local MainScale = Instance.new("UIScale")
MainScale.Scale = 0.92
MainScale.Parent = Main

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 16)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Colors.Border
MainStroke.Thickness = 1.8
MainStroke.Transparency = 0.15
MainStroke.Parent = Main


--==============================================================
-- TOP BAR
--==============================================================

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 46)
TopBar.BackgroundColor3 = Colors.Surface
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 16)
TopCorner.Parent = TopBar

-- Fix bottom corners of top bar
local TopFix = Instance.new("Frame")
TopFix.Size = UDim2.new(1, 0, 0, 16)
TopFix.Position = UDim2.new(0, 0, 1, -16)
TopFix.BackgroundColor3 = Colors.Surface
TopFix.BorderSizePixel = 0
TopFix.Parent = TopBar

local Accent = Instance.new("Frame")
Accent.Size = UDim2.new(0, 4, 1, -18)
Accent.Position = UDim2.new(0, 10, 0, 9)
Accent.BackgroundColor3 = Colors.Accent
Accent.BorderSizePixel = 0
Accent.Parent = TopBar

local AccentCorner = Instance.new("UICorner")
AccentCorner.CornerRadius = UDim.new(1, 0)
AccentCorner.Parent = Accent

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 24, 0, 0)
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextColor3 = Colors.Text
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "JHAYDEE"
Title.Parent = TopBar

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 32, 0, 32)
Close.Position = UDim2.new(1, -40, 0.5, -16)
Close.BackgroundColor3 = Colors.Danger
Close.Text = "×"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 18
Close.AutoButtonColor = false
Close.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = Close


--==============================================================
-- CONTROL BUTTONS
--==============================================================

local GlobalToggle = Instance.new("TextButton")
GlobalToggle.Size = UDim2.new(0, 92, 0, 32)
GlobalToggle.Position = UDim2.new(0, 10, 0, 58)
GlobalToggle.BackgroundColor3 = Colors.Success
GlobalToggle.Text = "ESP  •  ON"
GlobalToggle.TextColor3 = Color3.new(1, 1, 1)
GlobalToggle.Font = Enum.Font.GothamBold
GlobalToggle.TextSize = 11
GlobalToggle.AutoButtonColor = false
GlobalToggle.Parent = Main

local GlobalCorner = Instance.new("UICorner")
GlobalCorner.CornerRadius = UDim.new(0, 8)
GlobalCorner.Parent = GlobalToggle

local PlotTP = Instance.new("TextButton")
PlotTP.Size = UDim2.new(0, 92, 0, 32)
PlotTP.Position = UDim2.new(0, 108, 0, 58)
PlotTP.BackgroundColor3 = Colors.Info
PlotTP.Text = "My Plot"
PlotTP.TextColor3 = Color3.new(1, 1, 1)
PlotTP.Font = Enum.Font.GothamBold
PlotTP.TextSize = 11
PlotTP.AutoButtonColor = false
PlotTP.Parent = Main

local PlotTPCorner = Instance.new("UICorner")
PlotTPCorner.CornerRadius = UDim.new(0, 8)
PlotTPCorner.Parent = PlotTP

local CountLabel = Instance.new("TextLabel")
CountLabel.Size = UDim2.new(0, 80, 0, 32)
CountLabel.Position = UDim2.new(1, -90, 0, 58)
CountLabel.BackgroundColor3 = Colors.SurfaceAlt
CountLabel.Text = "Egg: 0"
CountLabel.TextColor3 = Colors.Text
CountLabel.Font = Enum.Font.GothamBold
CountLabel.TextSize = 11
CountLabel.Parent = Main

local CountCorner = Instance.new("UICorner")
CountCorner.CornerRadius = UDim.new(0, 8)
CountCorner.Parent = CountLabel


--==============================================================
-- SEARCH
--==============================================================

local SearchBox = Instance.new("Frame")
SearchBox.Size = UDim2.new(1, -20, 0, 34)
SearchBox.Position = UDim2.new(0, 10, 0, 98)
SearchBox.BackgroundColor3 = Colors.Surface
SearchBox.BorderSizePixel = 0
SearchBox.Parent = Main

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 9)
SearchCorner.Parent = SearchBox

local SearchIcon = Instance.new("TextLabel")
SearchIcon.Size = UDim2.new(0, 32, 1, 0)
SearchIcon.BackgroundTransparency = 1
SearchIcon.Text = "⌕"
SearchIcon.TextColor3 = Colors.TextDim
SearchIcon.Font = Enum.Font.GothamBold
SearchIcon.TextSize = 16
SearchIcon.Parent = SearchBox

local Search = Instance.new("TextBox")
Search.Position = UDim2.new(0, 32, 0, 0)
Search.Size = UDim2.new(1, -38, 1, 0)
Search.BackgroundTransparency = 1
Search.TextColor3 = Colors.Text
Search.PlaceholderColor3 = Colors.TextDim
Search.PlaceholderText = "Search egg type..."
Search.Text = ""
Search.ClearTextOnFocus = false
Search.Font = Enum.Font.Gotham
Search.TextSize = 12
Search.TextXAlignment = Enum.TextXAlignment.Left
Search.Parent = SearchBox


--==============================================================
-- SCROLL LIST
--==============================================================

local List = Instance.new("ScrollingFrame")
List.Size = UDim2.new(1, -20, 0, 220)
List.Position = UDim2.new(0, 10, 0, 140)
List.BackgroundColor3 = Colors.Surface
List.BorderSizePixel = 0
List.ClipsDescendants = true
List.ScrollingDirection = Enum.ScrollingDirection.Y
List.ScrollBarThickness = 3
List.ScrollBarImageTransparency = 0.3
List.ScrollBarImageColor3 = Colors.Accent
List.CanvasSize = UDim2.new(0, 0, 0, 0)
List.AutomaticCanvasSize = Enum.AutomaticSize.None
List.Parent = Main

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 10)
ListCorner.Parent = List

local ListPadding = Instance.new("UIPadding")
ListPadding.PaddingTop = UDim.new(0, 6)
ListPadding.PaddingBottom = UDim.new(0, 6)
ListPadding.PaddingLeft = UDim.new(0, 6)
ListPadding.PaddingRight = UDim.new(0, 6)
ListPadding.Parent = List

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 4)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = List

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    List.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 12)
end)


--==============================================================
-- STATUS
--==============================================================

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 32)
Status.Position = UDim2.new(0, 10, 0, 368)
Status.BackgroundColor3 = Colors.Surface
Status.Font = Enum.Font.Gotham
Status.TextSize = 11
Status.TextTruncate = Enum.TextTruncate.AtEnd
Status.TextYAlignment = Enum.TextYAlignment.Center
Status.TextColor3 = Colors.TextDim
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = ""
Status.Parent = Main

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 8)
StatusCorner.Parent = Status

local StatusPadding = Instance.new("UIPadding")
StatusPadding.PaddingLeft = UDim.new(0, 10)
StatusPadding.PaddingRight = UDim.new(0, 10)
StatusPadding.Parent = Status

local StatusExpiresAt = 0

local function showStatus(message, duration)
    Status.Text = message
    StatusExpiresAt = os.clock() + (duration or 3)
end


--==============================================================
-- OPEN / CLOSE LOGIC
--==============================================================

local function setPanelVisible(visible)
    PanelVisible = visible
    Main.Visible = visible

    if visible then
        ToggleBtn.Text = "J"
        ToggleBtn.BackgroundColor3 = Colors.Accent
    else
        ToggleBtn.Text = "J"
        ToggleBtn.BackgroundColor3 = Colors.SurfaceAlt
    end
end

ToggleBtn.MouseButton1Click:Connect(function()
    setPanelVisible(not PanelVisible)
end)

-- Soft hover effect on toggle
ToggleBtn.MouseEnter:Connect(function()
    TweenService:Create(ToggleBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = Colors.AccentSoft
    }):Play()
end)

ToggleBtn.MouseLeave:Connect(function()
    local target = PanelVisible and Colors.Accent or Colors.SurfaceAlt
    TweenService:Create(ToggleBtn, TweenInfo.new(0.15), {
        BackgroundColor3 = target
    }):Play()
end)


--==============================================================
-- DRAG
--==============================================================

local dragging = false
local dragStart = nil
local startPosition = nil

TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = Main.Position
    end
end)

TopBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

Connections.InputChanged = UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local delta = input.Position - dragStart
    Main.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end)


--==============================================================
-- CREATE ESP
--==============================================================

local function createESP(model)
    if not model or not model:IsA("Model") or not model.Parent then return end
    if ESPs[model] then return end

    local root = getRootPart(model)
    if not root then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EggESP"
    billboard.Adornee = root
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 180, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.Enabled = GlobalESPEnabled and getEggTypeEnabled(model)
    billboard.Parent = root

    local label = Instance.new("TextLabel")
    label.Name = "Info"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.2
    label.Text = model.Name
    label.Parent = billboard

    local highlight = nil
    if SHOW_HIGHLIGHT then
        highlight = Instance.new("Highlight")
        highlight.Name = "EggHighlight"
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0.1
        highlight.Adornee = model
        highlight.Enabled = GlobalESPEnabled and getEggTypeEnabled(model)
        highlight.Parent = model
    end

    ESPs[model] = {
        Billboard = billboard,
        Label = label,
        Highlight = highlight
    }
end

local function destroyESP(model)
    local esp = ESPs[model]
    if not esp then return end
    if esp.Billboard then esp.Billboard:Destroy() end
    if esp.Highlight then esp.Highlight:Destroy() end
    ESPs[model] = nil
end


--==============================================================
-- CREATE GROUP
--==============================================================

local function createEggGroup(groupName)
    if EggGroups[groupName] then
        return EggGroups[groupName]
    end

    local group = {
        Name = groupName,
        Eggs = {},
        Expanded = true,
        TypeESPEnabled = true,
        GroupFrame = nil,
        Header = nil,
        Container = nil,
        HeaderTitle = nil,
        TypeESPButton = nil
    }

    local GroupFrame = Instance.new("Frame")
    GroupFrame.Name = "Group_" .. groupName
    GroupFrame.Size = UDim2.new(1, -2, 0, 30)
    GroupFrame.BackgroundTransparency = 1
    GroupFrame.AutomaticSize = Enum.AutomaticSize.Y
    GroupFrame.Parent = List

    local GroupLayout = Instance.new("UIListLayout")
    GroupLayout.Padding = UDim.new(0, 2)
    GroupLayout.SortOrder = Enum.SortOrder.LayoutOrder
    GroupLayout.Parent = GroupFrame

    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, -2, 0, 30)
    Header.BackgroundColor3 = Colors.SurfaceAlt
    Header.BorderSizePixel = 0
    Header.LayoutOrder = 1
    Header.Parent = GroupFrame

    local HeaderCorner = Instance.new("UICorner")
    HeaderCorner.CornerRadius = UDim.new(0, 7)
    HeaderCorner.Parent = Header

    local Toggle = Instance.new("TextButton")
    Toggle.Size = UDim2.new(1, -72, 1, 0)
    Toggle.BackgroundTransparency = 1
    Toggle.TextXAlignment = Enum.TextXAlignment.Left
    Toggle.Font = Enum.Font.GothamBold
    Toggle.TextSize = 11
    Toggle.TextTruncate = Enum.TextTruncate.AtEnd
    Toggle.TextColor3 = Colors.Text
    Toggle.Text = "▼  " .. groupName
    Toggle.Parent = Header

    local TypeESP = Instance.new("TextButton")
    TypeESP.Size = UDim2.new(0, 58, 0, 22)
    TypeESP.Position = UDim2.new(1, -64, 0, 4)
    TypeESP.BackgroundColor3 = Colors.Success
    TypeESP.Text = "ESP"
    TypeESP.TextColor3 = Color3.new(1, 1, 1)
    TypeESP.Font = Enum.Font.GothamBold
    TypeESP.TextSize = 10
    TypeESP.AutoButtonColor = false
    TypeESP.Parent = Header

    local TypeCorner = Instance.new("UICorner")
    TypeCorner.CornerRadius = UDim.new(0, 6)
    TypeCorner.Parent = TypeESP

    local Container = Instance.new("Frame")
    Container.Name = "Container"
    Container.Size = UDim2.new(1, -2, 0, 0)
    Container.BackgroundTransparency = 1
    Container.AutomaticSize = Enum.AutomaticSize.Y
    Container.Visible = true
    Container.LayoutOrder = 2
    Container.Parent = GroupFrame

    local ContainerLayout = Instance.new("UIListLayout")
    ContainerLayout.Padding = UDim.new(0, 2)
    ContainerLayout.Parent = Container

    group.GroupFrame = GroupFrame
    group.Header = Header
    group.Container = Container
    group.HeaderTitle = Toggle
    group.TypeESPButton = TypeESP
    EggGroups[groupName] = group

    Toggle.MouseButton1Click:Connect(function()
        group.Expanded = not group.Expanded
        Container.Visible = group.Expanded
        GroupFrame.AutomaticSize = Enum.AutomaticSize.Y
        Toggle.Text = (group.Expanded and "▼  " or "▶  ") .. groupName
    end)

    TypeESP.MouseButton1Click:Connect(function()
        group.TypeESPEnabled = not group.TypeESPEnabled

        if group.TypeESPEnabled then
            TypeESP.Text = "ESP"
            TypeESP.BackgroundColor3 = Colors.Success
        else
            TypeESP.Text = "OFF"
            TypeESP.BackgroundColor3 = Colors.Danger
        end

        for model in pairs(group.Eggs) do
            local esp = ESPs[model]
            if esp then
                local enabled = GlobalESPEnabled and group.TypeESPEnabled
                esp.Billboard.Enabled = enabled
                if esp.Highlight then
                    esp.Highlight.Enabled = enabled
                end
            end
        end
    end)

    return group
end

local function updateGroupLayoutOrder(group)
    local eggCount = 0
    for _ in pairs(group.Eggs) do
        eggCount += 1
    end
    group.GroupFrame.LayoutOrder = eggCount
end


--==============================================================
-- CREATE EGG ENTRY
--==============================================================

local function createEggEntry(model)
    if EggEntries[model] then return end
    if not model or not model:IsA("Model") or not model.Parent then return end

    local group = createEggGroup(model.Name)
    group.Eggs[model] = true
    updateGroupLayoutOrder(group)

    local Row = Instance.new("Frame")
    Row.Name = "Egg"
    Row.Size = UDim2.new(1, -4, 0, 28)
    Row.BackgroundColor3 = Color3.fromRGB(12, 24, 48)
    Row.BorderSizePixel = 0
    Row.Parent = group.Container

    local RowCorner = Instance.new("UICorner")
    RowCorner.CornerRadius = UDim.new(0, 6)
    RowCorner.Parent = Row

    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(1, -64, 1, 0)
    NameLabel.Position = UDim2.new(0, 8, 0, 0)
    NameLabel.BackgroundTransparency = 1
    NameLabel.Text = model.Name
    NameLabel.TextColor3 = Colors.Text
    NameLabel.TextXAlignment = Enum.TextXAlignment.Left
    NameLabel.Font = Enum.Font.Gotham
    NameLabel.TextSize = 11
    NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    NameLabel.Parent = Row

    local TP = Instance.new("TextButton")
    TP.Size = UDim2.new(0, 50, 0, 22)
    TP.Position = UDim2.new(1, -56, 0, 3)
    TP.BackgroundColor3 = Colors.Info
    TP.Text = "TP"
    TP.TextColor3 = Color3.new(1, 1, 1)
    TP.Font = Enum.Font.GothamBold
    TP.TextSize = 10
    TP.AutoButtonColor = false
    TP.Parent = Row

    local TPCorner = Instance.new("UICorner")
    TPCorner.CornerRadius = UDim.new(0, 6)
    TPCorner.Parent = TP

    local entry = {
        Model = model,
        Frame = Row,
        Label = NameLabel,
        TP = TP
    }
    EggEntries[model] = entry

    TP.MouseButton1Click:Connect(function()
        if not Running then return end
        if not model or not model.Parent then
            showStatus("Egg no longer exists")
            return
        end

        getCharacter()
        if not Character or not RootPart then
            showStatus("Character not found")
            return
        end

        local target = getEggTopCFrame(model)
        if not target then
            showStatus("Egg is not ready")
            return
        end

        local success, reason = safeTeleport(Character, RootPart, target)
        if success then
            showStatus("Teleported to " .. model.Name)
        else
            showStatus("Teleport failed: " .. tostring(reason))
        end
    end)
end


--==============================================================
-- REGISTER / SCAN
--==============================================================

local function registerModel(model)
    if not Running then return end
    if not model or not model:IsA("Model") or not model.Parent then return end
    if not model:IsDescendantOf(RenderedEggs) then return end

    if not EggEntries[model] then
        createEggEntry(model)
    end
    if not ESPs[model] then
        createESP(model)
    end
    if updateSearch then
        updateSearch()
    end
end

local function tryRegisterEgg(object)
    if not Running then return end
    if not object or not object:IsA("Model") then return end
    if not object:IsDescendantOf(RenderedEggs) then return end

    task.defer(function()
        if not Running or not object.Parent or not object:IsDescendantOf(RenderedEggs) then
            return
        end

        local deadline = os.clock() + 2
        repeat
            if not Running or not object.Parent or not object:IsDescendantOf(RenderedEggs) then
                return
            end
            if getRootPart(object) then break end
            task.wait(0.05)
        until os.clock() >= deadline

        if not Running or not object.Parent or not object:IsDescendantOf(RenderedEggs) then
            return
        end
        registerModel(object)
    end)
end

for _, object in ipairs(RenderedEggs:GetDescendants()) do
    if object:IsA("Model") then
        registerModel(object)
    end
end

Connections.DescendantAdded = RenderedEggs.DescendantAdded:Connect(tryRegisterEgg)


--==============================================================
-- TELEPORT HELPERS
--==============================================================

getEggTopCFrame = function(egg)
    if not egg or not egg:IsA("Model") or not egg.Parent then return nil end
    local cf, size = egg:GetBoundingBox()
    if not isValidPosition(cf.Position) then return nil end
    if not isFiniteNumber(size.Y) or size.Y <= 0 then return nil end

    local targetPosition = Vector3.new(
        cf.Position.X,
        cf.Position.Y + (size.Y * 0.5) + HEIGHT_OFFSET,
        cf.Position.Z
    )
    if not isValidPosition(targetPosition) then return nil end
    return CFrame.new(targetPosition)
end

safeTeleport = function(character, root, targetCFrame)
    if not character or not character.Parent then
        return false, "Character is invalid"
    end
    if not root or not root.Parent then
        return false, "RootPart is invalid"
    end
    if not targetCFrame then
        return false, "Target is invalid"
    end

    local targetPosition = targetCFrame.Position
    if not isValidPosition(targetPosition) then
        return false, "Target position is invalid"
    end

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    character:PivotTo(targetCFrame)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end


--==============================================================
-- PLOT HELPERS
--==============================================================

local function scanMyPlot()
    if not Plots then return nil end
    if PlotScanCount >= MAX_PLOT_SCANS then
        return CachedMyPlot
    end

    PlotScanCount += 1
    CachedMyPlot = nil
    CachedBaseplate = nil

    for _, plot in ipairs(Plots:GetChildren()) do
        local data = plot:FindFirstChild("Data")
        if data then
            local owner = data:FindFirstChild("Owner")
            if owner and owner:IsA("ObjectValue") and owner.Value == LocalPlayer then
                CachedMyPlot = plot
                local baseplate = plot:FindFirstChild("Baseplate")
                    or plot:FindFirstChild("Baseplate", true)
                if baseplate and baseplate:IsA("BasePart") then
                    CachedBaseplate = baseplate
                end
                break
            end
        end
    end
    return CachedMyPlot
end

local function getMyPlot()
    if CachedMyPlot and CachedMyPlot.Parent then
        local data = CachedMyPlot:FindFirstChild("Data")
        local owner = data and data:FindFirstChild("Owner")
        if owner and owner:IsA("ObjectValue") and owner.Value == LocalPlayer then
            return CachedMyPlot
        end
    end
    return scanMyPlot()
end

local function getMyPlotBaseplate()
    local plot = getMyPlot()
    if not plot then return nil end

    if CachedBaseplate and CachedBaseplate.Parent and CachedBaseplate:IsDescendantOf(plot) then
        return CachedBaseplate
    end

    local baseplate = plot:FindFirstChild("Baseplate")
        or plot:FindFirstChild("Baseplate", true)
    if baseplate and baseplate:IsA("BasePart") then
        CachedBaseplate = baseplate
        return baseplate
    end
    return nil
end

local function getBaseplateTopCFrame(baseplate)
    if not baseplate or not baseplate:IsA("BasePart") or not baseplate.Parent then
        return nil
    end

    local size = baseplate.Size
    local cf = baseplate.CFrame
    if not isFiniteNumber(size.Y) or size.Y <= 0 then return nil end
    if not isValidPosition(cf.Position) then return nil end

    local verticalOffset = (size.Y * 0.5) + HEIGHT_OFFSET
    local target = cf * CFrame.new(0, verticalOffset, 0)
    if not isValidPosition(target.Position) then return nil end
    return target
end


--==============================================================
-- BUTTONS
--==============================================================

GlobalToggle.MouseButton1Click:Connect(function()
    GlobalESPEnabled = not GlobalESPEnabled

    if GlobalESPEnabled then
        GlobalToggle.Text = "ESP  •  ON"
        GlobalToggle.BackgroundColor3 = Colors.Success
    else
        GlobalToggle.Text = "ESP  •  OFF"
        GlobalToggle.BackgroundColor3 = Colors.Danger
    end

    for model, esp in pairs(ESPs) do
        if esp then
            local group = EggGroups[model.Name]
            local enabled = GlobalESPEnabled and (not group or group.TypeESPEnabled)
            esp.Billboard.Enabled = enabled
            if esp.Highlight then
                esp.Highlight.Enabled = enabled
            end
        end
    end
end)

PlotTP.MouseButton1Click:Connect(function()
    if not Running then return end
    getCharacter()
    if not Character or not RootPart then
        showStatus("Character not found")
        return
    end

    local baseplate = getMyPlotBaseplate()
    if not baseplate then
        showStatus("Your Plot was not found")
        return
    end

    local target = getBaseplateTopCFrame(baseplate)
    if not target then
        showStatus("Invalid Baseplate")
        return
    end

    local success, reason = safeTeleport(Character, RootPart, target)
    if success then
        showStatus("Teleported to My Plot")
    else
        showStatus("Teleport failed: " .. tostring(reason))
    end
end)


--==============================================================
-- SEARCH
--==============================================================

updateSearch = function()
    local query = string.lower(Search.Text or "")
    local groupHasMatch = {}

    for model, entry in pairs(EggEntries) do
        if entry and entry.Model and entry.Frame and entry.Model.Parent then
            local name = string.lower(entry.Model.Name)
            local matches = query == "" or string.find(name, query, 1, true) ~= nil
            entry.Frame.Visible = matches
            local group = EggGroups[entry.Model.Name]
            if group and matches then
                groupHasMatch[group] = true
            end
        elseif entry and entry.Frame then
            entry.Frame.Visible = false
        end
    end

    for _, group in pairs(EggGroups) do
        if query == "" then
            group.GroupFrame.Visible = true
        else
            group.GroupFrame.Visible = groupHasMatch[group] == true
        end
    end
end

Search:GetPropertyChangedSignal("Text"):Connect(updateSearch)


--==============================================================
-- UPDATE LOOP
--==============================================================

task.spawn(function()
    while Running do
        getCharacter()
        local root = RootPart
        local totalEggs = 0

        for model, esp in pairs(ESPs) do
            if not model or not model.Parent or not model:IsDescendantOf(RenderedEggs) then
                destroyESP(model)

                local entry = EggEntries[model]
                if entry then
                    if entry.Frame then entry.Frame:Destroy() end
                    EggEntries[model] = nil
                end

                local group = EggGroups[model.Name]
                if group then
                    group.Eggs[model] = nil
                    if next(group.Eggs) then
                        updateGroupLayoutOrder(group)
                    else
                        group.GroupFrame:Destroy()
                        EggGroups[model.Name] = nil
                    end
                end
            else
                totalEggs += 1
                local eggRoot = getRootPart(model)
                if eggRoot then
                    local distance = 0
                    if root then
                        distance = (root.Position - eggRoot.Position).Magnitude
                    end

                    local group = EggGroups[model.Name]
                    local groupEnabled = not group or group.TypeESPEnabled
                    local enabled = GlobalESPEnabled and groupEnabled

                    esp.Billboard.Enabled = enabled
                    if esp.Highlight then
                        esp.Highlight.Enabled = enabled
                    end

                    if root then
                        esp.Label.Text = model.Name .. "\n[" .. math.floor(distance) .. " studs]"
                    else
                        esp.Label.Text = model.Name
                    end

                    local entry = EggEntries[model]
                    if entry then
                        if root then
                            entry.Label.Text = model.Name .. "  [" .. math.floor(distance) .. " studs]"
                        else
                            entry.Label.Text = model.Name
                        end
                    end
                end
            end
        end

        CountLabel.Text = "Egg: " .. totalEggs

        if os.clock() >= StatusExpiresAt then
            Status.Text = "Online  •  Plot scan " .. PlotScanCount .. "/" .. MAX_PLOT_SCANS
        end

        task.wait(UPDATE_RATE)
    end
end)


--==============================================================
-- SHUTDOWN
--==============================================================

local function shutdown()
    if not Running then return end
    Running = false

    for model in pairs(ESPs) do
        destroyESP(model)
    end

    for _, connection in pairs(Connections) do
        if connection then
            pcall(function() connection:Disconnect() end)
        end
    end

    if ScreenGui then
        ScreenGui:Destroy()
    end
end

Close.MouseButton1Click:Connect(shutdown)


--==============================================================
-- START
--==============================================================

showStatus("Online  •  Watching for new Eggs", 2)
print("[JHAYDEE] ESP + Teleport loaded")
