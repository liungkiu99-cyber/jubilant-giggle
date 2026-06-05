--[[
    HS HUB · AutoSpawn v6
    Lobby-based: reads SaveSelectionGui slots → spawns alive → restart+spawn if all dead
    SAFE: hook never breaks game Mainkan (double-pcall + nil check on original fn)
    LEARN: press Mainkan once → panel shows exact arg + stores remote object for replay
    discord.gg/5rpP6faZSJ
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

local NAME_SPAWN, NAME_RESTART, NAME_INVIS = 'SpawnRemote', 'RestartSlotRemote', 'ActivateAbility'
local AUTO_RESPAWN, STEALTH, RUNNING = true, false, false
local function jit(a,b) return a + math.random()*(b-a) end
local logFn -- set later

-- ═══ SAFE HOOK (capture only, never breaks game) ═════════════════
local captured = {}
local REPLAYING = false

pcall(function()
    if not hookfunction then return end
    local cc = checkcaller
    local function findSample(cls)
        for _,d in ipairs(RS:GetDescendants()) do if d:IsA(cls) then return d end end
    end

    -- Hook FireServer (safe for RemoteEvents like Invis)
    local se = findSample('RemoteEvent')
    if se then
        local orig
        pcall(function()
            orig = hookfunction(se.FireServer, function(self, ...)
                local args = table.pack(...)  -- capture BEFORE pcall so ... is in scope
                pcall(function()
                    if not REPLAYING and not (cc and cc()) then
                        local nm = self.Name
                        if nm==NAME_INVIS or nm==NAME_SPAWN or nm==NAME_RESTART then
                            captured[nm] = {obj=self, method='FireServer', args=args}
                            local s={}; for i=1,args.n do s[i]=tostring(args[i]) end
                            if logFn then logFn('✓ LEARNED '..nm..'('..table.concat(s,',')..')', false) end
                        end
                    end
                end)
                if orig then return orig(self, table.unpack(args,1,args.n)) end
            end)
        end)
    end

    -- Hook InvokeServer (RemoteFunctions like SpawnRemote) — SAFE version
    local sf = findSample('RemoteFunction')
    if sf then
        local orig
        pcall(function()
            orig = hookfunction(sf.InvokeServer, function(self, ...)
                local args = table.pack(...)  -- capture BEFORE pcall
                pcall(function()
                    if not REPLAYING and not (cc and cc()) then
                        local nm = self.Name
                        if nm==NAME_SPAWN or nm==NAME_RESTART then
                            captured[nm] = {obj=self, method='InvokeServer', args=args}
                            local s={}; for i=1,args.n do s[i]=tostring(args[i]) end
                            if logFn then logFn('✓ LEARNED '..nm..'('..table.concat(s,',')..')', false) end
                        end
                    end
                end)
                -- CRITICAL: nil-check, never crash if orig is nil
                if orig then return orig(self, table.unpack(args,1,args.n)) end
            end)
        end)
    end
end)

-- ═══ FIND REMOTE (search everywhere) ════════════════════════════
local function findRemote(nm)
    -- 1. use captured (proven to work: exact object from game's own call)
    if captured[nm] then return captured[nm].obj, captured[nm].method end
    -- 2. LP.Remotes folder (CoS keeps remotes here)
    local lpR = LP:FindFirstChild('Remotes')
    if lpR then
        local o = lpR:FindFirstChild(nm, true)
        if o then return o, (o:IsA('RemoteFunction') and 'InvokeServer' or 'FireServer') end
    end
    -- 3. RS recursive
    local o = RS:FindFirstChild(nm, true)
    if o then return o, (o:IsA('RemoteFunction') and 'InvokeServer' or 'FireServer') end
    -- 4. LP recursive
    local o2 = LP:FindFirstChild(nm, true)
    if o2 then return o2, (o2:IsA('RemoteFunction') and 'InvokeServer' or 'FireServer') end
    return nil, nil
end

local function callRemote(nm, ...)
    local obj, method = findRemote(nm)
    if not obj then logFn('✗ '..nm..' not found anywhere', true); return false end
    local src = captured[nm] and 'replay' or 'found'
    local a = table.pack(...)           -- capture varargs BEFORE pcall
    local astr = table.concat({...},',')
    REPLAYING = true
    local ok, err = pcall(function()
        if method == 'InvokeServer' then return obj:InvokeServer(table.unpack(a,1,a.n))
        else obj:FireServer(table.unpack(a,1,a.n)) end
    end)
    REPLAYING = false
    logFn((ok and '→ ' or '✗ ')..nm..'('..astr..') ['..src..']', not ok)
    if not ok then logFn('  err: '..tostring(err):sub(1,60), true) end
    return ok
end

-- ═══ SPAWN via REPLAY (uses captured exact args) ═════════════════
local function replaySpawn()
    local c = captured[NAME_SPAWN]
    if not c then return false, 'not learned yet' end
    REPLAYING = true
    local ok, err = pcall(function()
        if c.method == 'InvokeServer' then return c.obj:InvokeServer(table.unpack(c.args,1,c.args.n))
        else c.obj:FireServer(table.unpack(c.args,1,c.args.n)) end
    end)
    REPLAYING = false
    logFn((ok and '→ REPLAY SpawnRemote' or '✗ REPLAY SpawnRemote '..tostring(err):sub(1,40)), not ok)
    return ok
end

-- ═══ READ LOBBY SLOTS ════════════════════════════════════════════
local function findSaveGui()
    for _,r in ipairs({PG, gethui and gethui() or PG}) do
        local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end
    end
end
local function readSlots()
    local out = {}
    local gui = findSaveGui(); if not gui then return out end
    local sf; for _,d in ipairs(gui:GetDescendants()) do if d.Name=='SlotsFrame' then sf=d; break end end
    if not sf then return out end
    for _,child in ipairs(sf:GetChildren()) do
        local n = tonumber(child.Name)  -- only numeric children (skip "Default" template)
        if n then
            local cf = child:FindFirstChild('CreatureFrame',true)
            local nm, dead = '?', false
            if cf then
                local nameL = cf:FindFirstChild('NameLabel')
                local deadL = cf:FindFirstChild('DeadLabel')
                local restB = cf:FindFirstChild('RestartButton')
                if nameL then nm = nameL.Text end
                dead = (deadL and deadL.Visible==true) or (restB and restB.Visible==true) or false
            end
            out[#out+1] = {slot='Slot'..n, n=n, name=nm, dead=dead}
        end
    end
    table.sort(out, function(a,b) return a.n<b.n end)
    return out
end

local function inGame()
    local chars = Workspace:FindFirstChild('Characters')
    return chars and (chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)) and true or false
end

-- ═══ SPAWN SEQUENCE ══════════════════════════════════════════════
local function waitForSpawn(timeout)
    local t = tick()
    repeat task.wait(0.5) until inGame() or tick()-t > timeout
    return inGame()
end

local function doSpawn(slot)
    -- try replay first (most reliable), fall back to fire
    local ok
    if captured[NAME_SPAWN] then
        ok = replaySpawn()
    else
        ok = callRemote(NAME_SPAWN, slot)
    end
    if ok then
        logFn('waiting for load...')
        waitForSpawn(6)
        if STEALTH then task.wait(0.5); callRemote(NAME_INVIS,'Invisibility') end
    end
    return ok
end

local function doRestart(slot)
    callRemote(NAME_RESTART, slot, false)
    task.wait(jit(1.0,2.0))
end

-- ═══ MAIN LOOP ═══════════════════════════════════════════════════
local busy = false
task.spawn(function()
    while true do
        task.wait(1.5)
        if RUNNING and not busy and not inGame() then
            busy = true
            local slots = readSlots()
            if #slots > 0 then
                local alive
                for _,s in ipairs(slots) do if not s.dead then alive=s; break end end
                if alive then
                    logFn('ALIVE: '..alive.slot..' '..alive.name)
                    doSpawn(alive.slot)
                else
                    local s = slots[1]
                    logFn('all DEAD → restart+spawn '..s.slot)
                    doRestart(s.slot)
                    doSpawn(s.slot)
                end
            else
                logFn('no slots read (lobby not loaded yet)', true)
            end
            task.wait(jit(2.0,3.5))
            busy = false
        end
    end
end)

-- ═══ UI ══════════════════════════════════════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name='HSHub_AutoSpawn_'..math.random(1e5,1e6)
gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Parent=(gethui and gethui()) or PG
shared.__HSHub_AutoSpawn = gui

local frame = Instance.new('Frame',gui)
frame.Size=UDim2.new(0,400,0,440); frame.Position=UDim2.new(0,20,0.5,-220)
frame.BackgroundColor3=Color3.fromRGB(18,20,28); frame.BorderSizePixel=0; frame.Active=true; frame.Draggable=true
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,10)
Instance.new('UIStroke',frame).Color=Color3.fromRGB(140,100,220)

local hdr=Instance.new('Frame',frame); hdr.Size=UDim2.new(1,0,0,40); hdr.BackgroundColor3=Color3.fromRGB(110,80,190); hdr.BorderSizePixel=0
Instance.new('UICorner',hdr).CornerRadius=UDim.new(0,10)
local ttl=Instance.new('TextLabel',hdr); ttl.BackgroundTransparency=1; ttl.Size=UDim2.new(1,-48,1,0); ttl.Position=UDim2.new(0,12,0,0)
ttl.Font=Enum.Font.GothamBold; ttl.TextSize=15; ttl.TextColor3=Color3.fromRGB(245,245,250); ttl.TextXAlignment=Enum.TextXAlignment.Left; ttl.Text='HS HUB · AutoSpawn v6'
local xBtn=Instance.new('TextButton',hdr); xBtn.BackgroundTransparency=1; xBtn.Size=UDim2.new(0,36,0,36); xBtn.Position=UDim2.new(1,-40,0,2)
xBtn.Font=Enum.Font.GothamBold; xBtn.TextSize=22; xBtn.TextColor3=Color3.fromRGB(255,255,255); xBtn.Text='×'
xBtn.MouseButton1Click:Connect(function() RUNNING=false; gui:Destroy(); shared.__HSHub_AutoSpawn=nil end)

local function mkBtn(lbl,col,x,w,y)
    local b=Instance.new('TextButton',frame); b.Size=UDim2.new(0,w,0,28); b.Position=UDim2.new(0,x,0,y)
    b.BackgroundColor3=col; b.BorderSizePixel=0; b.Font=Enum.Font.GothamBold; b.TextSize=11; b.TextColor3=Color3.fromRGB(245,245,250); b.Text=lbl
    Instance.new('UICorner',b).CornerRadius=UDim.new(0,6); return b
end
local function mkTgl(lbl,x,init,cb)
    local b=mkBtn(lbl..':OFF',Color3.fromRGB(70,74,88),x,122,116); local s=init
    local function paint() b.BackgroundColor3=s and Color3.fromRGB(70,150,110) or Color3.fromRGB(70,74,88); b.Text=lbl..':'..(s and 'ON' or 'OFF') end
    paint(); b.MouseButton1Click:Connect(function() s=not s; paint(); cb(s) end)
end

local readBtn    = mkBtn('🔍 Read Slots',   Color3.fromRGB(60,130,190),  10,126, 48)
local spawnBtn   = mkBtn('▶ Spawn now',     Color3.fromRGB(60,140,120), 140,120, 48)
local restartBtn = mkBtn('↻ Restart now',   Color3.fromRGB(140,100,60), 264,126, 48)
local invisBtn   = mkBtn('👻 Invis now',    Color3.fromRGB(100,80,190),  10,126, 82)
local learnInfo  = Instance.new('TextLabel',frame); learnInfo.BackgroundTransparency=1
learnInfo.Size=UDim2.new(1,-20,0,14); learnInfo.Position=UDim2.new(0,10,0,82+28+2)
learnInfo.Font=Enum.Font.Code; learnInfo.TextSize=10; learnInfo.TextColor3=Color3.fromRGB(200,200,140)
learnInfo.TextXAlignment=Enum.TextXAlignment.Left; learnInfo.Text='Spawn learned: NO  Restart: NO  Invis: NO'
mkTgl('AutoResp', 140, AUTO_RESPAWN, function(s) AUTO_RESPAWN=s end)
mkTgl('Stealth',  266, STEALTH,      function(s) STEALTH=s end)
local startBtn = mkBtn('▶ START',Color3.fromRGB(60,150,100), 10,190,150); startBtn.Size=UDim2.new(0,190,0,30)
local stopBtn  = mkBtn('■ STOP', Color3.fromRGB(160,80,80), 208,182,150); stopBtn.Size=UDim2.new(0,182,0,30)

local scroll=Instance.new('ScrollingFrame',frame); scroll.Size=UDim2.new(1,-18,0,252); scroll.Position=UDim2.new(0,9,0,188)
scroll.BackgroundColor3=Color3.fromRGB(11,13,19); scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4
scroll.ScrollBarImageColor3=Color3.fromRGB(140,100,220)
Instance.new('UICorner',scroll).CornerRadius=UDim.new(0,6)
local ll=Instance.new('UIListLayout',scroll); ll.Padding=UDim.new(0,2); ll.SortOrder=Enum.SortOrder.LayoutOrder
local lp=Instance.new('UIPadding',scroll); lp.PaddingTop=UDim.new(0,4); lp.PaddingLeft=UDim.new(0,6)

logFn = function(txt,isErr)
    local lb=Instance.new('TextLabel',scroll); lb.BackgroundTransparency=1; lb.Size=UDim2.new(1,-12,0,15); lb.LayoutOrder=#scroll:GetChildren()
    lb.Font=Enum.Font.Code; lb.TextSize=11; lb.TextColor3=isErr and Color3.fromRGB(255,140,140) or Color3.fromRGB(185,215,235)
    lb.TextXAlignment=Enum.TextXAlignment.Left; lb.TextTruncate=Enum.TextTruncate.AtEnd; lb.Text=txt
    scroll.CanvasSize=UDim2.new(0,0,0,#scroll:GetChildren()*17); scroll.CanvasPosition=Vector2.new(0,scroll.CanvasSize.Y.Offset)
    -- update learn status
    learnInfo.Text=('Spawn:%s  Restart:%s  Invis:%s'):format(
        captured[NAME_SPAWN] and 'YES✓' or 'no', captured[NAME_RESTART] and 'YES✓' or 'no', captured[NAME_INVIS] and 'YES✓' or 'no')
end

logFn('v6. First: press Mainkan on ONE creature → hook learns the exact call.')
logFn('Then: Spawn now (uses learned call). No blackscreen issue.')

readBtn.MouseButton1Click:Connect(function()
    local slots=readSlots()
    logFn(('── slots: in_game=%s  found=%d ──'):format(tostring(inGame()),#slots),Color3.fromRGB(120,210,255))
    if #slots==0 then logFn('  NONE (is the lobby/select screen loaded?)',true) end
    for _,s in ipairs(slots) do logFn(('  %s %s %s'):format(s.slot,s.name,s.dead and 'DEAD' or 'ALIVE'), s.dead and Color3.fromRGB(255,140,140) or Color3.fromRGB(150,230,150)) end
end)
spawnBtn.MouseButton1Click:Connect(function()
    local slots=readSlots(); local target=nil
    for _,s in ipairs(slots) do if not s.dead then target=s; break end end
    if not target and #slots>0 then target=slots[1] end
    if target then task.spawn(function() doSpawn(target.slot) end)
    else logFn('no slot found — read slots first',true) end
end)
restartBtn.MouseButton1Click:Connect(function()
    local slots=readSlots()
    if slots[1] then task.spawn(function() doRestart(slots[1].slot) end)
    else logFn('no slot found',true) end
end)
invisBtn.MouseButton1Click:Connect(function() callRemote(NAME_INVIS,'Invisibility') end)
startBtn.MouseButton1Click:Connect(function()
    if RUNNING then return end
    RUNNING=true; busy=false
    logFn(('STARTED. AutoResp=%s Stealth=%s'):format(tostring(AUTO_RESPAWN),tostring(STEALTH)))
    if not captured[NAME_SPAWN] then logFn('⚠ Spawn not learned yet — press Mainkan once first!',true) end
end)
stopBtn.MouseButton1Click:Connect(function() RUNNING=false; busy=false; logFn('STOPPED.') end)
