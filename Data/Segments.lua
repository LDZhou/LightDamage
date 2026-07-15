--[[
    LD Combat Stats - Segments.lua
    段落管理系统

    ★ 改造说明 (虚拟段架构):
    - history 数组仅存已归档段。每个已归档段在创建时分配 _localID。
    - 暴雪 API 现存的 sessions 不进 history,UI 渲染时通过 GetHistoryList 实时拼成
      虚拟段 (_isVirtual=true, 携带 _sessionID),数据每次现读 API。
    - viewIndex 改为 key 存储:
        nil                                       -> 实时 current
        { kind="overall" }                        -> 总计
        { kind="archived", localID="..." }        -> 已归档段
        { kind="virtual",  sessionID=N }          -> 暴雪 API 虚拟段
    - 黑名单 (LightDamageDB.hiddenSessionIDs / hiddenLocalIDs) 在 GetHistoryList
      构建合并列表时过滤。
]]

local addonName, ns = ...
local L = ns.L

local Segments = {}
ns.Segments = Segments

-- ============================================================
-- 数据结构
-- ============================================================
function Segments:NewSegment(segType, name)
    return {
        type      = segType,
        name      = name or segType,
        startTime = GetTime(),
        endTime   = 0,
        duration  = 0,
        isActive  = true,
        _realTime = time(),

        players = {},

        totalDamage      = 0,
        totalHealing     = 0,
        totalDamageTaken = 0,
        totalDeaths      = 0,
        totalEnemyDamageTaken = 0,

        encounterID   = nil,
        encounterName = nil,
        difficultyID  = nil,
        success       = nil,

        deathLog = {},
        enemyDamageTakenList = {},
    }
end

-- ★ 给已归档段分配本地唯一 ID。同一会话内单调递增,跨会话用时间戳兜底。
local _localIDCounter = 0
function Segments:GenLocalID(prefix)
    _localIDCounter = _localIDCounter + 1
    return string.format("%s_%d_%d", prefix or "arch", time(), _localIDCounter)
end

function Segments:NewPlayerData(guid, name, class)
    local gateway = ns.DamageMeterGateway
    if gateway and (not gateway:IsAccessible(guid) or not gateway:IsAccessible(name)) then
        return nil
    end
    local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
    local specID = cache.specID

    -- ★ 核心修复:如果是玩家自己,直接获取当前实时专精
    if guid == ns.state.playerGUID then
        local specIdx = GetSpecialization()
        if specIdx then
            specID = GetSpecializationInfo(specIdx)
        end
    end

    return {
        guid   = guid,
        name   = type(name) == "string" and name ~= "" and ns:ShortName(name) or nil,
        class  = type(class) == "string" and class ~= "" and class or nil,
        specID = specID,
        specIconID = nil,
        ilvl   = cache.ilvl or 0,
        score  = cache.score or 0,

        damage      = 0, healing     = 0, overhealing = 0, absorbed    = 0, damageTaken = 0,
        deaths      = 0, interrupts  = 0, dispels     = 0,

        spells          = {},
        pets            = {},
        interruptSpells = {},
        dispelSpells    = {},
        damageTakenSpells = {},

        activeTime     = 0, lastActionTime = 0,
    }
end

function Segments:NewSpellData(spellID, spellName, school)
    return {
        id          = spellID,
        name        = spellName,
        school      = school,
        damage      = 0,
        healing     = 0,
        overhealing = 0,
        hits        = 0,
        crits       = 0,
        misses      = 0,
        maxHit      = 0,
        minHit      = 999999999,
        absorbed    = 0,
    }
end

-- ============================================================
-- 初始化
-- ============================================================
function Segments:Init()
    self.overall     = self:NewSegment("overall", L.OVERALL)
    self.current     = nil
    self.history     = {}
    self.viewIndex   = nil   -- ★ 现在是 nil 或 table {kind=..., localID/sessionID=...}
    self.bossActive  = false
    self.currentBoss = nil
    self._locked     = false
    self._combatGeneration = self._combatGeneration or 0
    self._preReloadOverallData = nil
    self._fullRunOverrideSegment = nil
end

-- ============================================================
-- ★ View key 判定/设置 helper
-- ============================================================
function Segments:IsViewingCurrent()
    return self.viewIndex == nil
end

function Segments:IsViewingOverall()
    return type(self.viewIndex) == "table" and self.viewIndex.kind == "overall"
end

function Segments:IsViewingArchived()
    return type(self.viewIndex) == "table" and self.viewIndex.kind == "archived"
end

function Segments:IsViewingVirtual()
    return type(self.viewIndex) == "table" and self.viewIndex.kind == "virtual"
end

function Segments:ViewCurrent()
    self.viewIndex = nil
end

function Segments:ViewOverall()
    self.viewIndex = { kind = "overall" }
end

function Segments:ViewArchived(localID)
    if not localID then return end
    self.viewIndex = { kind = "archived", localID = localID }
end

function Segments:ViewVirtual(sessionID)
    if not sessionID then return end
    self.viewIndex = { kind = "virtual", sessionID = sessionID }
end

-- ============================================================
-- ★ 脱战时选择最新一条 HistoryList 里的战斗
--   包括 archived / virtual，并且会自动尊重隐藏黑名单
-- ============================================================
function Segments:ViewLatestHistory()
    local merged = self:GetMergedSegmentList()
    local latest = merged and merged[1]

    if latest then
        if latest._isVirtual and latest._sessionID then
            self:ViewVirtual(latest._sessionID)
            return true
        elseif latest._localID then
            self:ViewArchived(latest._localID)
            return true
        end
    end

    self:ViewCurrent()
    return false
end

function Segments:ResetAll(onComplete)
    -- A user reset is an explicit delete transaction.  In combat it is queued
    -- until the just-finished official session has published, then Blizzard
    -- Current/Overall and every local/hidden record are cleared atomically.
    -- The sessions being deleted are deliberately not archived first.
    if ns.CombatTracker and not self._performingQueuedReset then
        ns.CombatTracker:QueueUserReset(onComplete)
        return false, "queued"
    end

    self:Init()
    if ns.HistoryStore then ns.HistoryStore:Invalidate() end
    self._combatGeneration = (self._combatGeneration or 0) + 1
    self._preReloadOverallData = nil

    if ns.db then
        ns.db.savedHistory       = nil
        ns.db.savedOverall       = nil
        ns.db.savedBaseline      = nil
        ns.db.savedLastProcessed = nil
        -- ★ Reset 时清空黑名单
        ns.db.hiddenSessionIDs   = {}
        ns.db.hiddenLocalIDs     = {}
        ns.db.fullRunOverrideLocalID = nil
    end

    if ns.Analysis then
        ns.Analysis:InvalidateCache()
    end

    if ns.DeathTracker then
        ns.DeathTracker:ClearBuffers()
    end

    wipe(ns.PlayerInfoCache)
    if ns.PlayerInfo and ns.PlayerInfo.Refresh then ns.PlayerInfo:Refresh(0) end

    if ns.DetailView then
        ns.DetailView._lastRenderArgs = nil
        if ns.DetailView.frame and ns.DetailView.frame:IsShown() then
            ns.DetailView.frame:Hide()
        end
    end

    if ns.CombatTracker then
        ns.CombatTracker:MarkReset()
        ns.CombatTracker._bossSessionIndices = {}
    end

    if ns.HistoryList and ns.HistoryList._histItems then
        for _, item in ipairs(ns.HistoryList._histItems) do
            item.data = nil
        end
    end

    if ns.UI then
        if ns.UI.ResetCellData then ns.UI:ResetCellData() end
        ns.UI._sessionCache = {}
        ns.UI:Refresh()
    end
    return true
end

-- ============================================================
-- 战斗生命周期
-- ============================================================
function Segments:OnCombatStart()
    if self.current and self.current.isActive then return end

    self._combatGeneration = (self._combatGeneration or 0) + 1

    if ns.DeathTracker and ns.DeathTracker.ClearBuffers then
        ns.DeathTracker:ClearBuffers()
    end

    local zone    = GetZoneText() or ""
    local segName = zone

    if self.bossActive then
        segName = self.currentBoss and self.currentBoss.name or "Boss"
    end

    self.current   = self:NewSegment("current", segName)
    if self.bossActive then
        local boss = self.currentBoss or {}
        self.current.type = "boss"
        self.current._isBoss = true
        self.current.encounterID = boss.id
        self.current.encounterName = boss.name
        self.current.difficultyID = boss.difficulty
    end

    -- 新战斗是唯一强制全局视图回到“当前”的生命周期节点。
    self:ClearFullRunOverride()
    self:ViewCurrent()

    self._locked   = true
end

function Segments:OnCombatEnd()
    if not self.current then return end
    self._locked = false
    self.current.isActive = false
    self.current.endTime  = GetTime()

    if self.current.startTime and self.current.startTime > 0 then
        self.current.duration = self.current.endTime - self.current.startTime
    end

    if ns.DeathTracker then ns.DeathTracker:ClearBuffers() end
    if ns.Analysis then ns.Analysis:InvalidateCache() end

    -- 脱战不改变玩家正在查看的段落；归档事务完成后 CombatTracker
    -- 会把 current 原子替换为刚结束的官方 session。
    if ns.CombatTracker and ns.CombatTracker.OnCombatEnded then
        ns.CombatTracker:OnCombatEnded()
    end
    if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
end

-- 离开副本生成全程段落后，段落选择切到全程，“当前”和“总计”都显示它。
-- 覆盖 ID 存在角色存档中，因此重载后仍延续，直到新战斗、重置或删除。
function Segments:SetFullRunOverride(seg)
    if not seg or not seg._localID then return end
    ns.db.fullRunOverrideLocalID = seg._localID
    self._fullRunOverrideSegment = seg
    self:ViewArchived(seg._localID)
end

function Segments:ClearFullRunOverride()
    local id = ns.db and ns.db.fullRunOverrideLocalID
    local cached = self._fullRunOverrideSegment
    if ns.db then ns.db.fullRunOverrideLocalID = nil end
    self._fullRunOverrideSegment = nil
    -- Instance full-run presentation aliases Overall to the same local segment.
    -- Once that override is cleared (new combat, hide, delete), the alias must
    -- disappear too or a hidden full run can remain visible through Total.
    local overall = self.overall
    if overall and (overall == cached or (id and overall._localID == id)) then
        self.overall = self:NewSegment("overall", L.OVERALL)
    end
end

function Segments:GetFullRunOverride()
    local id = ns.db and ns.db.fullRunOverrideLocalID
    if not id then return nil end
    local cached = self._fullRunOverrideSegment
    if cached and cached._localID == id and cached._isMerged then return cached end
    for _, seg in ipairs(self.history or {}) do
        if seg._localID == id and seg._isMerged then
            self._fullRunOverrideSegment = seg
            return seg
        end
    end
    self:ClearFullRunOverride()
    return nil
end

function Segments:GetTotalDisplaySegment()
    -- “总计”代表当前有效 Total 数据源。离本全程覆盖期间，即使
    -- HistoryList 显式选中“总计”，Current/Total 仍同显该全程；
    -- 下一场战斗清除覆盖后才恢复 Blizzard Overall。
    return self:GetFullRunOverride() or self.overall
end

function Segments:OnEncounterStart(encounterID, name, difficultyID, groupSize)
    self.bossActive  = true
    self.currentBoss = {
        id         = encounterID,
        name       = name,
        difficulty = difficultyID,
        groupSize  = groupSize,
    }
    ns.state.lastCombatWasBoss = true

    if self.current and self.current.isActive then
        self.current.type          = "boss"
        self.current._isBoss       = true
        self.current.name          = name or "Boss"
        self.current.encounterID   = encounterID
        self.current.encounterName = name
        self.current.difficultyID  = difficultyID
    end
    if ns.CombatTracker and ns.CombatTracker.PersistLifecycleState then
        ns.CombatTracker:PersistLifecycleState()
    end
end

function Segments:OnEncounterEnd(encounterID, name, difficultyID, groupSize, success)
    self.bossActive = false
    if self.current then
        self.current._isBoss       = true
        self.current.success       = (success == 1)
        self.current.encounterName = name
    end
    self.currentBoss = nil
    if ns.CombatTracker and ns.CombatTracker.PersistLifecycleState then
        ns.CombatTracker:PersistLifecycleState()
    end
end

-- ============================================================
-- ★ 黑名单查询
-- ============================================================
local function isSessionIDHidden(sid)
    return sid and ns.db and ns.db.hiddenSessionIDs and ns.db.hiddenSessionIDs[sid] == true
end

local function isLocalIDHidden(lid)
    return lid and ns.db and ns.db.hiddenLocalIDs and ns.db.hiddenLocalIDs[lid] == true
end

-- ============================================================
-- ★ 虚拟段构建
--   返回当前暴雪 API 中所有 session 的轻量段对象,过滤掉:
--   - 已经归档进 history 的 sessionID
--   - 在黑名单里的 sessionID
--   注:这里不读 session 数据,只构建元信息壳。数据由 UI 走 API 路径现读。
-- ============================================================
function Segments:BuildVirtualSegments()
    local gateway = ns.DamageMeterGateway
    local sessions, sessionsState
    if gateway then
        sessions, sessionsState = gateway:GetAvailableSessionsRaw()
    end
    if not gateway or sessionsState ~= gateway.ACCESSIBLE
        or type(sessions) ~= "table" or #sessions == 0 then return {} end

    -- 收集 history 中所有已归档段的 sessionID(归档段的原始来源)
    local archivedSIDs = {}
    local rawGeneration = gateway:GetRawGeneration()
    for _, seg in ipairs(self.history) do
        -- Session IDs are only unique inside one Damage Meter generation and
        -- may be reused after ResetAllCombatSessions.  A stale local ID must
        -- never suppress a new official session from virtual History.
        if seg._sessionID and seg._archiveGeneration == rawGeneration then
            archivedSIDs[seg._sessionID] = true
        end
    end

    local result = {}

    for i, s in ipairs(sessions) do
        local sid, sidState = gateway:ReadField(s, "sessionID")
        local rawDuration, durationState = gateway:ReadField(s, "durationSeconds")
        local sessionName, nameState = gateway:ReadField(s, "name")
        -- sessionID is the identity of a virtual History row.  Optional or
        -- temporarily protected metadata must never decide whether that row
        -- exists: Current can already read the same official session, and
        -- hiding it here would make the fight unreachable after next combat.
        if sidState ~= gateway.ACCESSIBLE or type(sid) ~= "number" then sid = nil end
        local durationPublic = durationState == gateway.ACCESSIBLE
            and type(rawDuration) == "number"
        local dur = durationPublic and rawDuration or 0

        local skip = false
        if not sid then skip = true end
        -- Group combat state can remain true briefly after this session has
        -- completed.  Only hide the final row as live when its metadata does
        -- not yet prove completion; a positive public duration is History.
        local officiallyCompleted = ns.CombatTracker
            and ns.CombatTracker.IsCompletedSessionID
            and ns.CombatTracker:IsCompletedSessionID(sid)
        local finalSessionStillLive = ns.state.inCombat and i == #sessions
            and not officiallyCompleted
            and not (durationState == gateway.ACCESSIBLE
                and type(rawDuration) == "number" and rawDuration > 0)
        if finalSessionStillLive then skip = true end
        if archivedSIDs[sid] then skip = true end          -- 已经归档过
        if isSessionIDHidden(sid) then skip = true end     -- 用户黑名单
        -- Rendering History must never *classify* a raw session.  Classification
        -- belongs to the instance/M+ lifecycle transaction and is scoped to the
        -- current raw epoch.  Calling the heuristic here used to let stale reset
        -- state hide an otherwise ordinary Blizzard session.
        if ns.CombatTracker and ns.CombatTracker.IsSyntheticSessionID
            and ns.CombatTracker:IsSyntheticSessionID(sid) then skip = true end
        if not skip then
            local now = GetTime()
            if nameState ~= gateway.ACCESSIBLE then sessionName = nil end
            local seg = {
                type      = "virtual",
                name      = sessionName or GetZoneText() or "Combat",
                _isVirtual = true,
                _sessionID = sid,
                _sessionIdx = i,
                duration  = dur,
                startTime = (dur > 0) and (now - dur) or now,
                endTime   = now,
                isActive  = false,
                _realTime = time() - math.floor(dur or 0),
                _durationUnavailable = not durationPublic or nil,
                -- 数据相关字段为空,UI 走 API 路径现读
                players = {},
                totalDamage = 0, totalHealing = 0, totalDamageTaken = 0,
                deathLog = {},
                enemyDamageTakenList = {},
            }
            table.insert(result, seg)
        end
    end

    return result
end

-- ★ 把已归档段和虚拟段合并成"按时间倒序"的统一列表
--   (最新在前;current/overall 不在内)
function Segments:GetMergedSegmentList()
    local merged = {}

    -- 虚拟段（最新的在前，因为是按 sessionID 倒序拼的）
    local virtuals = self:BuildVirtualSegments()
    for i = #virtuals, 1, -1 do
        table.insert(merged, virtuals[i])
    end

    -- 已归档段（history 数组本身就是新→旧）
    for _, seg in ipairs(self.history) do
        if not isLocalIDHidden(seg._localID) then
            table.insert(merged, seg)
        end
    end

    return merged
end

-- ============================================================
-- ★ 段落数据访问
-- ============================================================
function Segments:GetViewSegment()
    -- 实时
    if self:IsViewingCurrent() then
        local seg = self.current
        if not seg then
            -- 没有当前战斗时,退回到合并列表第一项或 overall
            local merged = self:GetMergedSegmentList()
            seg = merged[1] or self.overall
        end
        return seg
    end

    -- 总计
    if self:IsViewingOverall() then
        return self:GetTotalDisplaySegment()
    end

    -- 已归档(按 localID 反查)
    if self:IsViewingArchived() then
        local lid = self.viewIndex.localID
        for _, seg in ipairs(self.history) do
            if seg._localID == lid then
                -- 懒加载兜底:旧逻辑,继续保留。但虚拟段架构下绝大多数 archived 段
                -- 在归档时已加载完毕,这条路径很少触发。
                if seg._sessionID and (not seg._dataLoaded or (seg.totalDamage or 0) == 0) then
                    if ns.CombatTracker then
                        ns.CombatTracker:LoadSegmentData(seg)
                    end
                end
                return seg
            end
        end
        -- 反查失败:段已被裁剪/删除,退回 current
        self:ViewCurrent()
        return self.current or self.overall
    end

    -- 虚拟段(按 sessionID 反查)
    if self:IsViewingVirtual() then
        local sid = self.viewIndex.sessionID
        local merged = self:GetMergedSegmentList()
        for _, seg in ipairs(merged) do
            if seg._isVirtual and seg._sessionID == sid then
                return seg
            end
        end
        -- 反查失败:虚拟段消失了(被归档/被清/被隐藏),退回 current
        self:ViewCurrent()
        return self.current or self.overall
    end

    -- 兜底
    return self.current or self.overall
end

function Segments:GetOverallSegment()
    return self.overall
end

function Segments:GetCurrentSegment()
    return self.current
end

function Segments:SetViewSegment(viewKey)
    -- 兼容旧调用:有些地方传数字,有些传 key table
    -- 旧 0 → overall;旧 nil → current;旧 number → archived 第 N 项(尽力而为)
    if viewKey == nil then
        self:ViewCurrent()
    elseif viewKey == 0 then
        self:ViewOverall()
    elseif type(viewKey) == "number" then
        local seg = self.history[viewKey]
        if seg and seg._localID then
            self:ViewArchived(seg._localID)
        else
            self:ViewCurrent()
        end
    elseif type(viewKey) == "table" then
        self.viewIndex = viewKey
    end
    if ns.UI then ns.UI:Refresh() end
end

-- ★ CycleSegment 在合并列表上循环
function Segments:CycleSegment(direction)
    local merged = self:GetMergedSegmentList()
    local maxIdx = #merged

    -- 当前位置:0=overall, nil=current, 1..N=合并列表索引
    local curPos
    if self:IsViewingCurrent() then
        curPos = -1   -- 用 -1 代表 current 位
    elseif self:IsViewingOverall() then
        curPos = 0
    else
        curPos = nil
        local target = self:GetViewSegment()
        for i, seg in ipairs(merged) do
            if seg == target then curPos = i; break end
        end
        if not curPos then curPos = -1 end
    end

    local newPos = curPos + direction
    -- 顺序:overall(0) → 合并列表 1..N → current(-1)
    if newPos == 0 then
        self:ViewOverall()
    elseif newPos >= 1 and newPos <= maxIdx then
        local seg = merged[newPos]
        if seg._isVirtual then
            self:ViewVirtual(seg._sessionID)
        else
            self:ViewArchived(seg._localID)
        end
    elseif newPos > maxIdx then
        self:ViewCurrent()
    elseif newPos == -1 then
        self:ViewCurrent()
    else
        -- 越界:跳到 overall
        self:ViewOverall()
    end

    if ns.UI then ns.UI:Refresh() end
end

function Segments:GetViewLabel()
    local seg = self:GetViewSegment()
    if not seg then return L.NO_DATA end

    if seg.type == "overall" then
        return L.COLORED_OVERALL
    elseif seg.type == "mythicplus" then
        if ns.MythicPlus then return ns.MythicPlus:FormatSegLabel(seg) end
        return seg.name or L.MYTHIC_PLUS
    elseif seg.type == "boss" then
        return seg.name or seg.encounterName or L.COMBAT
    else
        return seg.name or L.CURRENT
    end
end

-- ============================================================
-- 获取/创建玩家数据(原样保留)
-- ============================================================
function Segments:GetPlayer(seg, guid, name, flags)
    if not seg or not guid then return nil end
    local gateway = ns.DamageMeterGateway
    if gateway and (not gateway:IsAccessible(guid) or not gateway:IsAccessible(name)) then return nil end

    local pd = seg.players[guid]
    if not pd then
        local classEng
        if not ns:IsNPCGUID(guid) then
            local ok, _, ce = pcall(GetPlayerInfoByGUID, guid)
            classEng = ok and ce or nil
        end
        pd = self:NewPlayerData(guid, name, classEng)
        seg.players[guid] = pd
    end

    if name and not (issecretvalue and issecretvalue(name)) and name ~= "" and name ~= "?" then
        pd.name = ns:ShortName(name)
    end

    return pd
end

-- ============================================================
-- 记录承伤 / 死亡 / 宠物名(原样保留,只用在 CLEU 死亡日志路径)
-- ============================================================
function Segments:RecordDamageTaken(destGUID, destName, destFlags,
        amount, spellID, spellName, school, sourceGUID, sourceName)

    amount = ns:SafeNum(amount)
    if amount <= 0 then return end

    local function writeToSeg(seg)
        if not seg then return end
        local pd = self:GetPlayer(seg, destGUID, destName, destFlags)
        if not pd then return end
        pd.damageTaken       = pd.damageTaken + amount
        seg.totalDamageTaken = seg.totalDamageTaken + amount
    end

    writeToSeg(self.current)
    writeToSeg(self.overall)

    if ns.DeathTracker then
        ns.DeathTracker:RecordIncomingDamage(destGUID, destName, destFlags,
            amount, spellID, spellName, school, sourceGUID, sourceName)
    end
end

function Segments:RecordDeath(destGUID, destName, destFlags)
    local function writeToSeg(seg)
        if not seg then return end
        local pd = self:GetPlayer(seg, destGUID, destName, destFlags)
        if not pd then return end
        pd.deaths = pd.deaths + 1
    end
    writeToSeg(self.current)
    writeToSeg(self.overall)
end

function Segments:UpdatePetName(ownerGUID, petGUID, petName)
    if not petName or petName == "" then return end
    local shortName = ns:ShortName(petName)

    local function updateInSeg(seg)
        if not seg then return end
        local pd = seg.players[ownerGUID]
        if pd and pd.pets[petGUID] then
            pd.pets[petGUID].name = shortName
        end
    end
    updateInSeg(self.current)
    updateInSeg(self.overall)
end

-- ============================================================
-- 历史列表接口 - 由 HistoryList 渲染
-- 返回顺序:历史(最旧 → 最新) + current + overall
-- 历史部分 = 已归档段 + 虚拟段(都按时间倒序;最旧在最上面)
-- ============================================================
function Segments:GetHistoryList()
    local list = {}

    local merged = self:GetMergedSegmentList()
    local maxSeg = ns.GetHistoryDisplayLimit and ns:GetHistoryDisplayLimit()
        or (ns.db and ns.db.tracking and (ns.db.tracking.historyDisplayLimit or ns.db.tracking.maxSegments)) or 30

    -- 注意:合并列表是"最新→最旧"(因为 sort 用 ae > be)。
    -- 渲染上是"最旧 → 最新 → 当前 → 总计",所以倒着遍历。
    -- 截取规则:只展示前 maxSeg 个(以"最新优先"裁剪)。
    local limit = math.min(#merged, maxSeg)

    for i = limit, 1, -1 do
        local seg = merged[i]
        local label
        if seg.type == "mythicplus" then
            label = ns.MythicPlus and ns.MythicPlus:FormatSegLabel(seg) or seg.name
        else
            label = seg.name or L.COMBAT
        end
        local dur = seg.duration or 0
        if dur > 0 then
            label = label .. " |cffaaaaaa" .. ns:FormatTime(dur) .. "|r"
        end

        local entry = { seg = seg, label = label }
        if seg._isVirtual then
            entry.key       = "virtual"
            entry.sessionID = seg._sessionID
        else
            entry.key       = "archived"
            entry.localID   = seg._localID
        end
        table.insert(list, entry)
    end

    -- current
    local currentLabel
    if self.current and self.current.isActive then
        currentLabel = L.COLORED_CURRENT_COMBAT
    else
        currentLabel = L.COLORED_CURRENT_MARKER
    end
    table.insert(list, {
        key       = "current",
        seg       = self.current,
        label     = currentLabel,
        isCurrent = true,
    })

    -- overall
    table.insert(list, {
        key   = "overall",
        seg   = self.overall,
        label = L.COLORED_TOTAL_MARKER,
    })

    return list
end

-- ★ HistoryList 点击时调用:不再用 (key, index),改用 entry table
--    但旧签名 (key, index) 仍兼容(在 HistoryList 里改成传 entry)
function Segments:SetViewByKey(key, idOrIndex)
    if key == "current" then
        self:ViewCurrent()
    elseif key == "overall" then
        self:ViewOverall()
    elseif key == "archived" then
        self:ViewArchived(idOrIndex)   -- idOrIndex = localID
    elseif key == "virtual" then
        self:ViewVirtual(idOrIndex)    -- idOrIndex = sessionID
    elseif key == "history" then
        -- 旧调用兼容:idOrIndex 是数字 index
        local seg = self.history[idOrIndex]
        if seg and seg._localID then
            self:ViewArchived(seg._localID)
        else
            self:ViewCurrent()
        end
    end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    if ns.UI then ns.UI:Refresh() end
end

function Segments:GetViewKey()
    if self:IsViewingCurrent() then return "current", nil end
    if self:IsViewingOverall() then return "overall", nil end
    if self:IsViewingArchived() then return "archived", self.viewIndex.localID end
    if self:IsViewingVirtual() then return "virtual", self.viewIndex.sessionID end
    return "current", nil
end

-- ============================================================
-- ★ 黑名单操作
-- ============================================================
function Segments:HideSession(entry)
    if not entry then return end
    if not ns.db then return end
    if entry.key == "virtual" and entry.sessionID then
        ns.db.hiddenSessionIDs = ns.db.hiddenSessionIDs or {}
        ns.db.hiddenSessionIDs[entry.sessionID] = true
    elseif entry.key == "archived" and entry.localID then
        ns.db.hiddenLocalIDs = ns.db.hiddenLocalIDs or {}
        ns.db.hiddenLocalIDs[entry.localID] = true
        if ns.db.fullRunOverrideLocalID == entry.localID then self:ClearFullRunOverride() end
    end

    -- 如果当前正在看这个段,自动跳走
    if entry.key == "virtual" and self:IsViewingVirtual() and self.viewIndex.sessionID == entry.sessionID then
        self:ViewLatestHistory()
    elseif entry.key == "archived" and self:IsViewingArchived() and self.viewIndex.localID == entry.localID then
        self:ViewLatestHistory()
    end

    if ns.Analysis then ns.Analysis:InvalidateCache() end
end

-- ★ ResetAllCombatSessions 后调用,清掉 sessionID 黑名单(那些 ID 都失效了)
function Segments:ClearHiddenSessionIDs()
    if ns.db then
        ns.db.hiddenSessionIDs = {}
    end
end

-- ★ SmartTrimHistory 调用:已归档段被裁了之后,清理孤儿 localID 黑名单条目
function Segments:GCHiddenLocalIDs()
    if not ns.db or not ns.db.hiddenLocalIDs then return end
    local alive = {}
    for _, seg in ipairs(self.history) do
        if seg._localID then alive[seg._localID] = true end
    end
    for lid in pairs(ns.db.hiddenLocalIDs) do
        if not alive[lid] then ns.db.hiddenLocalIDs[lid] = nil end
    end
end

-- ★ 归档时迁移黑名单:虚拟段 sessionID 在 hiddenSessionIDs 里 → 归档段的 localID 加进 hiddenLocalIDs
function Segments:MigrateHideOnArchive(seg)
    if not seg or not seg._localID then return end
    if not ns.db then return end
    local sid = seg._sessionID
    if sid and ns.db.hiddenSessionIDs and ns.db.hiddenSessionIDs[sid] then
        ns.db.hiddenLocalIDs = ns.db.hiddenLocalIDs or {}
        ns.db.hiddenLocalIDs[seg._localID] = true
    end
end

function Segments:HideLocalID(localID)
    if not localID or not ns.db then return end
    ns.db.hiddenLocalIDs = ns.db.hiddenLocalIDs or {}
    ns.db.hiddenLocalIDs[localID] = true
    if ns.db.fullRunOverrideLocalID == localID then self:ClearFullRunOverride() end
end

function Segments:HideWhere(predicate)
    if type(predicate) ~= "function" then return 0 end
    local count = 0
    for _, seg in ipairs(self.history or {}) do
        if seg._localID and predicate(seg) then
            self:HideLocalID(seg._localID)
            count = count + 1
        end
    end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    return count
end
