local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

while not Players.LocalPlayer do task.wait() end
local player = Players.LocalPlayer

-- ============================================================
-- KONFIGURASI EMOTE
-- ============================================================
local EMOTE_IDS = {
    83470183839446,
    107343854451506,
    86004301790568,
    114912639422575,
    133273871148994,
    98621274661025,
    10713992055,
    121966805049108,
    133281090368079,
    83006214712285
}

local currentTrack = nil
local running = true

-- ============================================================
-- KONFIGURASI AUTOMATION
-- ============================================================
local autoKillEnabled = true
local STUCK_TIMEOUT   = 2.5

-- ============================================================
-- KONFIGURASI FREEZE (TWEEN IN PLACE)
-- ============================================================
local freezeEnabled = true
-- true  = animasi tetap main (running/idle in place)
-- false = benar-benar diam tanpa animasi gerak
local keepAnimation = true

local whitelist = {
    "alamak942"
}

-- ============================================================
-- STATE INTERNAL
-- ============================================================
local roundId          = 0
local activeKillName   = nil
local killThreadActive = false
local skippedTargets   = {}

-- ============================================================
-- STATE FREEZE
-- ============================================================
local frozenCFrame  = nil
local frozenHrp     = nil
local freezeConn    = nil

local function startFreeze(char)
    if not char then return end

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if not hrp then return end

    frozenHrp    = hrp
    frozenCFrame = hrp.CFrame

    if freezeConn then freezeConn:Disconnect() end

    freezeConn = RunService.Heartbeat:Connect(function()
        if not freezeEnabled then return end
        if not frozenHrp or not frozenHrp.Parent then return end
        if not frozenCFrame then return end

        frozenHrp.AssemblyLinearVelocity  = Vector3.zero
        frozenHrp.AssemblyAngularVelocity = Vector3.zero
        frozenHrp.CFrame = frozenCFrame
    end)
end

local function stopFreeze()
    if freezeConn then
        freezeConn:Disconnect()
        freezeConn = nil
    end
    frozenCFrame = nil
    frozenHrp    = nil
end

-- ============================================================
-- UTILITAS
-- ============================================================
local function isWhitelisted(p)
    if typeof(p) == "Instance" and p:IsA("Player") then
        if table.find(whitelist, p.Name) or table.find(whitelist, p.UserId) then
            return true
        end
    elseif type(p) == "string" then
        if table.find(whitelist, p) then return true end
        local plr = Players:FindFirstChild(p)
        if plr and (table.find(whitelist, plr.UserId) or table.find(whitelist, plr.Name)) then
            return true
        end
    end
    return false
end

local function getKnife()
    local char = player.Character
    if char then
        local k = char:FindFirstChild("Knife")
        if k then return k end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        local k = bp:FindFirstChild("Knife")
        if k then return k end
    end
    return nil
end

local function hasKnife() return getKnife() ~= nil end

local function getKillPart(char)
    if not char then return nil end
    return char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
end

local function rawFire(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return end
    local knife = getKnife()
    if not knife then return end

    if knife.Parent ~= player.Character and player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:EquipTool(knife) end
    end

    local events = knife:FindFirstChild("Events")
    if not events then return end
    local ht = events:FindFirstChild("HandleTouched")
    if not ht then return end

    local part = getKillPart(targetPlayer.Character)
    if not part then return end
    ht:FireServer(part)
end

-- ============================================================
-- EMOTE LOOP
-- ============================================================
local function playEmotes(character)
    local humanoid = character:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")

    while running and character == player.Character do
        for _, id in ipairs(EMOTE_IDS) do
            if not running or character ~= player.Character then
                break
            end

            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://" .. tostring(id)

            local success, track = pcall(function()
                return animator:LoadAnimation(anim)
            end)

            if success and track then
                if currentTrack then
                    currentTrack:Stop(0.3)
                    currentTrack:Destroy()
                end

                currentTrack = track
                currentTrack.Priority = Enum.AnimationPriority.Action4
                currentTrack.Looped = false

                track:Play(0.3)

                track.Ended:Wait()

                if currentTrack == track then
                    currentTrack = nil
                end

                track:Destroy()
            else
                warn("Gagal memuat emote:", id)
            end

            anim:Destroy()
        end
    end
end

-- ============================================================
-- LOGIKA KILL
-- ============================================================
local function killTargetSync(targetPlayer, currentRound)
    local name = targetPlayer.Name
    local startTime = os.clock()

    while autoKillEnabled and hasKnife() do
        if currentRound ~= roundId then break end
        if not targetPlayer or not targetPlayer.Character or not targetPlayer:IsDescendantOf(Players) then break end

        local hum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then break end

        if (os.clock() - startTime) > STUCK_TIMEOUT then
            skippedTargets[name] = true
            warn("[Assassin] Target " .. name .. " gagal terbunuh (Timeout Skip).")
            break
        end

        rawFire(targetPlayer)
        task.wait(0.05)
    end
end

local function startAutoKillLoop()
    if killThreadActive then return end
    killThreadActive = true

    task.spawn(function()
        local currentRound = roundId

        while autoKillEnabled and hasKnife() and currentRound == roundId do
            local targets = Players:GetPlayers()
            local targetFound = false

            for _, target in ipairs(targets) do
                if currentRound ~= roundId or not hasKnife() then break end

                if target ~= player
                   and not isWhitelisted(target)
                   and not skippedTargets[target.Name]
                   and target.Character
                then
                    local hum = target.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        targetFound = true
                        activeKillName = target.Name
                        killTargetSync(target, currentRound)
                        activeKillName = nil
                        task.wait(0.05)
                    end
                end
            end

            if not targetFound then task.wait(0.5) end
        end

        killThreadActive = false
    end)
end

-- ============================================================
-- WATCHER
-- ============================================================
local function watchChar(char)
    if not char then return end
    char.ChildAdded:Connect(function(item)
        if item.Name == "Knife" then startAutoKillLoop() end
    end)
end

local function watchBackpack()
    local bp = player:WaitForChild("Backpack")
    bp.ChildAdded:Connect(function(item)
        if item.Name == "Knife" then startAutoKillLoop() end
    end)
end

-- ============================================================
-- MAIN INIT (GABUNGAN)
-- ============================================================
task.spawn(function()
    watchBackpack()

    if player.Character then
        watchChar(player.Character)
        task.spawn(playEmotes, player.Character)
        if freezeEnabled then
            task.wait(0.3)
            startFreeze(player.Character)
        end
    end

    if hasKnife() then startAutoKillLoop() end

    player.CharacterAdded:Connect(function(char)
        -- === RESET STATE KILL ===
        roundId += 1
        activeKillName   = nil
        killThreadActive = false
        skippedTargets   = {}

        -- === RESET STATE EMOTE ===
        currentTrack = nil

        -- === START EMOTE (baru) ===
        task.spawn(playEmotes, char)

        -- === START FREEZE ===
        task.wait(0.3)
        if freezeEnabled then
            startFreeze(char)
        end

        -- === WATCHER ULANG ===
        watchBackpack()
        watchChar(char)
    end)
end)
