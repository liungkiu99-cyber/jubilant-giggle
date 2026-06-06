--[[
    HS HUB · TapTester  —  find the EXACT tap coordinate yourself
    discord.gg/5rpP6faZSJ

    Drag the RED crosshair onto a game button → it shows that button's X,Y.
    Then "TAP crosshair" sends a real VIM tap there. Or type X,Y and "TAP typed".
    Use this to find the coordinate that actually hits Mainkan — no guessing.
    Info shows ViewportSize + GuiInset so we can make it device-agnostic later.
]]

if shared.__HSHub_TapTester then pcall(function() shared.__HSHub_TapTester:Destroy() end) end

local Players    = game:GetService('Players')
local UIS        = game:GetService('UserInputService')
local GuiService = game:GetService('GuiService')
local RunService = game:GetService('RunService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

-- platform + VIM (KL method)
local IS_PC, IS_MOBILE = false, false
pcall(function()
    local p = UIS:GetPlatform()
    if p == Enum.Platform.Windows or p == Enum.Platform.OSX or p == Enum.Platform.UWP then IS_PC = true else IS_MOBILE = true end
end)
if not IS_PC and not IS_MOBILE then if UIS.TouchEnabled then IS_MOBILE = true else IS_PC = true end end
local VIM; pcall(function() VIM = game:GetService('VirtualInputManager') end)
local INSET = Vector2.new(0, 0); pcall(function() INSET = GuiService:GetGuiInset() end)

local logFn, hideUI, showUI

local function vimTap(x, y)
    if not VIM then return end
    if IS_PC then
        pcall(function() if VIM.SendMouseMoveEvent then VIM:SendMouseMoveEvent(x, y, game) end end)
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 1) end)
        task.wait(0.06)
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
    else
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 1) end)
        task.wait(0.05)
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
        pcall(function() VIM:SendTouchEvent(1, 0, x, y) end)
        task.wait(0.06)
        pcall(function() VIM:SendTouchEvent(1, 2, x, y) end)
    end
end

local function tapAt(x, y)
    logFn(('TAP @(%d,%d)'):format(math.floor(x), math.floor(y)))
    hideUI(); task.wait(0.1)
    vimTap(x, y)
    task.wait(0.1); showUI()
end

-- ═══ UI ══════════════════════════════════════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_TapTester_' .. math.random(1e5, 1e6)
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_TapTester = gui

-- the draggable crosshair
local cross = Instance.new('Frame', gui)
cross.Size = UDim2.new(0, 50, 0, 50); cross.Position = UDim2.new(0.5, -25, 0.5, -25)
cross.BackgroundColor3 = Color3.fromRGB(255, 60, 60); cross.BackgroundTransparency = 0.4
cross.BorderSizePixel = 0; cross.Active = true; cross.Draggable = true
Instance.new('UICorner', cross).CornerRadius = UDim.new(1, 0)
local dot = Instance.new('Frame', cross); dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.new(0.5, 0, 0.5, 0)
dot.Size = UDim2.new(0, 6, 0, 6); dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255); dot.BorderSizePixel = 0
Instance.new('UICorner', dot).CornerRadius = UDim.new(1, 0)

-- panel
local frame = Instance.new('Frame', gui); frame.Size = UDim2.new(0, 330, 0, 300); frame.Position = UDim2.new(0, 20, 0, 80)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10); Instance.new('UIStroke', frame).Color = Color3.fromRGB(255, 90, 90)
local hdr = Instance.new('Frame', frame); hdr.Size = UDim2.new(1, 0, 0, 36); hdr.BackgroundColor3 = Color3.fromRGB(200, 70, 70); hdr.BorderSizePixel = 0
Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 10)
local ttl = Instance.new('TextLabel', hdr); ttl.BackgroundTransparency = 1; ttl.Size = UDim2.new(1, -44, 1, 0); ttl.Position = UDim2.new(0, 12, 0, 0)
ttl.Font = Enum.Font.GothamBold; ttl.TextSize = 14; ttl.TextColor3 = Color3.fromRGB(255, 255, 255); ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = 'HS HUB · TapTester'
local xB = Instance.new('TextButton', hdr); xB.BackgroundTransparency = 1; xB.Size = UDim2.new(0, 34, 0, 34); xB.Position = UDim2.new(1, -38, 0, 1)
xB.Font = Enum.Font.GothamBold; xB.TextSize = 20; xB.TextColor3 = Color3.fromRGB(255, 255, 255); xB.Text = '×'
xB.MouseButton1Click:Connect(function() gui:Destroy(); shared.__HSHub_TapTester = nil end)

local coordLbl = Instance.new('TextLabel', frame); coordLbl.BackgroundTransparency = 1; coordLbl.Size = UDim2.new(1, -20, 0, 22); coordLbl.Position = UDim2.new(0, 12, 0, 42)
coordLbl.Font = Enum.Font.Code; coordLbl.TextSize = 13; coordLbl.TextColor3 = Color3.fromRGB(255, 200, 120); coordLbl.TextXAlignment = Enum.TextXAlignment.Left
coordLbl.Text = 'crosshair: (?,?)'

local function mkBox(ph, x)
    local b = Instance.new('TextBox', frame); b.Size = UDim2.new(0, 70, 0, 28); b.Position = UDim2.new(0, x, 0, 70)
    b.BackgroundColor3 = Color3.fromRGB(30, 34, 44); b.BorderSizePixel = 0; b.Font = Enum.Font.Code; b.TextSize = 14
    b.TextColor3 = Color3.fromRGB(230, 240, 230); b.PlaceholderText = ph; b.Text = ''; b.ClearTextOnFocus = false
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b
end
local boxX = mkBox('X', 12); local boxY = mkBox('Y', 88)
local function mkBtn(lbl, col, x, w, y)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, w, 0, 28); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = lbl
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b
end
local tapTyped = mkBtn('👆 TAP typed', Color3.fromRGB(70, 120, 180), 168, 150, 70)
local tapCross = mkBtn('👆 TAP crosshair', Color3.fromRGB(60, 160, 110), 12, 226, 104)
local infoLbl = Instance.new('TextLabel', frame); infoLbl.BackgroundTransparency = 1; infoLbl.Size = UDim2.new(1, -20, 0, 18); infoLbl.Position = UDim2.new(0, 12, 0, 138)
infoLbl.Font = Enum.Font.Code; infoLbl.TextSize = 11; infoLbl.TextColor3 = Color3.fromRGB(150, 200, 230); infoLbl.TextXAlignment = Enum.TextXAlignment.Left
pcall(function()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(0,0)
    infoLbl.Text = ('viewport %dx%d  inset.Y=%d  %s'):format(math.floor(vp.X), math.floor(vp.Y), math.floor(INSET.Y), IS_PC and 'PC' or 'MOBILE')
end)

local scroll = Instance.new('ScrollingFrame', frame); scroll.Size = UDim2.new(1, -18, 0, 130); scroll.Position = UDim2.new(0, 9, 0, 162)
scroll.BackgroundColor3 = Color3.fromRGB(11, 13, 19); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lo = Instance.new('UIListLayout', scroll); lo.Padding = UDim.new(0, 2); lo.SortOrder = Enum.SortOrder.LayoutOrder
local pd = Instance.new('UIPadding', scroll); pd.PaddingTop = UDim.new(0, 4); pd.PaddingLeft = UDim.new(0, 6)
logFn = function(t) local lb = Instance.new('TextLabel', scroll); lb.BackgroundTransparency = 1; lb.Size = UDim2.new(1, -12, 0, 16); lb.LayoutOrder = #scroll:GetChildren()
    lb.Font = Enum.Font.Code; lb.TextSize = 12; lb.TextColor3 = Color3.fromRGB(190, 215, 235); lb.TextXAlignment = Enum.TextXAlignment.Left; lb.TextTruncate = Enum.TextTruncate.AtEnd; lb.Text = t
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 18); scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset) end

hideUI = function() frame.Visible = false; cross.Visible = false end
showUI = function() frame.Visible = true; cross.Visible = true end

-- live crosshair coord (center of the red circle)
local function crossCenter()
    local ap, az = cross.AbsolutePosition, cross.AbsoluteSize
    return ap.X + az.X / 2, ap.Y + az.Y / 2
end
RunService.RenderStepped:Connect(function()
    local x, y = crossCenter()
    coordLbl.Text = ('crosshair: (%d, %d)  ← drag onto the button'):format(math.floor(x), math.floor(y))
end)

logFn('Drag the RED dot onto Mainkan, read its (x,y), then TAP crosshair.')
logFn('Or type X/Y and TAP typed. Tell me which coord hits Mainkan.')

tapCross.MouseButton1Click:Connect(function() task.spawn(function() local x, y = crossCenter(); tapAt(x, y) end) end)
tapTyped.MouseButton1Click:Connect(function() task.spawn(function()
    local x, y = tonumber(boxX.Text), tonumber(boxY.Text)
    if x and y then tapAt(x, y) else logFn('type valid X and Y first', true) end
end) end)
