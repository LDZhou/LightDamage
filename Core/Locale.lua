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
        else
            lang = "enUS"
        end
    end
    return lang
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
