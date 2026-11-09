--[[
    Light Damage - DeathTracker.lua
    API-first 死亡追踪器

    fix3:
    - totalAmount 战斗中可能是 secret，不能用 totalAmount > 0 阻断显示
    - sourceGUID 战斗中可能是 secret，不能和玩家 GUID 比较
    - name 是 ConditionalSecret，不能 SafeString 成“未知”，要原样交给 UI:SetText
]]

local addonName, ns = ...
local L = ns.L
local G = ns.DamageMeterGateway

local DT = {}
ns.DeathTracker = DT

local function ReadField(container, key)
    if G then return G:ReadField(container, key) end
    if type(container) ~= "table" then return nil, "missing" end
    local ok, value = pcall(function() return container[key] end)
    if not ok then return nil, "error" end
    return value, type(value) == "nil" and "missing" or "accessible"
end

local function IsSecretValue(v)
    if ns.DamageMeterGateway then
        return not ns.DamageMeterGateway:IsAccessible(v)
    end
    if type(issecretvalue) ~= "function" then return false end
    local ok, ret = pcall(issecretvalue, v)
    return ok and ret and true or false
end

local function SafeNum(v, default)
    if IsSecretValue(v) then return default or 0 end
    return type(v) == "number" and v or (default or 0)
end

local function SafeString(v, default)
    default = default or "?"
    if IsSecretValue(v) then return default end
    if type(v) == "nil" then return default end
    local ok, s = pcall(tostring, v)
    if ok and s and s ~= "" then return s end
    return default
end

local function OptionalNum(v)
    if IsSecretValue(v) then return nil end
    return type(v) == "number" and v or nil
end

local function OptionalString(v)
    if IsSecretValue(v) then return nil end
    return type(v) == "string" and v or nil
end

-- UI 可显示名：如果是 secret string，必须原样保留，不能 tostring / match / gsub。
local function DisplayNameValue(v, default)
    default = default or "?"
    if IsSecretValue(v) then return v end
    if type(v) == "nil" then return default end

    local ok, s = pcall(ns.ShortName, ns, v)
    if ok and s and s ~= "" then return s end

    local ok2, s2 = pcall(tostring, v)
    if ok2 and s2 and s2 ~= "" then return s2 end

    return default
end

local function GetDeathCount(src)
    if type(src) ~= "table" then return nil end
    local v = ReadField(src, "totalAmount")
    if IsSecretValue(v) then return nil end
    if type(v) == "number" then return v end
    return nil
end

local function GetDeathSpecIconID(guid, src)
    local sourceSpecIconID = 0
    if type(src) == "table" then
        sourceSpecIconID = SafeNum(ReadField(src, "specIconID"), 0)
    end
    if sourceSpecIconID > 0 then
        return sourceSpecIconID
    end

    if not IsSecretValue(guid) and type(guid) == "string" and guid == ns.state.playerGUID then
        -- Forever has no global spec API (only C_SpecializationInfo); the
        -- Utils helper resolves either and never throws.
        if ns.GetPlayerSpec then
            local _, icon = ns:GetPlayerSpec()
            if icon then return icon end
        end
    end

    if not IsSecretValue(guid) and type(guid) == "string" then
        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid]
        if cache and cache.specID and type(GetSpecializationInfoByID) == "function" then
            local _, _, _, icon = GetSpecializationInfoByID(cache.specID)
            if icon and icon > 0 then return icon end
        end
    end

    return nil
end

function DT:Init()
    self._apiDeathCache = {}
end

function DT:ClearBuffers()
    self._apiDeathCache = {}
end

-- 兼容旧外部调用：CLEU 死亡链路已废弃。
function DT:RecordIncomingDamage() end
function DT:RecordIncomingHeal() end
function DT:OnUnitDied() end

-- Naming ported from Blizzard_DeathRecap (DeathRecapEntryMixin:GetEventInfo).
-- A melee swing or an environmental hit carries no spell name, so the raw
-- event token ("SWING_DAMAGE") used to be shown instead.  Blizzard names a
-- swing ACTION_SWING and gives it the auto-attack spell (its icon and
-- tooltip), and environmental damage ACTION_ENVIRONMENTAL_DAMAGE_<TYPE>.
local function NameRecapEvent(eventType, spellID, spellName, environmentalType)
    if eventType == "SWING_DAMAGE" then
        local consts = type(Constants) == "table" and Constants.DeathRecapConsts or nil
        local swingID = type(consts) == "table" and consts.SWING_DAMAGE_SPELL_ID or nil
        return swingID or spellID, ACTION_SWING or spellName
    elseif eventType == "ENVIRONMENTAL_DAMAGE" and type(environmentalType) == "string" then
        return spellID, _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. string.upper(environmentalType)] or spellName
    end
    return spellID, spellName
end

-- Death records saved before swings were named still hold the raw token;
-- show the same name a new record gets.  Saved data is left untouched.
function ns:DeathEventLabel(text)
    if text == "SWING_DAMAGE" then return ACTION_SWING or text end
    return text
end

function DT:ParseRecapEvents(recapEvents, maxHP)
    local result = {}
    if type(maxHP) ~= "number" or maxHP <= 0 then maxHP = nil end
    if type(recapEvents) ~= "table" or (G and not G:IsTableAccessible(recapEvents)) then
        return result
    end

    local reversed = {}
    for i = #recapEvents, 1, -1 do
        table.insert(reversed, recapEvents[i])
    end

    for _, ev in ipairs(reversed) do
        if type(ev) ~= "table" or (G and not G:IsTableAccessible(ev)) then
            break
        end
        local spellID   = OptionalNum(ReadField(ev, "spellId"))
        local spellName = OptionalString(ReadField(ev, "spellName"))
        local evType    = OptionalString(ReadField(ev, "event"))
        -- The event type is required to distinguish healing from damage.
        -- Without it, omitting the row is safer than inventing a sign/type.
        if evType then
            local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
            spellID, spellName = NameRecapEvent(evType, spellID, spellName,
                evType == "ENVIRONMENTAL_DAMAGE" and OptionalString(ReadField(ev, "environmentalType")) or nil)
            local amount = OptionalNum(ReadField(ev, "amount"))
            local overkill = OptionalNum(ReadField(ev, "overkill"))
            if type(overkill) == "number" and overkill < 0 then overkill = 0 end
            local hp = OptionalNum(ReadField(ev, "currentHP"))
            local hpPct = (type(hp) == "number" and maxHP) and (hp / maxHP * 100) or nil

            table.insert(result, {
                time      = OptionalNum(ReadField(ev, "timestamp")),
                spellID   = spellID,
                spellName = spellName,
                eventType = evType,
                amount    = type(amount) == "number"
                    and (isHeal and -math.abs(amount) or math.abs(amount)) or nil,
                isHeal    = isHeal,
                srcName   = OptionalString(ReadField(ev, "sourceName")),
                hp        = hp,
                maxHP     = maxHP,
                hpPercent = hpPct,
                overkill  = overkill,
                school    = OptionalNum(ReadField(ev, "school")),
            })
        end
    end

    return result
end

local function GetRecapEvents(recapID)
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return nil end
    if IsSecretValue(recapID) or type(recapID) ~= "number" or recapID <= 0 then return nil end

    local ok, events = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if ok and type(events) == "table" and (not G or G:IsTableAccessible(events)) and #events > 0 then
        return events
    end
    return nil
end

local function GetRecapMaxHealth(recapID)
    if not C_DeathRecap or not C_DeathRecap.GetRecapMaxHealth then return nil end
    local ok, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
    hp = ok and OptionalNum(hp) or nil
    if type(hp) == "number" and hp > 0 then return hp end
    return nil
end

-- A published death recap never changes, but a Deaths cell rebuilt every one
-- of them on every render tick: two C_DeathRecap calls, event parsing and
-- totals per death.  Only the recap-derived part is cached (per-session fields
-- such as the death count differ between Current and Total and are rebuilt by
-- the caller).  Scoped to the meter's raw generation, so a reset that can
-- reuse recap IDs starts clean.  An empty recap is usually one Blizzard has
-- not published yet and is retried on the next refresh rather than cached.
function DT:GetRecapSummary(recapID)
    local generation = G and G:GetRawGeneration() or 0
    local cache = self._apiDeathCache
    if type(cache) ~= "table" or cache._generation ~= generation then
        cache = {_generation = generation}
        self._apiDeathCache = cache
    end
    local entry = cache[recapID]
    if entry then return entry end

    local maxHP = GetRecapMaxHealth(recapID)
    local recapEvents = GetRecapEvents(recapID)
    local events = recapEvents and self:ParseRecapEvents(recapEvents, maxHP) or {}

    local killingAbility, killerName
    for i = #events, 1, -1 do
        if not events[i].isHeal then
            killingAbility = events[i].spellName or events[i].eventType
            killerName = events[i].srcName
            break
        end
    end

    local totalDmg, totalHeal
    for _, ev in ipairs(events) do
        if type(ev.amount) == "number" then
            if ev.isHeal then totalHeal = (totalHeal or 0) + math.abs(ev.amount)
            else totalDmg = (totalDmg or 0) + math.abs(ev.amount) end
        end
    end

    local timeSpan
    if #events >= 2 and type(events[#events].time) == "number"
        and type(events[1].time) == "number" then
        timeSpan = events[#events].time - events[1].time
    end

    entry = {
        maxHP = maxHP, events = events,
        killingAbility = killingAbility, killerName = killerName,
        totalDmg = totalDmg, totalHeal = totalHeal, timeSpan = timeSpan,
        ts = (#events > 0 and type(events[#events].time) == "number")
            and math.floor(events[#events].time) or nil,
    }
    if #events > 0 then cache[recapID] = entry end
    return entry
end

function DT:BuildDeathRecordFromRecapID(recapID, src)
    if IsSecretValue(recapID) or type(recapID) ~= "number" or recapID <= 0 then return nil end

    local guid = type(src) == "table" and ReadField(src, "sourceGUID") or nil
    local rawIsSelf = type(src) == "table" and ReadField(src, "isLocalPlayer") or nil
    local isSelf = not IsSecretValue(rawIsSelf) and rawIsSelf == true

    -- sourceGUID 可能是 secret，不能比较 guid == ns.state.playerGUID。
    if isSelf then
        guid = ns.state.playerGUID or UnitGUID("player")
    elseif IsSecretValue(guid) then
        guid = nil
    end

    local class = OptionalString(type(src) == "table" and ReadField(src, "classFilename") or nil)

    -- 关键：src.name 是 ConditionalSecret，secret 时原样保存给 UI，不要替换成“未知”。
    local rawName = type(src) == "table" and ReadField(src, "name") or nil
    local playerName = DisplayNameValue(rawName, isSelf and (UnitName("player") or L.ME) or L.UNKNOWN)

    local recap = self:GetRecapSummary(recapID)

    return {
        timestamp            = recap.ts,
        gameTime             = nil,
        playerName           = playerName,
        playerGUID           = guid,
        playerClass          = class,
        isSelf               = isSelf,
        killingAbility       = recap.killingAbility,
        killerName           = recap.killerName,
        events               = recap.events,
        lastHP               = nil,
        maxHP                = recap.maxHP,
        totalDamageTaken     = recap.totalDmg,
        totalHealingReceived = recap.totalHeal,
        timeSpan             = recap.timeSpan,
        _fromRecap           = true,
        _recapID             = recapID,
        _specIconID          = GetDeathSpecIconID(guid, src),
        _deathCount          = GetDeathCount(src),
        _deathTimeSeconds    = OptionalNum(type(src) == "table" and ReadField(src, "deathTimeSeconds") or nil),
        _apiGenerated        = true,
        _incomplete          = (#recap.events == 0),
    }
end

local function IsAccessible(v)
    if ns.DamageMeterGateway then return ns.DamageMeterGateway:IsAccessible(v) end
    if type(v) == "nil" then return true end
    return not IsSecretValue(v)
end

local function BuildIncompleteArchiveRecord(recapID, src, reason)
    local guid, guidState = ReadField(src, "sourceGUID")
    if guidState ~= (G and G.ACCESSIBLE or "accessible") or type(guid) ~= "string" then guid = nil end
    local name, nameState = ReadField(src, "name")
    if nameState ~= (G and G.ACCESSIBLE or "accessible") or type(name) ~= "string" then name = nil end
    local class, classState = ReadField(src, "classFilename")
    if classState ~= (G and G.ACCESSIBLE or "accessible") or type(class) ~= "string" then class = nil end
    local isSelf, selfState = ReadField(src, "isLocalPlayer")
    isSelf = selfState == (G and G.ACCESSIBLE or "accessible") and isSelf == true
    if isSelf then
        guid = ns.state.playerGUID or (UnitGUID and UnitGUID("player")) or guid
        name = name or ns.state.playerName or (UnitName and UnitName("player"))
    end
    return {
        timestamp = nil, gameTime = nil,
        playerName = name, playerGUID = guid,
        playerClass = class, isSelf = isSelf,
        killingAbility = nil, killerName = nil, events = {},
        lastHP = nil, maxHP = nil, totalDamageTaken = nil,
        totalHealingReceived = nil, timeSpan = nil,
        _fromRecap = type(recapID) == "number" and recapID > 0,
        _recapID = type(recapID) == "number" and recapID > 0 and recapID or nil,
        _specIconID = GetDeathSpecIconID(guid, src), _deathCount = GetDeathCount(src),
        _deathTimeSeconds = OptionalNum(ReadField(src, "deathTimeSeconds")),
        _apiGenerated = true, _incomplete = true,
        _incompleteReason = reason or (G and G.MISSING or "missing"),
    }
end

-- Archive-only recap builder. Missing recap data is represented explicitly so
-- it cannot block a valid combat-session archive or fabricate event details.
-- Secret recap fields return a SECRET status; the gateway decides whether to
-- retry or accept the incomplete record after its bounded grace window.
function DT:BuildDeathRecordForArchive(recapID, src)
    local pending = G and G.SECRET or "secret"
    local missing = G and G.MISSING or "missing"
    local failed = G and G.ERROR or "error"
    local accessible = G and G.ACCESSIBLE or "accessible"
    local fallback = BuildIncompleteArchiveRecord(recapID, src, missing)
    if not IsAccessible(recapID) then fallback._incompleteReason = pending; return fallback, pending end
    if type(recapID) ~= "number" or recapID <= 0 then return fallback, missing end
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return fallback, missing end

    local ok, recapEvents = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok then fallback._incompleteReason = failed; return fallback, failed end
    if type(recapEvents) == "nil" then return fallback, missing end
    if type(recapEvents) ~= "table" then fallback._incompleteReason = failed; return fallback, failed end
    if G and not G:IsTableAccessible(recapEvents) then
        fallback._incompleteReason = pending
        return fallback, pending
    end

    local detailStatus = accessible
    local function note(status)
        if status == pending then return pending end
        if status == failed then detailStatus = failed
        elseif status ~= accessible and detailStatus == accessible then detailStatus = missing end
        return detailStatus
    end

    local maxHP
    if C_DeathRecap.GetRecapMaxHealth then
        local okHP, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if okHP and not IsAccessible(hp) then fallback._incompleteReason = pending; return fallback, pending end
        if okHP and type(hp) == "number" and hp > 0 then maxHP = hp
        else note(okHP and missing or failed) end
    else
        note(missing)
    end

    local events = {}
    local totalDmg, totalHeal
    for i = #recapEvents, 1, -1 do
        local ev = recapEvents[i]
        if type(ev) ~= "table" then
            note(failed)
        elseif G and not G:IsTableAccessible(ev) then
            fallback._incompleteReason = pending
            return fallback, pending
        else
            -- notApplicable: an absent field is expected for this row and is not
            -- a gap in the recap (a malformed or protected one still is).
            local function eventField(key, expectedType, default, notApplicable)
                local value, state = ReadField(ev, key)
                if state == pending then return nil, pending end
                if state == missing and notApplicable then return default end
                if state ~= accessible then note(state); return default end
                if type(value) ~= expectedType then note(failed); return default end
                return value, accessible
            end

            local eventType, state = eventField("event", "string", nil)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            -- A melee swing or an environmental hit has no spell (Blizzard's
            -- own death recap never reads one for them).
            local noSpell = eventType == "SWING_DAMAGE" or eventType == "ENVIRONMENTAL_DAMAGE"
            local spellID; spellID, state = eventField("spellId", "number", nil, noSpell)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            local spellName; spellName, state = eventField("spellName", "string", nil, noSpell)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            local amount; amount, state = eventField("amount", "number", nil)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            local overkill; overkill, state = eventField("overkill", "number", nil)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            local sourceName; sourceName, state = eventField("sourceName", "string", nil)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            local currentHP; currentHP, state = eventField("currentHP", "number", nil)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            local timestamp; timestamp, state = eventField("timestamp", "number", nil)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end
            local school; school, state = eventField("school", "number", nil)
            if state == pending then fallback._incompleteReason = pending; return fallback, pending end

            if eventType then
                local isHeal = eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL"
                -- environmentalType exists only on environmental rows; reading
                -- it there alone keeps every other row from looking incomplete.
                spellID, spellName = NameRecapEvent(eventType, spellID, spellName,
                    eventType == "ENVIRONMENTAL_DAMAGE" and OptionalString(ReadField(ev, "environmentalType")) or nil)
                if type(overkill) == "number" and overkill < 0 then overkill = 0 end
                local signedAmount = type(amount) == "number"
                    and (isHeal and -math.abs(amount) or math.abs(amount)) or nil
                if type(amount) == "number" then
                    if isHeal then totalHeal = (totalHeal or 0) + math.abs(amount)
                    else totalDmg = (totalDmg or 0) + math.abs(amount) end
                end
                table.insert(events, {
                    time = timestamp, spellID = spellID, spellName = spellName,
                    eventType = eventType, amount = signedAmount,
                    isHeal = isHeal, srcName = sourceName,
                    hp = currentHP, maxHP = maxHP,
                    hpPercent = (type(currentHP) == "number" and type(maxHP) == "number" and maxHP > 0)
                        and (currentHP / maxHP * 100) or nil,
                    overkill = overkill, school = school,
                })
            end
        end
    end

    if #events == 0 then note(missing) end

    local killingAbility, killerName
    for i = #events, 1, -1 do
        if not events[i].isHeal then
            killingAbility = events[i].spellName or events[i].eventType
            killerName = events[i].srcName
            break
        end
    end
    local span
    if #events >= 2 and type(events[#events].time) == "number"
        and type(events[1].time) == "number" then
        span = events[#events].time - events[1].time
    end
    local timestamp = (#events > 0 and type(events[#events].time) == "number")
        and events[#events].time or nil
    fallback.timestamp = timestamp and math.floor(timestamp) or nil
    fallback.killingAbility = killingAbility
    fallback.killerName = killerName
    fallback.events = events
    fallback.maxHP = maxHP
    fallback.totalDamageTaken = totalDmg
    fallback.totalHealingReceived = totalHeal
    fallback.timeSpan = span
    fallback._fromRecap = true
    fallback._recapID = recapID
    fallback._incomplete = detailStatus ~= accessible
    fallback._incompleteReason = fallback._incomplete and detailStatus or nil
    return fallback, detailStatus
end

local function GetDeathSession(sessionType, sessionID)
    if not G then return nil end
    local dmType = Enum.DamageMeterType.Deaths
    return G:GetRawSession(sessionType or Enum.DamageMeterSessionType.Current, sessionID, dmType)
end

local function InsertOrdered(list, record)
    if record then table.insert(list, record) end
end

-- Self first, then the most recent death.  Hoisted so sorting a Deaths cell
-- on every refresh does not allocate a new closure.
local function CompareDeathRecords(a, b)
    if a.isSelf ~= b.isSelf then return a.isSelf end
    local at = a._deathTimeSeconds or 0
    local bt = b._deathTimeSeconds or 0
    if at ~= bt then return at > bt end
    return (a.timestamp or 0) > (b.timestamp or 0)
end

function DT:GetDeathLogFromAPI(sessionType, sessionID, fallbackSegment)
    local session = GetDeathSession(sessionType, sessionID)
    local result = {}

    local sources, sourceState
    if type(session) == "table" and G then
        sources, sourceState = G:ReadTableField(session, "combatSources")
    end
    if sourceState == (G and G.ACCESSIBLE) and type(sources) == "table" then
        local seenRecap = {}
        for _, src in ipairs(sources) do
            if type(src) == "table" and (not G or G:IsTableAccessible(src)) then
                local recapID = SafeNum(ReadField(src, "deathRecapID"), 0)
                local deaths  = GetDeathCount(src)

                -- deathRecapID 是 NeverSecret，只要有 recapID 就生成死亡记录。
                if recapID > 0 and not seenRecap[recapID] then
                    seenRecap[recapID] = true
                    local record = self:BuildDeathRecordFromRecapID(recapID, src)
                    if record then
                        record._deathCount = deaths
                        InsertOrdered(result, record)
                    end
                elseif recapID <= 0 then
                    local guid = ReadField(src, "sourceGUID")
                    local rawIsSelf = ReadField(src, "isLocalPlayer")
                    local isSelf = not IsSecretValue(rawIsSelf) and rawIsSelf == true

                    if isSelf then
                        guid = ns.state.playerGUID or UnitGUID("player")
                    elseif IsSecretValue(guid) then
                        guid = nil
                    end

                    InsertOrdered(result, {
                        timestamp            = nil,
                        gameTime             = nil,
                        playerName           = DisplayNameValue(ReadField(src, "name"), isSelf and (UnitName("player") or L.ME) or L.UNKNOWN),
                        playerGUID           = guid,
                        playerClass          = OptionalString(ReadField(src, "classFilename")),
                        isSelf               = isSelf,
                        killingAbility       = nil,
                        killerName           = nil,
                        events               = {},
                        lastHP               = nil,
                        maxHP                = nil,
                        totalDamageTaken     = nil,
                        totalHealingReceived = nil,
                        timeSpan             = nil,
                        _fromRecap           = false,
                        _recapID             = nil,
                        _specIconID          = GetDeathSpecIconID(guid, src),
                        _deathCount          = deaths,
                        _deathTimeSeconds    = OptionalNum(ReadField(src, "deathTimeSeconds")),
                        _apiGenerated        = true,
                        _incomplete          = true,
                    })
                end
            end
        end
    end

    if #result == 0 and fallbackSegment and fallbackSegment.deathLog then
        return fallbackSegment.deathLog
    end

    table.sort(result, CompareDeathRecords)

    return result
end

local function InferAPIContext(segment)
    local segs = ns.Segments
    if not segs then return nil, nil end

    if segment and segment._sessionID then
        return nil, segment._sessionID
    end
    if segment and segs.overall and segment == segs.overall then
        return Enum.DamageMeterSessionType.Overall, nil
    end
    if segment and segs.current and segment == segs.current and ns.state.inCombat then
        return Enum.DamageMeterSessionType.Current, nil
    end

    if not segment then
        if segs.IsViewingOverall and segs:IsViewingOverall() then
            return Enum.DamageMeterSessionType.Overall, nil
        end
        if segs.IsViewingCurrent and segs:IsViewingCurrent() and ns.state.inCombat then
            return Enum.DamageMeterSessionType.Current, nil
        end
        local viewSeg = segs.GetViewSegment and segs:GetViewSegment()
        if viewSeg and viewSeg._sessionID then
            return nil, viewSeg._sessionID
        end
    end

    return nil, nil
end

function DT:GetDeathLog(segment)
    if not segment and ns.Segments then
        segment = ns.Segments:GetViewSegment()
    end

    local sessionType, sessionID = InferAPIContext(segment)
    if sessionType or sessionID then
        return self:GetDeathLogFromAPI(sessionType, sessionID, segment)
    end

    return segment and segment.deathLog or {}
end

function DT:GetDeathDetail(segment, index)
    local log = self:GetDeathLog(segment)
    return log and log[index]
end

function DT:GetSelfDeaths(segment)
    local log = self:GetDeathLog(segment)
    local result = {}
    for _, dr in ipairs(log) do
        if dr.isSelf then table.insert(result, dr) end
    end
    return result
end

function DT:GetOtherDeaths(segment)
    local log = self:GetDeathLog(segment)
    local result = {}
    for _, dr in ipairs(log) do
        if not dr.isSelf then table.insert(result, dr) end
    end
    return result
end

function DT:OnPlayerDead()
    C_Timer.After(0.2, function()
        if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
        if ns.DetailView and ns.DetailView:IsVisible() then ns.DetailView:Refresh() end
    end)
    C_Timer.After(1.0, function()
        if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
        if ns.DetailView and ns.DetailView:IsVisible() then ns.DetailView:Refresh() end
    end)
end

function DT:RefreshSelfDeathFromRecap()
    if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
end
