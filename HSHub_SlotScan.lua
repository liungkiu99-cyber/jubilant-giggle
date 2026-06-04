--[[
═══════════════════════════════════════════════════════════════════════
                      HS HUB · SlotScan
     Dump the LOBBY creature-slot menu so we can read, per slot:
       • alive vs dead (MATI)   • creature name   • the SlotN id
       • the Play / Restart buttons
                    discord.gg/5rpP6faZSJ

    PURPOSE: the autonomous farm must, AT THE LOBBY, detect which of your
    creatures is alive and spawn it (or restart+spawn if all dead). To do
    that without guessing we need to know HOW the lobby stores each slot's
    state. This dumps the creature-menu GUI tree + any slot data.

    USE:
      1. Open the creature/slot menu (the screen with the slot cards + Beli Slot).
      2. Paste this script. Panel appears.
      3. Tap "⟳ Scan Lobby"  →  saves HSHub_SlotScan_*.json + clipboard.
      4. Send the JSON.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_SlotScan then pcall(function() shared.__HSHub_SlotScan:Destroy() end) end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

local NODE_CAP = 3000
local DEPTH_CAP = 10
-- "Beli Slot" + "Tukarkan" are unique to the creature-slot menu; generic words like
-- MATI also appear in other popups (e.g. DailyLogin) so we PRIORITISE the specific ones.
local STRONG_WORDS = { 'Beli Slot', 'Tukarkan', 'Mulai ulang' }
local WEAK_WORDS   = { 'Mainkan', 'MATI', 'Menghidupkan' }
-- known slot-menu GUIs (from all_guis dump) — dump these by NAME, always, regardless of text
local TARGET_GUIS  = { 'SaveSelectionGui', 'DeathGui', 'SlotOverlayGui', 'SlotSpinnerGui', 'CreatureInfoGui' }

-- ═════════════ helpers ═══════════════════════════════════════════
local function getText(inst)
    local ok, t = pcall(function() return inst.Text end)
    if ok and type(t) == 'string' and #t > 0 and #t < 80 then return t end
    return nil
end
local function attrs(inst)
    local out = nil
    pcall(function()
        for k, v in pairs(inst:GetAttributes()) do
            out = out or {}
            out[tostring(k)] = tostring(v)
        end
    end)
    return out
end
local function anyOf(s, list)
    for _, w in ipairs(list) do if s:find(w, 1, true) then return true end end
    return false
end

-- ═════════════ tree dump (node-capped) ═══════════════════════════
local nodeCount = 0
local function dumpTree(inst, depth)
    if nodeCount >= NODE_CAP or depth > DEPTH_CAP then return nil end
    nodeCount = nodeCount + 1
    local node = { name = inst.Name, class = inst.ClassName }
    local t = getText(inst); if t then node.text = t end
    local a = attrs(inst); if a then node.attrs = a end
    pcall(function()
        if inst:IsA('GuiObject') then node.visible = inst.Visible end
    end)
    -- numeric values (slot ids often live in Value objects)
    if inst:IsA('ValueBase') then pcall(function() node.value = tostring(inst.Value) end) end
    local kids = inst:GetChildren()
    if #kids > 0 then
        local cl = {}
        for _, c in ipairs(kids) do
            local cn = dumpTree(c, depth + 1)
            if cn then cl[#cl + 1] = cn end
            if nodeCount >= NODE_CAP then break end
        end
        if #cl > 0 then node.children = cl end
    end
    return node
end

-- ═════════════ gather GUI roots (PlayerGui + gethui + CoreGui) ════
local function guiRoots()
    local roots = {}
    roots[#roots + 1] = PG
    pcall(function() if gethui then local h = gethui(); if h and h ~= PG then roots[#roots + 1] = h end end end)
    pcall(function() roots[#roots + 1] = game:GetService('CoreGui') end)
    return roots
end

-- list every top-level ScreenGui/Folder under all roots (so we always see what exists)
local function allGuis()
    local out = {}
    for _, r in ipairs(guiRoots()) do
        pcall(function()
            for _, sg in ipairs(r:GetChildren()) do
                out[#out + 1] = { name = sg.Name, class = sg.ClassName, parent = r.Name }
            end
        end)
    end
    return out
end

-- find the creature-slot menu: STRONG word match wins; else WEAK. Returns matches with score.
local function findMenus()
    local out = {}
    for _, r in ipairs(guiRoots()) do
        pcall(function()
            for _, sg in ipairs(r:GetChildren()) do
                if sg:IsA('ScreenGui') or sg:IsA('Folder') then
                    local strong, weak = false, false
                    pcall(function()
                        for _, d in ipairs(sg:GetDescendants()) do
                            local tx = getText(d)
                            if tx then
                                if anyOf(tx, STRONG_WORDS) then strong = true
                                elseif anyOf(tx, WEAK_WORDS) then weak = true end
                            end
                        end
                    end)
                    if strong then out[#out + 1] = { gui = sg, score = 2 }
                    elseif weak then out[#out + 1] = { gui = sg, score = 1 } end
                end
            end
        end)
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    return out
end

-- ═════════════ slot-card heuristic ═══════════════════════════════
-- a "slot card" = a GuiObject subtree that contains a MATI/Mainkan/Mulai-ulang
-- label AND (usually) a creature-name-ish label. Report compact summary per card.
local function collectSlotCards(root)
    local cards = {}
    pcall(function()
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA('GuiObject') then
                local matiL, playL, restartL, reviveL, tradeL = nil, nil, nil, nil, nil
                local texts = {}
                for _, c in ipairs(d:GetDescendants()) do
                    local tx = getText(c)
                    if tx then
                        if tx:find('MATI', 1, true) then matiL = true end
                        if tx:find('Mainkan', 1, true) then playL = true end
                        if tx:find('Mulai ulang', 1, true) then restartL = true end
                        if tx:find('Menghidupkan', 1, true) then reviveL = true end
                        if tx:find('Tukarkan', 1, true) then tradeL = true end
                        if #texts < 8 then texts[#texts + 1] = tx end
                    end
                end
                -- a card has play OR restart OR mati + isn't the whole menu
                if (playL or restartL or matiL or tradeL) and #d:GetChildren() < 40 then
                    cards[#cards + 1] = {
                        path = d:GetFullName(),
                        name = d.Name,
                        dead = matiL == true,
                        has_play = playL == true,
                        has_restart = restartL == true,
                        has_revive = reviveL == true,
                        has_trade = tradeL == true,
                        attrs = attrs(d),
                        texts = texts,
                    }
                end
            end
            if #cards >= 40 then break end
        end
    end)
    return cards
end

-- ═════════════ in-game vs lobby ══════════════════════════════════
local function inGame()
    local chars = Workspace:FindFirstChild('Characters')
    if chars then
        if chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName) then return true end
    end
    return false
end

-- ═════════════ LP children (slot data may live here) ═════════════
local function lpChildren()
    local out = {}
    pcall(function()
        for _, c in ipairs(LP:GetChildren()) do
            out[#out + 1] = { name = c.Name, class = c.ClassName, attrs = attrs(c) }
        end
    end)
    return out
end

-- ═════════════ JSON ══════════════════════════════════════════════
local function toJSON(v, indent)
    indent = indent or 0
    local pad1 = string.rep('  ', indent + 1)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' or t == 'number' then return tostring(v) end
    if t == 'string' then return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"' end
    if t == 'table' then
        local isArr, maxK = true, 0
        for k in pairs(v) do if type(k) ~= 'number' then isArr = false; break end; if k > maxK then maxK = k end end
        if isArr and maxK > 0 then
            local p = {}; for i = 1, maxK do p[i] = toJSON(v[i], indent + 1) end
            return '[\n' .. pad1 .. table.concat(p, ',\n' .. pad1) .. '\n' .. string.rep('  ', indent) .. ']'
        else
            local p = {}; for k, val in pairs(v) do p[#p + 1] = '"' .. tostring(k) .. '": ' .. toJSON(val, indent + 1) end
            if #p == 0 then return '{}' end
            return '{\n' .. pad1 .. table.concat(p, ',\n' .. pad1) .. '\n' .. string.rep('  ', indent) .. '}'
        end
    end
    return '"<' .. t .. '>"'
end

local function doScan()
    nodeCount = 0
    local menus = findMenus()
    local topScore = menus[1] and menus[1].score or 0
    local menuTrees, slotCards, dumpedNames = {}, {}, {}
    local seen = {}
    local function dumpGui(g)
        if not g or seen[g] then return end
        seen[g] = true
        menuTrees[#menuTrees + 1] = dumpTree(g, 0)
        dumpedNames[#dumpedNames + 1] = g.Name
        for _, card in ipairs(collectSlotCards(g)) do slotCards[#slotCards + 1] = card end
    end
    -- 1) ALWAYS dump the known slot-menu GUIs by name (across all roots)
    for _, r in ipairs(guiRoots()) do
        for _, want in ipairs(TARGET_GUIS) do
            pcall(function() dumpGui(r:FindFirstChild(want)) end)
        end
    end
    -- 2) also dump the strongest text-matched menu (covers renamed/unknown menus)
    for _, m in ipairs(menus) do
        if m.score == topScore then dumpGui(m.gui) end
    end
    local report = {
        time = os.date('%Y-%m-%d %H:%M:%S'),
        place_id = game.PlaceId,
        in_game = inGame(),
        menu_count = #menus,
        dumped = dumpedNames,
        top_score = topScore,   -- 2 = found the real slot menu (Beli Slot/Tukarkan), 1 = weak, 0 = none
        all_guis = allGuis(),
        node_count = nodeCount,
        slot_cards = slotCards,
        lp_children = lpChildren(),
        menu_trees = menuTrees,
    }
    local json = toJSON(report)
    local path = ('HSHub_SlotScan_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    return saved, path, #slotCards, #menus, topScore
end

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_SlotScan_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_SlotScan = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 380, 0, 320); frame.Position = UDim2.new(0, 20, 0.4, -160)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28); frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame); stroke.Color = Color3.fromRGB(90, 180, 220); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 44); header.BackgroundColor3 = Color3.fromRGB(70, 150, 200); header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -56, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · SlotScan'
local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -44, 0, 2)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() gui:Destroy(); shared.__HSHub_SlotScan = nil end)

local scanBtn = Instance.new('TextButton', frame)
scanBtn.Size = UDim2.new(1, -28, 0, 36); scanBtn.Position = UDim2.new(0, 14, 0, 54)
scanBtn.BackgroundColor3 = Color3.fromRGB(70, 150, 110); scanBtn.BorderSizePixel = 0
scanBtn.Font = Enum.Font.GothamBold; scanBtn.TextSize = 14; scanBtn.TextColor3 = Color3.fromRGB(245, 245, 250); scanBtn.Text = '⟳ Scan Lobby'
Instance.new('UICorner', scanBtn).CornerRadius = UDim.new(0, 6)

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 200); scroll.Position = UDim2.new(0, 10, 0, 100)
scroll.BackgroundColor3 = Color3.fromRGB(12, 14, 20); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 180, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lay = Instance.new('UIListLayout', scroll); lay.Padding = UDim.new(0, 2); lay.SortOrder = Enum.SortOrder.LayoutOrder
local lpd = Instance.new('UIPadding', scroll); lpd.PaddingTop = UDim.new(0, 4); lpd.PaddingLeft = UDim.new(0, 6)
local function logRow(text, color)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -12, 0, 15); lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 10; lbl.TextColor3 = color or Color3.fromRGB(180, 210, 230)
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 17)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end
logRow('Open the slot menu (cards + Beli Slot) then tap Scan.', Color3.fromRGB(200, 210, 150))

scanBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(scroll:GetChildren()) do if c:IsA('TextLabel') then c:Destroy() end end
    local saved, path, ncards, nmenus, topScore = doScan()
    logRow(('top_score=%d  slot_cards=%d  nodes=%d  in_game=%s'):format(topScore, ncards, nodeCount, tostring(inGame())),
        topScore >= 2 and Color3.fromRGB(170, 230, 180) or Color3.fromRGB(255, 200, 120))
    logRow(saved and ('Saved: workspace/' .. path) or 'Save FAILED (no writefile)', Color3.fromRGB(170, 230, 180))
    logRow('JSON also in clipboard. Send it.', Color3.fromRGB(180, 220, 255))
    if topScore < 2 then
        logRow('⚠ slot menu NOT found (no "Beli Slot"/"Tukarkan"). OPEN the creature', Color3.fromRGB(255, 150, 150))
        logRow('  menu (close the daily-login popup) then Scan again.', Color3.fromRGB(255, 150, 150))
    end
end)
