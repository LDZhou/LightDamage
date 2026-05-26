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

local DT = {}
ns.DeathTracker = DT

local function IsSecretValue(v)
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
    if v == nil then return default end
    if IsSecretValue(v) then return default end
    local ok, s = pcall(tostring, v)
    if ok and s and s ~= "" then return s end
    return default
end

-- UI 可显示名：如果是 secret string，必须原样保留，不能 tostring / match / gsub。
local function DisplayNameValue(v, default)
    default = default or "?"
    if v == nil then return default end
    if IsSecretValue(v) then return v end

    local ok, s = pcall(ns.ShortName, ns, v)
    if ok and s and s ~= "" then return s end

    local ok2, s2 = pcall(tostring, v)
    if ok2 and s2 and s2 ~= "" then return s2 end

    return default
end

local function GetDeathCount(src)
    if not src then return 1 end
    local v = src.totalAmount
    if IsSecretValue(v) then return 1 end
    if type(v) == "number" and v > 0 then return v end
    return 1
end

local function GetDeathSpecIconID(guid, src)
    if src and src.specIconID and src.specIconID > 0 then
        return src.specIconID
    end

    if guid and not IsSecretValue(guid) and guid == ns.state.playerGUID then
        local specIdx = GetSpecialization()
        if specIdx then
            local _, _, _, icon = GetSpecializationInfo(specIdx)
            if icon and icon > 0 then return icon end
        end
    end

    if guid and not IsSecretValue(guid) then
        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid]
        if cache and cache.specID then
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

function DT:ParseRecapEvents(recapEvents, maxHP)
    local result = {}
    maxHP = maxHP or 1

    local reversed = {}
    for i = #recapEvents, 1, -1 do
        table.insert(reversed, recapEvents[i])
    end

    for _, ev in ipairs(reversed) do
        local spellID   = SafeNum(ev.spellId, 0)
        local spellName = SafeString(ev.spellName, "")
        local evType    = SafeString(ev.event, "")
        local isHeal    = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
        local amount    = SafeNum(ev.amount, 0)
        local overkill  = SafeNum(ev.overkill, 0)
        if overkill < 0 then overkill = 0 end

        if spellName == "" then
            if isHeal then spellName = L["治疗"]
            elseif evType == "SWING_DAMAGE" then spellName = L["近战"]
            else spellName = L["未知"] end
        end

        local hp    = SafeNum(ev.currentHP, 0)
        local hpPct = maxHP > 0 and (hp / maxHP * 100) or 0

        table.insert(result, {
            time      = SafeNum(ev.timestamp, GetTime()),
            spellID   = spellID,
            spellName = spellName,
            amount    = isHeal and -math.abs(amount) or math.abs(amount),
            isHeal    = isHeal,
            srcName   = SafeString(ev.sourceName, ""),
            hp        = hp,
            maxHP     = maxHP,
            hpPercent = hpPct,
            overkill  = overkill,
            school    = SafeNum(ev.school, 1),
        })
    end

    return result
end

local function GetRecapEvents(recapID)
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return nil end
    if not recapID or recapID <= 0 then return nil end

    local ok, events = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if ok and events and #events > 0 then return events end
    return nil
end

local function GetRecapMaxHealth(recapID)
    if not C_DeathRecap or not C_DeathRecap.GetRecapMaxHealth then return 1 end
    local ok, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
    if ok and hp and hp > 0 then return hp end
    return 1
end

function DT:BuildDeathRecordFromRecapID(recapID, src)
    if not recapID or recapID <= 0 then return nil end

    local guid = src and src.sourceGUID
    local isSelf = (src and src.isLocalPlayer) and true or false

    -- sourceGUID 可能是 secret，不能比较 guid == ns.state.playerGUID。
    if isSelf then
        guid = ns.state.playerGUID or UnitGUID("player")
    elseif IsSecretValue(guid) then
        guid = nil
    end

    local class = src and src.classFilename
    if not class or class == "" then
        if guid and not IsSecretValue(guid) and ns:IsNPCGUID(guid) then
            class = "NPC"
        elseif guid and not IsSecretValue(guid) then
            local ok, _, ce = pcall(GetPlayerInfoByGUID, guid)
            class = (ok and ce) or "WARRIOR"
        else
            class = "WARRIOR"
        end
    end

    -- 关键：src.name 是 ConditionalSecret，secret 时原样保存给 UI，不要替换成“未知”。
    local playerName = DisplayNameValue(src and src.name, isSelf and (UnitName("player") or L["我"]) or L["未知"])

    local maxHP = GetRecapMaxHealth(recapID)
    local recapEvents = GetRecapEvents(recapID)
    local events = recapEvents and self:ParseRecapEvents(recapEvents, maxHP) or {}

    local killingAbility = "?"
    local killerName = ""
    for i = #events, 1, -1 do
        if not events[i].isHeal then
            killingAbility = events[i].spellName or "?"
            killerName = events[i].srcName or ""
            break
        end
    end

    local totalDmg, totalHeal = 0, 0
    for _, ev in ipairs(events) do
        if ev.isHeal then totalHeal = totalHeal + math.abs(ev.amount or 0)
        else totalDmg = totalDmg + math.abs(ev.amount or 0) end
    end

    local timeSpan = 0
    if #events >= 2 then
        timeSpan = (events[#events].time or 0) - (events[1].time or 0)
    end

    local ts = time()
    if #events > 0 and events[#events].time then
        ts = math.floor(events[#events].time)
    end

    return {
        timestamp            = ts,
        gameTime             = GetTime(),
        playerName           = playerName,
        playerGUID           = guid,
        playerClass          = class,
        isSelf               = isSelf,
        killingAbility       = (#events == 0) and L["等待死亡回放"] or killingAbility,
        killerName           = killerName,
        events               = events,
        lastHP               = 0,
        maxHP                = maxHP,
        totalDamageTaken     = totalDmg,
        totalHealingReceived = totalHeal,
        timeSpan             = timeSpan,
        _fromRecap           = true,
        _recapID             = recapID,
        _specIconID          = GetDeathSpecIconID(guid, src),
        _deathCount          = GetDeathCount(src),
        _deathTimeSeconds    = SafeNum(src and src.deathTimeSeconds, 0),
        _apiGenerated        = true,
        _incomplete          = (#events == 0),
    }
end

local function GetDeathSession(sessionType, sessionID)
    if not C_DamageMeter then return nil end
    local dmType = Enum.DamageMeterType.Deaths

    if sessionID then
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, dmType)
        if ok then return session end
    else
        local st = sessionType or Enum.DamageMeterSessionType.Current
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, st, dmType)
        if ok then return session end
    end

    return nil
end

local function InsertOrdered(list, record)
    if record then table.insert(list, record) end
end

function DT:GetDeathLogFromAPI(sessionType, sessionID, fallbackSegment)
    local session = GetDeathSession(sessionType, sessionID)
    local result = {}

    if session and session.combatSources then
        local seenRecap = {}
        for _, src in ipairs(session.combatSources) do
            local recapID = SafeNum(src.deathRecapID, 0)
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
                local guid = src.sourceGUID
                local isSelf = src.isLocalPlayer and true or false

                if isSelf then
                    guid = ns.state.playerGUID or UnitGUID("player")
                elseif IsSecretValue(guid) then
                    guid = nil
                end

                InsertOrdered(result, {
                    timestamp            = time(),
                    gameTime             = GetTime(),
                    playerName           = DisplayNameValue(src.name, isSelf and (UnitName("player") or L["我"]) or L["未知"]),
                    playerGUID           = guid,
                    playerClass          = src.classFilename or "WARRIOR",
                    isSelf               = isSelf,
                    killingAbility       = L["等待死亡回放"],
                    killerName           = "",
                    events               = {},
                    lastHP               = 0,
                    maxHP                = 1,
                    totalDamageTaken     = 0,
                    totalHealingReceived = 0,
                    timeSpan             = 0,
                    _fromRecap           = false,
                    _recapID             = nil,
                    _specIconID          = GetDeathSpecIconID(guid, src),
                    _deathCount          = deaths,
                    _deathTimeSeconds    = SafeNum(src.deathTimeSeconds, 0),
                    _apiGenerated        = true,
                    _incomplete          = true,
                })
            end
        end
    end

    if #result == 0 and fallbackSegment and fallbackSegment.deathLog then
        return fallbackSegment.deathLog
    end

    table.sort(result, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        local at = a._deathTimeSeconds or 0
        local bt = b._deathTimeSeconds or 0
        if at ~= bt then return at > bt end
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

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
