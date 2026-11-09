--[[
    Light Damage - Utils.lua
    工具函数
]]

local addonName, ns = ...
local L = ns.L

-- 职业颜色
ns.CLASS_COLORS = {
    WARRIOR     = {0.78, 0.61, 0.43}, PALADIN     = {0.96, 0.55, 0.73},
    HUNTER      = {0.67, 0.83, 0.45}, ROGUE       = {1.00, 0.96, 0.41},
    PRIEST      = {1.00, 1.00, 1.00}, DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN      = {0.00, 0.44, 0.87}, MAGE        = {0.25, 0.78, 0.92},
    WARLOCK     = {0.53, 0.53, 0.93}, MONK        = {0.00, 1.00, 0.60},
    DRUID       = {1.00, 0.49, 0.04}, DEMONHUNTER = {0.64, 0.19, 0.79},
    EVOKER      = {0.20, 0.58, 0.50},
}

-- 暴雪职业图标 (回退用)
ns.CLASS_ICONS = {
    WARRIOR=132355, PALADIN=135490, HUNTER=132222, ROGUE=132320,
    PRIEST=135940, DEATHKNIGHT=135771, SHAMAN=135962, MAGE=135932,
    WARLOCK=136145, MONK=608951, DRUID=132115, DEMONHUNTER=1260827,
    EVOKER=4567212,
}

-- 自定义图标包: specID → 文件名 stem
ns.SPEC_ICON_KEYS = {
    [62]="Mage_TouchOfTheArchmage", [63]="Mage_FiredUp", [64]="Mage_HandOfFrost",
    [65]="Paladin_BeaconOfTheSavior", [66]="Paladin_GloryOfTheVanguard", [70]="Paladin_LightWithin",
    [71]="Warrior_MasterOfWarfare", [72]="Warrior_RampagingBerserker", [73]="Warrior_Phalanx",
    [102]="Druid_AscendanceEclipses", [103]="Druid_UnseenPredator", [104]="Druid_WildGuardian", [105]="Druid_Everbloom",
    [250]="DeathKnight_DanceOfMidnight", [251]="DeathKnight_ChosenOfTheFrostbrood", [252]="DeathKnight_ForbiddenKnowledge",
    [253]="Hunter_KillFrenzy", [254]="Hunter_DeadlyInsight", [255]="Hunter_RaptorSwipe",
    [256]="Priest_VoidShield", [257]="Priest_Benediction", [258]="Priest_VoidApparitions",
    [259]="Rogue_AncientArts", [260]="Rogue_Gravedigger", [261]="Rogue_Implacable",
    [262]="Shaman_FeedbackLoop", [263]="Shaman_StormUnleashed", [264]="Shaman_StormstreamTotem",
    [265]="Warlock_ShadowsOfNathreza", [266]="Warlock_DominionOfArgus", [267]="Warlock_EmbersOfNihilam",
    [268]="Monk_BringMeAnother", [269]="Monk_TigereyeBrew", [270]="Monk_Spiritfont",
    [577]="DemonHunter_EternalHunt", [581]="DemonHunter_UntetheredRage", [1480]="DemonHunter_Midnight",
    [1467]="Evoker_RisingFury", [1468]="Evoker_MerithrasBlessing", [1473]="Evoker_Duplicate",
}

-- 图标包专用覆盖: 个别素材包的文件名或图标归属与通用表不同
ns.SPEC_ICON_PACK_OVERRIDES = {
    apex = {
        [72]="Warrior_RampagingBerserker2",
        [259]="Rogue_Implacable",
        [261]="Rogue_AncientArts",
    },
}

-- 自定义图标包路径前缀
local ICON_ROOT = "Interface\\AddOns\\LightDamage\\Textures\\icons\\"

-- NPC GUID 判断（用于区分玩家与生物，避免 NPC 被误染战士色）
-- 用首字节快速过滤，避免 4 次 string.match 调用
local NPC_GUID_PREFIX_BYTES = {
    [67] = true,  -- 'C' Creature
    [86] = true,  -- 'V' Vehicle
    [80] = true,  -- 'P' Pet
    [71] = true,  -- 'G' GameObject
}
function ns:IsNPCGUID(guid)
    if not guid or #guid < 5 then return false end
    local b = guid:byte(1)
    if not NPC_GUID_PREFIX_BYTES[b] then return false end
    -- 只在首字节命中时才做精确匹配，避免 Player- 之类误判
    if b == 67 then return guid:byte(2) == 114 -- "Cr"eature
    elseif b == 86 then return guid:byte(2) == 101 -- "Ve"hicle
    elseif b == 80 then return guid:byte(2) == 101 -- "Pe"t
    elseif b == 71 then return guid:byte(2) == 97  -- "Ga"meObject
    end
    return false
end

function ns:GetClassColor(class)
    return ns.CLASS_COLORS[class] or {0.5, 0.5, 0.5}
end

function ns:GetClassHex(class)
    local c = ns:GetClassColor(class)
    return string.format("|cff%02x%02x%02x", c[1]*255, c[2]*255, c[3]*255)
end

-- 统一图标查询: 根据当前图标包返回 specID 对应的图标
-- 返回 nil 表示完全无图标 (调用者应自行决定是否显示职业图标兜底)
function ns:GetSpecIcon(specID, class, specIconID)
    local pack = (ns.db and ns.db.display and ns.db.display.iconPack) or "default"
    local gateway = ns.DamageMeterGateway
    -- CombatSource.specIconID is public on Retail but may be a SecretValue on
    -- Forever.  This helper returns ordinary/cached data only; callers that
    -- own a secret-capable Texture pass protected values straight to it.
    local publicIcon = (not gateway or gateway:IsAccessibleFast(specIconID))
        and type(specIconID) == "number" and specIconID > 0 and specIconID or nil

    if pack == "default" then
        -- ★ 优先用 API 直接给的图标值 (队友自己都靠这个, 零延迟、不需要 inspect)
        if publicIcon then return publicIcon end
        -- 没拿到 specIconID 时再走 specID 路径 (主要给本地玩家自己用)
        if specID and type(GetSpecializationInfoByID) == "function" then
            local _, _, _, icon = GetSpecializationInfoByID(specID)
            if icon then return icon end
        end
        return class and ns.CLASS_ICONS[class] or nil
    end

    -- 自定义图标包: specID -> tga 文件名映射
    -- specID 缺失时, 用 specIconID 反查 specID
    if not specID and publicIcon and ns.ICON_TO_SPECID then
        specID = ns.ICON_TO_SPECID[publicIcon]
    end
    if specID then
        local packOverrides = ns.SPEC_ICON_PACK_OVERRIDES and ns.SPEC_ICON_PACK_OVERRIDES[pack]
        local stem = (packOverrides and packOverrides[specID]) or ns.SPEC_ICON_KEYS[specID]
        if stem then
            return ICON_ROOT .. pack .. "\\" .. stem
        end
    end
    -- ★ 自定义包匹配失败时, 用 API 给的 specIconID 作二级兜底 (起码能看到一个图标)
    if publicIcon then return publicIcon end
    return class and ns.CLASS_ICONS[class] or nil
end


-- ============================================================
-- 一次性建立 specIconID -> specID 反查表
-- 用于自定义图标包: 当 API 只返回 specIconID 时反查 specID
-- 在 PLAYER_LOGIN 后调用一次即可, 数据不会变
-- ============================================================
-- ============================================================
-- Specialization API, Forever-safe.
-- Forever exposes specializations only as C_SpecializationInfo.*.  The bare
-- globals (GetSpecialization, GetSpecializationInfo, ...) come from
-- Blizzard_DeprecatedSpecialization, which Forever never loads
-- (AllowLoadGameType: classic, standard), so on Forever every global-only
-- lookup silently found nothing -- or threw where it was unguarded.  All spec
-- reads go through these helpers; they prefer the namespaced function exactly
-- as Forever's own UI does, keep the global for clients that still have it,
-- and treat a missing, failing or protected answer as "unknown".
-- tools/forever_api_check.js rejects the deprecated globals anywhere else.
-- ============================================================
local function SpecAPI(name)
    local lib = C_SpecializationInfo
    local fn = type(lib) == "table" and lib[name] or nil
    if type(fn) ~= "function" then fn = _G[name] end
    return type(fn) == "function" and fn or nil
end

local function PublicNumber(value)
    if type(value) == "nil" then return nil end
    if type(canaccessvalue) == "function" and canaccessvalue(value) ~= true then return nil end
    if type(issecretvalue) == "function" and issecretvalue(value) == true then return nil end
    if type(value) == "number" and value > 0 then return value end
    return nil
end

-- The player's current specID and spec icon, or nil.
function ns:GetPlayerSpec()
    local getIndex, getInfo = SpecAPI("GetSpecialization"), SpecAPI("GetSpecializationInfo")
    if not getIndex or not getInfo then return nil end
    local ok, index = pcall(getIndex)
    index = ok and PublicNumber(index) or nil
    if not index then return nil end
    local okInfo, specID, _, _, icon = pcall(getInfo, index)
    if not okInfo then return nil end
    specID = PublicNumber(specID)
    if not specID then return nil end
    return specID, PublicNumber(icon)
end

-- An inspected unit's specID, or nil (including while it is protected).
function ns:GetInspectSpecID(unit)
    local fn = SpecAPI("GetInspectSpecialization")
    if not fn then return nil end
    local ok, specID = pcall(fn, unit)
    return ok and PublicNumber(specID) or nil
end

function ns:BuildIconToSpecIDMap()
    if ns.ICON_TO_SPECID then return end
    ns.ICON_TO_SPECID = {}
    local numSpecs = SpecAPI("GetNumSpecializationsForClassID")
    if not numSpecs or type(GetSpecializationInfoForClassID) ~= "function" then return end
    local classIDs
    local allClassIDs = SpecAPI("GetAllClassIDs")
    if allClassIDs then
        local ok, ids = pcall(allClassIDs)
        if ok and type(ids) == "table" then classIDs = ids end
    end
    if not classIDs and type(GetNumClasses) == "function" then
        classIDs = {}
        for classID = 1, GetNumClasses() do classIDs[classID] = classID end
    end
    if not classIDs then return end
    for _, classID in ipairs(classIDs) do
        local okCount, n = pcall(numSpecs, classID)
        n = okCount and PublicNumber(n) or 0
        for specIdx = 1, n do
            local okInfo, sid, _, _, icon = pcall(GetSpecializationInfoForClassID, classID, specIdx)
            sid, icon = okInfo and PublicNumber(sid), okInfo and PublicNumber(icon)
            if icon and sid then
                ns.ICON_TO_SPECID[icon] = sid
            end
        end
    end
end

-- 学校颜色 (伤害类型)
ns.SCHOOL_COLORS = {
    [1]  = {0.6, 0.6, 0.6},   -- Physical
    [2]  = {1.0, 0.9, 0.5},   -- Holy
    [4]  = {1.0, 0.5, 0.0},   -- Fire
    [8]  = {0.3, 1.0, 0.3},   -- Nature
    [16] = {0.5, 0.5, 1.0},   -- Frost
    [32] = {0.5, 0.0, 0.5},   -- Shadow
    [64] = {1.0, 0.5, 1.0},   -- Arcane
}

-- 格式化数字：archived/local values take the same rules as live API values
-- (see "Number format" below), so a fight reads the same before and after
-- it is archived.
function ns:FormatNumber(num)
    return ns.AbbrevNumber(num)
end

-- 格式化时间
function ns:FormatTime(sec)
    if not sec or sec <= 0 then return "0:00" end
    return string.format("%d:%02d", math.floor(sec/60), math.floor(sec%60))
end

-- 格式化时间戳 (HH:MM:SS)
function ns:FormatTimestamp(t)
    if not t then return "--:--:--" end
    return date("%H:%M:%S", t)
end

-- 安全数值读取 (12.0 Secret Values 兼容)
function ns:SafeNum(val)
    if val == nil then return 0 end
    if type(val) == "number" then return val end
    local ok, n = pcall(tonumber, val)
    return (ok and n) or 0
end

function ns:SafeStr(val)
    if type(val) == "string" then return val end
    if val == nil then return "" end
    local ok, s = pcall(tostring, val)
    return (ok and s) or ""
end

function ns:NormalizeFontOutline(outline)
    if not outline or outline == "" then return "" end
    local compact = tostring(outline):upper():gsub("%s+", ""):gsub(",", "")
    if compact == "OUTLINEMONOCHROME" then
        return "OUTLINE, MONOCHROME"
    elseif compact == "THICKOUTLINEMONOCHROME" then
        return "THICKOUTLINE, MONOCHROME"
    end
    return outline
end

-- GUID相关
function ns:IsPlayerGUID(guid)
    return guid and guid:match("^Player%-") ~= nil
end

function ns:IsPetGUID(guid)
    return guid and (guid:match("^Pet%-") ~= nil or guid:match("^Creature%-") ~= nil)
end

-- ============================================================
-- Flag 常量
-- ============================================================
local AFFILIATION_MASK = 0x0000000F
local AFF_MINE         = 0x00000001
local AFF_PARTY        = 0x00000002
local AFF_RAID         = 0x00000004

local FLAG_PLAYER      = 0x00000400
local FLAG_PET         = 0x00001000
local FLAG_GUARDIAN    = 0x00002000

function ns:IsGroupUnit(flags, guid)
    if guid and guid == ns.state.playerGUID then
        return true
    end
    if not flags then return false end
    local aff = bit.band(flags, AFFILIATION_MASK)
    return aff == AFF_MINE or aff == AFF_PARTY or aff == AFF_RAID
end

function ns:IsPlayerType(flags)
    return flags ~= nil and bit.band(flags, FLAG_PLAYER) ~= 0
end

function ns:IsPetType(flags)
    return flags ~= nil and bit.band(flags, FLAG_PET + FLAG_GUARDIAN) ~= 0
end

-- ============================================================
-- GUID → Unit 缓存
-- ============================================================
ns._guidUnitCache    = {}
ns._guidUnitCacheAge = 0

local function IsPublicGUID(guid)
    if type(guid) ~= "string" then return false end
    if ns.DamageMeterGateway then return ns.DamageMeterGateway:IsAccessible(guid) end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, guid)
        if not ok or secret then return false end
    end
    return true
end

function ns:InvalidateGUIDCache()
    ns._guidUnitCache    = {}
    ns._guidUnitCacheAge = GetTime()
end

function ns:FindUnitByGUID(guid)
    if not IsPublicGUID(guid) then return nil end
    if guid == ns.state.playerGUID then return "player" end

    local cached = ns._guidUnitCache[guid]
    if cached and UnitExists(cached) and UnitGUID(cached) == guid then
        return cached
    end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or math.max(0, GetNumGroupMembers() - 1)
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local g = UnitGUID(unit)
            if IsPublicGUID(g) then
                ns._guidUnitCache[g] = unit
                if g == guid then return unit end
            end
        end
    end
    return nil
end

-- 获取宠物主人GUID
function ns:FindPetOwner(petGUID)
    if not IsPublicGUID(petGUID) then return nil end
    local playerPetGUID = UnitExists("pet") and UnitGUID("pet")
    if IsPublicGUID(playerPetGUID) and playerPetGUID == petGUID then
        return UnitGUID("player")
    end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or math.max(0, GetNumGroupMembers() - 1)
    for i = 1, count do
        local petUnit = prefix .. "pet" .. i
        local unitPetGUID = UnitExists(petUnit) and UnitGUID(petUnit)
        if IsPublicGUID(unitPetGUID) and unitPetGUID == petGUID then
            return UnitGUID(prefix .. i)
        end
    end
    return nil
end

function ns:ShortName(name)
    if not name then return "?" end
    return name
end

function ns:DisplayName(name)
    -- A name without its realm, never shortened (titles, tooltips, killers).
    -- Protected names must remain opaque.  Ambiguate is explicitly allowed
    -- to consume them; string matching, substring operations and measuring
    -- are not.
    local protected=issecretvalue and issecretvalue(name)
    if protected then
        if Ambiguate then local ok,result=pcall(Ambiguate,name,"short"); if ok then return result end end
        return name
    end
    if not name or name=="" then return "?" end
    if Ambiguate then
        local ok, result = pcall(Ambiguate, name, "short")
        if ok and result then return result end
    end
    return name
end

-- ============================================================
-- Player name format (WoW Forever surnames)
-- ============================================================
-- Forever characters carry a surname.  UnitName hands it back as its second
-- value (the realm slot on retail) and Blizzard's own frames show
-- "First Last".  The meter's Name Format shapes PLAYERS' names only:
--   "full"  First Last          "first" First
--   "last"  Last                "abbr"  F. Last
--   number  at most that many characters (UTF-8 aware)
-- A protected (secret) name cannot be inspected, so another player's name
-- shows whole while it is protected (in combat).  Your own row reads your
-- unit name instead, so it keeps its format in and out of combat.  Shaped
-- names are cached (256 per format), so repaints build no strings.
do
    local floor = math.floor
    local SEP = " "
    if type(Constants) == "table" and type(Constants.CharacterNameSeparatorConsts) == "table" then
        local sep = Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
        if type(sep) == "string" and sep ~= "" then SEP = sep end
    end
    local SEP_PATTERN = SEP ~= " " and SEP:gsub("%W", "%%%0") or nil
    local NAMED_FORMATS = { full = true, first = true, last = true, abbr = true }
    local MAX_COUNT = 99

    local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
    local function IsCount(v) return type(v) == "number" and v >= 1 and v <= MAX_COUNT and v == floor(v) end

    function ns:IsValidNameFormat(v) return NAMED_FORMATS[v] == true or IsCount(v) end

    function ns:GetNameFormat()
        local display = ns.db and ns.db.display
        local v = display and display.nameFormat
        if v == nil or not ns:IsValidNameFormat(v) then return "full" end
        return v
    end

    -- Characters, not bytes: a CJK glyph is three bytes.
    local function Utf8Prefix(text, n)
        local bytes, i, chars = #text, 1, 0
        while i <= bytes do
            if chars == n then return text:sub(1, i - 1) end
            local b = text:byte(i)
            i = i + ((b < 128 and 1) or (b < 224 and 2) or (b < 240 and 3) or 4)
            chars = chars + 1
        end
        return text
    end
    ns.Utf8Prefix = Utf8Prefix

    local joined = {}   -- [name][surname] = "name<SEP>surname"
    function ns:WithSurname(name, surname, ignorePreference)
        if IsSecret(name) or IsSecret(surname) then return name end
        if type(name) ~= "string" or type(surname) ~= "string" or surname == "" then return name end
        if not ignorePreference and C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname
            and not C_PlayerInfo.ShouldDisplaySurname() then
            -- Blizzard's show-surname preference covers your own surname only.
            local myName, mySurname = UnitName("player")
            if name == myName and surname == mySurname then return name end
        end
        local row = joined[name]
        if not row then row = {}; joined[name] = row end
        local full = row[surname]
        if not full then
            local tail = SEP .. surname
            -- Some units already carry the surname in the first value.
            full = (name:sub(-#tail) == tail) and name or (name .. tail)
            row[surname] = full
        end
        return full
    end

    -- Your own display name, as Blizzard's frames show it.
    function ns:LocalPlayerFullName()
        local name, surname = UnitName("player")
        if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
        return ns:WithSurname(name, surname)
    end

    local short, counts = {}, {}   -- [format][name] = shaped name
    function ns:ShortenName(name, mode)
        if IsSecret(name) or type(name) ~= "string" or mode == "full" or not ns:IsValidNameFormat(mode) then
            return name
        end
        local cache = short[mode]
        if not cache then cache = {}; short[mode] = cache; counts[mode] = 0 end
        local s = cache[name]
        if s then return s end
        local words = SEP_PATTERN and name:gsub(SEP_PATTERN, " ") or name
        if mode == "first" then
            s = words:match("^%s*(%S+)")
        elseif mode == "last" then
            s = words:match("(%S+)%s*$")
        elseif mode == "abbr" then
            local parts = {}
            for word in words:gmatch("%S+") do parts[#parts + 1] = word end
            if #parts >= 2 then
                for i = 1, #parts - 1 do parts[i] = Utf8Prefix(parts[i], 1) .. "." end
                s = table.concat(parts, " ")
            end
        else
            -- No trailing space where the cut lands between two words.
            s = Utf8Prefix(words, mode):match("^(.-)%s*$")
        end
        if not s or s == "" then s = name end
        if counts[mode] >= 256 then wipe(cache); counts[mode] = 0 end
        cache[name] = s
        counts[mode] = counts[mode] + 1
        return s
    end

    -- A meter row's name.  isPlayer: the row is a player (an NPC's or a pet's
    -- name stays whole -- "Rot Hide Gnoll" never reads "Rot").  isSelf: your
    -- own row, which reads your unit name whenever a format is set.
    function ns:RowDisplayName(name, isPlayer, isSelf)
        local mode = ns:GetNameFormat()
        if mode == "full" or not isPlayer then return ns:DisplayName(name) end
        if isSelf then
            local own = ns:LocalPlayerFullName()
            if own then return ns:ShortenName(own, mode) end
        end
        if IsSecret(name) then return ns:DisplayName(name) end
        return ns:ShortenName(ns:DisplayName(name), mode)
    end
end

-- 模式名称映射
ns.MODE_NAMES = {
    damage      = "DAMAGE",
    healing     = "HEALING",
    damageTaken = "DAMAGE_TAKEN",
    deaths      = "DEATHS",
    interrupts  = "INTERRUPTS",
    dispels     = "DISPELS",
    avoidableDamageTaken = "AVOIDABLE_DAMAGE_TAKEN",
    enemyDamageTaken = "ENEMY_DAMAGE_TAKEN",
}

ns.MODE_SHORT = {
    damage          = "DAMAGE_SHORT",
    healing         = "HEALING_SHORT",
    damageTaken     = "DAMAGE_TAKEN_SHORT",
    deaths          = "DEATHS_SHORT",
    interrupts      = "INTERRUPTS_SHORT",
    dispels         = "DISPELS_SHORT",
    avoidableDamageTaken = "AVOIDABLE_DAMAGE_TAKEN_SHORT",
    enemyDamageTaken= "ENEMY_SHORT",
}

ns.MODE_UNITS = {
    damage          = "DPS",
    healing         = "HPS",
    damageTaken     = "DTPS",
    avoidableDamageTaken = "DTPS",
    enemyDamageTaken= "DPS",
}

-- Presentation order for the bottom bar, its More menu and the bottom-bar
-- settings list.  Offence first, then the utility counters, then the three
-- damage-received statistics from broadest to most specific.
ns.MODE_ORDER = {
    "damage", "healing", "interrupts", "dispels", "deaths",
    "damageTaken", "avoidableDamageTaken", "enemyDamageTaken",
}

function ns:NextMode(current)
    for i, m in ipairs(ns.MODE_ORDER) do
        if m == current then
            return ns.MODE_ORDER[(i % #ns.MODE_ORDER) + 1]
        end
    end
    return "damage"
end

function ns:FormatValueStr(perSec, total, mode, dur)
    local unit = ns.MODE_UNITS[mode]
    if unit and dur and dur > 0 then
        return string.format("%s(%s)", ns.AbbrevRate(perSec), ns:FormatNumber(total))
    else
        return ns:FormatNumber(total)
    end
end

-- ============================================================
-- 工具函数 (从原 Core.lua 搬入)
-- ============================================================
function ns:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = CopyTable(v)
            else
                ns:MergeDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- ============================================================
-- Number format: a straight port of EllesmereUI
-- ============================================================
-- EllesmereUI_NumberFormat.lua, Precision "standard" on WoW Forever, as
-- EllesmereUI.AbbreviateNumber uses it for its Damage Meters: the client's
-- AbbreviateNumbers with one cached CreateAbbreviateConfig, for public and
-- protected values alike.  The breakpoint tables and TrimTiers below are
-- copied from that file unchanged.
--   9999 stays "9999", 10123 reads "10.1K", 1.23M, 1.23B; 1.23万, 1.23亿.
-- Per-second rates follow EUI_DamageMeters_Format.lua FormatBarValue: a public
-- rate below 1 reads as 1; a protected rate cannot be compared and is passed
-- through as it is (EllesmereUI: "secret sessions are short, so perSec is
-- never sub-1 anyway").
do
    local tonumber = tonumber

    local function EnglishBreakpoints()
        return {
            { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
            { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
        }
    end

    -- Glyph order per locale: thousand, wan, yi.
    local CJK_GLYPHS = {
        zhCN = { "千", "万", "亿" },
        zhTW = { "千", "萬", "億" },
        koKR = { "천", "만", "억" },
    }

    local function CJKBreakpoints(g)
        return {
            { breakpoint = 100000000, abbreviation = g[3], significandDivisor = 1000000, fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 10000,     abbreviation = g[2], significandDivisor = 100,     fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1000,      abbreviation = g[1], significandDivisor = 100,     fractionDivisor = 10,  abbreviationIsGlobal = false },
            { breakpoint = 1,         abbreviation = "",   significandDivisor = 1,       fractionDivisor = 1,   abbreviationIsGlobal = false },
        }
    end

    -- rows (largest first) -> a new list without the tiers below threshold, bar the
    -- plain one (breakpoint 1 or 0). When nothing then starts AT threshold, the
    -- largest dropped tier moves up to start there, keeping its divisors: at 10,000
    -- the English K tier still reads 12345 as "12.3K", while the CJK thousands tier
    -- just goes (the wan tier already starts at 10,000). A moved row is edited in
    -- place, so pass freshly built rows.
    local function TrimTiers(rows, threshold)
        local out = {}
        for i = 1, #rows do
            local row = rows[i]
            local bp = row.breakpoint
            if bp >= threshold or bp <= 1 then
                out[#out + 1] = row
            elseif not out[1] or out[#out].breakpoint > threshold then
                row.breakpoint = threshold
                out[#out + 1] = row
            end
        end
        return out
    end

    -- WoW Forever's numbers are small: nothing below 10,000 abbreviates.
    local FOREVER_THRESHOLD = 10000

    -- EllesmereUI keys the glyphs on its effective locale; LightDamage's is its
    -- own language setting.
    local function EffectiveLang()
        local lang = ns.currentLang
        if not lang or lang == "auto" then
            lang = (ns.db and ns.db.display and ns.db.display.language) or "auto"
        end
        if lang == "auto" then lang = GetLocale() end
        return lang
    end

    -- EllesmereUI's BuildConfig: built once per language, then a warm call is
    -- an upvalue check.
    local meterOpts, builtFor
    local function MeterOptions()
        local lang = EffectiveLang()
        if meterOpts and lang == builtFor then return meterOpts end
        local g = CJK_GLYPHS[lang]
        local rows = g and CJKBreakpoints(g) or EnglishBreakpoints()
        meterOpts = { config = CreateAbbreviateConfig(TrimTiers(rows, FOREVER_THRESHOLD)) }
        builtFor = lang
        return meterOpts
    end
    ns.NumberFormatOptions = MeterOptions

    local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

    -- EllesmereUI.AbbreviateNumber.  A protected value goes to the client as
    -- it is: comparing one, even with nil, raises.
    function ns.AbbrevNumber(n)
        local opts = MeterOptions()
        if IsSecret(n) then return AbbreviateNumbers(n, opts) end
        return AbbreviateNumbers(tonumber(n) or 0, opts)
    end
    ns.AbbrevProtectedNumber = ns.AbbrevNumber

    -- EUI_DamageMeters_Format.lua FormatBarValue: "clamp to a min of 1, but only
    -- for a plain number -- never compare a secret value".
    function ns.AbbrevRate(n)
        if not IsSecret(n) and type(n) == "number" and n < 1 then n = 1 end
        return ns.AbbrevNumber(n)
    end
end
