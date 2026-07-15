--[[
    Light Damage - DataLoader.lua

    Archive materialization and local aggregation.  All C_DamageMeter reads go
    through DamageMeterGateway.  Existing segments are never cleared until a
    complete accessible candidate has been built.
]]
local addonName, ns = ...
local CT = ns.CombatTracker
local G = ns.DamageMeterGateway

local function candidateMeta(seg, options)
    options = options or {}
    return {
        type = seg.type, name = seg.name, duration = seg.duration,
        startTime = seg.startTime, endTime = seg.endTime,
        sessionIdx = seg._sessionIdx, instanceTag = seg._instanceTag,
        instanceDisplayName = seg._instanceDisplayName, isBoss = seg._isBoss,
        encounterName = seg.encounterName, encounterID = seg.encounterID,
        difficultyID = seg.difficultyID, success = seg.success,
        combatGeneration = seg._combatGeneration,
        completedWallTime = seg._completedWallTime,
        -- Secret/error data never has a time-based fail-open.  The option is
        -- retained only for call compatibility and intentionally ignored.
        allowIncomplete = false,
    }
end
function CT:LoadSegmentData(seg, options)
    if not seg or not seg._sessionID or not G then return false, "missing" end
    local candidate, status = G:BuildSessionCandidate(seg._sessionID, candidateMeta(seg, options))
    if not candidate then
        seg._dataLoaded = false
        seg._archiveStatus = status
        return false, status
    end
    local localID = seg._localID
    G:ApplyCandidateToSegment(candidate, seg)
    seg._localID = localID or seg._localID or ns.Segments:GenLocalID("arch")
    seg._dataLoaded = true
    seg._archiveStatus = nil
    if ns.HistoryStore then ns.HistoryStore:Invalidate(seg) end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    return true, G.ACCESSIBLE
end

function CT:BuildSessionCandidate(sessionID, meta)
    if not G then return nil, "gateway-missing" end
    return G:BuildSessionCandidate(sessionID, meta)
end

function CT:BuildOverallCandidate(meta)
    if not G then return nil, "gateway-missing" end
    return G:BuildOverallCandidate(meta)
end

function CT:CommitArchiveCandidate(candidate, opts)
    if not candidate or not ns.Segments then return nil, "invalid-candidate" end
    opts = opts or {}
    local seg = ns.Segments:NewSegment(candidate.type or "history", candidate.name)
    seg._localID = opts.localID or ns.Segments:GenLocalID(opts.prefix or "arch")
    G:ApplyCandidateToSegment(candidate, seg)
    seg._localID = opts.localID or seg._localID
    seg._dataLoaded = true
    if opts.insert ~= false then table.insert(ns.Segments.history, opts.index or 1, seg) end
    if ns.Segments.MigrateHideOnArchive then ns.Segments:MigrateHideOnArchive(seg) end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    return seg
end

local function mergeSpellMap(target, source)
    for storageKey, spell in pairs(source or {}) do
        local spellID = spell.spellID or spell.id or storageKey
        local out = target[storageKey]
        if not out then
            out = ns.Segments:NewSpellData(spellID, spell.name, spell.school)
            out.spellID = type(spellID) == "number" and spellID or nil
            target[storageKey] = out
        end
        out.damage = (out.damage or 0) + (spell.damage or 0)
        out.healing = (out.healing or 0) + (spell.healing or 0)
        out.absorbed = (out.absorbed or 0) + (spell.absorbed or 0)
        out.hits = (out.hits or 0) + (spell.hits or 0)
        out.crits = (out.crits or 0) + (spell.crits or 0)
        out.maxHit = math.max(out.maxHit or 0, spell.maxHit or 0)
        out.maxCrit = math.max(out.maxCrit or 0, spell.maxCrit or 0)
        if spell.isAvoidable then out.isAvoidable = true end
        if spell.isPet then out.isPet = true end
        if spell.petName and spell.petName ~= "" then out.petName = spell.petName end
    end
end

local function mergePet(target, source)
    target.name = source.name or target.name
    for _, field in ipairs({"damage", "healing", "damageTaken", "interrupts", "dispels"}) do
        target[field] = (target[field] or 0) + (source[field] or 0)
    end
    mergeSpellMap(target.spells, source.spells)
    mergeSpellMap(target.damageTakenSpells, source.damageTakenSpells)
    mergeSpellMap(target.interruptSpells, source.interruptSpells)
    mergeSpellMap(target.dispelSpells, source.dispelSpells)
    if source._detailsIncomplete then target._detailsIncomplete = true end
end

local function mergePlayer(target, source)
    target.name = source.name or target.name
    target.class = source.class or target.class
    target.specID = source.specID or target.specID
    target.specIconID = source.specIconID or target.specIconID
    target.ilvl = math.max(target.ilvl or 0, source.ilvl or 0)
    target.score = math.max(target.score or 0, source.score or 0)
    for _, field in ipairs({"damage", "healing", "overhealing", "absorbed", "damageTaken", "deaths", "interrupts", "dispels", "activeTime"}) do
        target[field] = (target[field] or 0) + (source[field] or 0)
    end
    mergeSpellMap(target.spells, source.spells)
    mergeSpellMap(target.damageTakenSpells, source.damageTakenSpells)
    mergeSpellMap(target.interruptSpells, source.interruptSpells)
    mergeSpellMap(target.dispelSpells, source.dispelSpells)
    for petKey, pet in pairs(source.pets or {}) do
        local out = target.pets[petKey]
        if not out then
            out = {name = pet.name or "Pet", damage = 0, healing = 0, damageTaken = 0,
                interrupts = 0, dispels = 0, spells = {}, damageTakenSpells = {},
                interruptSpells = {}, dispelSpells = {}}
            target.pets[petKey] = out
        end
        mergePet(out, pet)
    end
    if source._detailsIncomplete then target._detailsIncomplete = true end
end

local function mergeEnemyList(target, source)
    local byKey = {}
    for _, entry in ipairs(target) do byKey[entry.creatureID or entry.name] = entry end
    for _, entry in ipairs(source or {}) do
        local key = entry.creatureID or entry.name
        local out = byKey[key]
        if not out then
            out = {creatureID = entry.creatureID, name = entry.name, total = 0, perSec = nil, sources = {}}
            byKey[key] = out; table.insert(target, out)
        end
        out.total = out.total + (entry.total or 0)
        if entry._detailsIncomplete then out._detailsIncomplete = true end
        local sourceMap = {}
        for _, row in ipairs(out.sources) do sourceMap[row.name] = row end
        for _, row in ipairs(entry.sources or {}) do
            local merged = sourceMap[row.name]
            if not merged then
                merged = {name = row.name, class = row.class, amount = 0}
                sourceMap[row.name] = merged; table.insert(out.sources, merged)
            end
            merged.amount = merged.amount + (row.amount or 0)
        end
        table.sort(out.sources, function(a, b) return a.amount > b.amount end)
    end
    table.sort(target, function(a, b) return a.total > b.total end)
end

function CT:MergeLocalSegments(segments, meta)
    meta = meta or {}
    local merged = ns.Segments:NewSegment(meta.type or "history", meta.name or ns.L.OVERALL)
    merged.isActive = false; merged._dataLoaded = true; merged._isMerged = meta.isMerged ~= false
    merged._localID = meta.localID or ns.Segments:GenLocalID(meta.prefix or "merged")
    merged._instanceTag = meta.instanceTag
    for _, seg in ipairs(segments or {}) do
        merged.duration = (merged.duration or 0) + (seg.duration or 0)
        merged.totalDamage = merged.totalDamage + (seg.totalDamage or 0)
        merged.totalHealing = merged.totalHealing + (seg.totalHealing or 0)
        merged.totalDamageTaken = merged.totalDamageTaken + (seg.totalDamageTaken or 0)
        for guid, player in pairs(seg.players or {}) do
            local out = merged.players[guid]
            if not out then out = ns.Segments:NewPlayerData(guid, player.name, player.class); merged.players[guid] = out end
            mergePlayer(out, player)
        end
        for _, death in ipairs(seg.deathLog or {}) do table.insert(merged.deathLog, CopyTable(death)) end
        mergeEnemyList(merged.enemyDamageTakenList, seg.enemyDamageTakenList)
        for _, flag in ipairs({"_detailsIncomplete", "_spellDetailsIncomplete",
            "_deathDetailsIncomplete", "_enemySourceDetailsIncomplete",
            "_playerAttributionIncomplete", "_rateDetailsIncomplete",
            "_durationIncomplete"}) do
            if seg[flag] then merged[flag] = true end
        end
    end
    table.sort(merged.deathLog, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
    return merged
end

-- Overall is always a fixed local semantic item.  It is refreshed atomically
-- from Blizzard's official Overall session; failure leaves the previous value.
function CT:RebuildOverall(sessions, sessionCount)
    if not ns.Segments or not G then return false, "not-ready" end
    local old = ns.Segments.overall
    local meta = {type = "overall", name = old and old.name or ns.L.OVERALL}
    local candidate, status = G:BuildOverallCandidate(meta)
    if not candidate then return false, status end
    local replacement = ns.Segments:NewSegment("overall", candidate.name)
    G:ApplyCandidateToSegment(candidate, replacement)
    replacement.type = "overall"; replacement._localID = nil; replacement._isMerged = false
    ns.Segments.overall = replacement
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    return true, G.ACCESSIBLE
end
