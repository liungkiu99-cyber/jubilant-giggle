--[[
═══════════════════════════════════════════════════════════════════════
                 HS HUB · AutoSpawn (Mode 1 core tester)
        Autonomous spawn / auto-restart-on-death / stealth(invis)
                    discord.gg/5rpP6faZSJ

    Captured remotes (ActionSpy, 2026-06-02, place 5233782396):
        PLAY a slot      : SpawnRemote:InvokeServer("SlotN")
        RESTART a dead   : RestartSlotRemote:InvokeServer("SlotN", false)
                           then SpawnRemote:InvokeServer("SlotN")
        Invisibility     : ActivateAbility:FireServer("Invisibility")
    Slot is in the ARG — no UI click needed.

    THIS IS A STANDALONE TESTER. Validate the core loop on a THROWAWAY
    account first (CoS shadow-bans on a DELAY — "no ban in 5 min" ≠ safe).
    Once confirmed, it gets folded into the hub's Autonomous artifact farm.

    Anticheat baked in: every wait is JITTERED, a busy-guard prevents our
    own restart from re-triggering death, and there is a min-cycle floor.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

-- ═════════════ CONFIG (defaults; tune in UI) ═════════════════════
local SLOT        = 'Slot1'
local AUTO_RESPAWN= true
local STEALTH     = false           -- auto-activate Invisibility on spawn
local RUNNING     = false

-- jitter windows (seconds) — keep human-ish, anticheat-safe
local function jit(a, b) return a + math.random() * (b - a) end
-- user: jitter not critical here (UI activity, not teleport) — keep small, ~1-2s max
local DEATH_REACT = {0.4, 1.2}      -- wait after detecting death before restarting
local RESTART_GAP = {1.0, 2.0}      -- gap between RestartSlotRemote and SpawnRemote
local SPAWN_SETTLE= {0.8, 1.6}      -- wait after spawn before invis / before re-arming death watch

-- ═════════════ FIND REMOTES (by name, tree-read only) ════════════
local function findRemote(name)
    local d = RS:FindFirstChild(name, true)
    if d and (d:IsA('RemoteEvent') or d:IsA('RemoteFunction')) then return d end
    for _, x in ipairs(RS:GetDescendants()) do
        if x.Name == name and (x:IsA('RemoteEvent') or x:IsA('RemoteFunction')) then return x end
    end
    return nil
end
local SpawnRemote   = findRemote('SpawnRemote')
local RestartRemote = findRemote('RestartSlotRemote')
local AbilityRemote = findRemote('ActivateAbility')

-- ═════════════ CHARACTER / HEALTH ════════════════════════════════
local function getChar()
    local c = LP.Character
    if c and c:FindFirstChild('Data') then return c end
    local chars = Workspace:FindFirstChild('Characters')
    if chars then
        -- CoS character node may be keyed by Name OR DisplayName
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
    local data = c:FindFirstChild('Data'); if not data then return nil end
    return tonumber(data:GetAttribute('h'))
end
local function isAlive()
    local h = getHealth(); return h ~= nil and h > 0
end

-- ═════════════ ACTIONS (the captured remotes) ════════════════════
local busy = false   -- guard: we are mid-restart, ignore death watch
local logFn            -- set by UI

local function doSpawn()
    if not SpawnRemote then logFn('no SpawnRemote found', true); return false end
    local ok = pcall(function() SpawnRemote:InvokeServer(SLOT) end)
    logFn(ok and ('▶ SpawnRemote('..SLOT..')') or 'SpawnRemote FAILED', not ok)
    return ok
end
local function doRestart()
    if not RestartRemote then logFn('no RestartSlotRemote found', true); return false end
    local ok = pcall(function() RestartRemote:InvokeServer(SLOT, false) end)
    logFn(ok and ('↻ RestartSlotRemote('..SLOT..', false)') or 'Restart FAILED', not ok)
    return ok
end
local function doInvis()
    if not AbilityRemote then logFn('no ActivateAbility found', true); return end
    local ok = pcall(function() AbilityRemote:FireServer('Invisibility') end)
    logFn(ok and '👻 ActivateAbility(Invisibility)' or 'Invis FAILED', not ok)
end

-- ═════════════ MAIN AUTONOMOUS LOOP ══════════════════════════════
local function spawnThenStealth()
    doSpawn()
    task.wait(jit(SPAWN_SETTLE[1], SPAWN_SETTLE[2]))
    if STEALTH then doInvis() end
end

task.spawn(function()
    while true do
        task.wait(0.6)
        if RUNNING and not busy and AUTO_RESPAWN then
            if not isAlive() then
                busy = true
                logFn('☠ death detected — restart sequence', false)
                task.wait(jit(DEATH_REACT[1], DEATH_REACT[2]))
                doRestart()
                task.wait(jit(RESTART_GAP[1], RESTART_GAP[2]))   -- restart→spawn gap (human ~3.6s)
                spawnThenStealth()
                task.wait(jit(SPAWN_SETTLE[1], SPAWN_SETTLE[2]))  -- let new char settle before re-arming
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
frame.Size = UDim2.new(0, 380, 0, 446); frame.Position = UDim2.new(0, 20, 0.4, -223)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame); stroke.Color = Color3.fromRGB(150, 110, 220); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 44); header.BackgroundColor3 = Color3.fromRGB(120, 90, 200); header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -56, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · AutoSpawn'
local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -44, 0, 2)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() RUNNING = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)

-- slot textbox
local slotLbl = Instance.new('TextLabel', frame)
slotLbl.BackgroundTransparency = 1; slotLbl.Size = UDim2.new(0, 60, 0, 28); slotLbl.Position = UDim2.new(0, 14, 0, 52)
slotLbl.Font = Enum.Font.GothamBold; slotLbl.TextSize = 13; slotLbl.TextColor3 = Color3.fromRGB(220, 220, 235)
slotLbl.TextXAlignment = Enum.TextXAlignment.Left; slotLbl.Text = 'Slot:'
local slotBox = Instance.new('TextBox', frame)
slotBox.Size = UDim2.new(0, 120, 0, 28); slotBox.Position = UDim2.new(0, 64, 0, 52)
slotBox.BackgroundColor3 = Color3.fromRGB(30, 34, 44); slotBox.BorderSizePixel = 0
slotBox.Font = Enum.Font.Code; slotBox.TextSize = 13; slotBox.TextColor3 = Color3.fromRGB(230, 240, 230)
slotBox.Text = SLOT; slotBox.ClearTextOnFocus = false
Instance.new('UICorner', slotBox).CornerRadius = UDim.new(0, 6)
slotBox.FocusLost:Connect(function() if slotBox.Text ~= '' then SLOT = slotBox.Text end end)

local function toggle(label, x, y, init, cb)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, 158, 0, 30); b.Position = UDim2.new(0, x, 0, y); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250)
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    local state = init
    local function paint()
        b.BackgroundColor3 = state and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88)
        b.Text = label .. ': ' .. (state and 'ON' or 'OFF')
    end
    paint()
    b.MouseButton1Click:Connect(function() state = not state; paint(); cb(state) end)
    return b
end
toggle('Auto-Respawn', 14, 90, AUTO_RESPAWN, function(s) AUTO_RESPAWN = s end)
toggle('Stealth(Invis)', 184, 90, STEALTH, function(s) STEALTH = s end)

local function btn(label, color, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 32); b.Position = UDim2.new(0, x, 0, y); b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local startBtn = btn('▶ Start', Color3.fromRGB(60, 150, 100), 14, 110, 128)
local stopBtn  = btn('■ Stop',  Color3.fromRGB(160, 80, 80), 132, 110, 128)
local invisBtn = btn('👻 Invis now', Color3.fromRGB(110, 90, 200), 250, 116, 128)
-- manual test row (use these from the DEATH screen to validate each remote)
local spawnBtn   = btn('▶ Spawn now',   Color3.fromRGB(60, 140, 150), 14, 175, 166)
local restartBtn = btn('↻ Restart now', Color3.fromRGB(150, 110, 70), 199, 167, 166)

local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1; stat.Size = UDim2.new(1, -24, 0, 30); stat.Position = UDim2.new(0, 14, 0, 204)
stat.Font = Enum.Font.Code; stat.TextSize = 11; stat.TextColor3 = Color3.fromRGB(160, 220, 180)
stat.TextXAlignment = Enum.TextXAlignment.Left; stat.TextYAlignment = Enum.TextYAlignment.Top; stat.TextWrapped = true
stat.Text = ('Remotes — Spawn:%s Restart:%s Ability:%s'):format(
    SpawnRemote and 'OK' or 'X', RestartRemote and 'OK' or 'X', AbilityRemote and 'OK' or 'X')

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 196); scroll.Position = UDim2.new(0, 10, 0, 240)
scroll.BackgroundColor3 = Color3.fromRGB(12, 14, 20); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 110, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local layout = Instance.new('UIListLayout', scroll); layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder
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
logFn('ready. Slot=' .. SLOT .. '  (test on a throwaway first!)')
if not (SpawnRemote and RestartRemote) then logFn('WARNING: a remote was not found by name.', true) end

startBtn.MouseButton1Click:Connect(function()
    if RUNNING then return end
    RUNNING = true; busy = false
    logFn('STARTED. respawn=' .. tostring(AUTO_RESPAWN) .. ' stealth=' .. tostring(STEALTH))
    logFn(('detect: alive=%s  h=%s'):format(tostring(isAlive()), tostring(getHealth())))
    -- initial spawn only if not already alive (spawning while alive is a server no-op)
    task.spawn(function()
        if isAlive() then logFn('already alive — watching for death only')
        else spawnThenStealth() end
    end)
end)
stopBtn.MouseButton1Click:Connect(function() RUNNING = false; busy = false; logFn('STOPPED.') end)
invisBtn.MouseButton1Click:Connect(function() doInvis() end)
spawnBtn.MouseButton1Click:Connect(function() doSpawn() end)
restartBtn.MouseButton1Click:Connect(function() doRestart() end)
