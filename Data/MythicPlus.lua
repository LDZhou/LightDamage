--[[
    LD Combat Stats - MythicPlus.lua
    大秘境 / 副本生命周期管理
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

local AUTO_CLEAN_AGE = 600  -- 10分钟

-- ============================================================
-- 内部工具
-- ============================================================
local function getMapInfo()
    local id = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
               and C_ChallengeMode.GetActiveChallengeMapID()
    if not id then return nil, nil, 0 end
    -- ★ 新增：获取大秘境限时时间 (timeLimit, 单位秒)
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
           or seg._isMerged  -- ★ 修复：全程合并段永久保留，不受10分钟限制
           or seg._isBoss    -- ★ 修复：processArchivedSessions 产生的 Boss 段（type="history"+_isBoss=true）永久保留
           or seg._instanceTag 
        then
            table.insert(cleaned, seg)
        -- elseif seg.endTime and (now - seg.endTime) < AUTO_CLEAN_AGE then
        --     table.insert(cleaned, seg)
        end
    end
    segs.history = cleaned
end

local function enterInstance(id, name, level, timeLimit)
    cleanOutdoorHistory()

    -- ★ meter 已由 CT:RegisterEvents 的4s timer 或 MP:OnStart 重置为0
    --   baseline 直接设为0，与重置后的暴雪meter完全对齐
    if ns.CombatTracker then
        ns.CombatTracker._baselineSessionCount = 0
        ns.CombatTracker._lastProcessedCount   = 0
    end
    MP._baseline = 0

    if ns.Segments then
        local label = level and level > 0 and string.format("%s +%d", name, level) or name
        ns.Segments.overall  = ns.Segments:NewSegment("overall", label)
        ns.Segments.viewIndex = nil
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

-- 离开副本的清理工作（通用）
local function leaveInstance()
    MP:StopTimer()
    MP._active        = false
    MP._mapID         = nil
    MP._mapName       = nil
    MP._level         = nil
    MP._timeLimit     = nil
    MP._startTime     = nil
    MP._elapsedOnStop = nil

    -- ★ 删除这个1.5s的ResetBaselineToCurrentCount调用
    -- 它会在secret释放前抢先重置_lastProcessedCount
    -- mergeAndCleanInstance（4s后）已经会正确调用Reset
    C_Timer.After(1.5, function()
        -- 只保留overall重置和UI刷新，不重置baseline
        -- if ns.Segments then ns.Segments.overall = ns.Segments:NewSegment("overall", L["总计"]) end
        if ns.UI and ns.UI:IsVisible() then C_Timer.After(0, function() ns.UI:Layout() end) end
    end)
end

-- ============================================================
-- Init（Core:OnInitialize 调用）
-- ============================================================
function MP:Init()
    C_Timer.After(2, function()
        local id, name, timeLimit = getMapInfo()
        if not id then return end

        local level = getKeystoneLevel() or 0
        enterInstance(id, name or GetZoneText() or L["大秘境"], level, timeLimit)
        print(string.format(L["|cff4cb8e8[Light Damage]|r 检测到大秘境: %s +%d (reload)"], name, level))

        --   CT._currentMythicLevel停留在0，需手动同步，确保出副本时层数正确
        if ns.CombatTracker then
            ns.CombatTracker._currentMythicLevel   = level
            ns.CombatTracker._currentMythicMapName = name
        end

        -- ★ 修复：用重试 ticker 持续尝试读服务器计时，直到成功为止
        --         解决 reload 后计时器未就绪导致的 4-5 秒误差
        local retryCount = 0
        local retryTicker
        retryTicker = C_Timer.NewTicker(0.5, function()
            retryCount = retryCount + 1

            local timerIDs = { GetWorldElapsedTimers() }
            for _, timerID in ipairs(timerIDs) do
                local ok, _, elapsedTime, timerType = pcall(GetWorldElapsedTime, timerID)
                if ok and timerType == LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE
                   and elapsedTime and elapsedTime > 0 then
                    -- 成功读到服务器计时，修正 startTime
                    MP._startTime = GetTime() - elapsedTime
                    retryTicker:Cancel()
                    return
                end
            end

            -- 最多重试 20 次（10秒），超时放弃
            if retryCount >= 20 then
                retryTicker:Cancel()
            end
        end)
    end)
end

-- ============================================================
-- OnStart（CHALLENGE_MODE_START）
-- ============================================================
function MP:OnStart()
    -- ★ 清除预热段的副本关联
    if ns.state.isInInstance and ns.Segments then
        local preTag = ns.CombatTracker and ns.CombatTracker._currentInstanceTag
        if preTag then
            for _, seg in ipairs(ns.Segments.history) do
                if seg._instanceTag == preTag then
                    seg._instanceTag = nil
                    seg._preKeystone = true
                    if not seg.name:find(L["%[开本前%]"]) then
                        seg.name = L["[开本前] "] .. (seg.name or L["战斗"])
                    end
                end
            end
        end
    end

    -- ★ 插钥匙时立即重置暴雪meter
    --   玩家插钥匙前至少经过了走路时间，预热session的Secret Value早已解密归档完毕
    --   重置后 baseline=0，Overall API 从此只统计本次M+数据
    if ns.CombatTracker then
        ns.CombatTracker:ResetMeterForNewRun()
    end

    local id, name, timeLimit = getMapInfo()
    local level = getKeystoneLevel()
    name  = name  or GetZoneText() or L["大秘境"]
    level = level or 0
    enterInstance(id, name, level, timeLimit)
end

-- ============================================================
-- OnCompleted（CHALLENGE_MODE_COMPLETED）
-- ============================================================
function MP:OnCompleted(time, onTime)
    MP:StopTimer()
    MP._elapsedOnStop = time
    MP._completedAndStillInside = true

    local status  = onTime and "✓" or "✗"
    local runName = string.format("+%d %s %s",
        MP._level or 0, MP._mapName or L["大秘境"], status)

    MP:BuildMythicSegment(runName, onTime)

    print(string.format(L["|cff4cb8e8[Light Damage]|r M+ 完成: %s (计时: %s)"],
        runName, ns:FormatTime((time or 0) / 1000)))

    -- 完成后的清理
    leaveInstance()

    if ns.UI and ns.UI:IsVisible() then
        C_Timer.After(0.5, function() ns.UI:Layout() end)
    end
end

-- ============================================================
-- OnReset（CHALLENGE_MODE_RESET）
-- ============================================================
function MP:OnReset()
    MP._completedAndStillInside = false
    if MP._active then
        local elapsed = MP._startTime and (GetTime() - MP._startTime) or 0
        if elapsed > 30 then
            local runName = string.format("+%d %s —",
                MP._level or 0, MP._mapName or L["大秘境"])
            MP:BuildMythicSegment(runName, nil)
        end
    end

    leaveInstance()

    if ns.UI and ns.UI:IsVisible() then
        C_Timer.After(0.5, function() ns.UI:Layout() end)
    end
end

-- ============================================================
-- OnEnterDungeon（UpdateInstanceStatus 检测到进本）
-- ============================================================
function MP:OnEnterDungeon()
    if MP._active then return end
    local _, instanceType = IsInInstance()
    if instanceType ~= "party" and instanceType ~= "raid" then return end

    local id, name, timeLimit = getMapInfo()
    name = name or GetZoneText() or L["副本"]
    local level = getKeystoneLevel() or 0
    enterInstance(id, name, level, timeLimit)
end

-- ============================================================
-- OnLeaveInstance（离开副本时触发，普通副本结束）
-- ============================================================
function MP:OnLeaveInstance()
    if not MP._active then return end

    local runName = MP._mapName or L["副本"]
    if MP._level and MP._level > 0 then
        runName = string.format("+%d %s —", MP._level, runName)
    end

    MP:BuildMythicSegment(runName, nil)
    print(string.format(L["|cff4cb8e8[Light Damage]|r 离开副本，数据已归档"]))

    leaveInstance()

    if ns.UI and ns.UI:IsVisible() then
        C_Timer.After(0.5, function() ns.UI:Layout() end)
    end
end

-- ============================================================
-- 合并本局所有归档 session 为一个总览段 (照搬 Overall 完美逻辑)
-- ============================================================
function MP:BuildMythicSegment(name, success)
    MP._pendingMythicSeg = {
        name    = name,
        success = success,
        level   = MP._level   or 0,
        mapName = MP._mapName or L["大秘境"],
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

    local timerIDs = { GetWorldElapsedTimers() }
    for _, timerID in ipairs(timerIDs) do
        local ok, description, elapsedTime, timerType = pcall(GetWorldElapsedTime, timerID)
        if ok and timerType == LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE then
            if elapsedTime and elapsedTime > 0 then
                return elapsedTime
            end
        end
    end

end

function MP:GetHeaderInfo()
    if not MP._active then return nil end
    return {
        level     = MP._level   or 0,
        name      = MP._mapName or L["副本"],
        elapsed   = MP:GetElapsed(),
        timeLimit = MP._timeLimit or 0, -- ★ 增加返回值
    }
end

function MP:FormatSegLabel(seg)
    if not seg or seg.type ~= "mythicplus" then return nil end
    local status = ""
    if seg.success == true       then status = " |cff00ff00✓|r"
    elseif seg.success == false  then status = " |cffff4444✗|r"
    else                              status = " |cffaaaaaa—|r" end
    local levelStr = (seg.mythicLevel and seg.mythicLevel > 0)
        and string.format("|cff4cb8e8+%d|r ", seg.mythicLevel) or ""
    return levelStr .. (seg.mapName or L["副本"]) .. status
end

function MP:SetAutoCleanAge(seconds)
    AUTO_CLEAN_AGE = seconds
end

function MP:ResetBaseline()
    MP._baseline = 0
end