--[[
    Light Damage - InstanceManager.lua

    Instance completion consumes only committed local archive segments.  For a
    normal dungeon/M+ exit with no intervening combat it materializes Blizzard's
    official Overall snapshot directly.  Mythic+ uses that same boundary and the
    same logic, with exactly one extra step before building: if Blizzard
    published a dedicated run-wide session for the run, that session becomes the
    data source instead of Overall and its own History row is retired once
    copied.  Raid full-run always aggregates boss attempts (wins and wipes) and
    excludes trash.
]]
local addonName, ns = ...
local L = ns.L

local function shouldGenerate(scene)
    return ns.db and ns.db.mythicPlus and ns.db.mythicPlus.enabled ~= false
        and ns.db.fullRunSettings and ns.db.fullRunSettings[scene] == true
end
local function shouldHideTrash(scene)
    local supportsTrashCleanup = scene == "mplus" or scene == "raid" or scene == "dungeon"
    return supportsTrashCleanup and ns.db and ns.db.mythicPlus and ns.db.mythicPlus.autoCleanTrash ~= false
        and ns.db.cleanTrashSettings and ns.db.cleanTrashSettings[scene] == true
end

function ns.CombatTracker:SmartTrimHistory(dryRun)
    local segs = ns.Segments
    local history = segs and segs.history
    if not history then return 0 end
    local limit = ns.GetHistoryDisplayLimit and ns:GetHistoryDisplayLimit() or 20
    if #history < limit + 5 then return 0 end

    -- A raid full run may still need every boss attempt, including attempts
    -- currently outside the displayed history.  Defer this batch until exit.
    local activeTag = self._currentInstanceTag
    local exitingTag = self._exitingInstanceTag
    -- During login the lifecycle owner has not restored its instance tag yet.
    -- Later, use its live state: the saved copy can still describe an exited run.
    local lifecycle = not self._worldSnapshot and LightDamageDB and LightDamageDB.lightDamageLifecycle
    if type(lifecycle) == "table" then
        if not activeTag and type(lifecycle.active) == "table" then activeTag = lifecycle.active.tag end
        if not exitingTag and type(lifecycle.pendingExit) == "table" then exitingTag = lifecycle.pendingExit.tag end
    end
    for i = limit + 1, #history do
        local tag = history[i]._instanceTag
        if tag and (tag == activeTag or tag == exitingTag) then return 0 end
    end

    local removed = #history - limit
    local overrideID = ns.db and ns.db.fullRunOverrideLocalID
    local removedOverride = false
    if overrideID then
        for i = limit + 1, #history do
            if history[i]._localID == overrideID then removedOverride = true; break end
        end
    end
    if dryRun then return removed, removedOverride end

    local removedSelected = false
    local selectedID = segs.viewIndex and segs.viewIndex.kind == "archived" and segs.viewIndex.localID
    for i = #history, limit + 1, -1 do
        local old = table.remove(history)
        if old._localID == selectedID then removedSelected = true end
        if ns.HistoryStore then ns.HistoryStore:Invalidate(old) end
    end
    if removedOverride then
        segs:ClearFullRunOverride()
        if ns.db.savedOverall and ns.db.savedOverall._localID == overrideID then
            ns.db.savedOverall = nil
        end
    end
    if segs.GCHiddenLocalIDs then segs:GCHiddenLocalIDs() end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    if removedSelected then segs:ViewLatestHistory() end
    if ns.HistoryList and ns.HistoryList.IsOpen and ns.HistoryList:IsOpen() then
        ns.HistoryList:Rebuild()
    end
    return removed, removedOverride
end

local function matchingSegments(tag)
    local result = {}
    for _, seg in ipairs(ns.Segments.history or {}) do
        if seg._instanceTag == tag and not seg._isMerged then table.insert(result, seg) end
    end
    table.sort(result, function(a, b)
        return (a.endTime or 0) < (b.endTime or 0)
    end)
    return result
end

local function latestSegment(segments)
    return segments[#segments]
end

-- Every Mythic+ full run carries the 1.4.6 +level/map identity, whichever data
-- source produced it.  MythicPlus:FormatSegLabel renders it as +level map ✓/✗/—.
local function decorateMythicFullRun(fullRun, instanceTag, mythicLevel,
    mythicMapName, instanceName, fromOfficialSession)
    fullRun._instanceTag = nil
    fullRun._sourceInstanceTag = fromOfficialSession and instanceTag or nil
    fullRun._isBoss = false
    fullRun._isMerged = true
    fullRun._builtByMythicPlus = true
    fullRun._fromOfficialMythicOverall = fromOfficialSession or nil
    fullRun.mythicLevel = mythicLevel or 0
    fullRun.mapName = mythicMapName or instanceName
    local pending = ns.MythicPlus and ns.MythicPlus._pendingMythicSeg
    if pending then
        fullRun.success = pending.success
        fullRun.mapID = pending.mapID
        fullRun._keystoneTime = (pending.elapsed or 0) / 1000
        ns.MythicPlus._pendingMythicSeg = nil
    end
end

-- 12.0.7+ can publish a dedicated immutable M+ run-wide session.  It is looked
-- up once per exit: it proves the run happened and, when present, replaces
-- Blizzard Overall as the full-run data source.
local function officialMythicSession(tracker, scene)
    if scene ~= "mplus" or not tracker.GetOfficialMythicOverallSession then return nil end
    return tracker:GetOfficialMythicOverallSession()
end

function ns.CombatTracker:MergeAndCleanInstance(instanceTag, mythicLevel, mythicMapName,
    instanceName, exitingSceneKey, pendingCombatGeneration, allowIncomplete)
    local segs = ns.Segments
    if not segs or not instanceTag then return true end
    local scene = exitingSceneKey or ((mythicLevel or 0) > 0 and "mplus" or "dungeon")
    local generate = shouldGenerate(scene)
    local all = matchingSegments(instanceTag)
    -- The single Mythic+ difference: look for Blizzard's dedicated run-wide
    -- session before building anything.  Everything after this is the normal
    -- dungeon path.
    local officialSessionID, officialInfo = officialMythicSession(self, scene)
    -- Blizzard session publication is the product boundary: every official
    -- session counts, including zero-value or accidental sessions.  A local
    -- combat edge without a published session must not manufacture a full-run.
    local hadCombat = #all > 0 or officialSessionID ~= nil

    local function releaseExitedInstanceState()
        self._pendingMergeStatus = nil
        if not self._pendingMergeArgs or self._pendingMergeArgs.tag == instanceTag then
            self._pendingMergeArgs = nil
        end
        if self._exitingInstanceTag == instanceTag then self._exitingInstanceTag = nil end
        -- A slow old-instance archive can finish after the player has already
        -- entered a new run.  Never erase that newer run's identity/metadata.
        if self._currentInstanceTag == instanceTag then
            self._currentInstanceTag = nil
            self._currentInstanceName = nil
            self._currentInstanceType = nil
            self._currentMythicLevel = 0
            self._currentMythicMapName = nil
        end
        if self.ReleaseOverallCoverage then self:ReleaseOverallCoverage(instanceTag) end
    end

    local function finishEmptyExit()
        releaseExitedInstanceState()
        self:RequestMeterReset("instance-exit-empty", function()
            if ns.Segments then ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL) end
            if ns.UI and ns.UI:IsVisible() then ns.UI:Layout() end
        end, instanceTag)
        return true
    end

    -- Never materialize an empty or polluted Overall merely because the API
    -- still contains older outdoor data.  A real combat edge (persisted across
    -- reload) or a tagged committed session is required for every PvE scene.
    if not hadCombat then
        return finishEmptyExit()
    end

    -- Raid full-run is boss-attempt-only.  With no committed boss/encounter
    -- segment there is nothing to merge, but Blizzard Overall still must be
    -- reset so the following outdoor Total cannot inherit instance data.
    if #all == 0 and (not generate or scene == "raid") then
        return finishEmptyExit()
    end

    if shouldHideTrash(scene) then
        for _, seg in ipairs(all) do
            if not seg._isBoss then segs:HideLocalID(seg._localID) end
        end
    end

    local generationUnchanged = pendingCombatGeneration == nil
        or pendingCombatGeneration == (segs._combatGeneration or 0)
    local canUseOfficialOverall = generationUnchanged
        and (not self.IsOverallCompleteForTag or self:IsOverallCompleteForTag(instanceTag))
    -- Blizzard's dedicated run-wide session is immutable and already scoped to
    -- exactly this run, so neither a later fight (generationUnchanged) nor
    -- pre-instance data in the rolling Overall (coverage) can contaminate it.
    -- Gating it behind those flags sent runs down the local-aggregation path,
    -- which has no official per-second values -- that is why a full run could
    -- render bare totals with no DPS.  Only a reset inside the run truncates it.
    local canUseOfficialRunWide = officialSessionID ~= nil
        and (not self.IsOfficialRunWideComplete or self:IsOfficialRunWideComplete(instanceTag))
    local fullRun
    local builtFromOfficialSession = false

    if generate then
        local zoneName = mythicMapName or instanceName
            or (all[1] and all[1]._instanceDisplayName) or L.INSTANCE
        -- Normal/raid runs use "instance [full run]".  Mythic+ is the explicit
        -- 1.4.6 exception: its visible label is derived from level/map/status
        -- by MythicPlus:FormatSegLabel (+level map ✓/✗/—).
        local mergedName = scene == "mplus"
            and string.format("+%d %s", mythicLevel or 0, zoneName)
            or string.format(L.OVERALL_SEGMENT_NAME_FORMAT, zoneName)

        -- Raid, or an exit that had to wait through a newer outdoor fight:
        -- aggregate only the tagged local run so no later combat leaks in.
        local function buildFromLocalSegments()
            local source = {}
            for _, seg in ipairs(all) do
                if scene ~= "raid" or seg._isBoss then table.insert(source, seg) end
            end
            if #source == 0 then return nil end
            return self:MergeLocalSegments(source, {
                type = scene == "mplus" and "mythicplus" or "history",
                name = mergedName, prefix = scene == "mplus" and "mp" or "merged",
                isMerged = true,
            })
        end

        if scene ~= "raid" and (canUseOfficialRunWide or canUseOfficialOverall) then
            -- Prefer the dedicated immutable session found above; the Overall
            -- selector can change or clear between challenge completion and the
            -- later world transition.  Normal dungeons, and Mythic+ runs whose
            -- client never published that row, use Blizzard Overall as before.
            -- Either way every value in the full run -- totals, per-second
            -- rates, spell rows, deaths -- is copied from Blizzard, never
            -- derived: the API states the run's DPS, so we read it.
            local meta = {
                type = scene == "mplus" and "mythicplus" or "history",
                name = mergedName,
                allowIncomplete = false,
            }
            if officialInfo and type(officialInfo.durationSeconds) == "number" then
                meta.duration = officialInfo.durationSeconds
            end
            local candidate, status
            if canUseOfficialRunWide then
                candidate, status = self:BuildSessionCandidate(officialSessionID, meta)
            else
                candidate, status = self:BuildOverallCandidate(meta)
            end
            if not candidate and not allowIncomplete then
                self._pendingMergeStatus = status
                return false
            end
            if candidate then
                fullRun = self:CommitArchiveCandidate(candidate, {insert = false, prefix = scene == "mplus" and "mp" or "merged"})
                fullRun._isMerged = true
                builtFromOfficialSession = canUseOfficialRunWide
            else
                -- Forced boundary: the official source never became readable.
                -- Fall back to the tag-isolated local segments instead of
                -- stalling the exit and leaking this run into the next Total.
                fullRun = buildFromLocalSegments()
            end
        else
            fullRun = buildFromLocalSegments()
        end
        if not fullRun then return finishEmptyExit() end

        if scene == "mplus" then
            -- Leaving a Mythic+ instance always produces the +level/map label,
            -- whether the data came from the dedicated session or from Overall.
            decorateMythicFullRun(fullRun, instanceTag, mythicLevel, mythicMapName,
                instanceName, builtFromOfficialSession)
        else
            fullRun._instanceTag = nil
            fullRun._isBoss = false
            fullRun._isMerged = true
            fullRun._builtByMythicPlus = false
            fullRun.mythicLevel = mythicLevel or 0
            fullRun.mapName = mythicMapName or instanceName
        end
        -- LightDamage now owns this run.  Retire Blizzard's own run-wide row so
        -- History shows the generated full run instead of both.
        if builtFromOfficialSession and self.MarkOfficialFullRunConsumed then
            self:MarkOfficialFullRunConsumed(officialSessionID)
        end
        -- The summary is the newest completed item of the run.  It must stay at
        -- history[1] or it renders before the run's own first fight; the promote
        -- is a no-op here and guards only against a later reordering.
        table.insert(segs.history, 1, fullRun)
        segs:PromoteHistorySegment(fullRun)
        if generationUnchanged then
            segs.overall = fullRun
            if segs:GetFullRunOverride() ~= fullRun then
                segs:SetFullRunOverride(fullRun)
            end
        end
    else
        -- Full-run disabled: current remains the newest instance encounter and
        -- Total is an empty outdoor Overall after the coordinated meter reset.
        if generationUnchanged then
            segs.current = latestSegment(all)
            segs:ViewCurrent()
            segs.overall = segs:NewSegment("overall", L.OVERALL)
        end
    end

    releaseExitedInstanceState()
    if ns.SaveSessionHistory then ns:SaveSessionHistory() end
    if ns.Analysis then ns.Analysis:InvalidateCache() end

    -- Reset only after every API session (including a newer outdoor combat)
    -- has itself been archived.  RequestMeterReset re-checks that invariant.
    self:RequestMeterReset("instance-exit", function()
        if ns.Segments and (not generate or not generationUnchanged) then
            ns.Segments.overall = ns.Segments:NewSegment("overall", L.OVERALL)
        end
        if ns.UI and ns.UI:IsVisible() then ns.UI:Layout() end
    end, instanceTag)
    return true
end
