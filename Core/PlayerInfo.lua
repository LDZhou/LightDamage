--[[
    Light Damage - PlayerInfo.lua
    Event-driven roster enrichment (class/spec/item level/Mythic+ score).

    DamageMeter classFilename/specIconID remain the primary combat-row source.
    Inspect is an asynchronous enhancement only and never blocks rendering.
]]

local addonName, ns = ...

ns.PlayerInfoCache = ns.PlayerInfoCache or {}

local PlayerInfo = {}
ns.PlayerInfo = PlayerInfo

local SCORE_TTL = 300
local INSPECT_TTL = 300
local INSPECT_THROTTLE = 2.0
local INSPECT_TIMEOUT = 6.0
local RETRY_MAX = 120

local eventFrame = CreateFrame("Frame")
local rosterGeneration = 0
local rosterUnits = {}
local inspectQueue = {}
local queueHead = 1
local queuedGUIDs = {}
local pendingInspect
local rosterTimer
local rosterTimerDue
local pumpTimer
local pumpTimerDue
local lastNotifyAt = 0
local issuingInspect = false

local function IsAccessible(value)
    if type(value) == "nil" then return false end
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then return false end
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret == true then return false end
    end
    return true
end

local function AccessibleGUID(unit)
    local guid = UnitGUID(unit)
    if not IsAccessible(guid) or type(guid) ~= "string" then return nil end
    return guid
end

local function RestrictionIsActive(restrictionType)
    if not restrictionType or not C_RestrictedActions
        or not C_RestrictedActions.GetAddOnRestrictionState then return false end
    local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, restrictionType)
    local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
    return ok and state ~= inactive
end

-- Inspect is the only part of player enrichment that must yield while the
-- player is actively affecting combat.  Challenge/encounter restrictions can
-- remain active for an entire run, including safe out-of-combat periods; they
-- must not suppress public rating reads or CanInspect-driven inspect work.
local function IsInspectPaused()
    if InCombatLockdown() or UnitAffectingCombat("player") then return true end
    local types = Enum and Enum.AddOnRestrictionType
    return types and RestrictionIsActive(types.Combat) or false
end

local function InspectFrameIsShown()
    return InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown()
end

local function NotifyDataChanged(reason)
    if ns.RequestRefresh then ns:RequestRefresh("player-info:" .. tostring(reason or "update"), true)
    elseif ns.UI and ns.UI.IsVisible and ns.UI:IsVisible() then ns.UI:Refresh() end
end

local function CacheForGUID(guid)
    if not guid then return nil end
    local cache = ns.PlayerInfoCache[guid]
    if not cache then
        cache = {
            score = 0, ilvl = 0,
            scoreKnown = false, ilvlKnown = false, specKnown = false,
            lastInspect = 0, lastSeenAt = GetTime(),
        }
        ns.PlayerInfoCache[guid] = cache
    end
    return cache
end

local function Backoff(failures)
    return math.min(RETRY_MAX, 5 * (2 ^ math.min(5, math.max(0, failures or 0))))
end

local function CancelTimer(timer)
    if timer then timer:Cancel() end
end

local PumpQueue
local RebuildRoster

local function SchedulePump(delay)
    delay = math.max(0, tonumber(delay) or 0)
    local due = GetTime() + delay
    if pumpTimer and pumpTimerDue and pumpTimerDue <= due then return end
    CancelTimer(pumpTimer)
    pumpTimerDue = due
    pumpTimer = C_Timer.NewTimer(delay, function()
        pumpTimer, pumpTimerDue = nil, nil
        PumpQueue()
    end)
end

local function ScheduleRosterRefresh(delay)
    delay = math.max(0, tonumber(delay) or 0.15)
    local due = GetTime() + delay
    if rosterTimer and rosterTimerDue and rosterTimerDue <= due then return end
    CancelTimer(rosterTimer)
    rosterTimerDue = due
    rosterTimer = C_Timer.NewTimer(delay, function()
        rosterTimer, rosterTimerDue = nil, nil
        RebuildRoster()
    end)
end

local function EnqueueInspect(unit, guid, generation)
    if queuedGUIDs[guid] then return end
    queuedGUIDs[guid] = true
    inspectQueue[#inspectQueue + 1] = { unit=unit, guid=guid, generation=generation }
end

local function ClearPendingState()
    if pendingInspect and pendingInspect.timeout then pendingInspect.timeout:Cancel() end
    pendingInspect = nil
end

local function RetryPending(clearOwnedRequest)
    local request = pendingInspect
    if not request then return end
    local cache = ns.PlayerInfoCache[request.guid]
    if cache then
        cache.inspectFailures = (cache.inspectFailures or 0) + 1
        cache.inspectRetryAt = GetTime() + Backoff(cache.inspectFailures)
    end
    if clearOwnedRequest and request.owned and not IsInspectPaused() and not InspectFrameIsShown() then
        pcall(ClearInspectPlayer)
    end
    ClearPendingState()
    ScheduleRosterRefresh(cache and math.max(1, (cache.inspectRetryAt or 0) - GetTime()) or 5)
    SchedulePump(0)
end

local function ReadLocalPlayer()
    local guid = AccessibleGUID("player")
    if not guid then return end
    local cache = CacheForGUID(guid)
    local _, classFilename = UnitClass("player")
    cache.class = classFilename or cache.class
    cache.lastSeenAt = GetTime()
    cache.seenGeneration = rosterGeneration

    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local specID, _, _, icon = GetSpecializationInfo(specIndex)
        if specID then cache.specID = specID; cache.specKnown = true; cache.specAt = GetTime() end
        if icon then cache.specIconID = icon end
    end
    local _, equipped = GetAverageItemLevel()
    if type(equipped) == "number" then
        cache.ilvl = math.floor(equipped)
        cache.ilvlKnown = true
        cache.ilvlAt = GetTime()
    end
end

local function ReadScore(unit, cache, now)
    if cache.scoreKnown and now - (cache.scoreAt or 0) < SCORE_TTL then return end
    if now < (cache.scoreRetryAt or 0) then return end
    if not C_PlayerInfo or not C_PlayerInfo.GetPlayerMythicPlusRatingSummary then return end
    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    local gateway = ns.DamageMeterGateway
    local summaryReadable = ok and type(summary) == "table"
        and (not gateway or gateway:IsTableAccessible(summary))
    local scoreValue
    if summaryReadable then
        local readOK, value = pcall(function() return summary.currentSeasonScore end)
        if readOK and IsAccessible(value) then scoreValue = value end
    end
    if type(scoreValue) ~= "nil" then
        local score = tonumber(scoreValue)
        if score then
            local changed = not cache.scoreKnown or cache.score ~= score
            cache.score = score
            cache.scoreKnown = true -- zero is a valid cached result
            cache.scoreAt = now
            cache.scoreFailures = 0
            cache.scoreRetryAt = nil
            if changed then NotifyDataChanged("score") end
            return
        end
    end
    cache.scoreFailures = (cache.scoreFailures or 0) + 1
    local retryDelay = Backoff(cache.scoreFailures)
    cache.scoreRetryAt = now + retryDelay
    ScheduleRosterRefresh(retryDelay)
end

local function ProcessUnit(unit, isLocal, generation, now)
    if not UnitExists(unit) or not UnitIsPlayer(unit) or not UnitIsConnected(unit) then return end
    local guid = AccessibleGUID(unit)
    if not guid then return end -- never compare or index with a secret GUID
    local cache = CacheForGUID(guid)
    local _, classFilename = UnitClass(unit)
    cache.class = classFilename or cache.class
    cache.lastSeenAt = now
    cache.seenGeneration = generation
    rosterUnits[unit] = guid

    local playerGUID = ns.state and ns.state.playerGUID
    local isSelf = isLocal or (IsAccessible(playerGUID) and guid == playerGUID)
    if isSelf then
        -- Local spec and item level come from direct APIs, but the Mythic+
        -- rating still uses the same rating-summary API as every other player.
        -- Read it before returning from the inspect-only portion of this path.
        ReadScore(unit, cache, now)
        return
    end
    ReadScore(unit, cache, now)

    if IsInspectPaused() then return end

    local inspectFresh = cache.ilvlKnown and now - (cache.ilvlAt or cache.lastInspect or 0) < INSPECT_TTL
    local specFresh = cache.specKnown and now - (cache.specAt or 0) < INSPECT_TTL
    if (not inspectFresh or not specFresh) and now >= (cache.inspectRetryAt or 0) then
        EnqueueInspect(unit, guid, generation)
    end
end

RebuildRoster = function()
    rosterGeneration = rosterGeneration + 1
    local generation = rosterGeneration
    local now = GetTime()
    wipe(rosterUnits)
    wipe(inspectQueue)
    wipe(queuedGUIDs)
    queueHead = 1

    ReadLocalPlayer()
    ProcessUnit("player", true, generation, now)

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do ProcessUnit("raid" .. i, false, generation, now) end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do ProcessUnit("party" .. i, false, generation, now) end
    end

    if not IsInspectPaused() then SchedulePump(0) end
end

PumpQueue = function()
    if pendingInspect or IsInspectPaused() then return end
    if InspectFrameIsShown() then
        SchedulePump(2)
        return
    end

    local now = GetTime()
    local throttle = INSPECT_THROTTLE - (now - lastNotifyAt)
    if throttle > 0 then SchedulePump(throttle); return end

    while queueHead <= #inspectQueue do
        local request = inspectQueue[queueHead]
        queueHead = queueHead + 1
        queuedGUIDs[request.guid] = nil
        local cache = ns.PlayerInfoCache[request.guid]
        local currentGUID = request.generation == rosterGeneration and AccessibleGUID(request.unit) or nil
        if cache and currentGUID and currentGUID == request.guid
            and UnitExists(request.unit) and UnitIsConnected(request.unit)
            and GetTime() >= (cache.inspectRetryAt or 0) then
            if CanInspect(request.unit) then
                lastNotifyAt = GetTime()
                pendingInspect = {
                    unit=request.unit, guid=request.guid,
                    generation=request.generation, owned=true,
                }
                pendingInspect.timeout = C_Timer.NewTimer(INSPECT_TIMEOUT, function()
                    if pendingInspect and pendingInspect.guid == request.guid then RetryPending(true) end
                end)
                issuingInspect = true
                local ok = pcall(NotifyInspect, request.unit)
                issuingInspect = false
                if not ok then RetryPending(false) end
                return
            end
            cache.inspectFailures = (cache.inspectFailures or 0) + 1
            cache.inspectRetryAt = GetTime() + Backoff(cache.inspectFailures)
            ScheduleRosterRefresh(cache.inspectRetryAt - GetTime())
        end
    end

    wipe(inspectQueue)
    wipe(queuedGUIDs)
    queueHead = 1
end

local function OnInspectReady(eventGUID)
    if not pendingInspect then return end
    if not IsAccessible(eventGUID) or type(eventGUID) ~= "string" then
        RetryPending(false)
        return
    end
    if IsInspectPaused() then
        RetryPending(false)
        return
    end

    local request = pendingInspect
    if request.guid ~= eventGUID then return end
    local currentGUID = AccessibleGUID(request.unit)
    if not currentGUID or currentGUID ~= request.guid or request.generation ~= rosterGeneration then
        RetryPending(false)
        return
    end

    local cache = ns.PlayerInfoCache[request.guid]
    local changed = false
    if cache then
        local inspectItemLevel = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
        local okIlvl, ilvl = false, nil
        if inspectItemLevel then okIlvl, ilvl = pcall(inspectItemLevel, request.unit) end
        if okIlvl and IsAccessible(ilvl) and type(ilvl) == "number" and ilvl > 0 then
            cache.ilvl = math.floor(ilvl)
            cache.ilvlKnown = true
            cache.ilvlAt = GetTime()
            changed = true
        end
        if GetInspectSpecialization then
            local okSpec, specID = pcall(GetInspectSpecialization, request.unit)
            if okSpec and IsAccessible(specID) and type(specID) == "number" and specID > 0 then
                cache.specID = specID
                cache.specKnown = true
                cache.specAt = GetTime()
                changed = true
            end
        end
        cache.lastInspect = GetTime()
        cache.inspectFailures = 0
        cache.inspectRetryAt = nil
    end

    if request.owned and not InspectFrameIsShown() then pcall(ClearInspectPlayer) end
    ClearPendingState()
    if changed then NotifyDataChanged("inspect") end
    SchedulePump(0)
end

function PlayerInfo:ObserveDamageMeterSource(source)
    if type(source) ~= "table" then return end
    local gateway = ns.DamageMeterGateway
    if gateway and not gateway:IsTableAccessible(source) then return end
    local guid
    local localPlayer = IsAccessible(source.isLocalPlayer) and source.isLocalPlayer == true
    if localPlayer then guid = AccessibleGUID("player")
    elseif IsAccessible(source.sourceGUID) and type(source.sourceGUID) == "string" then guid = source.sourceGUID end
    if not guid then return end
    local cache = CacheForGUID(guid)
    if IsAccessible(source.classFilename) and type(source.classFilename) == "string" and source.classFilename ~= "" then
        cache.class = source.classFilename
    end
    -- This NeverSecret DamageMeter field is authoritative for combat icons.
    if IsAccessible(source.specIconID) and type(source.specIconID) == "number" and source.specIconID > 0 then
        cache.specIconID = source.specIconID
        cache.specIconSource = "damageMeter"
    end
end

function PlayerInfo:Get(guid)
    if not IsAccessible(guid) or type(guid) ~= "string" then return nil end
    return ns.PlayerInfoCache[guid]
end

function PlayerInfo:Refresh(delay)
    ScheduleRosterRefresh(delay or 0)
end

ns.ObserveDamageMeterSource = function(selfOrSource, source)
    PlayerInfo:ObserveDamageMeterSource(source or selfOrSource)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        OnInspectReady(arg1)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if pendingInspect then RetryPending(false) end
        CancelTimer(pumpTimer); pumpTimer, pumpTimerDue = nil, nil
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if IsInspectPaused() then
            if pendingInspect then RetryPending(false) end
        else
            ScheduleRosterRefresh(0.2)
            SchedulePump(0.2)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
            local guid = AccessibleGUID(arg1)
            local cache = guid and ns.PlayerInfoCache[guid]
            if cache then cache.specKnown = false; cache.specAt = 0; cache.inspectRetryAt = nil end
        end
        ReadLocalPlayer()
        NotifyDataChanged("local")
        ScheduleRosterRefresh(0.1)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- A completed key can change every party member's rating immediately;
        -- bypass the normal five-minute TTL on the next safe roster pass.
        for _, cache in pairs(ns.PlayerInfoCache) do
            cache.scoreKnown = false
            cache.scoreAt = 0
            cache.scoreRetryAt = nil
        end
        ScheduleRosterRefresh(2)
    else
        ScheduleRosterRefresh(event == "GROUP_ROSTER_UPDATE" and 0.2 or 0.1)
        if event == "PLAYER_REGEN_ENABLED" then SchedulePump(0.1) end
    end
end)

for _, event in ipairs({
    "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED", "INSPECT_READY",
    "ADDON_RESTRICTION_STATE_CHANGED", "CHALLENGE_MODE_COMPLETED",
}) do
    eventFrame:RegisterEvent(event)
end

-- NotifyInspect is a shared global channel.  If another consumer takes it
-- while our request is pending, relinquish ownership and never clear theirs.
if hooksecurefunc and NotifyInspect then
    hooksecurefunc("NotifyInspect", function()
        if pendingInspect and not issuingInspect then RetryPending(false) end
    end)
end
