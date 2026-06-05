--[[
    HS HUB · AutoSpawn v7  —  CLICKS the real buttons (full client flow)
    discord.gg/5rpP6faZSJ

    WHY v7: firing SpawnRemote only spawns the creature on the SERVER — your
    client stays in the lobby (so it starves & dies). The Mainkan/Play BUTTON
    does the full flow (remote + client load/camera). So we CLICK the button.

    SIMPLE FLOW (only what you need):
      1. "Read Slots"  → see your creatures + alive/dead
      2. "TEST: Play"  → selects an alive creature + clicks Mainkan  (← test this)
         → does your screen actually ENTER the game? tell me.
      3. once it works → turn AUTO on → it repeats by itself.
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

local AUTO = false
local logFn

-- ═══ click a GUI button the way the game expects ═════════════════
local function clickGui(btn)
    if not btn then return false end
    local did = false
    local function ev(name)
        local ok, sig = pcall(function() return btn[name] end)
        if ok and sig then
            if firesignal then pcall(function() firesignal(sig); did = true end) end
            if getconnections then
                pcall(function()
                    for _, c in ipairs(getconnections(sig)) do
                        if c.Fire then c:Fire(); did = true
                        elseif c.Function then pcall(c.Function); did = true end
                    end
                end)
            end
        end
    end
    ev('Activated'); ev('MouseButton1Click'); ev('MouseButton1Down'); ev('MouseButton1Up')
    return did
end

-- ═══ find the lobby GUI + buttons ════════════════════════════════
local function findSaveGui()
    for _, r in ipairs({ PG, gethui and gethui() or PG }) do
        local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end
    end
end

-- the big Mainkan/Play button (global, for the selected creature)
local function findPlayButton()
    local gui = findSaveGui(); if not gui then return nil end
    local fallback
    for _, d in ipairs(gui:GetDescendants()) do
        if d.Name == 'PlayButton' and (d:IsA('ImageButton') or d:IsA('TextButton')) then
            fallback = fallback or d
            local p = d.Parent
            while p and p ~= gui do
                if p.Name == 'ButtonsFrame' then return d end  -- the global one
                p = p.Parent
            end
        end
    end
    return fallback
end

-- read slots: SlotsFrame numeric children → {slot,name,dead, card}
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
                local nameL = cf:FindFirstChild('NameLabel')
                local deadL = cf:FindFirstChild('DeadLabel')
                local restB = cf:FindFirstChild('RestartButton')
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

-- ═══ THE PLAY ACTION: select a creature, click Mainkan ═══════════
local function selectCard(card)
    if not card then return end
    -- the card's own ViewButton selects/centers it; else click the card frame
    local vb = card:FindFirstChild('ViewButton')
    clickGui(vb or card)
end

local function playSlot(s)
    logFn('select ' .. s.slot .. ' (' .. s.name .. ')')
    selectCard(s.card)
    task.wait(0.7)
    local pb = findPlayButton()
    if not pb then logFn('✗ Mainkan/Play button NOT found', true); return false end
    logFn('click Mainkan...')
    local ok = clickGui(pb)
    if not ok then logFn('✗ click did nothing (no firesignal/getconnections?)', true); return false end
    -- wait for the client to actually enter the game
    local t = tick()
    repeat task.wait(0.5) until inGame() or tick() - t > 7
    if inGame() then logFn('✓ ENTERED GAME', false) else logFn('… still in lobby after click', true) end
    return inGame()
end

local function playAlive()
    local slots = readSlots()
    if #slots == 0 then logFn('no slots (lobby not loaded?)', true); return end
    local target
    for _, s in ipairs(slots) do if not s.dead then target = s; break end end
    if not target then logFn('all DEAD — need restart first (TODO)', true); return end
    playSlot(target)
end

-- ═══ AUTO loop (only runs when AUTO on; idle while in-game) ═══════
local busy = false
task.spawn(function()
    while true do
        task.wait(2)
        if AUTO and not busy and not inGame() then
            busy = true
            pcall(playAlive)
            task.wait(3)
            busy = false
        end
    end
end)

-- ═══ UI (minimal, clear) ═════════════════════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_AutoSpawn_' .. math.random(1e5, 1e6)
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_AutoSpawn = gui

local frame = Instance.new('Frame', gui); frame.Size = UDim2.new(0, 360, 0, 360); frame.Position = UDim2.new(0, 20, 0.5, -180)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10); Instance.new('UIStroke', frame).Color = Color3.fromRGB(140, 100, 220)
local hdr = Instance.new('Frame', frame); hdr.Size = UDim2.new(1, 0, 0, 40); hdr.BackgroundColor3 = Color3.fromRGB(110, 80, 190); hdr.BorderSizePixel = 0
Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 10)
local ttl = Instance.new('TextLabel', hdr); ttl.BackgroundTransparency = 1; ttl.Size = UDim2.new(1, -46, 1, 0); ttl.Position = UDim2.new(0, 12, 0, 0)
ttl.Font = Enum.Font.GothamBold; ttl.TextSize = 15; ttl.TextColor3 = Color3.fromRGB(245, 245, 250); ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = 'HS HUB · AutoSpawn v7'
local xB = Instance.new('TextButton', hdr); xB.BackgroundTransparency = 1; xB.Size = UDim2.new(0, 36, 0, 36); xB.Position = UDim2.new(1, -40, 0, 2)
xB.Font = Enum.Font.GothamBold; xB.TextSize = 22; xB.TextColor3 = Color3.fromRGB(255, 255, 255); xB.Text = '×'
xB.MouseButton1Click:Connect(function() AUTO = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)

local function mkBtn(lbl, col, x, w, y, h)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, w, 0, h or 34); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = lbl
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b
end

local readBtn = mkBtn('🔍 Read Slots', Color3.fromRGB(60, 130, 190), 12, 160, 50)
local playBtn = mkBtn('▶ TEST: Play', Color3.fromRGB(60, 160, 110), 184, 164, 50)
-- AUTO toggle
local autoBtn = mkBtn('AUTO: OFF', Color3.fromRGB(70, 74, 88), 12, 336, 92)
autoBtn.MouseButton1Click:Connect(function()
    AUTO = not AUTO
    autoBtn.BackgroundColor3 = AUTO and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88)
    autoBtn.Text = 'AUTO: ' .. (AUTO and 'ON (repeats by itself)' or 'OFF')
    logFn(AUTO and 'AUTO on' or 'AUTO off')
end)

local scroll = Instance.new('ScrollingFrame', frame); scroll.Size = UDim2.new(1, -18, 0, 210); scroll.Position = UDim2.new(0, 9, 0, 138)
scroll.BackgroundColor3 = Color3.fromRGB(11, 13, 19); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 100, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lo = Instance.new('UIListLayout', scroll); lo.Padding = UDim.new(0, 2); lo.SortOrder = Enum.SortOrder.LayoutOrder
local pd = Instance.new('UIPadding', scroll); pd.PaddingTop = UDim.new(0, 4); pd.PaddingLeft = UDim.new(0, 6)
logFn = function(txt, isErr)
    local lb = Instance.new('TextLabel', scroll); lb.BackgroundTransparency = 1; lb.Size = UDim2.new(1, -12, 0, 16); lb.LayoutOrder = #scroll:GetChildren()
    lb.Font = Enum.Font.Code; lb.TextSize = 12; lb.TextColor3 = isErr and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(190, 215, 235)
    lb.TextXAlignment = Enum.TextXAlignment.Left; lb.TextTruncate = Enum.TextTruncate.AtEnd; lb.Text = txt
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 18); scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end
logFn('v7: clicks the real Mainkan button (full client flow).')
logFn('1) Read Slots  2) TEST: Play  3) does screen ENTER game?')
logFn('firesignal=' .. tostring(firesignal ~= nil) .. '  getconnections=' .. tostring(getconnections ~= nil))

readBtn.MouseButton1Click:Connect(function()
    local slots = readSlots()
    logFn(('── slots: %d  in_game=%s  PlayBtn=%s ──'):format(#slots, tostring(inGame()), findPlayButton() and 'found' or 'MISSING'), Color3.fromRGB(120, 210, 255))
    for _, s in ipairs(slots) do
        logFn(('  %s %s %s'):format(s.slot, s.name, s.dead and 'DEAD' or 'ALIVE'), s.dead and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 230, 150))
    end
end)
playBtn.MouseButton1Click:Connect(function() task.spawn(playAlive) end)
