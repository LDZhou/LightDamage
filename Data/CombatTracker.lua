--[[
    Light Damage - CombatTracker.lua

    Event-driven C_DamageMeter lifecycle coordinator.
    * archive candidates commit atomically
    * a pending/secret session never advances the archive cursor
    * resets are serialized after archive work and never run in combat
    * external meter resets invalidate raw handles but preserve local history
]]
local addonName, ns = ...
local L = ns.L
local G = ns.DamageMeterGateway

local CT = {}
ns.CombatTracker = CT

CT._baselineSessionCount = 0
CT._lastProcessedCount = 0
CT._initialBaselineSet = false
CT._actions = {}
CT._completedContexts = {}
CT._sessionContextByID = {}
CT._sessionGenerationByID = {}
CT._meterObservedGenerations = {}
CT._primarySessionByGeneration = {}
CT._supplementalSessionIDs = {}
CT._syntheticSessionIDs = {}
CT._completedSessionIDs = {}
CT._archiveFirstSeenAt = {}
CT._overallCoverageByTag = {}
CT._instanceHadCombatByTag = {}
CT._resetGeneration = 0
CT._confirmedResetGeneration = 0
CT._appliedResetGeneration = 0
CT._currentMythicLevel = 0
CT._currentMythicMapName = nil
CT._currentInstanceTag = nil
CT._currentInstanceName = nil
CT._currentInstanceType = nil
CT._currentSceneKey = "outdoor"

local SESSION_PUBLICATION_GRACE = 12.0

local function gatewayAccessible(value)
    return not G or G:IsAccessible(value)
end

local function safeSessionCount()
    if not G then return nil, 0 end
    local sessions, state = G:GetAvailableSessionsRaw()
    if state ~= G.ACCESSIBLE or type(sessions) ~= "table" then return nil, 0 end
    return sessions, #sessions
end

local function normalizeInstanceState(inInstance, instanceType)
    if instanceType == "neighborhood" or instanceType == "interior" then return false end
    if instanceType == "scenario" or instanceType == "party" or instanceType == "raid"
        or instanceType == "arena" or instanceType == "pvp" then
        return true
    end
    return inInstance and true or false
end

local function isGroupInCombat()
    if UnitAffectingCombat("player") then return true end
    local rawInInstance, instanceType = IsInInstance()
    local inInstance = normalizeInstanceState(rawInInstance, instanceType)
    -- Outdoor party activity must never create/switch Light Damage Current.
    -- PvP has its own player combat edges and no PvE instance lifecycle.
    if not inInstance or instanceType == "arena" or instanceType == "pvp" then return false end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or math.max(0, GetNumGroupMembers() - 1)
    for i = 1, count do
        if UnitExists(prefix .. i) and UnitAffectingCombat(prefix .. i) then return true end
    end
    return false
end

local function syncCombatState()
    local inCombat = isGroupInCombat()
    if inCombat and not ns.state.inCombat then
        ns:EnterCombat()
        CT:OnCombatStarted()
    elseif not inCombat and ns.state.inCombat then ns:LeaveCombat() end
end

local function instanceSnapshot()
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local rawInInstance = IsInInstance()
    local inInstance = normalizeInstanceState(rawInInstance, instanceType)
    local scene = "outdoor"
    if inInstance then
        if ns.state.inMythicPlus then scene = "mplus"
        elseif instanceType == "raid" then scene = "raid"
        elseif instanceType == "pvp" then scene = "battleground"
        elseif instanceType == "arena" then scene = "arena"
        else scene = "dungeon" end
    end
    return {
        inInstance = inInstance and true or false,
        name = name or GetZoneText() or L.INSTANCE,
        instanceType = instanceType, instanceID = instanceID or 0,
        difficultyID = difficultyID or 0, scene = scene,
        ready = not inInstance or (type(name) == "string" and name ~= ""
            and type(instanceID) == "number" and instanceID > 0 and instanceType ~= nil),
    }
end

local function worldIdentityChanged(previous, current)
    return previous.instanceID ~= current.instanceID
        or previous.instanceType ~= current.instanceType
        or previous.difficultyID ~= current.difficultyID
end

local function sameWorldSample(a, b)
    if not a or not b or a.inInstance ~= b.inInstance then return false end
    if not a.inInstance then return true end
    return a.ready == b.ready
        and a.instanceID == b.instanceID
        and a.instanceType == b.instanceType
        and a.difficultyID == b.difficultyID
end

local function newInstanceTag(snapshot)
    CT._instanceTagSerial = (CT._instanceTagSerial or 0) + 1
    return string.format("%s|%d|%d|%d", snapshot.name or "Unknown",
        snapshot.instanceID or 0, time(), CT._instanceTagSerial)
end

local LIFECYCLE_SCHEMA = 1
local CONTEXT_FIELDS = {
    "combatGeneration", "name", "startTime", "endTime", "instanceTag",
    "instanceDisplayName", "isBoss", "encounterName", "encounterID",
    "difficultyID", "success", "scene", "wasOutdoor", "_completedAt", "_completedWallTime",
    "_rawObserved",
}

local function publicScalar(value)
    local valueType = type(value)
    if valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then return nil end
    if not gatewayAccessible(value) then return nil end
    return value
end

local function copyContextForSave(context)
    if type(context) ~= "table" then return nil end
    local result = {}
    for _, key in ipairs(CONTEXT_FIELDS) do
        local value = publicScalar(context[key])
        if value ~= nil then result[key] = value end
    end
    return next(result) and result or nil
end

local function copyPendingExitForSave(source)
    if type(source) ~= "table" then return nil end
    local tag = publicScalar(source.tag)
    if not tag then return nil end
    return {
        tag = tag,
        level = publicScalar(source.level or source.lvl) or 0,
        mapName = publicScalar(source.mapName),
        instanceName = publicScalar(source.instanceName or source.instName),
        scene = publicScalar(source.scene or source.exitingSceneKey) or "dungeon",
        combatGeneration = publicScalar(source.combatGeneration) or 0,
        hadCombat = source.hadCombat == true,
        overallComplete = source.overallComplete ~= false,
    }
end

local function sameSavedIdentity(saved, current)
    return type(saved) == "table" and current and current.inInstance
        and saved.instanceID == current.instanceID
        and saved.instanceType == current.instanceType
        and saved.difficultyID == current.difficultyID
end

-- Only public primitive metadata is persisted.  Raw C_DamageMeter objects and
-- secret values never enter SavedVariables.  This keeps a reload from creating
-- a new logical instance boundary or losing boss/session attribution.
function CT:PersistLifecycleState()
    if type(LightDamageDB) ~= "table" then return end
    local saved = {schema = LIFECYCLE_SCHEMA, contexts = {}, completed = {}}
    saved.combatGeneration = publicScalar(ns.Segments and ns.Segments._combatGeneration) or 0
    local world = self._worldSnapshot
    if world and world.inInstance and self._currentInstanceTag then
        local tag = self._currentInstanceTag
        saved.active = {
            tag = publicScalar(tag),
            name = publicScalar(self._currentInstanceName or world.name),
            instanceType = publicScalar(self._currentInstanceType or world.instanceType),
            instanceID = publicScalar(world.instanceID) or 0,
            difficultyID = publicScalar(world.difficultyID) or 0,
            scene = publicScalar(self._currentSceneKey or world.scene) or "dungeon",
            level = publicScalar(self._currentMythicLevel) or 0,
            mapName = publicScalar(self._currentMythicMapName),
            overallComplete = self._overallCoverageByTag[tag] == true,
            hadCombat = self._instanceHadCombatByTag[tag] == true,
            entryResetPending = self._entryResetPendingTag == tag,
        }
    end
    saved.pendingExit = copyPendingExitForSave(self._pendingMergeArgs)
    for _, action in ipairs(self._actions or {}) do
        if action.kind == "user-reset" then
            saved.pendingUserReset = true
            break
        elseif action.kind == "meter-reset" and not saved.pendingReset then
            saved.pendingReset = {
                reason = publicScalar(action.reason) or "enter-instance",
                boundaryTag = publicScalar(action.boundaryTag),
                combatGenerationAtQueue = publicScalar(action.combatGenerationAtQueue),
                preKeyCutoffWallTime = publicScalar(action.preKeyCutoffWallTime),
            }
        end
    end
    for sessionID, context in pairs(self._sessionContextByID) do
        if type(sessionID) == "number" and gatewayAccessible(sessionID) then
            local copy = copyContextForSave(context)
            if copy then saved.contexts[#saved.contexts + 1] = {sessionID = sessionID, context = copy} end
        end
    end
    for _, context in ipairs(self._completedContexts) do
        local copy = copyContextForSave(context)
        if copy then saved.completed[#saved.completed + 1] = copy end
    end
    saved.activeCombat = copyContextForSave(self._activeCombatContext)
    local encounter = ns.Segments and ns.Segments.currentBoss
    if encounter then
        saved.encounter = {
            id = publicScalar(encounter.id), name = publicScalar(encounter.name),
            difficulty = publicScalar(encounter.difficulty),
            groupSize = publicScalar(encounter.groupSize),
        }
    end
    if self._mythicRunBoundary then
        saved.mythicBoundary = {
            tag = publicScalar(self._mythicRunBoundary.tag),
            startedAt = publicScalar(self._mythicRunBoundary.startedAt),
        }
    end
    local pendingMythic = ns.MythicPlus and ns.MythicPlus._pendingMythicSeg
    if pendingMythic then
        saved.pendingMythic = {
            name = publicScalar(pendingMythic.name), success = publicScalar(pendingMythic.success),
            level = publicScalar(pendingMythic.level) or 0,
            mapName = publicScalar(pendingMythic.mapName), mapID = publicScalar(pendingMythic.mapID),
            elapsed = publicScalar(pendingMythic.elapsed),
        }
    end
    LightDamageDB.lightDamageLifecycle = saved
end

function CT:RestoreLifecycleState(current)
    local saved = type(LightDamageDB) == "table" and LightDamageDB.lightDamageLifecycle
    if type(saved) ~= "table" or saved.schema ~= LIFECYCLE_SCHEMA then return false, nil end
    local active = saved.active
    local restoredActive = sameSavedIdentity(active, current) and type(active.tag) == "string"
    if restoredActive then
        self._currentInstanceTag = active.tag
        self._currentInstanceName = active.name or current.name
        self._currentInstanceType = active.instanceType or current.instanceType
        self._currentSceneKey = active.scene or current.scene
        self._currentMythicLevel = tonumber(active.level) or 0
        self._currentMythicMapName = active.mapName
        current.instanceTag = active.tag
        self._overallCoverageByTag[active.tag] = active.overallComplete == true
        self._instanceHadCombatByTag[active.tag] = active.hadCombat == true
        if active.entryResetPending then self._entryResetPendingTag = active.tag end
    end

    local pendingExit = copyPendingExitForSave(saved.pendingExit)
    -- Combat generations are local identity tokens, but a pending exit also
    -- persists its token.  Restore both sides of that comparison so a reload
    -- cannot falsely look like "new combat happened" and suppress the full run.
    -- Older lifecycle saves did not carry the explicit field; their pending
    -- exit token is the lossless migration source.
    local restoredGeneration = publicScalar(saved.combatGeneration)
    if type(restoredGeneration) ~= "number" and pendingExit then
        restoredGeneration = pendingExit.combatGeneration
    end
    if type(restoredGeneration) == "number" and ns.Segments then
        ns.Segments._combatGeneration = math.max(0, restoredGeneration)
    end
    self._restoredPendingReset = type(saved.pendingReset) == "table" and {
        reason = publicScalar(saved.pendingReset.reason) or "enter-instance",
        boundaryTag = publicScalar(saved.pendingReset.boundaryTag),
        combatGenerationAtQueue = publicScalar(saved.pendingReset.combatGenerationAtQueue),
        preKeyCutoffWallTime = publicScalar(saved.pendingReset.preKeyCutoffWallTime),
    } or nil
    self._restoredPendingUserReset = saved.pendingUserReset == true
    if not restoredActive and type(active) == "table" and type(active.tag) == "string" then
        pendingExit = pendingExit or copyPendingExitForSave({
            tag = active.tag, level = active.level, mapName = active.mapName,
            instanceName = active.name, scene = active.scene,
            combatGeneration = 0,
            hadCombat = active.hadCombat,
            overallComplete = active.overallComplete,
        })
        self._overallCoverageByTag[active.tag] = active.overallComplete == true
        self._instanceHadCombatByTag[active.tag] = active.hadCombat == true
    end
    if pendingExit then
        self._overallCoverageByTag[pendingExit.tag] = pendingExit.overallComplete ~= false
        self._instanceHadCombatByTag[pendingExit.tag] = pendingExit.hadCombat == true
    end

    for _, item in ipairs(saved.contexts or {}) do
        if type(item) == "table" and type(item.sessionID) == "number"
            and type(item.context) == "table" then
            self._sessionContextByID[item.sessionID] = item.context
        end
    end
    for _, context in ipairs(saved.completed or {}) do
        if type(context) == "table" then
            -- Generations are runtime-local.  A restored unbound context is
            -- matched by FIFO/session publication, never to a new generation.
            context.combatGeneration = nil
            self._completedContexts[#self._completedContexts + 1] = context
        end
    end
    if restoredActive and type(saved.activeCombat) == "table" then
        self._activeCombatContext = saved.activeCombat
    end
    if restoredActive and type(saved.encounter) == "table" and ns.Segments then
        ns.Segments.bossActive = true
        ns.Segments.currentBoss = saved.encounter
    end
    local savedBoundary = saved.mythicBoundary
    local boundaryRelevant = type(savedBoundary) == "table" and type(savedBoundary.tag) == "string"
        and (savedBoundary.tag == self._currentInstanceTag
            or (pendingExit and savedBoundary.tag == pendingExit.tag))
    if boundaryRelevant then self._mythicRunBoundary = savedBoundary end
    if boundaryRelevant and type(saved.pendingMythic) == "table" and ns.MythicPlus then
        ns.MythicPlus._pendingMythicSeg = saved.pendingMythic
    end
    return restoredActive, pendingExit
end

local function captureCombatContext()
    local seg = ns.Segments and ns.Segments.current
    local outdoor = CT._currentSceneKey == "outdoor"
    return {
        combatGeneration = ns.Segments and ns.Segments._combatGeneration or 0,
        name = seg and seg.name or GetZoneText() or L.COMBAT,
        startTime = seg and seg.startTime or GetTime(),
        endTime = GetTime(),
        instanceTag = not outdoor and (seg and seg._instanceTag or CT._currentInstanceTag) or nil,
        instanceDisplayName = not outdoor and (seg and seg._instanceDisplayName or CT._currentInstanceName) or nil,
        isBoss = seg and seg._isBoss or false,
        encounterName = seg and seg.encounterName,
        encounterID = seg and seg.encounterID,
        difficultyID = seg and seg.difficultyID,
        success = seg and seg.success,
        scene = CT._currentSceneKey,
        wasOutdoor = outdoor,
    }
end

local function assignContext(sessionID)
    local context = CT._sessionContextByID[sessionID]
    if context then
        if context.combatGeneration ~= nil then CT._meterObservedGenerations[context.combatGeneration] = nil end
        return context
    end

    -- DAMAGE_METER_COMBAT_SESSION_UPDATED gives us the authoritative session
    -- ID.  Prefer the completed combat with the matching generation instead of
    -- relying solely on FIFO order when Blizzard publishes several sessions
    -- after a delay.
    local expectedGeneration = CT._sessionGenerationByID[sessionID]
    if expectedGeneration ~= nil then
        for index, candidate in ipairs(CT._completedContexts) do
            if candidate.combatGeneration == expectedGeneration then
                context = table.remove(CT._completedContexts, index)
                break
            end
        end
    end
    context = context or table.remove(CT._completedContexts, 1) or {}
    if context.combatGeneration ~= nil then CT._meterObservedGenerations[context.combatGeneration] = nil end
    CT._sessionContextByID[sessionID] = context
    return context
end

local function buildMeta(info, index, context, duration, durationUnknown, allowIncomplete)
    duration = duration or 0
    local sessionName = info.name
    return {
        -- Blizzard combat sessions are all ordinary History entries.  Boss
        -- metadata is retained separately for raid full-run selection; it
        -- must never manufacture a second [Win]/[Loss] display segment.
        type = "history",
        name = sessionName or context.name or GetZoneText() or L.COMBAT,
        duration = duration, startTime = context.startTime or (GetTime() - duration),
        endTime = context.endTime or GetTime(), sessionIdx = index,
        instanceTag = context.instanceTag, instanceDisplayName = context.instanceDisplayName,
        isBoss = context.isBoss, encounterName = context.encounterName,
        encounterID = context.encounterID, difficultyID = context.difficultyID,
        success = context.success,
        combatGeneration = context.combatGeneration,
        completedWallTime = context._completedWallTime,
        wasOutdoor = context.wasOutdoor,
        durationUnknown = durationUnknown,
        allowIncomplete = allowIncomplete,
    }
end

local function hasUnprocessedSessions()
    local _, count = safeSessionCount()
    return (CT._lastProcessedCount or 0) < count
end

function CT:MarkOverallResetPending(instanceTag)
    if not instanceTag then return end
    self._entryResetPendingTag = instanceTag
    self._coverageCombatBeforeReset = false
    self._overallCoverageByTag[instanceTag] = true
end

function CT:MarkOverallResetConfirmed()
    local tag = self._entryResetPendingTag
    if not tag then return end
    self._overallCoverageByTag[tag] = not self._coverageCombatBeforeReset
    if not self._coverageCombatBeforeReset then self._instanceHadCombatByTag[tag] = false end
    self._entryResetPendingTag = nil
    self._coverageCombatBeforeReset = false
    self:PersistLifecycleState()
end

function CT:IsOverallCompleteForTag(instanceTag)
    return instanceTag ~= nil and self._overallCoverageByTag[instanceTag] ~= false
end

function CT:ReleaseOverallCoverage(instanceTag)
    if not instanceTag then return end
    self._overallCoverageByTag[instanceTag] = nil
    self._instanceHadCombatByTag[instanceTag] = nil
    if self._entryResetPendingTag == instanceTag then
        self._entryResetPendingTag = nil
        self._coverageCombatBeforeReset = false
    end
    if self._mythicRunBoundary and self._mythicRunBoundary.tag == instanceTag then
        self._mythicRunBoundary = nil
    end
    self:PersistLifecycleState()
end

function CT:IsSyntheticSessionID(sessionID)
    local generation = G and G:GetRawGeneration() or 0
    return sessionID ~= nil and self._syntheticSessionIDs[sessionID] == generation
end

-- DAMAGE_METER_COMBAT_SESSION_UPDATED is the authoritative publication edge
-- for a finished Blizzard session.  Group combat may remain active after the
-- player's fight has ended, so ns.state.inCombat alone cannot decide whether
-- the final available session belongs in History.
function CT:IsCompletedSessionID(sessionID)
    local generation = G and G:GetRawGeneration() or 0
    return sessionID ~= nil and self._completedSessionIDs[sessionID] == generation
end

local function containsPlain(haystack, needle)
    return type(haystack) == "string" and type(needle) == "string" and needle ~= ""
        and haystack:find(needle, 1, true) ~= nil
end

function CT:IsSyntheticMythicOverall(info, index, count)
    if not info then return false end
    local sessionID = info.sessionID
    if self:IsSyntheticSessionID(sessionID) then return true end
    local pending = ns.MythicPlus and ns.MythicPlus._pendingMythicSeg
    local boundary = self._mythicRunBoundary
    local boundaryIsRelevant = boundary and (boundary.tag == self._currentInstanceTag
        or boundary.tag == self._exitingInstanceTag)
    if not pending or not boundaryIsRelevant then return false end
    local level = tonumber(pending.level or self._currentMythicLevel) or 0
    local sessionName = info.name
    if level <= 0 or type(sessionName) ~= "string" then return false end

    -- 12.0.7 publishes one Blizzard-owned run-wide M+ session alongside the
    -- ordinary combat sessions.  Its position is not a stable API contract, so
    -- never require it to be the final list item.  Structural evidence is
    -- primary: it is supplemental to the real fight or owns no combat context.
    local structural = self._supplementalSessionIDs[sessionID] == true
        or (self._sessionContextByID[sessionID] == nil and boundary.startedAt ~= nil)
    if not structural then return false end

    -- Blizzard does not expose a session-kind field.  Keep the localized name
    -- check only as a compatibility guard so a real encounter can never be
    -- discarded merely because it is the final session.
    local mapName = pending.mapName or self._currentMythicMapName
    local levelMatch = sessionName:find("%+%s*" .. tostring(level)) ~= nil
    local mapMatch = not mapName or containsPlain(sessionName, mapName)
    if not levelMatch or not mapMatch then return false end

    self._syntheticSessionIDs[sessionID] = G and G:GetRawGeneration() or 0
    return true
end

function CT:ClassifyLatestSyntheticMythicOverall()
    -- Avoid walking Blizzard's session list on ordinary History/UI refreshes.
    -- Classification is meaningful only while a completed keystone boundary
    -- still owns its pending metadata.
    if not (ns.MythicPlus and ns.MythicPlus._pendingMythicSeg)
        or not self._mythicRunBoundary then return false end
    local sessions, count = safeSessionCount()
    if not sessions or count <= 0 then return false end
    local matchedID, matchedInfo
    for index = count, 1, -1 do
        local info, infoState = G:ReadField(sessions, index)
        if infoState == G.ACCESSIBLE and type(info) == "table" then
            local sessionID, idState = G:ReadField(info, "sessionID")
            local duration, durationState = G:ReadField(info, "durationSeconds")
            local name, nameState = G:ReadField(info, "name")
            if idState == G.ACCESSIBLE and type(sessionID) == "number"
                and nameState == G.ACCESSIBLE and type(name) == "string" then
                local safeInfo = {
                    sessionID = sessionID,
                    durationSeconds = durationState == G.ACCESSIBLE and duration or nil,
                    name = name,
                }
                if self:IsSyntheticMythicOverall(safeInfo, index, count) and not matchedID then
                    matchedID, matchedInfo = sessionID, safeInfo
                end
            end
        end
    end
    return matchedID ~= nil, matchedID, matchedInfo
end

function CT:GetOfficialMythicOverallSession()
    local found, sessionID, info = self:ClassifyLatestSyntheticMythicOverall()
    if not found then return nil end
    return sessionID, info
end

-- While an automatic boundary is pending, the archive cursor is authoritative:
-- every raw row at or before it has already committed locally.  This remains
-- true across reload even if an earlier build detached legacy session handles.
-- Suppress only the virtual duplicate; never delete either stored history or
-- Blizzard data, and never apply this rule to the user's destructive Reset.
function CT:IsSessionIndexArchivedForPendingBoundary(index)
    if type(index) ~= "number" or index > (self._lastProcessedCount or 0) then return false end
    for _, action in ipairs(self._actions or {}) do
        if action.kind == "merge-instance"
            or (action.kind == "meter-reset" and not action.discardRaw) then
            return true
        end
    end
    return false
end

function CT:ReclassifyPreKeystoneSegments(action)
    if not action or action._preKeystoneReclassified then return true end
    local tag = action.boundaryTag
    if not tag or not ns.Segments then action._preKeystoneReclassified = true; return true end
    local changed = false
    for _, seg in ipairs(ns.Segments.history or {}) do
        local atBoundary
        if action.preKeyCutoffWallTime and seg._completedWallTime then
            atBoundary = seg._completedWallTime <= action.preKeyCutoffWallTime
        else
            atBoundary = action.combatGenerationAtQueue == nil
                or seg._combatGeneration == nil
                or seg._combatGeneration <= action.combatGenerationAtQueue
        end
        if seg._instanceTag == tag and not seg._isMerged and atBoundary then
            seg._instanceTag = nil
            seg._preKeystone = true
            if ns.HistoryStore then ns.HistoryStore:Invalidate(seg) end
            changed = true
        end
    end
    action._preKeystoneReclassified = true
    if changed and ns.SaveSessionHistory then ns:SaveSessionHistory() end
    return true
end

-- Normal combat end keeps Blizzard's session virtual.  Bind Current directly
-- to that official session for post-combat display, but do not copy it into
-- local History until an instance/reset boundary explicitly starts an archive
-- transaction.
local function mutableCurrentSegment()
    local current=ns.Segments and ns.Segments.current
    -- Locally archived rows are immutable and may also be aliased by Current
    -- for presentation. They must never be enriched in place by a late API row.
    if not current or current._localID or current._isMerged then return nil end
    return current
end

function CT:BindFinishedCurrentSession(sessionID, info, generation)
    if not ns.Segments or not ns.Segments.current then return false end
    local currentGeneration = ns.Segments._combatGeneration or 0
    if generation == nil or generation ~= currentGeneration then return false end
    if not gatewayAccessible(sessionID) or type(sessionID) ~= "number" then return false end
    local current=mutableCurrentSegment()
    if not current then return false end
    current._sessionID = sessionID
    current._archiveGeneration = G:GetRawGeneration()
    current.isActive = false

    -- The session identity is authoritative before its optional metadata has
    -- finished publishing.  Bind it immediately so Current never turns blank;
    -- enrich name/duration only when those individual fields are public.
    if info and G:IsTableAccessible(info) then
        local duration, durationState = G:ReadField(info, "durationSeconds")
        local sessionName, nameState = G:ReadField(info, "name")
        if durationState == G.ACCESSIBLE and type(duration) == "number" and duration > 0 then
            current.duration = duration
        end
        if nameState == G.ACCESSIBLE and type(sessionName) == "string" and sessionName ~= "" then
            current.name = sessionName
        end
    end
    return true
end

-- A Damage Meter completion event can precede publication of the same row in
-- GetAvailableCombatSessions.  Reconcile it again after the API settles so an
-- empty local Current shell can never survive merely because one event-time
-- metadata read was early or protected.
function CT:ReconcileFinishedCurrentSession()
    if not G or not ns.Segments or not ns.Segments.current then return false end
    local generation = ns.Segments._combatGeneration or 0
    if self._lastCompletedGeneration ~= generation then return false end

    self:ClassifyLatestSyntheticMythicOverall()
    local current=mutableCurrentSegment()
    if not current then return false end
    local sessions, count = safeSessionCount()
    if not sessions then return false end
    local preferred = self._primarySessionByGeneration[generation]
    if current._archiveGeneration == G:GetRawGeneration() and current._sessionID then
        preferred = current._sessionID
    end

    for index = count, 1, -1 do
        local info, infoState = G:ReadField(sessions, index)
        if infoState == G.ACCESSIBLE and type(info) == "table" then
            local sessionID, idState = G:ReadField(info, "sessionID")
            if idState == G.ACCESSIBLE and type(sessionID) == "number"
                and not self:IsSyntheticSessionID(sessionID) then
                local mappedGeneration = self._sessionGenerationByID[sessionID]
                local completed = self:IsCompletedSessionID(sessionID)
                local belongsToCurrent = sessionID == preferred
                    or mappedGeneration == generation
                    or (completed and self._lastCompletedGeneration == generation)
                if belongsToCurrent then
                    self._sessionGenerationByID[sessionID] = generation
                    self._primarySessionByGeneration[generation] = sessionID
                    self._meterObservedGenerations[generation] = true
                    for _, context in ipairs(self._completedContexts) do
                        if context.combatGeneration == generation then context._rawObserved = true end
                    end
                    return self:BindFinishedCurrentSession(sessionID, info, generation)
                end
            end
        end
    end
    return false
end

function CT:ProcessArchiveTransactions(targetIndex)
    if not G or not ns.Segments then return false, "not-ready" end
    local sessions, count = safeSessionCount()
    if not sessions then return false, "sessions-unavailable" end
    targetIndex = math.min(targetIndex or count, count)
    local index = (self._lastProcessedCount or 0) + 1
    local committedAny = false

    while index <= targetIndex do
        local info, infoState = G:ReadField(sessions, index)
        if infoState == G.SECRET then return false, G.SECRET end
        if infoState ~= G.ACCESSIBLE or type(info) ~= "table" then return false, "session-missing" end
        local sessionID, sessionIDState = G:ReadField(info, "sessionID")
        local duration, durationState = G:ReadField(info, "durationSeconds")
        local sessionName, sessionNameState = G:ReadField(info, "name")
        if sessionIDState == G.SECRET or not gatewayAccessible(sessionID) then
            self._pendingArchiveIndex = index
            self._pendingArchiveReason = G.SECRET
            return false, G.SECRET
        end
        if type(sessionID) ~= "number" then
            self._pendingArchiveIndex = index
            self._pendingArchiveReason = G.ERROR
            return false, G.ERROR
        end
        local now = GetTime()
        self._archiveFirstSeenAt[sessionID] = self._archiveFirstSeenAt[sessionID] or now
        if durationState == G.SECRET or not gatewayAccessible(duration) then
            self._pendingArchiveIndex = index
            self._pendingArchiveReason = G.SECRET
            return false, G.SECRET
        end
        if sessionNameState == G.SECRET or not gatewayAccessible(sessionName) then
            self._pendingArchiveIndex = index
            self._pendingArchiveReason = G.SECRET
            return false, G.SECRET
        end
        local safeInfo = {sessionID = sessionID, durationSeconds = duration, name = sessionName}

        if self:IsSyntheticMythicOverall(safeInfo, index, count) then
            -- Synthetic run-wide rows are an internal, epoch-scoped API detail.
            -- hiddenSessionIDs is reserved exclusively for the player's X action.
            self._sessionContextByID[sessionID] = nil
            self._sessionGenerationByID[sessionID] = nil
            self._lastProcessedCount = index
            self._archiveFirstSeenAt[sessionID] = nil
            index = index + 1
        else
        local durationUnknown = false
        local context

        if duration == nil then
            -- Blizzard explicitly permits nil.  Duration is optional: archive
            -- the official rows immediately, mark it unavailable, and never
            -- substitute the addon's local combat clock.
            duration = 0
            durationUnknown = true
        elseif type(duration) ~= "number" then
            self._pendingArchiveIndex = index
            self._pendingArchiveReason = G.ERROR
            return false, G.ERROR
        end

        context = context or assignContext(sessionID)
        local eventGeneration = self._sessionGenerationByID[sessionID]
        local currentGeneration = ns.Segments._combatGeneration or 0
        local sameGeneration = context.combatGeneration == currentGeneration
        local authoritativeCurrent = eventGeneration ~= nil and eventGeneration == currentGeneration

        -- Every official session is a real History row, including zero-duration
        -- or accidental sessions.  Product semantics are keyed to Blizzard's
        -- publication decision, never to a local minimum-duration heuristic.
        -- Current is a live API view during combat, so its local shell has no
        -- complete statistics.  Bind the authoritative finished session
        -- immediately; immutable archiving may continue in the background.
        local mutableCurrent=mutableCurrentSegment()
        if not ns.state.inCombat and sameGeneration and authoritativeCurrent and mutableCurrent then
            local current=mutableCurrent
            current._sessionID = sessionID
            current._archiveGeneration = G:GetRawGeneration()
            current.name = sessionName or current.name
            current.duration = duration
            current.isActive = false
        end

        local meta = buildMeta(safeInfo, index, context, duration, durationUnknown, false)
        local candidate, status = G:BuildSessionCandidate(sessionID, meta)
        if not candidate then
            self._pendingArchiveIndex = index
            self._pendingArchiveReason = status
            return false, status
        end
        candidate._durationUnknown = durationUnknown or nil

        -- Candidate is complete.  This is the only point at which local
        -- history and the archive cursor are mutated.
        local seg = self:CommitArchiveCandidate(candidate, {prefix = "arch", index = 1})
        if not seg then return false, "commit-failed" end
        self._lastProcessedCount = index
        self._sessionContextByID[sessionID] = nil
        self._sessionGenerationByID[sessionID] = nil
        self._pendingArchiveIndex = nil
        self._pendingArchiveReason = nil
        self._archiveFirstSeenAt[sessionID] = nil
        committedAny = true

        if not ns.state.inCombat and sameGeneration
            and not ns.Segments:GetFullRunOverride() then
            ns.Segments.current = seg
        end
        index = index + 1
        end
    end

    if committedAny then
        if ns.SaveSessionHistory then ns:SaveSessionHistory() end
        if ns.Analysis then ns.Analysis:InvalidateCache() end
    end
    return true, G.ACCESSIBLE
end

function CT:QueueAction(kind, payload)
    payload = payload or {}
    payload.kind = kind
    payload.queuedAt = payload.queuedAt or GetTime()
    payload.combatGenerationAtQueue = payload.combatGenerationAtQueue
        or (ns.Segments and ns.Segments._combatGeneration or 0)
    if payload.throughIndex == nil then
        local _, count = safeSessionCount(); payload.throughIndex = count
    end
    table.insert(self._actions, payload)
    if kind == "merge-instance" then
        -- This is a one-shot, presentation-only notice attached to the
        -- existing pending action.  It neither polls nor mutates the archive
        -- transaction, Current, Total or History.
        C_Timer.After(2, function()
            if payload.noticeShown then return end
            local stillPending = false
            for _, action in ipairs(CT._actions) do
                if action == payload then stillPending = true; break end
            end
            if not stillPending then return end
            payload.noticeShown = true
            local message = L.MSG_LIGHT_DAMAGE_ORGANIZING_INSTANCE_DATA
            if message and UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage(message, 0.30, 0.80, 1.00, 1.0)
            elseif message and RaidNotice_AddMessage and RaidWarningFrame then
                RaidNotice_AddMessage(RaidWarningFrame, message, {r=0.30, g=0.80, b=1.00})
            end
        end)
    end
    self:PersistLifecycleState()
    self:StartWatchdog()
    return payload
end

function CT:HasPendingActions()
    return #self._actions > 0 or self._pendingArchiveIndex ~= nil
end

function CT:IsResetReasonPending(reason)
    for _, action in ipairs(self._actions or {}) do
        if action.kind == "meter-reset" and action.reason == reason then return true end
    end
    return false
end

function CT:CanResetMeter()
    if ns.state.inCombat then return false end
    local _, count = safeSessionCount()
    return (self._lastProcessedCount or 0) >= count
        and self._pendingArchiveIndex == nil
end

local RESET_RETRY_DELAYS = {0, 1.25, 3, 6, 10}

function CT:ReconcileCompletedContexts(action, instanceTag, discardPublished)
    local now = GetTime()
    for index = #self._completedContexts, 1, -1 do
        local context = self._completedContexts[index]
        local relevant = instanceTag == nil or context.instanceTag == instanceTag
        if relevant then
            local observed = context._rawObserved
                or (context.combatGeneration ~= nil
                    and self._meterObservedGenerations[context.combatGeneration] == true)
            if observed then
                if discardPublished then
                    -- Explicit user Reset only needs proof that Blizzard
                    -- published the finished session; the user asked to delete
                    -- it, so consume the metadata shell without archiving.
                    table.remove(self._completedContexts, index)
                else
                    return false
                end
            else
                -- Automatic boundaries never time out a missing core session:
                -- the context survives reload and remains pending until the
                -- official row can be archived.  An explicit destructive Reset
                -- may conclude after the grace window only when Blizzard never
                -- published a session at all.
                if not discardPublished then return false end
                local age
                if type(context._completedWallTime) == "number" then
                    age = math.max(0, time() - context._completedWallTime)
                else
                    age = math.max(0, now - (context._completedAt or now))
                end
                if age < SESSION_PUBLICATION_GRACE then return false end
                table.remove(self._completedContexts, index)
            end
        end
    end
    self:PersistLifecycleState()
    return true
end

function CT:IsBlizzardMeterEmpty()
    if not G then return false end
    local sessions, sessionsState = G:GetAvailableSessionsRaw()
    if sessionsState ~= G.ACCESSIBLE or type(sessions) ~= "table" or #sessions > 0 then return false end
    local overall = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall
    if overall == nil then return false end
    local duration, durationState = G:GetSessionDurationRaw(overall)
    if durationState == G.SECRET or durationState == G.ERROR then return false end
    if duration ~= nil and (type(duration) ~= "number" or duration > 0) then return false end

    local typeNames = {
        "DamageDone", "HealingDone", "DamageTaken", "Deaths",
        "EnemyDamageTaken", "Interrupts", "Dispels",
    }
    for _, typeName in ipairs(typeNames) do
        local dmType = Enum and Enum.DamageMeterType and Enum.DamageMeterType[typeName]
        if dmType ~= nil then
            local session, state = G:GetRawSession(overall, nil, dmType)
            if state == G.SECRET or state == G.ERROR then return false end
            if session then
                local total, totalState = G:ReadField(session, "totalAmount")
                if totalState == G.SECRET or totalState == G.ERROR then return false end
                if total ~= nil and (type(total) ~= "number" or total > 0) then return false end
                local sources, sourcesState = G:ReadTableField(session, "combatSources")
                if sourcesState == G.SECRET or sourcesState == G.ERROR then return false end
                for _, source in ipairs(sources or {}) do
                    local amount, amountState = G:ReadField(source, "totalAmount")
                    if amountState == G.SECRET or amountState == G.ERROR then return false end
                    if amount ~= nil and (type(amount) ~= "number" or amount > 0) then return false end
                end
            end
        end
    end
    return true
end

function CT:ApplyDamageMeterResetState(internal, serial, deferPresentation)
    if internal and serial and (self._appliedResetGeneration or 0) >= serial then return false end
    if internal and serial then self._appliedResetGeneration = serial end
    -- The raw identity epoch is normally advanced immediately before the first
    -- reset API call.  Do not advance it a second time when confirmation arrives.
    local rawEpochAlreadyAdvanced = internal and serial
        and self._rawEpochResetSerial == serial
    if not rawEpochAlreadyAdvanced and G then
        G:InvalidateRaw(internal and "internal-reset" or "external-reset")
    end
    if rawEpochAlreadyAdvanced then self._rawEpochResetSerial = nil end
    local activeTag = self._currentInstanceTag
    if activeTag and self._entryResetPendingTag ~= activeTag
        and self._instanceHadCombatByTag[activeTag] then
        -- A user/foreign mid-run reset makes Blizzard Overall incomplete for
        -- the physical instance.  Exit must use tagged local sessions.
        self._overallCoverageByTag[activeTag] = false
    end
    -- Reset invalidates Blizzard session IDs and the client may reuse them in
    -- the next run.  The archived data is already fully local at this point;
    -- detach only the dead API handles so new virtual sessions cannot be
    -- mistaken for previously archived ones.
    self:ClearLoadedSessionIDs()
    self._baselineSessionCount = 0
    self._lastProcessedCount = 0
    self._initialBaselineSet = true
    self._pendingArchiveIndex = nil
    self._pendingArchiveReason = nil
    if not rawEpochAlreadyAdvanced then
        self._sessionContextByID = {}
        self._sessionGenerationByID = {}
        self._meterObservedGenerations = {}
        self._primarySessionByGeneration = {}
        self._supplementalSessionIDs = {}
        self._syntheticSessionIDs = {}
        self._completedSessionIDs = {}
        self._archiveFirstSeenAt = {}
    end
    if not internal then
        -- An external reset cannot delete or rewrite committed local history.
        -- Pending raw transactions are invalid now and must be abandoned.
        self._completedContexts = {}
    end
    if not deferPresentation and ns.Segments and not ns.Segments:GetFullRunOverride() then
        ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL)
    end
    if ns.Segments and ns.Segments.ClearHiddenSessionIDs then ns.Segments:ClearHiddenSessionIDs() end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    if ns.UI and not deferPresentation then
        ns.UI._sessionCache = {}
        if ns.UI:IsVisible() then ns.UI:Refresh() end
    end
    -- Persist detached handles only after the reset is authoritative.  Saving
    -- them earlier creates a reload state containing both local archives and
    -- the still-live Blizzard rows for the same fights.
    if ns.SaveSessionHistory and not self._performingUserReset then ns:SaveSessionHistory() end
    self:PersistLifecycleState()
    return true
end

function CT:CompleteQueuedUserReset(action)
    self._completedContexts = {}
    self._activeCombatSessionID = nil
    self._activeSessionCountAtStart = nil
    self._performingUserReset = true
    if ns.Segments then
        ns.Segments._performingQueuedReset = true
        ns.Segments:ResetAll()
        ns.Segments._performingQueuedReset = nil
    end
    self._performingUserReset = nil
    if action and action.onComplete then pcall(action.onComplete) end
    return true
end

function CT:CompleteResetActionOnce(action)
    if not action or action._completionRan then return true end
    action._completionRan = true
    if action.kind == "user-reset" then
        return self:CompleteQueuedUserReset(action)
    end
    if action.kind == "meter-reset" and action.discardRaw then
        -- A deliberate destructive boundary (currently the outdoor clear
        -- action) owns no archive transaction.  Do not leave orphan combat
        -- contexts that could block a later normal reset.
        self._completedContexts = {}
    end
    if action.kind == "meter-reset" and action.after then pcall(action.after) end
    return true
end

function CT:FinalizeConfirmedResetAction(serial)
    local action = self._actions[1]
    if not action or action.resetSerial ~= serial then return false end
    self:CompleteResetActionOnce(action)
    if self._actions[1] == action then table.remove(self._actions, 1) end
    self:PersistLifecycleState()
    return true
end

function CT:ConfirmInternalReset(serial, source, finalizeNow)
    if not serial then return false end
    self._confirmedResetGeneration = math.max(self._confirmedResetGeneration or 0, serial)
    if self._internalResetExpected == serial then self._internalResetExpected = nil end
    local grace = source == "empty" and 2 or 0.5
    self._ignoreResetEventsUntil = math.max(self._ignoreResetEventsUntil or 0, GetTime() + grace)
    self._resetSettleUntil = math.max(self._resetSettleUntil or 0, GetTime() + grace)
    local action = self._actions[1]
    local isUserReset = action and action.resetSerial == serial and action.kind == "user-reset"
    self:ApplyDamageMeterResetState(true, serial, isUserReset)
    self:MarkOverallResetConfirmed()
    if finalizeNow then self:FinalizeConfirmedResetAction(serial) end
    self:StartWatchdog()
    return true
end

function CT:HasPostResetCombatEvidence(action)
    if not action or not action.rawEpochBegan then return false end
    local captured = action.combatGenerationAtReset
    local current = ns.Segments and ns.Segments._combatGeneration or 0
    return type(captured) == "number" and current > captured
end

function CT:IsCombatBeforePendingReset(combatGeneration)
    for _, action in ipairs(self._actions) do
        if action.kind == "meter-reset" and action.rawEpochBegan then
            local captured = action.combatGenerationAtReset
            return type(captured) ~= "number" or combatGeneration <= captured
        end
    end
    -- No reset call has been issued yet, so this combat is part of the
    -- pre-reset coverage that official Overall cannot represent completely.
    return true
end

-- Reset is a two-phase transaction.  Calling the API without an error only
-- means that the request was accepted (or intercepted by another addon).  The
-- action completes after DAMAGE_METER_RESET, or after the public session list
-- and every supported Overall statistic independently prove the meter empty.
function CT:ExecuteMeterReset(reason, action)
    action = action or {}
    local resetAPI = C_DamageMeter and C_DamageMeter.ResetAllCombatSessions
    if type(resetAPI) ~= "function" then return false, "api-missing" end
    if not action.resetSerial then
        if GetTime() < (self._resetSettleUntil or 0) then return false, "reset-settling" end
        if not action.discardRaw and not self:CanResetMeter() then return false, "archive-pending" end
        self._resetGeneration = self._resetGeneration + 1
        action.resetSerial = self._resetGeneration
        action.resetAttempts = 0
        self._internalResetExpected = action.resetSerial
    end

    if not action.rawEpochBegan then
        -- Archive and presentation identities remain attached until reset is
        -- confirmed.  If Blizzard accepts the request asynchronously, the old
        -- raw rows therefore stay deduplicated and the M+ official-overall row
        -- stays filtered instead of reappearing as a second History entry.
        -- ApplyDamageMeterResetState performs the generation switch and handle
        -- detachment atomically after event/observable-empty confirmation.
        action.combatGenerationAtReset = ns.Segments
            and ns.Segments._combatGeneration or 0
        action.rawEpochBegan = true
    end

    if (self._confirmedResetGeneration or 0) >= action.resetSerial then
        return true, "reset-confirmed"
    end

    -- Some clients/wrappers can clear an already-empty meter without emitting
    -- another event.  Empty session list + zero Overall duration is an
    -- authoritative observable post-condition, not a timeout/fail-open.
    if (action.resetAttempts or 0) > 0 and self:IsBlizzardMeterEmpty() then
        self:ConfirmInternalReset(action.resetSerial, "empty", false)
        return true, "reset-confirmed-empty"
    end

    -- A combat generation born after the first reset request belongs to the
    -- new raw epoch.  Never issue a second ResetAllCombatSessions against it;
    -- wait for the matching reset event instead, even if that short fight has
    -- already ended and ns.state.inCombat is false again.
    if (action.resetAttempts or 0) > 0 and self:HasPostResetCombatEvidence(action) then
        return false, "reset-confirmation-pending"
    end

    local attempts = action.resetAttempts or 0
    local retryDelay = RESET_RETRY_DELAYS[math.min(attempts + 1, #RESET_RETRY_DELAYS)]
    local now = GetTime()
    if action.lastResetAttemptAt and now - action.lastResetAttemptAt < retryDelay then
        return false, "reset-pending"
    end

    action.lastResetAttemptAt = now
    action.resetAttempts = attempts + 1
    self._insideResetCall = true
    local ok = pcall(resetAPI)
    self._insideResetCall = nil
    if not ok then return false, "reset-failed" end
    if (self._confirmedResetGeneration or 0) >= action.resetSerial then
        return true, "reset-confirmed"
    end
    if self:IsBlizzardMeterEmpty() then
        self:ConfirmInternalReset(action.resetSerial, "empty", false)
        return true, "reset-confirmed-empty"
    end
    return false, "reset-pending"
end

function CT:HandleDamageMeterReset()
    local internalSerial = self._internalResetExpected
    if internalSerial then
        -- The event is authoritative, but wait until its public post-condition
        -- is visible before allowing Total/callbacks to advance.  The one valid
        -- non-empty post-condition is a new combat that began after our reset
        -- request: in that case the matching reset event is the boundary proof,
        -- and retrying ResetAllCombatSessions would erase the new fight.
        local action = self._actions[1]
        local postResetCombat = action and action.resetSerial == internalSerial
            and self:HasPostResetCombatEvidence(action)
        if not self:IsBlizzardMeterEmpty() and not postResetCombat then
            self:StartWatchdog()
            return
        end
        self:ConfirmInternalReset(internalSerial, "event", not self._insideResetCall)
        return
    end
    -- An event arriving just after an observable-empty confirmation belongs to
    -- that already-applied serial; never reinterpret it as an external reset.
    if GetTime() < (self._ignoreResetEventsUntil or 0) then return end
    self:ApplyDamageMeterResetState(false)
    self:StartWatchdog()
end

function CT:PerformQueuedUserReset(action)
    if ns.state.inCombat then return false end
    local reset = self:ExecuteMeterReset("user-reset", action)
    if not reset then return false end
    return self:CompleteResetActionOnce(action)
end

function CT:DrainActions(archiveReady)
    local action = self._actions[1]
    if not action then return true end
    if ns.state.inCombat then return false end
    if archiveReady == false then return false end

    local done = false
    if action.kind == "user-reset" then
        -- A combat-time Reset is an explicit delete, not an archive request,
        -- but it must still wait for Blizzard to finish publishing the combat
        -- that just ended.  This prevents a reset racing the session-finalize
        -- event while keeping the soon-to-be-deleted session out of local
        -- History.  ReconcileCompletedContexts has a bounded "no session was
        -- produced" path; an observed/pending publication continues waiting.
        if not self:ReconcileCompletedContexts(action, nil, true) then return false end
        done = self:PerformQueuedUserReset(action)
    elseif action.kind == "meter-reset" then
        -- Before clearing Blizzard state, also archive any combat that started
        -- while this reset was waiting (notably outdoor combat after an exit).
        if hasUnprocessedSessions() then return false end
        if not self:ReconcileCompletedContexts(action) then return false end
        if action.reason == "challenge-start" then self:ReclassifyPreKeystoneSegments(action) end
        if not action.rawEpochBegan and self._entryResetPendingTag
            and self._coverageCombatBeforeReset then
            -- The new instance's first combat beat an entry/key reset that had
            -- not yet been issued.  Never "catch up" after that fight: doing so
            -- would erase the new run's official Overall.  Keep all archived
            -- rows, mark Overall coverage incomplete so exit uses tag-isolated
            -- local fallback, and finish only the non-destructive callback.
            local tag = self._entryResetPendingTag
            self._overallCoverageByTag[tag] = false
            self._entryResetPendingTag = nil
            self._coverageCombatBeforeReset = false
            done = true
            self:CompleteResetActionOnce(action)
        else
            done = self:ExecuteMeterReset(action.reason, action)
            if done then self:CompleteResetActionOnce(action) end
        end
    elseif action.kind == "merge-instance" then
        -- The session list can lag combat end.  A completed context is the
        -- authoritative indication that one more raw archive is still owed.
        if hasUnprocessedSessions() then return false end
        if not self:ReconcileCompletedContexts(action, action.tag) then return false end
        if self.MergeAndCleanInstance then
            done = self:MergeAndCleanInstance(action.tag, action.level, action.mapName,
                action.instanceName, action.scene, action.combatGeneration, false) == true
        end
    elseif action.kind == "callback" then
        done = true
        if action.callback then pcall(action.callback) end
    end
    if done then
        table.remove(self._actions, 1)
        self:PersistLifecycleState()
    end
    return done
end

function CT:WatchdogTick()
    -- Combat-end and Damage Meter events restart the worker.  There is no value
    -- in repeatedly walking archive candidates while the raw session is live.
    -- The group-combat flag can outlive Blizzard's completed-session event and
    -- can also survive until the loading screen when leaving an instance.  Give
    -- the event-driven worker one authoritative resync before deciding to stop;
    -- otherwise an exit merge queued during that stale window is abandoned.
    if ns.state.inCombat then
        syncCombatState()
        if ns.state.inCombat then return true end
    end
    local reboundCurrent = self:ReconcileFinishedCurrentSession()
    local dirty = G and G:ConsumeDirty()
    local hadDirty = dirty and next(dirty) ~= nil
    local beforeCursor = self._lastProcessedCount or 0
    local beforeActions = #self._actions
    local beforePending = self._pendingArchiveIndex
    local beforeResetGeneration = self._confirmedResetGeneration or 0
    local firstAction = self._actions[1]
    local needsArchive = self:HasPendingActions() and not (firstAction and firstAction.discardRaw)
    local archiveReady = true
    if needsArchive then archiveReady = self:ProcessArchiveTransactions() end
    local progressed = self:DrainActions(archiveReady)
    local changed = reboundCurrent or beforeCursor ~= (self._lastProcessedCount or 0)
        or beforeActions ~= #self._actions
        or beforePending ~= self._pendingArchiveIndex
    local resetOccurred = beforeResetGeneration ~= (self._confirmedResetGeneration or 0)
    if not resetOccurred and (hadDirty or changed) and ns.Segments
        and not ns.Segments:GetFullRunOverride() and not ns.state.inCombat then
        self:RebuildOverall()
    end
    if (hadDirty or changed) and ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
    return progressed and not self:HasPendingActions()
end

function CT:StartWatchdog()
    if self._watchdog or self._watchdogRestartPending then return end
    self._watchdogTicks = 0
    local slow = self._watchdogSlow == true
    self._watchdog = C_Timer.NewTicker(slow and 5 or 0.25, function()
        CT._watchdogTicks = CT._watchdogTicks + 1
        local settled = CT:WatchdogTick()
        if settled then
            CT._watchdog:Cancel(); CT._watchdog = nil
            CT._watchdogSlow = nil
        elseif not slow and CT._watchdogTicks >= 40 then
            CT._watchdog:Cancel(); CT._watchdog = nil
            CT._watchdogSlow = true
            CT._watchdogRestartPending = true
            -- Secret/deferred API data can outlive the fast ten-second window.
            -- Continue only while work exists, at a low five-second cadence.
            C_Timer.After(5, function()
                CT._watchdogRestartPending = nil
                if CT:HasPendingActions() or hasUnprocessedSessions() then CT:StartWatchdog() end
            end)
        end
    end)
end

function CT:QueueUserReset(onComplete)
    for _, action in ipairs(self._actions) do
        if action.kind == "user-reset" then
            if onComplete then
                local previous = action.onComplete
                action.onComplete = function()
                    if previous then pcall(previous) end
                    pcall(onComplete)
                end
            end
            return action
        end
    end
    -- Explicit reset means delete.  It supersedes merge/archive work and clears
    -- Current, Total and History only after the server reset is confirmed.
    self._actions = {}
    self._pendingArchiveIndex = nil
    self._pendingArchiveReason = nil
    return self:QueueAction("user-reset", {
        reason = "user-reset", discardRaw = true, onComplete = onComplete,
    })
end

function CT:RequestMeterReset(reason, after, boundaryTag)
    -- Core and the lifecycle coordinator can observe the same zone transition.
    -- One physical ResetAll satisfies every not-yet-started boundary request.
    -- Coalesce across queued callbacks (not only adjacent/same-tag requests) so
    -- A->B->keystone transitions cannot erase B's first combat with a later
    -- duplicate reset.
    local pending = self._actions[#self._actions]
    if not (pending and pending.kind == "meter-reset" and not pending.resetSerial) then
        pending = nil
        for _, queued in ipairs(self._actions) do
            if queued.kind == "meter-reset" and not queued.resetSerial then pending = queued; break end
        end
    end
    if pending then
        if after then
            local previous = pending.after
            pending.after = function()
                if previous then pcall(previous) end
                pcall(after)
            end
        end
        if reason == "challenge-start" or pending.reason ~= "challenge-start" then
            pending.reason = reason or pending.reason
            pending.boundaryTag = boundaryTag or pending.boundaryTag
        end
        self:StartWatchdog()
        return pending
    end
    return self:QueueAction("meter-reset", {reason = reason, after = after, boundaryTag = boundaryTag})
end

function CT:ResetMeterForNewRun(after)
    if not ns.state.isInInstance then
        -- This compatibility entry point is used by the explicit "clear
        -- outdoor" action.  If a lifecycle reset is already queued, let it
        -- archive the instance first; otherwise enqueue a destructive reset
        -- without abusing the player's persistent History blacklist.
        local function finishOutdoorClear()
            if ns.Segments and ns.Segments.HideWhere then
                ns.Segments:HideWhere(function(seg)
                    return seg._wasOutdoor and not seg._isBoss and not seg._isMerged
                end)
            end
            if after then pcall(after) end
            if ns.SaveSessionHistory then ns:SaveSessionHistory() end
        end
        for _, queued in ipairs(self._actions) do
            if queued.kind == "meter-reset" then
                local previous = queued.after
                queued.after = function()
                    if previous then pcall(previous) end
                    finishOutdoorClear()
                end
                self:StartWatchdog()
                return queued
            end
        end
        return self:QueueAction("meter-reset", {
            reason = "new-run", after = finishOutdoorClear,
            boundaryTag = self._currentInstanceTag, discardRaw = true,
        })
    end
    return self:RequestMeterReset("new-run", after, self._currentInstanceTag)
end

function CT:MarkReset()
    if self._performingUserReset then return end
    if ns.state.inCombat then self:QueueUserReset()
    else self:RequestMeterReset("legacy-reset") end
end

function CT:ClearLoadedSessionIDs()
    local segments = ns.Segments
    for _, seg in ipairs(segments and segments.history or {}) do
        -- Every Blizzard session handle becomes invalid at reset, regardless
        -- of a legacy segment's old _dataLoaded flag.  Leaving a stale ID on a
        -- local History row can hide a newly reused session ID from the virtual
        -- list after the next combat.
        if seg._sessionID then
            seg._sessionID = nil
            seg._sessionIdx = nil
            if ns.HistoryStore then ns.HistoryStore:Invalidate(seg) end
        end
    end
    self._sessionContextByID = {}
end

function CT:SetBaseline()
    local sessions, count = safeSessionCount()
    local saved = ns.db and ns.db.savedLastProcessed
    local cursor
    if type(saved) == "number" then
        cursor = math.max(0, math.min(saved, count))
    else
        cursor = count
    end

    -- On a reload during combat the last entry is the live session.  It must
    -- remain ahead of the cursor so the completed version is archived later.
    local latest = sessions and sessions[count]
    local latestDuration, latestDurationState = G:ReadField(latest, "durationSeconds")
    if latestDurationState == G.ACCESSIBLE
        and type(latestDuration) == "number" and latestDuration <= 0 then
        cursor = math.min(cursor, math.max(0, count - 1))
    end
    self._baselineSessionCount = cursor
    self._lastProcessedCount = cursor
    self._initialBaselineSet = true
end

function CT:ResetBaselineToCurrentCount()
    -- Kept for Core/UI compatibility.  Entering a run must archive first, so
    -- this legacy call now schedules a coordinated meter reset.
    return self:RequestMeterReset("baseline-to-current")
end

function CT:OnCombatEnded()
    local finishedContext = captureCombatContext()
    local context = self._activeCombatContext or finishedContext
    context.endTime = finishedContext.endTime
    for _, key in ipairs({"name", "isBoss", "encounterName", "encounterID", "difficultyID", "success"}) do
        if type(finishedContext[key]) ~= "nil" then context[key] = finishedContext[key] end
    end
    local generation = context.combatGeneration
    context._completedAt = GetTime()
    context._completedWallTime = time()
    self._lastCompletedGeneration = generation
    local sessionID = self._activeCombatSessionID or self._primarySessionByGeneration[generation]
    local sessions, count = safeSessionCount()
    if not sessionID and sessions and self._activeSessionCountAtStart ~= nil
        and count > self._activeSessionCountAtStart then
        local latest = sessions[count]
        if latest and G and G:IsTableAccessible(latest) and gatewayAccessible(latest.sessionID)
            and type(latest.sessionID) == "number" then
            sessionID = latest.sessionID
        end
    end

    if sessionID then
        self._completedSessionIDs[sessionID] = G and G:GetRawGeneration() or 0
        context._rawObserved = true
        self._primarySessionByGeneration[generation] = self._primarySessionByGeneration[generation] or sessionID
        local mutableCurrent=mutableCurrentSegment()
        if mutableCurrent
            and generation == (ns.Segments._combatGeneration or 0) then
            -- Bind the identity immediately so History cannot briefly expose a
            -- duplicate while duration/name fields finish publishing.
            mutableCurrent._sessionID = sessionID
            mutableCurrent._archiveGeneration = G:GetRawGeneration()
            mutableCurrent.isActive = false
        end
        self._sessionContextByID[sessionID] = context
        self._sessionGenerationByID[sessionID] = generation
        local latest = sessions and sessions[count]
        if latest and G and G:IsTableAccessible(latest)
            and gatewayAccessible(latest.sessionID) and latest.sessionID == sessionID then
            self:BindFinishedCurrentSession(sessionID, latest, generation)
        end
    else
        -- Keep the metadata even when the raw event is late.  Unobserved
        -- contexts do not block a reset; a later session event can still bind
        -- the matching generation without losing instance/boss information.
        context._rawObserved = self._meterObservedGenerations[generation] == true
        table.insert(self._completedContexts, context)
        -- Never cap/drop unresolved core contexts.  They are normally short-
        -- lived, but if Blizzard delays publication they must survive the
        -- boundary and `/reload` instead of being rebound to a later fight.
    end
    self._activeCombatSessionID = nil
    self._activeSessionCountAtStart = nil
    self._activeCombatGeneration = nil
    self._activeCombatContext = nil
    if G then G:MarkDirty("combat-ended") end
    self:PersistLifecycleState()
    self:StartWatchdog()
    if ns.HistoryList and ns.HistoryList.IsOpen and ns.HistoryList:IsOpen() then
        ns.HistoryList:Rebuild()
    end
end

function CT:OnCombatStarted()
    local combatGeneration = ns.Segments and ns.Segments._combatGeneration or 0
    if self._activeCombatGeneration == combatGeneration then return end
    self._activeCombatGeneration = combatGeneration
    local sessions, count = safeSessionCount()
    self._activeSessionCountAtStart = sessions and count or nil
    self._activeCombatSessionID = nil
    local latest = sessions and sessions[count]
    if latest and G and G:IsTableAccessible(latest) and gatewayAccessible(latest.durationSeconds)
        and type(latest.durationSeconds) == "number" and latest.durationSeconds <= 0
        and gatewayAccessible(latest.sessionID)
        and type(latest.sessionID) == "number" then
        self._activeCombatSessionID = latest.sessionID
        self._meterObservedGenerations[combatGeneration] = true
    end
    if ns.Segments and ns.Segments.current then
        local seg = ns.Segments.current
        local outdoor = self._currentSceneKey == "outdoor"
        seg._instanceTag = not outdoor and self._currentInstanceTag or nil
        seg._instanceDisplayName = not outdoor and self._currentInstanceName or nil
        seg._scene = self._currentSceneKey
    end
    self._activeCombatContext = captureCombatContext()
    -- During a delayed exit merge the old instance tag intentionally remains
    -- alive as frozen transaction metadata.  It is not the active ownership
    -- tag of a new outdoor combat and must not affect had-combat/coverage state.
    local tag = self._currentSceneKey ~= "outdoor" and self._currentInstanceTag or nil
    if tag then
        self._instanceHadCombatByTag[tag] = true
        if self._entryResetPendingTag == tag
            and self:IsCombatBeforePendingReset(combatGeneration) then
            self._coverageCombatBeforeReset = true
            self._overallCoverageByTag[tag] = false
        end
    end
    if self._activeCombatSessionID then
        self._primarySessionByGeneration[combatGeneration] = self._activeCombatSessionID
    end
    self:PersistLifecycleState()
end

function CT:StartCombatEdgeWatcher()
    if self._combatEdgeWatcher or not ns.state.inCombat then return end
    local ticks = 0
    self._combatEdgeWatcher = C_Timer.NewTicker(0.5, function()
        ticks = ticks + 1
        syncCombatState()
        if not ns.state.inCombat or ticks >= 240 then
            CT._combatEdgeWatcher:Cancel()
            CT._combatEdgeWatcher = nil
        end
    end)
end

function CT:BeginMythicRun(afterReset)
    local tag = self._currentInstanceTag
    self._mythicRunBoundary = {tag = tag, startedAt = GetTime()}
    self:MarkOverallResetPending(tag)
    -- Reclassification runs in DrainActions after every pre-key virtual session
    -- has been atomically archived, immediately before the confirmed reset.
    local action = self:RequestMeterReset("challenge-start", afterReset, self._currentInstanceTag)
    action.preKeyCutoffWallTime = time()
    self:PersistLifecycleState()
    return action
end

function CT:QueueInstanceMerge(snapshot, boundaryCombatGeneration)
    local instanceTag = self._currentInstanceTag or (snapshot and snapshot.instanceTag)
    if not instanceTag then return end
    local _, count = safeSessionCount()
    local instanceName = self._currentInstanceName or (snapshot and snapshot.name)
    local scene = self._currentSceneKey or (snapshot and snapshot.scene) or "dungeon"
    local level = self._currentMythicLevel or 0
    local mapName = self._currentMythicMapName
    local combatGeneration = type(boundaryCombatGeneration) == "number"
        and boundaryCombatGeneration
        or (ns.Segments and ns.Segments._combatGeneration or 0)
    self._pendingMergeArgs = {
        tag = instanceTag, lvl = level,
        mapName = mapName, instName = instanceName,
        exitingSceneKey = scene,
        combatGeneration = combatGeneration,
        hadCombat = self._instanceHadCombatByTag[instanceTag] == true,
        overallComplete = self._overallCoverageByTag[instanceTag] ~= false,
    }
    self._exitingInstanceTag = instanceTag
    -- The dedicated Blizzard M+ run-wide session is already immutable at this
    -- boundary.  Materialize it before the slower per-fight archive/reset
    -- cleanup so the player sees the full run immediately after zoning out.
    if scene == "mplus" and self.MaterializeOfficialMythicFullRun then
        self:MaterializeOfficialMythicFullRun(instanceTag, level, mapName,
            instanceName, combatGeneration)
    end
    self:QueueAction("merge-instance", {
        throughIndex = count, tag = instanceTag,
        level = level, mapName = mapName,
        instanceName = instanceName, scene = scene,
        combatGeneration = combatGeneration,
    })
    self:PersistLifecycleState()
end

-- Fast presentation and destructive cleanup deliberately use different
-- boundaries.  Two consistent post-PLAYER_ENTERING_WORLD outdoor samples are
-- enough to publish Blizzard's immutable M+ summary, but never authorize raw
-- archiving or ResetAllCombatSessions.  The strict 1.5-second boundary below
-- remains the sole owner of those destructive operations.
function CT:TryFastPublishMythicExit(previous, current, pewSerial, combatGeneration)
    if not previous or not previous.inInstance or current.inInstance then return false end
    local scene = self._currentSceneKey or previous.scene
    if scene ~= "mplus" or not self.MaterializeOfficialMythicFullRun then return false end
    if pewSerial <= (self._consumedPlayerEnteringWorldSerial or 0) then return false end
    local tag = self._currentInstanceTag or previous.instanceTag
    if not tag then return false end
    local fullRun = self:MaterializeOfficialMythicFullRun(tag,
        self._currentMythicLevel or 0, self._currentMythicMapName,
        self._currentInstanceName or previous.name, combatGeneration)
    return fullRun ~= nil
end

function CT:HandleWorldTransition()
    if ns.UpdateInstanceStatus then ns:UpdateInstanceStatus() end
    -- Leaving an instance removes the party/raid combat units immediately, but
    -- PLAYER_REGEN_ENABLED is not guaranteed to be the last event we observe.
    -- Clear a stale group-combat state before queueing the exit transaction so
    -- its watchdog can archive and materialize the run-wide segment.
    syncCombatState()
    local current = instanceSnapshot()
    -- Do not replace a confirmed instance identity with half-populated loading
    -- screen metadata.  A later scheduled probe will commit the stable value.
    if current.inInstance and not current.ready then return false end
    local previous = self._worldSnapshot
    local acceptedBoundaryGeneration

    -- Loading screens can briefly report an outdoor or half-updated identity.
    -- A boundary can cause an eventual destructive meter reset.  Complete
    -- instance identities need two stable samples; an instance->outdoor edge
    -- additionally requires PLAYER_ENTERING_WORLD authorization and remains
    -- stable through the two-second probe.  ZONE_CHANGED_NEW_AREA alone can
    -- propose a candidate but can never authorize data deletion.  A
    -- same-map/same-difficulty A->B switch with no public identity change is
    -- intentionally not a boundary: preserving data wins over a guessed reset.
    local isBoundary = previous and (previous.inInstance ~= current.inInstance
        or (previous.inInstance and current.inInstance
            and worldIdentityChanged(previous, current)))
    if isBoundary then
        local outdoorExit = previous.inInstance and not current.inInstance
        local pewSerial = self._playerEnteringWorldSerial or 0
        if outdoorExit and (pewSerial <= (self._consumedPlayerEnteringWorldSerial or 0)
            or GetTime() - (self._playerEnteringWorldAt or 0) > 15) then
            return false
        end
        if not sameWorldSample(self._pendingWorldSnapshot, current)
            or (outdoorExit and self._pendingWorldPEWSerial ~= pewSerial) then
            self._pendingWorldSnapshot = current
            self._pendingWorldSnapshotAt = GetTime()
            self._pendingWorldSnapshotCount = 1
            self._pendingWorldPEWSerial = outdoorExit and pewSerial or nil
            local currentCombatGeneration = ns.Segments
                and ns.Segments._combatGeneration or 0
            self._pendingWorldCombatGeneration = outdoorExit
                and type(self._playerEnteringWorldCombatGeneration) == "number"
                and self._playerEnteringWorldCombatGeneration
                or currentCombatGeneration
            return false
        end
        self._pendingWorldSnapshotCount = (self._pendingWorldSnapshotCount or 1) + 1
        local pendingAge = GetTime() - (self._pendingWorldSnapshotAt or GetTime())
        if outdoorExit and self._pendingWorldSnapshotCount >= 2 and pendingAge >= 0.08 then
            self:TryFastPublishMythicExit(previous, current, pewSerial,
                self._pendingWorldCombatGeneration)
        end
        local minimumGap = outdoorExit and 1.5 or 0.20
        local minimumSamples = outdoorExit and 3 or 2
        if self._pendingWorldSnapshotCount < minimumSamples
            or pendingAge < minimumGap then
            return false
        end
        acceptedBoundaryGeneration = self._pendingWorldCombatGeneration
        if outdoorExit then self._consumedPlayerEnteringWorldSerial = pewSerial end
        self._pendingWorldSnapshot = nil
        self._pendingWorldSnapshotAt = nil
        self._pendingWorldSnapshotCount = nil
        self._pendingWorldPEWSerial = nil
        self._pendingWorldCombatGeneration = nil
    else
        self._pendingWorldSnapshot = nil
        self._pendingWorldSnapshotAt = nil
        self._pendingWorldSnapshotCount = nil
        self._pendingWorldPEWSerial = nil
        self._pendingWorldCombatGeneration = nil
        if current.inInstance and current.ready
            and (self._playerEnteringWorldSerial or 0) > (self._consumedPlayerEnteringWorldSerial or 0) then
            self._consumedPlayerEnteringWorldSerial = self._playerEnteringWorldSerial
        end
    end

    -- If the outdoor sample was missed and we landed directly in another
    -- instance, clear the old Mythic+ runtime latch and resolve the new scene
    -- again before freezing its identity.
    if previous and previous.inInstance and current.inInstance
        and worldIdentityChanged(previous, current)
        and ns.state.inMythicPlus then
        if ns.MythicPlus and ns.MythicPlus.IsActive and ns.MythicPlus:IsActive() then
            ns.MythicPlus:OnLeaveInstance()
        end
        ns.state.mplusRuntimeLatch = false
        ns.state.inMythicPlus = false
        if ns.db then ns.db.mplusResetLatch = nil end
        if ns.UpdateInstanceStatus then ns:UpdateInstanceStatus("LIGHTDAMAGE_INSTANCE_SWITCH") end
        current = instanceSnapshot()
    end
    if not previous then
        self._worldSnapshot = current
        if current.inInstance then
            self._currentInstanceTag = newInstanceTag(current)
            current.instanceTag = self._currentInstanceTag
            self._currentInstanceName = current.name
            self._currentInstanceType = current.instanceType
            self._currentSceneKey = current.scene
            self._overallCoverageByTag[self._currentInstanceTag] = true
        end
        return
    end

    if previous.inInstance and not current.inInstance then
        self._worldSnapshot = current
        self:QueueInstanceMerge(previous, acceptedBoundaryGeneration)
        self._currentSceneKey = "outdoor"
        -- Keep old tag/name until merge transaction commits.
    elseif not previous.inInstance and current.inInstance then
        self._worldSnapshot = current
        self._currentMythicLevel = 0
        self._currentMythicMapName = nil
        self._currentInstanceTag = newInstanceTag(current)
        current.instanceTag = self._currentInstanceTag
        self._currentInstanceName = current.name
        self._currentInstanceType = current.instanceType
        self._currentSceneKey = current.scene
        self:MarkOverallResetPending(self._currentInstanceTag)
        self:RequestMeterReset("enter-instance", function()
            if ns.Segments then ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL) end
        end, self._currentInstanceTag)
    elseif previous.inInstance and current.inInstance and worldIdentityChanged(previous, current) then
        self:QueueInstanceMerge(previous, acceptedBoundaryGeneration)
        self._worldSnapshot = current
        self._currentMythicLevel = 0
        self._currentMythicMapName = nil
        self._currentInstanceTag = newInstanceTag(current)
        current.instanceTag = self._currentInstanceTag
        self._currentInstanceName = current.name
        self._currentInstanceType = current.instanceType
        self._currentSceneKey = current.scene
        -- The old instance merge owns the one physical meter reset.  Mark the
        -- new tag as waiting for that reset instead of enqueueing a competing
        -- second reset which could erase the new run's first combat.
        self:MarkOverallResetPending(self._currentInstanceTag)
    else
        current.instanceTag = previous.instanceTag or self._currentInstanceTag
        self._worldSnapshot = current
        self._currentSceneKey = current.scene
    end
    self:PersistLifecycleState()
end

function CT:ScheduleWorldTransitionChecks(event)
    if event == "PLAYER_ENTERING_WORLD" then
        self._playerEnteringWorldSerial = (self._playerEnteringWorldSerial or 0) + 1
        self._playerEnteringWorldAt = GetTime()
        self._playerEnteringWorldCombatGeneration = ns.Segments
            and ns.Segments._combatGeneration or 0
    end
    self._worldTransitionToken = (self._worldTransitionToken or 0) + 1
    local token = self._worldTransitionToken
    local function check()
        if token == CT._worldTransitionToken then CT:HandleWorldTransition() end
    end
    -- Map/instance metadata can remain stale well beyond the loading screen.
    -- These event-scoped probes are bounded and have no steady-state CPU cost.
    for _, delay in ipairs({0, 0.10, 0.35, 1, 2, 4, 8, 12}) do
        C_Timer.After(delay, check)
    end
end

function CT:PullCurrentData()
    syncCombatState()
    if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
end

function CT:RegisterEvents()
    if self._frame then return end
    local frame = CreateFrame("Frame")
    self._frame = frame
    local events = {
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
        "CHALLENGE_MODE_RESET", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
        "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    }
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            if not ns.state.inCombat then ns:EnterCombat() end
            CT:OnCombatStarted()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if ns.state.inCombat and not isGroupInCombat() then ns:LeaveCombat() end
            if ns.state.inCombat then CT:StartCombatEdgeWatcher() end
            CT:StartWatchdog()
        elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
            syncCombatState()
            if ns.state.inCombat and ns.Segments then
                local generation = ns.Segments._combatGeneration or 0
                local sessions, count = safeSessionCount()
                local latest = sessions and sessions[count]
                if latest and G and G:IsTableAccessible(latest)
                    and gatewayAccessible(latest.durationSeconds)
                    and type(latest.durationSeconds) == "number" and latest.durationSeconds <= 0
                    and gatewayAccessible(latest.sessionID) and type(latest.sessionID) == "number" then
                    CT._activeCombatSessionID = latest.sessionID
                    CT._primarySessionByGeneration[generation] = latest.sessionID
                    CT._meterObservedGenerations[generation] = true
                end
            end
            if ns.state.inCombat and not UnitAffectingCombat("player") then CT:StartCombatEdgeWatcher() end
            if G then G:MarkDirty("current") end
            if ns.RequestRefresh then ns:RequestRefresh("damage-meter-current") end
        elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
            local damageMeterType, sessionID = ...
            if damageMeterType == Enum.DamageMeterType.DamageDone
                and G and G:IsAccessible(sessionID) and type(sessionID) == "number" and sessionID ~= 0 then
                CT._completedSessionIDs[sessionID] = G:GetRawGeneration()
                -- The live/current session is the final available entry.  An
                -- older delayed event arriving during a later fight must never
                -- claim that later fight's generation.
                local generation
                local sessions, count = safeSessionCount()
                local latest = sessions and sessions[count]
                local latestID, latestDuration
                if latest and G:IsTableAccessible(latest) then
                    latestID = latest.sessionID
                    latestDuration = latest.durationSeconds
                end
                -- Completion metadata and the Blizzard M+ run-wide row may
                -- publish in either order.  Classify every matching list item
                -- before assigning this event to the just-finished fight.
                CT:ClassifyLatestSyntheticMythicOverall()
                local isMythicOverall = CT:IsSyntheticSessionID(sessionID)
                if not isMythicOverall and type(latestID) ~= "nil"
                    and G:IsAccessible(latestID) and latestID == sessionID then
                    local activeEvidence = CT._activeCombatSessionID == sessionID
                    local liveDuration = G:IsAccessible(latestDuration)
                        and type(latestDuration) == "number" and latestDuration <= 0
                    if activeEvidence or (ns.state.inCombat and liveDuration) then
                        generation = ns.Segments and ns.Segments._combatGeneration or 0
                    else
                        generation = CT._lastCompletedGeneration
                    end
                end
                if not isMythicOverall and generation ~= nil
                    and CT._sessionGenerationByID[sessionID] == nil then
                    local primary = CT._primarySessionByGeneration[generation]
                    if primary and primary ~= sessionID then
                        CT._supplementalSessionIDs[sessionID] = true
                    else
                        CT._primarySessionByGeneration[generation] = sessionID
                        CT._sessionGenerationByID[sessionID] = generation
                    end
                end
                if generation ~= nil then
                    CT._meterObservedGenerations[generation] = true
                    for _, context in ipairs(CT._completedContexts) do
                        if context.combatGeneration == generation then context._rawObserved = true end
                    end
                end
                if generation ~= nil and not CT._supplementalSessionIDs[sessionID]
                    and not isMythicOverall then
                    -- The event sessionID is authoritative.  Bind it even if
                    -- the lightweight list row is one frame late; optional
                    -- name/duration enrichment is reconciled by the watchdog.
                    CT:BindFinishedCurrentSession(sessionID,
                        latestID == sessionID and latest or nil, generation)
                end
                CT:ReconcileFinishedCurrentSession()
                CT:PersistLifecycleState()
            end
            if G then G:MarkDirty("archive") end
            CT:StartWatchdog()
            if ns.HistoryList and ns.HistoryList.IsOpen and ns.HistoryList:IsOpen() then
                ns.HistoryList:Rebuild()
            end
        elseif event == "DAMAGE_METER_RESET" then
            CT:HandleDamageMeterReset()
        elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            CT:ScheduleWorldTransitionChecks(event)
        elseif event == "CHALLENGE_MODE_START" then
            CT._currentSceneKey = "mplus"
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            -- MythicPlus.lua and Blizzard's final synthetic session may publish
            -- in either order.  The session event handles the normal path; the
            -- next-frame pass handles completion metadata delivered last.
            C_Timer.After(0, function()
                CT:ClassifyLatestSyntheticMythicOverall()
                if ns.HistoryList and ns.HistoryList.IsOpen
                    and ns.HistoryList:IsOpen() then ns.HistoryList:Rebuild() end
            end)
            CT:StartWatchdog()
        elseif event == "CHALLENGE_MODE_RESET" then
            CT._currentSceneKey = (ns.state and ns.state.sceneKey) or "dungeon"
            CT._currentMythicLevel = 0
            CT._currentMythicMapName = nil
            C_Timer.After(0, function()
                CT._currentSceneKey = (ns.state and ns.state.sceneKey ~= "mplus"
                    and ns.state.sceneKey) or "dungeon"
                CT:PersistLifecycleState()
            end)
            CT:StartWatchdog()
        end
    end)
    self._worldSnapshot = instanceSnapshot()
    local restoredActive, pendingExit = self:RestoreLifecycleState(self._worldSnapshot)
    if self._worldSnapshot.inInstance then
        if not restoredActive then
            self._currentInstanceTag = newInstanceTag(self._worldSnapshot)
            self._worldSnapshot.instanceTag = self._currentInstanceTag
            self._currentInstanceName = self._worldSnapshot.name
            self._currentInstanceType = self._worldSnapshot.instanceType
            self._currentSceneKey = self._worldSnapshot.scene
            local _, existingCount = safeSessionCount()
            if existingCount > 0 then
                -- First install/update while already inside an active run: do
                -- not destroy Blizzard data we did not witness entering.
                self._instanceHadCombatByTag[self._currentInstanceTag] = true
                self._overallCoverageByTag[self._currentInstanceTag] = true
            else
                self._overallCoverageByTag[self._currentInstanceTag] = true
                if not self:IsBlizzardMeterEmpty() then
                    self:MarkOverallResetPending(self._currentInstanceTag)
                end
            end
        else
            self._worldSnapshot.scene = self._currentSceneKey
            if self._currentSceneKey == "mplus" and ns.state then
                ns.state.inMythicPlus = true
                ns.state.mplusRuntimeLatch = true
            end
        end
    else
        self._currentSceneKey = "outdoor"
    end
    self:SetBaseline()

    if pendingExit then
        self._pendingMergeArgs = {
            tag = pendingExit.tag, lvl = pendingExit.level,
            mapName = pendingExit.mapName, instName = pendingExit.instanceName,
            exitingSceneKey = pendingExit.scene,
            combatGeneration = pendingExit.combatGeneration,
            hadCombat = pendingExit.hadCombat,
            overallComplete = pendingExit.overallComplete,
        }
        self._exitingInstanceTag = pendingExit.tag
        if pendingExit.scene == "mplus" and self.MaterializeOfficialMythicFullRun then
            self:MaterializeOfficialMythicFullRun(pendingExit.tag, pendingExit.level,
                pendingExit.mapName, pendingExit.instanceName, pendingExit.combatGeneration)
        end
        self:QueueAction("merge-instance", {
            tag = pendingExit.tag, level = pendingExit.level,
            mapName = pendingExit.mapName, instanceName = pendingExit.instanceName,
            scene = pendingExit.scene, combatGeneration = pendingExit.combatGeneration,
        })
        if self._worldSnapshot.inInstance and not restoredActive then
            -- The old pending exit owns the one physical reset for a direct
            -- A-to-B transition; never enqueue a competing second reset.
            self:MarkOverallResetPending(self._currentInstanceTag)
        end
    elseif self._entryResetPendingTag == self._currentInstanceTag then
        local restored = self._restoredPendingReset
        self._restoredPendingReset = nil
        local reason = restored and restored.reason or "enter-instance"
        local function afterReset()
            if reason == "challenge-start" and ns.MythicPlus
                and ns.MythicPlus.ResumeAfterBoundaryReset then
                ns.MythicPlus:ResumeAfterBoundaryReset()
            elseif ns.Segments then
                ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL)
            end
        end
        local action = self:RequestMeterReset(reason, afterReset,
            restored and restored.boundaryTag or self._currentInstanceTag)
        if restored and restored.combatGenerationAtQueue ~= nil then
            action.combatGenerationAtQueue = restored.combatGenerationAtQueue
        end
        if restored and restored.preKeyCutoffWallTime ~= nil then
            action.preKeyCutoffWallTime = restored.preKeyCutoffWallTime
        end
    end
    if self._restoredPendingUserReset then
        self._restoredPendingUserReset = nil
        self:QueueUserReset()
    end
    if ns.Segments and ns.Segments.RestoreCurrentAfterReload then
        ns.Segments:RestoreCurrentAfterReload()
    end
    self:PersistLifecycleState()
end

function CT:RescanZeroDataSegments()
    for _, seg in ipairs(ns.Segments and ns.Segments.history or {}) do
        if seg._sessionID and not seg._dataLoaded then self:LoadSegmentData(seg) end
    end
end

function CT:ScanArchivedSessions() self:StartWatchdog() end
function CT:ProcessArchivedNow()
    if not self:HasPendingActions() then return false, "no-reset-boundary" end
    return self:ProcessArchiveTransactions()
end
function CT:WaitAndProcessArchived() self:StartWatchdog(); return true end

function CT:DebugSessions()
    local sessions, count = safeSessionCount()
    print(string.format("LightDamage sessions=%d cursor=%d pending=%s", count,
        self._lastProcessedCount or 0, tostring(self._pendingArchiveReason)))
    for i, info in ipairs(sessions or {}) do
        local sessionID, idState = G:ReadField(info, "sessionID")
        local name, nameState = G:ReadField(info, "name")
        local duration, durationState = G:ReadField(info, "durationSeconds")
        sessionID = idState == G.ACCESSIBLE and sessionID or "<secret>"
        name = nameState == G.ACCESSIBLE and name or "<secret>"
        duration = durationState == G.ACCESSIBLE and duration or "<secret>"
        print(string.format("  [%d] id=%s dur=%s name=%s", i, tostring(sessionID), tostring(duration), tostring(name)))
    end
end

function CT:DebugAPI()
    print("LightDamage DamageMeterGateway generation:", G and G:GetRawGeneration() or "missing")
    self:DebugSessions()
end
