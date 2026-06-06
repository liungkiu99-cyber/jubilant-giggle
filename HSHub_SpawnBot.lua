--[[
    HS HUB · SpawnBot  —  autonomous lobby spawn (device-agnostic taps)
    discord.gg/5rpP6faZSJ

    TAP FORMULA (device-agnostic, confirmed via TapTester):
        screen = button.AbsolutePosition + button.AbsoluteSize/2 + GuiService:GetGuiInset()
    AbsolutePosition is GUI-space (below topbar); VIM taps raw screen-space; the
    difference is exactly the GuiInset (queried per-device, incl. notch) → works on
    ANY device with no manual tuning. Small buttons (Mainkan ~60x21) need this; big
    cards tolerated the missing inset before.

    LOGIC: at the lobby, find an ALIVE slot → center it → tap Mainkan. If ALL dead →
    center a dead one → tap Restart (Mulai ulang) → tap Mainkan. While in-game: idle.
    No firesignal (genuine VIM input only, so anti-cheat doesn't flag a "fake" click).
]]

if shared.__HSHub_SpawnBot then pcall(function() shared.__HSHub_SpawnBot:Destroy() end) end

local Players, Workspace = game:GetService('Players'), game:GetService('Workspace')
local UIS, GuiService = game:GetService('UserInputService'), game:GetService('GuiService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

local AUTO, RUNNING = false, false
local logFn, panelGui

-- platform + VIM
local IS_PC = false
pcall(function() local p = UIS:GetPlatform()
    if p == Enum.Platform.Windows or p == Enum.Platform.OSX or p == Enum.Platform.UWP then IS_PC = true end end)
if not IS_PC and not UIS.TouchEnabled then IS_PC = true end
local VIM; pcall(function() VIM = game:GetService('VirtualInputManager') end)
local function inset() local i = GuiService:GetGuiInset(); return i or Vector2.new(0, 0) end

-- ═══ DEVICE-AGNOSTIC TAP: AbsolutePosition + size/2 + GuiInset ════
local function vimTap(x, y)
    if not VIM then return end
    pcall(function() if VIM.SendMouseMoveEvent then VIM:SendMouseMoveEvent(x, y, game) end end)
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 1) end)
    task.wait(0.06)
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
    if not IS_PC then
        pcall(function() VIM:SendTouchEvent(1, 0, x, y) end)
        task.wait(0.06)
        pcall(function() VIM:SendTouchEvent(1, 2, x, y) end)
    end
end
local function tapButton(btn, label)
    if not btn then logFn('tap nil: ' .. tostring(label), true); return false end
    local ap, az = btn.AbsolutePosition, btn.AbsoluteSize
    local ins = inset()
    local x = ap.X + az.X / 2 + ins.X
    local y = ap.Y + az.Y / 2 + ins.Y          -- ★ +GuiInset = the device-agnostic fix
    logFn(('tap %s @(%d,%d)'):format(tostring(label), math.floor(x), math.floor(y)))
    local was = panelGui and panelGui.Enabled
    if panelGui then panelGui.Enabled = false; task.wait(0.08) end
    vimTap(x, y)
    if panelGui then task.wait(0.08); panelGui.Enabled = was end
    return true
end

-- ═══ lobby lookups ═══════════════════════════════════════════════
local function findSaveGui()
    for _, r in ipairs({ PG, gethui and gethui() or PG }) do local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end end
end
local function visibleChain(o) local n = o; while n and n:IsA('GuiObject') do if not n.Visible then return false end n = n.Parent end; return true end
local function findNamed(name)   -- visible button with this exact Name, small (real button)
    local g = findSaveGui(); if not g then return nil end
    for _, d in ipairs(g:GetDescendants()) do
        if d.Name == name and (d:IsA('ImageButton') or d:IsA('TextButton')) and visibleChain(d) and d.AbsoluteSize.X < 200 then return d end
    end
end
local function findPlayButton() return findNamed('PlayButton') end
local function findRestartButton() return findNamed('RestartButton') end
local function readSlots()
    local out = {}; local g = findSaveGui(); if not g then return out end
    local sf; for _, d in ipairs(g:GetDescendants()) do if d.Name == 'SlotsFrame' then sf = d; break end end
    if not sf then return out end
    for _, c in ipairs(sf:GetChildren()) do
        local n = tonumber(c.Name)
        if n then
            local cf = c:FindFirstChild('CreatureFrame', true)
            local nm, dead = '?', false
            if cf then
                local nL, dL, rB = cf:FindFirstChild('NameLabel'), cf:FindFirstChild('DeadLabel'), cf:FindFirstChild('RestartButton')
                if nL then nm = nL.Text end
                dead = (dL and dL.Visible == true) or (rB and rB.Visible == true) or false
            end
            out[#out + 1] = { slot = 'Slot' .. n, n = n, name = nm, dead = dead, card = cf }
        end
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end
local function inGame()
    local ch = Workspace:FindFirstChild('Characters')
    return ch and (ch:FindFirstChild(LP.Name) or ch:FindFirstChild(LP.DisplayName)) and true or false
end
local function centerCard(s) if s and s.card then tapButton(s.card:FindFirstChild('ViewButton') or s.card, 'center ' .. s.slot) end end

-- ═══ PLAY / RESTART ══════════════════════════════════════════════
local function waitInGame(sec) local t = tick(); repeat task.wait(0.5) until inGame() or tick() - t > sec; return inGame() end
local function playAlive()
    if inGame() then return true end
    local slots = readSlots()
    if #slots == 0 then logFn('no slots (lobby loaded?)', true); return false end
    -- 1) try alive creatures
    for _, s in ipairs(slots) do
        if not s.dead then
            logFn('ALIVE ' .. s.slot .. ' ' .. s.name)
            centerCard(s); task.wait(0.8)
            local pb = findPlayButton()
            if pb then
                tapButton(pb, 'Mainkan')
                if waitInGame(9) then logFn('✓ ENTERED (' .. s.name .. ')'); return true end
                logFn('✗ no load after Mainkan', true); return false
            else logFn('  no Mainkan after centering ' .. s.slot, true) end
        end
    end
    -- 2) all dead → restart the first slot then play
    local s = slots[1]
    logFn('all DEAD → restart ' .. s.slot .. ' ' .. s.name)
    centerCard(s); task.wait(0.8)
    local rb = findRestartButton()
    if not rb then logFn('  no Restart button visible', true); return false end
    tapButton(rb, 'Restart'); task.wait(2.0)
    local pb = findPlayButton()
    if pb then tapButton(pb, 'Mainkan'); if waitInGame(9) then logFn('✓ ENTERED after restart'); return true end end
    logFn('✗ restart+play failed', true); return false
end

local busy = false
task.spawn(function()
    while true do task.wait(1.5)
        if AUTO and not busy and not inGame() and findPlayButton() then
            busy = true; task.wait(1.2 + math.random())
            if not inGame() then pcall(playAlive) end
            task.wait(2); busy = false
        end
    end
end)

-- ═══ UI ══════════════════════════════════════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_SpawnBot_' .. math.random(1e5, 1e6)
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_SpawnBot = gui; panelGui = gui
local frame = Instance.new('Frame', gui); frame.Size = UDim2.new(0, 360, 0, 360); frame.Position = UDim2.new(0, 20, 0.5, -180)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10); Instance.new('UIStroke', frame).Color = Color3.fromRGB(90, 200, 140)
local hdr = Instance.new('Frame', frame); hdr.Size = UDim2.new(1, 0, 0, 38); hdr.BackgroundColor3 = Color3.fromRGB(60, 170, 110); hdr.BorderSizePixel = 0
Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 10)
local ttl = Instance.new('TextLabel', hdr); ttl.BackgroundTransparency = 1; ttl.Size = UDim2.new(1, -44, 1, 0); ttl.Position = UDim2.new(0, 12, 0, 0)
ttl.Font = Enum.Font.GothamBold; ttl.TextSize = 14; ttl.TextColor3 = Color3.fromRGB(245, 245, 250); ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = 'HS HUB · SpawnBot'
local xB = Instance.new('TextButton', hdr); xB.BackgroundTransparency = 1; xB.Size = UDim2.new(0, 34, 0, 34); xB.Position = UDim2.new(1, -38, 0, 2)
xB.Font = Enum.Font.GothamBold; xB.TextSize = 20; xB.TextColor3 = Color3.fromRGB(255, 255, 255); xB.Text = '×'
xB.MouseButton1Click:Connect(function() AUTO = false; gui:Destroy(); shared.__HSHub_SpawnBot = nil end)
local function mkBtn(lbl, col, x, w, y)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, w, 0, 28); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = lbl
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b
end
local readBtn = mkBtn('🔍 Read', Color3.fromRGB(60, 130, 190), 12, 104, 46)
local playBtn = mkBtn('▶ TEST Play', Color3.fromRGB(60, 160, 110), 124, 110, 46)
local restBtn = mkBtn('↻ Restart', Color3.fromRGB(150, 110, 70), 242, 106, 46)
local autoBtn = mkBtn('AUTO: OFF', Color3.fromRGB(70, 74, 88), 12, 336, 80)
autoBtn.MouseButton1Click:Connect(function() AUTO = not AUTO
    autoBtn.BackgroundColor3 = AUTO and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88)
    autoBtn.Text = 'AUTO: ' .. (AUTO and 'ON (repeats itself)' or 'OFF'); logFn(AUTO and 'AUTO on' or 'AUTO off') end)
local scroll = Instance.new('ScrollingFrame', frame); scroll.Size = UDim2.new(1, -18, 0, 232); scroll.Position = UDim2.new(0, 9, 0, 120)
scroll.BackgroundColor3 = Color3.fromRGB(11, 13, 19); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lo = Instance.new('UIListLayout', scroll); lo.Padding = UDim.new(0, 2); lo.SortOrder = Enum.SortOrder.LayoutOrder
local pdg = Instance.new('UIPadding', scroll); pdg.PaddingTop = UDim.new(0, 4); pdg.PaddingLeft = UDim.new(0, 6)
logFn = function(t, e) local lb = Instance.new('TextLabel', scroll); lb.BackgroundTransparency = 1; lb.Size = UDim2.new(1, -12, 0, 16); lb.LayoutOrder = #scroll:GetChildren()
    lb.Font = Enum.Font.Code; lb.TextSize = 12; lb.TextColor3 = e and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(190, 215, 235); lb.TextXAlignment = Enum.TextXAlignment.Left; lb.TextTruncate = Enum.TextTruncate.AtEnd; lb.Text = t
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 18); scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset) end
local _i = inset()
logFn(('SpawnBot. inset=(%d,%d) %s'):format(math.floor(_i.X), math.floor(_i.Y), IS_PC and 'PC' or 'MOBILE'))
logFn('Read → TEST Play. Tap coord = AbsolutePos + GuiInset (all-device).')

readBtn.MouseButton1Click:Connect(function()
    local s = readSlots()
    logFn(('── slots:%d in_game=%s Play=%s Restart=%s ──'):format(#s, tostring(inGame()), findPlayButton() and 'Y' or 'n', findRestartButton() and 'Y' or 'n'), Color3.fromRGB(120, 210, 255))
    for _, x in ipairs(s) do logFn(('  %s %s %s'):format(x.slot, x.name, x.dead and 'DEAD' or 'ALIVE'), x.dead) end
end)
playBtn.MouseButton1Click:Connect(function() task.spawn(playAlive) end)
restBtn.MouseButton1Click:Connect(function() task.spawn(function()
    local rb = findRestartButton(); if rb then tapButton(rb, 'Restart') else logFn('no Restart visible (center a DEAD creature)', true) end
end) end)
