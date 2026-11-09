local addonName, ns = ...

ns.Locales = ns.Locales or {}
ns.L = ns.L or {}

function ns:RegisterLocale(lang, values)
    if not lang or type(values) ~= "table" then return end
    ns.Locales[lang] = values
end

function ns:SwitchLanguage(lang)
    ns.currentLang = lang
end

local function ResolveLanguage()
    local lang = ns.currentLang
    if not lang or lang == "auto" then
        lang = (ns.db and ns.db.display and ns.db.display.language)
            or (LightDamageDB and LightDamageDB.display and LightDamageDB.display.language)
            or (LDCombatStatsDB and LDCombatStatsDB.display and LDCombatStatsDB.display.language)
            or "auto"
    end
    if lang == "auto" then
        local client = GetLocale()
        if client == "zhTW" then
            lang = "zhTW"
        elseif client == "zhCN" then
            lang = "zhCN"
        elseif client == "ruRU" then
            lang = "ruRU"
        elseif client == "koKR" then
            lang = "koKR"
        else
            lang = "enUS"
        end
    end
    return lang
end

-- ---------------------------------------------------------------------------
-- Fonts for a UI language other than the client's.
-- A client's default fonts (STANDARD_TEXT_FONT, UNIT_NAME_FONT,
-- DAMAGE_TEXT_FONT) cover its own script, but not every other one: no
-- Chinese, English or Russian client font has a single Hangul glyph, and the
-- Latin ones have no CJK.  Where the chosen language's script is missing, a
-- text that asked for a client default font gets Blizzard's font for that
-- script instead.  Blizzard's shared font families (Blizzard_Fonts_Shared,
-- the alphabet members) load these four on every client, so they always
-- exist.  covered: the client languages whose default font already shows the
-- language (Simplified Chinese fonts carry the traditional characters too;
-- every client font carries Cyrillic and Latin, so Russian and English never
-- swap).  A font the user picked themselves is never replaced.
-- ---------------------------------------------------------------------------
local LANGUAGE_FONTS = {
    koKR = { font = "Fonts\\2002.TTF",    covered = { koKR = true } },
    zhCN = { font = "Fonts\\ARKai_T.ttf", covered = { zhCN = true } },
    zhTW = { font = "Fonts\\blei00d.TTF", covered = { zhCN = true, zhTW = true } },
}
-- The font each language's own name is drawn in (the language picker), so
-- every choice reads correctly whatever the client.
ns.LANGUAGE_NAME_FONTS = {
    koKR = LANGUAGE_FONTS.koKR.font,
    zhCN = LANGUAGE_FONTS.zhCN.font,
    zhTW = LANGUAGE_FONTS.zhTW.font,
}

local function NormalizedPath(path)
    if type(path) ~= "string" then return nil end
    return (path:lower():gsub("/", "\\"))
end

local function IsClientDefaultFont(path)
    local p = NormalizedPath(path)
    if not p then return false end
    return p == NormalizedPath(STANDARD_TEXT_FONT) or p == NormalizedPath(UNIT_NAME_FONT)
        or p == NormalizedPath(DAMAGE_TEXT_FONT)
end

-- Fixed once the language is resolved at login (a language change reloads).
local resolvedLang
local fontMemo = {}

-- path (nil = the client's standard font) -> the font to draw it with.
function ns:LocaleFont(path)
    path = path or STANDARD_TEXT_FONT
    if resolvedLang then
        local memo = fontMemo[path]
        if memo then return memo end
    end
    local result = path
    local swap = LANGUAGE_FONTS[resolvedLang or ResolveLanguage()]
    if swap and not swap.covered[GetLocale()] and IsClientDefaultFont(path) then
        result = swap.font
    end
    if resolvedLang and type(path) == "string" then fontMemo[path] = result end
    return result
end

-- Every locale file registers its full table at load time, but after login only
-- the resolved language (over the zhCN fallback) is ever read: a language change
-- always reloads the UI.  Resolve it once into ns.L itself, so every L.KEY on a
-- render tick is a plain table hit instead of a metamethod that re-reads the
-- saved settings, then release the per-language tables.
function ns:ReleaseUnusedLocales()
    local keep = ResolveLanguage()
    resolvedLang = keep
    fontMemo = {}
    local primary, fallback = ns.Locales[keep], ns.Locales.zhCN
    for key, value in pairs(fallback or {}) do rawset(ns.L, key, value) end
    if primary ~= fallback then
        for key, value in pairs(primary or {}) do rawset(ns.L, key, value) end
    end
    -- Unknown keys still fall through to the metamethod, which returns the key.
    for lang in pairs(ns.Locales) do ns.Locales[lang] = nil end
end

setmetatable(ns.L, {
    __index = function(_, key)
        if key == nil then return nil end
        local lang = ResolveLanguage()
        local primary = ns.Locales[lang]
        local fallback = ns.Locales.zhCN
        return (primary and primary[key]) or (fallback and fallback[key]) or key
    end,
})

ns:SwitchLanguage("auto")
