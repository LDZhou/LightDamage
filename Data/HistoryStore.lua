--[[
    Light Damage - HistoryStore.lua

    Persistent history is lossless with respect to the in-memory local
    archive.  maxSegments is a presentation limit only.  Secret values are
    never copied into SavedVariables; if a supposedly committed segment is
    found to contain one, the whole save is rejected and the previous save is
    retained.
]]
local addonName, ns = ...

local H = {}
ns.HistoryStore = H
H._compactCache = setmetatable({}, { __mode = "k" })

local function accessible(value)
    return not ns.DamageMeterGateway or ns.DamageMeterGateway:IsAccessible(value)
end

local function cloneAccessible(value, seen)
    if not accessible(value) then return nil, false end
    local kind = type(value)
    if kind == "nil" or kind == "number" or kind == "string" or kind == "boolean" then
        return value, true
    end
    if kind ~= "table" then return nil, false end
    if type(issecrettable) == "function" then
        local ok, secret = pcall(issecrettable, value)
        if not ok or secret == true then return nil, false end
    end
    if ns.DamageMeterGateway and not ns.DamageMeterGateway:IsTableAccessible(value) then
        return nil, false
    end
    seen = seen or {}
    if seen[value] then return seen[value], true end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then return nil, false end
        if not accessible(key) then return nil, false end
        local childCopy, ok = cloneAccessible(child, seen)
        if not ok then return nil, false end
        copy[key] = childCopy
    end
    return copy, true
end

local function compactSegment(seg)
    local compact = {
        type = seg.type, name = seg.name, startTime = seg.startTime,
        endTime = seg.endTime, duration = seg.duration, isActive = false,
        totalDamage = seg.totalDamage, totalHealing = seg.totalHealing,
        totalDamageTaken = seg.totalDamageTaken,
        totalDeaths = seg.totalDeaths,
        totalEnemyDamageTaken = seg.totalEnemyDamageTaken,
        encounterID = seg.encounterID, encounterName = seg.encounterName,
        difficultyID = seg.difficultyID, success = seg.success,
        mythicLevel = seg.mythicLevel, mapName = seg.mapName,
        mapID = seg.mapID, _keystoneTime = seg._keystoneTime,
        _isMerged = seg._isMerged, _isBoss = seg._isBoss,
        _instanceTag = seg._instanceTag, _instanceDisplayName = seg._instanceDisplayName,
        _combatGeneration = seg._combatGeneration,
        _completedWallTime = seg._completedWallTime,
        _preKeystone = seg._preKeystone, _mythicLevel = seg._mythicLevel,
        _mapName = seg._mapName, _builtByMythicPlus = seg._builtByMythicPlus,
        _fromOfficialMythicOverall = seg._fromOfficialMythicOverall,
        _sourceInstanceTag = seg._sourceInstanceTag,
        _sessionID = seg._sessionID, _sessionIdx = seg._sessionIdx,
        _localID = seg._localID, _wasOutdoor = seg._wasOutdoor,
        _dataLoaded = seg._dataLoaded, _archiveGeneration = seg._archiveGeneration,
        _durationEstimated = seg._durationEstimated,
        _durationUnknown = seg._durationUnknown,
        _detailsIncomplete = seg._detailsIncomplete,
        _durationIncomplete = seg._durationIncomplete,
        _spellDetailsIncomplete = seg._spellDetailsIncomplete,
        _deathDetailsIncomplete = seg._deathDetailsIncomplete,
        _enemySourceDetailsIncomplete = seg._enemySourceDetailsIncomplete,
        _playerAttributionIncomplete = seg._playerAttributionIncomplete,
        _rateDetailsIncomplete = seg._rateDetailsIncomplete,
        players = seg.players or {}, deathLog = seg.deathLog or {},
        enemyDamageTakenList = seg.enemyDamageTakenList or {},
    }
    return cloneAccessible(compact)
end

function H:Invalidate(seg)
    if seg then self._compactCache[seg] = nil
    else self._compactCache = setmetatable({}, { __mode = "k" }) end
end

function H:GetCompact(seg)
    -- Committed archive segments are immutable.  Reuse their already
    -- validated SavedVariables snapshot so each new combat clones only the
    -- new segment instead of recursively copying the entire lifetime history.
    local cached = self._compactCache[seg]
    if cached then return cached, true end
    local compact, ok = compactSegment(seg)
    if ok then self._compactCache[seg] = compact end
    return compact, ok
end

function H:Save()
    if not ns.db or not ns.Segments then return false, "not-ready" end
    local savedHistory = {}
    for _, seg in ipairs(ns.Segments.history or {}) do
        local compact, ok = self:GetCompact(seg)
        if not ok then
            self.lastError = "secret-or-unsupported-history-value"
            return false, self.lastError
        end
        table.insert(savedHistory, compact)
    end

    local savedOverall = nil
    local overall = ns.Segments.overall
    if overall then
        local compact, ok = self:GetCompact(overall)
        if not ok then
            self.lastError = "secret-or-unsupported-overall-value"
            return false, self.lastError
        end
        if (compact.totalDamage or 0) > 0 or (compact.totalHealing or 0) > 0
            or (compact.totalDamageTaken or 0) > 0 then
            savedOverall = compact
        end
    end

    -- Commit SavedVariables only after every segment has been validated.
    ns.db.savedHistory = savedHistory
    ns.db.savedHistorySchema = 2
    ns.db.savedOverall = savedOverall
    if ns.CombatTracker then
        ns.db.savedBaseline = ns.CombatTracker._baselineSessionCount or 0
        ns.db.savedLastProcessed = ns.CombatTracker._lastProcessedCount or 0
        if ns.CombatTracker.PersistLifecycleState then
            ns.CombatTracker:PersistLifecycleState()
        end
    end
    self.lastError = nil
    return true
end

-- Core/Profiles.lua defines the legacy saver before Data.xml is loaded.  Keep
-- its public API but replace the truncating implementation.
function ns:SaveSessionHistory()
    return H:Save()
end

return H
