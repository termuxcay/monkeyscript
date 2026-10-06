if _G.MonkeySuite and _G.MonkeySuite.Cleanup then pcall(_G.MonkeySuite.Cleanup) end

local Running = true
local Drawings = {}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = game.Workspace.CurrentCamera

local DODGE_MARGIN = 4
local DODGE_DIST = 22
local DODGE_COOLDOWN = 0.4
local MAX_ENGAGE_DIST = 150
local MIN_TARGET_DIST = 12
local SCREEN_Y_OFFSET = 24
local AIM_MOVE_THROTTLE = 0.1
local AIM_MIN_MOVE_PX = 3
local USER_OVERRIDE_PX = 50
local USER_OVERRIDE_TIME = 1.5
local F1_KEY = 112

local function notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title or "Monkey Suite", Text = text or "", Duration = duration or 3 })
    end)
end

local State = {
    Minimized = false,
    AutoShoot = false,
    AntiBomb = false,
    InfJump = false,
    NoClip = false, Fly = false, FlySpeed = 60,
    StatusText = "",
}
local TAB_MAIN, TAB_COMBAT, TAB_MOVE = 1, 2, 3
State.ActiveTab = TAB_MAIN

local GEN = (tonumber(_G.MonkeySuiteGen) or 0) + 1
_G.MonkeySuiteGen = GEN

local MenuBusyUntil = 0
local ShooterHolding = false
local syntheticPressActive = false
local userOverrideUntil = 0
local expectX, expectY = nil, nil
local lastScriptMove = 0
local lastF1 = false
local lastAimMove = 0
local lastAimX, lastAimY = -9999, -9999
local shootTime0, shootKills0 = 0, 0

local isFiring = false
local function releaseFire()
    if isFiring then
        pcall(mouse1release)
        isFiring = false
    end
    ShooterHolding = false
end
local function holdFire()
    if not isFiring then
        ShooterHolding = true
        pcall(mouse1press)
        isFiring = true
    end
end

local function readKills()
    local ok, v = pcall(function() return LocalPlayer.leaderstats.Kills.Value end)
    if ok and v then return v end
    return nil
end

local function armShootStats()
    shootTime0 = os.clock()
    local k = readKills()
    shootKills0 = k or 0
end

local function killsPerMin()
    local k = readKills()
    if not k then return nil end
    local el = os.clock() - shootTime0
    if el < 5 then return nil end
    return math.floor((k - shootKills0) / el * 60)
end

_G.MonkeySuite = {
    Cleanup = function()
        Running = false
        State.Fly = false; State.NoClip = false
        releaseFire()
        for _, d in ipairs(Drawings) do pcall(function() d:Remove() end) end
        Drawings = {}
    end,
    State = State,
    Set = function(k, v) State[k] = v end,
    Get = function(k) return State[k] end,
}

local UI = {
    Bg = Color3.fromRGB(13, 14, 21), HeaderBg = Color3.fromRGB(18, 20, 30),
    Border = Color3.fromRGB(42, 46, 62), BorderGlow = Color3.fromRGB(147, 51, 234),
    Box = Color3.fromRGB(22, 24, 34), BoxBorder = Color3.fromRGB(40, 44, 60),
    BoxHover = Color3.fromRGB(32, 35, 48), HoverBorder = Color3.fromRGB(60, 65, 85),
    ActiveBox = Color3.fromRGB(147, 51, 234), ActiveBdr = Color3.fromRGB(192, 132, 252),
    ActiveHov = Color3.fromRGB(168, 85, 247),
    TxtMain = Color3.fromRGB(240, 243, 255), TxtSec = Color3.fromRGB(185, 190, 205),
    TxtMuted = Color3.fromRGB(130, 135, 155), TxtActive = Color3.fromRGB(255, 255, 255),
    StatusOn = Color3.fromRGB(74, 222, 128),
    TabActive = Color3.fromRGB(40, 44, 60),
}
local UI_FONT = 2

local function WrapDraw(dType, rx, ry, rw, rh, props)
    local d = Drawing.new(dType)
    table.insert(Drawings, d)
    local w = { draw = d, rx = rx or 0, ry = ry or 0, rw = rw or 0, rh = rh or 0,
        lastX = -9999, lastY = -9999, lastW = -9999, lastH = -9999,
        lastColor = nil, lastTrans = -1, lastVis = false, lastFont = -1,
        lastRadius = -1, lastText = nil }
    if props then
        for k, v in pairs(props) do
            d[k] = v
            if k == "Color" then w.lastColor = v
            elseif k == "Transparency" then w.lastTrans = v
            elseif k == "Visible" then w.lastVis = v
            elseif k == "Size" and type(v) == "number" then w.lastFont = v
            elseif k == "Radius" then w.lastRadius = v
            elseif k == "Text" then w.lastText = v end
        end
    end
    return w
end
local function SetPos(e, x, y) if e.lastX ~= x or e.lastY ~= y then e.lastX, e.lastY = x, y; e.draw.Position = Vector2.new(x, y) end end
local function SetSize(e, w, h) if e.lastW ~= w or e.lastH ~= h then e.lastW, e.lastH = w, h; e.draw.Size = Vector2.new(w, h) end end
local function SetColor(e, c) if e.lastColor ~= c then e.lastColor = c; e.draw.Color = c end end
local function SetVisible(e, v) if e.lastVis ~= v then e.lastVis = v; e.draw.Visible = v end end
local function SetText(e, t) if e.lastText ~= t then e.lastText = t; e.draw.Text = t end end
local function SetRadius(e, r) if math.abs(e.lastRadius - r) > 0.05 then e.lastRadius = r; e.draw.Radius = r end end

local GW, GH = 350, 330
local MINI_W, MINI_H = 300, 34
local GuiX, GuiY, TargetX, TargetY = 60, 80, 60, 80
local isDragging = false
local dragOffX, dragOffY = 0, 0

local mainGlow   = WrapDraw("Square", -3, -3, GW + 6, GH + 6, { Filled = false, Thickness = 1.5, Color = UI.BorderGlow, Transparency = 0.65, Visible = true })
local mainBorder = WrapDraw("Square", -1, -1, GW + 2, GH + 2, { Filled = false, Thickness = 1, Rounding = 8, Color = UI.Border, Transparency = 1, Visible = true })
local mainBg     = WrapDraw("Square", 0, 0, GW, GH, { Filled = true, Rounding = 8, Color = UI.Bg, Transparency = 1, Visible = true })
local headerBg   = WrapDraw("Square", 0, 0, GW, 42, { Filled = true, Rounding = 8, Color = UI.HeaderBg, Transparency = 1, Visible = true })
local headerLine = WrapDraw("Square", 0, 42, GW, 2, { Filled = true, Color = UI.ActiveBox, Transparency = 1, Visible = true })
local statusHalo = WrapDraw("Circle", 17, 21, 0, 0, { Radius = 7, Filled = false, Thickness = 1.5, Color = UI.ActiveBdr, Transparency = 0.8, Visible = true })
local statusCore = WrapDraw("Circle", 17, 21, 0, 0, { Radius = 4, Filled = true, Color = UI.ActiveBdr, Transparency = 1, Visible = true })
local titleText  = WrapDraw("Text", 31, 12, 0, 0, { Size = 14, Font = UI_FONT, Outline = true, Color = UI.TxtMain, Text = "MONKEY SUITE // TXBAT", Visible = true })
local minBtn     = WrapDraw("Text", GW - 30, 13, 0, 0, { Size = 16, Font = UI_FONT, Outline = true, Color = UI.TxtMuted, Text = "[-]", Visible = true })
local statusHdr  = WrapDraw("Text", 0, 15, 0, 0, { Size = 11, Font = UI_FONT, Outline = true, Color = UI.StatusOn, Text = "", Visible = true })

local miniGlow  = WrapDraw("Square", -2, -2, MINI_W + 4, MINI_H + 4, { Filled = false, Thickness = 1.5, Color = UI.BorderGlow, Transparency = 0.6, Visible = false })
local miniBg    = WrapDraw("Square", 0, 0, MINI_W, MINI_H, { Filled = true, Rounding = 8, Color = UI.HeaderBg, Transparency = 1, Visible = false })
local miniBrd   = WrapDraw("Square", 0, 0, MINI_W, MINI_H, { Filled = false, Thickness = 1, Rounding = 8, Color = UI.ActiveBdr, Transparency = 0.9, Visible = false })
local miniHalo  = WrapDraw("Circle", 16, 17, 0, 0, { Radius = 5, Filled = true, Color = UI.ActiveBdr, Transparency = 1, Visible = false })
local miniTitle = WrapDraw("Text", 30, 9, 0, 0, { Size = 13, Font = UI_FONT, Outline = true, Color = UI.TxtMain, Text = "MONKEY SUITE // BY: TXBAT", Visible = false })
local miniPlus  = WrapDraw("Text", MINI_W - 32, 8, 0, 0, { Size = 16, Font = UI_FONT, Outline = true, Color = UI.ActiveBdr, Text = "[+]", Visible = false })

local cursorRing = WrapDraw("Circle", 0, 0, 0, 0, { Radius = 9, Filled = false, Thickness = 1.5, Color = UI.ActiveBdr, Transparency = 1, Visible = false })
local cursorDot  = WrapDraw("Circle", 0, 0, 0, 0, { Radius = 2, Filled = true, Color = UI.TxtActive, Transparency = 1, Visible = false })

local tabNames = { [TAB_MAIN] = "MAIN", [TAB_COMBAT] = "COMBAT", [TAB_MOVE] = "MOVEMENT" }
local tabButtons = {}
local tabW = (GW - 16) / 3
for i = 1, 3 do
    local bx = 8 + (i - 1) * tabW
    local box = WrapDraw("Square", bx, 50, tabW - 4, 26, { Filled = true, Rounding = 5, Color = UI.Box, Transparency = 1, Visible = true })
    local txt = WrapDraw("Text", bx + 8, 56, 0, 0, { Size = 12, Font = UI_FONT, Outline = true, Color = UI.TxtSec, Text = tabNames[i], Visible = true })
    tabButtons[i] = { box = box, txt = txt, rx = bx, ry = 50, rw = tabW - 4, rh = 26 }
end

local Buttons = {}
local function CreateBtn(tab, opt)
    local bw = opt.w or (GW - 20)
    local bh = opt.h or 32
    local btn = {
        tab = tab, rx = opt.x or 10, ry = opt.y, rw = bw, rh = bh,
        box = WrapDraw("Square", opt.x or 10, opt.y, bw, bh, { Filled = true, Rounding = 6, Color = UI.Box, Transparency = 1, Visible = true }),
        border = WrapDraw("Square", opt.x or 10, opt.y, bw, bh, { Filled = false, Thickness = 1, Rounding = 6, Color = UI.BoxBorder, Transparency = 0.85, Visible = true }),
        label = WrapDraw("Text", (opt.x or 10) + 12, opt.y + 7, 0, 0, { Size = 13, Font = UI_FONT, Outline = true, Color = UI.TxtMain, Text = opt.text or "", Visible = true }),
        onClick = opt.onClick,
    }
    table.insert(Buttons, btn)
    return btn
end

local SavedSpot = nil
local lastDodge = 0

local function readMarks()
    local marks = {}
    local aoe = game.Workspace:FindFirstChild("AoeMarks")
    if aoe then
        for _, m in ipairs(aoe:GetChildren()) do
            local ok1, p = pcall(function() return m.Position end)
            local ok2, s = pcall(function() return m.Size end)
            if ok1 and p and ok2 and s then
                table.insert(marks, { x = p.X, z = p.Z, hx = s.X / 2 + DODGE_MARGIN, hz = s.Z / 2 + DODGE_MARGIN })
            end
        end
    end
    return marks
end

local function insideAnyMark(x, z, marks)
    for _, mk in ipairs(marks) do
        if math.abs(x - mk.x) <= mk.hx and math.abs(z - mk.z) <= mk.hz then
            return true
        end
    end
    return false
end

local function nearCombat(x, z, radius)
    local ex = game.Workspace:FindFirstChild("ExplosionVFX")
    if ex then
        for _, p in ipairs(ex:GetChildren()) do
            local ok, pp = pcall(function() return p.Position end)
            if ok and pp then
                local d = math.sqrt((pp.X - x) ^ 2 + (pp.Z - z) ^ 2)
                if d < radius then return true end
            end
        end
    end
    return false
end

local function combatDist(x, z)
    local best = math.huge
    local ex = game.Workspace:FindFirstChild("ExplosionVFX")
    if ex then
        for _, p in ipairs(ex:GetChildren()) do
            local ok, pp = pcall(function() return p.Position end)
            if ok and pp then
                local d = math.sqrt((pp.X - x) ^ 2 + (pp.Z - z) ^ 2)
                if d < best then best = d end
            end
        end
    end
    return best
end

local function findEscape(pos, dist)
    local marks = readMarks()
    local bestCx, bestCz, bestScore = nil, nil, -1
    for i = 0, 7 do
        local ang = (i / 8) * math.pi * 2
        local cx = pos.X + math.cos(ang) * dist
        local cz = pos.Z + math.sin(ang) * dist
        if not insideAnyMark(cx, cz, marks) then
            local cd = combatDist(cx, cz)
            if cd > bestScore then
                bestScore = cd
                bestCx, bestCz = cx, cz
            end
            if cd >= 25 then
                return cx, cz
            end
        end
    end
    if bestCx and bestScore >= 10 then
        return bestCx, bestCz
    end
    return nil, nil
end

local function findTarget(hr)
    local best, bd = nil, math.huge
    local ex = game.Workspace:FindFirstChild("ExplosionVFX")
    if hr and ex then
        for _, p in ipairs(ex:GetChildren()) do
            local ok, pos = pcall(function() return p.Position end)
            if ok and pos then
                local d = (pos - hr.Position).Magnitude
                if d >= MIN_TARGET_DIST and d < bd and d < MAX_ENGAGE_DIST then bd = d; best = pos end
            end
        end
    end
    return best, bd
end

local function projectToScreen(worldPos)
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local camRight = Camera.CFrame.RightVector
    local camUp = Camera.CFrame.UpVector
    local vp = Camera.ViewportSize
    local fovY = 70
    pcall(function() fovY = Camera.FieldOfView end)
    local f = (vp.Y / 2) / math.tan(math.rad(fovY) / 2)
    local off = worldPos - camPos
    local depth = camLook:Dot(off)
    if depth <= 0.5 then return nil, nil end
    local sx = vp.X / 2 + (camRight:Dot(off) / depth) * f
    local sy = vp.Y / 2 - (camUp:Dot(off) / depth) * f
    if sx < -100 or sx > vp.X + 100 or sy < -100 or sy > vp.Y + 100 then
        return nil, nil
    end
    return sx, sy
end

local function cursorOverMenu(mx, my)
    if State.Minimized then
        return mx >= GuiX and mx <= GuiX + MINI_W and my >= GuiY and my <= GuiY + MINI_H
    end
    return mx >= GuiX and mx <= GuiX + GW and my >= GuiY and my <= GuiY + GH
end

local function getMonkeysLeft()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local g = pg and pg:FindFirstChild("Game")
    if not g then return nil end
    for _, c in ipairs(g:GetDescendants()) do
        if c.ClassName == "TextLabel" then
            local ok, t = pcall(function() return c.Text end)
            if ok and t and string.find(string.lower(t), "monkey") then
                local n = string.match(t, "(%d+)")
                if n then return n end
            end
        end
    end
    return nil
end

local function toggleShoot(on)
    if on == nil then on = not State.AutoShoot end
    State.AutoShoot = on
    if on then
        armShootStats()
        notify("Auto Shoot", "ON (F1)", 2)
    else
        releaseFire()
        notify("Auto Shoot", "OFF (F1)", 2)
    end
    print("F1_TOGGLE AutoShoot=" .. tostring(State.AutoShoot))
end

local btnShoot = CreateBtn(TAB_MAIN, { y = 88, text = "Auto Shoot Monkeys [F1]", onClick = function()
    toggleShoot()
end })
local btnDodge = CreateBtn(TAB_MAIN, { y = 126, text = "Anti Explosions", onClick = function()
    State.AntiBomb = not State.AntiBomb
    if State.AntiBomb then notify("Anti Explosions", "ON - dodging banana AoE", 2) end
end })
local btnPanic = CreateBtn(TAB_MAIN, { y = 164, text = "Panic TP (Safe)", onClick = function()
    local char = LocalPlayer.Character
    local hr = char and char:FindFirstChild("HumanoidRootPart")
    if hr then
        local cx, cz = findEscape(hr.Position, 30)
        if cx then
            hr.CFrame = CFrame.new(cx, hr.Position.Y + 1, cz)
            State.StatusText = "PANIC: safe spot"
        else
            State.StatusText = "PANIC: no safe spot!"
        end
    end
end })

local btnSave = CreateBtn(TAB_COMBAT, { y = 88, text = "Save Safe Spot", onClick = function()
    local char = LocalPlayer.Character
    local hr = char and char:FindFirstChild("HumanoidRootPart")
    if hr then
        SavedSpot = { x = hr.Position.X, y = hr.Position.Y, z = hr.Position.Z }
        notify("Safe Spot", "Position saved", 2)
    end
end })
local btnSpot = CreateBtn(TAB_COMBAT, { y = 126, text = "TP Safe Spot", onClick = function()
    local char = LocalPlayer.Character
    local hr = char and char:FindFirstChild("HumanoidRootPart")
    if hr and SavedSpot then
        local marks = readMarks()
        if insideAnyMark(SavedSpot.x, SavedSpot.z, marks) or nearCombat(SavedSpot.x, SavedSpot.z, 18) then
            State.StatusText = "SPOT: unsafe now!"
            notify("Safe Spot", "Danger there - TP blocked", 2)
        else
            hr.CFrame = CFrame.new(SavedSpot.x, SavedSpot.y + 1, SavedSpot.z)
            State.StatusText = "SPOT: teleported"
        end
    elseif not SavedSpot then
        notify("Safe Spot", "Save a spot first", 2)
    end
end })

local btnFly = CreateBtn(TAB_MOVE, { y = 88, text = "Fly (WASD + Space/C)", onClick = function() State.Fly = not State.Fly end })
local btnNoclip = CreateBtn(TAB_MOVE, { y = 126, text = "NoClip", onClick = function()
    State.NoClip = not State.NoClip
    if not State.NoClip then
        local ch = LocalPlayer.Character
        if ch then for _, p in ipairs(ch:GetChildren()) do
            if p.ClassName == "Part" or p.ClassName == "MeshPart" then pcall(function() p.CanCollide = true end) end
        end end
    end
end })
local btnJump = CreateBtn(TAB_MOVE, { y = 164, text = "Infinite Jump", onClick = function() State.InfJump = not State.InfJump end })

local function inRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end
local function handleTabClick(mx, my)
    for i, tb in ipairs(tabButtons) do
        if inRect(mx, my, GuiX + tb.rx, GuiY + tb.ry, tb.rw, tb.rh) then
            State.ActiveTab = i
            return true
        end
    end
    return false
end
local function handleBtnClick(mx, my)
    for _, btn in ipairs(Buttons) do
        if btn.tab == State.ActiveTab then
            if inRect(mx, my, GuiX + btn.rx, GuiY + btn.ry, btn.rw, btn.rh) then
                pcall(btn.onClick)
                return true
            end
        end
    end
    return false
end

local wasPressed = false

RunService.Heartbeat:Connect(function()
    if _G.MonkeySuiteGen ~= GEN then return end
    if State.NoClip then
        local char = LocalPlayer.Character
        if char then
            for _, p in ipairs(char:GetChildren()) do
                if p.ClassName == "Part" or p.ClassName == "MeshPart" then
                    if p.CanCollide then p.CanCollide = false end
                end
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if _G.MonkeySuiteGen ~= GEN then return end
    if not State.Fly then return end
    local char = LocalPlayer.Character
    local hr = char and char:FindFirstChild("HumanoidRootPart")
    if not hr then return end
    local cf = Camera.CFrame
    local lv, rv = cf.LookVector, cf.RightVector
    local mx, my, mz = 0, 0, 0
    if iskeypressed(87) or iskeypressed(119) then mx = mx + lv.X; my = my + lv.Y; mz = mz + lv.Z end
    if iskeypressed(83) or iskeypressed(115) then mx = mx - lv.X; my = my - lv.Y; mz = mz - lv.Z end
    if iskeypressed(68) or iskeypressed(100) then mx = mx + rv.X; mz = mz + rv.Z end
    if iskeypressed(65) or iskeypressed(97)  then mx = mx - rv.X; mz = mz - rv.Z end
    if iskeypressed(32) or iskeypressed(32)  then my = my + 1 end
    if iskeypressed(67) or iskeypressed(99)  then my = my - 1 end
    local moveSq = mx * mx + my * my + mz * mz
    if moveSq > 0 then
        local inv = 1 / math.sqrt(moveSq)
        local spd = State.FlySpeed
        hr.AssemblyLinearVelocity = Vector3.new(mx * inv * spd, my * inv * spd, mz * inv * spd)
    else
        hr.AssemblyLinearVelocity = Vector3.zero
    end
end)

task.spawn(function()
    while Running do
        if _G.MonkeySuiteGen ~= GEN then break end
        if State.AutoShoot then
            if os.clock() < MenuBusyUntil then
                releaseFire()
            else
                local char = LocalPlayer.Character
                local hr = char and char:FindFirstChild("HumanoidRootPart")
                if not hr then
                    releaseFire()
                else
                    local target, dist = findTarget(hr)
                    if target then
                        local sx, sy = projectToScreen(target)
                        if sx and sy then
                            local mx, my = Mouse.X, Mouse.Y
                            local now3 = os.clock()
                            local userHolding = false
                            if expectX and (now3 - lastScriptMove) > 0.3 then
                                if math.abs(mx - expectX) > USER_OVERRIDE_PX or math.abs(my - expectY) > USER_OVERRIDE_PX then
                                    expectX, expectY = mx, my
                                    lastAimX, lastAimY = sx, sy
                                    userHolding = true
                                    releaseFire()
                                    State.StatusText = "SHOOT: paused (your mouse)"
                                end
                            end
                            if not userHolding then
                                if not cursorOverMenu(mx, my) then
                                    if (math.abs(sx - lastAimX) > AIM_MIN_MOVE_PX or math.abs(sy - lastAimY) > AIM_MIN_MOVE_PX) and (now3 - lastAimMove) > AIM_MOVE_THROTTLE then
                                        lastAimMove = now3; lastAimX, lastAimY = sx, sy
                                        expectX, expectY = sx, sy
                                        lastScriptMove = now3
                                        pcall(mousemoveabs, sx, sy + SCREEN_Y_OFFSET)
                                    end
                                end
                                holdFire()
                                local kpm = killsPerMin()
                                State.StatusText = "SHOOT: " .. string.format("%.0f", dist) .. "m" .. (kpm and (" | " .. kpm .. "/min") or "")
                            end
                        else
                            releaseFire()
                            State.StatusText = "SHOOT: target offscreen"
                        end
                    else
                        releaseFire()
                        local left = getMonkeysLeft()
                        State.StatusText = left and ("SHOOT: (" .. left .. " left)") or "SHOOT: scanning"
                    end
                end
            end
        else
            releaseFire()
        end
        task.wait(0.1)
    end
end)

task.spawn(function()
    while Running do
        if _G.MonkeySuiteGen ~= GEN then break end
        if State.AntiBomb then
            local char = LocalPlayer.Character
            local hr = char and char:FindFirstChild("HumanoidRootPart")
            if hr then
                local pos = hr.Position
                local marks = readMarks()
                local inside = insideAnyMark(pos.X, pos.Z, marks)
                local now = os.clock()
                if inside and (now - lastDodge) > DODGE_COOLDOWN then
                    local cx, cz = findEscape(pos, DODGE_DIST)
                    if cx then
                        lastDodge = now
                        hr.CFrame = CFrame.new(cx, pos.Y + 1, cz)
                        State.StatusText = "DODGE!"
                    else
                        State.StatusText = "DODGE: no safe spot!"
                    end
                end
            end
        end
        task.wait(0.12)
    end
end)

RunService.RenderStepped:Connect(function()
    if _G.MonkeySuiteGen ~= GEN then return end
    local now = os.clock()

    local f1down = false
    pcall(function() f1down = iskeypressed(F1_KEY) end)
    if f1down and not lastF1 then
        toggleShoot()
    end
    lastF1 = f1down

    local pressed = ismouse1pressed()
    local mx, my = Mouse.X, Mouse.Y

    local __overMenu = cursorOverMenu(mx, my)
    SetVisible(cursorRing, __overMenu)
    SetVisible(cursorDot, __overMenu)
    if __overMenu then SetPos(cursorRing, mx, my); SetPos(cursorDot, mx, my) end

    if pressed and not wasPressed then
        local overMenu = cursorOverMenu(mx, my)
        if ShooterHolding and not overMenu then
            syntheticPressActive = true
        else
            syntheticPressActive = false
            MenuBusyUntil = now + 0.6
            if State.Minimized then
                if inRect(mx, my, GuiX + MINI_W - 36, GuiY + 2, 34, 30) then
                    State.Minimized = false
                elseif inRect(mx, my, GuiX, GuiY, MINI_W, MINI_H) then
                    isDragging = true
                    dragOffX, dragOffY = mx - GuiX, my - GuiY
                end
            else
                if inRect(mx, my, GuiX, GuiY, GW, 42) then
                    if inRect(mx, my, GuiX + GW - 34, GuiY + 4, 30, 30) then
                        State.Minimized = true
                    else
                        isDragging = true
                        dragOffX, dragOffY = mx - GuiX, my - GuiY
                    end
                elseif not handleTabClick(mx, my) and not handleBtnClick(mx, my) then
                    if not inRect(mx, my, GuiX, GuiY, GW, GH) then
                        if State.InfJump then
                            local char = LocalPlayer.Character
                            local hr = char and char:FindFirstChild("HumanoidRootPart")
                            if hr then
                                local vel = hr.AssemblyLinearVelocity
                                if vel.Y < 4 then
                                    hr.AssemblyLinearVelocity = Vector3.new(vel.X, 55, vel.Z)
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif not pressed and wasPressed then
        if syntheticPressActive then
            syntheticPressActive = false
        else
            isDragging = false
            MenuBusyUntil = now + 0.3
        end
    end
    wasPressed = pressed

    if isDragging then
        MenuBusyUntil = now + 0.5
        local vp = Camera.ViewportSize
        local maxW = State.Minimized and MINI_W or GW
        local maxH = State.Minimized and MINI_H or GH
        TargetX = math.clamp(mx - dragOffX, 5, math.max(10, vp.X - maxW - 5))
        TargetY = math.clamp(my - dragOffY, 5, math.max(10, vp.Y - maxH - 5))
    end
    GuiX = GuiX + (TargetX - GuiX) * 0.35
    GuiY = GuiY + (TargetY - GuiY) * 0.35
    if math.abs(TargetX - GuiX) < 0.5 then GuiX = TargetX end
    if math.abs(TargetY - GuiY) < 0.5 then GuiY = TargetY end

    local pulse = (math.sin(now * 3.2) + 1) * 0.5

    if State.Minimized then
        SetVisible(miniGlow, true);  SetPos(miniGlow, GuiX - 2, GuiY - 2);  SetSize(miniGlow, MINI_W + 4, MINI_H + 4)
        SetVisible(miniBg, true);    SetPos(miniBg, GuiX, GuiY);            SetSize(miniBg, MINI_W, MINI_H)
        SetVisible(miniBrd, true);   SetPos(miniBrd, GuiX, GuiY);           SetSize(miniBrd, MINI_W, MINI_H)
        SetVisible(miniHalo, true);  SetPos(miniHalo, GuiX + 16, GuiY + 17); SetRadius(miniHalo, 5 + pulse * 1)
        SetVisible(miniTitle, true); SetPos(miniTitle, GuiX + 30, GuiY + 9)
        SetVisible(miniPlus, true);  SetPos(miniPlus, GuiX + MINI_W - 32, GuiY + 8)
        SetVisible(mainGlow, false); SetVisible(mainBorder, false); SetVisible(mainBg, false)
        SetVisible(headerBg, false); SetVisible(headerLine, false)
        SetVisible(statusHalo, false); SetVisible(statusCore, false)
        SetVisible(titleText, false); SetVisible(minBtn, false); SetVisible(statusHdr, false)
        for _, tb in ipairs(tabButtons) do SetVisible(tb.box, false); SetVisible(tb.txt, false) end
        for _, btn in ipairs(Buttons) do
            SetVisible(btn.box, false); SetVisible(btn.border, false); SetVisible(btn.label, false)
        end
        return
    end

    SetVisible(miniGlow, false); SetVisible(miniBg, false); SetVisible(miniBrd, false)
    SetVisible(miniTitle, false); SetVisible(miniHalo, false); SetVisible(miniPlus, false)

    SetVisible(mainGlow, true);   SetPos(mainGlow, GuiX - 3, GuiY - 3);   SetSize(mainGlow, GW + 6, GH + 6)
    SetVisible(mainBorder, true); SetPos(mainBorder, GuiX - 1, GuiY - 1); SetSize(mainBorder, GW + 2, GH + 2)
    SetVisible(mainBg, true);     SetPos(mainBg, GuiX, GuiY);             SetSize(mainBg, GW, GH)
    SetVisible(headerBg, true);   SetPos(headerBg, GuiX, GuiY);           SetSize(headerBg, GW, 42)
    SetVisible(headerLine, true); SetPos(headerLine, GuiX, GuiY + 42);    SetSize(headerLine, GW, 2)
    SetVisible(statusHalo, true); SetPos(statusHalo, GuiX + 17, GuiY + 21); SetRadius(statusHalo, 7 + pulse * 1.5)
    SetVisible(statusCore, true); SetPos(statusCore, GuiX + 17, GuiY + 21); SetRadius(statusCore, 4)
    SetVisible(titleText, true);  SetPos(titleText, GuiX + 31, GuiY + 12)
    SetVisible(minBtn, true);     SetPos(minBtn, GuiX + GW - 30, GuiY + 12)
    SetColor(minBtn, UI.TxtMuted)

    SetVisible(statusHdr, true)
    local modes = {}
    if State.AutoShoot then table.insert(modes, "SHOOT") end
    if State.AntiBomb then table.insert(modes, "DODGE") end
    if State.Fly then table.insert(modes, "FLY") end
    local hdrTxt = table.concat(modes, "+")
    if State.StatusText ~= "" then
        hdrTxt = State.StatusText
    end
    SetText(statusHdr, string.sub(hdrTxt, 1, 22))
    SetPos(statusHdr, GuiX + GW - 160, GuiY + 15)
    if hdrTxt ~= "" then
        SetColor(statusHdr, UI.StatusOn)
    end

    for i, tb in ipairs(tabButtons) do
        local active = (State.ActiveTab == i)
        local hovered = inRect(mx, my, GuiX + tb.rx, GuiY + tb.ry, tb.rw, tb.rh)
        SetVisible(tb.box, true)
        SetPos(tb.box, GuiX + tb.rx, GuiY + tb.ry)
        SetSize(tb.box, tb.rw, tb.rh)
        SetColor(tb.box, active and UI.TabActive or (hovered and UI.BoxHover or UI.Box))
        SetVisible(tb.txt, true)
        SetPos(tb.txt, GuiX + tb.rx + 8, GuiY + tb.ry + 6)
        SetColor(tb.txt, active and UI.TxtActive or UI.TxtSec)
    end

    for _, btn in ipairs(Buttons) do
        if btn.tab == State.ActiveTab then
            local bx, by = GuiX + btn.rx, GuiY + btn.ry
            local hovered = inRect(mx, my, bx, by, btn.rw, btn.rh)
            local active = false
            if btn == btnShoot then active = State.AutoShoot end
            if btn == btnDodge then active = State.AntiBomb end
            if btn == btnFly then active = State.Fly end
            if btn == btnNoclip then active = State.NoClip end
            if btn == btnJump then active = State.InfJump end
            local bgCol = active and (hovered and UI.ActiveHov or UI.ActiveBox) or (hovered and UI.BoxHover or UI.Box)
            local bdrCol = active and UI.ActiveBdr or (hovered and UI.HoverBorder or UI.BoxBorder)
            SetVisible(btn.box, true); SetPos(btn.box, bx, by); SetSize(btn.box, btn.rw, btn.rh); SetColor(btn.box, bgCol)
            SetVisible(btn.border, true); SetPos(btn.border, bx, by); SetSize(btn.border, btn.rw, btn.rh); SetColor(btn.border, bdrCol)
            SetVisible(btn.label, true); SetPos(btn.label, bx + 12, by + 7); SetColor(btn.label, active and UI.TxtActive or UI.TxtMain)
        else
            SetVisible(btn.box, false); SetVisible(btn.border, false); SetVisible(btn.label, false)
        end
    end
end)

notify("Monkey Suite V4.3", "no HoldFire + safe dodge + cursor", 3)
print("MONKEY SUITE V4.3 LOADED gen=" .. tostring(GEN))
