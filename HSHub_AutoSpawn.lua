--[[
    HS HUB · AutoSpawn v8  —  REAL tap via VirtualInputManager
    discord.gg/5rpP6faZSJ

    v7 finding: firesignal/getconnections did NOT actually press Mainkan (the
    "ENTERED GAME" was the user's own finger). CoS routes input through a central
    handler, so only a REAL input at the button's coordinates works.
    v8 uses VirtualInputManager to send a real mouse+touch tap at the button center.

    FLOW:
      Read Slots → see creatures.   TAP Mainkan → real-tap just the Play button
      (test). TEST: Play → select alive card + tap Mainkan. AUTO → repeats itself.
      Save Log → writes HSHub_AutoSpawn_log.txt + clipboard.
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players    = game:GetService('Players')
local Workspace  = game:GetService('Workspace')
local VIM        = game:GetService('VirtualInputManager')
local GuiService = game:GetService('GuiService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

local AUTO = false
local logFn
local logLines = {}

-- ═══ REAL TAP at a GUI's screen center (mouse + touch) ═══════════
local function centerOf(gobj)
    local ap, az = gobj.AbsolutePosition, gobj.AbsoluteSize
    return ap.X + az.X / 2, ap.Y + az.Y / 2
end
local function tap(gobj, label)
    if not gobj then logFn('tap: nil ' .. tostring(label), true); return false end
    local x, y = centerOf(gobj)
    logFn(('tap %s @(%d,%d)'):format(tostring(label or gobj.Name), x, y))
    local ok = pcall(function()
        -- mouse
        if VIM.SendMouseMoveEvent then VIM:SendMouseMoveEvent(x, y, game) end
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.06)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
    -- touch backup (mobile)
    pcall(function()
        if VIM.SendTouchEvent then
            VIM:SendTouchEvent(1, 0, x, y); task.wait(0.06); VIM:SendTouchEvent(1, 3, x, y)
        end
    end)
    return ok
end

-- ═══ lobby GUI + buttons ═════════════════════════════════════════
local function findSaveGui()
    for _, r in ipairs({ PG, gethui and gethui() or PG }) do
        local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end
    end
end
local function findPlayButton()
    local gui = findSaveGui(); if not gui then return nil end
    local fb
    for _, d in ipairs(gui:GetDescendants()) do
        if d.Name == 'PlayButton' and (d:IsA('ImageButton') or d:IsA('TextButton')) then
            fb = fb or d
            local p = d.Parent
            while p and p ~= gui do if p.Name == 'ButtonsFrame' then return d end p = p.Parent end
        end
    end
    return fb
end
local function readSlots()
    local out = {}
    local gui = findSaveGui(); if not gui then return out end
    local sf; for _, d in ipairs(gui:GetDescendants()) do if d.Name == 'SlotsFrame' then sf = d; break end end
    if not sf then return out end
    for _, child in ipairs(sf:GetChildren()) do
        local n = tonumber(child.Name)
        if n then
            local cf = child:FindFirstChild('CreatureFrame', true)
            local nm, dead = '?', false
            if cf then
                local nameL, deadL, restB = cf:FindFirstChild('NameLabel'), cf:FindFirstChild('DeadLabel'), cf:FindFirstChild('RestartButton')
                if nameL then nm = nameL.Text end
                dead = (deadL and deadL.Visible == true) or (restB and restB.Visible == true) or false
            end
            out[#out + 1] = { slot = 'Slot' .. n, n = n, name = nm, dead = dead, card = cf }
        end
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end
local function inGame()
    local chars = Workspace:FindFirstChild('Characters')
    return chars and (chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)) and true or false
end
local function lobbyReady()
    local pb = findPlayButton(); if not pb then return false end
    local ok = true
    pcall(function() local n = pb; while n and n:IsA('GuiObject') do if not n.Visible then ok = false; break end n = n.Parent end end)
    return ok
end

-- ═══ PLAY ════════════════════════════════════════════════════════
local function playSlot(s)
    -- select the card (tap it), then tap the global Mainkan
    if s.card then
        local sel = s.card:FindFirstChild('ViewButton') or s.card
        tap(sel, 'card ' .. s.slot); task.wait(0.7)
    end
    local pb = findPlayButton()
    if not pb then logFn('✗ Mainkan not found', true); return false end
    tap(pb, 'Mainkan')
    local t = tick(); repeat task.wait(0.5) until inGame() or tick() - t > 7
    if inGame() then logFn('✓ ENTERED GAME', false) else logFn('… still in lobby', true) end
    return inGame()
end
local function playAlive()
    local slots = readSlots()
    if #slots == 0 then logFn('no slots', true); return false end
    local tgt; for _, s in ipairs(slots) do if not s.dead then tgt = s; break end end
    if not tgt then logFn('all DEAD (restart TODO)', true); return false end
    return playSlot(tgt)
end

-- ═══ AUTO loop (wait for stable lobby, retry) ════════════════════
local busy = false
task.spawn(function()
    while true do
        task.wait(2)
        if AUTO and not busy and not inGame() and lobbyReady() then
            busy = true
            task.wait(1.5 + math.random())            -- settle after death->lobby
            if not inGame() and lobbyReady() then
                for attempt = 1, 3 do
                    if playAlive() then break end
                    task.wait(2)
                end
            end
            busy = false
        end
    end
end)

-- ═══ UI ══════════════════════════════════════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_AutoSpawn_' .. math.random(1e5, 1e6)
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_AutoSpawn = gui
local frame = Instance.new('Frame', gui); frame.Size = UDim2.new(0, 370, 0, 390); frame.Position = UDim2.new(0, 20, 0.5, -195)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10); Instance.new('UIStroke', frame).Color = Color3.fromRGB(140, 100, 220)
local hdr = Instance.new('Frame', frame); hdr.Size = UDim2.new(1, 0, 0, 40); hdr.BackgroundColor3 = Color3.fromRGB(110, 80, 190); hdr.BorderSizePixel = 0
Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 10)
local ttl = Instance.new('TextLabel', hdr); ttl.BackgroundTransparency = 1; ttl.Size = UDim2.new(1, -46, 1, 0); ttl.Position = UDim2.new(0, 12, 0, 0)
ttl.Font = Enum.Font.GothamBold; ttl.TextSize = 15; ttl.TextColor3 = Color3.fromRGB(245, 245, 250); ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = 'HS HUB · AutoSpawn v8'
local xB = Instance.new('TextButton', hdr); xB.BackgroundTransparency = 1; xB.Size = UDim2.new(0, 36, 0, 36); xB.Position = UDim2.new(1, -40, 0, 2)
xB.Font = Enum.Font.GothamBold; xB.TextSize = 22; xB.TextColor3 = Color3.fromRGB(255, 255, 255); xB.Text = '×'
xB.MouseButton1Click:Connect(function() AUTO = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)
local function mkBtn(lbl, col, x, w, y, h)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, w, 0, h or 30); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = lbl
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b
end
local readBtn = mkBtn('🔍 Read Slots', Color3.fromRGB(60, 130, 190), 12, 168, 50)
local tapBtn  = mkBtn('👆 TAP Mainkan', Color3.fromRGB(170, 120, 60), 190, 168, 50)
local playBtn = mkBtn('▶ TEST: Play', Color3.fromRGB(60, 160, 110), 12, 168, 86)
local saveBtn = mkBtn('💾 Save Log', Color3.fromRGB(90, 100, 130), 190, 168, 86)
local autoBtn = mkBtn('AUTO: OFF', Color3.fromRGB(70, 74, 88), 12, 346, 122)
autoBtn.MouseButton1Click:Connect(function()
    AUTO = not AUTO; autoBtn.BackgroundColor3 = AUTO and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88)
    autoBtn.Text = 'AUTO: ' .. (AUTO and 'ON (repeats itself)' or 'OFF'); logFn(AUTO and 'AUTO on' or 'AUTO off')
end)
local scroll = Instance.new('ScrollingFrame', frame); scroll.Size = UDim2.new(1, -18, 0, 222); scroll.Position = UDim2.new(0, 9, 0, 160)
scroll.BackgroundColor3 = Color3.fromRGB(11, 13, 19); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 100, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lo = Instance.new('UIListLayout', scroll); lo.Padding = UDim.new(0, 2); lo.SortOrder = Enum.SortOrder.LayoutOrder
local pd = Instance.new('UIPadding', scroll); pd.PaddingTop = UDim.new(0, 4); pd.PaddingLeft = UDim.new(0, 6)
logFn = function(txt, isErr)
    logLines[#logLines + 1] = txt
    local lb = Instance.new('TextLabel', scroll); lb.BackgroundTransparency = 1; lb.Size = UDim2.new(1, -12, 0, 16); lb.LayoutOrder = #scroll:GetChildren()
    lb.Font = Enum.Font.Code; lb.TextSize = 12; lb.TextColor3 = isErr and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(190, 215, 235)
    lb.TextXAlignment = Enum.TextXAlignment.Left; lb.TextTruncate = Enum.TextTruncate.AtEnd; lb.Text = txt
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 18); scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end
logFn('v8: REAL tap via VirtualInputManager.')
logFn('VIM mouse=' .. tostring(VIM.SendMouseButtonEvent ~= nil) .. ' touch=' .. tostring(VIM.SendTouchEvent ~= nil))
logFn('1) Read Slots  2) TAP Mainkan (test)  3) AUTO')

readBtn.MouseButton1Click:Connect(function()
    local slots = readSlots()
    logFn(('── slots:%d in_game=%s PlayBtn=%s ──'):format(#slots, tostring(inGame()), findPlayButton() and 'found' or 'MISSING'), Color3.fromRGB(120, 210, 255))
    for _, s in ipairs(slots) do logFn(('  %s %s %s'):format(s.slot, s.name, s.dead and 'DEAD' or 'ALIVE'), s.dead and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 230, 150)) end
end)
tapBtn.MouseButton1Click:Connect(function() task.spawn(function()
    local pb = findPlayButton(); if pb then tap(pb, 'Mainkan'); task.wait(2); logFn(inGame() and '✓ ENTERED GAME' or '… still lobby', not inGame()) else logFn('Mainkan MISSING', true) end
end) end)
playBtn.MouseButton1Click:Connect(function() task.spawn(playAlive) end)
saveBtn.MouseButton1Click:Connect(function()
    local txt = table.concat(logLines, '\n')
    local s = false
    pcall(function() if writefile then writefile('HSHub_AutoSpawn_log.txt', txt); s = true end end)
    pcall(function() if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end end)
    logFn(s and 'saved HSHub_AutoSpawn_log.txt + clipboard' or 'clipboard only', false)
end)
