--[[
    Light Damage - UIRefresh.lua
    刷新逻辑:Refresh, RefreshTitle, RefreshHead, ShowTooltip, FillOvrBars

    API-first:
    - 死亡模式不再强制走本地 deathLog
    - Current / Overall / sessionID 都优先读 C_DamageMeter
    - Overall deaths 显示具体死亡条目，不再显示 totalAmount 次数榜
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local T = UI.T
local COUNT_MODES = UI.COUNT_MODES
local MODE_TO_DM = UI.MODE_TO_DM

local function IsSecret(value)
    local gateway = ns.DamageMeterGateway
    if gateway then return not gateway:IsAccessible(value) end
    return issecretvalue and issecretvalue(value) or false
end

local function SafeSessionDuration(sessionType)
    local gateway = ns.DamageMeterGateway
    if not gateway then return 0 end
    local value, state = gateway:GetSessionDurationRaw(sessionType)
    if state == gateway.ACCESSIBLE and type(value) == "number" then return value end
    return 0
end

local function SegmentDuration(seg)
    return ns.Analysis and ns.Analysis:GetSegmentDuration(seg) or (seg and seg.duration or 0)
end

local function TooltipNumber(value, isProtected)
    if isProtected then
        local formatter = ns.AbbrevProtectedNumber
        if formatter then
            local ok, text = pcall(formatter, value)
            if ok then return text end
        end
        return L.COMBAT_DATA_LOCKED
    end
    return ns.AbbrevNumber(value)
end

function UI:BuildLocalPlayerSnapshot()
    local guid = ns.state and ns.state.playerGUID or UnitGUID("player")
    local guidAccessible = not IsSecret(guid) and type(guid) == "string"
    local cache = guidAccessible and ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
    if not guidAccessible then guid = nil end
    local specID, specIconID = cache.specID, cache.specIconID
    local ilvl, score = cache.ilvl or 0, cache.score or 0

    if not specID then
        local index = GetSpecialization and GetSpecialization()
        if index then
            local id, _, _, icon = GetSpecializationInfo(index)
            specID, specIconID = id or specID, icon or specIconID
        end
    end
    if ilvl <= 0 then
        local _, equipped = GetAverageItemLevel()
        ilvl = math.floor(equipped or 0)
    end

    self._localPlayerSnapshot = {
        guid = guid, specID = specID, specIconID = specIconID,
        ilvl = ilvl, score = score,
    }
    return self._localPlayerSnapshot
end

function UI:GetLocalPlayerSnapshot()
    return self._localPlayerSnapshot or self:BuildLocalPlayerSnapshot()
end

function UI:BeginDataRefresh()
    if self._sessionCache then
        for _, sub in pairs(self._sessionCache) do wipe(sub) end
    else
        self._sessionCache = {}
    end
    self._rawSessionCache = self._rawSessionCache or {byType = {}, byID = {}}
    wipe(self._rawSessionCache.byType)
    wipe(self._rawSessionCache.byID)
    self._displaySourceCache = self._displaySourceCache or {}
    wipe(self._displaySourceCache)
    self._sessionDurationCache = self._sessionDurationCache or {}
    wipe(self._sessionDurationCache)
    self._observedSources = self._observedSources or {}
    wipe(self._observedSources)
    local gateway = ns.DamageMeterGateway
    self._refreshRawGeneration = gateway and gateway:GetRawGeneration() or nil
    -- Built lazily on the first self row/tooltip in this refresh. Collapsed or
    -- empty windows therefore perform no specialization/item-level calls.
    self._localPlayerSnapshot = nil
end

function UI:GetRefreshSessionDuration(sessionType)
    local cache = self._sessionDurationCache
    if not cache then cache = {}; self._sessionDurationCache = cache end
    local duration = cache[sessionType]
    if duration == nil then
        duration = SafeSessionDuration(sessionType)
        cache[sessionType] = duration
    end
    return duration
end

function UI:ObserveDamageMeterSourceOnce(source)
    if type(source) ~= "table" then return end
    local gateway = ns.DamageMeterGateway
    if gateway and not gateway:IsTableAccessible(source) then return end
    local seen = self._observedSources
    if not seen then seen = {}; self._observedSources = seen end
    local key
    local okLocal, localValue = pcall(function() return source.isLocalPlayer end)
    if okLocal and (not gateway or gateway:IsAccessible(localValue)) and localValue == true then
        key = "local"
    else
        local okGUID, guid = pcall(function() return source.sourceGUID end)
        if okGUID and (not gateway or gateway:IsAccessible(guid)) and type(guid) == "string" then
            key = guid
        end
    end
    if key and seen[key] then return end
    if key then seen[key] = true end
    if ns.ObserveDamageMeterSource then ns:ObserveDamageMeterSource(source) end
end

function UI:GetDisplaySource(range)
    local cache = self._displaySourceCache
    if not cache then
        self:BeginDataRefresh()
        cache = self._displaySourceCache
    end
    local source = cache[range]
    if not source then
        source = self:ResolveDisplaySource(range)
        cache[range] = source
    end
    return source
end

-- One raw C_DamageMeter session lookup per locator/stat in a UI refresh.  The
-- returned session and its source vector are table-guarded before render code
-- is allowed to index or iterate either object.
function UI:GetRefreshRawSession(sessionType, sessionID, dmType)
    local gateway = ns.DamageMeterGateway
    if not gateway or dmType == nil or (sessionType == nil and sessionID == nil) then return nil end
    local cache = self._rawSessionCache
    if not cache then self:BeginDataRefresh(); cache = self._rawSessionCache end
    local root, locator
    if sessionID ~= nil then root, locator = cache.byID, sessionID
    else root, locator = cache.byType, sessionType end
    local sub = root[locator]
    if not sub then sub = {}; root[locator] = sub end
    local cached = sub[dmType]
    if type(cached) ~= "nil" then return cached ~= false and cached or nil end

    local session = select(1, gateway:GetRawSession(sessionType, sessionID, dmType))
    if type(session) ~= "table" or not gateway:IsTableAccessible(session) then
        sub[dmType] = false
        return nil
    end
    local ok, sources = pcall(function() return session.combatSources end)
    if not ok or type(sources) ~= "table" or not gateway:IsTableAccessible(sources) then
        sub[dmType] = false
        return nil
    end
    sub[dmType] = session
    return session
end

-- The single display-source resolver for every overview cell.  "current" and
-- "total" become two views of the same segment during a full-run override;
-- explicitly selecting Overall likewise makes both ranges use Overall.
function UI:ResolveDisplaySource(range)
    local preview = self._previewContext
    if preview then
        local model = preview.model
        local seg = model and (range == "total" and model.overall or model:GetViewSegment())
        return {kind="local", segment=seg, duration=SegmentDuration(seg), range=range, preview=true}
    end

    local segs = ns.Segments
    local gateway = ns.DamageMeterGateway
    local generation = self._refreshRawGeneration
    if generation == nil and gateway then generation = gateway:GetRawGeneration() end
    if not segs then return {kind="local", range=range, duration=0} end

    local override = segs:GetFullRunOverride()
    if override then
        -- Leaving an instance selects the generated full-run by default and
        -- keeps Total on that snapshot until the next combat.  It must not,
        -- however, swallow an explicit History selection: Current-range cells
        -- then show the selected archived/virtual segment while Total remains
        -- the full-run.  Selecting Current/Total, or the full-run itself,
        -- continues to make both ranges display the full-run as designed.
        local viewingOverride = segs:IsViewingArchived()
            and segs.viewIndex and segs.viewIndex.localID == override._localID
        local useOverride = range == "total" or segs:IsViewingCurrent()
            or segs:IsViewingOverall() or viewingOverride
        if useOverride then
            return {kind="local", segment=override, duration=SegmentDuration(override), range=range, fullRun=true}
        end
    end

    if segs:IsViewingOverall() then
        local seg = segs.overall
        return {kind="api", segment=seg, duration=self:GetRefreshSessionDuration(Enum.DamageMeterSessionType.Overall),
            sessionType=Enum.DamageMeterSessionType.Overall, range=range, rawGeneration=generation}
    end

    if range == "total" then
        local seg = segs.overall
        return {kind="api", segment=seg, duration=self:GetRefreshSessionDuration(Enum.DamageMeterSessionType.Overall),
            sessionType=Enum.DamageMeterSessionType.Overall, range=range, rawGeneration=generation}
    end

    local seg = segs:GetViewSegment()
    local source = {kind="local", segment=seg, duration=SegmentDuration(seg), range=range}
    if segs:IsViewingCurrent() then
        if ns.state.inCombat then
            source.kind = "api"
            source.sessionType = Enum.DamageMeterSessionType.Current
            source.rawGeneration = generation
        elseif seg and seg._sessionID and seg._archiveGeneration == generation then
            source.kind = "api"
            source.sessionID = seg._sessionID
            source.rawGeneration = generation
        end
        return source
    end

    if segs:IsViewingVirtual() and seg and seg._isVirtual and seg._sessionID then
        -- Virtual rows are materialized from the current API generation.  Stamp
        -- the ephemeral shell so no later reset can reuse its raw handle.
        if seg._archiveGeneration == nil then seg._archiveGeneration = generation end
        if seg._archiveGeneration == generation then
            source.kind = "api"
            source.sessionID = seg._sessionID
            source.rawGeneration = generation
        end
        return source
    end

    -- A committed archive is immutable local data even while its old Blizzard
    -- session ID still happens to exist.  Only an incomplete legacy shell with
    -- an explicitly matching generation may temporarily use the API.
    if segs:IsViewingArchived() and seg and not seg._dataLoaded and seg._sessionID
        and seg._archiveGeneration == generation then
        source.kind = "api"
        source.sessionID = seg._sessionID
        source.rawGeneration = generation
    end
    return source
end

function UI:FillModeBars(bars, listObj, head, mode, seg, dur, sessionType, sessionID, displaySource)
    mode = mode or "damage"
    if displaySource then
        seg, dur = displaySource.segment, displaySource.duration
        sessionType, sessionID = displaySource.sessionType, displaySource.sessionID
    end
    local dmType = MODE_TO_DM[mode]
    local rawSession = (sessionType or sessionID) and self:GetRefreshRawSession(sessionType, sessionID, dmType) or nil
    local apiOk = type(rawSession) ~= "nil"

    if mode == "deaths" then
        if apiOk then
            self:RefreshHead(head, mode, nil, 0, sessionType, sessionID)
            self:FillDeathBars(seg, bars, listObj, sessionType, sessionID, rawSession)
        else
            self:RefreshHead(head, mode, seg, dur)
            self:FillDeathBars(seg, bars, listObj)
        end
        return
    end

    if apiOk then
        self:RefreshHead(head, mode, nil, 0, sessionType, sessionID)
        self:FillBarsFromAPI(bars, listObj, mode, sessionType, sessionID, rawSession)
    else
        self:RefreshHead(head, mode, seg, dur)
        self:FillBars(bars, listObj, ns.Analysis and ns.Analysis:GetSorted(seg, mode) or {}, dur, mode)
    end
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:BeginDataRefresh()

    local segs = ns.Segments
    local currentSource = self:GetDisplaySource("current")
    local totalSource = self:GetDisplaySource("total")
    local seg, dur = currentSource.segment, currentSource.duration
    local sp   = ns.db.split
    local mode = ns.db.display.mode
    local useOvr = self:IsOverallColumnActive()
    local isSplitView = self:IsSplitActiveInCurrentScene() and (mode == "split")

    local now = GetTime()
    if not self._lastTitleRefresh or (now - self._lastTitleRefresh) > 0.5 then
        self._lastTitleRefresh = now
        self:RefreshTitle()
    end

    if self.splitTab then
        if isSplitView then self.splitTab.abg:Show(); self:SetTabTextColor(self.splitTab.text, true)
        else self.splitTab.abg:Hide(); self:SetTabTextColor(self.splitTab.text, false) end
    end
    for _, t in ipairs(self.tabs) do
        if mode == t.mode then t.abg:Show(); self:SetTabTextColor(t.text, true)
        else t.abg:Hide(); self:SetTabTextColor(t.text, false) end
    end

    if isSplitView then
        self:FillModeBars(self.priBars, self.priList, self.priHead, sp.primaryMode, seg, dur, nil, nil, currentSource)
        self:FillModeBars(self.secBars, self.secList, self.secHead, sp.secondaryMode, seg, dur, nil, nil, currentSource)
        if useOvr then self:FillOvrBars(true, sp, mode) end
    else
        self:FillModeBars(self.priBars, self.priList, self.priHead, mode, seg, dur, nil, nil, currentSource)
        if useOvr then self:FillOvrBars(false, sp, mode) end
    end

    if useOvr and self.ovrContainer and self.ovrContainer:IsShown() then
        local ovrTitleWord = L.OVERALL
        if segs and segs.overall and segs.overall._isMerged then ovrTitleWord = L.OVERALL_SEGMENT end
        if isSplitView then
            local priLabel = L[ns.MODE_NAMES[sp.primaryMode] or ""]
            local secLabel = L[ns.MODE_NAMES[sp.secondaryMode] or ""]
            self:SetModeHeaderText(self.ovrPriHead.label, string.format(L.OVERALL_MODE_HEADER_FORMAT, ovrTitleWord, priLabel), sp.primaryMode)
            self:SetModeHeaderText(self.ovrSecHead.label, string.format(L.OVERALL_MODE_HEADER_FORMAT, ovrTitleWord, secLabel), sp.secondaryMode)
        else
            local modeLabel = L[ns.MODE_NAMES[mode] or ""]
            self:SetModeHeaderText(self.ovrPriHead.label, string.format(L.OVERALL_MODE_HEADER_FORMAT, ovrTitleWord, modeLabel), mode)
        end
    end
end

function UI:FillOvrBars(isSplitView, sp, mode)
    local source = self:GetDisplaySource("total")
    local seg, dur = source.segment, source.duration

    if isSplitView then
        self:FillModeBars(self.ovrPriBars, self.ovrPriList, self.ovrPriHead, sp.primaryMode, seg, dur, nil, nil, source)
        self:FillModeBars(self.ovrSecBars, self.ovrSecList, self.ovrSecHead, sp.secondaryMode, seg, dur, nil, nil, source)
    else
        self:FillModeBars(self.ovrPriBars, self.ovrPriList, self.ovrPriHead, mode, seg, dur, nil, nil, source)
    end
end

function UI:RefreshTitle()
    if not self.frame or not self.frame:IsShown() then return end
    if not self.titleText then return end

    local segs = ns.Segments
    local segL = segs and segs:GetViewLabel() or L.NO_DATA
    local dot = ""
    local dur = 0
    local liveCombatLabel

    if ns.state.inCombat and ns.state.combatStartTime and ns.state.combatStartTime > 0 then
        local isViewingOverall = segs and segs:IsViewingOverall()
        local isViewingCurrent = segs and segs:IsViewingCurrent()
        if isViewingOverall then
            dur = SafeSessionDuration(Enum.DamageMeterSessionType.Overall)
        else
            dur = SafeSessionDuration(Enum.DamageMeterSessionType.Current)
        end

        -- The locally-created Current segment starts with the zone name, which
        -- is useful archive context but is not the live combat title.  Blizzard
        -- exposes the actual encounter/enemy label on the final available
        -- combat session; show that name while Current is selected.  Boss event
        -- metadata is the safe immediate fallback until the live session exists.
        if isViewingCurrent then
            local gateway = ns.DamageMeterGateway
            local name, state
            if gateway then name, state = gateway:GetLiveSessionName() end
            if gateway and state == gateway.ACCESSIBLE then
                liveCombatLabel = name
            else
                local current = segs and segs.current
                if current and current._isBoss then
                    liveCombatLabel = current.encounterName or current.name
                end
                liveCombatLabel = liveCombatLabel or L.COMBAT
            end
        end
    else
        local seg = segs and segs:GetViewSegment()
        if seg and seg._keystoneTime and seg._keystoneTime > 0 then dur = seg._keystoneTime else dur = seg and (seg.duration or 0) or 0 end
    end

    local tStr = dur > 0 and ("|cffaaaaaa" .. ns:FormatTime(dur) .. "|r") or ""
    if self.titleTime then self.titleTime:SetText(tStr) end

    if liveCombatLabel then
        self.titleText:SetText(liveCombatLabel)
        return
    end

    if ns.MythicPlus and ns.MythicPlus:IsActive() and ns.state.inMythicPlus then
        local info = ns.MythicPlus:GetHeaderInfo()
        if info then
            local levelStr = (info.level and info.level > 0) and string.format("|cff4cb8e8+%d|r ", info.level) or ""
            local nameStr = info.name and ("|cff4cb8e8" .. info.name .. "|r") or ""
            self.titleText:SetText(dot .. segL .. " " .. levelStr .. nameStr)
            return
        end
    end

    self.titleText:SetText(dot .. segL)
end

function UI:RefreshHead(h, mode, seg, dur, apiSessionType, apiSessionID)
    if not h:IsShown() then return end
    local mn = L[ns.MODE_NAMES[mode] or mode]
    self:SetModeHeaderText(h.label, mn, mode)

    -- Cell headers only identify the statistic and range.  Team-wide summary
    -- text duplicated the bar data and made compact overview cells noisy.
    h.info:SetText(""); h.info:Hide()
    h.rawInfo:SetText(""); h.rawInfo:Hide()
end

-- ============================================================
-- Tooltip
-- ============================================================
function UI:AnchorTooltipToWindow(bar,tip)
    tip=tip or GameTooltip
    local f = self.frame
    if not f then tip:SetOwner(bar.frame, "ANCHOR_LEFT"); return end
    tip:SetOwner(bar.frame, "ANCHOR_NONE")
    tip:ClearAllPoints()
    local scale = f:GetEffectiveScale()
    local fLeft = (f:GetLeft() or 0) * scale
    local fTop = (f:GetTop() or 0) * scale
    local screenH = GetScreenHeight() * UIParent:GetEffectiveScale()
    if fLeft > 280 then tip:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
    elseif fTop < screenH * 0.7 then tip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    else tip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4) end
end

function UI:ShowTooltip(bar, section)
    local d = bar._data
    if not d then return end
    -- Live Damage Meter rows can contain opaque names and numbers.  Render them
    -- through ordinary FontStrings, never GameTooltip:AddLine/AddDoubleLine.
    if not ns.PrivateTooltip or not ns.PrivateTooltip.GetOpaque then return end
    local tip=ns.PrivateTooltip:GetOpaque()
    self:AnchorTooltipToWindow(bar,tip)

    local guid = bar._guid
    local seg = bar._detailSegment or (ns.Segments and ns.Segments:GetViewSegment())
    local specID, ilvl, score

    if d and d.isAPI then
        specID = d.specID; ilvl = d.ilvl or 0; score = d.score or 0
    elseif seg and seg.isActive then
        -- Raw combat GUIDs can be secret in 12.x.  Never use one as a normal
        -- Lua table key or in a conditional comparison; row-carried public
        -- metadata remains available and is still shown.
        local guidAccessible = not IsSecret(guid) and type(guid) == "string"
        local cache = guidAccessible and ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
        specID = (d and d.specID) or cache.specID
        ilvl = (d and d.ilvl) or cache.ilvl or 0
        score = cache.score or 0
        if guidAccessible and guid == ns.state.playerGUID then
            local snapshot = self:GetLocalPlayerSnapshot()
            specID = snapshot and snapshot.specID or specID
            ilvl = snapshot and snapshot.ilvl or ilvl
            score = snapshot and snapshot.score or score
        end
        if d then d.specID = specID; d.ilvl = ilvl; d.score = score end
    else
        specID = d and d.specID
        ilvl = d and d.ilvl or 0
        score = d and d.score or 0
    end

    local specName = ""
    if specID then
        local _, name = GetSpecializationInfoByID(specID)
        if name then specName = name end
    end
    local specIconID = d and d.specIconID
    if specName == "" and specIconID and not IsSecret(specIconID)
        and specIconID > 0 and ns.ICON_TO_SPECID then
        local sid = ns.ICON_TO_SPECID[specIconID]
        if sid then
            local _, name = GetSpecializationInfoByID(sid)
            if name then specName = name end
        end
    end

    local function AddPlayerInfoLines()
        if specName ~= "" or (ilvl and ilvl > 0) or (score and score > 0) then
            tip:AddLine(" ")
            if specName ~= "" then tip:AddDoubleLine(L.SPEC, specName, 0.7,0.7,0.7, 1,1,1) end
            if ilvl and ilvl > 0 then tip:AddDoubleLine(L.AVG_ITEM_LEVEL, tostring(ilvl), 0.7,0.7,0.7, 1,0.85,0) end
            if score and score > 0 then
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if color then tip:AddDoubleLine(L.MYTHIC_PLUS_RATING, color:WrapTextInColorCode(tostring(score)), 0.7,0.7,0.7, 1,1,1)
                else tip:AddDoubleLine(L.MYTHIC_PLUS_RATING, tostring(score), 0.7,0.7,0.7, 1,0.5,0) end
            end
        end
    end

    local function AddNameLine(raw,class)
        if type(raw) == "nil" then return false end
        local shown
        if issecretvalue and issecretvalue(raw) then shown=ns:DisplayName(raw) else shown=ns:DisplayName(raw) end
        if type(shown) == "nil" then return false end
        if issecretvalue and issecretvalue(shown) then tip:AddLine(shown)
        else tip:AddLine(ns:GetClassHex(class)..shown.."|r") end
        return true
    end

    if bar._isDeath then
        AddNameLine(d.playerName,d.playerClass)
        AddPlayerInfoLines()
        tip:AddLine(" ")
        if type(d.killingAbility) == "string" and d.killingAbility ~= "" then
            tip:AddDoubleLine(L.FATAL_SPELL, d.killingAbility, 0.7,0.7,0.7, 1,0.3,0.3)
        end
        if type(d.killerName) == "string" and d.killerName ~= "" then
            tip:AddDoubleLine(L.KILLER, ns:DisplayName(d.killerName), 0.7,0.7,0.7, 1,1,1)
        end
        if d._incomplete then
            tip:AddLine(L.COLORED_DEATH_RECAP_PENDING_DESC)
        end
        if type(d.totalDamageTaken) == "number" then
            tip:AddDoubleLine(L.DAMAGE_BEFORE_DEATH, ns:FormatNumber(d.totalDamageTaken), 0.7,0.7,0.7, 1,0.5,0.5)
        end
        if type(d.totalHealingReceived) == "number" then
            tip:AddDoubleLine(L.HEALED_BEFORE_DEATH, ns:FormatNumber(d.totalHealingReceived), 0.7,0.7,0.7, 0.5,1,0.5)
        end
        tip:AddLine(" ")
        tip:AddLine(L.COLORED_DEATH_LOG_HINT, 0.4,0.4,0.4)
        tip:Show()
        return
    end

    if d.isAPI then
        AddNameLine(bar._nameStr,bar._classStr)
        AddPlayerInfoLines()
        tip:AddLine(" ")
        tip:AddLine(L.COLORED_API_REALTIME_DATA)
        local amountText = TooltipNumber(d.totalAmount, d.isSecretAmount)
        if COUNT_MODES[bar._mode] then
            tip:AddDoubleLine((L[ns.MODE_NAMES[bar._mode] or bar._mode])..L.COUNT_SUFFIX, amountText, 0.7,0.7,0.7, 1,1,1)
        elseif ns.db.display.showPerSecond then
            local rateText = TooltipNumber(d.amountPerSecond, d.isSecretRate)
            tip:AddDoubleLine(L[ns.MODE_NAMES[bar._mode] or bar._mode], amountText, 0.7,0.7,0.7, 1,1,1)
            tip:AddDoubleLine(L.PER_SECONDS, rateText, 0.7,0.7,0.7, 1,0.85,0)
        else
            tip:AddDoubleLine(L[ns.MODE_NAMES[bar._mode] or bar._mode], amountText, 0.7,0.7,0.7, 1,1,1)
        end
        tip:AddLine(" ")
        tip:AddLine(L.COLORED_BAR_TOOLTIP_HINT, 0.4,0.4,0.4)
        tip:Show()
        return
    end

    local mode = bar._mode or ns.db.display.mode
    local mn = L[ns.MODE_NAMES[mode] or mode]
    AddNameLine(d.name,d.class)
    AddPlayerInfoLines()
    tip:AddLine(" ")
    tip:AddLine(L.SEGMENT)
    tip:AddDoubleLine(mn, ns:FormatNumber(d.value), 0.7,0.7,0.7, 1,1,1)
    if type(d.perSec) == "number" and ns.MODE_UNITS[mode] then
        tip:AddDoubleLine(ns.MODE_UNITS[mode], ns:FormatNumber(d.perSec), 0.7,0.7,0.7, 1,0.85,0)
    end
    tip:AddDoubleLine(L.PERCENT, string.format("%.1f%%", d.percent or 0), 0.7,0.7,0.7, 1,1,1)
    if d.petDamage and d.petDamage > 0 and mode == "damage" then tip:AddDoubleLine(L.INCL_PET, ns:FormatNumber(d.petDamage), 0.5,0.5,0.5, 0.7,0.7,0.7) end

    tip:AddLine(" ")
    if d.deaths and d.deaths > 0 then tip:AddDoubleLine(L.DEATHS, d.deaths, 0.7,0.7,0.7, 1,0.3,0.3) end
    if d.interrupts and d.interrupts > 0 then tip:AddDoubleLine(L.INTERRUPTS, d.interrupts, 0.7,0.7,0.7, 0.3,1,0.3) end
    if d.dispels and d.dispels > 0 then tip:AddDoubleLine(L.DISPELS, d.dispels, 0.7,0.7,0.7, 0.3,0.8,1) end
    tip:AddLine(" ")
    tip:AddLine(L.COLORED_BAR_TOOLTIP_HINT, 0.4,0.4,0.4)
    tip:Show()
end
