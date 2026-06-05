--[[
    LD Combat Stats - MythicPlus.lua
    大秘境 / 副本生命周期管理

    ★ 改造说明 (虚拟段架构):
    - viewIndex = nil 改为 ViewCurrent()
    - cleanOutdoorHistory 保留:这是裁剪 history (已归档段) 的工具函数,虚拟段不在这里处理
]]

local addonName, ns = ...
local L = ns.L

local MP = {}
ns.MythicPlus = MP

MP._active        = false
MP._mapID         = nil
MP._mapName       = nil
MP._level         = nil
MP._startTime     = nil
MP._elapsedOnStop = nil
MP._baseline      = 0
MP._timerHandle   = nil
MP._completedAndStillInside  = false

local AUTO_CLEAN_AGE = 600

-- ============================================================
-- 内部工具
-- ============================================================
local function getMapInfo()
    local id = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
               and C_ChallengeMode.GetActiveChallengeMapID()
    if not id then return nil, nil, 0 end
    local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(id)
    return id, name, timeLimit or 0
end

local function getKeystoneLevel()
    local level = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
                  and C_ChallengeMode.GetActiveKeystoneInfo()
    return level
end

local function cleanOutdoorHistory()
    local segs = ns.Segments
    if not segs then return end

    local now     = GetTime()
    local cleaned = {}
    for _, seg in ipairs(segs.history) do
        if seg.archived
           or seg.type == "mythicplus"
           or seg.type == "boss"
           or seg._isMerged
           or seg._isBoss
           or seg._instanceTag
        then
            table.insert(cleaned, seg)
        end
    end
    segs.history = cleaned
end

local function enterInstance(id, name, level, timeLimit)
    cleanOutdoorHistory()

    if ns.CombatTracker then
        ns.CombatTracker._baselineSessionCount = 0
        ns.CombatTracker._lastProcessedCount   = 0
    end
    MP._baseline = 0

    if ns.Segments then
        local label = level and level > 0 and string.format("%s +%d", name, level) or name
        ns.Segments.overall  = ns.Segments:NewSegment("overall", label)
        ns.Segments:ViewCurrent()                          -- ★ 改 key
    end

    MP._active        = true
    MP._mapID         = id
    MP._mapName       = name
    MP._level         = level or 0
    MP._timeLimit     = timeLimit or 0
    MP._startTime     = GetTime()
    MP._elapsedOnStop = nil
    ns.state.inMythicPlus = true

    MP:StartTimer()
    if ns.UI and ns.UI:IsVisible() then ns.UI:Layout() end
end

local function leaveInstance()
    MP:StopTimer()
    MP._active        = false
    MP._mapID         = nil
    MP._mapName       = nil
    MP._level         = nil
    MP._timeLimit     = nil
    MP._startTime     = nil
    MP._elapsedOnStop = nil

    C_Timer.After(1.5, function()
        if ns.UI and ns.UI:IsVisible() then C_Timer.After(0, function() ns.UI:Layout() end) end
    end)
end

-- ============================================================
-- Init(Core:OnInitialize 调用)
-- ============================================================
function MP:Init()
    C_Timer.After(2, function()
        local id, name, timeLimit = getMapInfo()
        if not id then return end

        local level = getKeystoneLevel() or 0
        enterInstance(id, name or GetZoneText() or L.MYTHIC_PLUS, level, timeLimit)
        print(string.format(L.MSG_LIGHT_DAMAGE_MYTHIC_PLUS_DETECTED_FORMAT_PLUS_FORMAT_RELOAD_FORM, name, level))

        if ns.CombatTracker then
            ns.CombatTracker._currentMythicLevel   = level
            ns.CombatTracker._currentMythicMapName = name
        end

        local retryCount = 0
        local retryTicker
        retryTicker = C_Timer.NewTicker(0.5, function()
            retryCount = retryCount + 1

            local timerIDs = { GetWorldElapsedTimers() }
            for _, timerID in ipairs(timerIDs) do
                local ok, _, elapsedTime, timerType = pcall(GetWorldElapsedTime, timerID)
                if ok and timerType == LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE
                   and elapsedTime and elapsedTime > 0 then
                    MP._startTime = GetTime() - elapsedTime
                    retryTicker:Cancel()
                    return
                end
            end

            if retryCount >= 20 then
                retryTicker:Cancel()
            end
        end)
    end)
end

-- ============================================================
-- OnStart(CHALLENGE_MODE_START)
-- ★ 改造:插钥匙前先归档(secret 等待),再 ResetMeter
-- ============================================================
function MP:OnStart()
    if ns.state.isInInstance and ns.Segments then
        local preTag = ns.CombatTracker and ns.CombatTracker._currentInstanceTag
        if preTag then
            for _, seg in ipairs(ns.Segments.history) do
                if seg._instanceTag == preTag then
                    seg._instanceTag = nil
                    seg._preKeystone = true
                    if not seg.name:find(L.PRE_INSTANCE_PATTERN) then
                        seg.name = L.PRE_INSTANCE_PREFIX .. (seg.name or L.COMBAT)
                    end
                end
            end
        end
    end

    -- ★ 新流程:先归档当前所有未归档 sessions (虚拟段),再清 meter
    if ns.CombatTracker and ns.CombatTracker.WaitAndProcessArchived then
        ns.CombatTracker:WaitAndProcessArchived()
    end

    -- 0.5s 缓冲后再清 meter,确保归档完成
    C_Timer.After(0.5, function()
        if ns.CombatTracker then
            ns.CombatTracker:ResetMeterForNewRun()
        end

        local id, name, timeLimit = getMapInfo()
        local level = getKeystoneLevel()
        name  = name  or GetZoneText() or L.MYTHIC_PLUS
        level = level or 0
        enterInstance(id, name, level, timeLimit)
    end)
end

-- ============================================================
-- OnCompleted(CHALLENGE_MODE_COMPLETED)
-- ============================================================
function MP:OnCompleted(time, onTime)
    MP:StopTimer()
    MP._elapsedOnStop = time
    MP._completedAndStillInside = true

    local status  = onTime and "✓" or "✗"
    local runName = string.format("+%d %s %s",
        MP._level or 0, MP._mapName or L.MYTHIC_PLUS, status)

    MP:BuildMythicSegment(runName, onTime)

    print(string.format(L.MSG_LIGHT_DAMAGE_MYTHIC_PLUS_COMPLETED_FORMAT_TIME_FORMAT,
        runName, ns:FormatTime((time or 0) / 1000)))

    leaveInstance()

    if ns.UI and ns.UI:IsVisible() then
        C_Timer.After(0.5, function() ns.UI:Layout() end)
    end
end

-- ============================================================
-- OnReset(CHALLENGE_MODE_RESET)
-- ============================================================
function MP:OnReset()
    MP._completedAndStillInside = false
    if MP._active then
        local elapsed = MP._startTime and (GetTime() - MP._startTime) or 0
        if elapsed > 30 then
            local runName = string.format("+%d %s —",
                MP._level or 0, MP._mapName or L.MYTHIC_PLUS)
            MP:BuildMythicSegment(runName, nil)
        end
    end

    leaveInstance()

    if ns.UI and ns.UI:IsVisible() then
        C_Timer.After(0.5, function() ns.UI:Layout() end)
    end
end

-- ============================================================
-- OnEnterDungeon(UpdateInstanceStatus 检测到进本)
-- ============================================================
function MP:OnEnterDungeon()
    if MP._active then return end
    local _, instanceType = IsInInstance()
    if instanceType ~= "party" and instanceType ~= "raid" then return end

    local id, name, timeLimit = getMapInfo()
    name = name or GetZoneText() or L.INSTANCE
    local level = getKeystoneLevel() or 0
    enterInstance(id, name, level, timeLimit)
end

-- ============================================================
-- OnLeaveInstance(离开副本时触发,普通副本结束)
-- ============================================================
function MP:OnLeaveInstance()
    if not MP._active then return end

    local runName = MP._mapName or L.INSTANCE
    if MP._level and MP._level > 0 then
        runName = string.format("+%d %s —", MP._level, runName)
    end

    MP:BuildMythicSegment(runName, nil)
    print(string.format(L.MSG_LIGHT_DAMAGE_LEFT_INSTANCE_DATA_ARCHIVED))

    leaveInstance()

    if ns.UI and ns.UI:IsVisible() then
        C_Timer.After(0.5, function() ns.UI:Layout() end)
    end
end

-- ============================================================
-- 合并本局所有归档 session 为一个总览段
-- ============================================================
function MP:BuildMythicSegment(name, success)
    MP._pendingMythicSeg = {
        name    = name,
        success = success,
        level   = MP._level   or 0,
        mapName = MP._mapName or L.MYTHIC_PLUS,
        mapID   = MP._mapID,
        elapsed = MP._elapsedOnStop,
    }
end

-- ============================================================
-- 计时器
-- ============================================================
function MP:StartTimer()
    MP:StopTimer()
    MP._timerHandle = C_Timer.NewTicker(1, function()
        if not MP._active then MP:StopTimer(); return end
        if ns.UI and ns.UI:IsVisible() then
            ns.UI:RefreshTitle()
        end
    end)
end

function MP:StopTimer()
    if MP._timerHandle then
        MP._timerHandle:Cancel()
        MP._timerHandle = nil
    end
end

-- ============================================================
-- 对外查询接口
-- ============================================================
function MP:IsActive()
    return MP._active
end

function MP:GetElapsed()
    if MP._elapsedOnStop then return MP._elapsedOnStop / 1000 end

    local n = select("#", GetWorldElapsedTimers())
    for i = 1, n do
        local timerID = select(i, GetWorldElapsedTimers())
        local ok, _, elapsedTime, timerType = pcall(GetWorldElapsedTime, timerID)
        if ok and timerType == LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE then
            if elapsedTime and elapsedTime > 0 then
                return elapsedTime
            end
        end
    end
end

local _headerInfoCache = {}
function MP:GetHeaderInfo()
    if not MP._active then return nil end
    _headerInfoCache.level     = MP._level   or 0
    _headerInfoCache.name      = MP._mapName or L.INSTANCE
    _headerInfoCache.elapsed   = MP:GetElapsed()
    _headerInfoCache.timeLimit = MP._timeLimit or 0
    return _headerInfoCache
end

function MP:FormatSegLabel(seg)
    if not seg or seg.type ~= "mythicplus" then return nil end
    local status = ""
    if seg.success == true       then status = " |cff00ff00✓|r"
    elseif seg.success == false  then status = " |cffff4444✗|r"
    else                              status = " |cffaaaaaa—|r" end
    local levelStr = (seg.mythicLevel and seg.mythicLevel > 0)
        and string.format("|cff4cb8e8+%d|r ", seg.mythicLevel) or ""
    return levelStr .. (seg.mapName or L.INSTANCE) .. status
end

function MP:SetAutoCleanAge(seconds)
    AUTO_CLEAN_AGE = seconds
end

function MP:ResetBaseline()
    MP._baseline = 0
end