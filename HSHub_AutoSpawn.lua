--[[
    HS HUB · AutoSpawn v10  —  proven tap method (ported from user's King Legacy script)
    discord.gg/5rpP6faZSJ

    Tap method (KL-proven): event-fire first → if fail, VIM tap at button center.
    Mobile uses RAW AbsolutePosition (no inset), tries offsets {0,-inset,+inset} and
    VERIFIES (inGame changed) — learns the winning offset and reuses it. mobile click =
    SendMouseButtonEvent + SendTouchEvent. PC adds GuiInset.Y.

    FLOW: Read → Tap S1/S2/S3 (test slot switching) → TAP Mainkan (enters game?) → AUTO.
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players    = game:GetService('Players')
local Workspace  = game:GetService('Workspace')
local UIS        = game:GetService('UserInputService')
local GuiService = game:GetService('GuiService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

local AUTO = false
local logFn
local logLines = {}
local learnedOff = nil   -- the VIM Y offset that worked (mobile)
local panelGui = nil     -- our ScreenGui (hidden during taps so it never blocks them)

-- ═══ platform + input primitives (from King Legacy) ══════════════
local IS_MOBILE, IS_PC, IS_IOS, IS_POTASSIUM = false, false, false, false
pcall(function()
    local p = UIS:GetPlatform()
    if p == Enum.Platform.IOS then IS_IOS = true; IS_MOBILE = true
    elseif p == Enum.Platform.Android then IS_MOBILE = true
    elseif p == Enum.Platform.Windows or p == Enum.Platform.OSX or p == Enum.Platform.UWP then IS_PC = true end
end)
if not IS_PC and not IS_MOBILE then if UIS.TouchEnabled then IS_MOBILE = true else IS_PC = true end end
pcall(function() if getexecutorname and tostring(getexecutorname()):lower():find('potassium') then IS_POTASSIUM = true end end)
local VIM; pcall(function() VIM = game:GetService('VirtualInputManager') end)
local GUI_INSET = Vector2.new(0, 0); pcall(function() GUI_INSET = GuiService:GetGuiInset() end)

local function vimTouch(x, y) if not VIM then return end
    pcall(function() VIM:SendTouchEvent(1, 0, x, y) end); task.wait(0.06); pcall(function() VIM:SendTouchEvent(1, 2, x, y) end) end
local function vimMouse(x, y) if not VIM then return end
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 1) end); task.wait(0.05); pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end) end
local function potClick(x, y) pcall(function() mousemoveabs(x, y) end); task.wait(0.03); pcall(function() mouse1click() end) end
local function vimClick(x, y)
    if IS_POTASSIUM and IS_PC then potClick(x, y); return end
    if IS_PC then if VIM then vimMouse(x, y) elseif IS_POTASSIUM then potClick(x, y) end
    else vimMouse(x, y); task.wait(0.1); vimTouch(x, y) end
end
-- tap, hiding our panel so it never intercepts the touch (the panel covers part of screen)
local function clickHidden(x, y)
    local was = panelGui and panelGui.Enabled
    if panelGui then panelGui.Enabled = false; task.wait(0.05) end
    vimClick(x, y)
    if panelGui then task.wait(0.05); panelGui.Enabled = was end
end
local function fireGuiButton(btn)
    if not btn then return end
    pcall(function() if typeof(firesignal) == 'function' then firesignal(btn.MouseButton1Click); firesignal(btn.Activated); return end end)
    pcall(function() if typeof(fireclick) == 'function' then fireclick(btn) end end)
    pcall(function() if getconnections then for _, c in ipairs(getconnections(btn.MouseButton1Click)) do pcall(function() c:Fire() end) end end end)
end
local function centerOf(b) local ap, as = b.AbsolutePosition, b.AbsoluteSize; return ap.X + as.X / 2, ap.Y + as.Y / 2 end

-- ═══ lobby GUI + slots ═══════════════════════════════════════════
local function findSaveGui()
    for _, r in ipairs({ PG, gethui and gethui() or PG }) do local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end end
end
local function visibleChain(o)
    local n = o
    while n and n:IsA('GuiObject') do if not n.Visible then return false end n = n.Parent end
    return true
end
-- find the VISIBLE Mainkan/Play button (the green one on the centered card),
-- NOT the hidden global PlayButton. Match by text, require visible ancestor chain.
local PLAY_TEXTS = { ['Mainkan'] = true, ['MAINKAN'] = true, ['Play'] = true, ['PLAY'] = true }
-- collect ALL visible Mainkan/Play candidates {btn, text, x, y, parent}; log them
local function playCandidates(doLog)
    local out = {}
    for _, gname in ipairs({ 'SaveSelectionGui', 'SlotOverlayGui' }) do
        for _, r in ipairs({ PG, gethui and gethui() or PG }) do
            local g = r:FindFirstChild(gname)
            if g then
                for _, d in ipairs(g:GetDescendants()) do
                    if (d:IsA('TextButton') or d:IsA('ImageButton')) and visibleChain(d) then
                        -- does this button (or a small child) carry Mainkan/Play text?
                        local txt
                        if d:IsA('TextButton') and PLAY_TEXTS[d.Text] then txt = d.Text end
                        if not txt then for _, c in ipairs(d:GetDescendants()) do if c:IsA('TextLabel') and PLAY_TEXTS[c.Text] then txt = c.Text; break end end end
                        if txt then
                            local x, y = centerOf(d)
                            out[#out + 1] = { btn = d, text = txt, x = x, y = y, name = d.Name, parent = d.Parent and d.Parent.Name or '?' }
                        end
                    end
                end
            end
        end
    end
    if doLog then
        logFn('Mainkan candidates: ' .. #out, Color3.fromRGB(120, 210, 255))
        for _, c in ipairs(out) do logFn(('  %s "%s" @(%d,%d) parent=%s'):format(c.name, c.text, math.floor(c.x), math.floor(c.y), c.parent)) end
    end
    return out
end
local function findPlayButton()
    local c = playCandidates(false)
    if #c == 0 then return nil end
    -- the real green Mainkan sits at the BOTTOM of the centered card (largest Y);
    -- favorite/Simpan & hidden ones are higher. Pick the lowest-on-screen visible candidate.
    table.sort(c, function(a, b) return a.y > b.y end)
    return c[1].btn
end
local function readSlots()
    local out = {}; local gui = findSaveGui(); if not gui then return out end
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
local function slotByN(n) for _, s in ipairs(readSlots()) do if s.n == n then return s end end end
local function inGame()
    local chars = Workspace:FindFirstChild('Characters')
    return chars and (chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)) and true or false
end
local function lobbyReady()
    local pb = findPlayButton(); if not pb then return false end
    local ok = true; pcall(function() local n = pb; while n and n:IsA('GuiObject') do if not n.Visible then ok = false break end n = n.Parent end end)
    return ok
end

-- ═══ SINGLE tap at the proven offset (mobile=0, PC=+inset). NO multi-tap spam
--     (multi-tap during slow loading = double-spawn = blackscreen). ═══
local function tapButton(btn, label)
    if not btn then logFn('tap nil: ' .. tostring(label), true); return false end
    local rx, ry = centerOf(btn)
    local off = IS_PC and GUI_INSET.Y or (learnedOff or 0)
    logFn(('tap %s @(%d,%d) off=%d'):format(label, math.floor(rx), math.floor(ry + off), math.floor(off)))
    clickHidden(rx, ry + off)
    return true
end

-- ═══ PLAY: only ever play an ALIVE creature ══════════════════════
-- Mainkan only appears for the CENTERED + ALIVE creature (dead shows "Mulai ulang").
-- So we select an alive card, then require the Mainkan button to be visible before tapping.
local function playAlive()
    if inGame() then return true end
    local slots = readSlots()
    local aliveList = {}
    for _, s in ipairs(slots) do if not s.dead then aliveList[#aliveList + 1] = s end end
    if #aliveList == 0 then logFn('no ALIVE creature — all dead (restart TODO)', true); return false end
    for _, tgt in ipairs(aliveList) do
        logFn('select ' .. tgt.slot .. ' (' .. tgt.name .. ')')
        tapButton(tgt.card and (tgt.card:FindFirstChild('ViewButton') or tgt.card), 'select ' .. tgt.slot)
        task.wait(0.9)
        local pb = findPlayButton()      -- visible Mainkan = an ALIVE creature is centered
        if pb then
            tapButton(pb, 'Mainkan ' .. tgt.name)
            local t = tick(); repeat task.wait(0.5) until inGame() or tick() - t > 9   -- single tap, long wait (no respam)
            if inGame() then logFn('✓ ENTERED GAME (' .. tgt.name .. ')'); return true end
            logFn('✗ tapped Mainkan but no load in 9s (blackscreen?) — stopping, NOT respamming', true)
            return false
        else
            logFn('  ' .. tgt.slot .. ': Mainkan not visible (not centered/playable) → next', true)
        end
    end
    logFn('no alive creature became playable', true)
    return false
end

local busy = false
task.spawn(function()
    while true do task.wait(2)
        if AUTO and not busy and not inGame() and lobbyReady() then
            busy = true; task.wait(1.5 + math.random())
            if not inGame() and lobbyReady() then for a = 1, 2 do if playAlive() then break end task.wait(2) end end
            busy = false
        end
    end
end)

-- ═══ UI ══════════════════════════════════════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_AutoSpawn_' .. math.random(1e5, 1e6)
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_AutoSpawn = gui; panelGui = gui
local frame = Instance.new('Frame', gui); frame.Size = UDim2.new(0, 380, 0, 410); frame.Position = UDim2.new(0, 20, 0.5, -205)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10); Instance.new('UIStroke', frame).Color = Color3.fromRGB(140, 100, 220)
local hdr = Instance.new('Frame', frame); hdr.Size = UDim2.new(1, 0, 0, 38); hdr.BackgroundColor3 = Color3.fromRGB(110, 80, 190); hdr.BorderSizePixel = 0
Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 10)
local ttl = Instance.new('TextLabel', hdr); ttl.BackgroundTransparency = 1; ttl.Size = UDim2.new(1, -44, 1, 0); ttl.Position = UDim2.new(0, 12, 0, 0)
ttl.Font = Enum.Font.GothamBold; ttl.TextSize = 14; ttl.TextColor3 = Color3.fromRGB(245, 245, 250); ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = 'HS HUB · AutoSpawn v10'
local xB = Instance.new('TextButton', hdr); xB.BackgroundTransparency = 1; xB.Size = UDim2.new(0, 34, 0, 34); xB.Position = UDim2.new(1, -38, 0, 2)
xB.Font = Enum.Font.GothamBold; xB.TextSize = 20; xB.TextColor3 = Color3.fromRGB(255, 255, 255); xB.Text = '×'
xB.MouseButton1Click:Connect(function() AUTO = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)
local function mkBtn(lbl, col, x, w, y)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, w, 0, 28); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = lbl
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b
end
local readBtn = mkBtn('🔍 Read', Color3.fromRGB(60, 130, 190), 10, 110, 46)
local tapMain = mkBtn('👆 TAP Mainkan', Color3.fromRGB(170, 120, 60), 126, 130, 46)
local playBtn = mkBtn('▶ TEST Play', Color3.fromRGB(60, 160, 110), 262, 108, 46)
local s1 = mkBtn('Tap S1', Color3.fromRGB(70, 110, 160), 10, 84, 80)
local s2 = mkBtn('Tap S2', Color3.fromRGB(70, 110, 160), 100, 84, 80)
local s3 = mkBtn('Tap S3', Color3.fromRGB(70, 110, 160), 190, 84, 80)
local saveBtn = mkBtn('💾 Save Log', Color3.fromRGB(90, 100, 130), 280, 90, 80)
local autoBtn = mkBtn('AUTO: OFF', Color3.fromRGB(70, 74, 88), 10, 360, 114)
autoBtn.MouseButton1Click:Connect(function() AUTO = not AUTO
    autoBtn.BackgroundColor3 = AUTO and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88)
    autoBtn.Text = 'AUTO: ' .. (AUTO and 'ON (repeats itself)' or 'OFF'); logFn(AUTO and 'AUTO on' or 'AUTO off') end)

local scroll = Instance.new('ScrollingFrame', frame); scroll.Size = UDim2.new(1, -18, 0, 252); scroll.Position = UDim2.new(0, 9, 0, 150)
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
logFn(('v10. platform=%s VIM=%s inset.Y=%d'):format(IS_PC and 'PC' or 'MOBILE', tostring(VIM ~= nil), math.floor(GUI_INSET.Y)))
logFn('Test: Tap S1/S2/S3 (switch?) → TAP Mainkan (enter?).')

readBtn.MouseButton1Click:Connect(function()
    local slots = readSlots()
    logFn(('── slots:%d in_game=%s PlayBtn=%s ──'):format(#slots, tostring(inGame()), findPlayButton() and 'found' or 'MISSING'), Color3.fromRGB(120, 210, 255))
    for _, s in ipairs(slots) do logFn(('  %s %s %s'):format(s.slot, s.name, s.dead and 'DEAD' or 'ALIVE'), s.dead and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 230, 150)) end
end)
local function testSlot(n) local s = slotByN(n); if s and s.card then tapButton(s.card:FindFirstChild('ViewButton') or s.card, 'Slot' .. n .. '(' .. s.name .. ')') else logFn('slot ' .. n .. ' not found', true) end end
s1.MouseButton1Click:Connect(function() task.spawn(function() testSlot(1) end) end)
s2.MouseButton1Click:Connect(function() task.spawn(function() testSlot(2) end) end)
s3.MouseButton1Click:Connect(function() task.spawn(function() testSlot(3) end) end)
-- DIAGNOSTIC: dump every visible button in the lobby GUIs (name, center, size, text),
-- sorted bottom→top, so we can see which one is the real green Mainkan. NO tap.
tapMain.MouseButton1Click:Connect(function() task.spawn(function()
    local cands = {}
    for _, gname in ipairs({ 'SaveSelectionGui', 'SlotOverlayGui' }) do
        for _, r in ipairs({ PG, gethui and gethui() or PG }) do
            local g = r:FindFirstChild(gname)
            if g then for _, d in ipairs(g:GetDescendants()) do
                if (d:IsA('TextButton') or d:IsA('ImageButton')) and visibleChain(d) then
                    local az = d.AbsoluteSize
                    if az.X >= 30 and az.Y >= 20 and az.X <= 600 then   -- real tappable buttons only
                        local x, y = centerOf(d)
                        local txt = ''
                        if d:IsA('TextButton') and #d.Text > 0 then txt = d.Text end
                        if txt == '' then for _, c in ipairs(d:GetDescendants()) do if c:IsA('TextLabel') and #c.Text > 0 and #c.Text < 16 then txt = c.Text; break end end end
                        cands[#cands + 1] = { name = d.Name, x = x, y = y, w = az.X, h = az.Y, txt = txt, parent = d.Parent and d.Parent.Name or '?' }
                    end
                end
            end end
        end
    end
    table.sort(cands, function(a, b) return a.y > b.y end)
    logFn(('── visible buttons: %d (bottom→top) ──'):format(#cands), Color3.fromRGB(120, 210, 255))
    for i = 1, math.min(#cands, 18) do
        local c = cands[i]
        logFn(('  %s [%s] @(%d,%d) %dx%d p=%s'):format(c.name, c.txt, math.floor(c.x), math.floor(c.y), math.floor(c.w), math.floor(c.h), c.parent))
    end
    logFn('↑ screenshot this — which one is the green Mainkan?', Color3.fromRGB(255, 220, 140))
end) end)
playBtn.MouseButton1Click:Connect(function() task.spawn(playAlive) end)
saveBtn.MouseButton1Click:Connect(function()
    local txt = table.concat(logLines, '\n'); local s = false
    pcall(function() if writefile then writefile('HSHub_AutoSpawn_log.txt', txt); s = true end end)
    pcall(function() if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end end)
    logFn(s and 'saved log.txt + clipboard' or 'clipboard only')
end)
