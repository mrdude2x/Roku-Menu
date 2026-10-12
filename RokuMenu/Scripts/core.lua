-- RokuMenu core v0.5: every game read and write lives here.
-- main.lua is the menu and the hotkeys. Fix this file when the game updates.
-- GON 1.3. Stamina cubes add 0.2s and 2 sprint speed. Scales sit on top of that.

local M = {}

local isGodMode = false
local isInfStamina = false
local isGhostMode = false
local isRokuFrozen = false
local isRokuSlow = false
local isUiHidden = false
local isSpankHold = false
local isCowbell = false
local isFollow = false
local followSaved = nil
local isNoclip = false
local isFreecam = false
local isCrouch = false
local flyScale = 1.0
local savedPawnLoc = nil
local savedCamRel = nil
local savedCamRot = nil
local savedHalfHeight = nil
local savedDist = nil
local savedVision = nil
local flyKeys = nil
local currentSkinIdx = 1
local lastLiveRokuNm = ""
local hadLevelRoku = false
local savedHudVis = nil
local persistCheats = false
local cheatSnapshot = nil
local listeners = {}

local function notify()
    for i = 1, #listeners do
        pcall(listeners[i], M.GetState())
    end
end

local function RunOnGameThread(fn)
    if ExecuteInGameThread then
        ExecuteInGameThread(fn)
    else
        pcall(fn)
    end
end

local function SafeGetObjectName(obj)
    if not obj or not obj:IsValid() then return "None" end
    local s1, name1 = pcall(function() return obj:GetFullName() end)
    if s1 and name1 then return name1 end
    local s2, name2 = pcall(function() return obj:GetName() end)
    if s2 and name2 then return name2 end
    return tostring(obj)
end

-- Live player and Roku. Default__ names are class templates, not actors in the level.
-- The 200 ms loop reuses the last live actor. The 1 s scan clears Roku so a level change is seen.
local pawnCache = nil
local rokuCache = nil

local function GetPlayerPawn()
    if pawnCache and pawnCache:IsValid() then
        return pawnCache
    end
    pawnCache = nil
    local players = FindAllOf("BP_HorrorCharacter_C") or {}
    for i = 1, #players do
        local p = players[i]
        if p and p:IsValid() and not string.find(p:GetFullName(), "Default__") then
            pawnCache = p
            return p
        end
    end
    local pc = FindFirstOf("PlayerController")
    if pc and pc:IsValid() and pc.Pawn and pc.Pawn:IsValid() then
        pawnCache = pc.Pawn
        return pc.Pawn
    end
    return nil
end

local function GetRoku()
    if rokuCache and rokuCache:IsValid() then
        return rokuCache
    end
    rokuCache = nil
    local actors = FindAllOf("BP_Rokuv3_C") or {}
    for i = 1, #actors do
        local a = actors[i]
        if a and a:IsValid() and not string.find(a:GetFullName(), "Default__") then
            rokuCache = a
            return a
        end
    end
    local chars = FindAllOf("Character") or {}
    for i = 1, #chars do
        local c = chars[i]
        if c and c:IsValid() then
            local fullName = SafeGetObjectName(c)
            if not string.find(fullName, "Default__") and not string.find(fullName:lower(), "horror") then
                if c.ApplyOutfit or c.C_shirt1 or string.find(fullName:lower(), "roku") then
                    rokuCache = c
                    return c
                end
            end
        end
    end
    return nil
end

local function GetGameInstance()
    local gi = FindFirstOf("GI_GON_C")
    if gi and gi:IsValid() and not string.find(gi:GetFullName(), "Default__") then
        return gi
    end
    return nil
end

local function GetMesh(actor)
    if not actor or not actor:IsValid() then return nil end
    if actor.Mesh and actor.Mesh:IsValid() then return actor.Mesh end
    if actor.CharacterMesh0 and actor.CharacterMesh0:IsValid() then return actor.CharacterMesh0 end
    return nil
end

-- Hit volumes that start the close-range slap (attack / inspect end / thrown-item hit).
-- SpankBox and ButtBox stay on so spank still works.
-- Attack volumes only. FaceBox and ChestBox are how wine and other items connect.
-- SpankBox and ButtBox stay on.
local slapVolumes = {
    "AttackBox", "crushbox",
    "GH_pelvis", "GH_chest", "GH_Head", "GH_leftarm", "GH_legL", "GH_legR", "GH_rightarm",
}

local function SetVolume(comp, enabled)
    if not comp or not comp:IsValid() then return end
    pcall(function()
        comp:SetGenerateOverlapEvents(enabled)
        comp:SetCollisionEnabled(enabled and 1 or 0)
    end)
end

local attackHookInstalled = false
local damageHookInstalled = false

local STOCK_SPRINT_TIME = 5.0
local STOCK_RECOVER_WALK = 150.0
local STOCK_SPRINT = 460.0
local STOCK_CHASE = 480.0
local CUBE_TIME = 0.2
local CUBE_SPEED = 2.0
local MAX_CUBES = 10
local STAMINA_SCALES = { 0.5, 1, 1.5, 2, 3 }
local SPRINT_SCALES = { 0.8, 0.9, 1, 1.1, 1.2 }
local CHASE_SCALES = { 0.7, 0.8, 0.9, 1, 1.1 }

local dmgMode = "normal"
local staminaScale = 1.0
local penaltyOff = false
local sprintScale = 1.0
local chaseScale = 1.0
local lastHealth = nil
local staminaReady = false
local damageHookFired = false
local damageHookTries = 0
local attackHookTries = 0
-- Unscaled cube totals. written* is the last number this mod stored, so a later +0.2 / +2 can be seen.
local timeBase = nil
local speedBase = nil
local writtenTime = nil
local writtenSpeed = nil
local savedSpeeds = nil

local function StockDistances()
    return { a = 5500, b = 1500, c = 3000, d = 1000 }
end

local function WriteNumber(obj, key, value, tol)
    if not obj or not obj:IsValid() then return false end
    local cur = nil
    local ok = pcall(function() cur = obj[key] end)
    if ok and type(cur) == "number" and math.abs(cur - value) <= tol then
        return false
    end
    pcall(function() obj[key] = value end)
    return true
end

local function ClampBase(base, stock, step)
    if base < stock then return stock end
    local cap = stock + MAX_CUBES * step
    if base > cap then return cap end
    return base
end

-- Live value matches stock + N cubes (N is 0..10). Returns the unscaled base, or nil.
local function SnapCubes(live, stock, step)
    if type(live) ~= "number" then return nil end
    local n = math.floor(((live - stock) / step) + 0.5)
    if n < 0 or n > MAX_CUBES then return nil end
    local base = stock + n * step
    if math.abs(live - base) > (step * 0.35) then return nil end
    return base
end

-- Prefer the value we wrote. A step of one cube updates the base. A jump back to 5+0.2*N is a fresh total.
local function ReconcileBase(live, written, base, stock, step, scale)
    if type(live) ~= "number" then
        return base or stock
    end
    local tol = step * 0.35
    if written ~= nil and math.abs(live - written) <= tol then
        return base or stock
    end
    if written ~= nil then
        local delta = live - written
        local cubes = math.floor((delta / step) + 0.5)
        if cubes ~= 0 and cubes >= -MAX_CUBES and cubes <= MAX_CUBES
            and math.abs(delta - (cubes * step)) <= tol then
            return ClampBase((base or stock) + (cubes * step), stock, step)
        end
    end
    local snapped = SnapCubes(live, stock, step)
    if not snapped and scale and scale ~= 1 and scale > 0 then
        snapped = SnapCubes(live / scale, stock, step)
    end
    if snapped then return snapped end
    if base then return base end
    return stock
end

local function ForgetMoveScale()
    timeBase = nil
    speedBase = nil
    writtenTime = nil
    writtenSpeed = nil
    staminaReady = false
    savedSpeeds = nil
    pawnCache = nil
    rokuCache = nil
end

local function AllowedScale(value, allowed, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    for i = 1, #allowed do
        if math.abs(allowed[i] - n) < 0.001 then return allowed[i] end
    end
    return fallback
end

local function ChosenChase()
    return STOCK_CHASE * chaseScale
end

-- Ghost and freeze. Attack montages are blocked. Vision and hearing stay off until it is turned off.
local function IsAttackName(name)
    local n = string.lower(name or "")
    return string.find(n, "attack", 1, true)
        or string.find(n, "aggro", 1, true)
end

local function StopAttackAnims(roku)
    local mesh = GetMesh(roku)
    if not mesh then return end
    local anim = nil
    pcall(function() anim = mesh:GetAnimInstance() end)
    if not anim or not anim:IsValid() then return end
    local cur = nil
    pcall(function() cur = anim:GetCurrentActiveMontage() end)
    if not cur or not cur.IsValid or not cur:IsValid() then return end
    local name = nil
    pcall(function()
        if cur.GetFullName then
            name = cur:GetFullName()
        end
    end)
    if type(name) == "string" and IsAttackName(name) then
        pcall(function() anim:Montage_Stop(0.05, cur) end)
        pcall(function() roku:StopAnimMontage(cur) end)
    end
end

-- Undo the previous ghost build, which paused her AI and zeroed walk speed.
local function ReleaseOldFreeze(roku)
    pcall(function()
        if roku.MoveSpeed == 0 then roku.MoveSpeed = 150 end
        if roku.chasespeed == 0 then roku.chasespeed = ChosenChase() end
        local cm = roku.CharacterMovement
        if cm and cm:IsValid() and cm.MaxWalkSpeed == 0 then
            cm.MaxWalkSpeed = 150
        end
    end)
    local ctrl = roku.Controller
    if ctrl and ctrl:IsValid() then
        local brain = nil
        pcall(function() brain = ctrl.BrainComponent end)
        if brain and brain:IsValid() then
            pcall(function() brain:RestartLogic() end)
        end
    end
end

-- Bools only. Calling OnLostPlayer every tick restarts her attack and wipes the cooldown.
local function QuietBlind(roku)
    pcall(function() roku.bIsChasing = false end)
    pcall(function() roku.bIsInvestigating = false end)
    pcall(function() roku.bPlayerInVisionBox = false end)
    pcall(function() roku.bLineTraceHitPlayer = false end)
    pcall(function() roku.visionchecker = false end)
    pcall(function() roku.bSensesEnabled = false end)
    pcall(function() roku.HasAttacked = true end)
    pcall(function() roku.bCanBump = false end)
end

-- Once per Ghost press. Hide is not used: flipping it on then off is "left the closet"
-- and makes her attack immediately.
local function DropChaseOnce(roku)
    if M.RestoreSight then M.RestoreSight(GetPlayerPawn(), roku) end
    QuietBlind(roku)
    pcall(function() roku:OnLostPlayer() end)
    pcall(function() roku:SetPlayerDetected(false) end)
    pcall(function() roku:StopCatchUp() end)
    pcall(function() roku:PickNextWaypoint() end)
    pcall(function() roku["VISION DOWN"]() end)
    local ctrl = roku.Controller
    if ctrl and ctrl:IsValid() then
        pcall(function() ctrl:CancelChase() end)
        pcall(function()
            local perc = ctrl.PerceptionComponent
            if perc and perc:IsValid() then perc:ForgetAll() end
        end)
    end
    StopAttackAnims(roku)
end

local function ApplyGhostState(roku, enableGhost)
    if not roku or not roku:IsValid() then return end
    ReleaseOldFreeze(roku)
    SetVolume(roku.VisionBox, not enableGhost)
    SetVolume(roku.HearingSphere, not enableGhost)
    for i = 1, #slapVolumes do
        SetVolume(roku[slapVolumes[i]], not enableGhost)
    end
    if enableGhost then
        DropChaseOnce(roku)
        print("[RokuMenu] Ghost: chase dropped once, senses stay off\n")
    else
        pcall(function() roku.bSensesEnabled = true end)
        pcall(function() roku.HasAttacked = false end)
        pcall(function() roku.bCanBump = true end)
        pcall(function() roku["VISION UP"]() end)
    end
end

local function InstallAttackHook()
    if attackHookInstalled then return end
    local ok, err = pcall(function()
        RegisterHook("/Script/Engine.Character:PlayAnimMontage", function(Context, Montage, PlayRate)
            if not isGhostMode and not isRokuFrozen then return end
            local ch = Context:get()
            if not ch or not ch:IsValid() then return end
            local full = ""
            pcall(function() full = ch:GetFullName() end)
            if not string.find(string.lower(full), "rokuv3", 1, true) then return end
            local mname = ""
            pcall(function()
                local m = Montage:get()
                if m and m:IsValid() then mname = m:GetName() end
            end)
            if IsAttackName(mname) then
                pcall(function() PlayRate:set(0.0) end)
                pcall(function() ch:StopAnimMontage() end)
                print("[RokuMenu] Blocked attack montage: " .. mname .. "\n")
            end
        end)
    end)
    if ok then
        attackHookInstalled = true
        print("[RokuMenu] Attack hook installed\n")
    else
        attackHookTries = attackHookTries + 1
        if attackHookTries == 1 then
            print("[RokuMenu] Attack hook waiting: " .. tostring(err) .. "\n")
        end
    end
end

-- Blueprint hook runs after TakeDamage. Refund part of the drop. Apples stay untouched.
local function InstallDamageHook()
    if damageHookInstalled then return end
    local ok, err = pcall(function()
        RegisterHook("/Game/Variant_Horror/Blueprints/BP_HorrorCharacter.BP_HorrorCharacter_C:TakeDamage", function(Context)
            local player = nil
            pcall(function()
                if Context and Context.get then
                    player = Context:get()
                elseif Context and Context.IsValid then
                    player = Context
                end
            end)
            if not player or not player:IsValid() then
                if not damageHookFired then
                    damageHookFired = true
                    print("[RokuMenu] Damage hook fired, player context empty\n")
                end
                return
            end
            local now = nil
            pcall(function() now = player.Health end)
            if type(now) ~= "number" then return end
            if not damageHookFired then
                damageHookFired = true
                print("[RokuMenu] Damage hook fired\n")
            end
            if isGodMode or dmgMode == "normal" then
                lastHealth = now
                return
            end
            local prev = lastHealth
            if type(prev) ~= "number" then
                lastHealth = now
                return
            end
            local drop = prev - now
            if drop <= 0.01 then
                lastHealth = now
                return
            end
            local restored = now
            if dmgMode == "half" then
                restored = now + (drop * 0.5)
            elseif dmgMode == "quarter" then
                restored = now + (drop * 0.75)
            end
            pcall(function() player.Health = restored end)
            if restored > 0.01 then
                pcall(function() player.IsDead = false end)
            end
            lastHealth = restored
            print(string.format("[RokuMenu] Damage %s: %.2f -> %.2f, restored to %.2f\n", dmgMode, prev, now, restored))
        end)
    end)
    if ok then
        damageHookInstalled = true
        print("[RokuMenu] Damage hook installed\n")
    else
        damageHookTries = damageHookTries + 1
        if damageHookTries == 1 then
            print("[RokuMenu] Damage hook waiting for the player class\n")
        end
    end
end

-- Outfits. Bunny keeps eye and teeth slots. Shirt-off uses the Topless row.
local clothingPieces = {
    "C_shirt1", "C_pants1",
    "C_sailortop", "C_sailortop2", "C_sailorskirt", "C_sailorskirt2", "C_sailorshibari",
    "C_bunnyskull", "C_bunnyears", "C_bunnyupper", "C_bunnybra", "C_bunnycorset", "skirt_test",
    "C_Bikini1",
    "C_CGbikini", "C_CGboots", "C_CGsleeves", "CGhead", "CG_hairpin",
    "C_Dbikini", "C_Dboots",
}

local function HideAllClothing(actor)
    for _, piece in ipairs(clothingPieces) do
        local comp = actor[piece]
        if comp and comp:IsValid() then
            comp:SetVisibility(false, true)
        end
    end
end

local function SetPieceVisible(actor, compName, isVis)
    local comp = actor[compName]
    if comp and comp:IsValid() then
        comp:SetVisibility(isVis, true)
    end
end

local function ResetToMeshDefaultMaterials(actor)
    local mesh = GetMesh(actor)
    if not mesh or not mesh:IsValid() then return end
    pcall(function()
        for slot = 0, 15 do
            mesh:SetMaterial(slot, nil)
        end
    end)
    local skMesh = mesh.SkeletalMeshAsset or mesh.SkeletalMesh
    if skMesh and skMesh:IsValid() and skMesh.Materials then
        for i = 1, #skMesh.Materials do
            local matInterface = skMesh.Materials[i].MaterialInterface
            if matInterface and matInterface:IsValid() then
                mesh:SetMaterial(i - 1, matInterface)
            end
        end
    end
end

local function FindBunnyMaterial(version)
    local target = (version == 2) and "M_RokuNudeBunny2" or "M_RokuNudeBunny"
    local classes = { "MaterialInstanceConstant", "Material" }
    for _, cls in ipairs(classes) do
        local list = FindAllOf(cls) or {}
        for i = 1, #list do
            local obj = list[i]
            local name = SafeGetObjectName(obj)
            if string.find(name, target) then
                return obj
            end
        end
    end
    return nil
end

local faceWords = { "eye", "teeth", "tooth", "mouth", "lash", "cornea", "iris", "tongue", "gum" }

local function IsFaceMaterial(mat)
    local name = string.lower(SafeGetObjectName(mat))
    for i = 1, #faceWords do
        if string.find(name, faceWords[i], 1, true) then
            return true
        end
    end
    return false
end

local function ApplyBunnyBody(actor, mat)
    local mesh = GetMesh(actor)
    if not mat or not mat:IsValid() or not mesh or not mesh:IsValid() then return end
    local keep = {}
    for slot = 0, 15 do
        local ok, current = pcall(function() return mesh:GetMaterial(slot) end)
        if not ok or not current or not current:IsValid() then break end
        if IsFaceMaterial(current) then
            keep[slot] = current
        end
    end
    for slot = 0, 15 do
        local ok, current = pcall(function() return mesh:GetMaterial(slot) end)
        if not ok or not current or not current:IsValid() then break end
        if not keep[slot] then
            mesh:SetMaterial(slot, mat)
        end
    end
end

local skins = {
    [1] = {
        name = "Base Roku (Skull Top + Pants)",
        apply = function(actor)
            HideAllClothing(actor)
            ResetToMeshDefaultMaterials(actor)
            SetPieceVisible(actor, "C_shirt1", true)
            SetPieceVisible(actor, "C_pants1", true)
            pcall(function() actor:ApplyOutfit(FName("Base")) end)
        end
    },
    [2] = {
        name = "Shirt-Off Roku",
        apply = function(actor)
            HideAllClothing(actor)
            -- DT_Outfits row is Topless (not ShirtOff). That swap is the
            -- in-game censored chest; default mesh without a shirt is nude.
            pcall(function() actor:ApplyOutfit(FName("Topless")) end)
            SetPieceVisible(actor, "C_pants1", true)
        end
    },
    [3] = {
        name = "Bottomless Roku",
        apply = function(actor)
            HideAllClothing(actor)
            ResetToMeshDefaultMaterials(actor)
            SetPieceVisible(actor, "C_shirt1", true)
            pcall(function() actor:ApplyOutfit(FName("Bottomless")) end)
        end
    },
    [4] = {
        name = "Bikini Roku",
        apply = function(actor)
            HideAllClothing(actor)
            ResetToMeshDefaultMaterials(actor)
            SetPieceVisible(actor, "C_Bikini1", true)
            pcall(function() actor:ApplyOutfit(FName("Bikini")) end)
        end
    },
    [5] = {
        name = "Source Roku",
        apply = function(actor)
            HideAllClothing(actor)
            ResetToMeshDefaultMaterials(actor)
            SetPieceVisible(actor, "C_shirt1", true)
            SetPieceVisible(actor, "C_pants1", true)
            pcall(function() actor:ApplyOutfit(FName("Source")) end)
        end
    },
    [6] = {
        name = "Bunny Roku (1)",
        apply = function(actor)
            HideAllClothing(actor)
            local mat = FindBunnyMaterial(1)
            if mat then ApplyBunnyBody(actor, mat) end
            SetPieceVisible(actor, "C_bunnyears", true)
            SetPieceVisible(actor, "C_bunnybra", true)
            SetPieceVisible(actor, "C_bunnycorset", true)
            SetPieceVisible(actor, "C_bunnyupper", true)
            pcall(function() actor:ApplyOutfit(FName("Bunny1")) end)
            SetPieceVisible(actor, "C_bunnyears", true)
            SetPieceVisible(actor, "C_bunnybra", true)
            SetPieceVisible(actor, "C_bunnycorset", true)
            SetPieceVisible(actor, "C_bunnyupper", true)
        end
    },
    [7] = {
        name = "Bunny Roku (2)",
        apply = function(actor)
            HideAllClothing(actor)
            local mat = FindBunnyMaterial(2)
            if mat then ApplyBunnyBody(actor, mat) end
            SetPieceVisible(actor, "C_bunnyears", true)
            SetPieceVisible(actor, "C_bunnyskull", true)
            SetPieceVisible(actor, "C_bunnycorset", true)
            SetPieceVisible(actor, "C_bunnyupper", true)
            pcall(function() actor:ApplyOutfit(FName("Bunny2")) end)
        end
    },
    [8] = {
        name = "Sailor Roku (1)",
        apply = function(actor)
            HideAllClothing(actor)
            ResetToMeshDefaultMaterials(actor)
            pcall(function() actor:ApplyOutfit(FName("Sailor1")) end)
            -- The 1.3 row also lists the shibari ropes. Sailor 1 stays the uniform.
            SetPieceVisible(actor, "C_sailorshibari", false)
            SetPieceVisible(actor, "C_sailortop", true)
            SetPieceVisible(actor, "C_sailorskirt", true)
        end
    },
    [9] = {
        name = "Sailor Roku (2)",
        apply = function(actor)
            HideAllClothing(actor)
            ResetToMeshDefaultMaterials(actor)
            pcall(function() actor:ApplyOutfit(FName("Sailor2")) end)
            SetPieceVisible(actor, "C_sailorshibari", false)
            SetPieceVisible(actor, "C_sailortop2", true)
            SetPieceVisible(actor, "C_sailorskirt2", true)
        end
    },
    [10] = {
        name = "Shibari Roku",
        apply = function(actor)
            HideAllClothing(actor)
            ResetToMeshDefaultMaterials(actor)
            SetPieceVisible(actor, "C_sailortop2", true)
            SetPieceVisible(actor, "C_sailorskirt2", true)
            SetPieceVisible(actor, "C_sailorshibari", true)
            pcall(function() actor:ApplyOutfit(FName("Shibari")) end)
        end
    },
    [11] = {
        name = "Uncensored Full Bare",
        apply = function(actor)
            pcall(function() actor:ApplyOutfit(FName("Shibari")) end)
            HideAllClothing(actor)
        end
    },
    [12] = {
        name = "Uncensored Shirtless",
        apply = function(actor)
            pcall(function() actor:ApplyOutfit(FName("Shibari")) end)
            HideAllClothing(actor)
            SetPieceVisible(actor, "C_pants1", true)
        end
    },
    [13] = {
        name = "Uncensored Bottomless",
        apply = function(actor)
            pcall(function() actor:ApplyOutfit(FName("Shibari")) end)
            HideAllClothing(actor)
            SetPieceVisible(actor, "C_shirt1", true)
        end
    },
    [14] = {
        name = "Cowmeat Roku",
        apply = function(actor)
            HideAllClothing(actor)
            pcall(function() actor:ApplyOutfit(FName("Cowmeat")) end)
            SetPieceVisible(actor, "C_CGbikini", true)
            SetPieceVisible(actor, "C_CGboots", true)
            SetPieceVisible(actor, "C_CGsleeves", true)
            SetPieceVisible(actor, "CGhead", true)
            SetPieceVisible(actor, "CG_hairpin", true)
        end
    },
    [15] = {
        name = "Dark Roku",
        apply = function(actor)
            HideAllClothing(actor)
            pcall(function() actor:ApplyOutfit(FName("Dark")) end)
            SetPieceVisible(actor, "C_Dbikini", true)
            SetPieceVisible(actor, "C_Dboots", true)
        end
    }
}

function M.GetState()
    return {
        god = isGodMode,
        stamina = isInfStamina,
        ghost = isGhostMode,
        frozen = isRokuFrozen,
        slow = isRokuSlow,
        uiHidden = isUiHidden,
        noclip = isNoclip,
        freecam = isFreecam,
        crouch = isCrouch,
        spank = isSpankHold,
        cowbell = isCowbell,
        follow = isFollow,
        fly = math.floor(flyScale * 100 + 0.5),
        skin = currentSkinIdx,
        persist = persistCheats,
        roku = lastLiveRokuNm,
    }
end

local storeCheats = nil

function M.SetCheatStore(fn)
    storeCheats = fn
end

local function StoreSnapshot()
    if storeCheats then
        pcall(storeCheats, cheatSnapshot)
    end
end

function M.SetPersistCheats(on)
    persistCheats = not not on
    if not persistCheats then
        cheatSnapshot = nil
        StoreSnapshot()
    end
    notify()
end

function M.LoadCheatSnapshot(saved)
    if not persistCheats or type(saved) ~= "table" then
        return
    end
    local skin = tonumber(saved.skin) or 1
    skin = math.floor(skin)
    if skin < 1 or skin > #skins then
        skin = 1
    end
    cheatSnapshot = {
        god = saved.god == true,
        stamina = saved.stamina == true,
        ghost = saved.ghost == true,
        frozen = saved.frozen == true,
        slow = saved.slow == true,
        uiHidden = saved.uiHidden == true,
        noclip = saved.noclip == true,
        freecam = saved.freecam == true,
        crouch = saved.crouch == true,
        spank = saved.spank == true,
        cowbell = false,
        follow = saved.follow == true,
        skin = skin,
    }
end

function M.GetSkinNames()
    local names = {}
    for i = 1, #skins do
        names[i] = { label = string.format("%d. %s", i, skins[i].name), value = i }
    end
    return names
end

function M.OnChange(fn)
    listeners[#listeners + 1] = fn
end

-- Difficulty tab. One choice per row. Stock rows do not write on the loop.
-- Stamina time and sprint speed scale the cube-adjusted base, not the bare 5s / 460.
local function ApplyEmptyPenalty(player)
    if not player or not player:IsValid() then return end
    if penaltyOff then
        local walk = 240
        pcall(function()
            local w = player["Walk Speed"]
            if type(w) == "number" and w > 1 then walk = w end
        end)
        WriteNumber(player, "Recovering Walk Speed", walk, 0.5)
    else
        WriteNumber(player, "Recovering Walk Speed", STOCK_RECOVER_WALK, 0.5)
    end
end

local function ApplySprintScale(player)
    if isCrouch then return end
    if not player or not player:IsValid() then return end
    if sprintScale == 1 and writtenSpeed == nil then
        return
    end
    local live = nil
    pcall(function() live = player["Sprint Speed"] end)
    speedBase = ReconcileBase(live, writtenSpeed, speedBase, STOCK_SPRINT, CUBE_SPEED, sprintScale)
    local target = speedBase * sprintScale
    if sprintScale == 1 then
        WriteNumber(player, "Sprint Speed", target, 0.5)
        writtenSpeed = nil
        return
    end
    WriteNumber(player, "Sprint Speed", target, 0.5)
    writtenSpeed = target
    local sprinting = false
    pcall(function() sprinting = player["Wants to Sprint"] == true end)
    if not sprinting then return end
    pcall(function()
        local cm = player.CharacterMovement
        if cm and cm:IsValid() then
            local cur = cm.MaxWalkSpeed
            if type(cur) ~= "number" or math.abs(cur - target) > 0.5 then
                cm.MaxWalkSpeed = target
            end
        end
    end)
end

local function ApplyStaminaScale(player, rescaleMeter)
    if not player or not player:IsValid() then return end
    local live = nil
    pcall(function() live = player["Sprint Time"] end)
    timeBase = ReconcileBase(live, writtenTime, timeBase, STOCK_SPRINT_TIME, CUBE_TIME, staminaScale)
    local newTime = timeBase * staminaScale
    if rescaleMeter and not isInfStamina and type(live) == "number" and live > 0.05 then
        local meter = nil
        pcall(function() meter = player["Sprint Meter"] end)
        pcall(function() player["Sprint Time"] = newTime end)
        if type(meter) == "number" then
            local scaled = meter * (newTime / live)
            if scaled > newTime then scaled = newTime end
            if scaled < 0 then scaled = 0 end
            pcall(function() player["Sprint Meter"] = scaled end)
        end
    else
        WriteNumber(player, "Sprint Time", newTime, 0.02)
        if isInfStamina then
            WriteNumber(player, "Sprint Meter", newTime, 0.02)
            pcall(function()
                if player.Recovering ~= false then player.Recovering = false end
            end)
            pcall(function()
                local rt = player["Recovery Time"]
                if type(rt) ~= "number" or rt ~= 0 then
                    player["Recovery Time"] = 0.0
                end
            end)
        else
            pcall(function()
                local meter = player["Sprint Meter"]
                if type(meter) == "number" and meter > newTime + 0.02 then
                    player["Sprint Meter"] = newTime
                end
            end)
        end
    end
    if staminaScale == 1 and not isInfStamina then
        writtenTime = nil
    else
        writtenTime = newTime
    end
    staminaReady = true
end

local function ApplyChaseScale(roku)
    if isRokuFrozen then return end
    if not roku or not roku:IsValid() then return end
    local target = ChosenChase()
    pcall(function()
        local cur = roku.chasespeed
        if type(cur) ~= "number" or math.abs(cur - target) > 0.5 then
            roku.chasespeed = target
        end
    end)
end

local function EnforceDifficulty()
    local needHealth = dmgMode ~= "normal"
    local needStamina = staminaScale ~= 1 or isInfStamina
    local needPenalty = penaltyOff
    local needSprint = sprintScale ~= 1
    local needChase = chaseScale ~= 1 and not isRokuFrozen
    if not needHealth and not needStamina and not needPenalty and not needSprint and not needChase then
        return
    end
    local player = GetPlayerPawn()
    if player and player:IsValid() then
        if needHealth then
            pcall(function()
                local h = player.Health
                if type(h) == "number" then lastHealth = h end
            end)
        end
        if needStamina then
            ApplyStaminaScale(player, not staminaReady)
        end
        if needPenalty then
            ApplyEmptyPenalty(player)
        end
        if needSprint then
            ApplySprintScale(player)
        end
    end
    if needChase then
        ApplyChaseScale(GetRoku())
    end
end

function M.SetDamageMode(mode)
    if mode == "off" then mode = "quarter" end
    if mode ~= "half" and mode ~= "quarter" then
        mode = "normal"
    end
    dmgMode = mode
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if player and player:IsValid() then
            pcall(function()
                local h = player.Health
                if type(h) == "number" then lastHealth = h end
            end)
        end
    end)
    print(string.format("[RokuMenu] Roku damage: %s\n", dmgMode))
end

function M.SetStaminaScale(scale)
    staminaScale = AllowedScale(scale, STAMINA_SCALES, 1)
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if player then
            ApplyStaminaScale(player, true)
        else
            staminaReady = false
        end
        print(string.format("[RokuMenu] Stamina scale: %.2f\n", staminaScale))
    end)
end

function M.SetPenaltyMode(mode)
    penaltyOff = (mode == "off")
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if player then
            ApplyEmptyPenalty(player)
        end
        print(string.format("[RokuMenu] Empty stamina penalty: %s\n", penaltyOff and "OFF" or "ON"))
    end)
end

function M.SetSprintScale(scale)
    sprintScale = AllowedScale(scale, SPRINT_SCALES, 1)
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if player and not isCrouch then
            ApplySprintScale(player)
        end
        print(string.format("[RokuMenu] Sprint scale: %.2f\n", sprintScale))
    end)
end

function M.SetChaseScale(scale)
    chaseScale = AllowedScale(scale, CHASE_SCALES, 1)
    RunOnGameThread(function()
        if not isRokuFrozen then
            ApplyChaseScale(GetRoku())
        end
        print(string.format("[RokuMenu] Chase scale: %.2f\n", chaseScale))
    end)
end

function M.ApplySavedDifficulty(opts)
    if type(opts) ~= "table" then return end
    M.SetDamageMode(opts.dmg)
    staminaScale = AllowedScale(opts.stamina, STAMINA_SCALES, 1)
    penaltyOff = (opts.penalty == "off")
    sprintScale = AllowedScale(opts.sprint, SPRINT_SCALES, 1)
    chaseScale = AllowedScale(opts.chase, CHASE_SCALES, 1)
    staminaReady = false
    RunOnGameThread(function()
        EnforceDifficulty()
    end)
    print(string.format("[RokuMenu] Difficulty: damage %s, stamina %.2f, penalty %s, sprint %.2f, chase %.2f\n",
        dmgMode, staminaScale, penaltyOff and "off" or "on", sprintScale, chaseScale))
end

function M.OnLevelRoku()
    ForgetMoveScale()
    InstallDamageHook()
end

-- Cheats, HUD, apples, and the outfit buttons.
function M.SetGod(on)
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if not player then
            print("[RokuMenu] Player not found.\n")
            return
        end
        isGodMode = not not on
        pcall(function()
            player.bCanBeDamaged = not isGodMode
            player.IsDead = false
            if isGodMode then player.Health = 1.0 end
        end)
        print(string.format("[RokuMenu] God Mode: %s\n", isGodMode and "ON" or "OFF"))
        notify()
    end)
end

function M.SetStamina(on)
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if not player then
            print("[RokuMenu] Player not found.\n")
            return
        end
        isInfStamina = not not on
        if isInfStamina then
            ApplyStaminaScale(player, false)
        elseif staminaScale == 1 then
            writtenTime = nil
        end
        print(string.format("[RokuMenu] Infinite Stamina: %s\n", isInfStamina and "ON" or "OFF"))
        notify()
    end)
end

-- Freecam turns Ghost on, and turns it back off only if Ghost was off before.
local ghostHeldByFreecam = false

local function ApplyGhostNow(on)
    on = not not on
    if on and isFollow then
        isFollow = false
        local player = GetPlayerPawn()
        local d = followSaved or StockDistances()
        if player and player:IsValid() then
            pcall(function() player.EasyDistanceCheckA = d.a end)
            pcall(function() player.EasyDistanceCheckB = d.b end)
            pcall(function() player.HardDistanceCheckA = d.c end)
            pcall(function() player.HardDistanceCheckB = d.d end)
        end
        print("[RokuMenu] Follow OFF because Ghost was turned on.\n")
    end
    isGhostMode = on
    local roku = GetRoku()
    if roku then
        ApplyGhostState(roku, isGhostMode or isRokuFrozen)
    end
    print(string.format("[RokuMenu] Ghost Mode: %s\n", isGhostMode and "ON" or "OFF"))
    notify()
end

local function HoldGhostForFreecam()
    if isGhostMode then
        ghostHeldByFreecam = false
        return
    end
    ghostHeldByFreecam = true
    print("[RokuMenu] Ghost ON for freecam\n")
    ApplyGhostNow(true)
end

local function ReleaseFreecamGhost()
    if not ghostHeldByFreecam then return end
    ghostHeldByFreecam = false
    print("[RokuMenu] Ghost OFF with freecam\n")
    ApplyGhostNow(false)
end

function M.SetGhost(on)
    RunOnGameThread(function()
        on = not not on
        if not on and isFreecam then
            print("[RokuMenu] Ghost stays on while freecam is on\n")
            notify()
            return
        end
        if not on or isFreecam then
            ghostHeldByFreecam = false
        end
        ApplyGhostNow(on)
    end)
end

function M.SetFrozen(on)
    RunOnGameThread(function()
        local roku = GetRoku()
        if not roku then
            print("[RokuMenu] Roku not found.\n")
            return
        end
        isRokuFrozen = not not on
        if isRokuFrozen then
            isRokuSlow = false
            pcall(function() roku.CustomTimeDilation = 0.0 end)
            ApplyGhostState(roku, true)
        else
            pcall(function() roku.CustomTimeDilation = 1.0 end)
            if not isGhostMode then
                ApplyGhostState(roku, false)
            end
            pcall(function() roku:NormalSpeed() end)
            ApplyChaseScale(roku)
        end
        print(string.format("[RokuMenu] Freeze: %s\n", isRokuFrozen and "ON" or "OFF"))
        notify()
    end)
end

function M.SetSlow(on)
    RunOnGameThread(function()
        local roku = GetRoku()
        if not roku then
            print("[RokuMenu] Roku not found.\n")
            return
        end
        isRokuSlow = not not on
        if isRokuSlow then
            isRokuFrozen = false
            pcall(function() roku.CustomTimeDilation = 0.05 end)
        else
            pcall(function() roku.CustomTimeDilation = 1.0 end)
        end
        print(string.format("[RokuMenu] Slo-Mo: %s\n", isRokuSlow and "ON" or "OFF"))
        notify()
    end)
end

function M.SetUIHidden(on)
    RunOnGameThread(function()
        local huds = FindAllOf("UI_Horror_C") or {}
        local found = 0
        isUiHidden = not not on
        for i = 1, #huds do
            local w = huds[i]
            if w and w:IsValid() and not string.find(w:GetFullName(), "Default__") then
                if isUiHidden then
                    local sVis, visVal = pcall(function() return w:GetVisibility() end)
                    if sVis and type(visVal) == "number" then
                        savedHudVis = visVal
                    end
                    pcall(function() w:SetVisibility(2) end)
                else
                    pcall(function() w:SetVisibility(savedHudVis or 0) end)
                end
                found = found + 1
            end
        end
        if found == 0 then
            print("[RokuMenu] HUD not found on this map.\n")
            isUiHidden = not isUiHidden
        else
            print(string.format("[RokuMenu] HUD: %s\n", isUiHidden and "HIDDEN" or "VISIBLE"))
            MaintainItemPrompts()
        end
        notify()
    end)
end

function M.FastApples()
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        local gi = GetGameInstance()
        local success = false
        if player then
            pcall(function()
                player.pinecollected = 65
                success = true
            end)
        end
        if gi then
            pcall(function()
                gi.PineCountGI = 65
                success = true
            end)
        end
        if success then
            print("[RokuMenu] Apples set to 65/66.\n")
        else
            print("[RokuMenu] Could not set apples.\n")
        end
    end)
end

function M.SetOutfit(idx)
    idx = tonumber(idx) or idx
    RunOnGameThread(function()
        local roku = GetRoku()
        if not roku then
            print("[RokuMenu] Roku not found.\n")
            return
        end
        if not skins[idx] then return end
        currentSkinIdx = idx
        skins[idx].apply(roku)
        ApplyGhostState(roku, isGhostMode or isRokuFrozen)
        print(string.format("[RokuMenu] Outfit [%d/%d] %s\n", idx, #skins, skins[idx].name))
        notify()
    end)
end

function M.CycleOutfit()
    M.SetOutfit((currentSkinIdx % #skins) + 1)
end

function M.ResetOutfit()
    M.SetOutfit(1)
end

function M.MaxDrunk()
    RunOnGameThread(function()
        local roku = GetRoku()
        if not roku then
            print("[RokuMenu] Roku not found.\n")
            return
        end
        pcall(function() roku.Drunk_level = 1.5 end)
        pcall(function() roku:DrunkMode() end)
        if roku.NS_drunk and roku.NS_drunk:IsValid() then
            pcall(function()
                roku.NS_drunk:Activate(true)
                roku.NS_drunk:SetVisibility(true, true)
            end)
        end
        print("[RokuMenu] Max Drunk.\n")
    end)
end

-- Spank hold, cowbell, and the thrown-item montages.
local function ApplySpankable(on)
    local roku = GetRoku()
    if not roku then return end
    pcall(function() roku.bSpankable = on and true or false end)
end

function M.SetSpankable(on)
    isSpankHold = not not on
    RunOnGameThread(function()
        ApplySpankable(isSpankHold)
        print(string.format("[RokuMenu] Spankable %s\n", isSpankHold and "ON" or "OFF"))
        notify()
    end)
end

function M.RefreshSpankable()
    if not isSpankHold then return end
    RunOnGameThread(function()
        ApplySpankable(true)
    end)
end

function M.ForceSpank()
    M.SetSpankable(not isSpankHold)
end

-- GON 1.3 uses the bell as the Cowmeat unlock. This cheat does not call cb_event.
local cowbellRemoved = true

function M.SetCowbell(on)
    if cowbellRemoved then
        isCowbell = false
        if on then
            print("[RokuMenu] Cowbell cheat stays off. GON 1.3 uses the bell for Cowmeat.\n")
            notify()
        end
        return
    end
    isCowbell = not not on
    RunOnGameThread(function()
        local roku = GetRoku()
        if not roku then
            print("[RokuMenu] Cowbell: Roku not found.\n")
            return
        end
        if isCowbell then
            pcall(function() roku:cb_event() end)
            pcall(function() roku.bIsCowbellOn = true end)
        else
            pcall(function() roku:cb_off() end)
            pcall(function() roku.bIsCowbellOn = false end)
        end
        print(string.format("[RokuMenu] Cowbell %s\n", isCowbell and "ON" or "OFF"))
        notify()
    end)
end

function M.ReapplyCowbell(roku)
    if cowbellRemoved or not isCowbell or not roku then return end
    pcall(function() roku:cb_event() end)
    pcall(function() roku.bIsCowbellOn = true end)
end

local itemMontages = {}
local itemHoldUntil = 0
local itemHoldSpeed = nil
local itemHoldMontage = nil
local itemHoldStart = 0
local itemHoldBump = nil
local itemHoldVisionMuted = false
local itemHoldPausedBrain = false
local itemHoldReplayAt = 0
local itemHoldRot = nil

local function LoadItemMontage(name)
    if itemMontages[name] and itemMontages[name]:IsValid() then
        return itemMontages[name]
    end
    local path = "/Game/ROKUv3/Roku_Interaction/" .. name .. "." .. name
    local full = "AnimMontage " .. path
    local asset = nil
    pcall(function() asset = StaticFindObject(full) end)
    if not asset or not asset:IsValid() then
        pcall(function() asset = StaticFindObject(path) end)
    end
    if not asset or not asset:IsValid() then
        local ok, err = pcall(function() asset = LoadAsset(path) end)
        if not ok then
            print("[RokuMenu] LoadAsset error: " .. tostring(err) .. "\n")
            asset = nil
        end
    end
    if not asset or not asset:IsValid() then
        print("[RokuMenu] Montage missing: " .. full .. "\n")
        return nil
    end
    itemMontages[name] = asset
    print("[RokuMenu] Montage found: " .. full .. "\n")
    return asset
end

local function ShowRokuPart(roku, name)
    local comp = roku[name]
    if not comp or not comp:IsValid() then
        print("[RokuMenu] Item part missing: " .. tostring(name) .. "\n")
        return
    end
    pcall(function() comp:SetVisibility(true, true) end)
    pcall(function() comp:SetHiddenInGame(false, true) end)
end

function M.PlayItem(which)
    RunOnGameThread(function()
        local roku = GetRoku()
        if not roku then
            print("[RokuMenu] Item: Roku not found.\n")
            return
        end
        local items = {
            apple = { mesh = "i_apple", call = "AppleVis", montage = "MHIT_apple_facefbx_Montage" },
            carrot = { mesh = "I_CARROT", call = "carrotVIS", montage = "MHIT_carrot_face_Montage" },
            wine = { mesh = "I_WINE", call = "WineVis", montage = "MHIT_wine_Montage" },
            beer = { mesh = "I_beer", calls = { "ebeer", "BeerDrunk" }, montage = "mhit_beer_Montage" },
            glowstick = { mesh = "I_GLOWSTICK", call = "GStickVis", light = "gs_light", montage = "MHIT_GSTICK_chest_Montage" },
            flashlight = { mesh = "I_flashlight", call = "FLVis", light = "FlashlightLIGHT", montage = "MHIT_flashlight_chest_Montage" },
        }
        local item = items[which]
        if not item then return end
        ShowRokuPart(roku, item.mesh)
        if item.light then
            ShowRokuPart(roku, item.light)
        end
        if item.calls then
            for i = 1, #item.calls do
                local fname = item.calls[i]
                pcall(function() roku[fname](roku) end)
            end
        elseif item.call then
            pcall(function() roku[item.call](roku) end)
        end
        local montage = LoadItemMontage(item.montage)
        local played = false
        local why = "no montage"
        if montage then
            local mesh = GetMesh(roku)
            local anim = nil
            if mesh then pcall(function() anim = mesh:GetAnimInstance() end) end
            local ok, err = nil, nil
            local length = nil
            if anim and anim:IsValid() then
                pcall(function()
                    local blendIn = montage.BlendIn
                    blendIn.BlendTime = 0.0
                    montage.BlendIn = blendIn
                end)
                -- Montage, rate, return type, start time, stop other montages.
                ok, length = pcall(function() return anim:Montage_Play(montage, 1.0, 0, 0.0, true) end)
                err = length
            else
                err = "no anim instance"
            end
            if ok then
                played = true
                local seconds = 4.5
                if type(length) == "number" and length > 0.2 and length < 20 then
                    seconds = length
                end
                M.HoldRokuForItem(roku, seconds, montage)
            else
                why = "Montage_Play: " .. tostring(err)
                local section = nil
                pcall(function() section = FName("None") end)
                local ok2, err2 = pcall(function() roku:PlayAnimMontage(montage, 1.0, section) end)
                if ok2 then
                    played = true
                else
                    why = why .. " | PlayAnimMontage: " .. tostring(err2)
                end
            end
        end
        if played then
            print("[RokuMenu] Item " .. which .. " montage played\n")
        else
            print("[RokuMenu] Item " .. which .. " montage failed. " .. why .. "\n")
        end
    end)
end

-- Follow uses a very short detection distance and the same calm state as ghost.
-- Ghost and Follow turn each other off.
local function ReadDistances(player)
    local d = StockDistances()
    pcall(function() if player.EasyDistanceCheckA > 100 then d.a = player.EasyDistanceCheckA end end)
    pcall(function() if player.EasyDistanceCheckB > 50 then d.b = player.EasyDistanceCheckB end end)
    pcall(function() if player.HardDistanceCheckA > 100 then d.c = player.HardDistanceCheckA end end)
    pcall(function() if player.HardDistanceCheckB > 50 then d.d = player.HardDistanceCheckB end end)
    return d
end

local function WriteDistances(player, d)
    if not player or not d then return end
    pcall(function() player.EasyDistanceCheckA = d.a end)
    pcall(function() player.EasyDistanceCheckB = d.b end)
    pcall(function() player.HardDistanceCheckA = d.c end)
    pcall(function() player.HardDistanceCheckB = d.d end)
end

local function ApplyFollowCalm(roku, on)
    if not roku or not roku:IsValid() then return end
    if on then
        QuietBlind(roku)
        SetVolume(roku.VisionBox, false)
        SetVolume(roku.HearingSphere, false)
        for i = 1, #slapVolumes do
            SetVolume(roku[slapVolumes[i]], false)
        end
    else
        pcall(function() roku.HasAttacked = false end)
        pcall(function() roku.bCanBump = true end)
        pcall(function() roku.bSensesEnabled = true end)
        if not isGhostMode and not isRokuFrozen then
            SetVolume(roku.VisionBox, true)
            SetVolume(roku.HearingSphere, true)
            for i = 1, #slapVolumes do
                SetVolume(roku[slapVolumes[i]], true)
            end
        end
    end
end

local function DropChaseOnceForFollow(roku)
    if not roku or not roku:IsValid() then return end
    pcall(function() roku:OnLostPlayer() end)
    local ctrl = roku.Controller
    if ctrl and ctrl:IsValid() then
        pcall(function() ctrl:CancelChase() end)
    end
end

function M.SetFollow(on)
    on = not not on
    if on and isFreecam then
        print("[RokuMenu] Follow blocked while freecam is on\n")
        notify()
        return
    end
    isFollow = on
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        local roku = GetRoku()
        if not player then
            print("[RokuMenu] Follow: player not found.\n")
            return
        end
        if isFollow then
            if isGhostMode then
                isGhostMode = false
                ghostHeldByFreecam = false
                print("[RokuMenu] Ghost OFF because Follow was turned on.\n")
            end
            if followSaved == nil then
                followSaved = ReadDistances(player)
            end
            WriteDistances(player, { a = 53, b = 53, c = 53, d = 53 })
            DropChaseOnceForFollow(roku)
            ApplyFollowCalm(roku, true)
            print("[RokuMenu] Follow ON. Distance 53, chase and swat volumes off.\n")
        else
            WriteDistances(player, followSaved or StockDistances())
            ApplyFollowCalm(roku, false)
            print("[RokuMenu] Follow OFF. Distance and volumes restored.\n")
        end
        notify()
    end)
end

function M.ReapplyFollow()
    if not isFollow then return end
    local player = GetPlayerPawn()
    local roku = GetRoku()
    WriteDistances(player, { a = 53, b = 53, c = 53, d = 53 })
    ApplyFollowCalm(roku, true)
end

function M.ToggleGod() M.SetGod(not isGodMode) end
function M.ToggleStamina() M.SetStamina(not isInfStamina) end
function M.ToggleGhost() M.SetGhost(not isGhostMode) end
function M.ToggleFrozen() M.SetFrozen(not isRokuFrozen) end
function M.ToggleSlow() M.SetSlow(not isRokuSlow) end
function M.ToggleUI() M.SetUIHidden(not isUiHidden) end

local userSettings = {
    lock = true,
    hasSaved = false,
    mouse = 1.0,
    master = 1.0,
    music = 1.0,
    sfx = 1.0,
}
-- Mouse, music, and effects. A blank number is ignored and not written to the game.
-- Music used to write a save object that is not in memory, so it never applied.
-- Effects used to set the engine SFX class and the game's SC_SoundFX class together.
local soundMixPushed = false
local soundBaseRestored = false

local function ObjectName(obj)
    local full = ""
    pcall(function() full = obj:GetFullName() end)
    return string.lower(full)
end

-- Item circles are WIDGET_CIRCLE / WIDGET_DOT, not part of UI_Horror.
-- Fade them and hide the component. Do not call SetVisibility on these
-- widgets: putting them back to SelfHitTestInvisible crashed the game.
local promptsHidden = false
local promptTracked = {}
local promptSeen = {}

local function ObjectAddress(obj)
    local addr = nil
    local ok = pcall(function() addr = obj:GetAddress() end)
    if ok and type(addr) == "number" then return string.format("%x", addr) end
    local name = ObjectName(obj)
    if name ~= "" then return name end
    return nil
end

local function MarkOnce(obj)
    local addr = ObjectAddress(obj)
    if not addr or promptSeen[addr] then return false end
    promptSeen[addr] = true
    return true
end

local function OuterComponent(widget)
    local obj = widget
    for _ = 1, 5 do
        if not obj or not obj.IsValid or not obj:IsValid() then return nil end
        if string.find(ObjectName(obj), "widgetcomponent", 1, true) then return obj end
        local outer = nil
        local ok = pcall(function() outer = obj:GetOuter() end)
        if not ok or outer == nil or outer == obj then return nil end
        obj = outer
    end
    return nil
end

local function HideCircleWidget(widget)
    if not widget or not widget.IsValid or not widget:IsValid() then return end
    if string.find(ObjectName(widget), "default__", 1, true) then return end
    if not MarkOnce(widget) then return end
    local opacity = 1
    pcall(function() opacity = widget:GetRenderOpacity() end)
    pcall(function() widget:SetRenderOpacity(0) end)
    local comp = OuterComponent(widget)
    local compWas = nil
    if comp and comp:IsValid() and MarkOnce(comp) then
        local was = false
        pcall(function() was = comp.bHiddenInGame == true end)
        compWas = was
        pcall(function() comp:SetHiddenInGame(true) end)
    end
    promptTracked[#promptTracked + 1] = {
        widget = widget,
        opacity = opacity,
        comp = comp,
        compWas = compWas,
    }
end

local function ApplyPromptHide()
    local names = { "WIDGET_CIRCLE_C", "WIDGET_DOT_C" }
    for c = 1, #names do
        local list = nil
        local ok = pcall(function() list = FindAllOf(names[c]) end)
        if ok and type(list) == "table" then
            for i = 1, #list do
                HideCircleWidget(list[i])
            end
        end
    end
end

local function RestoreItemPrompts()
    for i = 1, #promptTracked do
        local entry = promptTracked[i]
        local widget = entry.widget
        if widget and widget.IsValid and widget:IsValid() then
            pcall(function() widget:SetRenderOpacity(entry.opacity or 1) end)
        end
        local comp = entry.comp
        if comp and entry.compWas ~= nil and comp.IsValid and comp:IsValid() then
            pcall(function() comp:SetHiddenInGame(entry.compWas) end)
        end
    end
    promptTracked = {}
    promptSeen = {}
end

function MaintainItemPrompts()
    if isUiHidden then
        ApplyPromptHide()
        if not promptsHidden then
            promptsHidden = true
            print(string.format("[RokuMenu] Item circles hidden (%d)\n", #promptTracked))
        end
    elseif promptsHidden then
        RestoreItemPrompts()
        promptsHidden = false
        print("[RokuMenu] Item circles restored\n")
    end
end

local function FindLive(className)
    local list = FindAllOf(className) or {}
    for i = 1, #list do
        local obj = list[i]
        if obj and obj:IsValid() and not string.find(ObjectName(obj), "default__", 1, true) then
            return obj
        end
    end
    return nil
end

local function FindLoaded(path)
    if not StaticFindObject then return nil end
    local obj = nil
    local ok = pcall(function() obj = StaticFindObject(path) end)
    if ok and obj and obj.IsValid and obj:IsValid() then return obj end
    return nil
end

local function FindOrLoad(path)
    local obj = FindLoaded(path)
    if obj then return obj end
    if LoadAsset then
        local loaded = nil
        local ok = pcall(function() loaded = LoadAsset(path) end)
        if ok and loaded and loaded.IsValid and loaded:IsValid() then return loaded end
    end
    return nil
end

local function GetHelpers()
    local ueh = nil
    pcall(function() ueh = require("UEHelpers.UEHelpers") end)
    if not ueh then
        pcall(function() ueh = require("UEHelpers") end)
    end
    return ueh
end

local function GetGameplayStatics()
    local ueh = GetHelpers()
    if not ueh or not ueh.GetGameplayStatics then return nil end
    local gs = nil
    local ok = pcall(function() gs = ueh.GetGameplayStatics() end)
    if ok and gs and gs.IsValid and gs:IsValid() then return gs end
    return nil
end

local function WorldContext()
    local pc = FindFirstOf("PlayerController")
    if pc and pc:IsValid() and not string.find(ObjectName(pc), "default__", 1, true) then
        return pc
    end
    return GetPlayerPawn()
end

local function FindSoundClass(substr)
    local list = FindAllOf("SoundClass") or {}
    for i = 1, #list do
        local sc = list[i]
        if sc and sc:IsValid() and string.find(ObjectName(sc), substr, 1, true) then
            return sc
        end
    end
    return nil
end

local function SetClassVolume(sc, volume)
    if not sc or volume == nil then return false end
    local ok = pcall(function() sc.Properties.Volume = volume end)
    return ok == true
end

-- Undo the old write that pinned engine SFX and the game classes to the slider.
local function RestoreSoundBases()
    if soundBaseRestored then return end
    soundBaseRestored = true
    SetClassVolume(FindSoundClass("/enginesounds/sfx.sfx"), 1.0)
    SetClassVolume(FindSoundClass("/enginesounds/music.music"), 1.0)
    SetClassVolume(FindSoundClass("sc_soundfx"), 1.0)
end

local function ApplyOneSound(gs, world, mix, classObj, volume)
    if volume == nil then return "skip" end
    if gs and world and mix and classObj then
        local ok = pcall(function()
            gs:SetSoundMixClassOverride(world, mix, classObj, volume, 1.0, 0.0, false)
        end)
        if ok then return "mix" end
    end
    if SetClassVolume(classObj, volume) then return "class" end
    return "no"
end

local function WriteSettingsSave(mouse, music, sfx)
    local gs = GetGameplayStatics()
    if not gs then return false end
    local save = nil
    local loaded = pcall(function()
        if gs:DoesSaveGameExist("SettingsSlot", 0) then
            save = gs:LoadGameFromSlot("SettingsSlot", 0)
        end
    end)
    if not loaded or not save or not save.IsValid or not save:IsValid() then
        return false
    end
    if mouse ~= nil then pcall(function() save.MouseSen = mouse end) end
    if music ~= nil then pcall(function() save.MusicVolume = music end) end
    if sfx ~= nil then pcall(function() save.EffectsVolume = sfx end) end
    local stored = false
    pcall(function() stored = gs:SaveGameToSlot(save, "SettingsSlot", 0) end)
    return stored == true
end

function M.ApplyUserSettings()
    if not userSettings.hasSaved then return end
    local mouseSet = false
    if userSettings.mouse ~= nil then
        local player = GetPlayerPawn()
        if player then
            local ok = pcall(function() player.mouseSEN = userSettings.mouse end)
            mouseSet = ok
        end
        local gi = GetGameInstance()
        if gi then
            pcall(function() gi.MouseSensitivity = userSettings.mouse end)
        end
    end

    RestoreSoundBases()
    local gs = GetGameplayStatics()
    local world = WorldContext()
    local mix = FindOrLoad("/Game/Variant_Horror/Menus/SoundMix_Main.SoundMix_Main")
        or FindOrLoad("/Game/Variant_Horror/Menus/SoundMix_Main")
    local musicClass = FindLoaded("/Engine/EngineSounds/Music.Music")
        or FindSoundClass("/enginesounds/music.music")
    local fxClass = FindLoaded("/Game/MinimalisticMenu/Audio/SoundClass/SC_SoundFX.SC_SoundFX")
        or FindSoundClass("sc_soundfx")
    local musicHow = ApplyOneSound(gs, world, mix, musicClass, userSettings.music)
    local fxHow = ApplyOneSound(gs, world, mix, fxClass, userSettings.sfx)
    if mix and gs and world and not soundMixPushed and (musicHow == "mix" or fxHow == "mix") then
        local pushed = pcall(function() gs:PushSoundMixModifier(world, mix) end)
        if pushed then soundMixPushed = true end
    end
    local saved = WriteSettingsSave(userSettings.mouse, userSettings.music, userSettings.sfx)
    print(string.format(
        "[RokuMenu] Applied mouse=%s (%s) music=%s (%s) effects=%s (%s) save=%s\n",
        tostring(userSettings.mouse), mouseSet and "ok" or "no pawn",
        tostring(userSettings.music), musicHow,
        tostring(userSettings.sfx), fxHow,
        saved and "ok" or "no"
    ))
end

-- Same steps as the game Quality dropdown, one group at a time.
-- 0 Low, 1 Medium, 2 High, 3 Epic, 4 Cinematic.
M.QualityOptions = {
    { label = "Low", value = "0" },
    { label = "Medium", value = "1" },
    { label = "High", value = "2" },
    { label = "Epic", value = "3" },
    { label = "Cinematic", value = "4" },
}
M.GraphicsRows = {
    { id = "gfxView", label = "View distance", set = "SetViewDistanceQuality", get = "GetViewDistanceQuality", cmd = "sg.ViewDistanceQuality" },
    { id = "gfxAa", label = "Anti-aliasing", set = "SetAntiAliasingQuality", get = "GetAntiAliasingQuality", cmd = "sg.AntiAliasingQuality" },
    { id = "gfxShadow", label = "Shadows", set = "SetShadowQuality", get = "GetShadowQuality", cmd = "sg.ShadowQuality" },
    { id = "gfxGi", label = "Global illumination", set = "SetGlobalIlluminationQuality", get = "GetGlobalIlluminationQuality", cmd = "sg.GlobalIlluminationQuality" },
    { id = "gfxRefl", label = "Reflections", set = "SetReflectionQuality", get = "GetReflectionQuality", cmd = "sg.ReflectionQuality" },
    { id = "gfxPp", label = "Post process", set = "SetPostProcessQuality", get = "GetPostProcessQuality", cmd = "sg.PostProcessQuality" },
    { id = "gfxTex", label = "Textures", set = "SetTextureQuality", get = "GetTextureQuality", cmd = "sg.TextureQuality" },
    { id = "gfxFx", label = "Effects", set = "SetEffectsQuality", get = "GetEffectsQuality", cmd = "sg.EffectsQuality" },
    { id = "gfxFoliage", label = "Foliage", set = "SetFoliageQuality", get = "GetFoliageQuality", cmd = "sg.FoliageQuality" },
    { id = "gfxShade", label = "Shading", set = "SetShadingQuality", get = "GetShadingQuality", cmd = "sg.ShadingQuality" },
    { id = "gfxLand", label = "Landscape", set = "SetLandscapeQuality", get = "GetLandscapeQuality", cmd = "sg.LandscapeQuality" },
}

local function GraphicsRow(id)
    for i = 1, #M.GraphicsRows do
        if M.GraphicsRows[i].id == id then return M.GraphicsRows[i] end
    end
    return nil
end

local function GetGameUserSettings()
    return FindLive("GameUserSettings")
end

local function ExecConsole(cmd)
    local world = WorldContext()
    local ueh = GetHelpers()
    local lib = nil
    if ueh and ueh.GetKismetSystemLibrary then
        pcall(function() lib = ueh.GetKismetSystemLibrary() end)
    end
    if lib and lib.IsValid and lib:IsValid() and world then
        local ok = pcall(function() lib:ExecuteConsoleCommand(world, cmd, world) end)
        if ok then return true end
    end
    if world and world.ConsoleCommand then
        local ok = pcall(function() world:ConsoleCommand(cmd, true) end)
        if ok then return true end
    end
    return false
end

local function ReadGraphicsRaw(id)
    local row = GraphicsRow(id)
    if not row then return nil end
    local gus = GetGameUserSettings()
    if not gus then return nil end
    local value = nil
    local ok = pcall(function() value = gus[row.get](gus) end)
    local n = ok and tonumber(value) or nil
    if n == nil then return nil end
    return tostring(math.floor(n + 0.5))
end

function M.ReadGraphicsLevel(id)
    return ReadGraphicsRaw(id) or "2"
end

-- Live rows follow the engine, including the game Quality menu.
-- gfxWanted is the snapshot put back on map load when the toggle is on.
local gfxForce = false
local gfxWanted = {}
local gfxSeen = {}
local gfxStore = nil
local gfxApplying = false
local gfxQuiet = false

local function SaveGraphicsPrefs()
    if not gfxStore then return end
    local copy = {}
    for i = 1, #M.GraphicsRows do
        local id = M.GraphicsRows[i].id
        if gfxWanted[id] ~= nil then copy[id] = gfxWanted[id] end
    end
    gfxStore(gfxForce, copy)
end

function M.SetGraphicsLevel(id, value)
    local row = GraphicsRow(id)
    local n = tonumber(value)
    if not row or n == nil then return false end
    n = math.floor(n + 0.5)
    if n < 0 then n = 0 end
    if n > 4 then n = 4 end
    local gus = GetGameUserSettings()
    local how = "no"
    if gus then
        local ok = pcall(function() gus[row.set](gus, n) end)
        if ok then how = "settings" end
    end
    if how == "no" and ExecConsole(row.cmd .. " " .. tostring(n)) then
        how = "console"
    end
    if gus and how ~= "no" and not gfxApplying then
        pcall(function() gus:ApplyNonResolutionSettings() end)
        pcall(function() gus:SaveSettings() end)
    end
    local text = tostring(n)
    gfxWanted[id] = text
    gfxSeen[id] = text
    if not gfxApplying then SaveGraphicsPrefs() end
    if not gfxQuiet then
        print(string.format("[RokuMenu] Graphics %s=%d (%s)\n", row.label, n, how))
    end
    return how ~= "no"
end

function M.SetGraphicsStore(fn)
    gfxStore = fn
end

function M.LoadGraphicsPrefs(saved)
    if type(saved) ~= "table" then return end
    gfxForce = saved.force == true
    if type(saved.wanted) == "table" then
        for i = 1, #M.GraphicsRows do
            local id = M.GraphicsRows[i].id
            if saved.wanted[id] ~= nil then
                gfxWanted[id] = tostring(saved.wanted[id])
            end
        end
    end
end

function M.CaptureGraphicsWanted()
    for i = 1, #M.GraphicsRows do
        local id = M.GraphicsRows[i].id
        local live = ReadGraphicsRaw(id)
        if live ~= nil then
            gfxWanted[id] = live
            gfxSeen[id] = live
        end
    end
    SaveGraphicsPrefs()
end

function M.SetGraphicsForce(on)
    gfxForce = not not on
    if gfxForce then
        M.CaptureGraphicsWanted()
    else
        SaveGraphicsPrefs()
    end
    print(string.format("[RokuMenu] Force graphics on map load: %s\n", gfxForce and "ON" or "OFF"))
end

function M.ApplySavedGraphics()
    if not gfxForce then return end
    gfxApplying = true
    gfxQuiet = true
    local applied = 0
    for i = 1, #M.GraphicsRows do
        local id = M.GraphicsRows[i].id
        if gfxWanted[id] ~= nil and M.SetGraphicsLevel(id, gfxWanted[id]) then
            applied = applied + 1
        end
    end
    local gus = GetGameUserSettings()
    if gus and applied > 0 then
        pcall(function() gus:ApplyNonResolutionSettings() end)
        pcall(function() gus:SaveSettings() end)
    end
    gfxQuiet = false
    gfxApplying = false
    print(string.format("[RokuMenu] Graphics forced after map load (%d rows)\n", applied))
    notify()
end

function M.PollGraphics()
    if gfxApplying then return false end
    local changed = false
    for i = 1, #M.GraphicsRows do
        local row = M.GraphicsRows[i]
        local live = ReadGraphicsRaw(row.id)
        if live ~= nil then
            local prev = gfxSeen[row.id]
            gfxSeen[row.id] = live
            if prev ~= nil and prev ~= live then
                changed = true
                print(string.format("[RokuMenu] Game changed %s %s -> %s\n", row.label, prev, live))
            end
        end
    end
    if changed then notify() end
    return changed
end

function M.LoadUserSettings(saved)
    if type(saved) ~= "table" then return end
    if saved.hasSaved ~= nil then userSettings.hasSaved = saved.hasSaved and true or false end
    if saved.mouse ~= nil then userSettings.mouse = tonumber(saved.mouse) or userSettings.mouse end
    if saved.master ~= nil then userSettings.master = tonumber(saved.master) or userSettings.master end
    if saved.music ~= nil then userSettings.music = tonumber(saved.music) or userSettings.music end
    if saved.sfx ~= nil then userSettings.sfx = tonumber(saved.sfx) or userSettings.sfx end
end

function M.SetUserSetting(key, value)
    local n = tonumber(value)
    if n == nil then
        return false
    end
    userSettings[key] = n
    userSettings.hasSaved = true
    return true
end

function M.GetUserSettings()
    return {
        lock = userSettings.lock,
        hasSaved = userSettings.hasSaved,
        mouse = userSettings.mouse,
        master = userSettings.master,
        music = userSettings.music,
        sfx = userSettings.sfx,
    }
end

-- Noclip and freecam share the fly keys.
-- Noclip teleports the body and keeps physics off. Exit stays in noclip while inside a wall.
local function Vec(x, y, z)
    return { X = x, Y = y, Z = z }
end

local function ReadVec(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
    local x, y, z = v.X or v.x, v.Y or v.y, v.Z or v.z
    if x == nil then return nil end
    return x, y, z
end

local function CopyVec(v)
    local x, y, z = ReadVec(v)
    if not x then return nil end
    return { X = x, Y = y, Z = z }
end

local function CopyRot(r)
    if type(r) ~= "table" and type(r) ~= "userdata" then return nil end
    local p, y, rl = r.Pitch or r.pitch, r.Yaw or r.yaw, r.Roll or r.roll
    if p == nil and y == nil and rl == nil then return nil end
    return { Pitch = p or 0, Yaw = y or 0, Roll = rl or 0 }
end

local function ForwardRight(rot)
    local yaw = math.rad(rot.Yaw or rot.yaw or 0)
    local pitch = math.rad(rot.Pitch or rot.pitch or 0)
    local cp = math.cos(pitch)
    local fx, fy, fz = cp * math.cos(yaw), cp * math.sin(yaw), math.sin(pitch)
    local rx, ry = -math.sin(yaw), math.cos(yaw)
    return fx, fy, fz, rx, ry
end

local function EnsureFlyKeys()
    if flyKeys ~= nil then return flyKeys end
    flyKeys = false
    local ueh = nil
    pcall(function() ueh = require("UEHelpers.UEHelpers") end)
    if not ueh or not ueh.FindOrAddFName then return flyKeys end
    local function fkey(name)
        local fname = ueh.FindOrAddFName(name)
        if not fname then return nil end
        return { KeyName = fname }
    end
    flyKeys = {
        W = fkey("W"), A = fkey("A"), S = fkey("S"), D = fkey("D"),
        Space = fkey("SpaceBar"), X = fkey("X"),
    }
    return flyKeys
end

local function Held(pc, fkey)
    if not pc or not fkey then return false end
    local ok, down = pcall(function() return pc:IsInputKeyDown(fkey) == true end)
    if ok then return down == true end
    if fkey.KeyName then
        ok, down = pcall(function() return pc:IsInputKeyDown(fkey.KeyName) == true end)
        if ok then return down == true end
    end
    return false
end

local function Axis(pc, keys, pos, neg)
    local v = 0
    if Held(pc, keys[pos]) then v = v + 1 end
    if Held(pc, keys[neg]) then v = v - 1 end
    return v
end

local function PlayerBaseSpeed(player)
    local speed = 240
    pcall(function()
        local w = player["Walk Speed"]
        if type(w) == "number" and w > 1 then speed = w end
    end)
    return speed
end

-- TeleportTo does not write a hit result. SetActorLocation does, and that spams the console.
local function SetActorPos(actor, x, y, z)
    if math.abs(x) > 1000000 or math.abs(y) > 1000000 or math.abs(z) > 1000000 then return end
    local rot = nil
    pcall(function() rot = actor:K2_GetActorRotation() end)
    if not rot then rot = { Pitch = 0, Yaw = 0, Roll = 0 } end
    pcall(function() actor:K2_TeleportTo(Vec(x, y, z), rot) end)
end

local function KillNoclipPhysics(player)
    pcall(function()
        local cap = player.CapsuleComponent
        if cap and cap:IsValid() then cap:SetCollisionEnabled(0) end
    end)
    pcall(function() player:SetActorEnableCollision(false) end)
    pcall(function()
        local cm = player.CharacterMovement
        if cm and cm:IsValid() then
            cm.Velocity = Vec(0, 0, 0)
            cm.GravityScale = 0
            cm:SetMovementMode(0)
            cm:SetComponentTickEnabled(false)
        end
    end)
end

local function MoveActor(actor, dx, dy, dz)
    if dx == 0 and dy == 0 and dz == 0 then return end
    local loc = nil
    pcall(function() loc = actor:K2_GetActorLocation() end)
    local x, y, z = ReadVec(loc)
    if not x then return end
    if math.abs(dx) > 200 then dx = dx > 0 and 200 or -200 end
    if math.abs(dy) > 200 then dy = dy > 0 and 200 or -200 end
    if math.abs(dz) > 200 then dz = dz > 0 and 200 or -200 end
    SetActorPos(actor, x + dx, y + dy, z + dz)
end

local function MoveCamera(cam, dx, dy, dz, rot)
    if dx ~= 0 or dy ~= 0 or dz ~= 0 then
        local loc = nil
        pcall(function() loc = cam:K2_GetComponentLocation() end)
        local x, y, z = ReadVec(loc)
        if x then
            if math.abs(dx) > 200 then dx = dx > 0 and 200 or -200 end
            if math.abs(dy) > 200 then dy = dy > 0 and 200 or -200 end
            if math.abs(dz) > 200 then dz = dz > 0 and 200 or -200 end
            pcall(function()
                cam.RelativeLocation = Vec(x + dx, y + dy, z + dz)
            end)
        end
    end
    if rot then
        pcall(function() cam.RelativeRotation = rot end)
    end
end

function M.BumpFlySpeed(dir)
    local nextScale = flyScale + (dir * 0.1)
    if nextScale < 0.1 then nextScale = 0.1 end
    if nextScale > 3.0 then nextScale = 3.0 end
    flyScale = math.floor(nextScale * 10 + 0.5) / 10
    print(string.format("[RokuMenu] Fly speed %d%%\n", math.floor(flyScale * 100 + 0.5)))
    notify()
end

local function StopFreecam(player)
    local cam = player and player.FirstPersonCamera
    if cam and cam:IsValid() then
        pcall(function() cam:SetAbsolute(false, false, false) end)
        if savedCamRel then
            pcall(function() cam.RelativeLocation = savedCamRel end)
            pcall(function() cam:K2_SetRelativeLocation(savedCamRel, false, {}, true) end)
        end
        if savedCamRot then
            pcall(function() cam.RelativeRotation = savedCamRot end)
            pcall(function() cam:K2_SetRelativeRotation(savedCamRot, false, {}, true) end)
        end
        print(string.format(
            "[RokuMenu] Camera restored to %.1f %.1f %.1f\n",
            savedCamRel and savedCamRel.X or 0,
            savedCamRel and savedCamRel.Y or 0,
            savedCamRel and savedCamRel.Z or 0
        ))
    end
    savedPawnLoc = nil
    savedCamRel = nil
    savedCamRot = nil
end

local function GetKismet()
    local ueh = nil
    pcall(function() ueh = require("UEHelpers.UEHelpers") end)
    if not ueh or not ueh.GetKismetSystemLibrary then
        pcall(function() ueh = require("UEHelpers") end)
    end
    if not ueh or not ueh.GetKismetSystemLibrary then return nil end
    local lib = nil
    local ok = pcall(function() lib = ueh.GetKismetSystemLibrary() end)
    if ok and lib and lib.IsValid and lib:IsValid() then return lib end
    return nil
end

local traceColor = { R = 0, G = 0, B = 0, A = 0 }

-- true = geometry occupies the capsule, false = empty, nil = the trace did not run.
local function CapsuleBlocked(kismet, player, x, y, z, radius, half)
    local hit = {}
    local ok, wasHit = pcall(function()
        return kismet:CapsuleTraceSingle(
            player,
            Vec(x, y, z),
            Vec(x, y, z + 2),
            radius,
            half,
            0,
            false,
            { player },
            0,
            hit,
            true,
            traceColor,
            traceColor,
            0
        )
    end)
    if not ok then return nil end
    return wasHit == true
end

-- Centimetres of open air above this spot before a ceiling. 0 means the trace started inside geometry.
local function UpClearance(kismet, player, x, y, z)
    local hit = {}
    local ok, wasHit = pcall(function()
        return kismet:LineTraceSingle(
            player,
            Vec(x, y, z),
            Vec(x, y, z + 800),
            0,
            false,
            { player },
            0,
            hit,
            true,
            traceColor,
            traceColor,
            0
        )
    end)
    if not ok then return nil end
    if wasHit ~= true then return 800 end
    local pen = false
    pcall(function()
        pen = hit.bStartPenetrating == true or hit.StartPenetrating == true
    end)
    if pen then return 0 end
    local dist = nil
    pcall(function() dist = hit.Distance end)
    if type(dist) ~= "number" then
        pcall(function() dist = hit.distance end)
    end
    if type(dist) ~= "number" then return 0 end
    return dist
end

-- true only when a floor is within 2m under the capsule. Sky and a blind trace are not clear.
local function FloorUnder(kismet, player, x, y, z)
    local hit = {}
    local ok, wasHit = pcall(function()
        return kismet:LineTraceSingle(
            player,
            Vec(x, y, z),
            Vec(x, y, z - 200),
            0,
            false,
            { player },
            0,
            hit,
            true,
            traceColor,
            traceColor,
            0
        )
    end)
    if not ok then return nil end
    return wasHit == true
end

-- Collision stays off during the search. The player is moved only after a spot
-- is empty and has a floor within 2m, and never more than 4m above the exit spot.
local function StopNoclip(player)
    if not player or not player:IsValid() then return false end
    local loc = nil
    pcall(function() loc = player:K2_GetActorLocation() end)
    local x, y, z = ReadVec(loc)
    if not x then
        print("[RokuMenu] Noclip stayed on. Position could not be read.\n")
        return false
    end
    local half = 90
    local radius = 34
    local cap = nil
    pcall(function() cap = player.CapsuleComponent end)
    if cap and cap:IsValid() then
        pcall(function()
            local h = cap:GetUnscaledCapsuleHalfHeight()
            if type(h) == "number" and h >= 10 and h <= 200 then half = h end
        end)
        pcall(function()
            local r = cap:GetUnscaledCapsuleRadius()
            if type(r) == "number" and r >= 5 and r <= 80 then radius = r end
        end)
    end
    local kismet = GetKismet()
    if not kismet then
        print("[RokuMenu] Noclip stayed on. Exit trace unavailable.\n")
        return false
    end
    local testHalf = half * 0.85
    local testRadius = radius * 0.85
    local clearance = UpClearance(kismet, player, x, y, z)
    if clearance == nil then
        print("[RokuMenu] Noclip stayed on. Exit trace failed.\n")
        return false
    end
    local found = nil
    for rise = 0, 400, 50 do
        if rise > 0 and (clearance >= 800 or rise + testHalf >= clearance - 5) then break end
        local blocked = CapsuleBlocked(kismet, player, x, y, z + rise, testRadius, testHalf)
        local floor = FloorUnder(kismet, player, x, y, z + rise)
        if blocked == nil or floor == nil then
            print("[RokuMenu] Noclip stayed on. Exit trace failed.\n")
            return false
        end
        if blocked == false and floor == true then
            found = rise
            break
        end
    end
    if not found then
        print("[RokuMenu] Noclip stayed on. Still inside geometry. Position unchanged.\n")
        return false
    end
    if found > 0 then
        SetActorPos(player, x, y, z + found)
    end
    if cap and cap:IsValid() then
        pcall(function() cap:SetCollisionEnabled(3) end)
    end
    pcall(function() player:SetActorEnableCollision(true) end)
    pcall(function()
        local cm = player.CharacterMovement
        if cm and cm:IsValid() then
            cm.Velocity = Vec(0, 0, 0)
            cm:SetComponentTickEnabled(true)
            cm.GravityScale = 1
            cm:SetMovementMode(1)
        end
    end)
    print(string.format("[RokuMenu] Noclip exit: clear after %dcm\n", found))
    return true
end

function M.SetNoclip(on)
    on = not not on
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if on and isFreecam then
            isFreecam = false
            if player then StopFreecam(player) end
            ReleaseFreecamGhost()
        end
        if not on then
            isNoclip = false
            if not player or not StopNoclip(player) then
                isNoclip = true
                notify()
                return
            end
            print("[RokuMenu] Noclip OFF\n")
            notify()
            return
        end
        if not player then
            print("[RokuMenu] Noclip: player not found\n")
            isNoclip = false
            notify()
            return
        end
        pcall(function()
            local cap = player.CapsuleComponent
            if cap and cap:IsValid() then
                cap:SetCollisionEnabled(0)
            end
        end)
        pcall(function() player:SetActorEnableCollision(false) end)
        pcall(function()
            local cm = player.CharacterMovement
            if cm and cm:IsValid() then
                cm.GravityScale = 0
                cm:SetMovementMode(0)
                cm:SetComponentTickEnabled(false)
            end
        end)
        isNoclip = true
        print("[RokuMenu] Noclip ON. WASD, Space up, X down.\n")
        notify()
    end)
end

function M.SetFreecam(on)
    on = not not on
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if not player then
            print("[RokuMenu] Freecam: player not found\n")
            return
        end
        if on and isNoclip then
            if not StopNoclip(player) then
                print("[RokuMenu] Freecam blocked. Noclip exit spot was not clear.\n")
                isFreecam = false
                isNoclip = true
                notify()
                return
            end
            isNoclip = false
        end
        isFreecam = on
        local cam = player.FirstPersonCamera
        if isFreecam then
            if not cam or not cam:IsValid() then
                print("[RokuMenu] Freecam: no camera\n")
                isFreecam = false
                return
            end
            local pawnLoc = nil
            pcall(function() pawnLoc = player:K2_GetActorLocation() end)
            savedPawnLoc = CopyVec(pawnLoc)
            savedCamRel = CopyVec(cam.RelativeLocation)
            savedCamRot = CopyRot(cam.RelativeRotation)
            local worldLoc = nil
            pcall(function() worldLoc = cam:K2_GetComponentLocation() end)
            worldLoc = CopyVec(worldLoc) or savedPawnLoc
            local worldRot = nil
            pcall(function() worldRot = cam:K2_GetComponentRotation() end)
            worldRot = CopyRot(worldRot)
            if not worldRot then
                local pc = FindFirstOf("PlayerController")
                if pc and pc:IsValid() then
                    pcall(function() worldRot = CopyRot(pc.ControlRotation) end)
                end
            end
            if savedCamRel then
                print(string.format(
                    "[RokuMenu] Camera saved %.1f %.1f %.1f\n",
                    savedCamRel.X, savedCamRel.Y, savedCamRel.Z
                ))
            end
            pcall(function() cam:SetAbsolute(true, true, false) end)
            if worldLoc then
                pcall(function() cam.RelativeLocation = worldLoc end)
                pcall(function() cam:K2_SetRelativeLocation(worldLoc, false, {}, true) end)
                print(string.format(
                    "[RokuMenu] Freecam at %.1f %.1f %.1f\n",
                    worldLoc.X, worldLoc.Y, worldLoc.Z
                ))
            end
            if worldRot then
                pcall(function() cam.RelativeRotation = worldRot end)
                pcall(function() cam:K2_SetRelativeRotation(worldRot, false, {}, true) end)
            end
            HoldGhostForFreecam()
            print("[RokuMenu] Freecam ON. WASD, Space up, X down. Body stays put.\n")
        else
            StopFreecam(player)
            ReleaseFreecamGhost()
            print("[RokuMenu] Freecam OFF\n")
        end
        notify()
    end)
end

-- One hop, 20% over the game's jump speed. Shift sprint pins her to the ground, so jump is skipped then.
function M.TryJump()
    if isNoclip or isFreecam then return end
    local player = GetPlayerPawn()
    if not player or not player:IsValid() then return end
    local cm = nil
    pcall(function() cm = player.CharacterMovement end)
    if not cm or not cm:IsValid() then return end
    local sprinting = false
    pcall(function() sprinting = player["Wants to Sprint"] == true end)
    if sprinting then return end
    local mode = nil
    pcall(function() mode = cm.MovementMode end)
    if mode == 3 then return end
    local grounded = nil
    local okGround = pcall(function() grounded = cm:IsMovingOnGround() end)
    if okGround and grounded == false and mode ~= 1 then return end
    local z = 420
    pcall(function()
        local j = cm.JumpZVelocity
        if type(j) == "number" and j > 100 then z = j end
    end)
    z = z * 1.2
    local ok = pcall(function() player:LaunchCharacter(Vec(0, 0, z), false, true) end)
    if not ok then
        pcall(function() player:Jump() end)
    end
    print("[RokuMenu] Jump\n")
end

function M.FlyTick()
    if not isNoclip and not isFreecam then return end
    local player = GetPlayerPawn()
    local pc = FindFirstOf("PlayerController")
    if not player or not player:IsValid() or not pc or not pc:IsValid() then return end
    local keys = EnsureFlyKeys()
    if not keys then return end
    local rot = nil
    pcall(function() rot = pc.ControlRotation end)
    if not rot then return end
    local fx, fy, fz, rx, ry = ForwardRight(rot)
    local fwd = Axis(pc, keys, "W", "S")
    local strafe = Axis(pc, keys, "D", "A")
    local vert = 0
    if Held(pc, keys.Space) then vert = vert + 1 end
    if Held(pc, keys.X) then vert = vert - 1 end
    local step = PlayerBaseSpeed(player) * flyScale * 0.016
    local dx = (fx * fwd + rx * strafe) * step
    local dy = (fy * fwd + ry * strafe) * step
    local dz = (fz * fwd + vert) * step
    if isFreecam then
        local cam = player.FirstPersonCamera
        if cam and cam:IsValid() then
            MoveCamera(cam, dx, dy, dz, rot)
        end
        if savedPawnLoc then
            SetActorPos(player, savedPawnLoc.X, savedPawnLoc.Y, savedPawnLoc.Z)
        end
    else
        MoveActor(player, dx, dy, dz)
        KillNoclipPhysics(player)
    end
end

-- Watcher: VisionBox half-size is 300 / 1300 / 89. The 1300 axis is how far she looks.
local function SetVisionBox(roku, scale)
    if not roku or not roku:IsValid() or not roku.VisionBox or not roku.VisionBox:IsValid() then return end
    pcall(function() roku.VisionBox:SetRelativeScale3D(Vec(1, 1, 1)) end)
    pcall(function()
        roku.VisionBox:SetBoxExtent(Vec(300 * scale, 1300 * scale, 89 * scale), true)
    end)
end

local function RestoreSight(player, roku)
    if player and player:IsValid() and not isFollow then
        WriteDistances(player, followSaved or StockDistances())
    end
    if roku and roku:IsValid() then
        SetVisionBox(roku, 1)
    end
    if roku and roku:IsValid() and roku.HearingSphere and roku.HearingSphere:IsValid() and savedHear and savedHear > 100 then
        pcall(function() roku.HearingSphere:SetSphereRadius(savedHear, true) end)
    end
end
M.RestoreSight = RestoreSight

local function CaptureSight(player, roku)
    if savedDist == nil and player then
        savedDist = StockDistances()
        pcall(function()
            if player.EasyDistanceCheckA > 100 then savedDist.a = player.EasyDistanceCheckA end
        end)
        pcall(function()
            if player.EasyDistanceCheckB > 50 then savedDist.b = player.EasyDistanceCheckB end
        end)
        pcall(function()
            if player.HardDistanceCheckA > 100 then savedDist.c = player.HardDistanceCheckA end
        end)
        pcall(function()
            if player.HardDistanceCheckB > 50 then savedDist.d = player.HardDistanceCheckB end
        end)
    end
    if roku and roku.VisionBox and roku.VisionBox:IsValid() then
        if savedVision == nil then
            pcall(function()
                local ext = roku.VisionBox:GetUnscaledBoxExtent()
                local x, y, z = ReadVec(ext)
                if x and x > 1 then savedVision = { x = x, y = y, z = z } end
            end)
        end
        if savedBoxScale == nil then
            pcall(function()
                local s = roku.VisionBox.RelativeScale3D
                local x, y, z = ReadVec(s)
                if x and x > 0.01 then savedBoxScale = { x = x, y = y, z = z } end
            end)
        end
    end
    if savedHear == nil and roku and roku.HearingSphere and roku.HearingSphere:IsValid() then
        pcall(function()
            local r = roku.HearingSphere:GetUnscaledSphereRadius()
            if type(r) == "number" and r > 1 then savedHear = r end
        end)
    end
end



local function ApplyCrouchSpeed(player, on)
    if not player or not player:IsValid() then return end
    if savedSpeeds == nil then
        savedSpeeds = { walk = 240, sprint = 460, max = 240 }
        pcall(function()
            local w = player["Walk Speed"]
            if type(w) == "number" and w > 1 then savedSpeeds.walk = w end
        end)
        pcall(function()
            local s = player["Sprint Speed"]
            if type(s) == "number" and s > 1 then savedSpeeds.sprint = s end
        end)
        pcall(function()
            local sprinting = player["Wants to Sprint"] == true
            local cm = player.CharacterMovement
            if not sprinting and cm and cm:IsValid() and type(cm.MaxWalkSpeed) == "number" and cm.MaxWalkSpeed > 1 then
                savedSpeeds.max = cm.MaxWalkSpeed
            end
        end)
    end
    if speedBase == nil then
        speedBase = SnapCubes(savedSpeeds.sprint, STOCK_SPRINT, CUBE_SPEED)
        if not speedBase and sprintScale ~= 1 then
            speedBase = SnapCubes(savedSpeeds.sprint / sprintScale, STOCK_SPRINT, CUBE_SPEED)
        end
        speedBase = speedBase or STOCK_SPRINT
    end
    local scale = on and 0.7 or 1
    WriteNumber(player, "Walk Speed", savedSpeeds.walk * scale, 0.5)
    local sprintTarget
    if on then
        local live = nil
        pcall(function() live = player["Sprint Speed"] end)
        local expected = speedBase * 0.7
        if type(live) == "number" and math.abs(live - expected) > 0.6 then
            local delta = live - expected
            local cubes = math.floor((delta / CUBE_SPEED) + 0.5)
            local tol = CUBE_SPEED * 0.35
            if cubes ~= 0 and cubes >= -MAX_CUBES and cubes <= MAX_CUBES
                and math.abs(delta - (cubes * CUBE_SPEED)) <= tol then
                speedBase = ClampBase(speedBase + (cubes * CUBE_SPEED), STOCK_SPRINT, CUBE_SPEED)
            else
                local snapped = SnapCubes(live, STOCK_SPRINT, CUBE_SPEED)
                if snapped then speedBase = snapped end
            end
        end
        sprintTarget = speedBase * 0.7
    else
        sprintTarget = speedBase * sprintScale
        if sprintScale == 1 then
            writtenSpeed = nil
        else
            writtenSpeed = sprintTarget
        end
    end
    WriteNumber(player, "Sprint Speed", sprintTarget, 0.5)
    pcall(function()
        local cm = player.CharacterMovement
        if not cm or not cm:IsValid() then return end
        local maxTarget = savedSpeeds.max * scale
        if on then
            maxTarget = savedSpeeds.max * 0.7
        else
            local sprinting = false
            pcall(function() sprinting = player["Wants to Sprint"] == true end)
            if sprinting then maxTarget = sprintTarget end
        end
        local cur = cm.MaxWalkSpeed
        if type(cur) ~= "number" or math.abs(cur - maxTarget) > 0.5 then
            cm.MaxWalkSpeed = maxTarget
        end
    end)
    if penaltyOff or not on then
        ApplyEmptyPenalty(player)
    end
end

function M.SetCrouch(on)
    on = not not on
    if on and (isNoclip or isFreecam) then
        print("[RokuMenu] Crouch blocked while noclip or freecam is on\n")
        notify()
        return
    end
    isCrouch = on
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        local roku = GetRoku()
        if not player then
            print("[RokuMenu] Crouch: player not found\n")
            return
        end
        pcall(function() player.IsCrouching = isCrouch end)
        pcall(function() player["IsCrouching?"] = isCrouch end)
        local cam = player.FirstPersonCamera
        if cam and cam:IsValid() then
            local rel = cam.RelativeLocation
            local x, y, z = ReadVec(rel)
            if x then
                local zOff = isCrouch and -40 or 40
                if savedCamRel == nil or not isFreecam then
                    pcall(function()
                        cam:K2_SetRelativeLocation(Vec(x, y, z + zOff), false, {}, false)
                    end)
                end
            end
        end
        pcall(function()
            local cap = player.CapsuleComponent
            if cap and cap:IsValid() then
                if savedHalfHeight == nil then
                    savedHalfHeight = cap:GetUnscaledCapsuleHalfHeight()
                end
                local h = savedHalfHeight
                if isCrouch then h = savedHalfHeight * 0.55 end
                cap:SetCapsuleHalfHeight(h, true)
            end
        end)
        if isCrouch then
            SetVisionBox(roku, 0.10)
        else
            RestoreSight(player, roku)
        end
        ApplyCrouchSpeed(player, isCrouch)
        print(string.format("[RokuMenu] Crouch %s. Vision box %s. Speed %s.\n", isCrouch and "ON" or "OFF", isCrouch and "10%" or "normal", isCrouch and "70%" or "normal"))
        notify()
    end)
end

function M.MaintainCrouch()
    if not isCrouch then return end
    local player = GetPlayerPawn()
    local roku = GetRoku()
    if not player then return end
    SetVisionBox(roku, 0.10)
    ApplyCrouchSpeed(player, true)
end

function M.CollectNotes()
    RunOnGameThread(function()
        local player = GetPlayerPawn()
        if not player then
            print("[RokuMenu] Notes: player not found\n")
            return
        end
        local total = 5
        pcall(function()
            if type(player.TotalNotes) == "number" and player.TotalNotes > 0 then
                total = player.TotalNotes
            end
        end)
        pcall(function() player.NoteScore = total end)
        print(string.format("[RokuMenu] Notes set to %d\n", total))
    end)
end

function M.ToggleNoclip() M.SetNoclip(not isNoclip) end
function M.ToggleFreecam() M.SetFreecam(not isFreecam) end

-- Item montage. Her brain, path, and sight stay paused so a chase or look-around does not replace the clip.
local function ItemBrain(roku)
    if not roku or not roku:IsValid() then return nil end
    local ctrl = roku.Controller
    if not ctrl or not ctrl:IsValid() then return nil end
    local brain = nil
    pcall(function() brain = ctrl.BrainComponent end)
    if brain and brain:IsValid() then return brain end
    return nil
end

local function PauseItemBrain(roku)
    if itemHoldPausedBrain then return end
    local brain = ItemBrain(roku)
    if not brain then return end
    local ok = pcall(function() brain:PauseLogic("RokuMenuItem") end)
    if ok then itemHoldPausedBrain = true end
end

local function ResumeItemBrain(roku)
    if not itemHoldPausedBrain then return end
    itemHoldPausedBrain = false
    local brain = ItemBrain(roku)
    if not brain then return end
    pcall(function() brain:ResumeLogic("RokuMenuItem") end)
end

local function QuietItemSight(roku)
    local chasing = false
    pcall(function() chasing = roku.bIsChasing == true end)
    pcall(function()
        roku.bPlayerInVisionBox = false
        roku.bIsChasing = false
        roku.bIsInvestigating = false
    end)
    if chasing then
        local ctrl = roku.Controller
        if ctrl and ctrl:IsValid() then
            pcall(function() ctrl:CancelChase() end)
        end
    end
end

local function StopItemPath(roku)
    local ctrl = roku.Controller
    if ctrl and ctrl:IsValid() then
        pcall(function() ctrl:StopMovement() end)
    end
    pcall(function()
        local cm = roku.CharacterMovement
        if cm and cm:IsValid() then
            cm:StopMovementImmediately()
        end
    end)
end

local function ReadHoldBool(obj, name)
    local v = nil
    local ok = pcall(function() v = obj[name] end)
    if ok and type(v) == "boolean" then return v end
    return nil
end

local function CaptureItemRotation(roku)
    if itemHoldRot or not roku or not roku:IsValid() then return end
    local saved = {}
    saved.yaw = ReadHoldBool(roku, "bUseControllerRotationYaw")
    saved.pitch = ReadHoldBool(roku, "bUseControllerRotationPitch")
    saved.roll = ReadHoldBool(roku, "bUseControllerRotationRoll")
    local cm = nil
    pcall(function() cm = roku.CharacterMovement end)
    if cm and cm:IsValid() then
        saved.orient = ReadHoldBool(cm, "bOrientRotationToMovement")
        saved.desired = ReadHoldBool(cm, "bUseControllerDesiredRotation")
        saved.physics = ReadHoldBool(cm, "bAllowPhysicsRotationDuringAnimRootMotion")
        pcall(function() saved.rate = CopyRot(cm.RotationRate) end)
    end
    itemHoldRot = saved
end

local function ApplyItemRotationLock(roku)
    pcall(function()
        roku.bUseControllerRotationYaw = false
        roku.bUseControllerRotationPitch = false
        roku.bUseControllerRotationRoll = false
    end)
    pcall(function()
        local cm = roku.CharacterMovement
        if cm and cm:IsValid() then
            cm.bOrientRotationToMovement = false
            cm.bUseControllerDesiredRotation = false
            cm.bAllowPhysicsRotationDuringAnimRootMotion = false
            if itemHoldRot and itemHoldRot.rate then
                cm.RotationRate = { Pitch = 0, Yaw = 0, Roll = 0 }
            end
        end
    end)
    local ctrl = roku.Controller
    if ctrl and ctrl:IsValid() then
        pcall(function() ctrl:K2_ClearFocus() end)
    end
    pcall(function()
        local tl = roku.playerturnanim
        if tl and tl:IsValid() and tl:IsPlaying() then tl:Stop() end
    end)
end

local function RestoreItemRotation(roku)
    local saved = itemHoldRot
    itemHoldRot = nil
    if not saved or not roku or not roku:IsValid() then return end
    pcall(function()
        if type(saved.yaw) == "boolean" then roku.bUseControllerRotationYaw = saved.yaw end
        if type(saved.pitch) == "boolean" then roku.bUseControllerRotationPitch = saved.pitch end
        if type(saved.roll) == "boolean" then roku.bUseControllerRotationRoll = saved.roll end
    end)
    pcall(function()
        local cm = roku.CharacterMovement
        if not cm or not cm:IsValid() then return end
        if type(saved.orient) == "boolean" then cm.bOrientRotationToMovement = saved.orient end
        if type(saved.desired) == "boolean" then cm.bUseControllerDesiredRotation = saved.desired end
        if type(saved.physics) == "boolean" then cm.bAllowPhysicsRotationDuringAnimRootMotion = saved.physics end
        if saved.rate then cm.RotationRate = saved.rate end
    end)
end

function M.HoldRokuForItem(roku, seconds, montage)
    itemHoldUntil = os.clock() + seconds
    itemHoldStart = os.clock()
    itemHoldMontage = montage
    itemHoldReplayAt = 0
    if itemHoldBump == nil then
        itemHoldBump = true
        pcall(function()
            if roku.bCanBump == false then itemHoldBump = false end
        end)
    end
    pcall(function() roku.bCanBump = false end)
    QuietItemSight(roku)
    if not itemHoldVisionMuted and not isGhostMode and not isFollow and not isRokuFrozen then
        SetVolume(roku.VisionBox, false)
        itemHoldVisionMuted = true
    end
    PauseItemBrain(roku)
    StopItemPath(roku)
    CaptureItemRotation(roku)
    ApplyItemRotationLock(roku)
    print(string.format("[RokuMenu] Item hold %.1fs. Movement and sight paused.\n", seconds))
end

local function IsIdleMontage(name)
    local n = string.lower(name or "")
    return string.find(n, "lookaround", 1, true)
        or string.find(n, "generic_bump", 1, true)
        or string.find(n, "investigate", 1, true)
end

local function IsInterruptMontage(name)
    if IsIdleMontage(name) then return true end
    local n = string.lower(name or "")
    return string.find(n, "notice", 1, true)
        or string.find(n, "aggro", 1, true)
        or string.find(n, "attack", 1, true)
end

function M.MaintainItemHold()
    if itemHoldUntil == 0 then return end
    local roku = GetRoku()
    if os.clock() < itemHoldUntil then
        if not roku or not roku:IsValid() then return end
        pcall(function() roku.bCanBump = false end)
        QuietItemSight(roku)
        StopItemPath(roku)
        ApplyItemRotationLock(roku)
        local mesh = GetMesh(roku)
        local anim = nil
        if mesh then pcall(function() anim = mesh:GetAnimInstance() end) end
        if not anim or not anim:IsValid() then return end
        local current = nil
        pcall(function() current = anim:GetCurrentActiveMontage() end)
        if not current or not current:IsValid() then return end
        local name = ""
        pcall(function() name = current:GetFullName() end)
        if not IsInterruptMontage(name) then return end
        pcall(function() anim:Montage_Stop(0.0, current) end)
        local now = os.clock()
        if itemHoldMontage and itemHoldMontage:IsValid() and now - itemHoldReplayAt >= 0.45 then
            itemHoldReplayAt = now
            local elapsed = now - itemHoldStart
            if elapsed < 0 then elapsed = 0 end
            pcall(function()
                anim:Montage_Play(itemHoldMontage, 1.0, 0, elapsed, true)
            end)
        end
        return
    end
    local restoreBump = itemHoldBump
    local muted = itemHoldVisionMuted
    itemHoldBump = nil
    itemHoldVisionMuted = false
    itemHoldUntil = 0
    itemHoldMontage = nil
    itemHoldSpeed = nil
    itemHoldReplayAt = 0
    if roku and roku:IsValid() then
        if isGhostMode or isFollow or isRokuFrozen then
            pcall(function() roku.bCanBump = false end)
        elseif restoreBump ~= nil then
            pcall(function() roku.bCanBump = restoreBump end)
        end
        if muted and not isGhostMode and not isFollow and not isRokuFrozen then
            SetVolume(roku.VisionBox, true)
        end
        RestoreItemRotation(roku)
    end
    if itemHoldRot then itemHoldRot = nil end
    ResumeItemBrain(roku)
    print("[RokuMenu] Item hold released\n")
end

function M.ToggleCrouch() M.SetCrouch(not isCrouch) end
function M.ToggleCowbell() M.SetCowbell(not isCowbell) end
function M.ToggleFollow() M.SetFollow(not isFollow) end

-- Cheats clear when the level Roku unloads. Saved mouse and volume settings stay.
-- Keep cheats between loads stores the toggles first. The next level Roku gets them back.
-- One-shot buttons (apples, notes, drunk, items) are not stored.
-- The snapshot is written to config.json and kept after the game quits.
local function CaptureCheats()
    return {
        god = isGodMode,
        stamina = isInfStamina,
        ghost = isGhostMode and not ghostHeldByFreecam,
        frozen = isRokuFrozen,
        slow = isRokuSlow,
        uiHidden = isUiHidden,
        noclip = isNoclip,
        freecam = isFreecam,
        crouch = isCrouch,
        spank = isSpankHold,
        cowbell = isCowbell,
        follow = isFollow,
        skin = currentSkinIdx,
    }
end

local function RememberCheats()
    if not persistCheats then
        cheatSnapshot = nil
        return
    end
    cheatSnapshot = CaptureCheats()
    StoreSnapshot()
    print("[RokuMenu] Cheats saved for the next load.\n")
end

function M.SaveCheatsIfStillInLevel()
    if not persistCheats or not hadLevelRoku then
        return
    end
    RememberCheats()
end

local function RestoreSavedCheats()
    local snap = cheatSnapshot
    if not snap or not persistCheats then return end
    local player = GetPlayerPawn()
    local roku = GetRoku()
    if not player or not player:IsValid() or not roku or not roku:IsValid() then
        return
    end
    if string.find(SafeGetObjectName(roku), "MainMenu", 1, true) then
        return
    end
    cheatSnapshot = nil
    if snap.skin and snap.skin ~= 1 then
        M.SetOutfit(snap.skin)
    end
    if snap.god then M.SetGod(true) end
    if snap.stamina then M.SetStamina(true) end
    if snap.follow and not snap.ghost then
        M.SetFollow(true)
    end
    if snap.ghost then
        M.SetGhost(true)
    end
    if snap.frozen then
        M.SetFrozen(true)
    elseif snap.slow then
        M.SetSlow(true)
    end
    if snap.spank then M.SetSpankable(true) end
    if snap.cowbell then M.SetCowbell(true) end
    if snap.uiHidden then M.SetUIHidden(true) end
    if snap.crouch and not snap.noclip and not snap.freecam then
        M.SetCrouch(true)
    end
    if snap.noclip then
        M.SetNoclip(true)
    elseif snap.freecam then
        M.SetFreecam(true)
    end
    print("[RokuMenu] Cheats restored.\n")
end

local function ResetCheats()
    local player = GetPlayerPawn()
    local roku = GetRoku()
    if isCrouch and player then
        isCrouch = false
        ApplyCrouchSpeed(player, false)
    end
    if isFollow and player then
        isFollow = false
        WriteDistances(player, followSaved or StockDistances())
    end
    if isFreecam and player then
        StopFreecam(player)
    end
    if isUiHidden then
        isUiHidden = false
        M.SetUIHidden(false)
    end
    isGodMode = false
    isInfStamina = false
    isGhostMode = false
    ghostHeldByFreecam = false
    isRokuFrozen = false
    isRokuSlow = false
    isSpankHold = false
    isCowbell = false
    isFollow = false
    isCrouch = false
    isFreecam = false
    isNoclip = false
    currentSkinIdx = 1
    itemHoldUntil = 0
    itemHoldBump = nil
    itemHoldVisionMuted = false
    itemHoldPausedBrain = false
    itemHoldMontage = nil
    itemHoldReplayAt = 0
    itemHoldRot = nil
    if roku and roku:IsValid() then
        pcall(function() roku.bSpankable = false end)
        if not cowbellRemoved then
            pcall(function() roku.bIsCowbellOn = false end)
            pcall(function() roku:cb_off() end)
        end
        pcall(function() roku.CustomTimeDilation = 1.0 end)
    end
    ForgetMoveScale()
    print("[RokuMenu] Level Roku unloaded. Cheats reset.\n")
    notify()
end

local function UnloadRoku()
    RememberCheats()
    ResetCheats()
end

-- 200ms keeps cheats applied. 16ms runs only while flying or an item clip is playing.
-- Stock difficulty rows return before any actor lookup. Hooks retry until the class is loaded.
function M.StartLoops()
    InstallAttackHook()
    InstallDamageHook()
    if not attackHookInstalled or not damageHookInstalled then
        local hookTries = 0
        LoopAsync(500, function()
            if not attackHookInstalled then InstallAttackHook() end
            if not damageHookInstalled then InstallDamageHook() end
            if attackHookInstalled and damageHookInstalled then
                return true
            end
            hookTries = hookTries + 1
            if hookTries >= 24 then
                if not damageHookInstalled then
                    print("[RokuMenu] Damage hook stopped waiting\n")
                end
                if not attackHookInstalled then
                    print("[RokuMenu] Attack hook stopped waiting\n")
                end
                return true
            end
            return false
        end)
    end
    local function EnforceToggles()
        if isGodMode then
            local player = GetPlayerPawn()
            if player and player:IsValid() then
                pcall(function()
                    if player.Health ~= 1.0 then player.Health = 1.0 end
                end)
                pcall(function()
                    if player.bCanBeDamaged ~= false then player.bCanBeDamaged = false end
                end)
                pcall(function()
                    if player.IsDead ~= false then player.IsDead = false end
                end)
            end
        end
        if isGhostMode or isRokuFrozen then
            local roku = GetRoku()
            if roku and roku:IsValid() then
                QuietBlind(roku)
                StopAttackAnims(roku)
                SetVolume(roku.VisionBox, false)
                SetVolume(roku.HearingSphere, false)
                for i = 1, #slapVolumes do
                    SetVolume(roku[slapVolumes[i]], false)
                end
            end
        end
        if isCrouch then
            M.MaintainCrouch()
        end
        if isFollow then
            M.ReapplyFollow()
        end
        MaintainItemPrompts()
    end
    M._enforceToggles = EnforceToggles
    M._flyTick = M.FlyTick
    LoopAsync(200, function()
        EnforceToggles()
        EnforceDifficulty()
        return false
    end)
    local function FlyLoop()
        local holding = itemHoldUntil ~= 0
        if not isNoclip and not isFreecam and not holding then
            return false
        end
        if holding then
            M.MaintainItemHold()
        end
        if isNoclip or isFreecam then
            local ok, err = pcall(M.FlyTick)
            if not ok then
                isNoclip = false
                isFreecam = false
                print("[RokuMenu] Fly stopped: " .. tostring(err) .. "\n")
            end
        end
        return false
    end
    M._flyLoop = FlyLoop
    LoopAsync(16, FlyLoop)

    LoopAsync(5000, function()
        M.RefreshSpankable()
        return false
    end)

    LoopAsync(1000, function()
        M.PollGraphics()
        rokuCache = nil
        local roku = GetRoku()
        if roku and roku:IsValid() then
            local currentName = SafeGetObjectName(roku)
            local isMenu = string.find(currentName, "MainMenu", 1, true) ~= nil
            if isMenu then
                if hadLevelRoku then
                    hadLevelRoku = false
                    UnloadRoku()
                end
                if currentName ~= lastLiveRokuNm then
                    lastLiveRokuNm = currentName
                    print(string.format("\n[RokuMenu] Menu Roku: %s\n", currentName))
                    RunOnGameThread(function()
                        M.ApplyUserSettings()
                        print("[RokuMenu] Applied saved settings (main menu)\n")
                    end)
                end
            else
                hadLevelRoku = true
                if currentName ~= lastLiveRokuNm then
                    lastLiveRokuNm = currentName
                    print(string.format("\n[RokuMenu] Locked onto live Roku: %s\n", currentName))
                    M.OnLevelRoku()
                    if gfxForce then
                        local waited = 0
                        LoopAsync(500, function()
                            waited = waited + 500
                            if waited < 2000 then return false end
                            if gfxForce then M.ApplySavedGraphics() end
                            return true
                        end)
                    end
                    RunOnGameThread(function()
                        if skins[currentSkinIdx] then
                            skins[currentSkinIdx].apply(roku)
                        end
                        if isGhostMode or isRokuFrozen then
                            ApplyGhostState(roku, true)
                        end
                        M.ReapplyCowbell(roku)
                        M.ReapplyFollow()
                        if isSpankHold then
                            ApplySpankable(true)
                        end
                        if isRokuFrozen then
                            pcall(function() roku.CustomTimeDilation = 0.0 end)
                        elseif isRokuSlow then
                            pcall(function() roku.CustomTimeDilation = 0.05 end)
                        end
                    end)
                    notify()
                end
                RestoreSavedCheats()
            end
        else
            if hadLevelRoku then
                hadLevelRoku = false
                UnloadRoku()
            end
            lastLiveRokuNm = ""
        end
        return false
    end)
end

return M
