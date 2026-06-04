--[[
═══════════════════════════════════════════════════════════════════════
        HS HUB · AutoSpawn v5  (ALL-IN-ONE, multi-method)
   Read slots + 3 spawn methods you can test individually + capture the
   game's REAL spawn call + autonomous loop. Stop guessing — see the truth.
                    discord.gg/5rpP6faZSJ

   SPAWN METHODS (test each manually, autonomous uses the one you pick):
     • CLICK  : click the slot's card then the Play button (full game flow,
                no arg guessing — closest to a real human press)
     • FIRE   : SpawnRemote:InvokeServer("Slot"..N)   (found remote)
     • REPLAY : re-send the EXACT call the game made when YOU played manually
                (this is what worked before). Play one creature once to learn it.
   When you press the game's own Mainkan, the panel prints the REAL captured
   arg (e.g. SpawnRemote("Slot1") or whatever it truly is) — that tells us
   if our slot id is right.

   Slots: SaveSelectionGui > SlotsFrame > "<N>"(numeric) > … > CreatureFrame
          NameLabel=creature, DeadLabel.Visible=DEAD.  "Default"=template(skip).
   Test on a THROWAWAY (CoS shadow-bans on a delay).
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players, Workspace, RS = game:GetService('Players'), game:GetService('Workspace'), game:GetService('ReplicatedStorage')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

local NAME_SPAWN, NAME_RESTART, NAME_INVIS = 'SpawnRemote', 'RestartSlotRemote', 'ActivateAbility'
local METHOD = 'CLICK'                 -- CLICK | FIRE | REPLAY  (autonomous spawn method)
local AUTO_RESPAWN, STEALTH, RUNNING = true, false, false
local function jit(a, b) return a + math.random() * (b - a) end
local logFn

-- ═══════════ remote capture (learn the EXACT call) ═══════════════
local captured, REPLAYING = {}, false
local function isRemote(o) return o and (o:IsA('RemoteEvent') or o:IsA('RemoteFunction')) end
local function searchPlaces(nm)
    local places = {}
    pcall(function() local r = LP:FindFirstChild('Remotes'); if r then places[#places+1] = r end end)
    places[#places+1] = RS; pcall(function() places[#places+1] = LP end)
    for _, p in ipairs(places) do local o = p:FindFirstChild(nm, true)
        if isRemote(o) then return o, (o:IsA('RemoteFunction') and 'InvokeServer' or 'FireServer') end end
end
pcall(function()
    if not hookfunction then return end
    local cc = checkcaller
    local function sample(cls) for _, d in ipairs(RS:GetDescendants()) do if d:IsA(cls) then return d end end end
    local se, sf = sample('RemoteEvent'), sample('RemoteFunction')
    local function cap(method) return function(self, ...)
        if not REPLAYING and not (cc and cc()) then
            local nm = self.Name
            if nm == NAME_SPAWN or nm == NAME_RESTART or nm == NAME_INVIS then
                local a = table.pack(...)
                captured[nm] = { obj = self, method = method, args = a }
                local s = {}; for i = 1, a.n do s[i] = tostring(a[i]) end
                if logFn then logFn('✓ LEARNED ' .. nm .. '(' .. table.concat(s, ',') .. ')', false) end
            end
        end
    end end
    if se then local of; of = hookfunction(se.FireServer, function(self, ...) cap('FireServer')(self, ...); return of(self, ...) end) end
    if sf then local oi; oi = hookfunction(sf.InvokeServer, function(self, ...) cap('InvokeServer')(self, ...); return oi(self, ...) end) end
end)

-- FIRE: found remote with our own args
local function fireRemote(nm, ...)
    local obj, method
    if captured[nm] then obj, method = captured[nm].obj, captured[nm].method else obj, method = searchPlaces(nm) end
    if not obj then logFn('✗ ' .. nm .. ' not found', true); return false end
    local a = table.pack(...); REPLAYING = true
    local ok, err = pcall(function()
        if method == 'InvokeServer' then return obj:InvokeServer(table.unpack(a, 1, a.n)) else obj:FireServer(table.unpack(a, 1, a.n)) end
    end); REPLAYING = false
    logFn((ok and '→ FIRE ' or '✗ FIRE ') .. nm .. '(' .. table.concat({ ... }, ',') .. ')' .. (ok and '' or (' ' .. tostring(err):sub(1, 35))), not ok)
    return ok
end
-- REPLAY: exact captured call
local function replayRemote(nm)
    local c = captured[nm]; if not c then logFn('✗ no capture for ' .. nm .. ' (play once)', true); return false end
    REPLAYING = true
    local ok = pcall(function()
        if c.method == 'InvokeServer' then return c.obj:InvokeServer(table.unpack(c.args, 1, c.args.n)) else c.obj:FireServer(table.unpack(c.args, 1, c.args.n)) end
    end); REPLAYING = false
    logFn(ok and ('→ REPLAY ' .. nm) or ('✗ REPLAY ' .. nm), not ok)
    return ok
end

-- ═══════════ CLICK a GUI button (firesignal / getconnections) ════
local function clickGui(btn)
    if not btn then return false end
    local fired = false
    local evs = {}
    for _, e in ipairs({ 'MouseButton1Click', 'Activated', 'MouseButton1Down', 'MouseButton1Up' }) do
        local ok, sig = pcall(function() return btn[e] end); if ok and sig then evs[#evs + 1] = sig end
    end
    for _, sig in ipairs(evs) do if firesignal then pcall(function() firesignal(sig); fired = true end) end end
    if getconnections then for _, sig in ipairs(evs) do pcall(function()
        for _, c in ipairs(getconnections(sig)) do
            if c.Fire then c:Fire(); fired = true elseif c.Function then pcall(c.Function); fired = true end
        end
    end) end end
    return fired
end

-- ═══════════ slots ═══════════════════════════════════════════════
local function findSaveGui()
    for _, r in ipairs({ PG, (gethui and gethui()) or PG }) do local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end end
end
local function globalPlayBtn()
    local gui = findSaveGui(); if not gui then return nil end
    for _, d in ipairs(gui:GetDescendants()) do
        if d.Name == 'PlayButton' and (d:IsA('ImageButton') or d:IsA('TextButton')) then return d end
    end
end
local function readSlots()
    local out = {}; local gui = findSaveGui(); if not gui then return out end
    local slotsFrame; for _, d in ipairs(gui:GetDescendants()) do if d.Name == 'SlotsFrame' then slotsFrame = d; break end end
    if not slotsFrame then return out end
    for _, sf in ipairs(slotsFrame:GetChildren()) do
        local n = tonumber(sf.Name)
        if n then
            local cf = sf:FindFirstChild('CreatureFrame', true)
            local nm, dead = '?', false
            if cf then
                local nameL, deadL, rb = cf:FindFirstChild('NameLabel'), cf:FindFirstChild('DeadLabel'), cf:FindFirstChild('RestartButton')
                if nameL then nm = nameL.Text end
                dead = (deadL and deadL.Visible == true) or (rb and rb.Visible == true) or false
            end
            out[#out + 1] = { slot = 'Slot' .. n, n = n, name = nm, dead = dead, cf = cf }
        end
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end
local function inGame()
    local chars = Workspace:FindFirstChild('Characters')
    return chars and (chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)) and true or false
end

-- ═══════════ spawn one slot via the chosen METHOD ════════════════
local function clickSpawn(s)
    -- select the card, then press the global Play button
    local sel = s.cf and (s.cf:FindFirstChild('ViewButton') or s.cf)
    logFn('CLICK select ' .. s.slot .. ' (' .. s.name .. ')')
    clickGui(sel); task.wait(0.6)
    local pb = globalPlayBtn()
    if pb then logFn('CLICK Play button'); clickGui(pb) else logFn('✗ Play button not found', true) end
end
local function spawnSlot(s)
    if METHOD == 'CLICK' then clickSpawn(s)
    elseif METHOD == 'REPLAY' then replayRemote(NAME_SPAWN)
    else fireRemote(NAME_SPAWN, s.slot) end
    task.wait(jit(2.5, 4.0))
    if STEALTH then fireRemote(NAME_INVIS, 'Invisibility') end
end
local function restartSlot(s)
    -- click the card's RestartButton if present, else fire
    local rb = s.cf and s.cf:FindFirstChild('RestartButton')
    if METHOD == 'CLICK' and rb then logFn('CLICK Restart ' .. s.slot); clickGui(s.cf:FindFirstChild('ViewButton') or s.cf); task.wait(0.4); clickGui(rb)
    else fireRemote(NAME_RESTART, s.slot, false) end
    task.wait(jit(1.0, 2.0))
end
local function pickAndSpawn()
    local slots = readSlots()
    if #slots == 0 then logFn('no slots read', true); return end
    local alive; for _, s in ipairs(slots) do if not s.dead then alive = s; break end end
    if alive then spawnSlot(alive)
    else local s = slots[1]; logFn('all DEAD → restart+spawn ' .. s.slot); restartSlot(s); spawnSlot(s) end
end

-- ═══════════ loop ════════════════════════════════════════════════
local busy = false
task.spawn(function()
    while true do task.wait(1.2)
        if RUNNING and not busy and not inGame() then
            busy = true; pcall(pickAndSpawn); task.wait(jit(2.5, 4.0)); busy = false
        end
    end
end)

-- ═══════════ UI ══════════════════════════════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_AutoSpawn_' .. math.random(1e5, 1e6 - 1)
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_AutoSpawn = gui
local frame = Instance.new('Frame', gui); frame.Size = UDim2.new(0, 410, 0, 476); frame.Position = UDim2.new(0, 20, 0.5, -238)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10); Instance.new('UIStroke', frame).Color = Color3.fromRGB(150, 110, 220)
local header = Instance.new('Frame', frame); header.Size = UDim2.new(1, 0, 0, 40); header.BackgroundColor3 = Color3.fromRGB(120, 90, 200); header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header); title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -50, 1, 0); title.Position = UDim2.new(0, 12, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(245, 245, 250); title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · AutoSpawn v5'
local closeBtn = Instance.new('TextButton', header); closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.new(0, 36, 0, 36); closeBtn.Position = UDim2.new(1, -40, 0, 2)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() RUNNING = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)
local function B(label, color, x, w, y)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, w, 0, 28); b.Position = UDim2.new(0, x, 0, y); b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label; Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b
end
local readBtn = B('🔍 Read Slots', Color3.fromRGB(70, 150, 200), 10, 130, 48)
local sClick = B('▶ Spawn CLICK', Color3.fromRGB(60, 140, 150), 146, 124, 48)
local sFire  = B('▶ Spawn FIRE',  Color3.fromRGB(70, 120, 180), 276, 124, 48)
local sReplay = B('▶ Spawn REPLAY', Color3.fromRGB(90, 110, 170), 10, 130, 82)
local restartBtn = B('↻ Restart', Color3.fromRGB(150, 110, 70), 146, 124, 82)
local invisBtn = B('👻 Invis', Color3.fromRGB(110, 90, 200), 276, 124, 82)
-- method selector
local methodBtn = B('Method: CLICK', Color3.fromRGB(80, 90, 110), 10, 130, 116)
methodBtn.MouseButton1Click:Connect(function()
    METHOD = (METHOD == 'CLICK' and 'FIRE') or (METHOD == 'FIRE' and 'REPLAY') or 'CLICK'
    methodBtn.Text = 'Method: ' .. METHOD
end)
local function T(label, x, init, cb)
    local b = B(label .. ':OFF', Color3.fromRGB(70, 74, 88), x, 124, 116); local s = init
    local function paint() b.BackgroundColor3 = s and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88); b.Text = label .. ':' .. (s and 'ON' or 'OFF') end
    paint(); b.MouseButton1Click:Connect(function() s = not s; paint(); cb(s) end)
end
T('AutoResp', 146, AUTO_RESPAWN, function(s) AUTO_RESPAWN = s end)
T('Stealth', 276, STEALTH, function(s) STEALTH = s end)
local startBtn = B('▶ START', Color3.fromRGB(60, 150, 100), 10, 195, 150); startBtn.Size = UDim2.new(0, 195, 0, 30)
local stopBtn  = B('■ STOP', Color3.fromRGB(160, 80, 80), 213, 187, 150); stopBtn.Size = UDim2.new(0, 187, 0, 30)

local scroll = Instance.new('ScrollingFrame', frame); scroll.Size = UDim2.new(1, -18, 0, 280); scroll.Position = UDim2.new(0, 9, 0, 188)
scroll.BackgroundColor3 = Color3.fromRGB(12, 14, 20); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 110, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lay = Instance.new('UIListLayout', scroll); lay.Padding = UDim.new(0, 2); lay.SortOrder = Enum.SortOrder.LayoutOrder
local lpd = Instance.new('UIPadding', scroll); lpd.PaddingTop = UDim.new(0, 4); lpd.PaddingLeft = UDim.new(0, 6)
logFn = function(text, isErr)
    local lbl = Instance.new('TextLabel', scroll); lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -12, 0, 15); lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 11; lbl.TextColor3 = isErr and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(185, 215, 235)
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 17); scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end
logFn('v5. Tap a creature\'s Mainkan ONCE → I print its REAL arg.')
logFn('Then test Spawn CLICK / FIRE / REPLAY to see which works.')

readBtn.MouseButton1Click:Connect(function()
    local slots = readSlots()
    logFn(('── slots (in_game=%s, %d) play_btn=%s ──'):format(tostring(inGame()), #slots, globalPlayBtn() and 'ok' or 'MISSING'), Color3.fromRGB(120, 220, 255))
    for _, s in ipairs(slots) do logFn(('  %s %s %s'):format(s.slot, s.name, s.dead and 'DEAD' or 'ALIVE'), s.dead and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 230, 150)) end
end)
local function manualSpawn(m) local old = METHOD; METHOD = m; task.spawn(function() pcall(pickAndSpawn); METHOD = old end) end
sClick.MouseButton1Click:Connect(function() manualSpawn('CLICK') end)
sFire.MouseButton1Click:Connect(function() manualSpawn('FIRE') end)
sReplay.MouseButton1Click:Connect(function() replayRemote(NAME_SPAWN) end)
restartBtn.MouseButton1Click:Connect(function() local sl = readSlots(); if sl[1] then restartSlot(sl[1]) end end)
invisBtn.MouseButton1Click:Connect(function() fireRemote(NAME_INVIS, 'Invisibility') end)
startBtn.MouseButton1Click:Connect(function() if RUNNING then return end RUNNING = true; busy = false; logFn('STARTED method=' .. METHOD .. ' respawn=' .. tostring(AUTO_RESPAWN)) end)
stopBtn.MouseButton1Click:Connect(function() RUNNING = false; busy = false; logFn('STOPPED.') end)
