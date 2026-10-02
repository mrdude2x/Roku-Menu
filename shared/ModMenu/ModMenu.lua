--[[
  ModMenu.bundle.lua — generated release bundle. Do not edit.

  Build: npm run bundle
  Install as: Mods/shared/ModMenu/ModMenu.lua
  Hosts: require("ModMenu.ModMenu")
]]
-- core/store.lua
package.preload["ModMenu.core.store"] = function(...)
--[[
  ModMenu.core.store — tiny JSON key/value store (optional; host-owned).

  Public name is ModMenu.ConfigManager (facade + ConfigManager.lua shim):

    local ModMenu = require("ModMenu.ModMenu")
    local ConfigManager = ModMenu.ConfigManager
    -- or: require("ModMenu.ConfigManager") / require("ModMenu.core.store")

    ConfigManager.Init({
        id = "MyMod",
        defaults = { volume = 1 },
    })
    ConfigManager.Get("volume")
    ConfigManager.Set("volume", 0.5)  -- writes Mods/MyMod/config.json

  JSON-safe values only (bool, number, string, table, nil). Hosts still own
  when to Set and how to apply. Unknown file keys are kept.
  This module must not require ModMenu.ModMenu (no cycle).
]]

local M = {}

local LIB_NAME = "ConfigManager"

local initialized = false
local modId = nil
local filePath = nil
local autosave = true
local defaults = {}
local store = {}
local loadFailed = false

local function Log(msg)
    print(string.format("[%s] %s\n", LIB_NAME, tostring(msg)))
end

---@param s string
---@return string
local function EscapePattern(s)
    return (s:gsub("(%W)", "%%%1"))
end

---@param path string
---@return string
local function NormalizePath(path)
    return (tostring(path):gsub("\\", "/"))
end

---@param path string
---@return boolean
local function FileExists(path)
    local f = io.open(path, "r")
    if not f then
        return false
    end
    f:close()
    return true
end

---@param dir string
---@return boolean
local function LooksLikeModDir(dir)
    return FileExists(dir .. "/Scripts/main.lua")
        or FileExists(dir .. "/enabled.txt")
        or FileExists(dir .. "/config.json")
end

---@param value any
---@param seen table|nil
---@return any
local function Copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        error(LIB_NAME .. ": circular table")
    end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do
        out[Copy(k, seen)] = Copy(v, seen)
    end
    seen[value] = nil
    return out
end

---@param a any
---@param b any
---@return boolean
local function Equal(a, b)
    if a == b then
        return true
    end
    if type(a) ~= type(b) or type(a) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if not Equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

---@param value any
---@return boolean
local function IsJsonSafe(value)
    local t = type(value)
    if value == nil or t == "boolean" or t == "string" then
        return true
    end
    if t == "number" then
        return value == value and value ~= math.huge and value ~= -math.huge
    end
    if t ~= "table" then
        return false
    end
    for k, v in pairs(value) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            return false
        end
        if not IsJsonSafe(v) then
            return false
        end
    end
    return true
end

---@param n number
---@return string
local function EncodeNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then
        error(LIB_NAME .. ": cannot encode nan/inf")
    end
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return string.format("%.0f", n)
    end
    return tostring(n)
end

---@param s string
---@return string
local function EncodeString(s)
    s = s:gsub(".", function(ch)
        local b = string.byte(ch)
        if ch == "\\" then
            return "\\\\"
        end
        if ch == "\"" then
            return "\\\""
        end
        if b == 8 then
            return "\\b"
        end
        if b == 12 then
            return "\\f"
        end
        if b == 10 then
            return "\\n"
        end
        if b == 13 then
            return "\\r"
        end
        if b == 9 then
            return "\\t"
        end
        if b < 32 then
            return string.format("\\u%04x", b)
        end
        return ch
    end)
    return "\"" .. s .. "\""
end

---@param t table
---@return boolean
local function IsArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
            return false
        end
        if k > n then
            n = k
        end
    end
    if n == 0 then
        return false
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true
end

---@param value any
---@param level integer
---@return string
local function Encode(value, level)
    if value == nil then
        return "null"
    end
    local t = type(value)
    if t == "boolean" then
        return value and "true" or "false"
    end
    if t == "number" then
        return EncodeNumber(value)
    end
    if t == "string" then
        return EncodeString(value)
    end
    if t ~= "table" then
        error(LIB_NAME .. ": cannot encode " .. t)
    end

    level = level or 0
    local inner = level + 1
    local pad = string.rep("  ", inner)
    local close = string.rep("  ", level)

    if IsArray(value) then
        if #value == 0 then
            return "[]"
        end
        local parts = {}
        for i = 1, #value do
            parts[#parts + 1] = pad .. Encode(value[i], inner)
        end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. close .. "]"
    end

    local keys = {}
    for k in pairs(value) do
        if type(k) ~= "string" then
            error(LIB_NAME .. ": object keys must be strings")
        end
        keys[#keys + 1] = k
    end
    if #keys == 0 then
        return "{}"
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = pad .. EncodeString(k) .. ": " .. Encode(value[k], inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. close .. "}"
end

---@param s string
---@param i integer
---@return integer
local function SkipWs(s, i)
    local from = s:find("[^ \t\n\r]", i)
    return from or (#s + 1)
end

local ParseValue

---@param s string
---@param i integer
---@return string, integer
local function ParseString(s, i)
    i = i + 1
    local out = {}
    while i <= #s do
        local ch = s:sub(i, i)
        if ch == "\"" then
            return table.concat(out), i + 1
        end
        if ch ~= "\\" then
            out[#out + 1] = ch
            i = i + 1
        else
            local n = s:sub(i + 1, i + 1)
            local map = {
                ["\""] = "\"",
                ["\\"] = "\\",
                ["/"] = "/",
                b = "\b",
                f = "\f",
                n = "\n",
                r = "\r",
                t = "\t",
            }
            if map[n] then
                out[#out + 1] = map[n]
                i = i + 2
            elseif n == "u" then
                local hex = s:sub(i + 2, i + 5)
                if not hex:match("^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
                    error("bad \\u escape")
                end
                local cp = tonumber(hex, 16)
                if cp < 128 then
                    out[#out + 1] = string.char(cp)
                elseif cp < 2048 then
                    out[#out + 1] = string.char(192 + math.floor(cp / 64), 128 + (cp % 64))
                else
                    out[#out + 1] = string.char(
                        224 + math.floor(cp / 4096),
                        128 + (math.floor(cp / 64) % 64),
                        128 + (cp % 64)
                    )
                end
                i = i + 6
            else
                error("bad escape")
            end
        end
    end
    error("unterminated string")
end

---@param s string
---@param i integer
---@return number, integer
local function ParseNumber(s, i)
    local slice = s:sub(i)
    local num = slice:match("^-?%d+%.%d+[eE][%+%-]?%d+")
        or slice:match("^-?%d+[eE][%+%-]?%d+")
        or slice:match("^-?%d+%.%d+")
        or slice:match("^-?%d+")
    if not num then
        error("bad number")
    end
    return tonumber(num), i + #num
end

---@param s string
---@param i integer
---@return table, integer
local function ParseArray(s, i)
    i = SkipWs(s, i + 1)
    local arr = {}
    if s:sub(i, i) == "]" then
        return arr, i + 1
    end
    while true do
        local v
        v, i = ParseValue(s, i)
        arr[#arr + 1] = v
        i = SkipWs(s, i)
        local ch = s:sub(i, i)
        if ch == "]" then
            return arr, i + 1
        end
        if ch ~= "," then
            error("expected comma in array")
        end
        i = SkipWs(s, i + 1)
    end
end

---@param s string
---@param i integer
---@return table, integer
local function ParseObject(s, i)
    i = SkipWs(s, i + 1)
    local obj = {}
    if s:sub(i, i) == "}" then
        return obj, i + 1
    end
    while true do
        if s:sub(i, i) ~= "\"" then
            error("expected string key")
        end
        local key
        key, i = ParseString(s, i)
        i = SkipWs(s, i)
        if s:sub(i, i) ~= ":" then
            error("expected colon")
        end
        local v
        v, i = ParseValue(s, SkipWs(s, i + 1))
        obj[key] = v
        i = SkipWs(s, i)
        local ch = s:sub(i, i)
        if ch == "}" then
            return obj, i + 1
        end
        if ch ~= "," then
            error("expected comma in object")
        end
        i = SkipWs(s, i + 1)
    end
end

function ParseValue(s, i)
    i = SkipWs(s, i)
    local ch = s:sub(i, i)
    if ch == "\"" then
        return ParseString(s, i)
    end
    if ch == "{" then
        return ParseObject(s, i)
    end
    if ch == "[" then
        return ParseArray(s, i)
    end
    if ch == "t" and s:sub(i, i + 3) == "true" then
        return true, i + 4
    end
    if ch == "f" and s:sub(i, i + 4) == "false" then
        return false, i + 5
    end
    if ch == "n" and s:sub(i, i + 3) == "null" then
        return nil, i + 4
    end
    if ch == "-" or ch:match("%d") then
        return ParseNumber(s, i)
    end
    error("unexpected " .. tostring(ch))
end

---@param text string
---@return table
local function DecodeObject(text)
    local value, i = ParseValue(text, 1)
    i = SkipWs(text, i)
    if i <= #text then
        error("trailing junk")
    end
    if type(value) ~= "table" or IsArray(value) then
        error("root must be an object")
    end
    return value
end

---@param id string
---@return string|nil
local function CallerModRoot(id)
    local needle = EscapePattern(id)
    for level = 3, 12 do
        local info = debug.getinfo(level, "S")
        if info and type(info.source) == "string" then
            local src = info.source
            if src:sub(1, 1) == "@" then
                src = src:sub(2)
            end
            src = NormalizePath(src)
            local root = src:match("^(.*[\\/]Mods[\\/]" .. needle .. ")[\\/]")
            if root then
                return root
            end
        end
    end
    return nil
end

---@param id string
---@param explicit string|nil
---@return string
local function ResolveFile(id, explicit)
    if type(explicit) == "string" and explicit ~= "" then
        return NormalizePath(explicit)
    end

    local root = CallerModRoot(id)
    if root then
        return root .. "/config.json"
    end

    local candidates = {
        "ue4ss/Mods/" .. id .. "/config.json",
        "Mods/" .. id .. "/config.json",
    }
    for i = 1, #candidates do
        local path = candidates[i]
        local dir = path:match("^(.*)/[^/]+$")
        if dir and LooksLikeModDir(dir) then
            return path
        end
    end
    return candidates[1]
end

---@param path string
---@return table|nil, string|nil
local function ReadFile(path)
    local f, err = io.open(path, "r")
    if not f then
        return nil, err
    end
    local text = f:read("*a")
    f:close()
    if type(text) ~= "string" or text:match("^%s*$") then
        return {}
    end
    local ok, decoded = pcall(DecodeObject, text)
    if not ok then
        return nil, tostring(decoded)
    end
    return decoded
end

---@param path string
---@param text string
---@return boolean, string|nil
local function WriteFile(path, text)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then
        f, err = io.open(path, "w")
        if not f then
            return false, err
        end
        f:write(text)
        if text:sub(-1) ~= "\n" then
            f:write("\n")
        end
        f:close()
        return true
    end
    f:write(text)
    if text:sub(-1) ~= "\n" then
        f:write("\n")
    end
    f:close()
    os.remove(path)
    local renamed, renameErr = os.rename(tmp, path)
    if renamed then
        return true
    end
    os.remove(tmp)
    local f2, err2 = io.open(path, "w")
    if not f2 then
        return false, renameErr or err2
    end
    f2:write(text)
    if text:sub(-1) ~= "\n" then
        f2:write("\n")
    end
    f2:close()
    return true
end

local function EnsureInit()
    if not initialized then
        error(LIB_NAME .. ": call Init first")
    end
end

local function MergeLoaded(loaded)
    store = Copy(defaults)
    if type(loaded) ~= "table" then
        return
    end
    for k, v in pairs(loaded) do
        if type(k) == "string" then
            store[k] = Copy(v)
        end
    end
end

--- Initialize the store and load config.json if present. Safe to call again.
---@param opts { id: string, defaults?: table, file?: string, autosave?: boolean }
---@return table
function M.Init(opts)
    opts = opts or {}
    if type(opts.id) ~= "string" or opts.id == "" then
        error(LIB_NAME .. ".Init: id must be a non-empty string")
    end
    if opts.defaults ~= nil and type(opts.defaults) ~= "table" then
        error(LIB_NAME .. ".Init: defaults must be a table")
    end
    if opts.defaults ~= nil and not IsJsonSafe(opts.defaults) then
        error(LIB_NAME .. ".Init: defaults must be JSON-safe")
    end

    modId = opts.id
    autosave = opts.autosave ~= false
    defaults = Copy(opts.defaults or {})
    filePath = ResolveFile(modId, opts.file)
    loadFailed = false

    if FileExists(filePath) then
        local loaded, err = ReadFile(filePath)
        if loaded == nil then
            loadFailed = true
            MergeLoaded(nil)
            Log(string.format("%s: failed to parse %s — %s (file left untouched)", modId, filePath, tostring(err)))
            initialized = true
            return M
        end
        MergeLoaded(loaded)
        Log(string.format("%s: loaded %s", modId, filePath))
    else
        MergeLoaded(nil)
        Log(string.format("%s: no config yet (%s)", modId, filePath))
    end
    initialized = true
    return M
end

---@return string|nil
function M.File()
    return filePath
end

--- Current value, or the Init default if unset. Tables are copies.
---@param key string
---@return any
function M.Get(key)
    EnsureInit()
    if type(key) ~= "string" or key == "" then
        error(LIB_NAME .. ".Get: key must be a non-empty string")
    end
    local value = store[key]
    if value == nil then
        value = defaults[key]
    end
    return Copy(value)
end

--- Write a key. nil removes it (Get then returns the default). Autosaves.
---@param key string
---@param value any
function M.Set(key, value)
    EnsureInit()
    if type(key) ~= "string" or key == "" then
        error(LIB_NAME .. ".Set: key must be a non-empty string")
    end
    if value ~= nil and not IsJsonSafe(value) then
        error(LIB_NAME .. ".Set: value must be JSON-safe")
    end

    local current = store[key]
    if current == nil then
        current = defaults[key]
    end
    if Equal(current, value) then
        return
    end

    if value == nil then
        store[key] = nil
    else
        store[key] = Copy(value)
    end
    loadFailed = false
    if autosave then
        M.Save()
    end
end

--- Write the store to disk now. No-op if Init never loaded a path.
function M.Save()
    EnsureInit()
    if loadFailed then
        Log(string.format("%s: skip save, %s did not parse", modId, filePath))
        return false
    end
    local out = {}
    for k, v in pairs(store) do
        out[k] = v
    end
    local ok, err = WriteFile(filePath, Encode(out, 0))
    if not ok then
        Log(string.format("%s: save failed %s — %s", modId, filePath, tostring(err)))
        return false
    end
    return true
end

return M
end

-- ConfigManager.lua
package.preload["ModMenu.ConfigManager"] = function(...)
--[[
  Public require path for the JSON store. Implementation is core/store.lua.
]]

return require("ModMenu.core.store")
end

-- core/util.lua
package.preload["ModMenu.core.util"] = function(...)
--[[
  ModMenu.core.util — shared helpers (logging, validity, strings, value keys).
]]

local M = {}

local LIB_NAME = "ModMenu"

-- UE4SS LoopInGameThreadWithDelay / ExecuteInGameThreadWithDelay store a
-- registry ref. If Lua GC collects the closure, EngineTick throws
-- "Ref was not function" and removes the whole Lua tick hook.
local pinnedFns = {}

function M.PinFn(fn)
    if type(fn) == "function" then
        pinnedFns[fn] = true
    end
    return fn
end

local debugOn = false

function M.SetDebug(on)
    debugOn = on == true
end

function M.IsDebug()
    return debugOn == true
end

function M.Log(msg)
    print(string.format("[%s] %s\n", LIB_NAME, tostring(msg)))
end

--- Verbose traces (collapse, open/close, section register, click path). Off by default.
function M.Debug(msg)
    if debugOn then
        M.Log(msg)
    end
end

function M.IsValid(obj)
    return obj ~= nil and type(obj.IsValid) == "function" and obj:IsValid()
end

--- ComboBoxString / FText / FString userdata — normalize before compare/store.
function M.ToPlainString(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        return value
    end
    if type(value) == "userdata" or type(value) == "table" then
        if value.ToString then
            local ok, s = pcall(function()
                return value:ToString()
            end)
            if ok and type(s) == "string" then
                return s
            end
        end
    end
    local s = tostring(value)
    -- Avoid storing "FString: 0000..." pointer junk as a real value.
    if string.find(s, "FString:", 1, true) == 1 then
        return nil
    end
    return s
end

function M.ValueKey(sectionId, itemId)
    return tostring(sectionId) .. "." .. tostring(itemId)
end

function M.SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        M.Log("callback error: " .. tostring(err))
    end
end

--- Default debounce for textinput / number onChange (ms). 0 = immediate.
M.DEFAULT_INPUT_DEBOUNCE_MS = 250

function M.ValidateDebounceMs(item, prefix)
    if item.debounceMs ~= nil and (type(item.debounceMs) ~= "number" or item.debounceMs < 0) then
        error(prefix .. " debounceMs must be a number >= 0")
    end
end

function M.ResolveDebounceMs(item, defaultMs)
    if item.debounceMs == nil then
        return defaultMs or M.DEFAULT_INPUT_DEBOUNCE_MS
    end
    return item.debounceMs
end

--- Queue a debounced onChange. Values store should already be updated (Get stays live).
function M.ScheduleDebouncedOnChange(ctrl, debounceMs)
    if debounceMs == nil or debounceMs <= 0 then
        ctrl.onChangeDue = 0
    else
        ctrl.onChangeDue = os.clock() + (debounceMs / 1000)
    end
end

--- Fire pending onChange when due. No-op if nothing scheduled or value unchanged since last fire.
function M.FlushDebouncedOnChange(ctrl, ctx)
    if ctrl.onChangeDue == nil then
        return
    end
    if os.clock() < ctrl.onChangeDue then
        return
    end
    ctrl.onChangeDue = nil
    local v = ctx.values[ctrl.valueKey]
    if v == ctrl.lastFiredOnChange then
        return
    end
    ctrl.lastFiredOnChange = v
    M.SafeCall(ctrl.item.onChange, v)
end

--- Clear pending debounce (e.g. after Set/apply). Optionally sync lastFiredOnChange.
function M.ClearDebouncedOnChange(ctrl, syncValue)
    ctrl.onChangeDue = nil
    if syncValue ~= nil then
        ctrl.lastFiredOnChange = syncValue
    end
end

return M
end

-- core/theme.lua
package.preload["ModMenu.core.theme"] = function(...)
--[[
  ModMenu.core.theme — author-facing color presets.

  Init({ theme = "light" | "dark", colors = { panelBg = { R,G,B,A }, ... } }).
  light = current ModMenu look (dark panel, light fields).
  dark  = charcoal panel, dark fields, teal/gold accents.
  Not a player setting — hosts pick a preset (and optional overrides) at Init.
]]

local M = {}

local KEYS = {
    "panelBg",
    "panelBorder",
    "textPrimary",
    "textMuted",
    "textAccent",
    "textStatus",
    "buttonBg",
    "buttonText",
    "buttonBgPrimary",
    "buttonTextPrimary",
    "buttonBgSecondary",
    "buttonTextSecondary",
    "buttonBgSuccess",
    "buttonTextSuccess",
    "buttonBgDanger",
    "buttonTextDanger",
    "buttonBgWarning",
    "buttonTextWarning",
    "buttonBgInfo",
    "buttonTextInfo",
    "buttonBgActive",
    "buttonTextActive",
    "buttonBgDisabled",
    "buttonTextDisabled",
    "sectionHeaderBg",
    "sectionMark",
    "fieldBg",
    "fieldText",
    "fieldHint",
    "dropdownHeaderBg",
    "dropdownHeaderText",
    "dropdownOptionBg",
    "dropdownOptionText",
    "dropdownMore",
    "overlayDim",
    "confirmCardBg",
    "confirmDivider",
}

local function C(r, g, b, a)
    return { R = r, G = g, B = b, A = a or 1.0 }
end

local function CopyColor(c)
    if type(c) ~= "table" then
        return nil
    end
    return {
        R = tonumber(c.R) or 0,
        G = tonumber(c.G) or 0,
        B = tonumber(c.B) or 0,
        A = tonumber(c.A) or 1,
    }
end

local function CopyColors(src)
    local out = {}
    for _, key in ipairs(KEYS) do
        out[key] = CopyColor(src[key])
    end
    return out
end

-- Current shipped look: navy panel, mid-blue buttons, light editable fields.
local LIGHT = {
    panelBg = C(0.05, 0.07, 0.12, 0.92),
    panelBorder = C(0.05, 0.07, 0.12, 0.92),
    textPrimary = C(0.95, 0.95, 0.98),
    textMuted = C(0.72, 0.76, 0.82),
    textAccent = C(0.45, 0.72, 0.88),
    textStatus = C(0.83, 0.69, 0.22),
    buttonBg = C(0.18, 0.22, 0.32),
    buttonText = C(0.95, 0.95, 0.98),
    -- Bootstrap-like action colors (flat UMG; no outline/link variants).
    buttonBgPrimary = C(0.05, 0.43, 0.99),
    buttonTextPrimary = C(1.0, 1.0, 1.0),
    buttonBgSecondary = C(0.42, 0.46, 0.49),
    buttonTextSecondary = C(1.0, 1.0, 1.0),
    buttonBgSuccess = C(0.10, 0.53, 0.33),
    buttonTextSuccess = C(1.0, 1.0, 1.0),
    buttonBgDanger = C(0.86, 0.21, 0.27),
    buttonTextDanger = C(1.0, 1.0, 1.0),
    buttonBgWarning = C(1.0, 0.76, 0.03),
    buttonTextWarning = C(0.08, 0.09, 0.10),
    buttonBgInfo = C(0.05, 0.79, 0.94),
    buttonTextInfo = C(0.08, 0.09, 0.10),
    buttonBgActive = C(0.12, 0.40, 0.28),
    buttonTextActive = C(0.82, 0.98, 0.88),
    buttonBgDisabled = C(0.12, 0.14, 0.18),
    buttonTextDisabled = C(0.45, 0.48, 0.52),
    sectionHeaderBg = C(0.10, 0.13, 0.20),
    sectionMark = C(0.72, 0.76, 0.82),
    fieldBg = C(0.88, 0.90, 0.94),
    fieldText = C(0.06, 0.07, 0.10),
    fieldHint = C(0.35, 0.38, 0.45),
    dropdownHeaderBg = C(0.22, 0.28, 0.40),
    dropdownHeaderText = C(0.98, 0.98, 1.0),
    dropdownOptionBg = C(0.88, 0.90, 0.94),
    dropdownOptionText = C(0.06, 0.07, 0.10),
    dropdownMore = C(0.70, 0.75, 0.85),
    overlayDim = C(0.02, 0.03, 0.05, 0.62),
    confirmCardBg = C(0.08, 0.10, 0.16, 0.98),
    confirmDivider = C(0.22, 0.26, 0.34, 1.0),
}

-- Dark preset: charcoal panel, dark fields. Flat UMG (no bevel/glow).
local DARK = {
    panelBg = C(0.11, 0.11, 0.12, 0.90),
    panelBorder = C(0.62, 0.62, 0.64, 0.90),
    textPrimary = C(0.92, 0.92, 0.93),
    textMuted = C(0.62, 0.62, 0.64),
    textAccent = C(0.12, 0.72, 0.70),
    textStatus = C(0.83, 0.69, 0.22),
    buttonBg = C(0.20, 0.20, 0.21),
    buttonText = C(0.92, 0.92, 0.93),
    buttonBgPrimary = C(0.08, 0.34, 0.78),
    buttonTextPrimary = C(1.0, 1.0, 1.0),
    buttonBgSecondary = C(0.32, 0.32, 0.34),
    buttonTextSecondary = C(0.92, 0.92, 0.93),
    buttonBgSuccess = C(0.08, 0.42, 0.28),
    buttonTextSuccess = C(0.92, 0.98, 0.94),
    buttonBgDanger = C(0.72, 0.18, 0.22),
    buttonTextDanger = C(1.0, 1.0, 1.0),
    buttonBgWarning = C(0.90, 0.68, 0.10),
    buttonTextWarning = C(0.10, 0.09, 0.06),
    buttonBgInfo = C(0.08, 0.52, 0.58),
    buttonTextInfo = C(0.90, 0.98, 0.98),
    buttonBgActive = C(0.10, 0.36, 0.28),
    buttonTextActive = C(0.72, 0.95, 0.84),
    buttonBgDisabled = C(0.14, 0.14, 0.15),
    buttonTextDisabled = C(0.40, 0.40, 0.42),
    sectionHeaderBg = C(0.16, 0.16, 0.17),
    sectionMark = C(0.62, 0.62, 0.64),
    fieldBg = C(0.06, 0.06, 0.07),
    fieldText = C(0.94, 0.94, 0.94),
    fieldHint = C(0.50, 0.50, 0.52),
    dropdownHeaderBg = C(0.20, 0.20, 0.21),
    dropdownHeaderText = C(0.92, 0.92, 0.93),
    dropdownOptionBg = C(0.08, 0.08, 0.09),
    dropdownOptionText = C(0.92, 0.92, 0.93),
    dropdownMore = C(0.62, 0.62, 0.64),
    overlayDim = C(0.04, 0.04, 0.05, 0.62),
    confirmCardBg = C(0.16, 0.16, 0.17, 0.98),
    confirmDivider = C(0.30, 0.30, 0.32, 1.0),
}

local PAD = {
    light = { Left = 20, Top = 18, Right = 20, Bottom = 18 },
    dark = { Left = 16, Top = 14, Right = 16, Bottom = 14 },
}

local PRESETS = {
    light = LIGHT,
    dark = DARK,
}

function M.Normalize(name)
    if name == nil or name == "light" then
        return "light"
    end
    if name == "dark" then
        return "dark"
    end
    error('ModMenu.Init: theme must be "light" or "dark"')
end

function M.Preset(name)
    local key = name
    if key ~= "dark" then
        key = "light"
    end
    return CopyColors(PRESETS[key])
end

function M.Merge(base, overrides)
    local out = CopyColors(base)
    if type(overrides) ~= "table" then
        return out
    end
    for _, key in ipairs(KEYS) do
        if overrides[key] ~= nil then
            local copied = CopyColor(overrides[key])
            if copied then
                out[key] = copied
            end
        end
    end
    return out
end

function M.Resolve(name, overrides)
    return M.Merge(PRESETS[M.Normalize(name)], overrides)
end

function M.Of(config)
    if config ~= nil and type(config.colors) == "table" then
        return config.colors
    end
    return M.Preset("light")
end

function M.PadPanel(config)
    local name = "light"
    if config ~= nil and config.theme == "dark" then
        name = "dark"
    end
    local pad = PAD[name]
    return {
        Left = pad.Left,
        Top = pad.Top,
        Right = pad.Right,
        Bottom = pad.Bottom,
    }
end

return M
end

-- core/umg.lua
package.preload["ModMenu.core.umg"] = function(...)
--[[
  ModMenu.core.umg — StaticConstructObject helpers and common UMG controls.
]]

local Util = require("ModMenu.core.util")
local Theme = require("ModMenu.core.theme")

local M = {}

local defaults = {
    fontItem = 16,
    colors = nil, ---@type table|nil resolved in Init
}

function M.SetDefaults(opts)
    opts = opts or {}
    if opts.fontItem ~= nil then
        defaults.fontItem = opts.fontItem
    end
    if opts.colors ~= nil then
        defaults.colors = opts.colors
    end
end

local function Colors()
    return defaults.colors or Theme.Preset("light")
end

local lastScrollDebug = nil

--- Desktop: 8px. Touch: fat always-on track (finger). Drag-on-content is later —
--- MouseDown buttons steal the pointer, so the thumb has to be hittable.
--- Each setter is its own pcall: one failed UFunction must not skip thickness.
---@param scroll any
---@param config table|nil
function M.StyleScrollBox(scroll, config)
    if scroll == nil then
        return
    end
    local touch = config ~= nil and config.pointerMode == "touch"
    local thick = 8
    if touch then
        thick = 28
    end
    pcall(function()
        scroll:SetAnimateWheelScrolling(true)
    end)
    pcall(function()
        scroll:SetAlwaysShowScrollbar(touch == true)
    end)
    pcall(function()
        scroll:SetAllowOverscroll(touch == true)
    end)
    pcall(function()
        scroll:SetConsumeMouseWheel(1)
    end)
    pcall(function()
        if touch then
            scroll:SetAlwaysShowScrollbarTrack(true)
        end
    end)

    local vec = { X = thick, Y = thick }
    local applied = false
    if pcall(function()
        scroll:SetScrollbarThickness(vec)
    end) then
        applied = true
    elseif pcall(function()
        scroll.ScrollbarThickness = vec
    end) then
        applied = true
    elseif pcall(function()
        scroll.ScrollbarThickness.X = thick
        scroll.ScrollbarThickness.Y = thick
    end) then
        applied = true
    end

    -- FScrollBarStyle brushes often control how wide the thumb looks.
    pcall(function()
        local style = scroll.WidgetBarStyle
        if style == nil then
            return
        end
        local size = { X = thick, Y = thick }
        for _, key in ipairs({
            "VerticalBackgroundImage",
            "HorizontalBackgroundImage",
            "NormalThumbImage",
            "HoveredThumbImage",
            "DraggedThumbImage",
        }) do
            local brush = style[key]
            if brush ~= nil then
                pcall(function()
                    brush.ImageSize = size
                end)
            end
        end
        scroll.WidgetBarStyle = style
    end)

    pcall(function()
        scroll:SynchronizeProperties()
    end)

    local msg = string.format(
        "scroll thick=%d touch=%s thicknessSet=%s",
        thick,
        touch and "1" or "0",
        applied and "1" or "0"
    )
    if msg ~= lastScrollDebug then
        lastScrollDebug = msg
        Util.Debug(msg)
    end
end

local function FindClass(path)
    local cls = StaticFindObject(path)
    if not Util.IsValid(cls) then
        error("StaticFindObject failed: " .. path)
    end
    return cls
end

function M.Construct(classPath, outer, name)
    local cls = FindClass(classPath)
    local obj = StaticConstructObject(cls, outer, FName(name))
    if not Util.IsValid(obj) then
        error("StaticConstructObject failed: " .. classPath .. " as " .. name)
    end
    return obj
end

function M.StyleText(textBlock, size, color)
    color = color or Colors().textPrimary
    pcall(function()
        if textBlock.Font then
            textBlock.Font.Size = size or defaults.fontItem
        end
        textBlock:SetColorAndOpacity({
            SpecifiedColor = color,
            ColorUseRule = 0,
        })
    end)
end

--- Do not gate on IsValid() — child TextBlocks inside Buttons often report invalid.
function M.SetLabelText(textBlock, str)
    if textBlock == nil then
        return false
    end
    local ok = pcall(function()
        textBlock:SetText(FText(tostring(str)))
    end)
    return ok == true
end

--- Soft-wrap TextBlock to its laid-out width (needed for long hint / status labels).
function M.EnableAutoWrap(textBlock)
    if textBlock == nil then
        return
    end
    pcall(function()
        textBlock:SetAutoWrapText(true)
    end)
    pcall(function()
        textBlock.AutoWrapText = true
    end)
end

--- HAlign_Fill so AutoWrapText uses the panel width instead of desired (unwrapped) width.
function M.FillVerticalSlot(slot)
    if slot == nil then
        return
    end
    pcall(function()
        slot:SetHorizontalAlignment(0) -- EHorizontalAlignment::HAlign_Fill
    end)
end

function M.AddSpacer(parent, name, height)
    local spacer = M.Construct("/Script/UMG.Spacer", parent, name)
    pcall(function()
        spacer:SetSize({ X = 1, Y = height or 12 })
    end)
    parent:AddChildToVerticalBox(spacer)
    return spacer
end

--- Attach a widget to ctx.contentBox (VerticalBox or HorizontalBox via ctx.layout).
--- opts: fill (HBox fill), fillWeight, padLeft/Right/Top/Bottom, vAlign, fillVertical (VBox)
function M.AddToContent(ctx, widget, opts)
    opts = opts or {}
    local parent = ctx.contentBox
    local slot
    if ctx.layout == "horizontal" then
        slot = parent:AddChildToHorizontalBox(widget)
        pcall(function()
            if opts.fill then
                slot:SetSize({ SizeRule = 1, Value = opts.fillWeight or 1.0 })
            else
                slot:SetSize({ SizeRule = 0, Value = 0.0 })
            end
            slot:SetPadding({
                Left = opts.padLeft or 0,
                Top = opts.padTop or 0,
                Right = opts.padRight or 6,
                Bottom = opts.padBottom or 0,
            })
            -- EVerticalAlignment::VAlign_Center = 2
            slot:SetVerticalAlignment(opts.vAlign or 2)
        end)
    else
        slot = parent:AddChildToVerticalBox(widget)
        if opts.fillVertical then
            M.FillVerticalSlot(slot)
        end
    end
    return slot
end

--- Trailing pad after an item. No-op in horizontal rows (slot padding handles gaps).
function M.AddItemPad(ctx, name, size)
    if ctx.layout == "horizontal" then
        return nil
    end
    return M.AddSpacer(ctx.contentBox, name, size or 8)
end

--- Style an EditableTextBox from theme field tokens.
--- The engine's default slate box is light-grey; WidgetStyle.BackgroundColor
--- often does not tint it. Hide those brushes and let the wrapping Border
--- (CreateLabeledEditable / dropdown search) be the visible fill.
function M.StyleEditableTextBox(edit, fontSize)
    if edit == nil then
        return
    end
    local colors = Colors()
    local fill = colors.fieldBg
    local dark = colors.fieldText
    local hint = colors.fieldHint
    local slateFill = { SpecifiedColor = fill, ColorUseRule = 0 }
    local slateText = { SpecifiedColor = dark, ColorUseRule = 0 }
    local slateHint = { SpecifiedColor = hint, ColorUseRule = 0 }

    pcall(function()
        edit:SetForegroundColor(dark)
    end)
    pcall(function()
        local style = edit.WidgetStyle
        if style == nil then
            return
        end
        pcall(function()
            style.ForegroundColor = slateText
        end)
        pcall(function()
            style.BackgroundColor = slateFill
        end)
        pcall(function()
            style.FocusedForegroundColor = slateText
        end)
        for _, key in ipairs({
            "BackgroundImageNormal",
            "BackgroundImageHovered",
            "BackgroundImageFocused",
            "BackgroundImageReadOnly",
        }) do
            local brush = style[key]
            if brush ~= nil then
                pcall(function()
                    brush.TintColor = slateFill
                    -- ESlateBrushDrawType::NoDrawType — Border behind the field is the fill.
                    brush.DrawAs = 0
                end)
            end
        end
        if style.TextStyle ~= nil then
            if style.TextStyle.ColorAndOpacity ~= nil then
                style.TextStyle.ColorAndOpacity = slateText
            end
            if style.TextStyle.Font ~= nil and style.TextStyle.Font.Size ~= nil and fontSize then
                style.TextStyle.Font.Size = fontSize
            end
        end
        if style.HintTextStyle ~= nil then
            if style.HintTextStyle.ColorAndOpacity ~= nil then
                style.HintTextStyle.ColorAndOpacity = slateHint
            end
            if style.HintTextStyle.Font ~= nil and style.HintTextStyle.Font.Size ~= nil and fontSize then
                style.HintTextStyle.Font.Size = fontSize
            end
        end
        edit.WidgetStyle = style
    end)
end

--- Labeled single-line field: HorizontalBox(label + SizeBox(Border(EditableTextBox))).
--- Field chrome follows the active theme (light fields on light, dark on dark).
--- @return root, editBox, label
function M.CreateLabeledEditable(outer, namePrefix, caption, initialText, opts)
    opts = opts or {}
    local fontSize = opts.fontSize or defaults.fontItem
    local fieldWidth = opts.fieldWidth or 96
    local hint = opts.hint

    local root = M.Construct("/Script/UMG.HorizontalBox", outer, namePrefix .. "_Row")

    local label = M.Construct("/Script/UMG.TextBlock", root, namePrefix .. "_Label")
    M.StyleText(label, fontSize)
    M.SetLabelText(label, caption or "")

    local labelHost = label
    if type(opts.labelWidth) == "number" and opts.labelWidth > 0 then
        local labelSize = M.Construct("/Script/UMG.SizeBox", root, namePrefix .. "_LabelSize")
        pcall(function()
            labelSize:SetWidthOverride(opts.labelWidth)
            labelSize:SetContent(label)
        end)
        labelHost = labelSize
    end

    local labelSlot = root:AddChildToHorizontalBox(labelHost)
    pcall(function()
        labelSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        labelSlot:SetPadding({ Left = 0, Top = 4, Right = 8, Bottom = 4 })
        labelSlot:SetVerticalAlignment(2)
    end)

    local sizeBox = M.Construct("/Script/UMG.SizeBox", root, namePrefix .. "_Size")
    pcall(function()
        sizeBox:SetWidthOverride(fieldWidth)
    end)

    local border = M.Construct("/Script/UMG.Border", sizeBox, namePrefix .. "_Border")
    pcall(function()
        border:SetBrushColor(Colors().fieldBg)
        border:SetPadding({ Left = 8, Top = 4, Right = 8, Bottom = 4 })
    end)

    local edit = M.Construct("/Script/UMG.EditableTextBox", border, namePrefix .. "_Edit")
    pcall(function()
        edit:SetText(FText(tostring(initialText or "")))
        if hint ~= nil and hint ~= "" then
            edit:SetHintText(FText(tostring(hint)))
        end
    end)
    M.StyleEditableTextBox(edit, fontSize)
    pcall(function()
        border:SetContent(edit)
        sizeBox:SetContent(border)
    end)

    local fieldSlot = root:AddChildToHorizontalBox(sizeBox)
    pcall(function()
        if opts.fillField then
            fieldSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        else
            fieldSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        end
        fieldSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        fieldSlot:SetVerticalAlignment(2)
    end)

    return root, edit, label
end

function M.CreateLabeledToggle(outer, namePrefix, caption, initialChecked, fontSize)
    local check = M.Construct("/Script/UMG.CheckBox", outer, namePrefix .. "_Check")
    local label = M.Construct("/Script/UMG.TextBlock", check, namePrefix .. "_Label")
    M.StyleText(label, fontSize or defaults.fontItem)
    M.SetLabelText(label, caption)
    check:SetContent(label)
    check:SetIsChecked(initialChecked and true or false)
    return check, label
end

function M.CreateTextButton(outer, namePrefix, caption, bgColor, textColor, fontSize)
    local button = M.Construct("/Script/UMG.Button", outer, namePrefix .. "_Btn")
    local label = M.Construct("/Script/UMG.TextBlock", button, namePrefix .. "_BtnLabel")
    M.StyleText(label, fontSize or defaults.fontItem, textColor or Colors().buttonText)
    M.SetLabelText(label, caption)
    pcall(function()
        button:SetContent(label)
        button:SetBackgroundColor(bgColor or Colors().buttonBg)
        -- MouseDown / touch-down so IsPressed is true on pointer-down
        -- (DownAndUp misses short taps).
        if button.SetClickMethod then
            button:SetClickMethod(1)
        end
        if button.SetTouchMethod then
            button:SetTouchMethod(1)
        end
    end)
    return button, label
end

return M
end

-- core/shared.lua
package.preload["ModMenu.core.shared"] = function(...)
--[[
  ModMenu.core.shared — ModRef shared variables (process-wide, survive hot-reload).

  Scalars only. Do not store tables or functions.
]]

local M = {}

M.NEXT_INSTANCE = "ModMenu.NextInstanceId"
M.OPEN_COUNT = "ModMenu.OpenCount"
--- Claim map: ModMenu.KeyClaim.<keyHint> -> instanceTag (string). Warn-only on clash.
M.KEY_CLAIM_PREFIX = "ModMenu.KeyClaim."
--- Stashed PlayerController input flags while any ModMenu is open.
M.INPUT_SAVED = "ModMenu.InputSaved"
M.SAVED_SHOW_CURSOR = "ModMenu.Saved.bShowMouseCursor"
M.SAVED_CLICK = "ModMenu.Saved.bEnableClickEvents"
M.SAVED_HOVER = "ModMenu.Saved.bEnableMouseOverEvents"
M.SAVED_LOOK_BUMP = "ModMenu.Saved.LookIgnoreBump"

function M.Get(name)
    if ModRef == nil then
        return nil
    end
    local ok, value = pcall(function()
        return ModRef:GetSharedVariable(name)
    end)
    if ok then
        return value
    end
    return nil
end

function M.Set(name, value)
    if ModRef == nil then
        return false
    end
    local ok = pcall(function()
        ModRef:SetSharedVariable(name, value)
    end)
    return ok == true
end

function M.AdjustOpenCount(delta)
    local n = M.Get(M.OPEN_COUNT)
    if type(n) ~= "number" then
        n = 0
    end
    n = math.max(0, n + delta)
    M.Set(M.OPEN_COUNT, n)
    return n
end

return M
end

-- core/config.lua
package.preload["ModMenu.core.config"] = function(...)
--[[
  ModMenu.core.config — default Init table, option merge, small normalizers.
]]

local Theme = require("ModMenu.core.theme")

local M = {}

function M.New()
    return {
        title = "Mod Menu",
        key = nil, -- set in Init; default Key.F6
        dock = "right", -- "left" | "right" | "top" | "bottom" (author default; user can change)
        widthFrac = 0.32,
        topFrac = 0.05,
        bottomFrac = 0.05,
        rightFrac = 0.01, -- thickness-edge gap (all four docks)
        theme = "light", -- "light" (current look) | "dark" (charcoal panel)
        colors = Theme.Preset("light"),
        fontScale = 1, -- multiplies the default font sizes (per-game; 1 = stock)
        fontTitle = 22,
        fontHint = 14,
        fontItem = 16,
        fontSection = 18,
        fontDropdown = 15,
        instanceId = nil, -- optional human tag for FNames / Live View (e.g. "TestMod")
        canOpen = nil, -- optional fun(): boolean|boolean,string — gate Open / key toggle open
        ignoreLook = false, -- opt-in: SetIgnoreLookInput while open (mouse-look games)
        inputBackend = "ue4ss", -- "ue4ss" | "engine" (opt-in; no auto-detect)
        keyName = nil, -- Unreal FKey name for engine backend (e.g. "F7"); defaults from keyHint
        consoleCommand = nil, -- optional console command (toggle|open|close)
        cursorMode = "engine", -- "engine" | "modmenu" (opt-in overlay pointer)
        pointerMode = "mouse", -- "mouse" | "touch" (longer latch ignore + checkbox buttons)
        showClose = true, -- title-row Close (same path as the toggle key); pass false to hide
        touchFontScale = 1.75, -- extra multiply on resolved fonts + widthFrac when pointerMode is touch
        cursorScale = 1, -- overlay pointer multiplier (1 = native ~28x46; 2 = larger)
        cursorHideClasses = nil, -- optional string[] of UUserWidget class names to collapse while open
        tabs = nil, -- optional string[] top-level tabs; omit = single scroll
        debug = false, -- verbose [ModMenu] traces (collapse, open/close, register, click path)
    }
end

function M.NormalizeDock(side)
    local d = string.lower(tostring(side or "right"))
    if d == "left" or d == "right" or d == "top" or d == "bottom" then
        return d
    end
    return "right"
end

function M.NormalizeInputBackend(value)
    if value == nil then
        return "ue4ss"
    end
    if value == "ue4ss" or value == "engine" then
        return value
    end
    error('ModMenu.Init: inputBackend must be "ue4ss" or "engine"')
end

function M.NormalizeCursorMode(value)
    if value == nil then
        return "engine"
    end
    if value == "engine" or value == "modmenu" then
        return value
    end
    error('ModMenu.Init: cursorMode must be "engine" or "modmenu"')
end

--- "handheld" is an alias for touch (same Init line as debug).
function M.NormalizePointerMode(value)
    if value == nil then
        return "mouse"
    end
    if value == "mouse" then
        return "mouse"
    end
    if value == "touch" or value == "handheld" then
        return "touch"
    end
    error('ModMenu.Init: pointerMode must be "mouse", "touch", or "handheld"')
end

function M.NormalizeCursorScale(value)
    if value == nil then
        return 1
    end
    if type(value) ~= "number" or value ~= value or value < 1 then
        error("ModMenu.Init: cursorScale must be a number >= 1")
    end
    local n = math.floor(value + 0.5)
    if n < 1 then
        n = 1
    end
    if n > 8 then
        n = 8
    end
    return n
end

--- Host-supplied class short names to collapse while the ModMenu cursor is shown.
---@param value any
---@return string[]|nil
function M.NormalizeCursorHideClasses(value)
    if value == nil or value == false then
        return nil
    end
    if type(value) ~= "table" then
        error("ModMenu.Init: cursorHideClasses must be a string array or nil")
    end
    local out = {}
    for i = 1, #value do
        local name = value[i]
        if type(name) ~= "string" or name == "" then
            error("ModMenu.Init: cursorHideClasses entries must be non-empty strings")
        end
        out[#out + 1] = name
    end
    if #out == 0 then
        return nil
    end
    return out
end

--- Unique non-empty names. false / {} / omit → nil (single-scroll menu).
function M.NormalizeTabs(value)
    if value == nil or value == false then
        return nil
    end
    if type(value) ~= "table" then
        error('ModMenu.Init: tabs must be an array of strings')
    end
    local out = {}
    local seen = {}
    for i, name in ipairs(value) do
        if type(name) ~= "string" or name == "" then
            error("ModMenu.Init: tabs[" .. tostring(i) .. "] must be a non-empty string")
        end
        if seen[name] then
            error("ModMenu.Init: duplicate tab " .. name)
        end
        seen[name] = true
        table.insert(out, name)
    end
    if #out == 0 then
        return nil
    end
    return out
end

local FONT_DEFAULTS = {
    fontTitle = 22,
    fontHint = 14,
    fontItem = 16,
    fontSection = 18,
    fontDropdown = 15,
}

function M.NormalizeFontScale(value)
    if value == nil then
        return 1
    end
    if type(value) ~= "number" or value ~= value or value <= 0 then
        error("ModMenu.Init: fontScale must be a positive number")
    end
    return value
end

--- Extra size on handheld (fonts + panel width).
function M.NormalizeTouchFontScale(value)
    if value == nil then
        return 1.75
    end
    if type(value) ~= "number" or value ~= value or value <= 0 then
        error("ModMenu.Init: touchFontScale must be a positive number")
    end
    local n = value
    if n < 1 then
        n = 1
    end
    if n > 4 then
        n = 4
    end
    return n
end

local function ScaleFont(base, scale)
    local n = math.floor((base * scale) + 0.5)
    if n < 1 then
        n = 1
    end
    return n
end

--- Scale stock sizes, then apply any explicit font* from this Init (absolute).
--- Overrides persist across later Init calls that omit that key.
--- Writes desktop sizes to config._fontDesktop; ApplyTouchFonts copies them to config.font*.
local function ApplyFonts(config, opts)
    if opts.fontScale ~= nil then
        config.fontScale = M.NormalizeFontScale(opts.fontScale)
    end
    local scale = config.fontScale or 1
    local overrides = config._fontOverride
    if type(overrides) ~= "table" then
        overrides = {}
        config._fontOverride = overrides
    end
    local desktop = config._fontDesktop
    if type(desktop) ~= "table" then
        desktop = {}
        config._fontDesktop = desktop
    end
    for key, base in pairs(FONT_DEFAULTS) do
        if opts[key] ~= nil then
            if type(opts[key]) ~= "number" or opts[key] < 1 then
                error("ModMenu.Init: " .. key .. " must be a number >= 1")
            end
            desktop[key] = opts[key]
            overrides[key] = true
        elseif not overrides[key] then
            desktop[key] = ScaleFont(base, scale)
        end
    end
end

--- pointerMode touch: multiply desktop-resolved sizes (defaults × fontScale and
--- explicit fontTitle / …). Always copy from _fontDesktop so later Init does not stack.
local function ApplyTouchFonts(config)
    local desktop = config._fontDesktop
    if type(desktop) ~= "table" then
        return
    end
    local m = 1
    if config.pointerMode == "touch" then
        m = config.touchFontScale or 1.75
    end
    for key, _ in pairs(FONT_DEFAULTS) do
        local n = desktop[key]
        if type(n) == "number" then
            config[key] = ScaleFont(n, m)
        end
    end
end

local TOUCH_WIDTH_CAP = 0.85

--- Same multiplier as fonts. Snapshot desktop width so later Init does not stack.
local function ApplyTouchWidth(config)
    if config._desktopWidthFrac == nil then
        config._desktopWidthFrac = 0.32
    end
    local w = config._desktopWidthFrac
    if config.pointerMode == "touch" then
        local m = config.touchFontScale or 1.75
        w = w * m
        if w > TOUCH_WIDTH_CAP then
            w = TOUCH_WIDTH_CAP
        end
    end
    config.widthFrac = w
end

function M.ResolveEngineKeyName(config)
    if type(config.keyName) == "string" and config.keyName ~= "" then
        return config.keyName
    end
    local hint = tostring(config.keyHint or "")
    if hint:match("^[%w]+$") then
        return hint
    end
    return nil
end

--- Merge Init(opts) into config. ctx.instanceUnlocked: instanceId may still be set.
---@param config table
---@param opts table|nil
---@param ctx { instanceUnlocked?: boolean }|nil
function M.ApplyInit(config, opts, ctx)
    opts = opts or {}
    ctx = ctx or {}

    if opts.title ~= nil then config.title = opts.title end
    if opts.key ~= nil then config.key = opts.key end
    if opts.keyHint ~= nil then config.keyHint = opts.keyHint end
    if opts.widthFrac ~= nil then
        config._desktopWidthFrac = opts.widthFrac
    end
    if opts.topFrac ~= nil then config.topFrac = opts.topFrac end
    if opts.bottomFrac ~= nil then config.bottomFrac = opts.bottomFrac end
    if opts.rightFrac ~= nil then config.rightFrac = opts.rightFrac end
    if opts.dock ~= nil then config.dock = M.NormalizeDock(opts.dock) end
    if opts.theme ~= nil then
        config.theme = Theme.Normalize(opts.theme)
        config.colors = Theme.Resolve(config.theme, opts.colors)
    elseif opts.colors ~= nil then
        if type(opts.colors) ~= "table" then
            error("ModMenu.Init: colors must be a table of { R, G, B, A } tokens")
        end
        config.colors = Theme.Merge(config.colors, opts.colors)
    end
    ApplyFonts(config, opts)
    if opts.canOpen ~= nil then
        if opts.canOpen ~= false and type(opts.canOpen) ~= "function" then
            error("ModMenu.Init: canOpen must be a function or false/nil")
        end
        config.canOpen = (type(opts.canOpen) == "function") and opts.canOpen or nil
    end
    if opts.ignoreLook ~= nil then
        config.ignoreLook = opts.ignoreLook == true
    end
    if opts.inputBackend ~= nil then
        config.inputBackend = M.NormalizeInputBackend(opts.inputBackend)
    end
    if opts.keyName ~= nil then
        if type(opts.keyName) ~= "string" or opts.keyName == "" then
            error("ModMenu.Init: keyName must be a non-empty string")
        end
        config.keyName = opts.keyName
    end
    if opts.tabs ~= nil then
        config.tabs = M.NormalizeTabs(opts.tabs)
    end
    if opts.consoleCommand ~= nil then
        if opts.consoleCommand == false or opts.consoleCommand == "" then
            config.consoleCommand = nil
        elseif type(opts.consoleCommand) ~= "string" then
            error("ModMenu.Init: consoleCommand must be a string or false")
        else
            config.consoleCommand = opts.consoleCommand
        end
    end
    if opts.cursorMode ~= nil then
        config.cursorMode = M.NormalizeCursorMode(opts.cursorMode)
    end
    if opts.pointerMode ~= nil then
        config.pointerMode = M.NormalizePointerMode(opts.pointerMode)
    end
    if opts.showClose ~= nil then
        config.showClose = opts.showClose == true
    end
    if opts.touchFontScale ~= nil then
        config.touchFontScale = M.NormalizeTouchFontScale(opts.touchFontScale)
    end
    if opts.cursorScale ~= nil then
        config.cursorScale = M.NormalizeCursorScale(opts.cursorScale)
    end
    if opts.cursorHideClasses ~= nil then
        config.cursorHideClasses = M.NormalizeCursorHideClasses(opts.cursorHideClasses)
    end
    -- Human-readable FName tag (Live View). Locked after first EnsureInstanceIdentity.
    if opts.instanceId ~= nil and ctx.instanceUnlocked then
        config.instanceId = opts.instanceId
    end
    if opts.debug ~= nil then
        config.debug = opts.debug == true
    end

    if config.key == nil then
        config.key = Key.F6
        config.keyHint = config.keyHint or "F6"
    end
    config.inputBackend = M.NormalizeInputBackend(config.inputBackend)
    config.cursorMode = M.NormalizeCursorMode(config.cursorMode)
    config.pointerMode = M.NormalizePointerMode(config.pointerMode)
    config.touchFontScale = M.NormalizeTouchFontScale(config.touchFontScale)
    config.cursorScale = M.NormalizeCursorScale(config.cursorScale)
    ApplyTouchFonts(config)
    ApplyTouchWidth(config)
end

return M
end

-- core/instance.lua
package.preload["ModMenu.core.instance"] = function(...)
--[[
  ModMenu.core.instance — per-Lua-state identity, FName suffix, key claims, open-count hold.
]]

local Shared = require("ModMenu.core.shared")
local Util = require("ModMenu.core.util")

local M = {}

local VIEWPORT_Z_BASE = 1000

local instanceSerial = nil ---@type integer?
local instanceTag = nil ---@type string?
local viewportZ = VIEWPORT_Z_BASE
local createAttempts = 0
--- True while this instance has incremented SHARED_OPEN_COUNT.
local openCountHeld = false

local function SanitizeTag(raw)
    local s = tostring(raw or "mod"):gsub("[^%w_]", "_")
    if s == "" then
        s = "mod"
    end
    -- FName-friendly length; keep Live View readable.
    if #s > 48 then
        s = string.sub(s, 1, 48)
    end
    return s
end

--- Allocate a process-wide instance id so UObject names never collide across mods.
---@param config table
function M.Ensure(config)
    if instanceSerial ~= nil and instanceTag ~= nil then
        return
    end

    local nextId = Shared.Get(Shared.NEXT_INSTANCE)
    if type(nextId) ~= "number" then
        nextId = 0
    end
    nextId = nextId + 1
    if not Shared.Set(Shared.NEXT_INSTANCE, nextId) then
        -- No ModRef (unexpected): fall back to a local-only id (single-mod safe).
        nextId = (createAttempts > 0 and createAttempts or 1)
        Util.Log("WARNING: ModRef shared vars unavailable — instance id may collide across mods")
    end
    instanceSerial = nextId

    local tag = config.instanceId
    if tag == nil or tostring(tag) == "" then
        tag = "i" .. tostring(instanceSerial)
    end
    instanceTag = SanitizeTag(tag)
    viewportZ = VIEWPORT_Z_BASE + (instanceSerial - 1)

    Util.Debug(string.format(
        "Instance identity serial=%d tag=%q viewportZ=%d",
        instanceSerial,
        instanceTag,
        viewportZ
    ))
end

function M.BumpCreateAttempts()
    createAttempts = createAttempts + 1
    return createAttempts
end

---@param config table
---@return string
function M.ShellNameSuffix(config)
    M.Ensure(config)
    return string.format("%s_%d", instanceTag, createAttempts)
end

function M.GetTag()
    return instanceTag
end

function M.GetSerial()
    return instanceSerial
end

function M.GetViewportZ()
    return viewportZ
end

function M.IsOpenCountHeld()
    return openCountHeld == true
end

function M.NoteOpened()
    if openCountHeld then
        return
    end
    Shared.AdjustOpenCount(1)
    openCountHeld = true
end

function M.NoteClosed()
    if not openCountHeld then
        return Shared.AdjustOpenCount(0)
    end
    openCountHeld = false
    return Shared.AdjustOpenCount(-1)
end

--- Advertise our toggle key via ModRef so two mods on the same key log a clear clash.
--- Does not block binding — authors/players decide whether to change keys.
---@param config table
---@param keyHint any
function M.ClaimToggleKey(config, keyHint)
    M.Ensure(config)
    local hint = tostring(keyHint or "unknown")
    local claimKey = Shared.KEY_CLAIM_PREFIX .. hint
    local owner = Shared.Get(claimKey)
    local me = tostring(instanceTag)

    if type(owner) == "string" and owner ~= "" and owner ~= me then
        -- Single Log() line (Util.Log already prefixes [ModMenu]).
        Util.Log(string.format(
            "KEY CONFLICT: %s already claimed by %q — this menu (%q) shares that bind. "
                .. "Both may toggle together (ok for same-author dual docks); "
                .. "unrelated mods should use different keys.",
            hint,
            owner,
            me
        ))
    elseif type(owner) == "string" and owner == me then
        Util.Debug(string.format("Key %s already claimed by this instance (%q)", hint, me))
    else
        Util.Debug(string.format("Key %s claimed by %q", hint, me))
    end

    -- Last Init wins the registry slot (still useful: next mod sees the latest owner).
    Shared.Set(claimKey, me)
end

return M
end

-- core/inputmode.lua
package.preload["ModMenu.core.inputmode"] = function(...)
--[[
  ModMenu.core.inputmode — PlayerController + Slate while a shell is open.

  Keys stay in core/input.lua. This module owns GameAndUI / GameOnly,
  software cursor flags, opt-in look-ignore, and reclaim after game UI steals focus.
]]

local UEHelpers = require("UEHelpers.UEHelpers")
local Util = require("ModMenu.core.util")
local Shared = require("ModMenu.core.shared")

local M = {}

local IsValid = Util.IsValid

-- UE5 added trailing bFlushInput to SetInputMode_*; UE4.27 rejects the extra arg.
-- Cache after first successful call so we don't pcall-probe every open/close.
local inputModeFlushArity = nil ---@type "withFlush"|"noFlush"|nil

local getMenuRoot = function()
    return nil
end
local getIgnoreLook = function()
    return false
end
local isMenuOpen = function()
    return false
end
local getCursorMode = function()
    return "engine"
end

---@param hooks { getMenuRoot: fun(): any, getIgnoreLook: fun(): boolean, isMenuOpen: fun(): boolean, getCursorMode?: fun(): string }
function M.Bind(hooks)
    getMenuRoot = hooks.getMenuRoot
    getIgnoreLook = hooks.getIgnoreLook
    isMenuOpen = hooks.isMenuOpen
    if type(hooks.getCursorMode) == "function" then
        getCursorMode = hooks.getCursorMode
    end
end

local function OverlayCursor()
    return getCursorMode() == "modmenu"
end

--- GameAndUI with DoNotLock; try UE5 (5 args) then UE4 (4 args).
local function ApplyGameAndUI(lib, pc)
    local menuRoot = getMenuRoot()
    -- EMouseLockMode::DoNotLock = 0
    if inputModeFlushArity == "withFlush" then
        lib:SetInputMode_GameAndUIEx(pc, menuRoot, 0, false, false)
        return
    end
    if inputModeFlushArity == "noFlush" then
        lib:SetInputMode_GameAndUIEx(pc, menuRoot, 0, false)
        return
    end
    local ok = pcall(function()
        lib:SetInputMode_GameAndUIEx(pc, menuRoot, 0, false, false)
    end)
    if ok then
        inputModeFlushArity = "withFlush"
        return
    end
    lib:SetInputMode_GameAndUIEx(pc, menuRoot, 0, false)
    inputModeFlushArity = "noFlush"
end

--- GameOnly; try UE5 (pc + flush) then UE4 (pc only).
local function ApplyGameOnly(lib, pc)
    if inputModeFlushArity == "withFlush" then
        lib:SetInputMode_GameOnly(pc, false)
        return
    end
    if inputModeFlushArity == "noFlush" then
        lib:SetInputMode_GameOnly(pc)
        return
    end
    local ok = pcall(function()
        lib:SetInputMode_GameOnly(pc, false)
    end)
    if ok then
        inputModeFlushArity = "withFlush"
        return
    end
    lib:SetInputMode_GameOnly(pc)
    inputModeFlushArity = "noFlush"
end

--- Force a usable cursor for mouse-look games (no default UI cursor).
--- SetIgnoreLookInput is refcounted in UE. Re-bump if the game clears ignore while open;
--- if IsLookInputIgnored can't be probed, bump at most once (LOOK_BUMP).
local function EnsureLookIgnored(pc)
    local ignored = false
    local probeOk = pcall(function()
        ignored = pc:IsLookInputIgnored() == true
    end)
    if probeOk then
        if ignored then
            return
        end
        -- Look not ignored (first open, or game cleared it) — bump and remember for restore.
    elseif Shared.Get(Shared.SAVED_LOOK_BUMP) == true then
        return
    end
    local ok = pcall(function()
        pc:SetIgnoreLookInput(true)
    end)
    if ok then
        Shared.Set(Shared.SAVED_LOOK_BUMP, true)
    end
end

local function ForceMenuCursor(pc)
    if Shared.Get(Shared.INPUT_SAVED) ~= true then
        Shared.Set(Shared.SAVED_SHOW_CURSOR, pc.bShowMouseCursor == true)
        Shared.Set(Shared.SAVED_CLICK, pc.bEnableClickEvents == true)
        Shared.Set(Shared.SAVED_HOVER, pc.bEnableMouseOverEvents == true)
        Shared.Set(Shared.INPUT_SAVED, true)
    end
    -- Overlay mode: the game is expected to keep the engine cursor hidden.
    -- Forcing bShowMouseCursor just starts a fight that looks like a steal.
    if not OverlayCursor() then
        pc.bShowMouseCursor = true
    end
    pc.bEnableClickEvents = true
    pc.bEnableMouseOverEvents = true
    if getIgnoreLook() then
        EnsureLookIgnored(pc)
    end
end

--- Restore PlayerController cursor/look flags when the last ModMenu closes.
--- If we never took over input, leave the game's cursor/mode alone
--- (ClientRestart / DestroyShell used to force cursor off and GameOnly,
--- which hides hub/inventory cursors on games like Witchfire).
local function RestoreMenuCursor(pc)
    if Shared.Get(Shared.INPUT_SAVED) ~= true then
        return false
    end
    local wasShowingCursor = Shared.Get(Shared.SAVED_SHOW_CURSOR) == true
    pc.bShowMouseCursor = wasShowingCursor
    pc.bEnableClickEvents = Shared.Get(Shared.SAVED_CLICK) == true
    pc.bEnableMouseOverEvents = Shared.Get(Shared.SAVED_HOVER) == true
    if Shared.Get(Shared.SAVED_LOOK_BUMP) == true then
        pcall(function()
            pc:SetIgnoreLookInput(false)
        end)
    end
    Shared.Set(Shared.INPUT_SAVED, false)
    Shared.Set(Shared.SAVED_LOOK_BUMP, false)
    return wasShowingCursor
end

--- Show software cursor + GameAndUI (the mode that worked — white cursor).
--- On deactivate: only return to GameOnly when no other ModMenu instance is open.
---@param active boolean
---@param remainingOpenCount integer|nil when deactivating, open count after this instance released
function M.SetActive(active, remainingOpenCount)
    local pc = UEHelpers.GetPlayerController()
    if not IsValid(pc) then
        return
    end

    local ok, err = pcall(function()
        local lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        if not IsValid(lib) then
            return
        end
        if active then
            ForceMenuCursor(pc)
            ApplyGameAndUI(lib, pc)
        else
            local others = remainingOpenCount
            if type(others) ~= "number" then
                others = Shared.Get(Shared.OPEN_COUNT)
                if type(others) ~= "number" then
                    others = 0
                end
            end
            if others > 0 then
                -- Another mod's shell still open — do not yank GameAndUI / cursor.
                ForceMenuCursor(pc)
                return
            end
            -- Only GameOnly if we actually took over from mouse-look (saved cursor false).
            -- If the game already had a cursor (hub / inventory), leave its input mode.
            local hadSaved = Shared.Get(Shared.INPUT_SAVED) == true
            local wasShowingCursor = RestoreMenuCursor(pc)
            if hadSaved and wasShowingCursor ~= true then
                ApplyGameOnly(lib, pc)
            end
        end
    end)
    if not ok then
        Util.Log("SetInputMode skipped: " .. tostring(err))
    end
end

--- Re-apply GameAndUI after game UI interrupts (amber toast, etc.).
--- Only call on open, after clicks, or when we detect the cursor was stolen — not every tick.
function M.Reclaim()
    if not isMenuOpen() then
        return
    end
    M.SetActive(true)
end

--- Re-bump look-ignore without re-applying GameAndUI (keeps text/checkbox focus).
function M.RefreshLookIgnore(pc)
    if not getIgnoreLook() then
        return
    end
    if not IsValid(pc) then
        pc = UEHelpers.GetPlayerController()
    end
    if IsValid(pc) then
        EnsureLookIgnored(pc)
    end
end

--- True when the game cleared cursor / click / hover / (opt-in) look-ignore.
--- Overlay cursor: a hidden engine pointer is expected — do not treat that
--- (or a cleared look-ignore) as a full input-mode steal. Re-applying
--- GameAndUI every tick kills checkbox clicks and EditableTextBox focus.
---@param pc any
---@return boolean
function M.CursorStolen(pc)
    if not IsValid(pc) then
        return false
    end
    if OverlayCursor() then
        return not pc.bEnableClickEvents or not pc.bEnableMouseOverEvents
    end
    local lookOk = true
    if getIgnoreLook() then
        pcall(function()
            lookOk = pc:IsLookInputIgnored() == true
        end)
    end
    return not pc.bShowMouseCursor
        or not pc.bEnableClickEvents
        or not pc.bEnableMouseOverEvents
        or not lookOk
end

return M
end

-- core/cursor.lua
package.preload["ModMenu.core.cursor"] = function(...)
--[[
  ModMenu.core.cursor — opt-in ModMenu-owned cursor overlay.

  Init({ cursorMode = "modmenu" }) draws a HitTestInvisible pointer above the
  shell while open. Default remains "engine" (PlayerController / GameAndUI only).

  Optional cursorHideClasses collapses named UUserWidget classes while open
  (host-supplied; e.g. Wuchang WB_Cursor_C). Empty by default — game-agnostic.
  Class defaults are skipped; prior visibility is restored on hide/close.
  A later Init that changes cursorMode / cursorScale / cursorHideClasses
  rebuilds the overlay.
]]

local UEHelpers = require("UEHelpers.UEHelpers")
local Util = require("ModMenu.core.util")
local Instance = require("ModMenu.core.instance")

local M = {}

local POLL_MS = 16
local CURSOR_Z_OFFSET = 1

local VIS_VISIBLE = 0
local VIS_COLLAPSED = 1
local VIS_HITTEST_INVISIBLE = 3

-- Windows IDC_ARROW topology (12x21), restroked at 2x with a 1px outline.
-- 3x read as ~1.5–2× a normal desktop pointer. cursorScale still multiplies
-- this glyph if a host wants it larger.
local SHADOW_COLOR = { R = 0.0, G = 0.0, B = 0.0, A = 0.40 }
local OUTLINE_COLOR = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }
local FILL_COLOR = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }

local SRC_SCALE = 2
local PAD = 2
local SHADOW_OX = 1
local SHADOW_OY = 1
local HOTSPOT_X = PAD
local HOTSPOT_Y = PAD

-- Head-only fill spans (0-based, inclusive). The stem is drawn as a
-- straight 2px ribbon — interpolating the 12px tail is what made it noisy.
local WIN_HEAD_SPANS = {
    [2] = { { 1, 1 } },
    [3] = { { 1, 2 } },
    [4] = { { 1, 3 } },
    [5] = { { 1, 4 } },
    [6] = { { 1, 5 } },
    [7] = { { 1, 6 } },
    [8] = { { 1, 7 } },
    [9] = { { 1, 8 } },
    [10] = { { 1, 9 } },
    [11] = { { 1, 10 } },
    [12] = { { 1, 6 } },
    [13] = { { 1, 3 } },
    [14] = { { 1, 2 } },
    [15] = { { 1, 1 } },
}

local SRC_W = 12
local SRC_H = 21
local GLYPH_W = SRC_W * SRC_SCALE + PAD * 2 + SHADOW_OX
local GLYPH_H = SRC_H * SRC_SCALE + PAD * 2 + SHADOW_OY

local function NewGrid(w, h)
    local g = {}
    for y = 0, h - 1 do
        g[y] = {}
    end
    return g
end

local function InBounds(x, y, w, h)
    return x >= 0 and y >= 0 and x < w and y < h
end

local function Plot(g, x, y, w, h)
    if InBounds(x, y, w, h) then
        g[y][x] = true
    end
end

--- 4-connected ring only — 8-connected dilation makes fat corners.
local function DilateOutline(fill, w, h)
    local outline = NewGrid(w, h)
    local dirs = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            if fill[y][x] then
                for d = 1, #dirs do
                    local nx = x + dirs[d][1]
                    local ny = y + dirs[d][2]
                    if InBounds(nx, ny, w, h) and not fill[ny][nx] then
                        outline[ny][nx] = true
                    end
                end
            end
        end
    end
    return outline
end

local function MergeRuns(runs)
    table.sort(runs, function(a, b)
        if a.x ~= b.x then
            return a.x < b.x
        end
        if a.w ~= b.w then
            return a.w < b.w
        end
        return a.y < b.y
    end)
    local merged = {}
    for i = 1, #runs do
        local r = runs[i]
        local prev = merged[#merged]
        if prev and prev.x == r.x and prev.w == r.w and prev.y + prev.h == r.y then
            prev.h = prev.h + r.h
        else
            merged[#merged + 1] = r
        end
    end
    return merged
end

local function GridToRuns(grid, w, h)
    local runs = {}
    for y = 0, h - 1 do
        local x = 0
        while x < w do
            if grid[y][x] then
                local x0 = x
                x = x + 1
                while x < w and grid[y][x] do
                    x = x + 1
                end
                runs[#runs + 1] = { x = x0, y = y, w = x - x0, h = 1 }
            else
                x = x + 1
            end
        end
    end
    return MergeRuns(runs)
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function FillHead(g, w, h)
    local scale = SRC_SCALE
    local y0 = PAD + 2 * scale
    local y1 = PAD + 15 * scale + (scale - 1)
    for dy = y0, y1 do
        local srcY = (dy - PAD) / scale
        local yA = math.floor(srcY)
        local yB = yA + 1
        local t = srcY - yA
        local a = WIN_HEAD_SPANS[yA] and WIN_HEAD_SPANS[yA][1]
        local b = WIN_HEAD_SPANS[yB] and WIN_HEAD_SPANS[yB][1]
        if a == nil then
            a = b
        end
        if b == nil then
            b = a
        end
        if a ~= nil then
            local x0 = Lerp(a[1], b[1], t)
            local x1 = Lerp(a[2], b[2], t)
            local dx0 = math.floor(PAD + x0 * scale + 0.5)
            local dx1 = math.floor(PAD + (x1 + 1) * scale - 1 + 0.5)
            if dx1 < dx0 then
                dx1 = dx0
            end
            for x = dx0, dx1 do
                Plot(g, x, dy, w, h)
            end
        end
    end
    Plot(g, PAD + 1, PAD + 1, w, h)
end

--- 3-down, 1-right stair. DDA made the tail bend; a regular step stays even.
local function FillStemStair(g, w, h, x0, y0, width, length)
    for i = 0, length - 1 do
        local x = x0 + math.floor(i / 3)
        local y = y0 + i
        for k = 0, width - 1 do
            Plot(g, x + k, y, w, h)
        end
    end
    local capX = x0 + math.floor((length - 1) / 3)
    local capY = y0 + length - 1
    for k = 0, width - 1 do
        Plot(g, capX + k, capY + 1, w, h)
    end
end

--- Outline pixels jammed in the head/stem crease (3+ fill neighbors).
local function CleanJoinOutline(outline, fill, w, h)
    local dirs = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            if outline[y][x] then
                local n = 0
                for d = 1, #dirs do
                    local nx = x + dirs[d][1]
                    local ny = y + dirs[d][2]
                    if InBounds(nx, ny, w, h) and fill[ny][nx] then
                        n = n + 1
                    end
                end
                if n >= 3 then
                    outline[y][x] = nil
                end
            end
        end
    end
end

local function FillWindowsArrow(g, w, h)
    local scale = SRC_SCALE
    FillHead(g, w, h)
    -- Vertical socket in the notch, then a regular stair. Keeps the join
    -- filled so the outline cannot wrap between head and stem.
    local stemW = 2
    local x0 = PAD + 5 * scale
    local socketY = PAD + 10 * scale
    local socketH = 2 * scale + 2
    for oy = 0, socketH - 1 do
        for ox = 0, stemW - 1 do
            Plot(g, x0 + ox, socketY + oy, w, h)
        end
    end
    FillStemStair(g, w, h, x0, socketY + socketH - 2, stemW, 5 * scale + 2)
end

local function OffsetRuns(runs, dx, dy)
    local out = {}
    for i = 1, #runs do
        local r = runs[i]
        out[i] = { x = r.x + dx, y = r.y + dy, w = r.w, h = r.h }
    end
    return out
end

local function BuildPointerRuns()
    local w, h = GLYPH_W, GLYPH_H
    local fill = NewGrid(w, h)
    FillWindowsArrow(fill, w, h)
    local outline = DilateOutline(fill, w, h)
    CleanJoinOutline(outline, fill, w, h)
    local fillRuns = GridToRuns(fill, w, h)
    local outlineRuns = GridToRuns(outline, w, h)
    local shadow = {}
    for i = 1, #outlineRuns do
        shadow[#shadow + 1] = outlineRuns[i]
    end
    for i = 1, #fillRuns do
        shadow[#shadow + 1] = fillRuns[i]
    end
    shadow = MergeRuns(OffsetRuns(shadow, SHADOW_OX, SHADOW_OY))
    return outlineRuns, fillRuns, shadow
end

local ARROW_OUTLINE, ARROW_FILL, ARROW_SHADOW = BuildPointerRuns()

local IsValid = Util.IsValid

local function Log(msg)
    Util.Log("Cursor: " .. tostring(msg))
end

local function Debug(msg)
    Util.Debug("Cursor: " .. tostring(msg))
end

-- Soft construct: overlay must not error() the shell if a class is missing.
local function Construct(classPath, outer, name)
    local cls = StaticFindObject(classPath)
    if not IsValid(cls) then
        return nil
    end
    local obj = StaticConstructObject(cls, outer, FName(name))
    if not IsValid(obj) then
        return nil
    end
    return obj
end

--- UE4SS IsValid is true for pending-kill objects. Native calls on those are fatals.
local function IsLiveWidget(obj)
    if not IsValid(obj) then
        return false
    end
    local dead = false
    pcall(function()
        if obj.IsPendingKill and obj:IsPendingKill() then
            dead = true
        end
    end)
    if dead then
        return false
    end
    pcall(function()
        if obj.bIsPendingKill == true then
            dead = true
        end
    end)
    return not dead
end

local function SetVisibility(widget, vis)
    if not IsLiveWidget(widget) then
        return
    end
    pcall(function()
        widget:SetVisibility(vis)
    end)
end

local function ReadVisibility(widget)
    if not IsValid(widget) then
        return nil
    end
    local ok, vis = pcall(function()
        return widget:GetVisibility()
    end)
    if not ok or vis == nil then
        return nil
    end
    if type(vis) == "number" then
        return vis
    end
    local n = tonumber(vis)
    if n ~= nil then
        return n
    end
    local okVal, value = pcall(function()
        return vis.Value or vis.value
    end)
    if okVal and type(value) == "number" then
        return value
    end
    return nil
end

--- UE4SS FindAllOf often includes the CDO (Default__Class). Collapsing that
--- would change every future instance of the class.
local function IsClassDefault(obj)
    if not IsValid(obj) then
        return true
    end
    local ok, isDefault = pcall(function()
        return obj.IsDefaultObject and obj:IsDefaultObject()
    end)
    if ok and isDefault == true then
        return true
    end
    local okName, name = pcall(function()
        if obj.GetName then
            return tostring(obj:GetName())
        end
        return ""
    end)
    if okName and type(name) == "string" and name:find("Default__", 1, true) then
        return true
    end
    return false
end

local function RemoveOverlayWidget(hud)
    if not IsLiveWidget(hud) then
        return
    end
    pcall(function()
        hud:RemoveFromParent()
    end)
    pcall(function()
        hud:RemoveFromViewport()
    end)
end

--- Mouse coords from GetMousePositionOnViewport are viewport-space. The
--- overlay UserWidget must fill the viewport or SetPosition clips / drifts.
local function FillViewport(hud)
    if not IsValid(hud) then
        return
    end
    pcall(function()
        if hud.SetAnchorsInViewport then
            hud:SetAnchorsInViewport({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        end
        if hud.SetAlignmentInViewport then
            hud:SetAlignmentInViewport({ X = 0, Y = 0 })
        end
        if hud.SetPositionInViewport then
            hud:SetPositionInViewport({ X = 0, Y = 0 }, false)
        end
    end)
    pcall(function()
        local slot = hud.Slot
        if slot == nil or slot.SetAnchors == nil then
            return
        end
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        if slot.SetOffsets then
            slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        end
        if slot.SetAlignment then
            slot:SetAlignment({ X = 0, Y = 0 })
        end
    end)
end

local function AddRect(canvas, name, x, y, w, h, color, z)
    local border = Construct("/Script/UMG.Border", canvas, name)
    if not border then
        return false
    end
    pcall(function()
        border:SetBrushColor(color)
        border:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    end)

    local slot = canvas:AddChildToCanvas(border)
    if not slot then
        return false
    end
    pcall(function()
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
        slot:SetAlignment({ X = 0, Y = 0 })
        slot:SetPosition({ X = x, Y = y })
        slot:SetSize({ X = w, Y = h })
        slot:SetZOrder(z or 1)
    end)
    SetVisibility(border, VIS_HITTEST_INVISIBLE)
    return true
end

local function ReadVec2(v)
    if v == nil then
        return nil, nil
    end
    if type(v) == "table" then
        return v.X or v.x, v.Y or v.y
    end
    local okX, x = pcall(function()
        return v.X
    end)
    local okY, y = pcall(function()
        return v.Y
    end)
    if okX and okY and type(x) == "number" and type(y) == "number" then
        return x, y
    end
    return nil, nil
end

local function GetMouseXY()
    local world = UEHelpers.GetGameInstance()
    if IsValid(world) then
        local ok, lib = pcall(function()
            return StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        end)
        if ok and IsValid(lib) and lib.GetMousePositionOnViewport then
            local okPos, pos = pcall(function()
                return lib:GetMousePositionOnViewport(world)
            end)
            if okPos then
                local x, y = ReadVec2(pos)
                if x and y then
                    return x, y
                end
            end
        end
    end

    local pc = UEHelpers.GetPlayerController()
    if IsValid(pc) and pc.GetMousePosition then
        local ok, a, b = pcall(function()
            return pc:GetMousePosition()
        end)
        if ok and type(a) == "number" and type(b) == "number" then
            return a, b
        end
    end

    return nil, nil
end

local function ResolveScale(config)
    local n = config and config.cursorScale
    if type(n) ~= "number" or n ~= n or n < 1 then
        return 1
    end
    n = math.floor(n + 0.5)
    if n < 1 then
        return 1
    end
    if n > 8 then
        return 8
    end
    return n
end

local function CursorConfigSig(config)
    local mode = (config and config.cursorMode) or "engine"
    local scale = ResolveScale(config)
    local classes = config and config.cursorHideClasses
    local hide = ""
    if type(classes) == "table" and #classes > 0 then
        hide = table.concat(classes, "\0")
    end
    return mode .. "|" .. tostring(scale) .. "|" .. hide
end

local function BuildArrowGlyphRoot(canvas, suffix, scale)
    local sizeBox = Construct("/Script/UMG.SizeBox", canvas, "ModMenu_CursorSize_" .. suffix)
    if not sizeBox then
        return nil
    end
    pcall(function()
        sizeBox:SetWidthOverride(GLYPH_W * scale)
        sizeBox:SetHeightOverride(GLYPH_H * scale)
    end)

    local innerCanvas = Construct("/Script/UMG.CanvasPanel", sizeBox, "ModMenu_CursorInner_" .. suffix)
    if not innerCanvas then
        return nil
    end
    pcall(function()
        sizeBox:SetContent(innerCanvas)
    end)

    for i = 1, #ARROW_SHADOW do
        local part = ARROW_SHADOW[i]
        AddRect(
            innerCanvas,
            "ModMenu_CursorShadow_" .. suffix .. "_" .. i,
            part.x * scale,
            part.y * scale,
            part.w * scale,
            part.h * scale,
            SHADOW_COLOR,
            0
        )
    end
    for i = 1, #ARROW_OUTLINE do
        local part = ARROW_OUTLINE[i]
        AddRect(
            innerCanvas,
            "ModMenu_CursorOutline_" .. suffix .. "_" .. i,
            part.x * scale,
            part.y * scale,
            part.w * scale,
            part.h * scale,
            OUTLINE_COLOR,
            1
        )
    end
    for i = 1, #ARROW_FILL do
        local part = ARROW_FILL[i]
        AddRect(
            innerCanvas,
            "ModMenu_CursorFill_" .. suffix .. "_" .. i,
            part.x * scale,
            part.y * scale,
            part.w * scale,
            part.h * scale,
            FILL_COLOR,
            2
        )
    end

    SetVisibility(sizeBox, VIS_HITTEST_INVISIBLE)
    SetVisibility(innerCanvas, VIS_HITTEST_INVISIBLE)
    return sizeBox
end

local function StopPoll(S)
    if S.cursorPollHandle then
        pcall(function()
            CancelDelayedAction(S.cursorPollHandle)
        end)
        S.cursorPollHandle = nil
    end
    -- Keep S.cursorPollFn pinned. CancelDelayedAction can still run this tick.
end

local function RestoreHidden(S)
    local list = S.cursorHiddenWidgets
    if type(list) ~= "table" then
        return
    end
    for i = 1, #list do
        local entry = list[i]
        local widget = entry
        local vis = VIS_VISIBLE
        if type(entry) == "table" and entry.widget ~= nil then
            widget = entry.widget
            if type(entry.vis) == "number" then
                vis = entry.vis
            end
        end
        SetVisibility(widget, vis)
    end
    S.cursorHiddenWidgets = {}
end

local function HideConfiguredClasses(S)
    RestoreHidden(S)
    local classes = S.config.cursorHideClasses
    if type(classes) ~= "table" or #classes == 0 then
        return
    end
    local hidden = {}
    for i = 1, #classes do
        local cls = classes[i]
        if type(cls) == "string" and cls ~= "" then
            local found = FindAllOf(cls)
            if type(found) == "table" then
                for j = 1, #found do
                    local w = found[j]
                    if IsLiveWidget(w) and not IsClassDefault(w) then
                        hidden[#hidden + 1] = {
                            widget = w,
                            vis = ReadVisibility(w),
                        }
                        SetVisibility(w, VIS_COLLAPSED)
                    end
                end
            end
        end
    end
    S.cursorHiddenWidgets = hidden
end

local function EnsureOverlay(S)
    if IsValid(S.cursorRoot) and S.cursorSlot then
        SetVisibility(S.cursorRoot, VIS_HITTEST_INVISIBLE)
        return true
    end

    local outer = UEHelpers.GetGameInstance()
    if not IsValid(outer) then
        outer = UEHelpers.GetPlayerController()
    end
    if not IsValid(outer) then
        return false
    end

    Instance.Ensure(S.config)
    local suffix = Instance.ShellNameSuffix(S.config)
    local z = Instance.GetViewportZ() + CURSOR_Z_OFFSET

    local hud = Construct("/Script/UMG.UserWidget", outer, "ModMenu_CursorOverlay_" .. suffix)
    if not hud then
        return false
    end

    local tree = Construct("/Script/UMG.WidgetTree", hud, "ModMenu_CursorTree_" .. suffix)
    if not tree then
        RemoveOverlayWidget(hud)
        return false
    end
    hud.WidgetTree = tree

    local canvas = Construct("/Script/UMG.CanvasPanel", tree, "ModMenu_CursorCanvas_" .. suffix)
    if not canvas then
        RemoveOverlayWidget(hud)
        return false
    end
    tree.RootWidget = canvas

    local scale = ResolveScale(S.config)
    local glyph = BuildArrowGlyphRoot(canvas, suffix, scale)
    if not glyph then
        Log("failed to build glyph")
        RemoveOverlayWidget(hud)
        return false
    end

    local slot = canvas:AddChildToCanvas(glyph)
    if not slot then
        Log("failed to add glyph to canvas")
        RemoveOverlayWidget(hud)
        return false
    end
    pcall(function()
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
        slot:SetAlignment({ X = 0, Y = 0 })
        slot:SetPosition({ X = 0, Y = 0 })
        slot:SetAutoSize(true)
        slot:SetZOrder(9999)
    end)

    SetVisibility(hud, VIS_HITTEST_INVISIBLE)
    SetVisibility(canvas, VIS_HITTEST_INVISIBLE)
    SetVisibility(glyph, VIS_HITTEST_INVISIBLE)

    local added = pcall(function()
        hud:AddToViewport(z)
    end)
    if not added then
        Log("failed to add overlay to viewport")
        RemoveOverlayWidget(hud)
        return false
    end
    FillViewport(hud)

    S.cursorScale = scale
    S.cursorHotspotX = HOTSPOT_X * scale
    S.cursorHotspotY = HOTSPOT_Y * scale
    S.cursorRoot = hud
    S.cursorSlot = slot
    Debug(string.format("overlay ready z=%d tag=%s", z, tostring(Instance.GetTag())))
    return true
end

local function UpdatePosition(S)
    if not S.cursorSlot then
        return
    end
    local x, y = GetMouseXY()
    if not x or not y then
        return
    end
    pcall(function()
        S.cursorSlot:SetPosition({
            X = x - (S.cursorHotspotX or HOTSPOT_X),
            Y = y - (S.cursorHotspotY or HOTSPOT_Y),
        })
    end)
end

---@param S table
---@return boolean
function M.IsEnabled(S)
    return S ~= nil and S.config ~= nil and S.config.cursorMode == "modmenu"
end

---@param S table
function M.Show(S)
    if not M.IsEnabled(S) then
        return
    end
    if not EnsureOverlay(S) then
        return
    end
    HideConfiguredClasses(S)
    SetVisibility(S.cursorRoot, VIS_HITTEST_INVISIBLE)
    UpdatePosition(S)
end

---@param S table
function M.Hide(S)
    StopPoll(S)
    RestoreHidden(S)
    if IsValid(S.cursorRoot) then
        SetVisibility(S.cursorRoot, VIS_COLLAPSED)
    end
end

---@param S table
function M.StartPoll(S)
    if not M.IsEnabled(S) then
        return
    end
    StopPoll(S)
    if S.cursorPollFn == nil then
        S.cursorPollFn = Util.PinFn(function()
            if not S.menuOpen or not IsValid(S.cursorRoot) or not S.cursorSlot then
                return
            end
            UpdatePosition(S)
        end)
    end
    S.cursorPollHandle = LoopInGameThreadWithDelay(POLL_MS, S.cursorPollFn)
end

--- Tear down overlay UObjects (ClientRestart / DestroyShell / live Init).
---@param S table
function M.Destroy(S)
    if S.cursorShowHandle ~= nil then
        pcall(function()
            CancelDelayedAction(S.cursorShowHandle)
        end)
        S.cursorShowHandle = nil
    end
    StopPoll(S)
    RestoreHidden(S)
    RemoveOverlayWidget(S.cursorRoot)
    S.cursorRoot = nil
    S.cursorSlot = nil
    S.cursorHiddenWidgets = nil
    S.cursorScale = nil
    S.cursorHotspotX = nil
    S.cursorHotspotY = nil
end

--- Rebuild the overlay when a later Init changes cursorMode / cursorScale /
--- cursorHideClasses. First Init only records the signature (no overlay yet).
---@param S table
function M.OnConfigChanged(S)
    if S == nil or S.config == nil then
        return
    end
    local sig = CursorConfigSig(S.config)
    local prev = S.cursorConfigSig
    S.cursorConfigSig = sig
    if prev == nil or prev == sig then
        return
    end
    M.Destroy(S)
    if M.IsEnabled(S) and S.menuOpen then
        M.Show(S)
        M.StartPoll(S)
    end
end

return M
end

-- core/input.lua
package.preload["ModMenu.core.input"] = function(...)
--[[
  ModMenu.core.input — toggle + LMB click latch.

  Backends (Init inputBackend; no auto-detect):
    ue4ss  — RegisterKeyBind (default; games where UE4SS keybinds fire)
    engine — poll APlayerController:IsInputKeyDown (games where they do not)

  Hosts call ModMenu.Init only. This module owns implementation.
]]

local UEHelpers = require("UEHelpers.UEHelpers")
local Util = require("ModMenu.core.util")

local M = {}

local LMB_UE_NAME = "LeftMouseButton"
local ENGINE_POLL_MS = 50

-- IsPressed() polling misses short clicks on constructed UButtons.
local mouseClickLatch = false
local clickIgnore = 0
local pointerTouch = false

-- Touch: ignore delayed LMB latch after press-edge (~320ms at 16ms poll).
local TOUCH_IGNORE_TICKS = 20
-- Touch only: mouse-down often drops IsHovered before pollClick.
local HOVER_STICKY_TOUCH = 8
local LATCH_RETRY_TOUCH = 10

local lastHoverWidget = nil
local lastHoverAge = 999
local latchRetryLeft = 0

local installed = false
local enginePollHandle = nil
local togglePrevDown = false
local lmbPrevDown = false
local inputProbeLogged = false

local function Log(msg)
    Util.Log(msg)
end

local function Debug(msg)
    Util.Debug(msg)
end

local function IsValid(obj)
    return Util.IsValid(obj)
end

local function MakeFKey(ueName)
    local fname = UEHelpers.FindOrAddFName(ueName)
    if fname == nil or fname == NAME_None then
        return nil
    end
    return { KeyName = fname }
end

--- Rising edge of IsInputKeyDown. 50ms poll misses WasInputKeyJustPressed (1-frame).
local function IsKeyDown(pc, fkey)
    if fkey == nil or not IsValid(pc) then
        return false
    end
    local ok, result = pcall(function()
        return pc:IsInputKeyDown(fkey) == true
    end)
    if ok then
        return result == true
    end
    -- Some UE4SS builds accept the FName instead of an FKey table.
    if fkey.KeyName ~= nil then
        ok, result = pcall(function()
            return pc:IsInputKeyDown(fkey.KeyName) == true
        end)
        if ok then
            return result == true
        end
    end
    if not inputProbeLogged then
        inputProbeLogged = true
        Log("engine IsInputKeyDown failed: " .. tostring(result))
    end
    return false
end

local function KeyWentDown(pc, fkey, prevDown)
    local down = IsKeyDown(pc, fkey)
    return (down and not prevDown), down
end

--- fn must already be pinned. A fresh wrapper here is what GC's into
--- "Ref was not function" and UE4SS then removes the whole EngineTick hook.
local function FireOnGameThread(fn)
    if type(fn) ~= "function" then
        return
    end
    ExecuteInGameThread(fn)
end

local function InstallUe4ss(opts)
    RegisterKeyBind(opts.key, function()
        FireOnGameThread(opts.onToggle)
    end)
    RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
        if opts.isMenuOpen and opts.isMenuOpen() then
            mouseClickLatch = true
        end
    end)
    Debug(string.format("input backend=ue4ss toggle=%s", tostring(opts.keyName or opts.key)))
end

local function InstallEngine(opts)
    local toggleKey = MakeFKey(opts.keyName)
    local lmbKey = MakeFKey(LMB_UE_NAME)
    if toggleKey == nil then
        Log(string.format("engine backend: invalid keyName %q (FName not found)", tostring(opts.keyName)))
        return
    end
    if lmbKey == nil then
        Log("engine backend: LeftMouseButton FName not found")
        return
    end

    if enginePollHandle ~= nil then
        return
    end

    enginePollHandle = LoopInGameThreadWithDelay(ENGINE_POLL_MS, Util.PinFn(function()
        local pc = UEHelpers.GetPlayerController()
        if not IsValid(pc) then
            togglePrevDown = false
            lmbPrevDown = false
            return
        end

        local toggleDown
        toggleDown, togglePrevDown = KeyWentDown(pc, toggleKey, togglePrevDown)
        if toggleDown then
            Util.SafeCall(opts.onToggle)
        end

        if opts.isMenuOpen and opts.isMenuOpen() then
            local lmbDown
            lmbDown, lmbPrevDown = KeyWentDown(pc, lmbKey, lmbPrevDown)
            if lmbDown then
                mouseClickLatch = true
            end
        else
            lmbPrevDown = false
        end
    end))

    Debug(string.format("input backend=engine poll %s + LMB (%dms)", tostring(opts.keyName), ENGINE_POLL_MS))
end

local function InstallConsoleCommand(opts)
    local name = opts.consoleCommand
    if type(name) ~= "string" or name == "" then
        return
    end
    RegisterConsoleCommandHandler(name, function(FullCommand, Parameters, Ar)
        local action = string.lower(tostring(Parameters[1] or "toggle"))
        if action == "open" then
            FireOnGameThread(opts.onOpen or opts.onToggle)
            if Ar and Ar.Log then
                Ar:Log("ModMenu open")
            end
        elseif action == "close" then
            FireOnGameThread(opts.onClose or opts.onToggle)
            if Ar and Ar.Log then
                Ar:Log("ModMenu close")
            end
        elseif action == "toggle" then
            FireOnGameThread(opts.onToggle)
            if Ar and Ar.Log then
                Ar:Log("ModMenu toggle")
            end
        else
            local usage = "Usage: " .. name .. " [toggle|open|close]"
            print("[ModMenu] " .. usage)
            if Ar and Ar.Log then
                Ar:Log(usage)
            end
        end
        return true
    end)
    Debug(string.format("console command %q registered", name))
end

--- Bind toggle + LMB once. Same backend for both.
---@param opts { backend: string, key: any, keyName: string, onToggle: function, onOpen?: function, onClose?: function, isMenuOpen: fun(): boolean, consoleCommand?: string }
function M.Install(opts)
    if installed then
        return
    end
    opts = opts or {}
    if type(opts.onToggle) ~= "function" then
        error("ModMenu.core.input.Install: onToggle must be a function")
    end
    if type(opts.isMenuOpen) ~= "function" then
        error("ModMenu.core.input.Install: isMenuOpen must be a function")
    end
    opts.onToggle = Util.PinFn(opts.onToggle)
    if type(opts.onOpen) == "function" then
        opts.onOpen = Util.PinFn(opts.onOpen)
    end
    if type(opts.onClose) == "function" then
        opts.onClose = Util.PinFn(opts.onClose)
    end

    local backend = opts.backend or "ue4ss"
    if backend == "ue4ss" then
        if opts.key == nil then
            error("ModMenu.core.input.Install: key is required for backend ue4ss")
        end
        InstallUe4ss(opts)
    elseif backend == "engine" then
        if type(opts.keyName) ~= "string" or opts.keyName == "" then
            error("ModMenu.core.input.Install: keyName is required for backend engine (Unreal FKey, e.g. \"F7\")")
        end
        InstallEngine(opts)
    else
        error('ModMenu.core.input.Install: backend must be "ue4ss" or "engine"')
    end

    InstallConsoleCommand(opts)
    installed = true
end

function M.ConsumeMouseClick()
    if clickIgnore > 0 then
        clickIgnore = clickIgnore - 1
        mouseClickLatch = false
        latchRetryLeft = 0
        return false
    end
    if not mouseClickLatch then
        return false
    end
    mouseClickLatch = false
    return true
end

--- Unclaimed latch: try again next poll so a late IsHovered / IsPressed can still fire.
--- Touch only — on mouse this retry lets an earlier widget steal the real click.
---@return boolean true if another attempt is scheduled
function M.RetryUnclaimedClick()
    if not pointerTouch then
        return false
    end
    if latchRetryLeft == 0 then
        latchRetryLeft = LATCH_RETRY_TOUCH
    end
    latchRetryLeft = latchRetryLeft - 1
    if latchRetryLeft <= 0 then
        latchRetryLeft = 0
        return false
    end
    mouseClickLatch = true
    return true
end

local function NoteHover(widget)
    if widget == nil then
        return
    end
    local ok, hovered = pcall(function()
        return widget:IsHovered()
    end)
    if ok and (hovered == true or hovered == 1) then
        lastHoverWidget = widget
        lastHoverAge = 0
    end
end

--- Once per poll: age the last hover, then record who is hovered this tick.
--- Touch only — desktop IsHovered is enough and sticky would steal later buttons.
---@param controls table|nil
function M.BeginPoll(controls)
    if not pointerTouch then
        return
    end
    lastHoverAge = lastHoverAge + 1
    if controls == nil then
        return
    end
    for _, ctrl in ipairs(controls) do
        NoteHover(ctrl.widget)
        NoteHover(ctrl.headerBtn)
        NoteHover(ctrl.headerLabel)
        if ctrl.optionRows then
            for _, row in ipairs(ctrl.optionRows) do
                NoteHover(row.button)
            end
        end
    end
end

function M.SetPointerMode(mode)
    pointerTouch = mode == "touch"
end

function M.IsTouch()
    return pointerTouch == true
end

function M.IgnoreClicks(n)
    local ticks = n or 2
    if pointerTouch then
        ticks = math.max(ticks, TOUCH_IGNORE_TICKS)
    end
    clickIgnore = math.max(clickIgnore, ticks)
    mouseClickLatch = false
    latchRetryLeft = 0
    lastHoverWidget = nil
    lastHoverAge = 999
end

--- After a latch click, mark the widget down so WidgetPressedEdge does not
--- fire again on the next 16ms tick (IsPressed / HasMouseCapture lag).
---@param state table|nil
---@param flagKey string|nil
function M.SuppressPressEdge(state, flagKey)
    if state ~= nil then
        state[flagKey or "wasPressed"] = true
    end
end

--- Clear latch + ignore counters (e.g. after content rebuild while open).
function M.ClearClickState()
    mouseClickLatch = false
    clickIgnore = 0
    latchRetryLeft = 0
    lastHoverWidget = nil
    lastHoverAge = 999
end

local function IsTruthy(value)
    return value == true or value == 1
end

-- UE4SS FVector2D fields are often userdata, not Lua numbers.
local function AsNumber(v)
    if v == nil then
        return nil
    end
    if type(v) == "number" then
        return v
    end
    local ok, n = pcall(tonumber, v)
    if ok and type(n) == "number" then
        return n
    end
    ok, n = pcall(function()
        return v + 0
    end)
    if ok and type(n) == "number" then
        return n
    end
    return nil
end

local function ReadVec2(v)
    if v == nil then
        return nil, nil
    end
    if type(v) == "table" then
        return AsNumber(v.X or v.x), AsNumber(v.Y or v.y)
    end
    local okX, x = pcall(function()
        return v.X
    end)
    local okY, y = pcall(function()
        return v.Y
    end)
    if not okX or not okY then
        return nil, nil
    end
    return AsNumber(x), AsNumber(y)
end

--- Viewport-space pointer (Windows touch is a fake mouse). Debug traces only.
---@return number|nil, number|nil
local function GetPointerXY()
    local world = UEHelpers.GetGameInstance()
    if IsValid(world) then
        local ok, lib = pcall(function()
            return StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        end)
        if ok and IsValid(lib) and lib.GetMousePositionOnViewport then
            local okPos, pos = pcall(function()
                return lib:GetMousePositionOnViewport(world)
            end)
            if okPos then
                local x, y = ReadVec2(pos)
                if x and y then
                    return x, y
                end
            end
        end
    end
    local pc = UEHelpers.GetPlayerController()
    if IsValid(pc) and pc.GetMousePosition then
        local ok, a, b = pcall(function()
            return pc:GetMousePosition()
        end)
        if ok then
            a, b = AsNumber(a), AsNumber(b)
            if a and b then
                return a, b
            end
        end
    end
    return nil, nil
end

---@param widget any
---@return boolean pressed
---@return boolean capture
local function ReadPressedCapture(widget)
    local pressed = false
    local capture = false
    if widget == nil then
        return false, false
    end
    pcall(function()
        pressed = IsTruthy(widget:IsPressed())
    end)
    pcall(function()
        capture = IsTruthy(widget:HasMouseCapture())
    end)
    return pressed, capture
end

local function CtrlTag(ctrl)
    if ctrl == nil then
        return "kind=? id=?"
    end
    local id = nil
    if ctrl.item ~= nil and ctrl.item.id ~= nil then
        id = ctrl.item.id
    elseif ctrl.tabId ~= nil then
        id = ctrl.tabId
    elseif ctrl.sectionId ~= nil then
        id = ctrl.sectionId
    elseif ctrl.role ~= nil then
        id = ctrl.role
    end
    return string.format("kind=%s id=%s", tostring(ctrl.kind or "?"), tostring(id or "?"))
end

--- Click-path trace. No-op unless Init({ debug = true }).
--- path=press-edge | latch-hover | latch-miss.
---@param path string
---@param ctrl table|nil
---@param widget any|nil
function M.DebugClick(path, ctrl, widget)
    if not Util.IsDebug() then
        return
    end
    widget = widget or (ctrl and (ctrl.widget or ctrl.headerBtn))
    local px, py = GetPointerXY()
    local hovered = M.WidgetHovered(widget)
    local pressed, capture = ReadPressedCapture(widget)
    local downVia = "none"
    if pressed then
        downVia = "pressed"
    elseif capture then
        downVia = "capture"
    end
    local ptr = "ptr=?"
    if px ~= nil and py ~= nil then
        ptr = string.format("ptr=%.0f,%.0f", px, py)
    end
    Debug(string.format(
        "click path=%s %s hover=%s pressed=%s capture=%s downVia=%s %s",
        tostring(path),
        CtrlTag(ctrl),
        hovered and "1" or "0",
        pressed and "1" or "0",
        capture and "1" or "0",
        downVia,
        ptr
    ))
end

function M.WidgetHovered(widget)
    if widget == nil then
        return false
    end
    local ok, hovered = pcall(function()
        return widget:IsHovered()
    end)
    if ok and IsTruthy(hovered) then
        return true
    end
    if not pointerTouch then
        return false
    end
    -- Finger-down often clears IsHovered before pollClick; keep the last widget briefly.
    return widget == lastHoverWidget and lastHoverAge <= HOVER_STICKY_TOUCH
end

--- IsPressed, or HasMouseCapture when constructed UButtons lag the pressed flag.
---@param widget any
---@return boolean
function M.WidgetIsDown(widget)
    if widget == nil then
        return false
    end
    local ok, pressed = pcall(function()
        return widget:IsPressed()
    end)
    if ok and IsTruthy(pressed) then
        return true
    end
    ok, pressed = pcall(function()
        return widget:HasMouseCapture()
    end)
    return ok and IsTruthy(pressed)
end

--- Rising edge of UButton press. Do not gate on type()=="function": UE4SS UFunctions
--- are userdata, so that check skipped IsPressed entirely (hover/press visuals still worked).
---@param state table
---@param widget any
---@param flagKey string|nil default "wasPressed"
---@return boolean
function M.WidgetPressedEdge(state, widget, flagKey)
    flagKey = flagKey or "wasPressed"
    if state == nil or widget == nil then
        return false
    end
    local down = M.WidgetIsDown(widget)
    local wentDown = down and not state[flagKey]
    state[flagKey] = down
    return wentDown
end

return M
end

-- core/options.lua
package.preload["ModMenu.core.options"] = function(...)
--[[
  ModMenu.core.options — dropdown option normalize / filter helpers.
]]

local Util = require("ModMenu.core.util")

local M = {}

--- Normalize dropdown options into { {label, value}, ... } plus lookup maps.
--- Labels/values are forced to plain Lua strings so lang + category behave identically.
function M.NormalizeOptions(options)
    local list = {}
    local labelToValue = {}
    local valueToLabel = {}
    for _, opt in ipairs(options or {}) do
        if type(opt) == "string" then
            local s = Util.ToPlainString(opt) or opt
            table.insert(list, { label = s, value = s })
            labelToValue[s] = s
            valueToLabel[s] = s
        elseif type(opt) == "table" then
            local value = opt.value
            local label = opt.label
            if value == nil and label == nil then
                error("dropdown option needs .label or .value")
            end
            if label == nil then
                label = value
            end
            if value == nil then
                value = label
            end
            label = Util.ToPlainString(label) or tostring(label)
            value = Util.ToPlainString(value) or tostring(value)
            table.insert(list, { label = label, value = value })
            labelToValue[label] = value
            valueToLabel[value] = label
        end
    end
    return list, labelToValue, valueToLabel
end

function M.OptionMatchesFilter(label, filter)
    if filter == nil or filter == "" then
        return true
    end
    local hay = string.lower(tostring(label or ""))
    local needle = string.lower(tostring(filter))
    return string.find(hay, needle, 1, true) ~= nil
end

function M.GetWidgetPlainText(widget)
    if widget == nil then
        return ""
    end
    local ok, text = pcall(function()
        return widget:GetText()
    end)
    if not ok or text == nil then
        return ""
    end
    return Util.ToPlainString(text) or tostring(text) or ""
end

return M
end

-- core/dockmath.lua
package.preload["ModMenu.core.dockmath"] = function(...)
--[[
  ModMenu.core.dockmath — viewport fractions for a docked panel. No UMG.
]]

local M = {}

--- rightFrac = thickness-edge gap; widthFrac = thickness; topFrac/bottomFrac = long-axis margins.
---@return { minX: number, maxX: number, minY: number, maxY: number }
function M.PercentRect(config)
    local edge = config.rightFrac or 0.01
    local thick = config.widthFrac or 0.32
    local longMin = config.topFrac or 0
    local longMax = 1.0 - (config.bottomFrac or 0)
    local dock = config.dock
    if dock == "top" then
        return { minX = longMin, maxX = longMax, minY = edge, maxY = edge + thick }
    end
    if dock == "bottom" then
        return {
            minX = longMin,
            maxX = longMax,
            minY = 1.0 - thick - edge,
            maxY = 1.0 - edge,
        }
    end
    if dock == "left" then
        return { minX = edge, maxX = edge + thick, minY = longMin, maxY = longMax }
    end
    return {
        minX = 1.0 - thick - edge,
        maxX = 1.0 - edge,
        minY = longMin,
        maxY = longMax,
    }
end

return M
end

-- widgets/button.lua
package.preload["ModMenu.widgets.button"] = function(...)
--[[
  ModMenu widget: button

  Visual layers (disabled wins, then active, then variant):
    enabled = false  → themed disabled chrome + no clicks
    active = true    → "this is on" (green) — not a variant
    variant          → Bootstrap-like intent (primary/danger/warning/…)
    default          → theme buttonBg
    confirm          → optional table; onClick waits for the in-shell modal
]]

local Util = require("ModMenu.core.util")
local Theme = require("ModMenu.core.theme")

local Button = {}
Button.type = "button"

local VARIANTS = {
    default = true,
    primary = true,
    secondary = true,
    success = true,
    danger = true,
    warning = true,
    info = true,
}

-- Short-lived names from the first variant pass.
local ALIASES = {
    accent = "primary",
}

local VARIANT_CHROME = {
    primary = { "buttonBgPrimary", "buttonTextPrimary" },
    secondary = { "buttonBgSecondary", "buttonTextSecondary" },
    success = { "buttonBgSuccess", "buttonTextSuccess" },
    danger = { "buttonBgDanger", "buttonTextDanger" },
    warning = { "buttonBgWarning", "buttonTextWarning" },
    info = { "buttonBgInfo", "buttonTextInfo" },
}

local VARIANT_HELP = "default|primary|secondary|success|danger|warning|info"

function Button.NormalizeVariant(value)
    if value == nil or value == "" then
        return "default"
    end
    if type(value) ~= "string" then
        return nil
    end
    value = ALIASES[value] or value
    if VARIANTS[value] then
        return value
    end
    return nil
end

local function ChromeColors(colors, item)
    colors = colors or {}
    local fallbackBg, fallbackFg = colors.buttonBg, colors.buttonText
    if item.enabled == false then
        return colors.buttonBgDisabled or fallbackBg, colors.buttonTextDisabled or fallbackFg
    end
    if item.active == true then
        return colors.buttonBgActive or fallbackBg, colors.buttonTextActive or fallbackFg
    end
    local variant = item.variant or "default"
    local keys = VARIANT_CHROME[variant]
    if keys then
        return colors[keys[1]] or fallbackBg, colors[keys[2]] or fallbackFg
    end
    return fallbackBg, fallbackFg
end

--- Paint UMG from item.enabled / item.active / item.variant.
function Button.applyChrome(ctrl, ctx)
    if ctrl == nil or ctrl.item == nil then
        return
    end
    local item = ctrl.item
    local enabled = item.enabled ~= false
    ctrl.enabled = enabled
    local colors = Theme.Of(ctx and ctx.config)
    local bg, fg = ChromeColors(colors, item)
    pcall(function()
        if ctrl.widget ~= nil then
            ctrl.widget:SetIsEnabled(enabled)
            ctrl.widget:SetBackgroundColor(bg)
        end
    end)
    if ctrl.labelWidget ~= nil and ctx ~= nil and ctx.umg ~= nil then
        ctx.umg.StyleText(ctrl.labelWidget, ctx.config.fontItem, fg)
    end
end

function Button.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onClick ~= nil and type(item.onClick) ~= "function" then
        error(prefix .. " onClick must be a function")
    end
    if item.enabled ~= nil and type(item.enabled) ~= "boolean" then
        error(prefix .. " enabled must be a boolean")
    end
    if item.active ~= nil and type(item.active) ~= "boolean" then
        error(prefix .. " active must be a boolean")
    end
    if item.variant ~= nil and Button.NormalizeVariant(item.variant) == nil then
        error(prefix .. " variant must be " .. VARIANT_HELP)
    end
    if item.confirm ~= nil then
        if type(item.confirm) ~= "table" then
            error(prefix .. " confirm must be a table")
        end
        for _, key in ipairs({ "title", "message", "confirmLabel", "cancelLabel" }) do
            if item.confirm[key] ~= nil and type(item.confirm[key]) ~= "string" then
                error(prefix .. " confirm." .. key .. " must be a string")
            end
        end
        if item.confirm.variant ~= nil and Button.NormalizeVariant(item.confirm.variant) == nil then
            error(prefix .. " confirm.variant must be " .. VARIANT_HELP)
        end
        if item.onClick == nil then
            error(prefix .. " confirm requires onClick (runs after Confirm)")
        end
    end
end

function Button.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    item.variant = Button.NormalizeVariant(item.variant) or "default"
    local button, label = umg.CreateTextButton(ctx.contentBox, ctx.namePrefix, item.label)
    umg.AddToContent(ctx, button)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    local ctrl = {
        kind = "button",
        sectionId = ctx.section.id,
        item = item,
        widget = button,
        labelWidget = label,
        enabled = item.enabled ~= false,
        wasPressed = false,
    }
    Button.applyChrome(ctrl, ctx)
    table.insert(ctx.liveControls, ctrl)
end

--- Fire onClick. Shared by IsPressed poll and LMB-latch pollClick.
---@param path string
local function FireClick(ctrl, ctx, path)
    ctx.Input.DebugClick(path, ctrl, ctrl.widget)
    ctx.Input.SuppressPressEdge(ctrl)
    if ctrl.item.confirm ~= nil and ctx.ShowConfirm ~= nil then
        ctx.ShowConfirm(ctrl.item)
    else
        ctx.SafeCall(ctrl.item.onClick)
    end
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    -- Reclaim touches PlayerController / SetInputMode — must stay on the game thread.
    ExecuteInGameThreadWithDelay(200, Util.PinFn(function()
        ctx.ReclaimMenuInput()
    end))
    return true
end

--- Continuous press poll — does not need the global LMB latch (engine / GameAndUI).
function Button.poll(ctrl, ctx)
    if ctrl.enabled == false then
        return
    end
    if ctx.Input.WidgetPressedEdge(ctrl, ctrl.widget) then
        FireClick(ctrl, ctx, "press-edge")
    end
end

--- @return boolean true if click consumed
function Button.pollClick(ctrl, ctx)
    if ctrl.enabled == false then
        return false
    end
    if not ctx.Input.WidgetHovered(ctrl.widget) then
        return false
    end
    return FireClick(ctrl, ctx, "latch-hover")
end

return Button
end

-- widgets/checkbox.lua
package.preload["ModMenu.widgets.checkbox"] = function(...)
--[[
  ModMenu widget: checkbox

  Desktop: native UCheckBox, poll IsChecked().
  pointerMode = "touch": UButton toggle (same onChange(bool)). Native UCheckBox
  on a handheld needs a cursor + A; constructed buttons fire press-edge from a tap.
]]

local Button = require("ModMenu.widgets.button")
local Theme = require("ModMenu.core.theme")

local Checkbox = {}
Checkbox.type = "checkbox"

local function IsEnabled(item)
    return item == nil or item.enabled ~= false
end

local function PaintDisabled(ctrl, ctx)
    if IsEnabled(ctrl.item) then
        return
    end
    pcall(function()
        if ctrl.widget then
            ctrl.widget:SetIsEnabled(false)
        end
    end)
    local colors = Theme.Of(ctx and ctx.config)
    local fg = colors.buttonTextDisabled or colors.textMuted
    if ctrl.label and ctx and ctx.umg then
        ctx.umg.StyleText(ctrl.label, ctx.config and ctx.config.fontItem, fg)
    end
end

local function Caption(item, isOn)
    if item.showState == false then
        return item.label
    end
    return string.format("%s: %s", item.label, isOn and "ON" or "OFF")
end

Checkbox.Caption = Caption

local function UseTouchButton(ctx)
    return ctx ~= nil and ctx.Input ~= nil and ctx.Input.IsTouch and ctx.Input.IsTouch()
end

local function PaintToggle(ctrl, ctx, isOn)
    ctrl.paintItem = {
        active = isOn == true,
        enabled = true,
        variant = "default",
    }
    local paint = {
        kind = "checkbox",
        widget = ctrl.widget,
        labelWidget = ctrl.label or ctrl.labelWidget,
        item = ctrl.paintItem,
    }
    Button.applyChrome(paint, ctx)
end

function Checkbox.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
    if item.enabled ~= nil and type(item.enabled) ~= "boolean" then
        error(prefix .. " enabled must be a boolean")
    end
end

function Checkbox.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    if values[vkey] == nil then
        values[vkey] = item.default and true or false
    end
end

function Checkbox.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = ctx.values[vkey]
    if current == nil then
        current = item.default and true or false
        ctx.values[vkey] = current
    end

    local asButton = UseTouchButton(ctx)
    local widget
    local label
    if asButton then
        widget, label = umg.CreateTextButton(ctx.contentBox, ctx.namePrefix, Caption(item, current))
    else
        widget, label = umg.CreateLabeledToggle(
            ctx.contentBox,
            ctx.namePrefix,
            Caption(item, current),
            current
        )
    end
    umg.AddToContent(ctx, widget)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    local ctrl = {
        kind = "checkbox",
        sectionId = ctx.section.id,
        item = item,
        widget = widget,
        label = label,
        labelWidget = label,
        valueKey = vkey,
        asButton = asButton,
        wasPressed = false,
    }
    if asButton then
        PaintToggle(ctrl, ctx, current)
    end
    if not IsEnabled(item) then
        ctx.values[vkey] = false
        pcall(function() widget:SetIsChecked(false) end)
        PaintDisabled(ctrl, ctx)
    end
    table.insert(ctx.liveControls, ctrl)
end

local function FireToggle(ctrl, ctx, path)
    if not IsEnabled(ctrl.item) then
        return false
    end
    local nextOn = not (ctx.values[ctrl.valueKey] == true)
    ctx.values[ctrl.valueKey] = nextOn
    ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, nextOn))
    PaintToggle(ctrl, ctx, nextOn)
    ctx.Input.DebugClick(path, ctrl, ctrl.widget)
    ctx.Input.SuppressPressEdge(ctrl)
    ctx.SafeCall(ctrl.item.onChange, nextOn)
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    return true
end

--- Native box: IsChecked. Touch button: IsPressed rising edge.
function Checkbox.poll(ctrl, ctx)
    if not IsEnabled(ctrl.item) then
        pcall(function() ctrl.widget:SetIsChecked(false) end)
        return
    end
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    if ctrl.asButton then
        if ctx.Input.WidgetPressedEdge(ctrl, ctrl.widget) then
            FireToggle(ctrl, ctx, "press-edge")
        end
        return
    end
    local ok, checked = pcall(function()
        return ctrl.widget:IsChecked()
    end)
    if ok and checked ~= ctx.values[ctrl.valueKey] then
        ctx.values[ctrl.valueKey] = checked
        ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, checked))
        ctx.SafeCall(ctrl.item.onChange, checked)
        ctx.ReclaimMenuInput()
    end
end

function Checkbox.pollClick(ctrl, ctx)
    if not IsEnabled(ctrl.item) then
        return false
    end
    if not ctrl.asButton then
        return false
    end
    if not ctx.Input.WidgetHovered(ctrl.widget) then
        return false
    end
    return FireToggle(ctrl, ctx, "latch-hover")
end

function Checkbox.apply(ctrl, value, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    if not IsEnabled(ctrl.item) then
        value = false
    end
    local on = value and true or false
    if ctrl.asButton then
        ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, on))
        PaintToggle(ctrl, ctx, on)
        return
    end
    pcall(function()
        ctrl.widget:SetIsChecked(on)
    end)
    ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, on))
    if not IsEnabled(ctrl.item) then
        PaintDisabled(ctrl, ctx)
    end
end

return Checkbox
end

-- widgets/dropdown.lua
package.preload["ModMenu.widgets.dropdown"] = function(...)
--[[
  ModMenu widget: dropdown (plain + searchable).
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Theme = require("ModMenu.core.theme")
local Options = require("ModMenu.core.options")
local Input = require("ModMenu.core.input")

local Dropdown = {}
Dropdown.type = "dropdown"

local VIS_VISIBLE = 0
local VIS_COLLAPSED = 1

local DROPDOWN_LIST_MAX_HEIGHT = 320
local DROPDOWN_SEARCHABLE_MAX_ROWS = 400

local dropdownRowSerial = 0

local function SyncHeader(ctrl)
    local label = ctrl.selectedLabel
    if ctrl.selectedValue == nil or label == nil or label == "" then
        label = ctrl.placeholder or "Select..."
    end
    Umg.SetLabelText(ctrl.headerLabel, tostring(label))
    Umg.SetLabelText(ctrl.arrowLabel, ctrl.expanded and "▲" or "▼")
end

local function RebuildRows(ctrl)
    if ctrl == nil or ctrl.listBox == nil then
        return
    end
    pcall(function()
        ctrl.listBox:ClearChildren()
    end)
    ctrl.optionRows = {}

    local maxVisible = ctrl.maxVisible or 12
    local filter = ctrl.searchFilter or ""
    local matched = 0
    local shown = 0
    local fontDropdown = ctrl.fontDropdown or 15
    local optionBg = ctrl.optionBg
    local optionText = ctrl.optionText
    local selectedBg = ctrl.optionSelectedBg or optionBg
    local selectedText = ctrl.optionSelectedText or optionText
    local selectedValue = Util.ToPlainString(ctrl.selectedValue) or ctrl.selectedValue

    for _, opt in ipairs(ctrl.list or {}) do
        if Options.OptionMatchesFilter(opt.label, filter) then
            matched = matched + 1
            if shown < maxVisible then
                shown = shown + 1
                dropdownRowSerial = dropdownRowSerial + 1
                local optValue = Util.ToPlainString(opt.value) or opt.value
                local isSelected = selectedValue ~= nil and optValue == selectedValue
                local btn, lbl = Umg.CreateTextButton(
                    ctrl.listBox,
                    ctrl.namePrefix .. "_Opt" .. tostring(dropdownRowSerial),
                    opt.label,
                    isSelected and selectedBg or optionBg,
                    isSelected and selectedText or optionText,
                    fontDropdown
                )
                ctrl.listBox:AddChildToVerticalBox(btn)
                table.insert(ctrl.optionRows, {
                    button = btn,
                    label = lbl,
                    optLabel = opt.label,
                    optValue = opt.value,
                    wasPressed = false,
                })
            end
        end
    end

    if ctrl.scrollBox ~= nil then
        pcall(function()
            ctrl.scrollBox:ScrollToStart()
        end)
    end

    if ctrl.moreLabel ~= nil then
        local extra = matched - shown
        if extra > 0 then
            Umg.SetLabelText(ctrl.moreLabel, string.format("…%d more — type to narrow", extra))
            pcall(function()
                ctrl.moreLabel:SetVisibility(VIS_VISIBLE)
            end)
        elseif matched == 0 then
            Umg.SetLabelText(ctrl.moreLabel, "No matches")
            pcall(function()
                ctrl.moreLabel:SetVisibility(VIS_VISIBLE)
            end)
        else
            pcall(function()
                ctrl.moreLabel:SetVisibility(VIS_COLLAPSED)
            end)
        end
    end
end

local function SetExpanded(ctrl, expanded)
    ctrl.expanded = expanded and true or false
    pcall(function()
        if ctrl.optionsBox ~= nil then
            ctrl.optionsBox:SetVisibility(ctrl.expanded and VIS_VISIBLE or VIS_COLLAPSED)
        end
    end)
    if ctrl.expanded then
        if ctrl.searchable then
            ctrl.searchFilter = ""
            pcall(function()
                if ctrl.searchBox ~= nil then
                    ctrl.searchBox:SetText(FText(""))
                end
            end)
        end
        RebuildRows(ctrl)
    end
    SyncHeader(ctrl)
end

function Dropdown.collapseAll(liveControls, exceptCtrl)
    for _, ctrl in ipairs(liveControls or {}) do
        if ctrl.kind == "dropdown" and ctrl ~= exceptCtrl then
            SetExpanded(ctrl, false)
        end
    end
end

local function CreatePicker(outer, namePrefix, options, selectedValue, dropOpts, config)
    dropOpts = dropOpts or {}
    config = config or {}
    local searchable = dropOpts.searchable == true
    local placeholder = dropOpts.placeholder or "Select..."
    local maxVisible = dropOpts.maxVisible
        or (searchable and DROPDOWN_SEARCHABLE_MAX_ROWS or 9999)
    local listMaxHeight = dropOpts.listMaxHeight or DROPDOWN_LIST_MAX_HEIGHT
    local allowEmpty = dropOpts.allowEmpty == true or searchable or dropOpts.placeholder ~= nil
    local fontDropdown = config.fontDropdown or 15
    local fontHint = config.fontHint or 14
    local colors = Theme.Of(config)

    local list, labelToValue, valueToLabel = Options.NormalizeOptions(options)
    selectedValue = Util.ToPlainString(selectedValue) or selectedValue
    local selectedLabel = selectedValue ~= nil and valueToLabel[selectedValue] or nil
    if selectedLabel == nil and #list > 0 and not allowEmpty then
        selectedLabel = list[1].label
        selectedValue = list[1].value
    end
    if selectedLabel == nil then
        selectedLabel = placeholder
        selectedValue = nil
    end

    local root = Umg.Construct("/Script/UMG.VerticalBox", outer, namePrefix .. "_Root")

    local headerBtn = Umg.Construct("/Script/UMG.Button", root, namePrefix .. "_Header_Btn")
    pcall(function()
        headerBtn:SetBackgroundColor(colors.dropdownHeaderBg)
        if headerBtn.SetClickMethod then
            headerBtn:SetClickMethod(1)
        end
        if headerBtn.SetTouchMethod then
            headerBtn:SetTouchMethod(1)
        end
    end)
    local headerRow = Umg.Construct("/Script/UMG.HorizontalBox", headerBtn, namePrefix .. "_HeaderRow")

    local valueLabel = Umg.Construct("/Script/UMG.TextBlock", headerRow, namePrefix .. "_Value")
    Umg.StyleText(valueLabel, fontDropdown, colors.dropdownHeaderText)
    Umg.SetLabelText(valueLabel, tostring(selectedLabel))
    local valueSlot = headerRow:AddChildToHorizontalBox(valueLabel)
    pcall(function()
        valueSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        valueSlot:SetPadding({ Left = 10, Top = 8, Right = 6, Bottom = 8 })
        valueSlot:SetVerticalAlignment(2)
    end)

    local arrowLabel = Umg.Construct("/Script/UMG.TextBlock", headerRow, namePrefix .. "_Arrow")
    Umg.StyleText(arrowLabel, fontDropdown, colors.dropdownHeaderText)
    Umg.SetLabelText(arrowLabel, "▼")
    local arrowSlot = headerRow:AddChildToHorizontalBox(arrowLabel)
    pcall(function()
        arrowSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        arrowSlot:SetPadding({ Left = 4, Top = 8, Right = 10, Bottom = 8 })
        arrowSlot:SetVerticalAlignment(2)
    end)

    pcall(function()
        headerBtn:SetContent(headerRow)
    end)
    root:AddChildToVerticalBox(headerBtn)

    local optionsBox = Umg.Construct("/Script/UMG.VerticalBox", root, namePrefix .. "_Opts")
    pcall(function()
        optionsBox:SetVisibility(VIS_COLLAPSED)
    end)

    local searchBox = nil
    if searchable then
        local searchBorder = Umg.Construct("/Script/UMG.Border", optionsBox, namePrefix .. "_SearchBorder")
        pcall(function()
            searchBorder:SetBrushColor(colors.fieldBg)
            searchBorder:SetPadding({ Left = 8, Top = 6, Right = 8, Bottom = 6 })
        end)
        searchBox = Umg.Construct("/Script/UMG.EditableTextBox", searchBorder, namePrefix .. "_Search")
        pcall(function()
            searchBox:SetHintText(FText("Type to filter..."))
            searchBox:SetText(FText(""))
        end)
        Umg.StyleEditableTextBox(searchBox, fontDropdown)
        pcall(function()
            searchBorder:SetContent(searchBox)
        end)
        optionsBox:AddChildToVerticalBox(searchBorder)
        Umg.AddSpacer(optionsBox, namePrefix .. "_SearchPad", 6)
    end

    local sizeBox = Umg.Construct("/Script/UMG.SizeBox", optionsBox, namePrefix .. "_ListSize")
    pcall(function()
        sizeBox:SetMaxDesiredHeight(listMaxHeight)
    end)
    local scrollBox = Umg.Construct("/Script/UMG.ScrollBox", sizeBox, namePrefix .. "_Scroll")
    pcall(function()
        sizeBox:SetContent(scrollBox)
    end)

    local listBox = Umg.Construct("/Script/UMG.VerticalBox", scrollBox, namePrefix .. "_List")
    pcall(function()
        scrollBox:AddChild(listBox)
    end)
    Umg.StyleScrollBox(scrollBox, config)
    optionsBox:AddChildToVerticalBox(sizeBox)

    local moreLabel = nil
    if searchable then
        moreLabel = Umg.Construct("/Script/UMG.TextBlock", optionsBox, namePrefix .. "_More")
        Umg.StyleText(moreLabel, fontHint, colors.dropdownMore)
        Umg.SetLabelText(moreLabel, "")
        pcall(function()
            moreLabel:SetVisibility(VIS_COLLAPSED)
        end)
        optionsBox:AddChildToVerticalBox(moreLabel)
    end

    root:AddChildToVerticalBox(optionsBox)

    local picker = {
        namePrefix = namePrefix,
        list = list,
        labelToValue = labelToValue,
        valueToLabel = valueToLabel,
        selectedValue = selectedValue,
        selectedLabel = selectedLabel,
        placeholder = placeholder,
        searchable = searchable,
        maxVisible = maxVisible,
        fontDropdown = fontDropdown,
        searchFilter = "",
        searchBox = searchBox,
        scrollBox = scrollBox,
        listBox = listBox,
        moreLabel = moreLabel,
        headerBtn = headerBtn,
        headerLabel = valueLabel,
        arrowLabel = arrowLabel,
        optionsBox = optionsBox,
        optionRows = {},
        optionBg = colors.dropdownOptionBg,
        optionText = colors.dropdownOptionText,
        optionSelectedBg = colors.buttonBgActive,
        optionSelectedText = colors.buttonTextActive,
        expanded = false,
        headerWasPressed = false,
    }

    -- Option buttons spawn on first expand, not at menu build.
    return root, picker
end

function Dropdown.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if type(item.options) ~= "table" or #item.options == 0 then
        error(prefix .. " dropdown requires non-empty .options array")
    end
    local ok, err = pcall(Options.NormalizeOptions, item.options)
    if not ok then
        error(prefix .. " " .. tostring(err))
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
    if item.maxVisible ~= nil and (type(item.maxVisible) ~= "number" or item.maxVisible < 1) then
        error(prefix .. " maxVisible must be a positive number")
    end
end

function Dropdown.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    if values[vkey] == nil and item.default ~= nil then
        values[vkey] = item.default
    end
end

function Dropdown.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = ctx.values[vkey]
    if current == nil then
        current = item.default
    end

    local caption = umg.Construct("/Script/UMG.TextBlock", ctx.contentBox, ctx.namePrefix .. "_Cap")
    umg.StyleText(caption, ctx.config.fontHint)
    umg.SetLabelText(caption, item.label)
    ctx.contentBox:AddChildToVerticalBox(caption)

    local root, picker = CreatePicker(ctx.contentBox, ctx.namePrefix, item.options, current, {
        searchable = item.searchable == true,
        placeholder = item.placeholder,
        maxVisible = item.maxVisible,
        listMaxHeight = item.listMaxHeight,
        allowEmpty = item.allowEmpty,
    }, ctx.config)

    ctx.values[vkey] = picker.selectedValue
    ctx.contentBox:AddChildToVerticalBox(root)
    umg.AddSpacer(ctx.contentBox, ctx.namePrefix .. "_Pad", 8)

    table.insert(ctx.liveControls, Dropdown.liveControl(picker, {
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        valueKey = vkey,
    }))
end

--- Shell chrome (dock picker) and Register dropdowns share this control shape.
function Dropdown.liveControl(picker, extra)
    local ctrl = {
        kind = "dropdown",
        namePrefix = picker.namePrefix,
        list = picker.list,
        labelToValue = picker.labelToValue,
        valueToLabel = picker.valueToLabel,
        selectedLabel = picker.selectedLabel,
        selectedValue = picker.selectedValue,
        placeholder = picker.placeholder,
        searchable = picker.searchable,
        maxVisible = picker.maxVisible,
        fontDropdown = picker.fontDropdown,
        searchFilter = picker.searchFilter,
        searchBox = picker.searchBox,
        scrollBox = picker.scrollBox,
        listBox = picker.listBox,
        moreLabel = picker.moreLabel,
        headerBtn = picker.headerBtn,
        headerLabel = picker.headerLabel,
        arrowLabel = picker.arrowLabel,
        optionsBox = picker.optionsBox,
        optionRows = picker.optionRows,
        optionBg = picker.optionBg,
        optionText = picker.optionText,
        optionSelectedBg = picker.optionSelectedBg,
        optionSelectedText = picker.optionSelectedText,
        expanded = false,
        headerWasPressed = false,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            ctrl[key] = value
        end
    end
    return ctrl
end

---@param path string
local function SelectOption(ctrl, ctx, row, path)
    Input.DebugClick(path, ctrl, row.button)
    local value = row.optValue
    ctrl.selectedValue = value
    ctrl.selectedLabel = tostring(row.optLabel or value)
    ctx.values[ctrl.valueKey] = value
    SetExpanded(ctrl, false)
    Input.SuppressPressEdge(row)
    Input.SuppressPressEdge(ctrl, "headerWasPressed")
    Input.IgnoreClicks(2)
    ctx.SafeCall(ctrl.item.onChange, value)
    ctx.ReclaimMenuInput()
    ctx.EnsureMenuVisible()
end

---@param path string
local function ToggleHeader(ctrl, ctx, path)
    if Input.WidgetHovered(ctrl.searchBox) then
        return false
    end
    Input.DebugClick(path, ctrl, ctrl.headerBtn)
    local nextExpanded = not ctrl.expanded
    if nextExpanded then
        Dropdown.collapseAll(ctx.liveControls, ctrl)
    end
    SetExpanded(ctrl, nextExpanded)
    if nextExpanded then
        ctx.SafeCall(ctrl.item.onExpand, ctrl.list)
    end
    Input.SuppressPressEdge(ctrl, "headerWasPressed")
    Input.IgnoreClicks(2)
    return true
end

--- Filter text poll while expanded + native UButton press (no LMB latch).
function Dropdown.poll(ctrl, ctx)
    if ctrl.searchable and ctrl.expanded and ctrl.searchBox ~= nil then
        local text = Options.GetWidgetPlainText(ctrl.searchBox)
        if text ~= ctrl.searchFilter then
            ctrl.searchFilter = text
            RebuildRows(ctrl)
        end
    end

    if ctrl.expanded and ctrl.optionRows then
        for _, row in ipairs(ctrl.optionRows) do
            if Input.WidgetPressedEdge(row, row.button) then
                SelectOption(ctrl, ctx, row, "press-edge")
                return
            end
        end
    end
    if Input.WidgetPressedEdge(ctrl, ctrl.headerBtn, "headerWasPressed") then
        ToggleHeader(ctrl, ctx, "press-edge")
    end
end

--- Option-row click (priority over header). Returns true if consumed.
function Dropdown.pollOptionClick(ctrl, ctx)
    if not ctrl.expanded or not ctrl.optionRows then
        return false
    end
    for _, row in ipairs(ctrl.optionRows) do
        if Input.WidgetHovered(row.button) then
            SelectOption(ctrl, ctx, row, "latch-hover")
            return true
        end
    end
    return false
end

--- Header toggle click. Returns true if consumed.
function Dropdown.pollHeaderClick(ctrl, ctx)
    if not (Input.WidgetHovered(ctrl.headerBtn) or Input.WidgetHovered(ctrl.headerLabel)) then
        return false
    end
    return ToggleHeader(ctrl, ctx, "latch-hover")
end

--- LMB latch: option rows first, then header.
function Dropdown.pollClick(ctrl, ctx)
    if Dropdown.pollOptionClick(ctrl, ctx) then
        return true
    end
    return Dropdown.pollHeaderClick(ctrl, ctx)
end

function Dropdown.apply(ctrl, value, _ctx)
    if value == nil then
        ctrl.selectedValue = nil
        ctrl.selectedLabel = ctrl.placeholder or "Select..."
    else
        local label = ctrl.valueToLabel and ctrl.valueToLabel[value] or tostring(value)
        ctrl.selectedValue = value
        ctrl.selectedLabel = tostring(label)
    end
    SyncHeader(ctrl)
end

--- In-place searchable list refresh (SetOptions path).
function Dropdown.refreshLive(ctrl, list, selectedValue, values, vkey)
    local normalized, labelToValue, valueToLabel = Options.NormalizeOptions(list)
    ctrl.list = normalized
    ctrl.labelToValue = labelToValue
    ctrl.valueToLabel = valueToLabel
    if selectedValue == false then
        ctrl.selectedValue = nil
        ctrl.selectedLabel = ctrl.placeholder or "Select..."
    elseif selectedValue ~= nil then
        local plain = Util.ToPlainString(selectedValue) or selectedValue
        ctrl.selectedValue = plain
        ctrl.selectedLabel = valueToLabel[plain] or tostring(plain)
    elseif ctrl.selectedValue ~= nil and valueToLabel[ctrl.selectedValue] == nil then
        ctrl.selectedValue = nil
        ctrl.selectedLabel = ctrl.placeholder or "Select..."
        values[vkey] = nil
    elseif ctrl.selectedValue ~= nil then
        ctrl.selectedLabel = valueToLabel[ctrl.selectedValue] or ctrl.selectedLabel
    end
    ctrl.searchFilter = ""
    pcall(function()
        if ctrl.searchBox ~= nil then
            ctrl.searchBox:SetText(FText(""))
        end
    end)
    if ctrl.expanded then
        RebuildRows(ctrl)
    end
    SyncHeader(ctrl)
end

function Dropdown.createPicker(outer, namePrefix, options, selectedValue, dropOpts, config)
    return CreatePicker(outer, namePrefix, options, selectedValue, dropOpts, config)
end

function Dropdown.nextRowSerial()
    dropdownRowSerial = dropdownRowSerial + 1
    return dropdownRowSerial
end

return Dropdown
end

-- widgets/fold.lua
package.preload["ModMenu.widgets.fold"] = function(...)
--[[
  ModMenu widget: fold (nested collapsible group inside a section).

  Body is always built; toggle only SetVisibility. Same idea as section
  collapse so a still-down click cannot rebuild the header.
]]

local Umg = require("ModMenu.core.umg")
local Input = require("ModMenu.core.input")
local Session = require("ModMenu.shell.session")
local Theme = require("ModMenu.core.theme")

local Widgets ---@type table|nil

local Fold = {}
Fold.type = "fold"

local VIS_VISIBLE = Session.VIS_VISIBLE
local VIS_COLLAPSED = Session.VIS_COLLAPSED

local MARK_COLLAPSED = "+"
local MARK_EXPANDED = "-"

local ALLOWED = {
    button = true,
    checkbox = true,
    dropdown = true,
    label = true,
    number = true,
    row = true,
    separator = true,
    textinput = true,
}

local function Registry()
    if Widgets == nil then
        Widgets = require("ModMenu.widgets.init")
    end
    return Widgets
end

local function Mark(collapsed)
    if collapsed then
        return MARK_COLLAPSED
    end
    return MARK_EXPANDED
end

local function SetBodyVisible(ctrl, collapsed)
    ctrl.collapsed = collapsed and true or false
    pcall(function()
        if ctrl.body ~= nil then
            ctrl.body:SetVisibility(ctrl.collapsed and VIS_COLLAPSED or VIS_VISIBLE)
        end
    end)
    if ctrl.mark ~= nil then
        Umg.SetLabelText(ctrl.mark, Mark(ctrl.collapsed))
    end
end

function Fold.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " fold requires .id")
    end
    if item.label == nil then
        error(prefix .. " fold requires .label")
    end
    if type(item.items) ~= "table" or #item.items == 0 then
        error(prefix .. " fold requires non-empty .items array")
    end
    if item.collapsed ~= nil and type(item.collapsed) ~= "boolean" then
        error(prefix .. " collapsed must be a boolean")
    end
    local reg = Registry()
    for i, child in ipairs(item.items) do
        local childPrefix = string.format("%s.items[%d]", prefix, i)
        if type(child) ~= "table" then
            error(childPrefix .. " must be a table")
        end
        local t = child.type
        if not ALLOWED[t] then
            error(childPrefix .. " unsupported fold child type '" .. tostring(t) .. "'")
        end
        local widget = reg.get(t)
        if not widget then
            error(childPrefix .. " unknown type '" .. tostring(t) .. "'")
        end
        if widget.validate then
            widget.validate(child, sectionId, i)
        end
    end
end

function Fold.seed(sectionId, item, values)
    local reg = Registry()
    for _, child in ipairs(item.items or {}) do
        local widget = reg.get(child.type)
        if widget and widget.seed then
            widget.seed(sectionId, child, values)
        end
    end
end

function Fold.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local collapsed = item.collapsed ~= false
    local foldKey = ctx.ValueKey(ctx.section.id, item.id)
    local foldMap = ctx.foldCollapsedByKey
    if type(foldMap) == "table" then
        if foldMap[foldKey] == nil then
            foldMap[foldKey] = collapsed
        end
        collapsed = foldMap[foldKey] == true
    end
    local colors = Theme.Of(ctx.config)
    local fontSize = ctx.config.fontHint or ctx.config.fontSection or 14
    local namePrefix = ctx.namePrefix

    local headerBtn = umg.Construct("/Script/UMG.Button", ctx.contentBox, namePrefix .. "_Hdr")
    pcall(function()
        headerBtn:SetBackgroundColor(colors.sectionHeaderBg)
        if headerBtn.SetClickMethod then
            headerBtn:SetClickMethod(1)
        end
        if headerBtn.SetTouchMethod then
            headerBtn:SetTouchMethod(1)
        end
    end)

    local headerRow = umg.Construct("/Script/UMG.HorizontalBox", headerBtn, namePrefix .. "_HdrRow")
    local title = umg.Construct("/Script/UMG.TextBlock", headerRow, namePrefix .. "_Title")
    umg.StyleText(title, fontSize, colors.textPrimary)
    umg.SetLabelText(title, tostring(item.label))
    local titleSlot = headerRow:AddChildToHorizontalBox(title)
    pcall(function()
        titleSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        titleSlot:SetPadding({ Left = 10, Top = 4, Right = 8, Bottom = 4 })
        titleSlot:SetVerticalAlignment(2)
    end)

    local mark = umg.Construct("/Script/UMG.TextBlock", headerRow, namePrefix .. "_Mark")
    umg.StyleText(mark, fontSize, colors.sectionMark)
    umg.SetLabelText(mark, Mark(collapsed))
    local markSlot = headerRow:AddChildToHorizontalBox(mark)
    pcall(function()
        markSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        markSlot:SetPadding({ Left = 4, Top = 4, Right = 10, Bottom = 4 })
        markSlot:SetVerticalAlignment(2)
    end)

    pcall(function()
        headerBtn:SetContent(headerRow)
    end)
    umg.AddToContent(ctx, headerBtn, { fillVertical = true })

    local body = umg.Construct("/Script/UMG.VerticalBox", ctx.contentBox, namePrefix .. "_Body")
    umg.AddToContent(ctx, body)
    pcall(function()
        body:SetVisibility(collapsed and VIS_COLLAPSED or VIS_VISIBLE)
    end)

    local savedBox = ctx.contentBox
    local savedItem = ctx.item
    local savedPrefix = ctx.namePrefix
    local savedLayout = ctx.layout
    ctx.contentBox = body
    ctx.layout = nil

    local reg = Registry()
    for i, child in ipairs(item.items) do
        local widget = reg.get(child.type)
        if not widget or not widget.build then
            error("fold.build: no builder for type " .. tostring(child.type))
        end
        ctx.item = child
        ctx.namePrefix = string.format("%s_f%d_%s", savedPrefix, i, tostring(child.id or child.type))
        widget.build(ctx)
    end

    ctx.contentBox = savedBox
    ctx.item = savedItem
    ctx.namePrefix = savedPrefix
    ctx.layout = savedLayout
    umg.AddItemPad(ctx, namePrefix .. "_Pad", 8)

    table.insert(ctx.liveControls, {
        kind = "fold",
        sectionId = ctx.section.id,
        item = item,
        widget = headerBtn,
        mark = mark,
        body = body,
        collapsed = collapsed,
        wasPressed = false,
    })
end

local function Toggle(ctrl, ctx)
    SetBodyVisible(ctrl, not ctrl.collapsed)
    local foldMap = ctx.foldCollapsedByKey
    if type(foldMap) == "table" and ctrl.item and ctrl.item.id ~= nil then
        foldMap[ctx.ValueKey(ctrl.sectionId, ctrl.item.id)] = ctrl.collapsed
    end
    Input.SuppressPressEdge(ctrl)
    Input.IgnoreClicks(2)
    ctx.ReclaimMenuInput()
end

function Fold.poll(ctrl, ctx)
    if ctx.Input.WidgetPressedEdge(ctrl, ctrl.widget) then
        ctx.Input.DebugClick("press-edge", ctrl, ctrl.widget)
        Toggle(ctrl, ctx)
    end
end

function Fold.pollClick(ctrl, ctx)
    if not ctx.Input.WidgetHovered(ctrl.widget) then
        return false
    end
    ctx.Input.DebugClick("latch-hover", ctrl, ctrl.widget)
    Toggle(ctrl, ctx)
    return true
end

return Fold
end

-- widgets/label.lua
package.preload["ModMenu.widgets.label"] = function(...)
--[[
  ModMenu widget: label
]]

local Label = {}
Label.type = "label"

function Label.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.label == nil then
        error(prefix .. " label requires .label")
    end
end

function Label.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local label = umg.Construct("/Script/UMG.TextBlock", ctx.contentBox, ctx.namePrefix)
    umg.StyleText(label, ctx.config.fontHint)
    umg.SetLabelText(label, item.label)
    if ctx.layout ~= "horizontal" then
        umg.EnableAutoWrap(label)
    end
    umg.AddToContent(ctx, label)
    local pad = umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 6)
    local ctrl = {
        kind = "label",
        sectionId = ctx.section.id,
        item = item,
        widget = label,
        pad = pad,
        valueKey = item.id and ctx.ValueKey(ctx.section.id, item.id) or nil,
    }
    Label.apply(ctrl, item.label, ctx)
    if item.id then
        table.insert(ctx.liveControls, ctrl)
    end
end

function Label.apply(ctrl, text, ctx)
    local VIS_VISIBLE = 0
    local VIS_COLLAPSED = 1
    local s = tostring(text or "")
    if ctrl.widget ~= nil then
        ctx.umg.SetLabelText(ctrl.widget, s)
    end
    local empty = s:match("^%s*$") ~= nil
    local vis = empty and VIS_COLLAPSED or VIS_VISIBLE
    pcall(function()
        if ctrl.widget ~= nil then
            ctrl.widget:SetVisibility(vis)
        end
        if ctrl.pad ~= nil then
            ctrl.pad:SetVisibility(vis)
        end
    end)
end

return Label
end

-- widgets/number.lua
package.preload["ModMenu.widgets.number"] = function(...)
--[[
  ModMenu widget: number (labeled EditableTextBox, parsed/clamped numeric value)
]]

local Options = require("ModMenu.core.options")
local Util = require("ModMenu.core.util")

local Number = {}
Number.type = "number"

local function Prefix(sectionId, index)
    return string.format("Register(%s) items[%d]", tostring(sectionId), index)
end

local function CoerceDefault(item)
    local n = tonumber(item.default)
    if n == nil then
        n = 0
    end
    if item.integer then
        n = math.floor(n + (n >= 0 and 0.5 or -0.5))
    end
    if item.min ~= nil and n < item.min then
        n = item.min
    end
    if item.max ~= nil and n > item.max then
        n = item.max
    end
    return n
end

local function FormatValue(n, integer)
    if integer then
        return tostring(math.floor(n + (n >= 0 and 0.5 or -0.5)))
    end
    -- Trim trailing zeros from floats for cleaner fields.
    local s = string.format("%.6f", n)
    s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return s
end

local function ParseText(text, item)
    if text == nil then
        return nil
    end
    local trimmed = tostring(text):match("^%s*(.-)%s*$")
    if trimmed == nil or trimmed == "" or trimmed == "-" or trimmed == "." or trimmed == "-." then
        return nil
    end
    local n = tonumber(trimmed)
    if n == nil then
        return nil
    end
    if item.integer then
        n = math.floor(n + (n >= 0 and 0.5 or -0.5))
    end
    -- Below min: treat as incomplete so typing "10" with min=10 is not forced to 10 on "1".
    if item.min ~= nil and n < item.min then
        return nil
    end
    if item.max ~= nil and n > item.max then
        n = item.max
    end
    return n
end

function Number.validate(item, sectionId, index)
    local prefix = Prefix(sectionId, index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
    if item.min ~= nil and type(item.min) ~= "number" then
        error(prefix .. " min must be a number")
    end
    if item.max ~= nil and type(item.max) ~= "number" then
        error(prefix .. " max must be a number")
    end
    if item.min ~= nil and item.max ~= nil and item.min > item.max then
        error(prefix .. " min must be <= max")
    end
    if item.default ~= nil and tonumber(item.default) == nil then
        error(prefix .. " default must be numeric")
    end
    if item.fieldWidth ~= nil and (type(item.fieldWidth) ~= "number" or item.fieldWidth < 1) then
        error(prefix .. " fieldWidth must be a positive number")
    end
    if item.labelWidth ~= nil and (type(item.labelWidth) ~= "number" or item.labelWidth < 1) then
        error(prefix .. " labelWidth must be a positive number")
    end
    Util.ValidateDebounceMs(item, prefix)
end

function Number.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    if values[vkey] == nil then
        values[vkey] = CoerceDefault(item)
    end
end

function Number.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = ctx.values[vkey]
    if current == nil or tonumber(current) == nil then
        current = CoerceDefault(item)
        ctx.values[vkey] = current
    end

    local fillField = ctx.layout ~= "horizontal" and item.fill ~= false
    local root, edit, label = umg.CreateLabeledEditable(
        ctx.contentBox,
        ctx.namePrefix,
        item.label,
        FormatValue(current, item.integer == true),
        {
            fontSize = ctx.config.fontItem,
            fieldWidth = item.fieldWidth or (ctx.layout == "horizontal" and 72 or 96),
            labelWidth = item.labelWidth,
            hint = item.placeholder,
            fillField = fillField,
        }
    )
    umg.AddToContent(ctx, root, {
        fill = ctx.layout == "horizontal" and item.fill == true,
    })
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)

    table.insert(ctx.liveControls, {
        kind = "number",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        edit = edit,
        label = label,
        valueKey = vkey,
        lastText = FormatValue(current, item.integer == true),
        lastFiredOnChange = current,
        debounceMs = Util.ResolveDebounceMs(item, Util.DEFAULT_INPUT_DEBOUNCE_MS),
    })
end

--- Poll typed text; update store when a valid number is parsed.
--- Get/store update immediately; onChange is debounced (default 250ms).
--- Do not reclaim input here — that steals focus from the EditableTextBox.
function Number.poll(ctrl, ctx)
    if ctrl.edit == nil then
        return
    end
    local text = Options.GetWidgetPlainText(ctrl.edit)
    if text ~= ctrl.lastText then
        ctrl.lastText = text
        local n = ParseText(text, ctrl.item)
        if n ~= nil and n ~= ctx.values[ctrl.valueKey] then
            ctx.values[ctrl.valueKey] = n
            Util.ScheduleDebouncedOnChange(ctrl, ctrl.debounceMs)
        end
    end
    Util.FlushDebouncedOnChange(ctrl, ctx)
end

function Number.apply(ctrl, value, ctx)
    if ctrl.edit == nil then
        return
    end
    local n = tonumber(value)
    if n == nil then
        return
    end
    if ctrl.item.integer then
        n = math.floor(n + (n >= 0 and 0.5 or -0.5))
    end
    if ctrl.item.min ~= nil and n < ctrl.item.min then
        n = ctrl.item.min
    end
    if ctrl.item.max ~= nil and n > ctrl.item.max then
        n = ctrl.item.max
    end
    local text = FormatValue(n, ctrl.item.integer == true)
    pcall(function()
        ctrl.edit:SetText(FText(text))
    end)
    ctrl.lastText = text
    ctx.values[ctrl.valueKey] = n
    Util.ClearDebouncedOnChange(ctrl, n)
end

return Number
end

-- widgets/row.lua
package.preload["ModMenu.widgets.row"] = function(...)
--[[
  ModMenu widget: row (horizontal group of child items)

  Children share one HorizontalBox. Supported child types:
    button | checkbox | label | number | textinput
  Nested row / dropdown / separator are rejected at validate time.
]]

local Widgets ---@type table|nil delayed require to avoid init cycle

local Row = {}
Row.type = "row"

local ALLOWED = {
    button = true,
    checkbox = true,
    label = true,
    number = true,
    textinput = true,
}

local function Registry()
    if Widgets == nil then
        Widgets = require("ModMenu.widgets.init")
    end
    return Widgets
end

local function Prefix(sectionId, index)
    return string.format("Register(%s) items[%d]", tostring(sectionId), index)
end

function Row.validate(item, sectionId, index)
    local prefix = Prefix(sectionId, index)
    if type(item.items) ~= "table" or #item.items == 0 then
        error(prefix .. " row requires non-empty .items array")
    end
    local reg = Registry()
    for i, child in ipairs(item.items) do
        local childPrefix = string.format("%s.items[%d]", prefix, i)
        if type(child) ~= "table" then
            error(childPrefix .. " must be a table")
        end
        local t = child.type
        if not ALLOWED[t] then
            error(childPrefix .. " unsupported row child type '" .. tostring(t)
                .. "' (button|checkbox|label|number|textinput)")
        end
        local widget = reg.get(t)
        if not widget then
            error(childPrefix .. " unknown type '" .. tostring(t) .. "'")
        end
        if widget.validate then
            widget.validate(child, sectionId, i)
        end
    end
end

function Row.seed(sectionId, item, values)
    local reg = Registry()
    for _, child in ipairs(item.items or {}) do
        local widget = reg.get(child.type)
        if widget and widget.seed then
            widget.seed(sectionId, child, values)
        end
    end
end

function Row.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local reg = Registry()

    local rowBox = umg.Construct("/Script/UMG.HorizontalBox", ctx.contentBox, ctx.namePrefix .. "_H")
    -- Attach row to the parent (usually the section VerticalBox).
    local parentLayout = ctx.layout
    ctx.layout = nil
    umg.AddToContent(ctx, rowBox, { fillVertical = false })
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)

    local savedBox = ctx.contentBox
    local savedItem = ctx.item
    local savedPrefix = ctx.namePrefix
    ctx.contentBox = rowBox
    ctx.layout = "horizontal"

    for i, child in ipairs(item.items) do
        local widget = reg.get(child.type)
        if not widget or not widget.build then
            error("row.build: no builder for type " .. tostring(child.type))
        end
        ctx.item = child
        ctx.namePrefix = string.format("%s_c%d_%s", savedPrefix, i, tostring(child.id or child.type))
        widget.build(ctx)
    end

    ctx.contentBox = savedBox
    ctx.item = savedItem
    ctx.namePrefix = savedPrefix
    ctx.layout = parentLayout
end

return Row
end

-- widgets/separator.lua
package.preload["ModMenu.widgets.separator"] = function(...)
--[[
  ModMenu widget: separator
]]

local Separator = {}
Separator.type = "separator"

function Separator.validate(_item, _sectionId, _index)
    -- no fields required
end

function Separator.build(ctx)
    ctx.umg.AddSpacer(ctx.contentBox, ctx.namePrefix .. "_Sep", 14)
end

return Separator
end

-- widgets/textinput.lua
package.preload["ModMenu.widgets.textinput"] = function(...)
--[[
  ModMenu widget: textinput (labeled EditableTextBox, string value)
]]

local Options = require("ModMenu.core.options")
local Util = require("ModMenu.core.util")

local TextInput = {}
TextInput.type = "textinput"

local function Prefix(sectionId, index)
    return string.format("Register(%s) items[%d]", tostring(sectionId), index)
end

function TextInput.validate(item, sectionId, index)
    local prefix = Prefix(sectionId, index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
    if item.fieldWidth ~= nil and (type(item.fieldWidth) ~= "number" or item.fieldWidth < 1) then
        error(prefix .. " fieldWidth must be a positive number")
    end
    if item.labelWidth ~= nil and (type(item.labelWidth) ~= "number" or item.labelWidth < 1) then
        error(prefix .. " labelWidth must be a positive number")
    end
    if item.maxLength ~= nil and (type(item.maxLength) ~= "number" or item.maxLength < 1) then
        error(prefix .. " maxLength must be a positive number")
    end
    Util.ValidateDebounceMs(item, prefix)
end

function TextInput.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    if values[vkey] == nil then
        values[vkey] = item.default ~= nil and tostring(item.default) or ""
    end
end

function TextInput.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = ctx.values[vkey]
    if current == nil then
        current = item.default ~= nil and tostring(item.default) or ""
        ctx.values[vkey] = current
    else
        current = tostring(current)
    end

    local fillField = ctx.layout ~= "horizontal" and item.fill ~= false
    local root, edit, label = umg.CreateLabeledEditable(
        ctx.contentBox,
        ctx.namePrefix,
        item.label,
        current,
        {
            fontSize = ctx.config.fontItem,
            fieldWidth = item.fieldWidth or (ctx.layout == "horizontal" and 140 or 200),
            labelWidth = item.labelWidth,
            hint = item.placeholder,
            fillField = fillField,
        }
    )
    umg.AddToContent(ctx, root, {
        fill = ctx.layout == "horizontal" and (item.fill ~= false),
    })
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)

    table.insert(ctx.liveControls, {
        kind = "textinput",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        edit = edit,
        label = label,
        valueKey = vkey,
        lastText = current,
        lastFiredOnChange = current,
        debounceMs = Util.ResolveDebounceMs(item, Util.DEFAULT_INPUT_DEBOUNCE_MS),
    })
end

--- Do not reclaim input here — that steals focus from the EditableTextBox.
--- Get/store update immediately; onChange is debounced (default 250ms).
function TextInput.poll(ctrl, ctx)
    if ctrl.edit == nil then
        return
    end
    local text = Options.GetWidgetPlainText(ctrl.edit)
    if ctrl.item.maxLength ~= nil and #text > ctrl.item.maxLength then
        text = string.sub(text, 1, ctrl.item.maxLength)
        pcall(function()
            ctrl.edit:SetText(FText(text))
        end)
    end
    if text ~= ctrl.lastText then
        ctrl.lastText = text
        if text ~= ctx.values[ctrl.valueKey] then
            ctx.values[ctrl.valueKey] = text
            Util.ScheduleDebouncedOnChange(ctrl, ctrl.debounceMs)
        end
    end
    Util.FlushDebouncedOnChange(ctrl, ctx)
end

function TextInput.apply(ctrl, value, ctx)
    if ctrl.edit == nil then
        return
    end
    local text = value ~= nil and tostring(value) or ""
    if ctrl.item.maxLength ~= nil and #text > ctrl.item.maxLength then
        text = string.sub(text, 1, ctrl.item.maxLength)
    end
    pcall(function()
        ctrl.edit:SetText(FText(text))
    end)
    ctrl.lastText = text
    ctx.values[ctrl.valueKey] = text
    Util.ClearDebouncedOnChange(ctrl, text)
end

return TextInput
end

-- widgets/init.lua
package.preload["ModMenu.widgets.init"] = function(...)
--[[
  ModMenu widget registry.

  Add a new type:
    1. Create widgets/<type>.lua exporting { type, validate?, seed?, build, poll?, pollClick?, apply? }
    2. register(require("ModMenu.widgets.<type>")) below
    3. Document fields in README

  widgets/*.lua are auto-bundled; core/ and shell/ still need a MODULES row
  in tools/bundle.mjs.

  ctx fields (build / poll / pollClick / apply):
    values, liveControls, config, umg, Input, ValueKey, SafeCall, IsValid,
    ReclaimMenuInput, EnsureMenuVisible, contentBox, section, item, namePrefix,
    layout (nil or "horizontal" inside a row)
]]

local registry = {} ---@type table<string, table>
local order = {} ---@type string[]

local function register(mod)
    if type(mod) ~= "table" or type(mod.type) ~= "string" then
        error("widgets.init: register() expects a module with .type")
    end
    if registry[mod.type] == nil then
        table.insert(order, mod.type)
    end
    registry[mod.type] = mod
end

register(require("ModMenu.widgets.separator"))
register(require("ModMenu.widgets.label"))
register(require("ModMenu.widgets.button"))
register(require("ModMenu.widgets.checkbox"))
register(require("ModMenu.widgets.dropdown"))
register(require("ModMenu.widgets.number"))
register(require("ModMenu.widgets.textinput"))
register(require("ModMenu.widgets.row"))
register(require("ModMenu.widgets.fold"))

local M = {}

function M.get(typeName)
    return registry[typeName]
end

function M.has(typeName)
    return registry[typeName] ~= nil
end

--- @return string comma-separated type names for error messages
function M.typeList()
    return table.concat(order, "|")
end

return M
end

-- shell/session.lua
package.preload["ModMenu.shell.session"] = function(...)
--[[
  ModMenu.shell.session — mutable per-Lua-state shell fields shared by dock/build/lifecycle.
]]

local Util = require("ModMenu.core.util")

local M = {}

M.VIS_VISIBLE = 0
M.VIS_COLLAPSED = 1
M.POLL_MS = 16

---@param opts { config: table, sections: table, values: table, onOpenCallbacks: table, onDockCallbacks?: table }
function M.New(opts)
    return {
        config = opts.config,
        sections = opts.sections,
        sectionIndexById = {},
        values = opts.values,
        onOpenCallbacks = opts.onOpenCallbacks,
        onCloseCallbacks = opts.onCloseCallbacks or {},
        onDockCallbacks = opts.onDockCallbacks or {},
        menuRoot = nil,
        contentBox = nil,
        menuScroll = nil, ---@type any panel ScrollBox (reset to top after dock change)
        panelSlot = nil,
        panelBorder = nil, ---@type any fill Border
        panelOutline = nil, ---@type any 1px outline Border
        menuOpen = false,
        contentGen = 0,
        pollHandle = nil,
        pollFn = nil, ---@type function|nil strong ref for LoopInGameThreadWithDelay
        hooksInstalled = false,
        liveControls = {},
        contentDirty = false, --- rebuild on next Open after Register/SetOptions while closed
        collapsedById = {}, ---@type table<string, boolean>
        foldCollapsedByKey = {}, ---@type table<string, boolean> "sectionId.foldId"
        activeTab = nil, ---@type string|nil session-only; first Init tab when unset
        pendingTabId = nil, ---@type string|nil
        tabApplyQueue = {}, ---@type string[]
        tabApplyFn = nil, ---@type function|nil
        tabApplyScheduled = false,
        pendingCollapseId = nil, ---@type string|nil
        pendingCollapseSource = nil, ---@type string|nil
        collapseApplyQueue = {}, ---@type { id: string, source: string|nil }[]
        collapseApplyFn = nil, ---@type function|nil
        collapseApplyScheduled = false,
        menuCanvas = nil, ---@type any CanvasPanel (panel + confirm overlay)
        confirm = nil, ---@type table|nil active confirm spec
        confirmRoot = nil,
        confirmSlot = nil,
        confirmControls = nil,
        confirmGen = 0,
        makeWidgetCtx = nil, ---@type fun(): table
        -- Opt-in cursorMode = "modmenu" overlay (core/cursor.lua).
        cursorRoot = nil,
        cursorSlot = nil,
        cursorPollHandle = nil,
        cursorPollFn = nil, ---@type function|nil strong ref for LoopInGameThreadWithDelay
        cursorShowFn = nil, ---@type function|nil
        cursorShowHandle = nil,
        clientRestartFn = nil, ---@type function|nil
        rebuildFn = nil, ---@type function|nil
        cursorHiddenWidgets = nil, ---@type { widget: any, vis: number|nil }[]|nil
        cursorScale = nil,
        cursorHotspotX = nil,
        cursorHotspotY = nil,
        cursorConfigSig = nil, ---@type string|nil last applied cursorMode|scale|hideClasses
    }
end

function M.ClearLive(S)
    local list = S.liveControls
    for i = #list, 1, -1 do
        list[i] = nil
    end
end

function M.EnsureVisible(S)
    if S.menuOpen and Util.IsValid(S.menuRoot) then
        pcall(function()
            S.menuRoot:SetVisibility(M.VIS_VISIBLE)
        end)
    end
end

function M.IsVisible(S)
    if not Util.IsValid(S.menuRoot) then
        return false
    end
    local ok, vis = pcall(function()
        return S.menuRoot:GetVisibility()
    end)
    return ok and vis == M.VIS_VISIBLE
end

return M
end

-- shell/dock.lua
package.preload["ModMenu.shell.dock"] = function(...)
--[[
  ModMenu.shell.dock — percent layout and dock chrome dropdown.

  Init({ dock }) is the author default. The header picker offers Left / Right /
  Top / Bottom for every host. Same rectangle, rotated 90° on top/bottom.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Config = require("ModMenu.core.config")
local DockMath = require("ModMenu.core.dockmath")
local Widgets = require("ModMenu.widgets.init")

local Dropdown = Widgets.get("dropdown")
local Debug = Util.Debug

-- Clockwise. Selection must not rotate this list.
local SIDES = {
    { label = "Top", value = "top" },
    { label = "Right", value = "right" },
    { label = "Bottom", value = "bottom" },
    { label = "Left", value = "left" },
}

local M = {}

M.PercentRect = DockMath.PercentRect

--- Percentage anchors. left/right unchanged; top/bottom is the same strip rotated 90°.
--- rightFrac = thickness-edge gap; widthFrac = thickness; topFrac/bottomFrac = long-axis margins.
function M.ApplyPercentLayout(slot, config)
    if slot == nil then
        return
    end
    local rect = DockMath.PercentRect(config)
    pcall(function()
        slot:SetAutoSize(false)
        slot:SetAnchors({
            Minimum = { X = rect.minX, Y = rect.minY },
            Maximum = { X = rect.maxX, Y = rect.maxY },
        })
        slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        slot:SetAlignment({ X = 0.0, Y = 0.0 })
    end)
end

function M.BuildChrome(S, contentBox, suffix)
    local config = S.config
    local caption = Umg.Construct("/Script/UMG.TextBlock", contentBox, "ModMenu_DockCap_" .. suffix)
    Umg.StyleText(caption, config.fontHint)
    Umg.SetLabelText(caption, "Dock")
    contentBox:AddChildToVerticalBox(caption)

    local root, picker = Dropdown.createPicker(
        contentBox,
        "ModMenu_Dock_" .. suffix,
        SIDES,
        config.dock,
        { maxVisible = 4 },
        config
    )
    contentBox:AddChildToVerticalBox(root)

    local dockPad = 8
    if config.pointerMode == "touch" then
        dockPad = 24
    end
    Umg.AddSpacer(contentBox, "ModMenu_DockPad_" .. suffix, dockPad)

    table.insert(S.liveControls, Dropdown.liveControl(picker, {
        role = "dock",
        widget = root,
        valueKey = "__modmenu.dock",
        item = {
            onChange = function(value)
                M.Set(S, value)
            end,
        },
    }))
end

function M.SyncChrome(S)
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "dropdown" and ctrl.role == "dock" then
            Dropdown.apply(ctrl, S.config.dock)
        end
    end
end

function M.Set(S, side)
    S.config.dock = Config.NormalizeDock(side)
    M.ApplyPercentLayout(S.panelSlot, S.config)
    M.SyncChrome(S)
    if S.menuScroll ~= nil then
        pcall(function()
            S.menuScroll:ScrollToStart()
        end)
    end
    Debug("Dock -> " .. S.config.dock)
    for _, fn in ipairs(S.onDockCallbacks or {}) do
        Util.SafeCall(fn, S.config.dock)
    end
end

return M
end

-- shell/close.lua
package.preload["ModMenu.shell.close"] = function(...)
--[[
  ModMenu.shell.close — title-row Close button. Same path as the toggle key.
]]

local Input = require("ModMenu.core.input")

local M = {}

local function Request(S, ctrl)
    Input.SuppressPressEdge(ctrl)
    Input.IgnoreClicks(2)
    S.pendingClose = true
end

function M.Poll(S, ctrl)
    if Input.WidgetPressedEdge(ctrl, ctrl.widget) then
        Input.DebugClick("press-edge", ctrl, ctrl.widget)
        Request(S, ctrl)
    end
end

---@return boolean
function M.PollClick(S, ctrl)
    if not Input.WidgetHovered(ctrl.widget) then
        return false
    end
    Input.DebugClick("latch-hover", ctrl, ctrl.widget)
    Request(S, ctrl)
    return true
end

return M
end

-- shell/collapse.lua
package.preload["ModMenu.shell.collapse"] = function(...)
--[[
  ModMenu.shell.collapse — collapsible section headers.

  Opt-in via Register({ collapsible = true, collapsed = true? }).
  Session remembers open/closed per section id (not saved to disk).

  Same pattern as dropdowns: keep the header widget, show/hide a body box.
  Do not rebuild the tree on toggle — that destroyed the header under a
  still-down click and caused an open/close flicker.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Theme = require("ModMenu.core.theme")
local Input = require("ModMenu.core.input")
local Session = require("ModMenu.shell.session")

local Debug = Util.Debug
local SafeCall = Util.SafeCall

-- Isolated on the right like a shadcn chevron. ASCII so game fonts stay valid.
local MARK_COLLAPSED = "+"
local MARK_EXPANDED = "-"

local M = {}

function M.IsCollapsible(section)
    return section ~= nil and section.collapsible == true
end

function M.IsCollapsed(S, section)
    if not M.IsCollapsible(section) then
        return false
    end
    return S.collapsedById[section.id] == true
end

--- Seed session state once. Re-Register keeps the player's current open/closed.
function M.Seed(S, section)
    if not M.IsCollapsible(section) then
        return
    end
    if S.collapsedById[section.id] == nil then
        S.collapsedById[section.id] = section.collapsed == true
    end
end

function M.Mark(collapsed)
    if collapsed then
        return MARK_COLLAPSED
    end
    return MARK_EXPANDED
end

function M.Validate(section)
    local id = tostring(section.id)
    if section.collapsible ~= nil and type(section.collapsible) ~= "boolean" then
        error("Register(" .. id .. ") collapsible must be a boolean")
    end
    if section.collapsed ~= nil and type(section.collapsed) ~= "boolean" then
        error("Register(" .. id .. ") collapsed must be a boolean")
    end
    if section.onToggle ~= nil and type(section.onToggle) ~= "function" then
        error("Register(" .. id .. ") onToggle must be a function")
    end
    if section.collapsed == true and section.collapsible ~= true then
        error("Register(" .. id .. ") collapsed=true requires collapsible=true")
    end
end

local function FindHeader(S, sectionId)
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "collapse" and ctrl.sectionId == sectionId then
            return ctrl
        end
    end
    return nil
end

local function SetBodyVisible(ctrl, collapsed)
    if ctrl == nil or ctrl.body == nil then
        return
    end
    pcall(function()
        ctrl.body:SetVisibility(collapsed and Session.VIS_COLLAPSED or Session.VIS_VISIBLE)
    end)
    if ctrl.mark ~= nil then
        Umg.SetLabelText(ctrl.mark, M.Mark(collapsed))
    end
end

--- Queue a toggle. Apply in Flush after the poll loop (dropdown-style: one
--- click must not both press-edge and latch).
function M.QueueToggle(S, sectionId, source)
    if S.pendingCollapseId ~= nil then
        Debug(string.format(
            "collapse queue skip id=%s via=%s (already pending id=%s via=%s)",
            tostring(sectionId),
            tostring(source),
            tostring(S.pendingCollapseId),
            tostring(S.pendingCollapseSource)
        ))
        return
    end
    S.pendingCollapseId = sectionId
    S.pendingCollapseSource = source
    Debug(string.format("collapse queue id=%s via=%s", tostring(sectionId), tostring(source)))
end

function M.Poll(S, ctrl)
    if Input.WidgetPressedEdge(ctrl, ctrl.widget) then
        Input.DebugClick("press-edge", ctrl, ctrl.widget)
        Input.SuppressPressEdge(ctrl)
        Input.IgnoreClicks(2)
        M.QueueToggle(S, ctrl.sectionId, "press")
    end
end

---@return boolean
function M.PollClick(S, ctrl)
    if not Input.WidgetHovered(ctrl.widget) then
        return false
    end
    Input.DebugClick("latch-hover", ctrl, ctrl.widget)
    Input.SuppressPressEdge(ctrl)
    Input.IgnoreClicks(2)
    M.QueueToggle(S, ctrl.sectionId, "latch")
    return true
end

function M.Apply(S, sectionId, source)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        Debug(string.format("collapse apply miss id=%s via=%s (no section)", tostring(sectionId), tostring(source)))
        return
    end
    local section = S.sections[idx]
    if not M.IsCollapsible(section) then
        return
    end

    local collapsed = not M.IsCollapsed(S, section)
    S.collapsedById[sectionId] = collapsed
    section.collapsed = collapsed

    local ctrl = FindHeader(S, sectionId)
    SetBodyVisible(ctrl, collapsed)
    if ctrl then
        Input.SuppressPressEdge(ctrl)
    end
    Input.IgnoreClicks(2)

    Debug(string.format(
        "collapse apply id=%s via=%s %s gen=%d header=%s",
        tostring(sectionId),
        tostring(source),
        collapsed and "close" or "open",
        S.contentGen or 0,
        ctrl ~= nil and "live" or "missing"
    ))
    SafeCall(section.onToggle, collapsed)
end

function M.Flush(S)
    local sectionId = S.pendingCollapseId
    if sectionId == nil then
        return
    end
    local source = S.pendingCollapseSource
    S.pendingCollapseId = nil
    S.pendingCollapseSource = nil
    -- Do not SetVisibility inside LoopInGameThreadWithDelay. Opening a large
    -- always-built body (Add, Give, …) hitches UMG on this EngineTick; UE4SS
    -- then fails get_function_ref on a delayed callback and removes the hook.
    table.insert(S.collapseApplyQueue, { id = sectionId, source = source })
    if S.collapseApplyFn == nil then
        S.collapseApplyFn = Util.PinFn(function()
            S.collapseApplyScheduled = false
            local queue = S.collapseApplyQueue
            S.collapseApplyQueue = {}
            for _, job in ipairs(queue) do
                M.Apply(S, job.id, job.source)
            end
        end)
    end
    if S.collapseApplyScheduled then
        return
    end
    S.collapseApplyScheduled = true
    ExecuteInGameThreadWithDelay(1, S.collapseApplyFn)
end

local function AddHeaderText(row, name, text, fontSize, color, fill)
    local block = Umg.Construct("/Script/UMG.TextBlock", row, name)
    Umg.StyleText(block, fontSize, color)
    Umg.SetLabelText(block, text)
    pcall(function()
        -- ETextJustify::Left / Right
        block:SetJustification(fill and 0 or 2)
    end)

    local host = block
    if not fill then
        local size = Umg.Construct("/Script/UMG.SizeBox", row, name .. "_Size")
        pcall(function()
            size:SetWidthOverride(18)
            size:SetContent(block)
        end)
        host = size
    end

    local slot = row:AddChildToHorizontalBox(host)
    pcall(function()
        if fill then
            slot:SetSize({ SizeRule = 1, Value = 1.0 })
            slot:SetHorizontalAlignment(0) -- Left
        else
            slot:SetSize({ SizeRule = 0, Value = 0.0 })
            slot:SetHorizontalAlignment(2) -- Right
        end
        slot:SetVerticalAlignment(2) -- Center
        slot:SetPadding({
            Left = fill and 10 or 4,
            Top = 4,
            Right = fill and 8 or 10,
            Bottom = 4,
        })
    end)
    return block
end

--- Accordion header: title left, + / - right, full-width click target.
--- Caller attaches a body VerticalBox and always builds children into it.
---@return table ctrl
function M.BuildHeader(S, section, contentBox, suffix)
    local collapsed = M.IsCollapsed(S, section)
    local name = string.format("ModMenu_SecHdr_%s_%s", section.id, suffix)
    local colors = Theme.Of(S.config)
    local fontSize = S.config.fontSection
    local titleText = tostring(section.title or section.id)

    local button = Umg.Construct("/Script/UMG.Button", contentBox, name .. "_Btn")
    local row = Umg.Construct("/Script/UMG.HorizontalBox", button, name .. "_Row")
    local title = AddHeaderText(row, name .. "_Title", titleText, fontSize, colors.textPrimary, true)
    local mark = AddHeaderText(row, name .. "_Mark", M.Mark(collapsed), fontSize, colors.sectionMark, false)

    pcall(function()
        button:SetContent(row)
        button:SetBackgroundColor(colors.sectionHeaderBg)
        if button.SetClickMethod then
            button:SetClickMethod(1) -- MouseDown; matches other constructed buttons
        end
    end)

    local slot = contentBox:AddChildToVerticalBox(button)
    Umg.FillVerticalSlot(slot)
    local ctrl = {
        kind = "collapse",
        sectionId = section.id,
        widget = button,
        label = title,
        mark = mark,
        body = nil,
        wasPressed = false,
    }
    table.insert(S.liveControls, ctrl)
    return ctrl
end

function M.AttachBody(ctrl, body, collapsed)
    if ctrl == nil or body == nil then
        return
    end
    ctrl.body = body
    SetBodyVisible(ctrl, collapsed)
end

return M
end

-- shell/tabs.lua
package.preload["ModMenu.shell.tabs"] = function(...)
--[[
  ModMenu.shell.tabs — optional top-level tab strip.

  Init({ tabs = { "Cheats", "Give" } }) + Register({ tab = "Cheats", ... }).
  Omit tabs = current single-scroll menu.

  Only the active tab's sections are built. Switching queues a rebuild off
  the poll tick (same hitch rule as collapse: never rebuild under a still-down click).
  Last tab is session-only (survives close/open; not written to disk).
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Input = require("ModMenu.core.input")
local InputMode = require("ModMenu.core.inputmode")
local Theme = require("ModMenu.core.theme")

local Debug = Util.Debug
local Construct = Umg.Construct
local CreateTextButton = Umg.CreateTextButton
local AddSpacer = Umg.AddSpacer

local M = {}

---@return boolean
function M.Enabled(S)
    return type(S.config.tabs) == "table" and #S.config.tabs > 0
end

---@return boolean
function M.Has(S, name)
    if not M.Enabled(S) or type(name) ~= "string" then
        return false
    end
    for _, tab in ipairs(S.config.tabs) do
        if tab == name then
            return true
        end
    end
    return false
end

--- Seed / repair S.activeTab against the current Init list.
function M.Ensure(S)
    if not M.Enabled(S) then
        S.activeTab = nil
        return
    end
    if M.Has(S, S.activeTab) then
        return
    end
    S.activeTab = S.config.tabs[1]
end

--- Map Register({ tab }) onto an Init tab. Omit tab = first tab.
---@return string|nil
function M.ResolveSectionTab(S, section)
    if not M.Enabled(S) then
        return nil
    end
    local tab = section.tab
    if tab == nil or tab == "" then
        return S.config.tabs[1]
    end
    if type(tab) ~= "string" then
        error("Register(" .. tostring(section.id) .. ") tab must be a string")
    end
    if not M.Has(S, tab) then
        error("Register(" .. tostring(section.id) .. ") tab " .. tab
            .. " is not in Init({ tabs = ... })")
    end
    return tab
end

---@return boolean
function M.SectionVisible(S, section)
    if not M.Enabled(S) then
        return true
    end
    M.Ensure(S)
    return section ~= nil and section.tab == S.activeTab
end

-- Finger-sized tab targets (desktop stays compact, text-height buttons).
local TOUCH_TAB_MIN_H = 56
local TOUCH_TAB_GAP = 8
local TOUCH_TAB_PAD = 12

--- Horizontal tab buttons under title / dock. Fill-width so three names share the row.
function M.BuildStrip(S, contentBox, suffix)
    M.Ensure(S)
    if not M.Enabled(S) then
        return
    end
    local colors = Theme.Of(S.config)
    local touch = S.config.pointerMode == "touch"
    local row = Construct("/Script/UMG.HorizontalBox", contentBox, "ModMenu_Tabs_" .. suffix)
    contentBox:AddChildToVerticalBox(row)

    for i, name in ipairs(S.config.tabs) do
        local active = name == S.activeTab
        local bg = active and colors.buttonBgActive or colors.buttonBg
        local fg = active and colors.buttonTextActive or colors.buttonText
        local host = row
        local size = nil
        if touch then
            size = Construct("/Script/UMG.SizeBox", row, "ModMenu_TabSize" .. tostring(i) .. "_" .. suffix)
            pcall(function()
                size:SetMinDesiredHeight(TOUCH_TAB_MIN_H)
            end)
            host = size
        end
        local btn, lbl = CreateTextButton(
            host,
            "ModMenu_Tab" .. tostring(i) .. "_" .. suffix,
            name,
            bg,
            fg,
            S.config.fontItem
        )
        if size ~= nil then
            -- Button must fill the SizeBox or the extra height is not hittable.
            local contentSlot
            pcall(function()
                contentSlot = size:SetContent(btn)
            end)
            pcall(function()
                if contentSlot ~= nil then
                    contentSlot:SetHorizontalAlignment(0) -- Fill
                    contentSlot:SetVerticalAlignment(0)
                end
            end)
            pcall(function()
                btn:SetPadding({ Left = 8, Top = 12, Right = 8, Bottom = 12 })
            end)
        end
        local slot = row:AddChildToHorizontalBox(size or btn)
        pcall(function()
            slot:SetSize({ SizeRule = 1, Value = 1.0 })
            slot:SetPadding({
                Left = (i == 1) and 0 or (touch and TOUCH_TAB_GAP or 4),
                Top = 0,
                Right = 0,
                Bottom = 0,
            })
            slot:SetVerticalAlignment(2)
        end)
        table.insert(S.liveControls, {
            kind = "tab",
            widget = btn,
            label = lbl,
            tabId = name,
        })
    end

    AddSpacer(contentBox, "ModMenu_TabPad_" .. suffix, touch and TOUCH_TAB_PAD or 8)
end

function M.QueueSelect(S, tabId)
    if not M.Enabled(S) or tabId == nil then
        return
    end
    if tabId == S.activeTab then
        return
    end
    if S.pendingTabId ~= nil then
        return
    end
    S.pendingTabId = tabId
end

--- Apply a tab change. Lazy-requires build so this module can be loaded from build.lua.
function M.Apply(S, tabId)
    if not M.Enabled(S) or tabId == nil then
        return
    end
    M.Ensure(S)
    if not M.Has(S, tabId) then
        return
    end
    if tabId == S.activeTab then
        return
    end
    S.activeTab = tabId
    Debug("Tab -> " .. tabId)
    if not S.menuOpen then
        if Util.IsValid(S.menuRoot) then
            S.contentDirty = true
        end
        return
    end
    local Build = require("ModMenu.shell.build")
    Build.BuildContent(S)
    Input.ClearClickState()
    InputMode.Reclaim()
end

--- Drain a queued tab click off the poll tick (collapse-style delay).
function M.Flush(S)
    local tabId = S.pendingTabId
    if tabId == nil then
        return
    end
    S.pendingTabId = nil
    table.insert(S.tabApplyQueue, tabId)
    if S.tabApplyFn == nil then
        S.tabApplyFn = Util.PinFn(function()
            S.tabApplyScheduled = false
            local queue = S.tabApplyQueue
            S.tabApplyQueue = {}
            local last = queue[#queue]
            if last ~= nil then
                M.Apply(S, last)
            end
        end)
    end
    if S.tabApplyScheduled then
        return
    end
    S.tabApplyScheduled = true
    ExecuteInGameThreadWithDelay(1, S.tabApplyFn)
end

--- Host SetTab: apply now so GetTab matches. Click path still queues (Flush).
---@return boolean
function M.Select(S, tabId)
    if not M.Enabled(S) then
        error("ModMenu.SetTab: Init({ tabs = ... }) was not set")
    end
    if type(tabId) ~= "string" or tabId == "" then
        error("ModMenu.SetTab: tab must be a non-empty string")
    end
    if not M.Has(S, tabId) then
        error("ModMenu.SetTab: " .. tabId .. " is not in Init({ tabs = ... })")
    end
    M.Ensure(S)
    if tabId == S.activeTab then
        return true
    end
    M.Apply(S, tabId)
    return true
end

function M.Poll(S, ctrl)
    if Input.WidgetPressedEdge(ctrl, ctrl.widget) then
        Input.DebugClick("press-edge", ctrl, ctrl.widget)
        M.QueueSelect(S, ctrl.tabId)
        InputMode.Reclaim()
        Input.IgnoreClicks(2)
    end
end

---@return boolean
function M.PollClick(S, ctrl)
    if not Input.WidgetHovered(ctrl.widget) then
        return false
    end
    Input.DebugClick("latch-hover", ctrl, ctrl.widget)
    Input.SuppressPressEdge(ctrl)
    M.QueueSelect(S, ctrl.tabId)
    InputMode.Reclaim()
    Input.IgnoreClicks(2)
    return true
end

return M
end

-- shell/confirm.lua
package.preload["ModMenu.shell.confirm"] = function(...)
--[[
  ModMenu.shell.confirm — in-shell modal for destructive actions.

  Covers the docked panel (same canvas, higher Z). Blocks other widget polls
  while open. Cancel / close menu runs nothing. Confirm runs onConfirm once.
  A new Show replaces the current prompt (treated as Cancel).
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Theme = require("ModMenu.core.theme")
local Input = require("ModMenu.core.input")
local InputMode = require("ModMenu.core.inputmode")
local Dock = require("ModMenu.shell.dock")
local Button = require("ModMenu.widgets.button")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local SafeCall = Util.SafeCall
local Construct = Umg.Construct
local StyleText = Umg.StyleText
local SetLabelText = Umg.SetLabelText
local EnableAutoWrap = Umg.EnableAutoWrap

local M = {}

local function Normalize(opts)
    if type(opts) ~= "table" then
        error("ModMenu.Confirm expects a table")
    end
    if type(opts.onConfirm) ~= "function" then
        error("ModMenu.Confirm requires onConfirm")
    end
    if opts.onCancel ~= nil and type(opts.onCancel) ~= "function" then
        error("ModMenu.Confirm onCancel must be a function")
    end
    local variant = Button.NormalizeVariant(opts.variant) or "danger"
    local title = opts.title
    if type(title) ~= "string" or title == "" then
        title = "Are you sure?"
    end
    local message = opts.message
    if type(message) ~= "string" or message == "" then
        message = nil
    end
    local confirmLabel = opts.confirmLabel
    if type(confirmLabel) ~= "string" or confirmLabel == "" then
        confirmLabel = "Confirm"
    end
    local cancelLabel = opts.cancelLabel
    if type(cancelLabel) ~= "string" or cancelLabel == "" then
        cancelLabel = "Cancel"
    end
    return {
        title = title,
        message = message,
        confirmLabel = confirmLabel,
        cancelLabel = cancelLabel,
        variant = variant,
        onConfirm = opts.onConfirm,
        onCancel = opts.onCancel,
    }
end

local function DestroyOverlay(S)
    if IsValid(S.confirmRoot) then
        pcall(function()
            S.confirmRoot:RemoveFromParent()
        end)
        pcall(function()
            S.confirmRoot:SetVisibility(1)
        end)
    end
    S.confirmRoot = nil
    S.confirmSlot = nil
    S.confirmControls = nil
end

--- Dismiss without stacking. reason = "confirm" | "cancel" | "close"
function M.Hide(S, reason)
    local spec = S.confirm
    S.confirm = nil
    DestroyOverlay(S)
    if spec == nil then
        return
    end
    if reason == "confirm" then
        Debug("Confirm accepted: " .. tostring(spec.title))
        SafeCall(spec.onConfirm)
    else
        Debug("Confirm dismissed (" .. tostring(reason) .. "): " .. tostring(spec.title))
        SafeCall(spec.onCancel)
    end
end

function M.IsOpen(S)
    return S.confirm ~= nil
end

local CARD_WIDTH = 360

local function AddHairline(parent, name, color)
    local box = Construct("/Script/UMG.SizeBox", parent, name)
    pcall(function()
        box:SetHeightOverride(1)
    end)
    local line = Construct("/Script/UMG.Border", box, name .. "_Line")
    pcall(function()
        line:SetBrushColor(color)
        line:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        box:SetContent(line)
    end)
    parent:AddChildToVerticalBox(box)
end

local function MakeButton(S, parent, namePrefix, label, variant, role)
    local colors = Theme.Of(S.config)
    local keys = {
        default = { "buttonBg", "buttonText" },
        primary = { "buttonBgPrimary", "buttonTextPrimary" },
        secondary = { "buttonBgSecondary", "buttonTextSecondary" },
        success = { "buttonBgSuccess", "buttonTextSuccess" },
        danger = { "buttonBgDanger", "buttonTextDanger" },
        warning = { "buttonBgWarning", "buttonTextWarning" },
        info = { "buttonBgInfo", "buttonTextInfo" },
    }
    local pair = keys[variant] or keys.default
    local bg = colors[pair[1]] or colors.buttonBg
    local fg = colors[pair[2]] or colors.buttonText
    local button, text = Umg.CreateTextButton(parent, namePrefix, label, bg, fg, S.config.fontItem)
    return {
        kind = "confirm",
        role = role,
        widget = button,
        labelWidget = text,
        item = { variant = variant, enabled = true, label = label },
        wasPressed = false,
    }
end

local function BuildOverlay(S, spec)
    if not IsValid(S.menuCanvas) then
        Log("Confirm: no menu canvas")
        return false
    end

    S.confirmGen = (S.confirmGen or 0) + 1
    local suffix = tostring(S.confirmGen)
    local colors = Theme.Of(S.config)
    local canvas = S.menuCanvas

    -- Dim fills the docked panel. The card is a separate auto-sized child so
    -- height follows title + message + buttons (Bootstrap-style), not the panel.
    local dim = Construct("/Script/UMG.Border", canvas, "ModMenu_ConfirmDim_" .. suffix)
    pcall(function()
        dim:SetBrushColor(colors.overlayDim or { R = 0, G = 0, B = 0, A = 0.55 })
        dim:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    end)

    local inner = Construct("/Script/UMG.CanvasPanel", dim, "ModMenu_ConfirmInner_" .. suffix)
    pcall(function()
        dim:SetContent(inner)
    end)

    local sizeBox = Construct("/Script/UMG.SizeBox", inner, "ModMenu_ConfirmSize_" .. suffix)
    pcall(function()
        sizeBox:SetWidthOverride(CARD_WIDTH)
        if sizeBox.SetMaxDesiredWidth then
            sizeBox:SetMaxDesiredWidth(CARD_WIDTH)
        end
    end)

    local card = Construct("/Script/UMG.Border", sizeBox, "ModMenu_ConfirmCard_" .. suffix)
    pcall(function()
        card:SetBrushColor(colors.confirmCardBg or colors.panelBg)
        card:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        sizeBox:SetContent(card)
    end)

    local vbox = Construct("/Script/UMG.VerticalBox", card, "ModMenu_ConfirmBox_" .. suffix)
    pcall(function()
        card:SetContent(vbox)
    end)

    local sectionPad = { Left = 16, Top = 12, Right = 16, Bottom = 12 }
    local divider = colors.confirmDivider or colors.panelBorder

    local title = Construct("/Script/UMG.TextBlock", vbox, "ModMenu_ConfirmTitle_" .. suffix)
    StyleText(title, S.config.fontSection, colors.textPrimary)
    SetLabelText(title, spec.title)
    EnableAutoWrap(title)
    local titleSlot = vbox:AddChildToVerticalBox(title)
    pcall(function()
        titleSlot:SetPadding(sectionPad)
        titleSlot:SetHorizontalAlignment(0)
        titleSlot:SetSize({ SizeRule = 0, Value = 0.0 })
    end)

    AddHairline(vbox, "ModMenu_ConfirmRule1_" .. suffix, divider)

    if spec.message ~= nil then
        local msg = Construct("/Script/UMG.TextBlock", vbox, "ModMenu_ConfirmMsg_" .. suffix)
        StyleText(msg, S.config.fontItem, colors.textMuted)
        SetLabelText(msg, spec.message)
        EnableAutoWrap(msg)
        local msgSlot = vbox:AddChildToVerticalBox(msg)
        pcall(function()
            msgSlot:SetPadding(sectionPad)
            msgSlot:SetHorizontalAlignment(0)
            msgSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        end)
        AddHairline(vbox, "ModMenu_ConfirmRule2_" .. suffix, divider)
    end

    local row = Construct("/Script/UMG.HorizontalBox", vbox, "ModMenu_ConfirmRow_" .. suffix)
    local rowSlot = vbox:AddChildToVerticalBox(row)
    pcall(function()
        rowSlot:SetPadding({ Left = 12, Top = 10, Right = 12, Bottom = 10 })
        rowSlot:SetSize({ SizeRule = 0, Value = 0.0 })
    end)

    local push = Construct("/Script/UMG.Spacer", row, "ModMenu_ConfirmPush_" .. suffix)
    local pushSlot = row:AddChildToHorizontalBox(push)
    pcall(function()
        pushSlot:SetSize({ SizeRule = 1, Value = 1.0 })
    end)

    local cancel = MakeButton(S, row, "ModMenu_ConfirmNo_" .. suffix, spec.cancelLabel, "secondary", "cancel")
    local cancelSlot = row:AddChildToHorizontalBox(cancel.widget)
    pcall(function()
        cancelSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        cancelSlot:SetPadding({ Left = 0, Top = 0, Right = 8, Bottom = 0 })
        cancelSlot:SetVerticalAlignment(2)
    end)

    local ok = MakeButton(S, row, "ModMenu_ConfirmYes_" .. suffix, spec.confirmLabel, spec.variant, "confirm")
    local okSlot = row:AddChildToHorizontalBox(ok.widget)
    pcall(function()
        okSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        okSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        okSlot:SetVerticalAlignment(2)
    end)

    local cardSlot = inner:AddChildToCanvas(sizeBox)
    pcall(function()
        cardSlot:SetAutoSize(true)
        cardSlot:SetAnchors({
            Minimum = { X = 0.5, Y = 0.5 },
            Maximum = { X = 0.5, Y = 0.5 },
        })
        cardSlot:SetAlignment({ X = 0.5, Y = 0.5 })
        cardSlot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        cardSlot:SetZOrder(1)
    end)

    local slot = canvas:AddChildToCanvas(dim)
    Dock.ApplyPercentLayout(slot, S.config)
    pcall(function()
        slot:SetZOrder(20)
    end)

    S.confirmRoot = dim
    S.confirmSlot = slot
    S.confirmControls = { cancel, ok }
    return true
end

function M.Show(S, opts)
    local spec = Normalize(opts)
    if M.IsOpen(S) then
        M.Hide(S, "cancel")
    end
    if not IsValid(S.menuCanvas) or S.menuOpen ~= true then
        Log("Confirm: menu is not open")
        return false
    end
    if not BuildOverlay(S, spec) then
        return false
    end
    S.confirm = spec
    Input.ClearClickState()
    Input.IgnoreClicks(2)
    InputMode.Reclaim()
    Debug("Confirm shown: " .. spec.title)
    return true
end

--- Poll only the modal buttons. Consumes leftover clicks so they cannot hit the panel.
---@return boolean true if a confirm is open
function M.Poll(S)
    if S.confirm == nil then
        return false
    end

    local fired = nil
    for _, ctrl in ipairs(S.confirmControls or {}) do
        if Input.WidgetPressedEdge(ctrl, ctrl.widget) then
            Input.DebugClick("press-edge", ctrl, ctrl.widget)
            fired = ctrl.role
            Input.SuppressPressEdge(ctrl)
            break
        end
    end

    if Input.ConsumeMouseClick() and fired == nil then
        local latchHit = false
        for _, ctrl in ipairs(S.confirmControls or {}) do
            if Input.WidgetHovered(ctrl.widget) then
                Input.DebugClick("latch-hover", ctrl, ctrl.widget)
                fired = ctrl.role
                Input.SuppressPressEdge(ctrl)
                latchHit = true
                break
            end
        end
        if not latchHit then
            Input.DebugClick("latch-miss", { kind = "confirm" }, nil)
        end
    end

    if fired == "confirm" then
        Input.IgnoreClicks(2)
        M.Hide(S, "confirm")
        InputMode.Reclaim()
    elseif fired == "cancel" then
        Input.IgnoreClicks(2)
        M.Hide(S, "cancel")
        InputMode.Reclaim()
    end
    return true
end

--- Button item.confirm → Show. onClick runs only after Confirm.
function M.FromButton(S, item)
    local spec = item.confirm
    if type(spec) ~= "table" then
        return false
    end
    M.Show(S, {
        title = spec.title,
        message = spec.message,
        confirmLabel = spec.confirmLabel,
        cancelLabel = spec.cancelLabel,
        variant = spec.variant or item.variant,
        onConfirm = item.onClick,
    })
    return true
end

return M
end

-- shell/build.lua
package.preload["ModMenu.shell.build"] = function(...)
--[[
  ModMenu.shell.build — construct / destroy the UMG tree and rebuild section content.
]]

local UEHelpers = require("UEHelpers.UEHelpers")
local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Theme = require("ModMenu.core.theme")
local Instance = require("ModMenu.core.instance")
local InputMode = require("ModMenu.core.inputmode")
local Cursor = require("ModMenu.core.cursor")
local Widgets = require("ModMenu.widgets.init")
local Session = require("ModMenu.shell.session")
local Dock = require("ModMenu.shell.dock")
local Collapse = require("ModMenu.shell.collapse")
local Tabs = require("ModMenu.shell.tabs")
local Confirm = require("ModMenu.shell.confirm")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local Construct = Umg.Construct
local StyleText = Umg.StyleText
local SetLabelText = Umg.SetLabelText
local AddSpacer = Umg.AddSpacer
local CreateTextButton = Umg.CreateTextButton

local M = {}

function M.BuildContent(S)
    if not IsValid(S.contentBox) then
        return
    end
    S.contentDirty = false

    pcall(function()
        S.contentBox:ClearChildren()
    end)
    Session.ClearLive(S)

    -- Must change every rebuild. Reusing FNames after ClearChildren resurrects zombies —
    -- category (more option rows) breaks harder than language; both are the same control.
    S.contentGen = S.contentGen + 1
    local suffix = tostring(S.contentGen)
    local config = S.config
    local contentBox = S.contentBox

    local titleRow = Construct("/Script/UMG.HorizontalBox", contentBox, "ModMenu_TitleRow_" .. suffix)
    contentBox:AddChildToVerticalBox(titleRow)

    local title = Construct("/Script/UMG.TextBlock", titleRow, "ModMenu_Title_" .. suffix)
    StyleText(title, config.fontTitle)
    SetLabelText(title, config.title)
    local titleSlot = titleRow:AddChildToHorizontalBox(title)
    pcall(function()
        titleSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        titleSlot:SetVerticalAlignment(2)
    end)

    -- Title-row Close: same path as the toggle key. Opt out with showClose = false.
    if config.showClose ~= false then
        local closeBtn, closeLbl = CreateTextButton(
            titleRow,
            "ModMenu_Close_" .. suffix,
            "Close"
        )
        local closeSlot = titleRow:AddChildToHorizontalBox(closeBtn)
        pcall(function()
            closeSlot:SetSize({ SizeRule = 0, Value = 0.0 })
            closeSlot:SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 })
            closeSlot:SetVerticalAlignment(2)
        end)
        table.insert(S.liveControls, {
            kind = "close",
            widget = closeBtn,
            label = closeLbl,
            role = "close",
            wasPressed = false,
        })
    end

    local keyName = tostring(config.keyHint or config.keyName or "F6")
    local hintText = "[" .. keyName .. "] toggle menu"
    if type(config.consoleCommand) == "string" and config.consoleCommand ~= "" then
        hintText = hintText .. " · " .. config.consoleCommand
    end
    local hint = Construct("/Script/UMG.TextBlock", contentBox, "ModMenu_Hint_" .. suffix)
    StyleText(hint, config.fontHint)
    SetLabelText(hint, hintText)
    contentBox:AddChildToVerticalBox(hint)

    -- Shell chrome: four-side dock picker (no panel rebuild).
    Dock.BuildChrome(S, contentBox, suffix)

    Tabs.BuildStrip(S, contentBox, suffix)

    AddSpacer(contentBox, "ModMenu_HeadPad_" .. suffix, 16)

    if #S.sections == 0 then
        local empty = Construct("/Script/UMG.TextBlock", contentBox, "ModMenu_Empty_" .. suffix)
        StyleText(empty, config.fontHint)
        SetLabelText(empty, "No mods registered yet.")
        contentBox:AddChildToVerticalBox(empty)
        return
    end

    local visible = {}
    for _, section in ipairs(S.sections) do
        if Tabs.SectionVisible(S, section) then
            table.insert(visible, section)
        end
    end

    if #visible == 0 then
        local emptyTab = Construct("/Script/UMG.TextBlock", contentBox, "ModMenu_EmptyTab_" .. suffix)
        StyleText(emptyTab, config.fontHint)
        SetLabelText(emptyTab, "No sections on this tab.")
        contentBox:AddChildToVerticalBox(emptyTab)
        return
    end

    for sIndex, section in ipairs(visible) do
        local collapsed = Collapse.IsCollapsed(S, section)
        local itemParent = contentBox
        if Collapse.IsCollapsible(section) then
            local header = Collapse.BuildHeader(S, section, contentBox, suffix)
            local body = Construct(
                "/Script/UMG.VerticalBox",
                contentBox,
                string.format("ModMenu_SecBody_%s_%s", section.id, suffix)
            )
            contentBox:AddChildToVerticalBox(body)
            Collapse.AttachBody(header, body, collapsed)
            itemParent = body
        else
            local secTitle = Construct(
                "/Script/UMG.TextBlock",
                contentBox,
                string.format("ModMenu_Sec_%s_%s", section.id, suffix)
            )
            StyleText(secTitle, config.fontSection)
            SetLabelText(secTitle, section.title or section.id)
            contentBox:AddChildToVerticalBox(secTitle)
        end
        AddSpacer(itemParent, string.format("ModMenu_SecPad_%s_%s", section.id, suffix), 8)

        -- Always build children. Collapsed sections hide the body (dropdown-style)
        -- so toggling does not rebuild and flicker under a still-down click.
        local ctx = S.makeWidgetCtx()
        ctx.contentBox = itemParent

        for i, item in ipairs(section.items) do
            local namePrefix = string.format("ModMenu_%s_%s_%d_%s", section.id, tostring(item.id or item.type), i, suffix)
            local widget = Widgets.get(item.type)
            if not widget or not widget.build then
                error("BuildContent: no builder for type " .. tostring(item.type))
            end
            ctx.section = section
            ctx.item = item
            ctx.namePrefix = namePrefix
            widget.build(ctx)
        end

        if sIndex < #visible then
            AddSpacer(contentBox, "ModMenu_Between_" .. section.id .. "_" .. suffix, 18)
        end
    end

    -- Touch: last Combat buttons sat on the 1080p clip edge. Mouse does not
    -- need that extra well — those clicks were landing (God hid the HP change).
    local foot = 8
    if config.pointerMode == "touch" then
        foot = 120
    end
    AddSpacer(contentBox, "ModMenu_Foot_" .. suffix, foot)
end

function M.Teardown(S)
    Confirm.Hide(S, "close")
    Cursor.Destroy(S)
    if IsValid(S.menuRoot) then
        pcall(function()
            S.menuRoot:RemoveFromParent()
        end)
        pcall(function()
            S.menuRoot:RemoveFromViewport()
        end)
    end
    S.menuRoot = nil
    S.contentBox = nil
    S.menuScroll = nil
    S.menuCanvas = nil
    S.panelSlot = nil
    S.panelBorder = nil
    S.panelOutline = nil
    S.confirm = nil
    S.confirmRoot = nil
    S.confirmSlot = nil
    S.confirmControls = nil
    Session.ClearLive(S)
    S.menuOpen = false
end

--- ClientRestart always destroys the shell. Do not ApplyGameOnly / hide
--- the cursor unless this instance had actually taken input.
function M.Destroy(S, stopPoll)
    if stopPoll then
        stopPoll()
    end
    local wasHoldingInput = S.menuOpen or Instance.IsOpenCountHeld()
    local remaining = Instance.NoteClosed()
    M.Teardown(S)
    if wasHoldingInput then
        InputMode.SetActive(false, remaining)
    end
end

function M.Create(S)
    local config = S.config
    Instance.Ensure(config)
    Instance.BumpCreateAttempts()
    local suffix = Instance.ShellNameSuffix(config)

    local outer = UEHelpers.GetGameInstance()
    if not IsValid(outer) then
        outer = UEHelpers.GetPlayerController()
    end
    if not IsValid(outer) then
        error("No GameInstance or PlayerController to parent the widget")
    end

    -- Names must be unique under GameInstance across ALL mods (ModRef-backed tag/serial).
    local hud = Construct("/Script/UMG.UserWidget", outer, "ModMenu_Root_" .. suffix)
    local tree = Construct("/Script/UMG.WidgetTree", hud, "ModMenu_Tree_" .. suffix)
    hud.WidgetTree = tree

    local canvas = Construct("/Script/UMG.CanvasPanel", tree, "ModMenu_Canvas_" .. suffix)
    tree.RootWidget = canvas
    S.menuCanvas = canvas

    local colors = Theme.Of(config)
    local fill = Construct("/Script/UMG.Border", canvas, "ModMenu_Border_" .. suffix)
    pcall(function()
        fill:SetBrushColor(colors.panelBg)
        fill:SetPadding(Theme.PadPanel(config))
    end)

    -- Always wrap in a 1px outline. Light uses panelBg so the edge is invisible.
    local outline = Construct("/Script/UMG.Border", canvas, "ModMenu_Outline_" .. suffix)
    pcall(function()
        outline:SetBrushColor(colors.panelBorder)
        outline:SetPadding({ Left = 1, Top = 1, Right = 1, Bottom = 1 })
        outline:SetContent(fill)
    end)

    -- ScrollBox fills the docked panel so long section lists are reachable.
    local scroll = Construct("/Script/UMG.ScrollBox", fill, "ModMenu_Scroll_" .. suffix)
    fill:SetContent(scroll)

    local vbox = Construct("/Script/UMG.VerticalBox", scroll, "ModMenu_VBox_" .. suffix)
    pcall(function()
        scroll:AddChild(vbox)
    end)
    -- After children: constructed ScrollBox often ignores thickness until the slot exists.
    Umg.StyleScrollBox(scroll, config)

    local slot = canvas:AddChildToCanvas(outline)
    S.panelSlot = slot
    S.panelBorder = fill
    S.panelOutline = outline
    if slot then
        Dock.ApplyPercentLayout(slot, config)
    end

    hud:AddToViewport(Instance.GetViewportZ())
    hud:SetVisibility(Session.VIS_COLLAPSED)
    Umg.StyleScrollBox(scroll, config)

    S.menuRoot = hud
    S.contentBox = vbox
    S.menuScroll = scroll
    M.BuildContent(S)

    local thickPct = (config.widthFrac or 0.32) * 100
    local longPct = (1.0 - (config.topFrac or 0) - (config.bottomFrac or 0)) * 100
    local spanX = thickPct
    local spanY = longPct
    if config.dock == "top" or config.dock == "bottom" then
        spanX = longPct
        spanY = thickPct
    end
    Debug(string.format(
        "Shell ready name=ModMenu_Root_%s z=%d dock=%s (~%.0f%% x ~%.0f%%). Sections: %d",
        suffix,
        Instance.GetViewportZ(),
        tostring(config.dock),
        spanX,
        spanY,
        #S.sections
    ))
end

function M.Ensure(S)
    if IsValid(S.menuRoot) and IsValid(S.contentBox) then
        return true
    end
    local ok, err = pcall(M.Create, S)
    if not ok then
        Log("CreateShell failed: " .. tostring(err))
        M.Destroy(S, S.stopPoll)
        return false
    end
    return IsValid(S.menuRoot)
end

return M
end

-- shell/lifecycle.lua
package.preload["ModMenu.shell.lifecycle"] = function(...)
--[[
  ModMenu.shell.lifecycle — open / close / toggle, poll loop, ClientRestart.
]]

local UEHelpers = require("UEHelpers.UEHelpers")
local Util = require("ModMenu.core.util")
local Input = require("ModMenu.core.input")
local InputMode = require("ModMenu.core.inputmode")
local Instance = require("ModMenu.core.instance")
local Cursor = require("ModMenu.core.cursor")
local Widgets = require("ModMenu.widgets.init")
local Session = require("ModMenu.shell.session")
local Close = require("ModMenu.shell.close")
local Collapse = require("ModMenu.shell.collapse")
local Tabs = require("ModMenu.shell.tabs")
local Build = require("ModMenu.shell.build")
local Confirm = require("ModMenu.shell.confirm")
local Theme = require("ModMenu.core.theme")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local SafeCall = Util.SafeCall
local Dropdown = Widgets.get("dropdown")

local M = {}

function M.StopPoll(S)
    if S.pollHandle then
        pcall(function()
            CancelDelayedAction(S.pollHandle)
        end)
        S.pollHandle = nil
    end
    -- Keep S.pollFn pinned. CancelDelayedAction can still run this tick;
    -- dropping the Lua function here is what produces "Ref was not function".
end

local function PollControls(S)
    if Confirm.Poll(S) then
        return
    end

    local ctx = S.makeWidgetCtx()

    Input.BeginPoll(S.liveControls)

    -- Continuous polls (search filter, checkbox state, UButton IsPressed).
    -- pollClick is the LMB-latch fallback. Handlers must SuppressPressEdge so
    -- a latch click is not also treated as an IsPressed rising edge next tick.
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "close" then
            Close.Poll(S, ctrl)
        elseif ctrl.kind == "collapse" then
            Collapse.Poll(S, ctrl)
        elseif ctrl.kind == "tab" then
            Tabs.Poll(S, ctrl)
        else
            local widget = Widgets.get(ctrl.kind)
            if widget and widget.poll then
                widget.poll(ctrl, ctx)
            end
        end
    end

    if Input.ConsumeMouseClick() then
        -- List order. Dropdown.pollClick does option rows then header.
        local consumed = false
        for _, ctrl in ipairs(S.liveControls) do
            if ctrl.kind == "close" then
                if Close.PollClick(S, ctrl) then
                    consumed = true
                    break
                end
            elseif ctrl.kind == "collapse" then
                if Collapse.PollClick(S, ctrl) then
                    consumed = true
                    break
                end
            elseif ctrl.kind == "tab" then
                if Tabs.PollClick(S, ctrl) then
                    consumed = true
                    break
                end
            else
                local widget = Widgets.get(ctrl.kind)
                if widget and widget.pollClick and widget.pollClick(ctrl, ctx) then
                    consumed = true
                    break
                end
            end
        end
        if not consumed then
            if not Input.RetryUnclaimedClick() then
                Input.DebugClick("latch-miss", nil, nil)
            end
        end
    end

    -- Collapse show/hide after ipairs so a press-edge + latch cannot both apply.
    Collapse.Flush(S)
    -- Tab rebuild is also deferred — never BuildContent under a still-down click.
    Tabs.Flush(S)
    if S.pendingClose then
        S.pendingClose = false
        M.Close(S)
    end
end

function M.StartPoll(S)
    M.StopPoll(S)
    if S.pollFn == nil then
        S.pollFn = Util.PinFn(function()
            if not S.menuOpen then
                return
            end
            -- Reclaim when the game steals cursor / click routing (toast, etc.).
            -- Look-ignore is opt-in (Init ignoreLook) — do not re-lock the camera by default.
            local pc = UEHelpers.GetPlayerController()
            if InputMode.CursorStolen(pc) then
                InputMode.Reclaim()
            else
                -- Overlay / Wuchang: keep look locked without resetting Slate focus.
                InputMode.RefreshLookIgnore(pc)
            end
            PollControls(S)
        end)
    end
    S.pollHandle = LoopInGameThreadWithDelay(Session.POLL_MS, S.pollFn)
end

--- Host gate for opening (key toggle + ModMenu.Open). Close is never gated.
---@return boolean allowed
---@return string|nil reason
function M.EvaluateCanOpen(S)
    local fn = S.config.canOpen
    if type(fn) ~= "function" then
        return true
    end
    local ok, a, b = pcall(fn)
    if not ok then
        return false, tostring(a)
    end
    if a == false then
        return false, (type(b) == "string" and b ~= "") and b or "canOpen returned false"
    end
    return true
end

---@param opts { skipCanOpen?: boolean }|nil
function M.Open(S, opts)
    opts = opts or {}
    if not opts.skipCanOpen then
        local allowed, reason = M.EvaluateCanOpen(S)
        if not allowed then
            Log("OPEN blocked: " .. tostring(reason))
            return
        end
    end
    if not Build.Ensure(S) then
        return
    end
    -- Keep the UMG tree across open/close. Create already builds content;
    -- rebuilding here respawns every searchable row (Give, keybinds, …).
    -- contentDirty: Register / SetOptions while closed after the first open.
    if S.contentDirty or S.liveControls == nil or #S.liveControls == 0 then
        Build.BuildContent(S)
    end
    S.menuRoot:SetVisibility(Session.VIS_VISIBLE)
    S.menuOpen = true
    Instance.NoteOpened()
    InputMode.SetActive(true)
    M.StartPoll(S)
    if Cursor.IsEnabled(S) then
        if S.cursorShowFn == nil then
            S.cursorShowFn = Util.PinFn(function()
                S.cursorShowHandle = nil
                if S.menuOpen then
                    Cursor.Show(S)
                    Cursor.StartPoll(S)
                end
            end)
        end
        if S.cursorShowHandle ~= nil then
            pcall(function()
                CancelDelayedAction(S.cursorShowHandle)
            end)
            S.cursorShowHandle = nil
        end
        -- Brief delay so the shell is in the viewport before the overlay attaches.
        S.cursorShowHandle = ExecuteInGameThreadWithDelay(50, S.cursorShowFn)
    end
    Debug(string.format("OPEN tag=%s", tostring(Instance.GetTag())))
    for _, fn in ipairs(S.onOpenCallbacks) do
        SafeCall(fn)
    end
end

function M.Close(S)
    Confirm.Hide(S, "close")
    M.StopPoll(S)
    if S.cursorShowHandle ~= nil then
        pcall(function()
            CancelDelayedAction(S.cursorShowHandle)
        end)
        S.cursorShowHandle = nil
    end
    Cursor.Hide(S)
    Input.ClearClickState()
    Dropdown.collapseAll(S.liveControls, nil)
    if IsValid(S.menuRoot) then
        S.menuRoot:SetVisibility(Session.VIS_COLLAPSED)
    end
    S.menuOpen = false
    local remaining = Instance.NoteClosed()
    InputMode.SetActive(false, remaining)
    Debug(string.format("CLOSED tag=%s openRemaining=%s", tostring(Instance.GetTag()), tostring(remaining)))
    if S.onCloseCallbacks then
        for _, fn in ipairs(S.onCloseCallbacks) do
            SafeCall(fn)
        end
    end
end

function M.Toggle(S)
    -- Close is never gated. Open (and recover-to-open) respects canOpen.
    if S.menuOpen and IsValid(S.menuRoot) and Session.IsVisible(S) then
        M.Close(S)
    else
        M.Open(S)
    end
end

--- Re-apply panel fill/outline after Init. Rebuild content if the shell exists.
function M.OnConfigChanged(S)
    Tabs.Ensure(S)
    local colors = Theme.Of(S.config)
    if IsValid(S.panelBorder) then
        pcall(function()
            S.panelBorder:SetBrushColor(colors.panelBg)
            S.panelBorder:SetPadding(Theme.PadPanel(S.config))
        end)
    end
    if IsValid(S.panelOutline) then
        pcall(function()
            S.panelOutline:SetBrushColor(colors.panelBorder)
        end)
    end
    -- Cursor overlay is independent of the shell tree (first Init has no root yet).
    Cursor.OnConfigChanged(S)
    if not IsValid(S.menuRoot) then
        return
    end
    if S.menuOpen then
        Build.BuildContent(S)
        Input.ClearClickState()
    else
        S.contentDirty = true
    end
end

function M.InstallHooks(S)
    if S.hooksInstalled then
        return
    end
    S.hooksInstalled = true
    S.stopPoll = function()
        M.StopPoll(S)
    end

    S.clientRestartFn = Util.PinFn(function()
        local wasOpen = S.menuOpen
        Build.Destroy(S, S.stopPoll)
        Debug("ClientRestart — shell reset")
        if wasOpen then
            -- Already-open session: restore without re-checking the host gate.
            M.Open(S, { skipCanOpen = true })
        end
    end)

    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        ExecuteInGameThread(S.clientRestartFn)
    end)
end

return M
end

-- shell/registry.lua
package.preload["ModMenu.shell.registry"] = function(...)
--[[
  ModMenu.shell.registry — sections, values, Register, Get/Set, live widget apply.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Input = require("ModMenu.core.input")
local Options = require("ModMenu.core.options")
local Widgets = require("ModMenu.widgets.init")
local Session = require("ModMenu.shell.session")
local Build = require("ModMenu.shell.build")
local Collapse = require("ModMenu.shell.collapse")
local Tabs = require("ModMenu.shell.tabs")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local ToPlainString = Util.ToPlainString
local ValueKey = Util.ValueKey
local SetLabelText = Umg.SetLabelText
local NormalizeOptions = Options.NormalizeOptions
local Dropdown = Widgets.get("dropdown")
local Button = Widgets.get("button")

local M = {}

local function ValidateItem(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if type(item) ~= "table" then
        error(prefix .. " must be a table")
    end
    local t = item.type
    local widget = Widgets.get(t)
    if not widget then
        error(prefix .. " unsupported type '" .. tostring(t) .. "' (" .. Widgets.typeList() .. ")")
    end
    if widget.validate then
        widget.validate(item, sectionId, index)
    end
end

--- Walk top-level, fold, and row children (fold may contain a row).
local function FindItemById(items, itemId, typeName)
    for _, item in ipairs(items or {}) do
        if item.id == itemId and (typeName == nil or item.type == typeName) then
            return item
        end
        if (item.type == "row" or item.type == "fold") and type(item.items) == "table" then
            local found = FindItemById(item.items, itemId, typeName)
            if found then
                return found
            end
        end
    end
    return nil
end

local function ValidateSection(section)
    if type(section) ~= "table" then
        error("Register() expects a section table")
    end
    if section.id == nil or section.id == "" then
        error("Register() section requires .id")
    end
    if type(section.items) ~= "table" then
        error("Register(" .. tostring(section.id) .. ") requires .items array")
    end
    Collapse.Validate(section)
    for i, item in ipairs(section.items) do
        ValidateItem(item, section.id, i)
    end
end

--- Rebuild now if open; otherwise mark dirty so the next Open rebuilds
--- (close/open keeps the UMG tree).
local function EnsureRebuildFn(S)
    if S.rebuildFn ~= nil then
        return S.rebuildFn
    end
    S.rebuildFn = Util.PinFn(function()
        local ok, err = pcall(function()
            if Build.Ensure(S) then
                Build.BuildContent(S)
                Session.EnsureVisible(S)
                Input.ClearClickState()
            end
        end)
        if not ok then
            Log("rebuild failed: " .. tostring(err))
            Session.EnsureVisible(S)
        end
    end)
    return S.rebuildFn
end

local function RebuildIfOpen(S)
    if not S.menuOpen then
        if IsValid(S.menuRoot) then
            S.contentDirty = true
        end
        return
    end
    ExecuteInGameThread(EnsureRebuildFn(S))
end

--- Apply a stored value to any live control with that valueKey.
local function ApplyLive(S, vkey, value)
    local ctx = S.makeWidgetCtx()
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.valueKey == vkey then
            local widget = Widgets.get(ctrl.kind)
            if widget and widget.apply then
                widget.apply(ctrl, value, ctx)
            end
        end
    end
end

function M.Register(S, section)
    ValidateSection(section)

    local copy = {
        id = section.id,
        title = section.title or section.id,
        items = section.items,
        collapsible = section.collapsible == true,
        collapsed = section.collapsed == true,
        onToggle = section.onToggle,
        tab = Tabs.ResolveSectionTab(S, section),
    }

    Collapse.Seed(S, copy)

    -- Seed defaults into values store.
    for _, item in ipairs(copy.items) do
        local widget = Widgets.get(item.type)
        if widget and widget.seed then
            widget.seed(copy.id, item, S.values)
        end
    end

    local existing = S.sectionIndexById[copy.id]
    local oldTab = existing and S.sections[existing].tab
    if existing then
        S.sections[existing] = copy
        Debug("Updated section: " .. copy.id)
    else
        table.insert(S.sections, copy)
        S.sectionIndexById[copy.id] = #S.sections
        Debug("Registered section: " .. copy.id .. " (" .. tostring(#copy.items) .. " items)")
    end

    -- Hidden-tab Register must not rebuild the active tab's tree.
    local needsUi = (not Tabs.Enabled(S))
        or Tabs.SectionVisible(S, copy)
        or (oldTab ~= nil and oldTab == S.activeTab)
    if needsUi then
        RebuildIfOpen(S)
    end
end

function M.Get(S, sectionId, itemId)
    return S.values[ValueKey(sectionId, itemId)]
end

function M.Set(S, sectionId, itemId, value)
    local vkey = ValueKey(sectionId, itemId)
    S.values[vkey] = value
    ApplyLive(S, vkey, value)
end

function M.SetLabel(S, sectionId, itemId, text)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "label")
    if not item then
        return false
    end
    item.label = tostring(text)
    local vkey = ValueKey(sectionId, itemId)
    local ctx = S.makeWidgetCtx()
    local labelWidget = Widgets.get("label")
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "label" and ctrl.valueKey == vkey and IsValid(ctrl.widget) then
            if labelWidget and labelWidget.apply then
                labelWidget.apply(ctrl, item.label, ctx)
            end
        end
    end
    return true
end

function M.SetButtonLabel(S, sectionId, itemId, text)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "button")
    if not item then
        return false
    end
    item.label = tostring(text)
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "button"
            and ctrl.sectionId == sectionId
            and ctrl.item
            and ctrl.item.id == itemId
        then
            -- Do not gate on IsValid(labelWidget) — Button child TextBlocks often report invalid.
            SetLabelText(ctrl.labelWidget, item.label)
            return true
        end
    end
    return true
end

local function SyncLiveButton(S, sectionId, itemId)
    local ctx = S.makeWidgetCtx()
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "button"
            and ctrl.sectionId == sectionId
            and ctrl.item
            and ctrl.item.id == itemId
        then
            if Button and Button.applyChrome then
                Button.applyChrome(ctrl, ctx)
            end
            return
        end
    end
end

function M.SetButtonEnabled(S, sectionId, itemId, enabled)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "button")
    if not item then
        return false
    end
    item.enabled = enabled and true or false
    SyncLiveButton(S, sectionId, itemId)
    return true
end

function M.SetButtonVariant(S, sectionId, itemId, variant)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "button")
    if not item then
        return false
    end
    local normalized = Button.NormalizeVariant(variant)
    if normalized == nil then
        error("SetButtonVariant: variant must be default|primary|secondary|success|danger|warning|info")
    end
    item.variant = normalized
    SyncLiveButton(S, sectionId, itemId)
    return true
end

function M.SetButtonActive(S, sectionId, itemId, active)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "button")
    if not item then
        return false
    end
    item.active = active and true or false
    SyncLiveButton(S, sectionId, itemId)
    return true
end

--- Replace dropdown options.
--- Searchable dropdowns refresh rows in place when live; others rebuild the panel.
function M.SetOptions(S, sectionId, itemId, options, selectedValue)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "dropdown")
    if not item then
        return false
    end
    if type(options) ~= "table" or #options == 0 then
        error("SetOptions requires non-empty options array")
    end
    local list = NormalizeOptions(options)
    item.options = list
    local vkey = ValueKey(sectionId, itemId)
    if selectedValue == false then
        S.values[vkey] = nil
        item.default = nil
    elseif selectedValue ~= nil then
        local plain = ToPlainString(selectedValue) or selectedValue
        S.values[vkey] = plain
        item.default = plain
    end

    -- Prefer in-place refresh for searchable lists (category filter, etc.).
    -- Live pickers still exist while the menu is closed (tree is kept).
    local live = nil
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "dropdown" and ctrl.valueKey == vkey then
            live = ctrl
            break
        end
    end

    if live and live.searchable and live.listBox ~= nil then
        Dropdown.refreshLive(live, list, selectedValue, S.values, vkey)
        Debug(string.format(
            "SetOptions(%s.%s) refreshed searchable list (%d options)",
            tostring(sectionId),
            tostring(itemId),
            #list
        ))
        return true
    end

    if S.menuOpen and Tabs.Enabled(S) and not Tabs.SectionVisible(S, section) then
        return true
    end

    if S.menuOpen then
        ExecuteInGameThread(EnsureRebuildFn(S))
        Debug(string.format(
            "SetOptions(%s.%s) scheduled rebuild with %d options",
            tostring(sectionId),
            tostring(itemId),
            #list
        ))
    elseif IsValid(S.menuRoot) then
        S.contentDirty = true
    end
    return true
end

function M.ListSections(S)
    local ids = {}
    for _, section in ipairs(S.sections) do
        table.insert(ids, section.id)
    end
    return ids
end

return M
end

-- ModMenu.lua (entry)
--[[
  ModMenu — shared in-game UMG settings shell for UE4SS Lua mods.

  Usage:
    local ModMenu = require("ModMenu.ModMenu")
    ModMenu.Init({ title = "My Mod Menu", key = Key.F6 }) -- ignoreLook = true to lock camera
    -- inputBackend = "engine" when RegisterKeyBind does not fire (e.g. Code Vein 2)
    -- cursorMode = "modmenu" when the game suppresses the engine cursor
    -- pointerMode = "touch" on handheld (checkbox buttons + ignore delayed latch)
    -- showClose = false to hide the title-row Close button (on by default)
    ModMenu.Register({
      id = "MyMod",
      title = "My Mod",
      items = {
        { type = "checkbox", id = "enabled", label = "Enabled", default = false,
          onChange = function(on) end },
        { type = "button", id = "run", label = "Do thing",
          onClick = function() end },
        { type = "dropdown", id = "mode", label = "Mode",
          options = { "A", { label = "Bee", value = "b" } },
          default = "A", onChange = function(value) end },
        { type = "dropdown", id = "item", label = "Item", searchable = true,
          placeholder = "Select item...", maxVisible = 12,
          options = { ... }, onChange = function(value) end },
        { type = "row", items = {
            { type = "number", id = "count", label = "Count", default = 1, min = 1, integer = true },
            { type = "button", id = "add", label = "Add Selected",
              onClick = function()
                local n = ModMenu.Get("MyMod", "count")
              end },
          }},
        { type = "label", label = "Hint text" },
        { type = "separator" },
      },
    })
    ModMenu.SetDock("left") -- or Init({ dock = "left"|"right"|"top"|"bottom" })

  Per-mod shell: each Lua mod that Init()s gets its own panel + hotkey.
  UObject names / viewport Z are allocated via ModRef shared vars so two mods
  never collide on ModMenu_Root_1 under the same GameInstance.

  Dock presets: Init({ dock }) is the starting edge. Header dropdown offers
  Left / Right / Top / Bottom. Session only unless the host persists (OnDockChange).
  Collapsible sections: Register({ collapsible = true, collapsed = true }).
  Nested fold: { type = "fold", id, label, collapsed = true, items = { ... } }.
  Theme (authors): Init({ theme = "light" | "dark" }) — light is the current look.
  Tabs: Init({ tabs = { "Cheats", "Give" } }) + Register({ tab = "Cheats", ... }).
  Confirm: button { confirm = { title, message } } or ModMenu.Confirm({ onConfirm = fn }).
  Persistence: optional ModMenu.ConfigManager (Init / Get / Set). Host-owned; not auto-wired.

  Internals: core/ helpers + widgets/ registry (see README.md).
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Input = require("ModMenu.core.input")
local Config = require("ModMenu.core.config")
local Instance = require("ModMenu.core.instance")
local InputMode = require("ModMenu.core.inputmode")
local Session = require("ModMenu.shell.session")
local Dock = require("ModMenu.shell.dock")
local Tabs = require("ModMenu.shell.tabs")
local Lifecycle = require("ModMenu.shell.lifecycle")
local Registry = require("ModMenu.shell.registry")
local Confirm = require("ModMenu.shell.confirm")
local ConfigStore = require("ModMenu.core.store")

local ModMenu = {}
ModMenu.ConfigManager = ConfigStore

local Debug = Util.Debug

local config = Config.New()

--- Callbacks fired after the menu finishes opening (feature modules use for lazy init).
local onOpenCallbacks = {} ---@type function[]
local onCloseCallbacks = {} ---@type function[]

--- Callbacks fired after SetDock / header picker (hosts persist if they want).
local onDockCallbacks = {} ---@type function[]

local initialized = false

local S = Session.New({
    config = config,
    sections = {},
    values = {},
    onOpenCallbacks = onOpenCallbacks,
    onCloseCallbacks = onCloseCallbacks,
    onDockCallbacks = onDockCallbacks,
})

InputMode.Bind({
    getMenuRoot = function()
        return S.menuRoot
    end,
    getIgnoreLook = function()
        return S.config.ignoreLook == true
    end,
    isMenuOpen = function()
        return S.menuOpen == true
    end,
    getCursorMode = function()
        return S.config.cursorMode
    end,
})

S.makeWidgetCtx = function()
    return {
        values = S.values,
        liveControls = S.liveControls,
        config = S.config,
        umg = Umg,
        Input = Input,
        ValueKey = Util.ValueKey,
        SafeCall = Util.SafeCall,
        IsValid = Util.IsValid,
        ReclaimMenuInput = InputMode.Reclaim,
        EnsureMenuVisible = function()
            Session.EnsureVisible(S)
        end,
        foldCollapsedByKey = S.foldCollapsedByKey,
        ShowConfirm = function(item)
            Confirm.FromButton(S, item)
        end,
    }
end

local function InstallInput()
    local key = config.key or Key.F6
    config.key = key
    if config.keyHint == nil and key == Key.F6 then
        config.keyHint = "F6"
    end
    config.keyName = Config.ResolveEngineKeyName(config) or config.keyName
    if config.inputBackend == "engine" and (type(config.keyName) ~= "string" or config.keyName == "") then
        error('ModMenu.Init: keyName is required when inputBackend is "engine" (Unreal FKey name, e.g. "F7")')
    end
    if config.inputBackend ~= "engine" and (type(config.keyName) ~= "string" or config.keyName == "") then
        config.keyName = tostring(config.keyHint or "F6")
    end
    Instance.ClaimToggleKey(config, config.keyHint or tostring(key))
    Input.SetPointerMode(config.pointerMode)
    Input.Install({
        backend = config.inputBackend,
        key = key,
        keyName = config.keyName,
        onToggle = function()
            Lifecycle.Toggle(S)
        end,
        onOpen = function()
            Lifecycle.Open(S)
        end,
        onClose = function()
            Lifecycle.Close(S)
        end,
        isMenuOpen = function()
            return S.menuOpen == true
        end,
        consoleCommand = config.consoleCommand,
    })
end

--- Initialize / configure this mod's shell. Safe to call multiple times.
---@param opts table|nil
function ModMenu.Init(opts)
    Config.ApplyInit(config, opts, { instanceUnlocked = Instance.GetTag() == nil })
    Util.SetDebug(config.debug == true)
    Instance.Ensure(config)
    Umg.SetDefaults({ fontItem = config.fontItem, colors = config.colors })
    Lifecycle.InstallHooks(S)
    InstallInput()
    initialized = true
    -- Re-apply dock if shell already exists (Init can be called again).
    Dock.ApplyPercentLayout(S.panelSlot, S.config)
    Dock.SyncChrome(S)
    Lifecycle.OnConfigChanged(S)
    local tabList = "off"
    if type(config.tabs) == "table" and #config.tabs > 0 then
        tabList = table.concat(config.tabs, ",")
    end
    Debug(string.format(
        "Init — title=%q key=%s backend=%s cursor=%s pointer=%s dock=%s theme=%s tabs=%s fontScale=%s touchFont=%s fontItem=%s widthFrac=%.2f instance=%q serial=%s z=%d",
        tostring(config.title),
        tostring(config.keyHint or config.key),
        tostring(config.inputBackend),
        tostring(config.cursorMode),
        tostring(config.pointerMode),
        tostring(config.dock),
        tostring(config.theme),
        tabList,
        tostring(config.fontScale),
        tostring(config.touchFontScale),
        tostring(config.fontItem),
        config.widthFrac or 0,
        tostring(Instance.GetTag()),
        tostring(Instance.GetSerial()),
        Instance.GetViewportZ()
    ))
end

--- Process-wide instance tag used in UObject names (e.g. ModMenu_Root_TestMod_1).
---@return string|nil
function ModMenu.GetInstanceId()
    return Instance.GetTag()
end

---@return integer|nil
function ModMenu.GetInstanceSerial()
    return Instance.GetSerial()
end

--- Pin the panel to an edge (session only; no free drag).
---@param side string "left"|"right"|"top"|"bottom"
function ModMenu.SetDock(side)
    Dock.Set(S, side)
end

---@return string
function ModMenu.GetDock()
    return config.dock
end

--- Switch the active tab (Init tabs). Session-only; rebuilds if the menu is open.
---@param name string
---@return boolean
function ModMenu.SetTab(name)
    return Tabs.Select(S, name)
end

--- Current tab name, or nil when Init did not set tabs.
---@return string|nil
function ModMenu.GetTab()
    if not Tabs.Enabled(S) then
        return nil
    end
    Tabs.Ensure(S)
    return S.activeTab
end

--- Register or replace a mod section.
---@param section table
function ModMenu.Register(section)
    if not initialized then
        ModMenu.Init({})
    end
    Registry.Register(S, section)
end

---@param sectionId string
---@param itemId string
---@return any
function ModMenu.Get(sectionId, itemId)
    return Registry.Get(S, sectionId, itemId)
end

--- Update a label item's text (by id) in the section + live widget if present.
---@param sectionId string
---@param itemId string
---@param text string
---@return boolean
function ModMenu.SetLabel(sectionId, itemId, text)
    return Registry.SetLabel(S, sectionId, itemId, text)
end

--- Update a button's caption (section item + live TextBlock if present).
---@param sectionId string
---@param itemId string
---@param text string
---@return boolean
function ModMenu.SetButtonLabel(sectionId, itemId, text)
    return Registry.SetButtonLabel(S, sectionId, itemId, text)
end

--- Enable/disable a button (blocks poll clicks + themed disabled chrome).
---@param sectionId string
---@param itemId string
---@param enabled boolean
---@return boolean
function ModMenu.SetButtonEnabled(sectionId, itemId, enabled)
    return Registry.SetButtonEnabled(S, sectionId, itemId, enabled)
end

--- Button semantic color (Bootstrap-like): default|primary|secondary|success|danger|warning|info.
---@param sectionId string
---@param itemId string
---@param variant string
---@return boolean
function ModMenu.SetButtonVariant(sectionId, itemId, variant)
    return Registry.SetButtonVariant(S, sectionId, itemId, variant)
end

--- Button selected/on chrome (green). Disabled still wins over active.
---@param sectionId string
---@param itemId string
---@param active boolean
---@return boolean
function ModMenu.SetButtonActive(sectionId, itemId, active)
    return Registry.SetButtonActive(S, sectionId, itemId, active)
end

--- Set a value and sync a live checkbox/dropdown/number/textinput if present.
---@param sectionId string
---@param itemId string
---@param value any
function ModMenu.Set(sectionId, itemId, value)
    Registry.Set(S, sectionId, itemId, value)
end

--- Replace dropdown options.
--- Searchable dropdowns refresh rows in place when live; others rebuild the panel.
---@param sectionId string
---@param itemId string
---@param options table
---@param selectedValue any|nil pass false to clear selection
---@return boolean
function ModMenu.SetOptions(sectionId, itemId, options, selectedValue)
    return Registry.SetOptions(S, sectionId, itemId, options, selectedValue)
end

local openOnGameThread = Util.PinFn(function()
    Lifecycle.Open(S)
end)
local closeOnGameThread = Util.PinFn(function()
    Lifecycle.Close(S)
end)
local toggleOnGameThread = Util.PinFn(function()
    Lifecycle.Toggle(S)
end)

--- Register a callback invoked each time the menu opens (after shell is visible).
---@param fn function
function ModMenu.OnOpen(fn)
    if type(fn) ~= "function" then
        error("ModMenu.OnOpen expects a function")
    end
    table.insert(onOpenCallbacks, fn)
end

--- Register a callback invoked after the menu closes.
---@param fn function
function ModMenu.OnClose(fn)
    if type(fn) ~= "function" then
        error("ModMenu.OnClose expects a function")
    end
    table.insert(onCloseCallbacks, fn)
end

--- Register a callback invoked after the dock edge changes (picker or SetDock).
---@param fn fun(side: string)
function ModMenu.OnDockChange(fn)
    if type(fn) ~= "function" then
        error("ModMenu.OnDockChange expects a function")
    end
    table.insert(onDockCallbacks, fn)
end

function ModMenu.Open()
    if not initialized then
        ModMenu.Init({})
    end
    ExecuteInGameThread(openOnGameThread)
end

function ModMenu.Close()
    ExecuteInGameThread(closeOnGameThread)
end

function ModMenu.Toggle()
    if not initialized then
        ModMenu.Init({})
    end
    ExecuteInGameThread(toggleOnGameThread)
end

function ModMenu.IsOpen()
    return S.menuOpen == true
end

--- In-shell confirm modal. onConfirm runs only if the player presses Confirm.
--- Replaces any open confirm (treated as Cancel). Menu must be open.
---@param opts { title?: string, message?: string, confirmLabel?: string, cancelLabel?: string, variant?: string, onConfirm: function, onCancel?: function }
---@return boolean
function ModMenu.Confirm(opts)
    return Confirm.Show(S, opts)
end

function ModMenu.IsConfirmOpen()
    return Confirm.IsOpen(S)
end

--- List registered section ids (debug / tooling).
---@return string[]
function ModMenu.ListSections()
    return Registry.ListSections(S)
end

return ModMenu
