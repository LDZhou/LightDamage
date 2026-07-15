--[[
    Light Damage - InstanceManager.lua

    Instance completion consumes only committed local archive segments.  For a
    normal dungeon/M+ exit with no intervening combat it materializes Blizzard's
    official Overall snapshot directly.  Raid full-run always aggregates boss
    attempts (wins and wipes) and excludes trash.
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

-- maxSegments is display-only.  Kept as a compatibility no-op for callers.
function ns.CombatTracker:SmartTrimHistory()
    return ns.Segments and #(ns.Segments.history or {}) or 0
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

function ns.CombatTracker:MergeAndCleanInstance(instanceTag, mythicLevel, mythicMapName,
    instanceName, exitingSceneKey, pendingCombatGeneration, allowIncomplete)
    local segs = ns.Segments
    if not segs or not instanceTag then return true end
    local scene = exitingSceneKey or ((mythicLevel or 0) > 0 and "mplus" or "dungeon")
    local generate = shouldGenerate(scene)
    local all = matchingSegments(instanceTag)
    -- Blizzard session publication is the product boundary: every official
    -- session counts, including zero-value or accidental sessions.  A local
    -- combat edge without a published session must not manufacture a full-run.
    local hadCombat = #all > 0

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
    local fullRun = nil

    if generate then
        local zoneName = mythicMapName or instanceName
            or (all[1] and all[1]._instanceDisplayName) or L.INSTANCE
        -- Normal/raid runs use "instance [full run]".  Mythic+ is the explicit
        -- 1.4.6 exception: its visible label is derived from level/map/status
        -- by MythicPlus:FormatSegLabel (+level map ✓/✗/—).
        local mergedName = scene == "mplus"
            and string.format("+%d %s", mythicLevel or 0, zoneName)
            or string.format(L.OVERALL_SEGMENT_NAME_FORMAT, zoneName)

        if scene ~= "raid" and canUseOfficialOverall then
            -- Normal path: exact Blizzard Overall, including all seven modes,
            -- pets, spells and deaths, captured atomically by the gateway.
            local candidate, status = self:BuildOverallCandidate({
                type = scene == "mplus" and "mythicplus" or "history",
                name = mergedName,
                allowIncomplete = false,
            })
            if not candidate then
                self._pendingMergeStatus = status
                return false
            end
            fullRun = self:CommitArchiveCandidate(candidate, {insert = false, prefix = scene == "mplus" and "mp" or "merged"})
            fullRun._isMerged = true
        else
            -- Raid, or an exit that had to wait through a newer outdoor fight:
            -- aggregate only the tagged local run so no later combat leaks in.
            local source = {}
            for _, seg in ipairs(all) do
                if scene ~= "raid" or seg._isBoss then table.insert(source, seg) end
            end
            if #source == 0 then return finishEmptyExit() end
            fullRun = self:MergeLocalSegments(source, {
                type = scene == "mplus" and "mythicplus" or "history",
                name = mergedName, prefix = scene == "mplus" and "mp" or "merged",
                isMerged = true,
            })
        end

        fullRun._instanceTag = nil
        fullRun._isBoss = false
        fullRun._isMerged = true
        fullRun._builtByMythicPlus = scene == "mplus"
        fullRun.mythicLevel = mythicLevel or 0
        fullRun.mapName = mythicMapName or instanceName
        local pending = ns.MythicPlus and ns.MythicPlus._pendingMythicSeg
        if pending and scene == "mplus" then
            fullRun.success = pending.success
            fullRun.mapID = pending.mapID
            fullRun._keystoneTime = (pending.elapsed or 0) / 1000
            ns.MythicPlus._pendingMythicSeg = nil
        end
        table.insert(segs.history, 1, fullRun)
        if generationUnchanged then
            segs.overall = fullRun
            segs:SetFullRunOverride(fullRun)
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
