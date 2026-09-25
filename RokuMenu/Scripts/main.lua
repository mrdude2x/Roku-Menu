-- RokuMenu: in-game overlay. All game writes go through core.lua.
-- Do not enable GONTrainer at the same time (two Lua states = double hotkeys).

local Core = require("core")

local okMenu, ModMenu = pcall(require, "ModMenu.ModMenu")
if not okMenu or not ModMenu then
    print("[RokuMenu] ERROR: ModMenu not found. Copy shared/ModMenu into ue4ss/Mods/shared/\n")
    print("[RokuMenu] Hotkeys still work (NumPad, NumLock ON).\n")
else
    ModMenu.Init({
        title = "RokuMenu",
        instanceId = "RokuMenu",
        key = Key.HOME,
        keyHint = "Home",
        dock = "left",
        ignoreLook = true,
        cursorMode = "modmenu",
        tabs = { "Cheats", "Camera", "Outfits", "Settings", "Bindings" },
        widthFrac = 0.28,
    })

    local Config = ModMenu.ConfigManager
    Config.Init({
        id = "RokuMenu",
        defaults = {
            lockSettings = true,
            hasSaved = false,
            mouse = 1.0,
            master = 1.0,
            music = 1.0,
            sfx = 1.0,
            binds = "",
            dock = "left",
        },
    })
    Core.LoadUserSettings({
        lock = Config.Get("lockSettings"),
        hasSaved = Config.Get("hasSaved"),
        mouse = Config.Get("mouse"),
        master = Config.Get("master"),
        music = Config.Get("music"),
        sfx = Config.Get("sfx"),
    })

    local function PersistSettings()
        local prev = Core.GetUserSettings()
        local function keep(id, fallback)
            local n = tonumber(ModMenu.Get("GameSettings", id))
            if n == nil then return fallback end
            return n
        end
        local saved = {
            hasSaved = true,
            mouse = keep("mouse", prev.mouse),
            master = keep("master", prev.master),
            music = keep("music", prev.music),
            sfx = keep("sfx", prev.sfx),
        }
        Config.Set("mouse", saved.mouse)
        Config.Set("master", saved.master)
        Config.Set("music", saved.music)
        Config.Set("sfx", saved.sfx)
        Config.Set("hasSaved", true)
        Core.LoadUserSettings(saved)
        Core.ApplyUserSettings()
        print("[RokuMenu] Settings saved and applied\n")
    end

    local function syncUi(state)
        if not ModMenu.IsOpen or not ModMenu.IsOpen() then return end
        pcall(function() ModMenu.Set("Player", "god", state.god) end)
        pcall(function() ModMenu.Set("Player", "stamina", state.stamina) end)
        pcall(function() ModMenu.Set("Player", "crouch", state.crouch) end)
        pcall(function() ModMenu.Set("Camera", "uiHidden", state.uiHidden) end)
        pcall(function() ModMenu.Set("Camera", "freecam", state.freecam) end)
        pcall(function() ModMenu.Set("Camera", "noclip", state.noclip) end)
        pcall(function() ModMenu.SetLabel("Camera", "flySpeed", "Fly speed: " .. tostring(state.fly) .. "%") end)
        pcall(function() ModMenu.Set("Roku", "ghost", state.ghost) end)
        pcall(function() ModMenu.Set("Roku", "frozen", state.frozen) end)
        pcall(function() ModMenu.Set("Roku", "slow", state.slow) end)
        pcall(function() ModMenu.Set("Looks", "skin", state.skin) end)
        local lock = "Roku: not in this map"
        if state.roku and state.roku ~= "" and state.roku ~= "None" then
            lock = "Locked"
        end
        pcall(function() ModMenu.SetLabel("Looks", "status", lock) end)
    end

    Core.OnChange(syncUi)

    ModMenu.OnOpen(function()
        syncUi(Core.GetState())
    end)

    ModMenu.OnClose(PersistSettings)

    local savedDock = Config.Get("dock")
    if savedDock == "left" or savedDock == "right" or savedDock == "top" or savedDock == "bottom" then
        ModMenu.SetDock(savedDock)
    end
    ModMenu.OnDockChange(function(side)
        Config.Set("dock", side)
    end)

    ModMenu.Register({
        id = "Player",
        title = "Player",
        tab = "Cheats",
        items = {
            {
                type = "checkbox",
                id = "god",
                label = "God Mode",
                default = false,
                onChange = function(on) Core.SetGod(on) end,
            },
            {
                type = "checkbox",
                id = "stamina",
                label = "Infinite Stamina",
                default = false,
                onChange = function(on) Core.SetStamina(on) end,
            },
            {
                type = "checkbox",
                id = "crouch",
                label = "Crouch (10% vision box, 70% speed)",
                default = false,
                onChange = function(on) Core.SetCrouch(on) end,
            },
            {
                type = "button",
                id = "apples",
                label = "Apples 65/66",
                onClick = function() Core.FastApples() end,
            },
            {
                type = "button",
                id = "notes",
                label = "Notes complete",
                onClick = function() Core.CollectNotes() end,
            },
        },
    })

    ModMenu.Register({
        id = "Roku",
        title = "Roku",
        tab = "Cheats",
        items = {
            {
                type = "checkbox",
                id = "ghost",
                label = "Ghost (blind / deaf)",
                default = false,
                onChange = function(on) Core.SetGhost(on) end,
            },
            {
                type = "checkbox",
                id = "frozen",
                label = "Freeze",
                default = false,
                onChange = function(on) Core.SetFrozen(on) end,
            },
            {
                type = "checkbox",
                id = "slow",
                label = "Slo-Mo 5%",
                default = false,
                onChange = function(on) Core.SetSlow(on) end,
            },
            {
                type = "button",
                id = "drunk",
                label = "Max Drunk",
                onClick = function() Core.MaxDrunk() end,
            },
            {
                type = "button",
                id = "spank",
                label = "Force Spankable",
                onClick = function() Core.ForceSpank() end,
            },
        },
    })

    ModMenu.Register({
        id = "Camera",
        title = "Camera",
        tab = "Camera",
        items = {
            {
                type = "checkbox",
                id = "uiHidden",
                label = "Hide HUD",
                default = false,
                onChange = function(on) Core.SetUIHidden(on) end,
            },
            {
                type = "checkbox",
                id = "freecam",
                label = "Freecam",
                default = false,
                onChange = function(on) Core.SetFreecam(on) end,
            },
            -- Noclip checkbox disabled until the geometry crash is solved.
            -- {
            --     type = "checkbox",
            --     id = "noclip",
            --     label = "Noclip",
            --     default = false,
            --     onChange = function(on) Core.SetNoclip(on) end,
            -- },
            { type = "label", id = "flySpeed", label = "Fly speed: 100%" },
            { type = "label", id = "flyHint", label = "WASD move, Space up, X down. [ ] change speed." },
        },
    })

    ModMenu.Register({
        id = "Looks",
        title = "Outfits",
        tab = "Outfits",
        items = {
            { type = "label", id = "status", label = "Load a level for Roku" },
            {
                type = "dropdown",
                id = "skin",
                label = "Skin",
                searchable = true,
                options = Core.GetSkinNames(),
                default = 1,
                onChange = function(value) Core.SetOutfit(value) end,
            },
            {
                type = "row",
                items = {
                    {
                        type = "button",
                        id = "cycle",
                        label = "Next",
                        onClick = function() Core.CycleOutfit() end,
                    },
                    {
                        type = "button",
                        id = "base",
                        label = "Base",
                        onClick = function() Core.ResetOutfit() end,
                    },
                },
            },
        },
    })

    ModMenu.Register({
        id = "GameSettings",
        title = "Game settings",
        tab = "Settings",
        items = {
            {
                type = "label",
                id = "hint",
                label = "Type a number. Blank is ignored. Close the menu to save and apply.",
            },
            {
                type = "number",
                id = "mouse",
                label = "Mouse",
                default = tonumber(Config.Get("mouse")) or 1,
                min = 0.05,
                max = 5,
                integer = false,
            },
            { type = "separator" },
            { type = "label", id = "volumes", label = "Volumes" },
            {
                type = "number",
                id = "music",
                label = "Music",
                default = tonumber(Config.Get("music")) or 1,
                min = 0,
                max = 1,
                integer = false,
            },
            {
                type = "number",
                id = "sfx",
                label = "Effects",
                default = tonumber(Config.Get("sfx")) or 1,
                min = 0,
                max = 1,
                integer = false,
            },
        },
    })

    local actions = {
        { id = "god", label = "God Mode", default = "NUM_ONE", fn = function() Core.ToggleGod() end },
        { id = "stamina", label = "Infinite Stamina", default = "NUM_TWO", fn = function() Core.ToggleStamina() end },
        { id = "ghost", label = "Ghost", default = "NUM_THREE", fn = function() Core.ToggleGhost() end },
        { id = "apples", label = "Apples 65/66", default = "NUM_FOUR", fn = function() Core.FastApples() end },
        { id = "cycle", label = "Next Outfit", default = "NUM_FIVE", fn = function() Core.CycleOutfit() end },
        { id = "base", label = "Base Outfit", default = "NUM_SIX", fn = function() Core.ResetOutfit() end },
        { id = "drunk", label = "Max Drunk", default = "NUM_SEVEN", fn = function() Core.MaxDrunk() end },
        { id = "spank", label = "Force Spankable", default = "NUM_EIGHT", fn = function() Core.ForceSpank() end },
        { id = "hud", label = "Hide HUD", default = "NUM_NINE", fn = function() Core.ToggleUI() end },
        { id = "freeze", label = "Freeze", default = "NUM_ZERO", fn = function() Core.ToggleFrozen() end },
        { id = "slow", label = "Slo-Mo", default = "DECIMAL", fn = function() Core.ToggleSlow() end },
        { id = "crouch", label = "Crouch", default = "C", fn = function() Core.ToggleCrouch() end },
        { id = "freecam", label = "Freecam", default = "END", fn = function() Core.ToggleFreecam() end },
        -- { id = "noclip", label = "Noclip", default = "OEM_FIVE", fn = function() Core.ToggleNoclip() end },
        { id = "flyDown", label = "Fly Slower", default = "OEM_FOUR", fn = function() Core.BumpFlySpeed(-1) end },
        { id = "flyUp", label = "Fly Faster", default = "OEM_SIX", fn = function() Core.BumpFlySpeed(1) end },
    }

    local function prettyKey(id)
        local symbols = {
            DECIMAL = "Num .",
            DIVIDE = "Num /",
            MULTIPLY = "Num *",
            ADD = "Num +",
            SUBTRACT = "Num -",
            ZERO = "0", ONE = "1", TWO = "2", THREE = "3", FOUR = "4",
            FIVE = "5", SIX = "6", SEVEN = "7", EIGHT = "8", NINE = "9",
            OEM_MINUS = "-",
            OEM_PLUS = "=",
            OEM_COMMA = ",",
            OEM_PERIOD = ".",
            OEM_ONE = ";",
            OEM_TWO = "/",
            OEM_THREE = "`",
            OEM_FOUR = "[",
            OEM_FIVE = "\\",
            OEM_SIX = "]",
            OEM_SEVEN = "'",
        }
        if symbols[id] then return symbols[id] end
        if id == "END" then return "End" end
        if id:find("CONTROL", 1, true) then return "Ctrl" end
        local num = id:match("^NUM_(.+)$")
        if num == "ZERO" then return "Num 0" end
        if num == "ONE" then return "Num 1" end
        if num == "TWO" then return "Num 2" end
        if num == "THREE" then return "Num 3" end
        if num == "FOUR" then return "Num 4" end
        if num == "FIVE" then return "Num 5" end
        if num == "SIX" then return "Num 6" end
        if num == "SEVEN" then return "Num 7" end
        if num == "EIGHT" then return "Num 8" end
        if num == "NINE" then return "Num 9" end
        if num then return "Num " .. num end
        return id:gsub("_", " ")
    end

    local actionById = {}
    local keyToAction = {}
    for i = 1, #actions do
        actionById[actions[i].id] = actions[i]
        keyToAction[actions[i].default] = actions[i].id
    end

    local function packBinds()
        local parts = {}
        for i = 1, #actions do
            local id = actions[i].id
            local keyId = nil
            for k, act in pairs(keyToAction) do
                if act == id then keyId = k break end
            end
            parts[#parts + 1] = id .. "=" .. (keyId or "")
        end
        return table.concat(parts, ",")
    end

    local function applyPacked(text)
        if type(text) ~= "string" or text == "" then return end
        local mentioned = {}
        for pair in string.gmatch(text, "[^,]+") do
            local id, keyId = pair:match("^([%w_]+)=([%w_]*)$")
            if id and actionById[id] then
                mentioned[id] = keyId or ""
            end
        end
        for k, act in pairs(keyToAction) do
            if mentioned[act] ~= nil then
                keyToAction[k] = nil
            end
        end
        for id, keyId in pairs(mentioned) do
            if keyId == "LEFT_CONTROL" or keyId == "LCONTROL" or keyId == "CONTROL" then
                keyId = "C"
            end
            if keyId ~= "" then
                keyToAction[keyId] = id
            end
        end
    end

    applyPacked(Config.Get("binds"))

    local function keyFor(actionId)
        for k, act in pairs(keyToAction) do
            if act == actionId then return k end
        end
        return nil
    end

    local function refreshBindLabels()
        for i = 1, #actions do
            local a = actions[i]
            local keyId = keyFor(a.id)
            local shown = keyId and prettyKey(keyId) or "None"
            pcall(function() ModMenu.SetLabel("Binds", a.id .. "_key", a.label .. ": " .. shown) end)
            pcall(function() ModMenu.SetButtonLabel("Binds", a.id .. "_set", "Assign") end)
        end
    end

    local pending = nil

    local function beginAssign(actionId)
        pending = actionId
        local a = actionById[actionId]
        pcall(function() ModMenu.SetButtonLabel("Binds", actionId .. "_set", "Press a key") end)
        pcall(function()
            ModMenu.SetLabel("Binds", "bind_status", "Press a key for " .. a.label .. ". Esc cancels.")
        end)
    end

    local bindRows = {
        { type = "label", id = "bind_status", label = "Assign, then press a key. Home still closes the menu." },
    }
    for i = 1, #actions do
        local a = actions[i]
        local keyId = keyFor(a.id)
        local shown = keyId and prettyKey(keyId) or "None"
        bindRows[#bindRows + 1] = {
            type = "row",
            items = {
                { type = "label", id = a.id .. "_key", label = a.label .. ": " .. shown },
                {
                    type = "button",
                    id = a.id .. "_set",
                    label = "Assign",
                    onClick = function() beginAssign(a.id) end,
                },
            },
        }
    end

    ModMenu.Register({
        id = "Binds",
        title = "Bindings",
        tab = "Bindings",
        items = bindRows,
    })

    local function menuOpen()
        if type(ModMenu) ~= "table" or type(ModMenu.IsOpen) ~= "function" then
            return false
        end
        local ok, open = pcall(ModMenu.IsOpen)
        return ok and open == true
    end

    local function onKey(keyId)
        if pending then
            if keyId == "ESCAPE" then
                pending = nil
                refreshBindLabels()
                pcall(function() ModMenu.SetLabel("Binds", "bind_status", "Cancelled.") end)
                return
            end
            local actionId = pending
            for k, act in pairs(keyToAction) do
                if act == actionId or k == keyId then
                    keyToAction[k] = nil
                end
            end
            keyToAction[keyId] = actionId
            pending = nil
            Config.Set("binds", packBinds())
            refreshBindLabels()
            pcall(function()
                ModMenu.SetLabel("Binds", "bind_status", actionById[actionId].label .. " set to " .. prettyKey(keyId))
            end)
            return
        end
        if menuOpen() then return end
        local actionId = keyToAction[keyId]
        local action = actionId and actionById[actionId]
        if action then action.fn() end
    end

    local listen = {
        "ESCAPE",
        "NUM_ZERO", "NUM_ONE", "NUM_TWO", "NUM_THREE", "NUM_FOUR",
        "NUM_FIVE", "NUM_SIX", "NUM_SEVEN", "NUM_EIGHT", "NUM_NINE",
        "DECIMAL", "DIVIDE", "MULTIPLY", "ADD", "SUBTRACT",
        "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE",
        "OEM_MINUS", "OEM_PLUS", "OEM_COMMA", "OEM_PERIOD",
        "OEM_ONE", "OEM_TWO", "OEM_THREE", "OEM_FOUR", "OEM_FIVE", "OEM_SIX", "OEM_SEVEN",
        "END", "LEFT_CONTROL", "LCONTROL", "CONTROL",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F11", "F12",
        "INSERT", "DELETE", "PAGE_UP", "PAGE_DOWN", "END",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    }
    local seen = {}
    for i = 1, #listen do
        local keyId = listen[i]
        local code = Key[keyId]
        if keyId == "DECIMAL" and not code then
            code = Key.NUM_DECIMAL or Key.NUM_PERIOD
        end
        if keyId == "LEFT_CONTROL" and not code then
            code = Key.LCONTROL or Key.CONTROL or 0xA2
        end
        if code and not seen[code] then
            seen[code] = true
            RegisterKeyBind(code, function() onKey(keyId) end)
        end
    end

    print("[RokuMenu] Overlay ready. Press Home to open.\n")
end

Core.StartLoops()

print("[RokuMenu] Loaded. Home = menu. NumPad keys are ignored while the menu is open.")
print("[RokuMenu] Disable GONTrainer while this is enabled.\n")
