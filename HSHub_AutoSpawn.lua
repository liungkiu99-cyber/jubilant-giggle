--[[
═══════════════════════════════════════════════════════════════════════
            HS HUB · AutoSpawn v2  (capture → REPLAY)
     Autonomous spawn / auto-restart-on-death / stealth(invis)
                    discord.gg/5rpP6faZSJ

    WHY v2: calling a remote we found BY NAME (FindFirstChild) can hit the
    WRONG instance / wrong context, and a guessed "Slot1" arg may not match
    your creature — that's the "works 1 in 50-100" trap. v2 instead RECORDS
    the EXACT remote object + EXACT args the GAME itself sends when YOU press
    the button once, then REPLAYS that identical call. No guessing.

    HOW TO USE (learn once, then auto):
      1. Open the creature/slot menu, paste this, the panel appears.
      2. LEARN by doing each action MANUALLY one time — the tool grabs it:
           • press "Mainkan" (Play) on your farm creature  -> learns SPAWN
           • let it die, press "Mulai ulang" (Restart)      -> learns RESTART
           • activate the invisible skill                   -> learns INVIS
         The "Learned" row turns ✓ as each is captured.
      3. Test: tap "Replay Spawn / Restart / Invis" — must reproduce the action.
      4. Auto: Auto-Respawn ON (+ Stealth if wanted) -> Start. On death it
         replays RESTART then SPAWN (then INVIS) — the exact calls you taught.

    Learn RESTART and SPAWN on the SAME creature/slot (the one you farm).
    Test on a THROWAWAY first — CoS shadow-bans on a DELAY.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

-- the remote NAMES we care about (from ActionSpy). We still REPLAY the exact
-- captured object, not a by-name lookup — these are just for labelling.
local NAME_SPAWN   = 'SpawnRemote'
local NAME_RESTART = 'RestartSlotRemote'
local NAME_INVIS   = 'ActivateAbility'

local AUTO_RESPAWN = true
local STEALTH      = false
local RUNNING      = false

local function jit(a, b) return a + math.random() * (b - a) end
local DEATH_REACT = {0.4, 1.2}
local RESTART_GAP = {1.0, 2.0}
local SPAWN_SETTLE= {0.8, 1.6}

-- ═════════════ CAPTURE STORE ═════════════════════════════════════
-- captured[name] = { obj=<remote Instance>, method='FireServer'/'InvokeServer', args=table.pack(...), argstr }
local captured = {}
local logFn                      -- set by UI
local REPLAYING = false

local function dumpArgs(a)
    local p = {}
    for i = 1, math.min(a.n or 0, 6) do
        local v = a[i]; local t = typeof and typeof(v) or type(v)
        if t == 'string' then p[i] = '"'..v..'"'
        elseif t == 'Instance' then p[i] = '<'..v.ClassName..' '..v.Name..'>'
        else p[i] = tostring(v) end
    end
    return table.concat(p, ', ')
end

-- ═════════════ CHARACTER / HEALTH ════════════════════════════════
local function getChar()
    local c = LP.Character
    if c and c:FindFirstChild('Data') then return c end
    local chars = Workspace:FindFirstChild('Characters')
    if chars then
        local b = chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)
        if b and b:FindFirstChild('Data') then return b end
        for _, ch in ipairs(chars:GetChildren()) do
            if ch:FindFirstChild('Data') and (ch.Name == LP.Name or ch.Name == LP.DisplayName) then return ch end
        end
    end
    return c
end
local function getHealth()
    local c = getChar(); if not c then return nil end
    local d = c:FindFirstChild('Data'); if not d then return nil end
    return tonumber(d:GetAttribute('h'))
end
local function isAlive() local h = getHealth(); return h ~= nil and h > 0 end

-- ═════════════ HOOKS (capture the game's own calls) ══════════════
local hookStatus = 'init'
local learnEvent
pcall(function()
    if not hookfunction then hookStatus = 'NO hookfunction'; return end
    local cc = checkcaller
    local function sample(cls) for _, d in ipairs(RS:GetDescendants()) do if d:IsA(cls) then return d end end end
    local se, sf = sample('RemoteEvent'), sample('RemoteFunction')
    local function mk(method)
        return function(self, ...)
            -- capture only the GAME's own calls (not our replays / not other executor calls)
            if not REPLAYING and not (cc and cc()) then
                local nm = self.Name
                if nm == NAME_SPAWN or nm == NAME_RESTART or nm == NAME_INVIS then
                    local a = table.pack(...)
                    captured[nm] = { obj = self, method = method, args = a, argstr = dumpArgs(a) }
                    if learnEvent then learnEvent(nm) end
                end
            end
        end
    end
    local okE, okF = false, false
    if se then local of; okE = pcall(function()
        of = hookfunction(se.FireServer, function(self, ...) mk('FireServer')(self, ...); return of(self, ...) end)
    end) end
    if sf then local oi; okF = pcall(function()
        oi = hookfunction(sf.InvokeServer, function(self, ...) mk('InvokeServer')(self, ...); return oi(self, ...) end)
    end) end
    hookStatus = ('hook FS:%s IS:%s'):format(okE and 'OK' or 'x', okF and 'OK' or 'x')
end)

-- ═════════════ REPLAY ════════════════════════════════════════════
local function replay(name)
    local c = captured[name]
    if not c then logFn('not learned yet: ' .. name .. ' (do it manually once)', true); return false end
    REPLAYING = true
    local ok, err = pcall(function()
        if c.method == 'InvokeServer' then return c.obj:InvokeServer(table.unpack(c.args, 1, c.args.n))
        else c.obj:FireServer(table.unpack(c.args, 1, c.args.n)) end
    end)
    REPLAYING = false
    logFn((ok and '▶ replay ' or 'replay FAIL ') .. name .. '(' .. (c.argstr or '') .. ')' .. (ok and '' or (' — ' .. tostring(err):sub(1, 50))), not ok)
    return ok
end

-- ═════════════ AUTONOMOUS LOOP ═══════════════════════════════════
local busy = false
local function spawnSeq()
    replay(NAME_SPAWN)
    task.wait(jit(SPAWN_SETTLE[1], SPAWN_SETTLE[2]))
    if STEALTH then replay(NAME_INVIS) end
end
task.spawn(function()
    while true do
        task.wait(0.6)
        if RUNNING and AUTO_RESPAWN and not busy and not isAlive() then
            if captured[NAME_SPAWN] then
                busy = true
                logFn('☠ death — restart sequence')
                task.wait(jit(DEATH_REACT[1], DEATH_REACT[2]))
                if captured[NAME_RESTART] then
                    replay(NAME_RESTART)
                    task.wait(jit(RESTART_GAP[1], RESTART_GAP[2]))
                end
                spawnSeq()
                task.wait(jit(SPAWN_SETTLE[1], SPAWN_SETTLE[2]))
                busy = false
            end
        end
    end
end)

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_AutoSpawn_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_AutoSpawn = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 390, 0, 452); frame.Position = UDim2.new(0, 20, 0.4, -226)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame); stroke.Color = Color3.fromRGB(150, 110, 220); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 44); header.BackgroundColor3 = Color3.fromRGB(120, 90, 200); header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -56, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · AutoSpawn v2'
local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -44, 0, 2)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() RUNNING = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)

local learnLbl = Instance.new('TextLabel', frame)
learnLbl.BackgroundTransparency = 1; learnLbl.Size = UDim2.new(1, -24, 0, 20); learnLbl.Position = UDim2.new(0, 14, 0, 50)
learnLbl.Font = Enum.Font.Code; learnLbl.TextSize = 12; learnLbl.TextColor3 = Color3.fromRGB(230, 210, 130)
learnLbl.TextXAlignment = Enum.TextXAlignment.Left; learnLbl.Text = 'Learned — Spawn:✗  Restart:✗  Invis:✗'
local function refreshLearned()
    learnLbl.Text = ('Learned — Spawn:%s  Restart:%s  Invis:%s'):format(
        captured[NAME_SPAWN] and '✓' or '✗', captured[NAME_RESTART] and '✓' or '✗', captured[NAME_INVIS] and '✓' or '✗')
end

local hint = Instance.new('TextLabel', frame)
hint.BackgroundTransparency = 1; hint.Size = UDim2.new(1, -24, 0, 30); hint.Position = UDim2.new(0, 14, 0, 70)
hint.Font = Enum.Font.Gotham; hint.TextSize = 11; hint.TextColor3 = Color3.fromRGB(170, 190, 210)
hint.TextWrapped = true; hint.TextXAlignment = Enum.TextXAlignment.Left; hint.TextYAlignment = Enum.TextYAlignment.Top
hint.Text = 'Do each action MANUALLY once (Play / Restart / Invis) to LEARN it, then Replay/Auto.'

local function btn(label, color, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 30); b.Position = UDim2.new(0, x, 0, y); b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local rSpawn = btn('Replay Spawn', Color3.fromRGB(60, 140, 150), 12, 120, 104)
local rRest  = btn('Replay Restart', Color3.fromRGB(150, 110, 70), 136, 120, 104)
local rInv   = btn('Replay Invis', Color3.fromRGB(110, 90, 200), 260, 116, 104)

local function tgl(label, x, y, init, cb)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, 178, 0, 30); b.Position = UDim2.new(0, x, 0, y); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250)
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    local s = init
    local function paint() b.BackgroundColor3 = s and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88); b.Text = label .. ': ' .. (s and 'ON' or 'OFF') end
    paint(); b.MouseButton1Click:Connect(function() s = not s; paint(); cb(s) end); return b
end
tgl('Auto-Respawn', 12, 142, AUTO_RESPAWN, function(s) AUTO_RESPAWN = s end)
tgl('Stealth(Invis)', 198, 142, STEALTH, function(s) STEALTH = s end)

local startBtn = btn('▶ Start', Color3.fromRGB(60, 150, 100), 12, 150, 180)
local stopBtn  = btn('■ Stop',  Color3.fromRGB(160, 80, 80), 168, 150, 180)

local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1; stat.Size = UDim2.new(1, -24, 0, 18); stat.Position = UDim2.new(0, 14, 0, 216)
stat.Font = Enum.Font.Code; stat.TextSize = 11; stat.TextColor3 = Color3.fromRGB(150, 220, 180)
stat.TextXAlignment = Enum.TextXAlignment.Left; stat.Text = hookStatus

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 196); scroll.Position = UDim2.new(0, 10, 0, 240)
scroll.BackgroundColor3 = Color3.fromRGB(12, 14, 20); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 110, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lay = Instance.new('UIListLayout', scroll); lay.Padding = UDim.new(0, 2); lay.SortOrder = Enum.SortOrder.LayoutOrder
local lpad = Instance.new('UIPadding', scroll); lpad.PaddingTop = UDim.new(0, 4); lpad.PaddingLeft = UDim.new(0, 6)

logFn = function(text, isErr)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -12, 0, 15); lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 10
    lbl.TextColor3 = isErr and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(180, 210, 230)
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = ('[%5.1fs] %s'):format(tick() % 100000, text)
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 17)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end
learnEvent = function(nm) refreshLearned(); logFn('✓ learned ' .. nm .. '(' .. (captured[nm].argstr or '') .. ')', false) end

logFn('ready. ' .. hookStatus)
if not hookfunction then logFn('hookfunction missing — cannot capture.', true) end
logFn('Do Play / Restart / Invis manually ONCE to learn them.')

rSpawn.MouseButton1Click:Connect(function() replay(NAME_SPAWN) end)
rRest.MouseButton1Click:Connect(function() replay(NAME_RESTART) end)
rInv.MouseButton1Click:Connect(function() replay(NAME_INVIS) end)
startBtn.MouseButton1Click:Connect(function()
    if RUNNING then return end
    RUNNING = true; busy = false
    logFn(('STARTED. respawn=%s stealth=%s  alive=%s h=%s'):format(tostring(AUTO_RESPAWN), tostring(STEALTH), tostring(isAlive()), tostring(getHealth())))
    if not captured[NAME_SPAWN] then logFn('⚠ SPAWN not learned — press Play once first!', true) end
end)
stopBtn.MouseButton1Click:Connect(function() RUNNING = false; busy = false; logFn('STOPPED.') end)
