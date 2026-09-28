--[[
╔══════════════════════════════════════════════════════════════════╗
║                         JHAYDEE                                  ║
║         Rendered Eggs ESP + Teleport + Auto Farm                 ║
║                                                                  ║
║  UI restyled to match Chilli Hub (dark red theme)                ║
║  Improved Twin function (smooth plot return + real interactions) ║
║                                                                  ║
║ • ESP all Models inside workspace.RenderedEggs                   ║
║ • Show name + distance at any range                              ║
║ • Group Eggs by name / collapse / search                         ║
║ • Global + per-type ESP ON/OFF                                   ║
║ • Direct TP to egg / My Plot                                     ║
║ • AUTO FARM: multi-select egg types                              ║
║ • Auto TP → Grab → Return to My Plot (TP or Twin)                ║
║ • Detects newly spawned eggs automatically                       ║
║ • Twin mode: smooth tween to plot + fire real Twin/Merge/Claim   ║
╚══════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")

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

local FARM_COOLDOWN = 0.25
local GRAB_WAIT = 0.08
local PLOT_WAIT = 0.12
local GRAB_HEIGHT = 2
local GRAB_SPAM = 12
local TWIN_SETTLE = 0.30
local TWIN_RETURN_TIME = 0.50
local TWIN_INTERACT_TIME = 1.40
local GRAB_CONFIRM_TIMEOUT = 1.75
local GRAB_RETRIES = 3

--==============================================================
-- STATE
--==============================================================

local Running = true
local GlobalESPEnabled = true
local PanelVisible = true
local CurrentTab = "Farm"

local AutoFarmEnabled = false
local SelectedFarmEggs = {}
local FarmBusy = false
local LastFarmAt = 0
local FarmStatusText = "Idle"
local ReturnMode = "TP" -- "TP" | "Twin"

local ESPs = {}
local EggEntries = {}
local EggGroups = {}
local FarmRows = {}
local ImportantEggs = {
    ["Galaxy Egg"] = true,
    ["Blackhole Egg"] = true,
    ["Solaris Egg"] = true,
    ["Cherub Egg"] = true,
    ["Vulcanic Egg"] = true,
}
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
local refreshFarmList = nil
local setTab = nil
local setFarmStatus = nil

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
-- COLORS (Chilli Hub style - dark red)
--==============================================================

local Colors = {
    Background   = Color3.fromRGB(25, 12, 12),
    Surface      = Color3.fromRGB(35, 18, 18),
    SurfaceAlt   = Color3.fromRGB(45, 22, 22),
    Border       = Color3.fromRGB(180, 40, 40),
    Accent       = Color3.fromRGB(220, 50, 50),
    AccentSoft   = Color3.fromRGB(180, 40, 40),
    Text         = Color3.fromRGB(240, 240, 240),
    TextDim      = Color3.fromRGB(180, 160, 160),
    Success      = Color3.fromRGB(50, 200, 80),
    Danger       = Color3.fromRGB(220, 50, 50),
    Info         = Color3.fromRGB(60, 140, 220),
    Warning      = Color3.fromRGB(255, 180, 50),
    Sidebar      = Color3.fromRGB(30, 14, 14),
    Header       = Color3.fromRGB(180, 35, 35),
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

-- Floating toggle button
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
ToggleCorner.CornerRadius = UDim.new(0, 12)
ToggleCorner.Parent = ToggleBtn

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(255, 80, 80)
ToggleStroke.Thickness = 2
ToggleStroke.Transparency = 0.3
ToggleStroke.Parent = ToggleBtn

-- Main panel
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 520, 0, 420)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3 = Colors.Background
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Visible = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Colors.Border
MainStroke.Thickness = 1.5
MainStroke.Transparency = 0.2
MainStroke.Parent = Main

-- Top header bar (Chilli Hub style)
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 38)
TopBar.BackgroundColor3 = Colors.Header
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 10)
TopCorner.Parent = TopBar

local TopFix = Instance.new("Frame")
TopFix.Size = UDim2.new(1, 0, 0, 12)
TopFix.Position = UDim2.new(0, 0, 1, -12)
TopFix.BackgroundColor3 = Colors.Header
TopFix.BorderSizePixel = 0
TopFix.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 14, 0, 0)
Title.Size = UDim2.new(1, -60, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextColor3 = Color3.new(1, 1, 1)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "Chilli Hub"
Title.Parent = TopBar

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 28, 0, 28)
Close.Position = UDim2.new(1, -34, 0.5, -14)
Close.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
Close.Text = "×"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 18
Close.AutoButtonColor = false
Close.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = Close

-- Left Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 110, 1, -38)
Sidebar.Position = UDim2.new(0, 0, 0, 38)
Sidebar.BackgroundColor3 = Colors.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Main

local function createSidebarBtn(text, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -12, 0, 36)
    btn.Position = UDim2.new(0, 6, 0, 10 + (order - 1) * 42)
    btn.BackgroundColor3 = Colors.SurfaceAlt
    btn.Text = text
    btn.TextColor3 = Colors.Text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.AutoButtonColor = false
    btn.Parent = Sidebar

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    return btn
end

local TabFarm = createSidebarBtn("Farm", 1)
local TabESP = createSidebarBtn("ESP", 2)
local TabPlayer = createSidebarBtn("Player", 3)
local TabServer = createSidebarBtn("Server", 4)

-- Right content area
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -110, 1, -38)
Content.Position = UDim2.new(0, 110, 0, 38)
Content.BackgroundColor3 = Colors.Background
Content.BorderSizePixel = 0
Content.ClipsDescendants = true
Content.Parent = Main

--==============================================================
-- FARM PAGE
--==============================================================

local FarmPage = Instance.new("ScrollingFrame")
FarmPage.Name = "FarmPage"
FarmPage.Size = UDim2.new(1, 0, 1, 0)
FarmPage.BackgroundTransparency = 1
FarmPage.BorderSizePixel = 0
FarmPage.ScrollBarThickness = 4
FarmPage.ScrollBarImageColor3 = Colors.Accent
FarmPage.CanvasSize = UDim2.new(0, 0, 0, 520)
FarmPage.Visible = true
FarmPage.Parent = Content

local function createSection(parent, title, yPos, height)
    local section = Instance.new("Frame")
    section.Size = UDim2.new(1, -20, 0, height)
    section.Position = UDim2.new(0, 10, 0, yPos)
    section.BackgroundColor3 = Colors.Surface
    section.BorderSizePixel = 0
    section.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = section

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -16, 0, 28)
    header.Position = UDim2.new(0, 10, 0, 4)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.TextSize = 13
    header.TextColor3 = Colors.Text
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = "▼  " .. title
    header.Parent = section

    return section, header
end

-- Farm Status section
local FarmStatusSection = createSection(FarmPage, "Farm Status", 10, 70)

local FarmStatusLabel = Instance.new("TextLabel")
FarmStatusLabel.Size = UDim2.new(1, -20, 0, 28)
FarmStatusLabel.Position = UDim2.new(0, 10, 0, 34)
FarmStatusLabel.BackgroundColor3 = Colors.SurfaceAlt
FarmStatusLabel.Font = Enum.Font.Gotham
FarmStatusLabel.TextSize = 12
FarmStatusLabel.TextColor3 = Colors.TextDim
FarmStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
FarmStatusLabel.Text = "  Idle"
FarmStatusLabel.Parent = FarmStatusSection

local FarmStatusCorner = Instance.new("UICorner")
FarmStatusCorner.CornerRadius = UDim.new(0, 6)
FarmStatusCorner.Parent = FarmStatusLabel

setFarmStatus = function(text)
    FarmStatusText = text
    FarmStatusLabel.Text = "  " .. text
end

-- Auto Farm toggle section
local AutoFarmSection = createSection(FarmPage, "Auto Collect Eggs", 90, 160)

local function createToggleRow(parent, text, y, defaultOn)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 28)
    row.Position = UDim2.new(0, 10, 0, y)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = Colors.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = row

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 44, 0, 22)
    toggle.Position = UDim2.new(1, -48, 0.5, -11)
    toggle.BackgroundColor3 = defaultOn and Colors.Success or Color3.fromRGB(60, 60, 60)
    toggle.Text = ""
    toggle.AutoButtonColor = false
    toggle.Parent = row

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(1, 0)
    toggleCorner.Parent = toggle

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = defaultOn and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = toggle

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    return toggle, knob
end

local FarmToggle, FarmKnob = createToggleRow(AutoFarmSection, "Auto Collect Eggs", 34, false)
local GlobalESPToggle, GlobalESPKnob = createToggleRow(AutoFarmSection, "Global ESP", 68, true)

-- Mode buttons
local ModeLabel = Instance.new("TextLabel")
ModeLabel.Size = UDim2.new(0, 80, 0, 24)
ModeLabel.Position = UDim2.new(0, 10, 0, 108)
ModeLabel.BackgroundTransparency = 1
ModeLabel.Font = Enum.Font.Gotham
ModeLabel.TextSize = 12
ModeLabel.TextColor3 = Colors.TextDim
ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
ModeLabel.Text = "After grab:"
ModeLabel.Parent = AutoFarmSection

local ModeTP = Instance.new("TextButton")
ModeTP.Size = UDim2.new(0, 90, 0, 24)
ModeTP.Position = UDim2.new(0, 90, 0, 108)
ModeTP.BackgroundColor3 = Colors.Accent
ModeTP.Text = "TP Home"
ModeTP.TextColor3 = Color3.new(1, 1, 1)
ModeTP.Font = Enum.Font.GothamBold
ModeTP.TextSize = 11
ModeTP.AutoButtonColor = false
ModeTP.Parent = AutoFarmSection

local ModeTPCorner = Instance.new("UICorner")
ModeTPCorner.CornerRadius = UDim.new(0, 5)
ModeTPCorner.Parent = ModeTP

local ModeTwin = Instance.new("TextButton")
ModeTwin.Size = UDim2.new(0, 90, 0, 24)
ModeTwin.Position = UDim2.new(0, 190, 0, 108)
ModeTwin.BackgroundColor3 = Colors.SurfaceAlt
ModeTwin.Text = "Twin (no TP)"
ModeTwin.TextColor3 = Colors.Text
ModeTwin.Font = Enum.Font.GothamBold
ModeTwin.TextSize = 11
ModeTwin.AutoButtonColor = false
ModeTwin.Parent = AutoFarmSection

local ModeTwinCorner = Instance.new("UICorner")
ModeTwinCorner.CornerRadius = UDim.new(0, 5)
ModeTwinCorner.Parent = ModeTwin

local function updateModeButtons()
    if ReturnMode == "TP" then
        ModeTP.BackgroundColor3 = Colors.Accent
        ModeTP.TextColor3 = Color3.new(1, 1, 1)
        ModeTwin.BackgroundColor3 = Colors.SurfaceAlt
        ModeTwin.TextColor3 = Colors.Text
    else
        ModeTwin.BackgroundColor3 = Colors.Warning
        ModeTwin.TextColor3 = Color3.fromRGB(20, 20, 30)
        ModeTP.BackgroundColor3 = Colors.SurfaceAlt
        ModeTP.TextColor3 = Colors.Text
    end
end

-- Target Eggs section
local TargetSection = createSection(FarmPage, "Target Eggs", 260, 240)

local SelectAllBtn = Instance.new("TextButton")
SelectAllBtn.Size = UDim2.new(0, 70, 0, 24)
SelectAllBtn.Position = UDim2.new(1, -160, 0, 6)
SelectAllBtn.BackgroundColor3 = Colors.Info
SelectAllBtn.Text = "All"
SelectAllBtn.TextColor3 = Color3.new(1, 1, 1)
SelectAllBtn.Font = Enum.Font.GothamBold
SelectAllBtn.TextSize = 11
SelectAllBtn.AutoButtonColor = false
SelectAllBtn.Parent = TargetSection

local SelectAllCorner = Instance.new("UICorner")
SelectAllCorner.CornerRadius = UDim.new(0, 5)
SelectAllCorner.Parent = SelectAllBtn

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0, 70, 0, 24)
ClearBtn.Position = UDim2.new(1, -80, 0, 6)
ClearBtn.BackgroundColor3 = Colors.SurfaceAlt
ClearBtn.Text = "Clear"
ClearBtn.TextColor3 = Colors.Text
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.TextSize = 11
ClearBtn.AutoButtonColor = false
ClearBtn.Parent = TargetSection

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 5)
ClearCorner.Parent = ClearBtn

local FarmList = Instance.new("ScrollingFrame")
FarmList.Size = UDim2.new(1, -16, 0, 190)
FarmList.Position = UDim2.new(0, 8, 0, 36)
FarmList.BackgroundColor3 = Colors.SurfaceAlt
FarmList.BorderSizePixel = 0
FarmList.ScrollBarThickness = 3
FarmList.ScrollBarImageColor3 = Colors.Accent
FarmList.CanvasSize = UDim2.new(0, 0, 0, 0)
FarmList.Parent = TargetSection

local FarmListCorner = Instance.new("UICorner")
FarmListCorner.CornerRadius = UDim.new(0, 6)
FarmListCorner.Parent = FarmList

local FarmListLayout = Instance.new("UIListLayout")
FarmListLayout.Padding = UDim.new(0, 3)
FarmListLayout.SortOrder = Enum.SortOrder.Name
FarmListLayout.Parent = FarmList

local FarmListPadding = Instance.new("UIPadding")
FarmListPadding.PaddingTop = UDim.new(0, 4)
FarmListPadding.PaddingBottom = UDim.new(0, 4)
FarmListPadding.PaddingLeft = UDim.new(0, 4)
FarmListPadding.PaddingRight = UDim.new(0, 4)
FarmListPadding.Parent = FarmList

FarmListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    FarmList.CanvasSize = UDim2.new(0, 0, 0, FarmListLayout.AbsoluteContentSize.Y + 10)
end)

--==============================================================
-- ESP PAGE
--==============================================================

local ESPPage = Instance.new("ScrollingFrame")
ESPPage.Name = "ESPPage"
ESPPage.Size = UDim2.new(1, 0, 1, 0)
ESPPage.BackgroundTransparency = 1
ESPPage.BorderSizePixel = 0
ESPPage.ScrollBarThickness = 4
ESPPage.ScrollBarImageColor3 = Colors.Accent
ESPPage.CanvasSize = UDim2.new(0, 0, 0, 480)
ESPPage.Visible = false
ESPPage.Parent = Content

local ESPControlSection = createSection(ESPPage, "ESP Controls", 10, 90)

local PlotTP = Instance.new("TextButton")
PlotTP.Size = UDim2.new(0, 110, 0, 28)
PlotTP.Position = UDim2.new(0, 10, 0, 40)
PlotTP.BackgroundColor3 = Colors.Info
PlotTP.Text = "My Plot"
PlotTP.TextColor3 = Color3.new(1, 1, 1)
PlotTP.Font = Enum.Font.GothamBold
PlotTP.TextSize = 12
PlotTP.AutoButtonColor = false
PlotTP.Parent = ESPControlSection

local PlotTPCorner = Instance.new("UICorner")
PlotTPCorner.CornerRadius = UDim.new(0, 6)
PlotTPCorner.Parent = PlotTP

local CountLabel = Instance.new("TextLabel")
CountLabel.Size = UDim2.new(0, 100, 0, 28)
CountLabel.Position = UDim2.new(0, 130, 0, 40)
CountLabel.BackgroundColor3 = Colors.SurfaceAlt
CountLabel.Text = "Eggs: 0"
CountLabel.TextColor3 = Colors.Text
CountLabel.Font = Enum.Font.GothamBold
CountLabel.TextSize = 12
CountLabel.Parent = ESPControlSection

local CountCorner = Instance.new("UICorner")
CountCorner.CornerRadius = UDim.new(0, 6)
CountCorner.Parent = CountLabel

local SearchSection = createSection(ESPPage, "Search & List", 110, 340)

local SearchBox = Instance.new("Frame")
SearchBox.Size = UDim2.new(1, -20, 0, 30)
SearchBox.Position = UDim2.new(0, 10, 0, 36)
SearchBox.BackgroundColor3 = Colors.SurfaceAlt
SearchBox.BorderSizePixel = 0
SearchBox.Parent = SearchSection

local SearchCorner = Instance.new("UICorner")
SearchCorner.CornerRadius = UDim.new(0, 6)
SearchCorner.Parent = SearchBox

local Search = Instance.new("TextBox")
Search.Position = UDim2.new(0, 10, 0, 0)
Search.Size = UDim2.new(1, -20, 1, 0)
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

local List = Instance.new("ScrollingFrame")
List.Size = UDim2.new(1, -20, 0, 260)
List.Position = UDim2.new(0, 10, 0, 74)
List.BackgroundColor3 = Colors.SurfaceAlt
List.BorderSizePixel = 0
List.ScrollBarThickness = 3
List.ScrollBarImageColor3 = Colors.Accent
List.CanvasSize = UDim2.new(0, 0, 0, 0)
List.Parent = SearchSection

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 6)
ListCorner.Parent = List

local ListPadding = Instance.new("UIPadding")
ListPadding.PaddingTop = UDim.new(0, 4)
ListPadding.PaddingBottom = UDim.new(0, 4)
ListPadding.PaddingLeft = UDim.new(0, 4)
ListPadding.PaddingRight = UDim.new(0, 4)
ListPadding.Parent = List

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 3)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = List

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    List.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
end)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 24)
Status.Position = UDim2.new(0, 10, 1, -30)
Status.BackgroundColor3 = Colors.SurfaceAlt
Status.Font = Enum.Font.Gotham
Status.TextSize = 11
Status.TextColor3 = Colors.TextDim
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "  Online"
Status.Parent = ESPPage

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 5)
StatusCorner.Parent = Status

local StatusExpiresAt = 0
local function showStatus(message, duration)
    Status.Text = "  " .. message
    StatusExpiresAt = os.clock() + (duration or 3)
end

--==============================================================
-- PLAYER / SERVER PAGES
--==============================================================

local PlayerPage = Instance.new("Frame")
PlayerPage.Name = "PlayerPage"
PlayerPage.Size = UDim2.new(1, 0, 1, 0)
PlayerPage.BackgroundTransparency = 1
PlayerPage.Visible = false
PlayerPage.Parent = Content

local PlayerSection = createSection(PlayerPage, "Movement", 10, 160)

local SpeedToggle, SpeedKnob = createToggleRow(PlayerSection, "Speed Boost", 36, false)
local JumpToggle, JumpKnob = createToggleRow(PlayerSection, "Infinite Jump", 70, false)
local NoclipToggle, NoclipKnob = createToggleRow(PlayerSection, "Noclip", 104, false)

local ServerPage = Instance.new("Frame")
ServerPage.Name = "ServerPage"
ServerPage.Size = UDim2.new(1, 0, 1, 0)
ServerPage.BackgroundTransparency = 1
ServerPage.Visible = false
ServerPage.Parent = Content

local ServerSection = createSection(ServerPage, "Server", 10, 180)

local RejoinBtn = Instance.new("TextButton")
RejoinBtn.Size = UDim2.new(1, -20, 0, 32)
RejoinBtn.Position = UDim2.new(0, 10, 0, 40)
RejoinBtn.BackgroundColor3 = Colors.Accent
RejoinBtn.Text = "Rejoin Server"
RejoinBtn.TextColor3 = Color3.new(1, 1, 1)
RejoinBtn.Font = Enum.Font.GothamBold
RejoinBtn.TextSize = 13
RejoinBtn.AutoButtonColor = false
RejoinBtn.Parent = ServerSection

local RejoinCorner = Instance.new("UICorner")
RejoinCorner.CornerRadius = UDim.new(0, 6)
RejoinCorner.Parent = RejoinBtn

local HopBtn = Instance.new("TextButton")
HopBtn.Size = UDim2.new(1, -20, 0, 32)
HopBtn.Position = UDim2.new(0, 10, 0, 80)
HopBtn.BackgroundColor3 = Colors.SurfaceAlt
HopBtn.Text = "Server Hop"
HopBtn.TextColor3 = Colors.Text
HopBtn.Font = Enum.Font.GothamBold
HopBtn.TextSize = 13
HopBtn.AutoButtonColor = false
HopBtn.Parent = ServerSection

local HopCorner = Instance.new("UICorner")
HopCorner.CornerRadius = UDim.new(0, 6)
HopCorner.Parent = HopBtn

--==============================================================
-- TAB SWITCH
--==============================================================

local allPages = {
    Farm = FarmPage,
    ESP = ESPPage,
    Player = PlayerPage,
    Server = ServerPage,
}

local allTabs = {
    Farm = TabFarm,
    ESP = TabESP,
    Player = TabPlayer,
    Server = TabServer,
}

setTab = function(tab)
    CurrentTab = tab
    for name, page in pairs(allPages) do
        page.Visible = (name == tab)
    end
    for name, btn in pairs(allTabs) do
        if name == tab then
            btn.BackgroundColor3 = Colors.Accent
            btn.TextColor3 = Color3.new(1, 1, 1)
        else
            btn.BackgroundColor3 = Colors.SurfaceAlt
            btn.TextColor3 = Colors.Text
        end
    end
    if tab == "Farm" and refreshFarmList then
        refreshFarmList()
    end
end

TabFarm.MouseButton1Click:Connect(function() setTab("Farm") end)
TabESP.MouseButton1Click:Connect(function() setTab("ESP") end)
TabPlayer.MouseButton1Click:Connect(function() setTab("Player") end)
TabServer.MouseButton1Click:Connect(function() setTab("Server") end)

setTab("Farm")

--==============================================================
-- OPEN / CLOSE + DRAG
--==============================================================

local function setPanelVisible(visible)
    PanelVisible = visible
    Main.Visible = visible
    ToggleBtn.BackgroundColor3 = visible and Colors.Accent or Colors.SurfaceAlt
end

ToggleBtn.MouseButton1Click:Connect(function()
    setPanelVisible(not PanelVisible)
end)

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
-- CREATE GROUP + EGG ENTRY
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
    Header.Size = UDim2.new(1, -2, 0, 28)
    Header.BackgroundColor3 = Colors.Surface
    Header.BorderSizePixel = 0
    Header.LayoutOrder = 1
    Header.Parent = GroupFrame

    local HeaderCorner = Instance.new("UICorner")
    HeaderCorner.CornerRadius = UDim.new(0, 5)
    HeaderCorner.Parent = Header

    local Toggle = Instance.new("TextButton")
    Toggle.Size = UDim2.new(1, -60, 1, 0)
    Toggle.BackgroundTransparency = 1
    Toggle.TextXAlignment = Enum.TextXAlignment.Left
    Toggle.Font = Enum.Font.GothamBold
    Toggle.TextSize = 11
    Toggle.TextTruncate = Enum.TextTruncate.AtEnd
    Toggle.TextColor3 = Colors.Text
    Toggle.Text = "▼  " .. groupName
    Toggle.Parent = Header

    local TypeESP = Instance.new("TextButton")
    TypeESP.Size = UDim2.new(0, 48, 0, 20)
    TypeESP.Position = UDim2.new(1, -52, 0, 4)
    TypeESP.BackgroundColor3 = Colors.Success
    TypeESP.Text = "ESP"
    TypeESP.TextColor3 = Color3.new(1, 1, 1)
    TypeESP.Font = Enum.Font.GothamBold
    TypeESP.TextSize = 10
    TypeESP.AutoButtonColor = false
    TypeESP.Parent = Header

    local TypeCorner = Instance.new("UICorner")
    TypeCorner.CornerRadius = UDim.new(0, 4)
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

    if refreshFarmList then
        refreshFarmList()
    end

    return group
end

local function updateGroupLayoutOrder(group)
    local eggCount = 0
    for _ in pairs(group.Eggs) do
        eggCount += 1
    end
    group.GroupFrame.LayoutOrder = eggCount
end

local function createEggEntry(model)
    if EggEntries[model] then return end
    if not model or not model:IsA("Model") or not model.Parent then return end

    local group = createEggGroup(model.Name)
    group.Eggs[model] = true
    updateGroupLayoutOrder(group)

    local Row = Instance.new("Frame")
    Row.Name = "Egg"
    Row.Size = UDim2.new(1, -4, 0, 26)
    Row.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
    Row.BorderSizePixel = 0
    Row.Parent = group.Container

    local RowCorner = Instance.new("UICorner")
    RowCorner.CornerRadius = UDim.new(0, 4)
    RowCorner.Parent = Row

    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(1, -56, 1, 0)
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
    TP.Size = UDim2.new(0, 44, 0, 20)
    TP.Position = UDim2.new(1, -50, 0, 3)
    TP.BackgroundColor3 = Colors.Info
    TP.Text = "TP"
    TP.TextColor3 = Color3.new(1, 1, 1)
    TP.Font = Enum.Font.GothamBold
    TP.TextSize = 10
    TP.AutoButtonColor = false
    TP.Parent = Row

    local TPCorner = Instance.new("UICorner")
    TPCorner.CornerRadius = UDim.new(0, 4)
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
-- FARM LIST
--==============================================================

local function updateFarmRowVisual(name)
    local row = FarmRows[name]
    if not row then return end
    local selected = ImportantEggs[name] or SelectedFarmEggs[name] == true
    row.Check.Text = selected and "✓" or ""
    row.Check.BackgroundColor3 = selected and Colors.Success or Colors.Surface
    row.Frame.BackgroundColor3 = selected and Color3.fromRGB(30, 50, 30) or Color3.fromRGB(40, 20, 20)
end

local function createFarmRow(name)
    if FarmRows[name] then
        updateFarmRowVisual(name)
        return
    end

    local Row = Instance.new("Frame")
    Row.Name = name
    Row.Size = UDim2.new(1, -4, 0, 28)
    Row.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
    Row.BorderSizePixel = 0
    Row.Parent = FarmList

    local RowCorner = Instance.new("UICorner")
    RowCorner.CornerRadius = UDim.new(0, 4)
    RowCorner.Parent = Row

    local Check = Instance.new("TextButton")
    Check.Size = UDim2.new(0, 22, 0, 22)
    Check.Position = UDim2.new(0, 4, 0.5, -11)
    Check.BackgroundColor3 = Colors.Surface
    Check.Text = ""
    Check.TextColor3 = Color3.new(1, 1, 1)
    Check.Font = Enum.Font.GothamBold
    Check.TextSize = 13
    Check.AutoButtonColor = false
    Check.Parent = Row

    local CheckCorner = Instance.new("UICorner")
    CheckCorner.CornerRadius = UDim.new(0, 4)
    CheckCorner.Parent = Check

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -36, 1, 0)
    Label.Position = UDim2.new(0, 32, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = ImportantEggs[name] and ("★ " .. name) or name
    Label.TextColor3 = ImportantEggs[name] and Colors.Warning or Colors.Text
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextTruncate = Enum.TextTruncate.AtEnd
    Label.Parent = Row

    local function toggle()
        if ImportantEggs[name] then
            SelectedFarmEggs[name] = true
        else
            if SelectedFarmEggs[name] then
                SelectedFarmEggs[name] = nil
            else
                SelectedFarmEggs[name] = true
            end
        end
        updateFarmRowVisual(name)
    end

    Check.MouseButton1Click:Connect(toggle)
    Row.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            toggle()
        end
    end)

    FarmRows[name] = { Frame = Row, Check = Check, Label = Label }
    updateFarmRowVisual(name)
end

refreshFarmList = function()
    for name in pairs(EggGroups) do
        createFarmRow(name)
    end
    for name in pairs(ImportantEggs) do
        createFarmRow(name)
        SelectedFarmEggs[name] = true
    end
    for name in pairs(SelectedFarmEggs) do
        createFarmRow(name)
    end
    for name in pairs(FarmRows) do
        updateFarmRowVisual(name)
    end
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
    if refreshFarmList then
        refreshFarmList()
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
-- TELEPORT + PLOT HELPERS
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

local function teleportToMyPlot()
    getCharacter()
    if not Character or not RootPart then
        return false, "Character not found"
    end
    local baseplate = getMyPlotBaseplate()
    if not baseplate then
        return false, "Plot not found"
    end
    local target = getBaseplateTopCFrame(baseplate)
    if not target then
        return false, "Invalid baseplate"
    end
    return safeTeleport(Character, RootPart, target)
end

local function looksLikeTwin(obj)
    local n = string.lower(tostring(obj.Name or ""))
    local action, objText = "", ""
    pcall(function()
        if obj:IsA("ProximityPrompt") then
            action = string.lower(tostring(obj.ActionText or ""))
            objText = string.lower(tostring(obj.ObjectText or ""))
        end
    end)
    return string.find(n, "twin", 1, true)
        or string.find(action, "twin", 1, true)
        or string.find(objText, "twin", 1, true)
        or string.find(n, "merge", 1, true)
        or string.find(action, "merge", 1, true)
        or string.find(n, "claim", 1, true)
        or string.find(action, "claim", 1, true)
        or string.find(n, "collect", 1, true)
        or string.find(action, "collect", 1, true)
        or string.find(n, "hatch", 1, true)
        or string.find(action, "hatch", 1, true)
end

local tryTwinOnEgg
local afterGrabReturn

--==============================================================
-- GRAB EGG
--==============================================================

local function tryFireProximityPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return false
    end
    local ok = pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt, 0)
            fireproximityprompt(prompt)
        else
            prompt:InputHoldBegin()
            task.wait(0.02)
            prompt:InputHoldEnd()
        end
    end)
    return ok
end

local function tryFireClickDetector(detector)
    if not detector or not detector:IsA("ClickDetector") then
        return false
    end
    local ok = pcall(function()
        if fireclickdetector then
            fireclickdetector(detector)
            fireclickdetector(detector, 1)
        end
    end)
    return ok
end

local function pressKeyE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

local function collectPrompts(model)
    local prompts = {}
    local clicks = {}

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            table.insert(prompts, desc)
        elseif desc:IsA("ClickDetector") then
            table.insert(clicks, desc)
        end
    end

    local parent = model.Parent
    if parent then
        for _, desc in ipairs(parent:GetChildren()) do
            if desc:IsA("ProximityPrompt") then
                table.insert(prompts, desc)
            elseif desc:IsA("ClickDetector") then
                table.insert(clicks, desc)
            end
        end
    end

    return prompts, clicks
end

local function tryGrabEgg(model)
    if not model or not model.Parent then
        return false
    end

    local prompts, clicks = collectPrompts(model)
    local grabbed = false

    for _ = 1, GRAB_SPAM do
        if not model.Parent then
            return true
        end

        for _, prompt in ipairs(prompts) do
            if prompt and prompt.Parent then
                if tryFireProximityPrompt(prompt) then
                    grabbed = true
                end
            end
        end

        for _, detector in ipairs(clicks) do
            if detector and detector.Parent then
                if tryFireClickDetector(detector) then
                    grabbed = true
                end
            end
        end

        if #prompts == 0 and #clicks == 0 then
            pressKeyE()
        end
        task.wait(0.025)
    end

    return grabbed
end

local function waitForEggGrabConfirmed(egg, timeout)
    local deadline = os.clock() + (timeout or GRAB_CONFIRM_TIMEOUT)

    while os.clock() < deadline do
        if not egg or not egg.Parent then
            return true
        end

        if not RenderedEggs or not egg:IsDescendantOf(RenderedEggs) then
            return true
        end

        task.wait(0.05)
    end

    return false
end

local function grabEggUntilConfirmed(egg)
    if not egg or not egg.Parent then
        return true
    end

    for attempt = 1, GRAB_RETRIES do
        if not egg.Parent or not egg:IsDescendantOf(RenderedEggs) then
            return true
        end

        setFarmStatus("GRAB " .. tostring(egg.Name) .. " (" .. attempt .. "/" .. GRAB_RETRIES .. ")")
        tryGrabEgg(egg)

        if waitForEggGrabConfirmed(egg, GRAB_CONFIRM_TIMEOUT) then
            return true
        end

        if attempt < GRAB_RETRIES then
            task.wait(0.12)
        end
    end

    return false
end

local function getEggGrabCFrame(egg)
    if not egg or not egg:IsA("Model") or not egg.Parent then
        return nil
    end
    local cf, size = egg:GetBoundingBox()
    if not isValidPosition(cf.Position) then
        return nil
    end
    local y = cf.Position.Y + (isFiniteNumber(size.Y) and (size.Y * 0.5) or 0) + GRAB_HEIGHT
    local pos = Vector3.new(cf.Position.X, y, cf.Position.Z)
    if not isValidPosition(pos) then
        return nil
    end
    return CFrame.new(pos)
end

--==============================================================
-- IMPROVED TWIN FUNCTION (matches video-style behavior)
-- Smooth return to plot + real Twin / Merge / Claim / Hatch
-- interactions found on the player's own plot.
--==============================================================

tryTwinOnEgg = function(eggModel)
    if not eggModel then
        return false, "Egg gone"
    end

    local plot = getMyPlot()
    if not plot then
        return false, "Plot not found"
    end

    getCharacter()
    if not Character or not RootPart then
        return false, "Character not found"
    end

    local baseplate = getMyPlotBaseplate()
    local target = baseplate and getBaseplateTopCFrame(baseplate)
    if not target then
        return false, "Plot position not found"
    end

    setFarmStatus("Smooth Twin → Plot")

    -- Smooth tween back to plot (no hard teleport snap)
    local ok = pcall(function()
        local distance = (RootPart.Position - target.Position).Magnitude
        local duration = math.clamp(distance / 110, 0.20, TWIN_RETURN_TIME)
        local tween = TweenService:Create(
            RootPart,
            TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {CFrame = target}
        )
        tween:Play()
        tween.Completed:Wait()
    end)

    if not ok or not RootPart.Parent then
        -- Fallback only if tween failed
        local tpOK = safeTeleport(Character, RootPart, target)
        if not tpOK then
            return false, "Plot return failed"
        end
    end

    task.wait(TWIN_SETTLE)

    -- Collect real Twin / Merge / Claim / Hatch interactions on the plot
    local prompts, clicks = {}, {}
    for _, desc in ipairs(plot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and looksLikeTwin(desc) then
            table.insert(prompts, desc)
        elseif desc:IsA("ClickDetector") and looksLikeTwin(desc) then
            table.insert(clicks, desc)
        end
    end

    if #prompts == 0 and #clicks == 0 then
        -- Also try any enabled prompt on the plot as last resort
        for _, desc in ipairs(plot:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled ~= false then
                table.insert(prompts, desc)
            end
        end
    end

    if #prompts == 0 and #clicks == 0 then
        return false, "No Twin interaction found on plot"
    end

    setFarmStatus("Firing Twin interactions...")

    -- Real interaction burst (same style as video auto-collect)
    local finishAt = os.clock() + TWIN_INTERACT_TIME
    while os.clock() < finishAt do
        for _, prompt in ipairs(prompts) do
            if prompt and prompt.Parent and prompt.Enabled ~= false then
                tryFireProximityPrompt(prompt)
            end
        end
        for _, detector in ipairs(clicks) do
            if detector and detector.Parent then
                tryFireClickDetector(detector)
            end
        end
        pressKeyE() -- extra safety for any E-key prompts
        task.wait(0.05)
    end

    return true, "Twin Plot complete"
end

afterGrabReturn = function(eggModel)
    if ReturnMode == "Twin" then
        local confirmed = waitForEggGrabConfirmed(eggModel, GRAB_CONFIRM_TIMEOUT)
        if not confirmed then
            setFarmStatus("Waiting for egg confirmation...")
            return false
        end

        local ok, msg = tryTwinOnEgg(eggModel)
        if ok then
            setFarmStatus("Twin done")
        else
            setFarmStatus("Twin fail: " .. tostring(msg))
        end
        return ok
    else
        setFarmStatus("TP → Plot")
        local ok = teleportToMyPlot()
        if ok then
            setFarmStatus("Ready")
        else
            setFarmStatus("Plot TP failed")
        end
        task.wait(PLOT_WAIT)
        return ok
    end
end

--==============================================================
-- FIND FARM TARGET + AUTO FARM LOOP
--==============================================================

local function findFarmTarget()
    if not next(SelectedFarmEggs) then
        return nil
    end

    getCharacter()
    local best = nil
    local bestDist = math.huge

    for model in pairs(EggEntries) do
        if model and model.Parent and model:IsDescendantOf(RenderedEggs) then
            if SelectedFarmEggs[model.Name] or ImportantEggs[model.Name] then
                local root = getRootPart(model)
                if root then
                    local dist = RootPart and (RootPart.Position - root.Position).Magnitude or 0
                    local priority = ImportantEggs[model.Name] and 0 or 1
                    local score = priority * 1000000 + dist
                    if score < bestDist then
                        bestDist = score
                        best = model
                    end
                end
            end
        end
    end

    return best
end

task.spawn(function()
    while Running do
        if AutoFarmEnabled and not FarmBusy and next(SelectedFarmEggs) then
            if os.clock() - LastFarmAt >= FARM_COOLDOWN then
                local target = findFarmTarget()
                if target then
                    FarmBusy = true
                    local eggName = target.Name
                    setFarmStatus("SNIPE → " .. eggName)

                    getCharacter()
                    if Character and RootPart then
                        local cf = getEggGrabCFrame(target) or getEggTopCFrame(target)
                        if cf then
                            local ok = safeTeleport(Character, RootPart, cf)
                            if ok then
                                setFarmStatus("GRAB " .. eggName)
                                local confirmed = grabEggUntilConfirmed(target)

                                if confirmed then
                                    task.wait(GRAB_WAIT)
                                    afterGrabReturn(target)
                                else
                                    setFarmStatus("Grab not confirmed: " .. eggName)
                                    task.wait(0.20)
                                end
                            else
                                setFarmStatus("TP failed")
                            end
                        else
                            setFarmStatus("Bad egg pos")
                        end
                    else
                        setFarmStatus("No character")
                    end

                    LastFarmAt = os.clock()
                    FarmBusy = false
                else
                    setFarmStatus("Scanning...")
                end
            end
        elseif AutoFarmEnabled and not next(SelectedFarmEggs) then
            setFarmStatus("Select egg types")
        elseif not AutoFarmEnabled and not FarmBusy then
            if FarmStatusText ~= "Idle" then
                setFarmStatus("Idle")
            end
        end

        task.wait(0.08)
    end
end)

--==============================================================
-- BUTTON CONNECTIONS
--==============================================================

local function setToggleVisual(toggle, knob, state)
    toggle.BackgroundColor3 = state and Colors.Success or Color3.fromRGB(60, 60, 60)
    knob.Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
end

FarmToggle.MouseButton1Click:Connect(function()
    AutoFarmEnabled = not AutoFarmEnabled
    setToggleVisual(FarmToggle, FarmKnob, AutoFarmEnabled)
    if AutoFarmEnabled then
        setFarmStatus("Running...")
        showStatus("Auto Farm enabled")
    else
        setFarmStatus("Idle")
        showStatus("Auto Farm disabled")
    end
end)

GlobalESPToggle.MouseButton1Click:Connect(function()
    GlobalESPEnabled = not GlobalESPEnabled
    setToggleVisual(GlobalESPToggle, GlobalESPKnob, GlobalESPEnabled)
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

ModeTP.MouseButton1Click:Connect(function()
    ReturnMode = "TP"
    updateModeButtons()
    setFarmStatus("Mode: TP Plot")
end)

ModeTwin.MouseButton1Click:Connect(function()
    ReturnMode = "Twin"
    updateModeButtons()
    setFarmStatus("Mode: Twin Plot")
end)

updateModeButtons()

PlotTP.MouseButton1Click:Connect(function()
    if not Running then return end
    local ok, reason = teleportToMyPlot()
    if ok then
        showStatus("Teleported to My Plot")
    else
        showStatus("Teleport failed: " .. tostring(reason))
    end
end)

SelectAllBtn.MouseButton1Click:Connect(function()
    for name in pairs(EggGroups) do
        SelectedFarmEggs[name] = true
        updateFarmRowVisual(name)
    end
    for name in pairs(FarmRows) do
        SelectedFarmEggs[name] = true
        updateFarmRowVisual(name)
    end
    setFarmStatus("All types selected")
end)

ClearBtn.MouseButton1Click:Connect(function()
    table.clear(SelectedFarmEggs)
    for name in pairs(ImportantEggs) do
        SelectedFarmEggs[name] = true
    end
    for name in pairs(FarmRows) do
        updateFarmRowVisual(name)
    end
    setFarmStatus("Normal selection cleared • Important Eggs stay ON")
end)

RejoinBtn.MouseButton1Click:Connect(function()
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
end)

HopBtn.MouseButton1Click:Connect(function()
    showStatus("Server hop not implemented in this build")
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

        CountLabel.Text = "Eggs: " .. totalEggs

        if os.clock() >= StatusExpiresAt then
            Status.Text = "  Online  •  Plot scan " .. PlotScanCount .. "/" .. MAX_PLOT_SCANS
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
    AutoFarmEnabled = false

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
setFarmStatus("Idle")
print("[JHAYDEE] ESP + Teleport + Auto Farm loaded (Chilli Hub style + improved Twin)")
