--[[
═══════════════════════════════════════════════════════════════════════
            HS HUB · AutoSpawn v4  (lobby-based, robust)
   Reads real slots from SlotsFrame, spawns an ALIVE one; if all dead,
   Restart then Spawn. Resolves remotes from EVERYWHERE (capture / LP.Remotes
   / ReplicatedStorage) and lets you test each step manually.
                    discord.gg/5rpP6faZSJ

   SLOT TRUTH (SlotScan-confirmed): SaveSelectionGui … > SlotsFrame >
       "<N>" (numeric child = the slot id)  > InnerFrame > CreatureFrame
            NameLabel.Text = creature ;  DeadLabel.Visible = DEAD
       The "Default" child is the TEMPLATE (skip it).  remote arg = "Slot"..N
   Remotes: SpawnRemote:InvokeServer("SlotN") ; RestartSlotRemote("SlotN",false)
            then SpawnRemote ; ActivateAbility:FireServer("Invisibility")

   USE: at the lobby → "🔍 Read Slots" (verify) → "▶ Spawn now" (test ONE spawn)
        → if it works, Auto-Respawn ON → Start. If "remote NOT FOUND", play one
        creature manually once to LEARN it, then it works.
   Test on a THROWAWAY (CoS shadow-bans on a delay).
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

local NAME_SPAWN, NAME_RESTART, NAME_INVIS = 'SpawnRemote', 'RestartSlotRemote', 'ActivateAbility'
local AUTO_RESPAWN, STEALTH, RUNNING = true, false, false
local function jit(a, b) return a + math.random() * (b - a) end
local SETTLE = {2.5, 4.0}
local GAP    = {1.0, 2.0}
local logFn

-- ═════════════ ROBUST REMOTE RESOLUTION (try everywhere) ═════════
local captured, REPLAYING = {}, false
local function isRemote(o) return o and (o:IsA('RemoteEvent') or o:IsA('RemoteFunction')) end
local function searchPlaces(nm)
    -- ordered: LocalPlayer.Remotes first (CoS keeps them there), then RS, then PlayerGui
    local places = {}
    pcall(function() local r = LP:FindFirstChild('Remotes'); if r then places[#places+1] = r end end)
    places[#places+1] = RS
    pcall(function() places[#places+1] = LP end)
    for _, p in ipairs(places) do
        local o = p:FindFirstChild(nm, true)
        if isRemote(o) then return o, (o:IsA('RemoteFunction') and 'InvokeServer' or 'FireServer') end
    end
    return nil
end
local function resolve(nm)
    if captured[nm] then return captured[nm].obj, captured[nm].method, 'captured' end
    local o, m = searchPlaces(nm)
    if o then return o, m, 'found' end
    return nil
end
-- learn the exact remote objects from the game's own calls
pcall(function()
    if not hookfunction then return end
    local cc = checkcaller
    local function sample(cls) for _, d in ipairs(RS:GetDescendants()) do if d:IsA(cls) then return d end end end
    local se, sf = sample('RemoteEvent'), sample('RemoteFunction')
    local function cap(method) return function(self, ...)
        if not REPLAYING and not (cc and cc()) then
            local nm = self.Name
            if nm == NAME_SPAWN or nm == NAME_RESTART or nm == NAME_INVIS then captured[nm] = { obj = self, method = method } end
        end
    end end
    if se then local of; of = hookfunction(se.FireServer, function(self, ...) cap('FireServer')(self, ...); return of(self, ...) end) end
    if sf then local oi; oi = hookfunction(sf.InvokeServer, function(self, ...) cap('InvokeServer')(self, ...); return oi(self, ...) end) end
end)

local function fire(nm, ...)
    local obj, method, how = resolve(nm)
    if not obj then logFn('✗ ' .. nm .. ' NOT FOUND (play once to learn it)', true); return false end
    local args = table.pack(...)
    REPLAYING = true
    local ok, err = pcall(function()
        if method == 'InvokeServer' then return obj:InvokeServer(table.unpack(args, 1, args.n))
        else obj:FireServer(table.unpack(args, 1, args.n)) end
    end)
    REPLAYING = false
    if ok then logFn(('→ %s(%s) [%s]'):format(nm, table.concat({...}, ','), how))
    else logFn('✗ ' .. nm .. ' err: ' .. tostring(err):sub(1, 40), true) end
    return ok
end

-- ═════════════ READ SLOTS (SlotsFrame numeric children) ══════════
local function findSaveGui()
    for _, r in ipairs({ PG, (gethui and gethui()) or PG }) do
        local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end
    end
    return nil
end
local function readSlots()
    local out = {}
    local gui = findSaveGui(); if not gui then return out, 'no SaveSelectionGui' end
    local slotsFrame
    for _, d in ipairs(gui:GetDescendants()) do if d.Name == 'SlotsFrame' then slotsFrame = d; break end end
    if not slotsFrame then return out, 'no SlotsFrame' end
    for _, sf in ipairs(slotsFrame:GetChildren()) do
        local n = tonumber(sf.Name)   -- numeric child = real slot id; skips "Default"/layouts
        if n then
            local cf = sf:FindFirstChild('CreatureFrame', true)
            local nm = '?'; local dead = false
            if cf then
                local nameL = cf:FindFirstChild('NameLabel')
                local deadL = cf:FindFirstChild('DeadLabel')
                local restartB = cf:FindFirstChild('RestartButton')
                if nameL then nm = nameL.Text end
                dead = (deadL and deadL.Visible == true) or (restartB and restartB.Visible == true) or false
            end
            out[#out + 1] = { slot = 'Slot' .. n, n = n, name = nm, dead = dead }
        end
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end

local function inGame()
    local chars = Workspace:FindFirstChild('Characters')
    if chars and (chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)) then return true end
    return false
end

-- ═════════════ actions ═══════════════════════════════════════════
local function doInvis() fire(NAME_INVIS, 'Invisibility') end
local function spawnSlot(slot)
    fire(NAME_SPAWN, slot)
    task.wait(jit(SETTLE[1], SETTLE[2]))
    if STEALTH then doInvis() end
end
local function restartSlot(slot) fire(NAME_RESTART, slot, false); task.wait(jit(GAP[1], GAP[2])) end
local function pickAndSpawn()
    local slots = readSlots()
    if #slots == 0 then logFn('no slots read (open lobby menu)', true); return end
    local alive
    for _, s in ipairs(slots) do if not s.dead then alive = s; break end end
    if alive then
        logFn('spawning ALIVE ' .. alive.slot .. ' (' .. alive.name .. ')')
        spawnSlot(alive.slot)
    else
        local s = slots[1]
        logFn('all DEAD → restart+spawn ' .. s.slot)
        restartSlot(s.slot); spawnSlot(s.slot)
    end
end

-- ═════════════ LOBBY LOOP ════════════════════════════════════════
local busy = false
task.spawn(function()
    while true do
        task.wait(1.2)
        if RUNNING and not busy and not inGame() then
            busy = true
            pcall(pickAndSpawn)
            task.wait(jit(SETTLE[1], SETTLE[2]))
            busy = false
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
frame.Size = UDim2.new(0, 400, 0, 452); frame.Position = UDim2.new(0, 20, 0.5, -226)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
Instance.new('UIStroke', frame).Color = Color3.fromRGB(150, 110, 220)
local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 42); header.BackgroundColor3 = Color3.fromRGB(120, 90, 200); header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -52, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · AutoSpawn v4'
local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.new(0, 38, 0, 38); closeBtn.Position = UDim2.new(1, -42, 0, 2)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() RUNNING = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)

local function btn(label, color, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 30); b.Position = UDim2.new(0, x, 0, y); b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local readBtn  = btn('🔍 Read Slots', Color3.fromRGB(70, 150, 200), 12, 124, 50)
local spawnBtn = btn('▶ Spawn now', Color3.fromRGB(60, 140, 150), 140, 122, 50)
local restartBtn = btn('↻ Restart now', Color3.fromRGB(150, 110, 70), 266, 122, 50)
local invisBtn = btn('👻 Invis now', Color3.fromRGB(110, 90, 200), 12, 124, 86)

local function tgl(label, x, y, init, cb)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, 122, 0, 30); b.Position = UDim2.new(0, x, 0, y); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.TextColor3 = Color3.fromRGB(245, 245, 250)
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    local s = init
    local function paint() b.BackgroundColor3 = s and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88); b.Text = label .. ':' .. (s and 'ON' or 'OFF') end
    paint(); b.MouseButton1Click:Connect(function() s = not s; paint(); cb(s) end); return b
end
tgl('Auto-Respawn', 140, 86, AUTO_RESPAWN, function(s) AUTO_RESPAWN = s end)
tgl('Stealth', 266, 86, STEALTH, function(s) STEALTH = s end)
local startBtn = btn('▶ Start', Color3.fromRGB(60, 150, 100), 12, 188, 122)
local stopBtn  = btn('■ Stop',  Color3.fromRGB(160, 80, 80), 204, 184, 122)

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 246); scroll.Position = UDim2.new(0, 10, 0, 162)
scroll.BackgroundColor3 = Color3.fromRGB(12, 14, 20); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(150, 110, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lay = Instance.new('UIListLayout', scroll); lay.Padding = UDim.new(0, 2); lay.SortOrder = Enum.SortOrder.LayoutOrder
local lpd = Instance.new('UIPadding', scroll); lpd.PaddingTop = UDim.new(0, 4); lpd.PaddingLeft = UDim.new(0, 6)
logFn = function(text, isErr)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -12, 0, 15); lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 11; lbl.TextColor3 = isErr and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(185, 215, 235)
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 17)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end
-- show remote resolution status up-front so we know if spawn can work
local function remoteStatus()
    local function st(nm) local o,_,how = resolve(nm); return o and (how) or 'MISSING' end
    logFn(('remotes — Spawn:%s Restart:%s Invis:%s'):format(st(NAME_SPAWN), st(NAME_RESTART), st(NAME_INVIS)),
        resolve(NAME_SPAWN) and false or true)
end
logFn('v4 ready. Tap Read Slots, then Spawn now to test.')
remoteStatus()

readBtn.MouseButton1Click:Connect(function()
    local slots = readSlots()
    logFn(('── Read Slots (in_game=%s, %d) ──'):format(tostring(inGame()), #slots), Color3.fromRGB(120, 220, 255))
    if #slots == 0 then logFn('  none — is the lobby/creature menu loaded?', Color3.fromRGB(255, 200, 120)) end
    for _, s in ipairs(slots) do
        logFn(('  %s  %s  %s'):format(s.slot, s.name, s.dead and 'DEAD' or 'ALIVE'),
            s.dead and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 230, 150))
    end
    remoteStatus()
end)
spawnBtn.MouseButton1Click:Connect(function() task.spawn(pickAndSpawn) end)
restartBtn.MouseButton1Click:Connect(function()
    local slots = readSlots(); if slots[1] then restartSlot(slots[1].slot) else logFn('no slot', true) end
end)
invisBtn.MouseButton1Click:Connect(function() doInvis() end)
startBtn.MouseButton1Click:Connect(function()
    if RUNNING then return end
    RUNNING = true; busy = false
    logFn(('STARTED. respawn=%s stealth=%s'):format(tostring(AUTO_RESPAWN), tostring(STEALTH)))
    remoteStatus()
end)
stopBtn.MouseButton1Click:Connect(function() RUNNING = false; busy = false; logFn('STOPPED.') end)
