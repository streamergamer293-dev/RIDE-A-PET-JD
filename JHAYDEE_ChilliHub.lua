--[[
╔══════════════════════════════════════════════════════════════════╗
║                       JHAYDEE HUB                                ║
║         Rendered Eggs ESP + Teleport + Auto Farm                 ║
║                                                                  ║
║  Compact Chilli Hub style panel (~400x340)                       ║
║  Twin steps 1-4 only (side → DROP → re-grab → claim)             ║
║  Map tab: live eggs on map + distance + TP                       ║
╚══════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local RenderedEggs = workspace:FindFirstChild("RenderedEggs")
local Plots = workspace:FindFirstChild("Plots")

if not RenderedEggs then
    warn("[JHAYDEE] workspace.RenderedEggs was not found")
    return
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
local TWIN_SETTLE = 0.35
local TWIN_RETURN_TIME = 0.55
local TWIN_INTERACT_TIME = 1.80
local TWIN_SIDE_EXTRA = 28          -- extra studs past the edge of the plot (clearly outside)
local TWIN_DROP_WAIT = 0.70         -- wait after script presses DROP
local TWIN_REGRAB_WAIT = 0.40       -- wait after re-grab before going onto plot
local GRAB_CONFIRM_TIMEOUT = 1.75
local GRAB_RETRIES = 3

local DEFAULT_WALKSPEED = 16
local BOOST_WALKSPEED = 55

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
local ReturnMode = "TP"

local SpeedBoostEnabled = false
local InfiniteJumpEnabled = false
local NoclipEnabled = false
local InstantPickupEnabled = false

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
local Humanoid = nil

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
    return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isValidPosition(position)
    if typeof(position) ~= "Vector3" then return false end
    return isFiniteNumber(position.X) and isFiniteNumber(position.Y) and isFiniteNumber(position.Z)
end

local function getCharacter()
    Character = LocalPlayer.Character
    if not Character then
        RootPart = nil
        Humanoid = nil
        return nil
    end
    RootPart = Character:FindFirstChild("HumanoidRootPart")
        or Character:FindFirstChild("UpperTorso")
        or Character:FindFirstChild("Torso")
    Humanoid = Character:FindFirstChildOfClass("Humanoid")
    return Character
end

getCharacter()

Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function(character)
    Character = character
    RootPart = character:WaitForChild("HumanoidRootPart", 10)
    Humanoid = character:WaitForChild("Humanoid", 10)
    if SpeedBoostEnabled and Humanoid then
        Humanoid.WalkSpeed = BOOST_WALKSPEED
    end
end)

local function getRootPart(model)
    if not model or not model:IsA("Model") then return nil end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    local root = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("RootPart")
        or model:FindFirstChild("Handle")
    if root and root:IsA("BasePart") then return root end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getEggTypeEnabled(model)
    if not model then return true end
    local group = EggGroups[model.Name]
    return group and group.TypeESPEnabled or true
end

--==============================================================
-- COLORS (Chilli Hub dark red)
--==============================================================

local Colors = {
    Background = Color3.fromRGB(22, 10, 10),
    Surface    = Color3.fromRGB(32, 15, 15),
    SurfaceAlt = Color3.fromRGB(42, 20, 20),
    Border     = Color3.fromRGB(170, 35, 35),
    Accent     = Color3.fromRGB(210, 45, 45),
    Text       = Color3.fromRGB(240, 240, 240),
    TextDim    = Color3.fromRGB(175, 155, 155),
    Success    = Color3.fromRGB(45, 195, 75),
    Danger     = Color3.fromRGB(210, 45, 45),
    Info       = Color3.fromRGB(55, 130, 210),
    Warning    = Color3.fromRGB(255, 175, 45),
    Sidebar    = Color3.fromRGB(28, 12, 12),
    Header     = Color3.fromRGB(170, 32, 32),
}

--==============================================================
-- GUI (compact size matching Chilli Hub ~400x340)
--==============================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "JHAYDEE_HUB"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "ToggleButton"
ToggleBtn.Size = UDim2.new(0, 40, 0, 40)
ToggleBtn.Position = UDim2.new(0, 14, 0.28, 0)
ToggleBtn.AnchorPoint = Vector2.new(0, 0.5)
ToggleBtn.BackgroundColor3 = Colors.Accent
ToggleBtn.Text = "J"
ToggleBtn.TextColor3 = Color3.new(1, 1, 1)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 18
ToggleBtn.AutoButtonColor = false
ToggleBtn.Parent = ScreenGui

Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 10)
local ToggleStroke = Instance.new("UIStroke", ToggleBtn)
ToggleStroke.Color = Color3.fromRGB(255, 70, 70)
ToggleStroke.Thickness = 1.5
ToggleStroke.Transparency = 0.3

-- Compact main panel
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 400, 0, 340)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3 = Colors.Background
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Visible = true
Main.Parent = ScreenGui

Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 8)
local MainStroke = Instance.new("UIStroke", Main)
MainStroke.Color = Colors.Border
MainStroke.Thickness = 1.4
MainStroke.Transparency = 0.25

-- Header
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 32)
TopBar.BackgroundColor3 = Colors.Header
TopBar.BorderSizePixel = 0
TopBar.Parent = Main
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 8)
local TopFix = Instance.new("Frame")
TopFix.Size = UDim2.new(1, 0, 0, 10)
TopFix.Position = UDim2.new(0, 0, 1, -10)
TopFix.BackgroundColor3 = Colors.Header
TopFix.BorderSizePixel = 0
TopFix.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 12, 0, 0)
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.new(1, 1, 1)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "JHAYDEE HUB"
Title.Parent = TopBar

local Close = Instance.new("TextButton")
Close.Size = UDim2.new(0, 24, 0, 24)
Close.Position = UDim2.new(1, -28, 0.5, -12)
Close.BackgroundColor3 = Color3.fromRGB(130, 28, 28)
Close.Text = "×"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.Font = Enum.Font.GothamBold
Close.TextSize = 16
Close.AutoButtonColor = false
Close.Parent = TopBar
Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 5)

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 90, 1, -32)
Sidebar.Position = UDim2.new(0, 0, 0, 32)
Sidebar.BackgroundColor3 = Colors.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Main

local function createSidebarBtn(text, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -10, 0, 30)
    btn.Position = UDim2.new(0, 5, 0, 8 + (order - 1) * 36)
    btn.BackgroundColor3 = Colors.SurfaceAlt
    btn.Text = text
    btn.TextColor3 = Colors.Text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.Parent = Sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    return btn
end

local TabFarm = createSidebarBtn("Farm", 1)
local TabESP = createSidebarBtn("ESP", 2)
local TabPlayer = createSidebarBtn("Player", 3)
local TabServer = createSidebarBtn("Server", 4)
local TabMap = createSidebarBtn("Map", 5)

-- Content
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -90, 1, -32)
Content.Position = UDim2.new(0, 90, 0, 32)
Content.BackgroundColor3 = Colors.Background
Content.BorderSizePixel = 0
Content.ClipsDescendants = true
Content.Parent = Main

--==============================================================
-- HELPERS
--==============================================================

local function createSection(parent, title, yPos, height)
    local section = Instance.new("Frame")
    section.Size = UDim2.new(1, -14, 0, height)
    section.Position = UDim2.new(0, 7, 0, yPos)
    section.BackgroundColor3 = Colors.Surface
    section.BorderSizePixel = 0
    section.Parent = parent
    Instance.new("UICorner", section).CornerRadius = UDim.new(0, 6)

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -12, 0, 22)
    header.Position = UDim2.new(0, 8, 0, 3)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.TextSize = 11
    header.TextColor3 = Colors.Text
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = "▼  " .. title
    header.Parent = section
    return section
end

local function createToggleRow(parent, text, y, defaultOn)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -14, 0, 24)
    row.Position = UDim2.new(0, 7, 0, y)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -50, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextColor3 = Colors.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = row

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 38, 0, 18)
    toggle.Position = UDim2.new(1, -42, 0.5, -9)
    toggle.BackgroundColor3 = defaultOn and Colors.Success or Color3.fromRGB(55, 55, 55)
    toggle.Text = ""
    toggle.AutoButtonColor = false
    toggle.Parent = row
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = defaultOn and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = toggle
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    return toggle, knob
end

local function setToggleVisual(toggle, knob, state)
    toggle.BackgroundColor3 = state and Colors.Success or Color3.fromRGB(55, 55, 55)
    knob.Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
end

--==============================================================
-- FARM PAGE
--==============================================================

local FarmPage = Instance.new("ScrollingFrame")
FarmPage.Name = "FarmPage"
FarmPage.Size = UDim2.new(1, 0, 1, 0)
FarmPage.BackgroundTransparency = 1
FarmPage.BorderSizePixel = 0
FarmPage.ScrollBarThickness = 3
FarmPage.ScrollBarImageColor3 = Colors.Accent
FarmPage.CanvasSize = UDim2.new(0, 0, 0, 460)
FarmPage.Visible = true
FarmPage.Parent = Content

local FarmStatusSection = createSection(FarmPage, "Farm Status", 6, 52)
local FarmStatusLabel = Instance.new("TextLabel")
FarmStatusLabel.Size = UDim2.new(1, -14, 0, 22)
FarmStatusLabel.Position = UDim2.new(0, 7, 0, 26)
FarmStatusLabel.BackgroundColor3 = Colors.SurfaceAlt
FarmStatusLabel.Font = Enum.Font.Gotham
FarmStatusLabel.TextSize = 11
FarmStatusLabel.TextColor3 = Colors.TextDim
FarmStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
FarmStatusLabel.Text = "  Idle"
FarmStatusLabel.Parent = FarmStatusSection
Instance.new("UICorner", FarmStatusLabel).CornerRadius = UDim.new(0, 4)

setFarmStatus = function(text)
    FarmStatusText = text
    FarmStatusLabel.Text = "  " .. text
end

local AutoFarmSection = createSection(FarmPage, "Auto Collect Eggs", 64, 130)
local FarmToggle, FarmKnob = createToggleRow(AutoFarmSection, "Auto Collect Eggs", 26, false)
local GlobalESPToggle, GlobalESPKnob = createToggleRow(AutoFarmSection, "Global ESP", 52, true)

local ModeLabel = Instance.new("TextLabel")
ModeLabel.Size = UDim2.new(0, 70, 0, 20)
ModeLabel.Position = UDim2.new(0, 7, 0, 82)
ModeLabel.BackgroundTransparency = 1
ModeLabel.Font = Enum.Font.Gotham
ModeLabel.TextSize = 11
ModeLabel.TextColor3 = Colors.TextDim
ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
ModeLabel.Text = "After grab:"
ModeLabel.Parent = AutoFarmSection

local ModeTP = Instance.new("TextButton")
ModeTP.Size = UDim2.new(0, 78, 0, 20)
ModeTP.Position = UDim2.new(0, 78, 0, 82)
ModeTP.BackgroundColor3 = Colors.Accent
ModeTP.Text = "TP Home"
ModeTP.TextColor3 = Color3.new(1, 1, 1)
ModeTP.Font = Enum.Font.GothamBold
ModeTP.TextSize = 10
ModeTP.AutoButtonColor = false
ModeTP.Parent = AutoFarmSection
Instance.new("UICorner", ModeTP).CornerRadius = UDim.new(0, 4)

local ModeTwin = Instance.new("TextButton")
ModeTwin.Size = UDim2.new(0, 78, 0, 20)
ModeTwin.Position = UDim2.new(0, 164, 0, 82)
ModeTwin.BackgroundColor3 = Colors.SurfaceAlt
ModeTwin.Text = "Twin"
ModeTwin.TextColor3 = Colors.Text
ModeTwin.Font = Enum.Font.GothamBold
ModeTwin.TextSize = 10
ModeTwin.AutoButtonColor = false
ModeTwin.Parent = AutoFarmSection
Instance.new("UICorner", ModeTwin).CornerRadius = UDim.new(0, 4)

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

local TargetSection = createSection(FarmPage, "Target Eggs", 200, 200)
local SelectAllBtn = Instance.new("TextButton")
SelectAllBtn.Size = UDim2.new(0, 58, 0, 18)
SelectAllBtn.Position = UDim2.new(1, -128, 0, 4)
SelectAllBtn.BackgroundColor3 = Colors.Info
SelectAllBtn.Text = "All"
SelectAllBtn.TextColor3 = Color3.new(1, 1, 1)
SelectAllBtn.Font = Enum.Font.GothamBold
SelectAllBtn.TextSize = 10
SelectAllBtn.AutoButtonColor = false
SelectAllBtn.Parent = TargetSection
Instance.new("UICorner", SelectAllBtn).CornerRadius = UDim.new(0, 4)

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0, 58, 0, 18)
ClearBtn.Position = UDim2.new(1, -64, 0, 4)
ClearBtn.BackgroundColor3 = Colors.SurfaceAlt
ClearBtn.Text = "Clear"
ClearBtn.TextColor3 = Colors.Text
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.TextSize = 10
ClearBtn.AutoButtonColor = false
ClearBtn.Parent = TargetSection
Instance.new("UICorner", ClearBtn).CornerRadius = UDim.new(0, 4)

local FarmList = Instance.new("ScrollingFrame")
FarmList.Size = UDim2.new(1, -12, 0, 160)
FarmList.Position = UDim2.new(0, 6, 0, 28)
FarmList.BackgroundColor3 = Colors.SurfaceAlt
FarmList.BorderSizePixel = 0
FarmList.ScrollBarThickness = 3
FarmList.ScrollBarImageColor3 = Colors.Accent
FarmList.CanvasSize = UDim2.new(0, 0, 0, 0)
FarmList.Parent = TargetSection
Instance.new("UICorner", FarmList).CornerRadius = UDim.new(0, 4)

local FarmListLayout = Instance.new("UIListLayout")
FarmListLayout.Padding = UDim.new(0, 2)
FarmListLayout.SortOrder = Enum.SortOrder.Name
FarmListLayout.Parent = FarmList
local FarmListPadding = Instance.new("UIPadding")
FarmListPadding.PaddingTop = UDim.new(0, 3)
FarmListPadding.PaddingBottom = UDim.new(0, 3)
FarmListPadding.PaddingLeft = UDim.new(0, 3)
FarmListPadding.PaddingRight = UDim.new(0, 3)
FarmListPadding.Parent = FarmList
FarmListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    FarmList.CanvasSize = UDim2.new(0, 0, 0, FarmListLayout.AbsoluteContentSize.Y + 8)
end)

--==============================================================
-- ESP PAGE
--==============================================================

local ESPPage = Instance.new("ScrollingFrame")
ESPPage.Name = "ESPPage"
ESPPage.Size = UDim2.new(1, 0, 1, 0)
ESPPage.BackgroundTransparency = 1
ESPPage.BorderSizePixel = 0
ESPPage.ScrollBarThickness = 3
ESPPage.ScrollBarImageColor3 = Colors.Accent
ESPPage.CanvasSize = UDim2.new(0, 0, 0, 400)
ESPPage.Visible = false
ESPPage.Parent = Content

local ESPControlSection = createSection(ESPPage, "ESP Controls", 6, 70)
local PlotTP = Instance.new("TextButton")
PlotTP.Size = UDim2.new(0, 90, 0, 24)
PlotTP.Position = UDim2.new(0, 7, 0, 30)
PlotTP.BackgroundColor3 = Colors.Info
PlotTP.Text = "My Plot"
PlotTP.TextColor3 = Color3.new(1, 1, 1)
PlotTP.Font = Enum.Font.GothamBold
PlotTP.TextSize = 11
PlotTP.AutoButtonColor = false
PlotTP.Parent = ESPControlSection
Instance.new("UICorner", PlotTP).CornerRadius = UDim.new(0, 4)

local CountLabel = Instance.new("TextLabel")
CountLabel.Size = UDim2.new(0, 80, 0, 24)
CountLabel.Position = UDim2.new(0, 105, 0, 30)
CountLabel.BackgroundColor3 = Colors.SurfaceAlt
CountLabel.Text = "Eggs: 0"
CountLabel.TextColor3 = Colors.Text
CountLabel.Font = Enum.Font.GothamBold
CountLabel.TextSize = 11
CountLabel.Parent = ESPControlSection
Instance.new("UICorner", CountLabel).CornerRadius = UDim.new(0, 4)

local SearchSection = createSection(ESPPage, "Search & List", 82, 280)
local SearchBox = Instance.new("Frame")
SearchBox.Size = UDim2.new(1, -14, 0, 24)
SearchBox.Position = UDim2.new(0, 7, 0, 28)
SearchBox.BackgroundColor3 = Colors.SurfaceAlt
SearchBox.BorderSizePixel = 0
SearchBox.Parent = SearchSection
Instance.new("UICorner", SearchBox).CornerRadius = UDim.new(0, 4)

local Search = Instance.new("TextBox")
Search.Position = UDim2.new(0, 8, 0, 0)
Search.Size = UDim2.new(1, -16, 1, 0)
Search.BackgroundTransparency = 1
Search.TextColor3 = Colors.Text
Search.PlaceholderColor3 = Colors.TextDim
Search.PlaceholderText = "Search egg type..."
Search.Text = ""
Search.ClearTextOnFocus = false
Search.Font = Enum.Font.Gotham
Search.TextSize = 11
Search.TextXAlignment = Enum.TextXAlignment.Left
Search.Parent = SearchBox

local List = Instance.new("ScrollingFrame")
List.Size = UDim2.new(1, -14, 0, 210)
List.Position = UDim2.new(0, 7, 0, 58)
List.BackgroundColor3 = Colors.SurfaceAlt
List.BorderSizePixel = 0
List.ScrollBarThickness = 3
List.ScrollBarImageColor3 = Colors.Accent
List.CanvasSize = UDim2.new(0, 0, 0, 0)
List.Parent = SearchSection
Instance.new("UICorner", List).CornerRadius = UDim.new(0, 4)

local ListPadding = Instance.new("UIPadding")
ListPadding.PaddingTop = UDim.new(0, 3)
ListPadding.PaddingBottom = UDim.new(0, 3)
ListPadding.PaddingLeft = UDim.new(0, 3)
ListPadding.PaddingRight = UDim.new(0, 3)
ListPadding.Parent = List

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 2)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = List
ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    List.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 8)
end)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -14, 0, 20)
Status.Position = UDim2.new(0, 7, 1, -26)
Status.BackgroundColor3 = Colors.SurfaceAlt
Status.Font = Enum.Font.Gotham
Status.TextSize = 10
Status.TextColor3 = Colors.TextDim
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Text = "  Online"
Status.Parent = ESPPage
Instance.new("UICorner", Status).CornerRadius = UDim.new(0, 4)

local StatusExpiresAt = 0
local function showStatus(message, duration)
    Status.Text = "  " .. message
    StatusExpiresAt = os.clock() + (duration or 3)
end

--==============================================================
-- PLAYER PAGE (fully functional)
--==============================================================

local PlayerPage = Instance.new("Frame")
PlayerPage.Name = "PlayerPage"
PlayerPage.Size = UDim2.new(1, 0, 1, 0)
PlayerPage.BackgroundTransparency = 1
PlayerPage.Visible = false
PlayerPage.Parent = Content

local PlayerSection = createSection(PlayerPage, "Movement", 6, 150)
local SpeedToggle, SpeedKnob = createToggleRow(PlayerSection, "Speed Boost", 28, false)
local JumpToggle, JumpKnob = createToggleRow(PlayerSection, "Infinite Jump", 56, false)
local NoclipToggle, NoclipKnob = createToggleRow(PlayerSection, "Noclip", 84, false)
local InstantToggle, InstantKnob = createToggleRow(PlayerSection, "Instant Pickup", 112, false)

--==============================================================
-- SERVER PAGE
--==============================================================

local ServerPage = Instance.new("Frame")
ServerPage.Name = "ServerPage"
ServerPage.Size = UDim2.new(1, 0, 1, 0)
ServerPage.BackgroundTransparency = 1
ServerPage.Visible = false
ServerPage.Parent = Content

local ServerSection = createSection(ServerPage, "Server", 6, 140)
local RejoinBtn = Instance.new("TextButton")
RejoinBtn.Size = UDim2.new(1, -14, 0, 28)
RejoinBtn.Position = UDim2.new(0, 7, 0, 30)
RejoinBtn.BackgroundColor3 = Colors.Accent
RejoinBtn.Text = "Rejoin Server"
RejoinBtn.TextColor3 = Color3.new(1, 1, 1)
RejoinBtn.Font = Enum.Font.GothamBold
RejoinBtn.TextSize = 12
RejoinBtn.AutoButtonColor = false
RejoinBtn.Parent = ServerSection
Instance.new("UICorner", RejoinBtn).CornerRadius = UDim.new(0, 5)

local HopBtn = Instance.new("TextButton")
HopBtn.Size = UDim2.new(1, -14, 0, 28)
HopBtn.Position = UDim2.new(0, 7, 0, 66)
HopBtn.BackgroundColor3 = Colors.SurfaceAlt
HopBtn.Text = "Server Hop (same place)"
HopBtn.TextColor3 = Colors.Text
HopBtn.Font = Enum.Font.GothamBold
HopBtn.TextSize = 12
HopBtn.AutoButtonColor = false
HopBtn.Parent = ServerSection
Instance.new("UICorner", HopBtn).CornerRadius = UDim.new(0, 5)

local CopyJobBtn = Instance.new("TextButton")
CopyJobBtn.Size = UDim2.new(1, -14, 0, 28)
CopyJobBtn.Position = UDim2.new(0, 7, 0, 102)
CopyJobBtn.BackgroundColor3 = Colors.SurfaceAlt
CopyJobBtn.Text = "Copy Job ID"
CopyJobBtn.TextColor3 = Colors.Text
CopyJobBtn.Font = Enum.Font.GothamBold
CopyJobBtn.TextSize = 12
CopyJobBtn.AutoButtonColor = false
CopyJobBtn.Parent = ServerSection
Instance.new("UICorner", CopyJobBtn).CornerRadius = UDim.new(0, 5)

--==============================================================
-- MAP PAGE (live eggs on map + distance + TP — Chilli style)
--==============================================================

local MapPage = Instance.new("ScrollingFrame")
MapPage.Name = "MapPage"
MapPage.Size = UDim2.new(1, 0, 1, 0)
MapPage.BackgroundTransparency = 1
MapPage.BorderSizePixel = 0
MapPage.ScrollBarThickness = 3
MapPage.ScrollBarImageColor3 = Colors.Accent
MapPage.CanvasSize = UDim2.new(0, 0, 0, 400)
MapPage.Visible = false
MapPage.Parent = Content

local MapHeaderSection = createSection(MapPage, "Map Eggs", 6, 52)
local MapInfoLabel = Instance.new("TextLabel")
MapInfoLabel.Size = UDim2.new(1, -14, 0, 22)
MapInfoLabel.Position = UDim2.new(0, 7, 0, 26)
MapInfoLabel.BackgroundTransparency = 1
MapInfoLabel.Font = Enum.Font.Gotham
MapInfoLabel.TextSize = 11
MapInfoLabel.TextColor3 = Colors.TextDim
MapInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
MapInfoLabel.Text = "Eggs currently on the map"
MapInfoLabel.Parent = MapHeaderSection

local MapRefreshBtn = Instance.new("TextButton")
MapRefreshBtn.Size = UDim2.new(0, 70, 0, 20)
MapRefreshBtn.Position = UDim2.new(1, -78, 0, 4)
MapRefreshBtn.BackgroundColor3 = Colors.Accent
MapRefreshBtn.Text = "Refresh"
MapRefreshBtn.TextColor3 = Color3.new(1, 1, 1)
MapRefreshBtn.Font = Enum.Font.GothamBold
MapRefreshBtn.TextSize = 10
MapRefreshBtn.AutoButtonColor = false
MapRefreshBtn.Parent = MapHeaderSection
Instance.new("UICorner", MapRefreshBtn).CornerRadius = UDim.new(0, 4)

local MapListSection = createSection(MapPage, "Nearby / All Eggs", 64, 240)
local MapListFrame = Instance.new("ScrollingFrame")
MapListFrame.Size = UDim2.new(1, -12, 1, -28)
MapListFrame.Position = UDim2.new(0, 6, 0, 24)
MapListFrame.BackgroundTransparency = 1
MapListFrame.BorderSizePixel = 0
MapListFrame.ScrollBarThickness = 3
MapListFrame.ScrollBarImageColor3 = Colors.Accent
MapListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
MapListFrame.Parent = MapListSection

local MapListLayout = Instance.new("UIListLayout")
MapListLayout.SortOrder = Enum.SortOrder.LayoutOrder
MapListLayout.Padding = UDim.new(0, 3)
MapListLayout.Parent = MapListFrame

local refreshMapList
refreshMapList = function()
    for _, child in ipairs(MapListFrame:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then
            child:Destroy()
        end
    end
    getCharacter()
    local eggs = {}
    if RenderedEggs then
        for _, model in ipairs(RenderedEggs:GetChildren()) do
            if model:IsA("Model") then
                local root = getRootPart(model)
                if root then
                    local dist = RootPart and (RootPart.Position - root.Position).Magnitude or 0
                    table.insert(eggs, { model = model, name = model.Name, dist = dist, root = root })
                end
            end
        end
    end
    table.sort(eggs, function(a, b) return a.dist < b.dist end)

    MapInfoLabel.Text = (#eggs > 0) and (tostring(#eggs) .. " eggs on map") or "No eggs on map"
    local order = 0
    for _, info in ipairs(eggs) do
        order = order + 1
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, -4, 0, 26)
        row.BackgroundColor3 = Colors.SurfaceAlt
        row.Text = ""
        row.AutoButtonColor = false
        row.LayoutOrder = order
        row.Parent = MapListFrame
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(0.55, 0, 1, 0)
        nameLbl.Position = UDim2.new(0, 8, 0, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 11
        nameLbl.TextColor3 = Colors.Text
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.Text = info.name
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = row

        local distLbl = Instance.new("TextLabel")
        distLbl.Size = UDim2.new(0.25, 0, 1, 0)
        distLbl.Position = UDim2.new(0.55, 0, 0, 0)
        distLbl.BackgroundTransparency = 1
        distLbl.Font = Enum.Font.Gotham
        distLbl.TextSize = 10
        distLbl.TextColor3 = Colors.TextDim
        distLbl.TextXAlignment = Enum.TextXAlignment.Right
        distLbl.Text = string.format("%.0fm", info.dist)
        distLbl.Parent = row

        local tpLbl = Instance.new("TextLabel")
        tpLbl.Size = UDim2.new(0.18, -4, 0, 18)
        tpLbl.Position = UDim2.new(0.82, 0, 0.5, -9)
        tpLbl.BackgroundColor3 = Colors.Accent
        tpLbl.Font = Enum.Font.GothamBold
        tpLbl.TextSize = 9
        tpLbl.TextColor3 = Color3.new(1, 1, 1)
        tpLbl.Text = "TP"
        tpLbl.Parent = row
        Instance.new("UICorner", tpLbl).CornerRadius = UDim.new(0, 3)

        local modelRef = info.model
        row.MouseButton1Click:Connect(function()
            getCharacter()
            if not Character or not RootPart then return end
            if not modelRef or not modelRef.Parent then
                refreshMapList()
                return
            end
            local cf = getEggGrabCFrame(modelRef) or getEggTopCFrame(modelRef)
            if cf then
                safeTeleport(Character, RootPart, cf)
                setFarmStatus("Map TP → " .. modelRef.Name)
            end
        end)
    end
    MapListFrame.CanvasSize = UDim2.new(0, 0, 0, order * 29 + 4)
end

MapRefreshBtn.MouseButton1Click:Connect(function()
    refreshMapList()
end)

-- Auto-refresh map list while Map tab is open
task.spawn(function()
    while Running do
        if CurrentTab == "Map" and PanelVisible then
            pcall(refreshMapList)
        end
        task.wait(1.5)
    end
end)

--==============================================================
-- TAB SWITCH
--==============================================================

local allPages = { Farm = FarmPage, ESP = ESPPage, Player = PlayerPage, Server = ServerPage, Map = MapPage }
local allTabs = { Farm = TabFarm, ESP = TabESP, Player = TabPlayer, Server = TabServer, Map = TabMap }

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
    if tab == "Farm" and refreshFarmList then refreshFarmList() end
    if tab == "Map" and refreshMapList then refreshMapList() end
end

TabFarm.MouseButton1Click:Connect(function() setTab("Farm") end)
TabESP.MouseButton1Click:Connect(function() setTab("ESP") end)
TabPlayer.MouseButton1Click:Connect(function() setTab("Player") end)
TabServer.MouseButton1Click:Connect(function() setTab("Server") end)
TabMap.MouseButton1Click:Connect(function() setTab("Map") end)
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

local dragging, dragStart, startPosition = false, nil, nil
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = Main.Position
    end
end)
TopBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
Connections.InputChanged = UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local delta = input.Position - dragStart
    Main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
end)

--==============================================================
-- MOVEMENT FEATURES (fully functional)
--==============================================================

SpeedToggle.MouseButton1Click:Connect(function()
    SpeedBoostEnabled = not SpeedBoostEnabled
    setToggleVisual(SpeedToggle, SpeedKnob, SpeedBoostEnabled)
    getCharacter()
    if Humanoid then
        Humanoid.WalkSpeed = SpeedBoostEnabled and BOOST_WALKSPEED or DEFAULT_WALKSPEED
    end
    showStatus(SpeedBoostEnabled and "Speed Boost ON" or "Speed Boost OFF")
end)

task.spawn(function()
    while Running do
        if SpeedBoostEnabled then
            getCharacter()
            if Humanoid and Humanoid.WalkSpeed ~= BOOST_WALKSPEED then
                Humanoid.WalkSpeed = BOOST_WALKSPEED
            end
        end
        task.wait(0.5)
    end
end)

JumpToggle.MouseButton1Click:Connect(function()
    InfiniteJumpEnabled = not InfiniteJumpEnabled
    setToggleVisual(JumpToggle, JumpKnob, InfiniteJumpEnabled)
    showStatus(InfiniteJumpEnabled and "Infinite Jump ON" or "Infinite Jump OFF")
end)

Connections.JumpRequest = UserInputService.JumpRequest:Connect(function()
    if InfiniteJumpEnabled then
        getCharacter()
        if Humanoid then
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

NoclipToggle.MouseButton1Click:Connect(function()
    NoclipEnabled = not NoclipEnabled
    setToggleVisual(NoclipToggle, NoclipKnob, NoclipEnabled)
    showStatus(NoclipEnabled and "Noclip ON" or "Noclip OFF")
end)

Connections.Noclip = RunService.Stepped:Connect(function()
    if not NoclipEnabled then return end
    getCharacter()
    if Character then
        for _, part in ipairs(Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

InstantToggle.MouseButton1Click:Connect(function()
    InstantPickupEnabled = not InstantPickupEnabled
    setToggleVisual(InstantToggle, InstantKnob, InstantPickupEnabled)
    showStatus(InstantPickupEnabled and "Instant Pickup ON" or "Instant Pickup OFF")
end)

task.spawn(function()
    while Running do
        if InstantPickupEnabled then
            getCharacter()
            if RootPart then
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") and obj.Enabled then
                        local parent = obj.Parent
                        if parent and parent:IsA("BasePart") then
                            local dist = (RootPart.Position - parent.Position).Magnitude
                            if dist < 18 then
                                pcall(function()
                                    if fireproximityprompt then
                                        fireproximityprompt(obj, 0)
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.15)
    end
end)

--==============================================================
-- CREATE ESP / GROUPS / ENTRIES
--==============================================================

local function createESP(model)
    if not model or not model:IsA("Model") or not model.Parent or ESPs[model] then return end
    local root = getRootPart(model)
    if not root then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EggESP"
    billboard.Adornee = root
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 160, 0, 36)
    billboard.StudsOffset = Vector3.new(0, 2.4, 0)
    billboard.Enabled = GlobalESPEnabled and getEggTypeEnabled(model)
    billboard.Parent = root

    local label = Instance.new("TextLabel")
    label.Name = "Info"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 11
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.25
    label.Text = model.Name
    label.Parent = billboard

    local highlight = nil
    if SHOW_HIGHLIGHT then
        highlight = Instance.new("Highlight")
        highlight.Name = "EggHighlight"
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0.12
        highlight.Adornee = model
        highlight.Enabled = GlobalESPEnabled and getEggTypeEnabled(model)
        highlight.Parent = model
    end

    ESPs[model] = { Billboard = billboard, Label = label, Highlight = highlight }
end

local function destroyESP(model)
    local esp = ESPs[model]
    if not esp then return end
    if esp.Billboard then esp.Billboard:Destroy() end
    if esp.Highlight then esp.Highlight:Destroy() end
    ESPs[model] = nil
end

local function createEggGroup(groupName)
    if EggGroups[groupName] then return EggGroups[groupName] end

    local group = {
        Name = groupName, Eggs = {}, Expanded = true, TypeESPEnabled = true,
        GroupFrame = nil, Header = nil, Container = nil, HeaderTitle = nil, TypeESPButton = nil
    }

    local GroupFrame = Instance.new("Frame")
    GroupFrame.Name = "Group_" .. groupName
    GroupFrame.Size = UDim2.new(1, -2, 0, 26)
    GroupFrame.BackgroundTransparency = 1
    GroupFrame.AutomaticSize = Enum.AutomaticSize.Y
    GroupFrame.Parent = List

    local GroupLayout = Instance.new("UIListLayout")
    GroupLayout.Padding = UDim.new(0, 2)
    GroupLayout.SortOrder = Enum.SortOrder.LayoutOrder
    GroupLayout.Parent = GroupFrame

    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, -2, 0, 24)
    Header.BackgroundColor3 = Colors.Surface
    Header.BorderSizePixel = 0
    Header.LayoutOrder = 1
    Header.Parent = GroupFrame
    Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 4)

    local Toggle = Instance.new("TextButton")
    Toggle.Size = UDim2.new(1, -52, 1, 0)
    Toggle.BackgroundTransparency = 1
    Toggle.TextXAlignment = Enum.TextXAlignment.Left
    Toggle.Font = Enum.Font.GothamBold
    Toggle.TextSize = 10
    Toggle.TextTruncate = Enum.TextTruncate.AtEnd
    Toggle.TextColor3 = Colors.Text
    Toggle.Text = "▼  " .. groupName
    Toggle.Parent = Header

    local TypeESP = Instance.new("TextButton")
    TypeESP.Size = UDim2.new(0, 42, 0, 18)
    TypeESP.Position = UDim2.new(1, -46, 0, 3)
    TypeESP.BackgroundColor3 = Colors.Success
    TypeESP.Text = "ESP"
    TypeESP.TextColor3 = Color3.new(1, 1, 1)
    TypeESP.Font = Enum.Font.GothamBold
    TypeESP.TextSize = 9
    TypeESP.AutoButtonColor = false
    TypeESP.Parent = Header
    Instance.new("UICorner", TypeESP).CornerRadius = UDim.new(0, 3)

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
        TypeESP.Text = group.TypeESPEnabled and "ESP" or "OFF"
        TypeESP.BackgroundColor3 = group.TypeESPEnabled and Colors.Success or Colors.Danger
        for model in pairs(group.Eggs) do
            local esp = ESPs[model]
            if esp then
                local enabled = GlobalESPEnabled and group.TypeESPEnabled
                esp.Billboard.Enabled = enabled
                if esp.Highlight then esp.Highlight.Enabled = enabled end
            end
        end
    end)

    if refreshFarmList then refreshFarmList() end
    return group
end

local function updateGroupLayoutOrder(group)
    local eggCount = 0
    for _ in pairs(group.Eggs) do eggCount += 1 end
    group.GroupFrame.LayoutOrder = eggCount
end

local function createEggEntry(model)
    if EggEntries[model] or not model or not model:IsA("Model") or not model.Parent then return end

    local group = createEggGroup(model.Name)
    group.Eggs[model] = true
    updateGroupLayoutOrder(group)

    local Row = Instance.new("Frame")
    Row.Name = "Egg"
    Row.Size = UDim2.new(1, -4, 0, 22)
    Row.BackgroundColor3 = Color3.fromRGB(38, 18, 18)
    Row.BorderSizePixel = 0
    Row.Parent = group.Container
    Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 3)

    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(1, -48, 1, 0)
    NameLabel.Position = UDim2.new(0, 6, 0, 0)
    NameLabel.BackgroundTransparency = 1
    NameLabel.Text = model.Name
    NameLabel.TextColor3 = Colors.Text
    NameLabel.TextXAlignment = Enum.TextXAlignment.Left
    NameLabel.Font = Enum.Font.Gotham
    NameLabel.TextSize = 10
    NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    NameLabel.Parent = Row

    local TP = Instance.new("TextButton")
    TP.Size = UDim2.new(0, 38, 0, 16)
    TP.Position = UDim2.new(1, -42, 0, 3)
    TP.BackgroundColor3 = Colors.Info
    TP.Text = "TP"
    TP.TextColor3 = Color3.new(1, 1, 1)
    TP.Font = Enum.Font.GothamBold
    TP.TextSize = 9
    TP.AutoButtonColor = false
    TP.Parent = Row
    Instance.new("UICorner", TP).CornerRadius = UDim.new(0, 3)

    local entry = { Model = model, Frame = Row, Label = NameLabel, TP = TP }
    EggEntries[model] = entry

    TP.MouseButton1Click:Connect(function()
        if not Running or not model or not model.Parent then
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
        showStatus(success and ("Teleported to " .. model.Name) or ("Teleport failed: " .. tostring(reason)))
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
    row.Frame.BackgroundColor3 = selected and Color3.fromRGB(28, 48, 28) or Color3.fromRGB(38, 18, 18)
end

local function createFarmRow(name)
    if FarmRows[name] then
        updateFarmRowVisual(name)
        return
    end

    local Row = Instance.new("Frame")
    Row.Name = name
    Row.Size = UDim2.new(1, -4, 0, 24)
    Row.BackgroundColor3 = Color3.fromRGB(38, 18, 18)
    Row.BorderSizePixel = 0
    Row.Parent = FarmList
    Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 3)

    local Check = Instance.new("TextButton")
    Check.Size = UDim2.new(0, 18, 0, 18)
    Check.Position = UDim2.new(0, 3, 0.5, -9)
    Check.BackgroundColor3 = Colors.Surface
    Check.Text = ""
    Check.TextColor3 = Color3.new(1, 1, 1)
    Check.Font = Enum.Font.GothamBold
    Check.TextSize = 11
    Check.AutoButtonColor = false
    Check.Parent = Row
    Instance.new("UICorner", Check).CornerRadius = UDim.new(0, 3)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -28, 1, 0)
    Label.Position = UDim2.new(0, 26, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = ImportantEggs[name] and ("★ " .. name) or name
    Label.TextColor3 = ImportantEggs[name] and Colors.Warning or Colors.Text
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 11
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            toggle()
        end
    end)

    FarmRows[name] = { Frame = Row, Check = Check, Label = Label }
    updateFarmRowVisual(name)
end

refreshFarmList = function()
    for name in pairs(EggGroups) do createFarmRow(name) end
    for name in pairs(ImportantEggs) do
        createFarmRow(name)
        SelectedFarmEggs[name] = true
    end
    for name in pairs(SelectedFarmEggs) do createFarmRow(name) end
    for name in pairs(FarmRows) do updateFarmRowVisual(name) end
end

--==============================================================
-- REGISTER
--==============================================================

local function registerModel(model)
    if not Running or not model or not model:IsA("Model") or not model.Parent then return end
    if not model:IsDescendantOf(RenderedEggs) then return end
    if not EggEntries[model] then createEggEntry(model) end
    if not ESPs[model] then createESP(model) end
    if updateSearch then updateSearch() end
    if refreshFarmList then refreshFarmList() end
end

local function tryRegisterEgg(object)
    if not Running or not object or not object:IsA("Model") then return end
    if not object:IsDescendantOf(RenderedEggs) then return end
    task.defer(function()
        if not Running or not object.Parent or not object:IsDescendantOf(RenderedEggs) then return end
        local deadline = os.clock() + 2
        repeat
            if not Running or not object.Parent or not object:IsDescendantOf(RenderedEggs) then return end
            if getRootPart(object) then break end
            task.wait(0.05)
        until os.clock() >= deadline
        if not Running or not object.Parent or not object:IsDescendantOf(RenderedEggs) then return end
        registerModel(object)
    end)
end

for _, object in ipairs(RenderedEggs:GetDescendants()) do
    if object:IsA("Model") then registerModel(object) end
end
Connections.DescendantAdded = RenderedEggs.DescendantAdded:Connect(tryRegisterEgg)

--==============================================================
-- TELEPORT + PLOT
--==============================================================

getEggTopCFrame = function(egg)
    if not egg or not egg:IsA("Model") or not egg.Parent then return nil end
    local cf, size = egg:GetBoundingBox()
    if not isValidPosition(cf.Position) or not isFiniteNumber(size.Y) or size.Y <= 0 then return nil end
    local targetPosition = Vector3.new(cf.Position.X, cf.Position.Y + (size.Y * 0.5) + HEIGHT_OFFSET, cf.Position.Z)
    if not isValidPosition(targetPosition) then return nil end
    return CFrame.new(targetPosition)
end

safeTeleport = function(character, root, targetCFrame)
    if not character or not character.Parent or not root or not root.Parent or not targetCFrame then
        return false, "Invalid target"
    end
    local targetPosition = targetCFrame.Position
    if not isValidPosition(targetPosition) then return false, "Invalid position" end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    character:PivotTo(targetCFrame)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

local function scanMyPlot()
    if not Plots then return nil end
    if PlotScanCount >= MAX_PLOT_SCANS then return CachedMyPlot end
    PlotScanCount += 1
    CachedMyPlot = nil
    CachedBaseplate = nil
    for _, plot in ipairs(Plots:GetChildren()) do
        local data = plot:FindFirstChild("Data")
        if data then
            local owner = data:FindFirstChild("Owner")
            if owner and owner:IsA("ObjectValue") and owner.Value == LocalPlayer then
                CachedMyPlot = plot
                local baseplate = plot:FindFirstChild("Baseplate") or plot:FindFirstChild("Baseplate", true)
                if baseplate and baseplate:IsA("BasePart") then CachedBaseplate = baseplate end
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
    local baseplate = plot:FindFirstChild("Baseplate") or plot:FindFirstChild("Baseplate", true)
    if baseplate and baseplate:IsA("BasePart") then
        CachedBaseplate = baseplate
        return baseplate
    end
    return nil
end

local function getBaseplateTopCFrame(baseplate)
    if not baseplate or not baseplate:IsA("BasePart") or not baseplate.Parent then return nil end
    local size, cf = baseplate.Size, baseplate.CFrame
    if not isFiniteNumber(size.Y) or size.Y <= 0 or not isValidPosition(cf.Position) then return nil end
    local target = cf * CFrame.new(0, (size.Y * 0.5) + HEIGHT_OFFSET, 0)
    if not isValidPosition(target.Position) then return nil end
    return target
end

-- Side of the plot — CLEARLY OUTSIDE the ranch so the egg does not auto-place
local function getPlotSideCFrame(baseplate)
    if not baseplate or not baseplate:IsA("BasePart") or not baseplate.Parent then return nil end
    local size, cf = baseplate.Size, baseplate.CFrame
    if not isFiniteNumber(size.Y) or size.Y <= 0 or not isValidPosition(cf.Position) then return nil end
    -- Use half the longest horizontal side + extra studs so we are past the plot edge
    local halfEdge = math.max(size.X, size.Z) * 0.5
    local offset = halfEdge + TWIN_SIDE_EXTRA
    local side = cf * CFrame.new(offset, (size.Y * 0.5) + 6, 0)
    if not isValidPosition(side.Position) then return nil end
    return side
end

local function teleportToMyPlot()
    getCharacter()
    if not Character or not RootPart then return false, "Character not found" end
    local baseplate = getMyPlotBaseplate()
    if not baseplate then return false, "Plot not found" end
    local target = getBaseplateTopCFrame(baseplate)
    if not target then return false, "Invalid baseplate" end
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
-- GRAB
--==============================================================

local function tryFireProximityPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    return pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt, 0)
            fireproximityprompt(prompt)
        else
            prompt:InputHoldBegin()
            task.wait(0.02)
            prompt:InputHoldEnd()
        end
    end)
end

local function tryFireClickDetector(detector)
    if not detector or not detector:IsA("ClickDetector") then return false end
    return pcall(function()
        if fireclickdetector then
            fireclickdetector(detector)
            fireclickdetector(detector, 1)
        end
    end)
end

local function pressKeyE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

local function collectPrompts(model)
    local prompts, clicks = {}, {}
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then table.insert(prompts, desc)
        elseif desc:IsA("ClickDetector") then table.insert(clicks, desc) end
    end
    local parent = model.Parent
    if parent then
        for _, desc in ipairs(parent:GetChildren()) do
            if desc:IsA("ProximityPrompt") then table.insert(prompts, desc)
            elseif desc:IsA("ClickDetector") then table.insert(clicks, desc) end
        end
    end
    return prompts, clicks
end

local function tryGrabEgg(model)
    if not model or not model.Parent then return false end
    local prompts, clicks = collectPrompts(model)
    local grabbed = false
    for _ = 1, GRAB_SPAM do
        if not model.Parent then return true end
        for _, prompt in ipairs(prompts) do
            if prompt and prompt.Parent and tryFireProximityPrompt(prompt) then grabbed = true end
        end
        for _, detector in ipairs(clicks) do
            if detector and detector.Parent and tryFireClickDetector(detector) then grabbed = true end
        end
        if #prompts == 0 and #clicks == 0 then pressKeyE() end
        task.wait(0.025)
    end
    return grabbed
end

local function waitForEggGrabConfirmed(egg, timeout)
    local deadline = os.clock() + (timeout or GRAB_CONFIRM_TIMEOUT)
    while os.clock() < deadline do
        if not egg or not egg.Parent then return true end
        if not RenderedEggs or not egg:IsDescendantOf(RenderedEggs) then return true end
        task.wait(0.05)
    end
    return false
end

local function grabEggUntilConfirmed(egg)
    if not egg or not egg.Parent then return true end
    for attempt = 1, GRAB_RETRIES do
        if not egg.Parent or not egg:IsDescendantOf(RenderedEggs) then return true end
        setFarmStatus("GRAB " .. tostring(egg.Name) .. " (" .. attempt .. "/" .. GRAB_RETRIES .. ")")
        tryGrabEgg(egg)
        if waitForEggGrabConfirmed(egg, GRAB_CONFIRM_TIMEOUT) then return true end
        if attempt < GRAB_RETRIES then task.wait(0.12) end
    end
    return false
end

local function getEggGrabCFrame(egg)
    if not egg or not egg:IsA("Model") or not egg.Parent then return nil end
    local cf, size = egg:GetBoundingBox()
    if not isValidPosition(cf.Position) then return nil end
    local y = cf.Position.Y + (isFiniteNumber(size.Y) and (size.Y * 0.5) or 0) + GRAB_HEIGHT
    local pos = Vector3.new(cf.Position.X, y, cf.Position.Z)
    if not isValidPosition(pos) then return nil end
    return CFrame.new(pos)
end

-- Script presses the red DROP button so the egg is placed on the ground
-- (not the player – the script does this automatically)
local function pressDropButton()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local found = false

    local function tryClick(btn)
        if not btn then return end
        pcall(function()
            if firesignal then
                pcall(function() firesignal(btn.MouseButton1Click) end)
                pcall(function() firesignal(btn.Activated) end)
                pcall(function() firesignal(btn.MouseButton1Down) end)
                pcall(function() firesignal(btn.MouseButton1Up) end)
            end
            pcall(function() btn:Activate() end)
            local pos = btn.AbsolutePosition
            local size = btn.AbsoluteSize
            if size and size.X > 5 and size.Y > 5 then
                local cx = pos.X + size.X / 2
                local cy = pos.Y + size.Y / 2
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                task.wait(0.05)
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
            end
        end)
        found = true
    end

    -- 1) Find any button/label that says DROP
    for _, desc in ipairs(gui:GetDescendants()) do
        local text, name = "", ""
        pcall(function()
            if desc:IsA("TextButton") or desc:IsA("TextLabel") then
                text = string.upper(tostring(desc.Text or ""))
            end
            name = string.upper(tostring(desc.Name or ""))
        end)
        if text == "DROP" or name == "DROP"
            or string.find(text, "DROP", 1, true)
            or string.find(name, "DROP", 1, true) then
            -- Prefer the actual button; if it's a label, click its parent button
            if desc:IsA("TextButton") or desc:IsA("ImageButton") then
                tryClick(desc)
            else
                local parent = desc.Parent
                if parent and (parent:IsA("TextButton") or parent:IsA("ImageButton") or parent:IsA("Frame") or parent:IsA("ImageLabel")) then
                    tryClick(parent)
                end
                tryClick(desc)
            end
        end
    end

    -- 2) Fallback: click the right side of the screen where the red DROP button sits in the video
    if not found then
        pcall(function()
            local cam = workspace.CurrentCamera
            if cam then
                local vp = cam.ViewportSize
                -- DROP is a tall red button on the right edge, middle-right
                local cx = vp.X - 40
                local cy = vp.Y * 0.45
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                task.wait(0.05)
                VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
            end
        end)
    end

    -- 3) Unequip tools (egg may be a tool in some builds)
    getCharacter()
    if Character then
        local hum = Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:UnequipTools() end) end
        for _, tool in ipairs(Character:GetChildren()) do
            if tool:IsA("Tool") then
                pcall(function() tool.Parent = LocalPlayer:FindFirstChild("Backpack") end)
            end
        end
    end

    -- 4) Common drop keys
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
    end)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
    end)

    return found
end

-- After the script drops the egg, re-grab it from the ground near the player
local function reGrabAtSide()
    getCharacter()
    if not RootPart then return end
    for _ = 1, 15 do
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.Enabled ~= false then
                local parent = obj.Parent
                if parent then
                    local part = parent:IsA("BasePart") and parent or parent:FindFirstChildWhichIsA("BasePart")
                    if part and (RootPart.Position - part.Position).Magnitude < 30 then
                        tryFireProximityPrompt(obj)
                    end
                end
            elseif obj:IsA("ClickDetector") then
                local parent = obj.Parent
                if parent then
                    local part = parent:IsA("BasePart") and parent or parent:FindFirstChildWhichIsA("BasePart")
                    if part and (RootPart.Position - part.Position).Magnitude < 30 then
                        tryFireClickDetector(obj)
                    end
                end
            end
        end
        -- Also try grabbing any nearby model that looks like an egg
        if RenderedEggs then
            for _, model in ipairs(RenderedEggs:GetChildren()) do
                if model:IsA("Model") then
                    local root = getRootPart(model)
                    if root and (RootPart.Position - root.Position).Magnitude < 30 then
                        tryGrabEgg(model)
                    end
                end
            end
        end
        pressKeyE()
        task.wait(0.05)
    end
end

-- Smooth move helper
local function smoothMoveTo(targetCFrame, statusText)
    getCharacter()
    if not Character or not RootPart or not targetCFrame then return false end
    setFarmStatus(statusText or "Moving...")
    local ok = pcall(function()
        local distance = (RootPart.Position - targetCFrame.Position).Magnitude
        local duration = math.clamp(distance / 110, 0.15, TWIN_RETURN_TIME)
        local tween = TweenService:Create(RootPart, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = targetCFrame})
        tween:Play()
        tween.Completed:Wait()
    end)
    if not ok or not RootPart.Parent then
        return safeTeleport(Character, RootPart, targetCFrame)
    end
    return true
end

--==============================================================
-- TWIN  (Script drops egg on side → re-grabs → claims on plot)
--==============================================================
--[[
  Goal: egg does NOT get auto-returned. Script does everything:
  1. Egg is in basket (after map grab)
  2. Script moves to SIDE of plot (outside ranch) + DROPS egg
  3. Script re-grabs that dropped egg
  4. Script moves onto the plot and places/claims it (you keep the egg)
]]

tryTwinOnEgg = function(eggModel)
    local plot = getMyPlot()
    if not plot then return false, "Plot not found" end
    getCharacter()
    if not Character or not RootPart then return false, "Character not found" end

    local baseplate = getMyPlotBaseplate()
    if not baseplate then return false, "Plot position not found" end

    local sideCF = getPlotSideCFrame(baseplate)
    local centerCF = getBaseplateTopCFrame(baseplate)
    if not sideCF or not centerCF then return false, "Invalid plot positions" end

    -- ============================================================
    -- STEP 1: HARD TP to SIDE of plot (OUTSIDE ranch)
    -- ============================================================
    setFarmStatus("Twin STEP1 → SIDE of plot")
    local okSide = safeTeleport(Character, RootPart, sideCF)
    if not okSide then
        pcall(function()
            if Character.PrimaryPart then
                Character:PivotTo(sideCF)
            else
                RootPart.CFrame = sideCF
            end
        end)
    end
    task.wait(0.35)
    getCharacter()
    if RootPart then
        pcall(function()
            if Character.PrimaryPart then
                Character:PivotTo(sideCF)
            else
                RootPart.CFrame = sideCF
            end
        end)
    end
    task.wait(0.12)

    -- ============================================================
    -- STEP 2: DROP egg on the side (outside plot)
    -- ============================================================
    setFarmStatus("Twin STEP2 → DROP on side")
    for _ = 1, 12 do
        pressDropButton()
        task.wait(0.07)
    end
    task.wait(TWIN_DROP_WAIT)
    getCharacter()
    if RootPart then
        pcall(function()
            if Character.PrimaryPart then
                Character:PivotTo(sideCF)
            else
                RootPart.CFrame = sideCF
            end
        end)
    end

    -- ============================================================
    -- STEP 3: Re-grab the dropped egg
    -- ============================================================
    setFarmStatus("Twin STEP3 → Re-grab")
    reGrabAtSide()
    task.wait(TWIN_REGRAB_WAIT)

    -- ============================================================
    -- STEP 4: Onto plot + place/claim (you keep the egg)
    -- ============================================================
    setFarmStatus("Twin STEP4 → Plot claim")
    getCharacter()
    if not Character or not RootPart then return false, "Character lost" end
    local okCenter = safeTeleport(Character, RootPart, centerCF)
    if not okCenter then
        pcall(function()
            if Character.PrimaryPart then
                Character:PivotTo(centerCF)
            else
                RootPart.CFrame = centerCF
            end
        end)
    end
    task.wait(TWIN_SETTLE)

    local prompts, clicks = {}, {}
    for _, desc in ipairs(plot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local n = string.lower(tostring(desc.Name or "") .. " " .. tostring(desc.ActionText or "") .. " " .. tostring(desc.ObjectText or ""))
            if string.find(n, "place", 1, true)
                or string.find(n, "nest", 1, true)
                or string.find(n, "claim", 1, true)
                or string.find(n, "egg", 1, true)
                or string.find(n, "drop", 1, true)
                or desc.Enabled ~= false then
                table.insert(prompts, desc)
            end
        elseif desc:IsA("ClickDetector") then
            table.insert(clicks, desc)
        end
    end

    local finishAt = os.clock() + TWIN_INTERACT_TIME
    while os.clock() < finishAt do
        for _, prompt in ipairs(prompts) do
            if prompt and prompt.Parent then
                tryFireProximityPrompt(prompt)
            end
        end
        for _, detector in ipairs(clicks) do
            if detector and detector.Parent then
                tryFireClickDetector(detector)
            end
        end
        pressKeyE()
        pressDropButton()
        task.wait(0.05)
    end

    return true, "Claimed – side drop → re-grab → plot"
end

afterGrabReturn = function(eggModel)
    if ReturnMode == "Twin" then
        local confirmed = waitForEggGrabConfirmed(eggModel, GRAB_CONFIRM_TIMEOUT)
        if not confirmed then
            setFarmStatus("Waiting for egg in basket...")
            -- still try Twin even if confirmation is slow
        end
        setFarmStatus("Starting Twin (side → DROP → claim)...")
        local ok, msg = tryTwinOnEgg(eggModel)
        setFarmStatus(ok and "Twin done – egg claimed" or ("Twin fail: " .. tostring(msg)))
        return ok
    else
        -- TP mode = goes straight onto plot (no side drop)
        setFarmStatus("TP → Plot (no side drop)")
        local ok = teleportToMyPlot()
        setFarmStatus(ok and "Ready" or "Plot TP failed")
        task.wait(PLOT_WAIT)
        return ok
    end
end

--==============================================================
-- AUTO FARM LOOP
--==============================================================

local function findFarmTarget()
    if not next(SelectedFarmEggs) then return nil end
    getCharacter()
    local best, bestDist = nil, math.huge
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
                            if safeTeleport(Character, RootPart, cf) then
                                setFarmStatus("GRAB " .. eggName)
                                if grabEggUntilConfirmed(target) then
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
            if FarmStatusText ~= "Idle" then setFarmStatus("Idle") end
        end
        task.wait(0.08)
    end
end)

--==============================================================
-- BUTTON CONNECTIONS
--==============================================================

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
            if esp.Highlight then esp.Highlight.Enabled = enabled end
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
    showStatus(ok and "Teleported to My Plot" or ("Teleport failed: " .. tostring(reason)))
end)

SelectAllBtn.MouseButton1Click:Connect(function()
    for name in pairs(EggGroups) do SelectedFarmEggs[name] = true; updateFarmRowVisual(name) end
    for name in pairs(FarmRows) do SelectedFarmEggs[name] = true; updateFarmRowVisual(name) end
    setFarmStatus("All types selected")
end)

ClearBtn.MouseButton1Click:Connect(function()
    table.clear(SelectedFarmEggs)
    for name in pairs(ImportantEggs) do SelectedFarmEggs[name] = true end
    for name in pairs(FarmRows) do updateFarmRowVisual(name) end
    setFarmStatus("Cleared • Important Eggs stay ON")
end)

RejoinBtn.MouseButton1Click:Connect(function()
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
end)

HopBtn.MouseButton1Click:Connect(function()
    showStatus("Server Hop: looking for new server...")
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end)

CopyJobBtn.MouseButton1Click:Connect(function()
    local jobId = game.JobId
    if setclipboard then
        setclipboard(jobId)
        showStatus("Job ID copied")
    else
        showStatus("Job ID: " .. tostring(jobId))
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
            if group and matches then groupHasMatch[group] = true end
        elseif entry and entry.Frame then
            entry.Frame.Visible = false
        end
    end
    for _, group in pairs(EggGroups) do
        group.GroupFrame.Visible = (query == "" or groupHasMatch[group] == true)
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
                    local distance = root and (root.Position - eggRoot.Position).Magnitude or 0
                    local group = EggGroups[model.Name]
                    local enabled = GlobalESPEnabled and (not group or group.TypeESPEnabled)
                    esp.Billboard.Enabled = enabled
                    if esp.Highlight then esp.Highlight.Enabled = enabled end
                    esp.Label.Text = root and (model.Name .. "\n[" .. math.floor(distance) .. " studs]") or model.Name
                    local entry = EggEntries[model]
                    if entry then
                        entry.Label.Text = root and (model.Name .. "  [" .. math.floor(distance) .. " studs]") or model.Name
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
    for model in pairs(ESPs) do destroyESP(model) end
    for _, connection in pairs(Connections) do
        if connection then pcall(function() connection:Disconnect() end) end
    end
    if ScreenGui then ScreenGui:Destroy() end
end
Close.MouseButton1Click:Connect(shutdown)

--==============================================================
-- START
--==============================================================

showStatus("Online  •  Watching for new Eggs", 2)
setFarmStatus("Idle")
print("[JHAYDEE HUB] Loaded – Twin side-drop + functional buttons")
