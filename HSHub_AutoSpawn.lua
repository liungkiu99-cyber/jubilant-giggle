--[[
═══════════════════════════════════════════════════════════════════════
            HS HUB · AutoSpawn v3  (lobby-based, reads slots)
   At the LOBBY: read each slot's creature + alive/dead, then
   spawn an ALIVE one — if all dead, Restart one then Spawn.
                    discord.gg/5rpP6faZSJ

   SLOT STRUCTURE (SlotScan-confirmed, place 5233782396):
     SaveSelectionGui > … > InnerFrame > CreatureFrame (one per active slot)
        NameLabel.Text   = creature name
        IndexLabel.Text  = slot number N  ->  remote arg "Slot"..N
        DeadLabel.Visible = true => DEAD (else alive)
   Remotes (capture-replayed so the instance is always correct):
        Play  : SpawnRemote:InvokeServer("SlotN")
        Restart: RestartSlotRemote:InvokeServer("SlotN", false)  then SpawnRemote
        Invis : ActivateAbility:FireServer("Invisibility")

   USE:
     1. At the lobby, paste this. Tap "🔍 Read Slots" → it lists every slot:
        "Slot1 Whispthera ALIVE / Slot2 ... ". CONFIRM that matches the menu.
     2. (optional) Play once manually so it LEARNS the exact remote objects
        (otherwise it finds them by name).
     3. Auto-Respawn ON (+Stealth if wanted) → Start. At the lobby it spawns an
        alive slot; if all dead it restarts one then spawns. While in-game it idles.
   Test on a THROWAWAY first (CoS shadow-bans on a DELAY).
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
local SETTLE = {2.5, 4.0}   -- wait after a spawn for the blackscreen/load
local GAP    = {1.0, 2.0}   -- restart -> spawn gap

-- ═════════════ remote capture + lookup ═══════════════════════════
local captured, REPLAYING = {}, false
local function guiRoots()
    local r = { PG }
    pcall(function() if gethui then local h = gethui(); if h and h ~= PG then r[#r+1] = h end end end)
    pcall(function() r[#r+1] = game:GetService('CoreGui') end)
    return r
end
local function findRemoteByName(nm)
    local d = RS:FindFirstChild(nm, true)
    if d and (d:IsA('RemoteEvent') or d:IsA('RemoteFunction')) then return d end
    return nil
end
-- returns obj, method
local function remoteFor(nm, method)
    if captured[nm] then return captured[nm].obj, captured[nm].method end
    local o = findRemoteByName(nm)
    if o then return o, (o:IsA('RemoteFunction') and 'InvokeServer' or method or 'FireServer') end
    return nil, nil
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
                captured[nm] = { obj = self, method = method }
            end
        end
    end end
    if se then local of; of = hookfunction(se.FireServer, function(self, ...) cap('FireServer')(self, ...); return of(self, ...) end) end
    if sf then local oi; oi = hookfunction(sf.InvokeServer, function(self, ...) cap('InvokeServer')(self, ...); return oi(self, ...) end) end
end)

local logFn
local function fire(nm, defaultMethod, ...)
    local obj, method = remoteFor(nm, defaultMethod)
    if not obj then logFn('remote not found: ' .. nm, true); return false end
    local args = table.pack(...)
    REPLAYING = true
    local ok, err = pcall(function()
        if method == 'InvokeServer' then return obj:InvokeServer(table.unpack(args, 1, args.n))
        else obj:FireServer(table.unpack(args, 1, args.n)) end
    end)
    REPLAYING = false
    if not ok then logFn(nm .. ' FAIL: ' .. tostring(err):sub(1, 50), true) end
    return ok
end

-- ═════════════ read the slots (live) ═════════════════════════════
local function findSaveGui()
    for _, r in ipairs(guiRoots()) do
        local g = r:FindFirstChild('SaveSelectionGui')
        if g then return g end
    end
    return nil
end
-- list { slot="SlotN", name=, dead=bool } for each active CreatureFrame
local function readSlots()
    local out, seen = {}, {}
    local gui = findSaveGui()
    if not gui then return out end
    for _, d in ipairs(gui:GetDescendants()) do
        if d.Name == 'CreatureFrame' then
            local nameL = d:FindFirstChild('NameLabel')
            local idxL  = d:FindFirstChild('IndexLabel')
            if nameL and idxL then
                local nm  = nameL.Text
                local idx = tonumber((idxL.Text or ''):match('%d+'))
                local visible = true
                pcall(function() visible = d.Visible end)
                if idx and nm and nm ~= '' and visible and not seen[idx] then
                    seen[idx] = true
                    local deadL = d:FindFirstChild('DeadLabel')
                    local restartB = d:FindFirstChild('RestartButton')
                    local dead = (deadL and deadL.Visible == true) or (restartB and restartB.Visible == true) or false
                    out[#out + 1] = { slot = 'Slot' .. idx, idx = idx, name = nm, dead = dead }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.idx < b.idx end)
    return out
end

-- ═════════════ in-game vs lobby ══════════════════════════════════
local function inGame()
    local chars = Workspace:FindFirstChild('Characters')
    if chars and (chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)) then return true end
    return false
end

-- ═════════════ spawn / restart sequences ═════════════════════════
local function doInvis() fire(NAME_INVIS, 'FireServer', 'Invisibility') end
local function spawnSlot(slot)
    logFn('▶ Spawn ' .. slot)
    fire(NAME_SPAWN, 'InvokeServer', slot)
    task.wait(jit(SETTLE[1], SETTLE[2]))
    if STEALTH then doInvis() end
end
local function restartSlot(slot)
    logFn('↻ Restart ' .. slot)
    fire(NAME_RESTART, 'InvokeServer', slot, false)
    task.wait(jit(GAP[1], GAP[2]))
end

-- ═════════════ MAIN LOBBY LOOP ═══════════════════════════════════
local busy = false
task.spawn(function()
    while true do
        task.wait(1.2)
        if RUNNING and not busy and not inGame() then
            local slots = readSlots()
            if #slots == 0 then
                -- menu not loaded yet / nothing to read; idle quietly
            else
                busy = true
                local alive
                for _, s in ipairs(slots) do if not s.dead then alive = s; break end end
                if alive then
                    spawnSlot(alive.slot)
                else
                    -- all dead -> restart the first slot then spawn it
                    local s = slots[1]
                    restartSlot(s.slot)
                    spawnSlot(s.slot)
                end
                task.wait(jit(SETTLE[1], SETTLE[2]))
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
frame.Size = UDim2.new(0, 400, 0, 430); frame.Position = UDim2.new(0, 20, 0.5, -215)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
Instance.new('UIStroke', frame).Color = Color3.fromRGB(150, 110, 220)

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 44); header.BackgroundColor3 = Color3.fromRGB(120, 90, 200); header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -56, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · AutoSpawn v3'
local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -44, 0, 2)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() RUNNING = false; gui:Destroy(); shared.__HSHub_AutoSpawn = nil end)

local function btn(label, color, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 32); b.Position = UDim2.new(0, x, 0, y); b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local readBtn = btn('🔍 Read Slots', Color3.fromRGB(70, 150, 200), 12, 180, 54)
local invisBtn = btn('👻 Invis now', Color3.fromRGB(110, 90, 200), 200, 188, 54)

local function tgl(label, x, y, init, cb)
    local b = Instance.new('TextButton', frame); b.Size = UDim2.new(0, 184, 0, 30); b.Position = UDim2.new(0, x, 0, y); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250)
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    local s = init
    local function paint() b.BackgroundColor3 = s and Color3.fromRGB(70, 150, 110) or Color3.fromRGB(70, 74, 88); b.Text = label .. ': ' .. (s and 'ON' or 'OFF') end
    paint(); b.MouseButton1Click:Connect(function() s = not s; paint(); cb(s) end); return b
end
tgl('Auto-Respawn', 12, 92, AUTO_RESPAWN, function(s) AUTO_RESPAWN = s end)
tgl('Stealth(Invis)', 204, 92, STEALTH, function(s) STEALTH = s end)
local startBtn = btn('▶ Start', Color3.fromRGB(60, 150, 100), 12, 184, 130)
local stopBtn  = btn('■ Stop',  Color3.fromRGB(160, 80, 80), 204, 184, 130)

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 250); scroll.Position = UDim2.new(0, 10, 0, 170)
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
logFn('v3 ready. Tap "Read Slots" first to verify, then Start.')

readBtn.MouseButton1Click:Connect(function()
    local slots = readSlots()
    logFn(('── Read Slots (in_game=%s, found %d) ──'):format(tostring(inGame()), #slots), Color3.fromRGB(120, 220, 255))
    if #slots == 0 then logFn('  none — open the creature/lobby menu, then Read again.', Color3.fromRGB(255, 200, 120)) end
    for _, s in ipairs(slots) do
        logFn(('  %s  %s  %s'):format(s.slot, s.name, s.dead and 'DEAD' or 'ALIVE'),
            s.dead and Color3.fromRGB(255, 140, 140) or Color3.fromRGB(150, 230, 150))
    end
    logFn('Confirm slot↔creature↔alive matches the menu before Start.', Color3.fromRGB(255, 220, 140))
end)
invisBtn.MouseButton1Click:Connect(function() doInvis() end)
startBtn.MouseButton1Click:Connect(function()
    if RUNNING then return end
    RUNNING = true; busy = false
    logFn(('STARTED. respawn=%s stealth=%s in_game=%s'):format(tostring(AUTO_RESPAWN), tostring(STEALTH), tostring(inGame())))
end)
stopBtn.MouseButton1Click:Connect(function() RUNNING = false; busy = false; logFn('STOPPED.') end)
