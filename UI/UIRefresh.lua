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

local function EffMode(m)
    if m == "damageTaken" and ns.state.damageTakenView == "enemy" then return "enemyDamageTaken" end
    return m
end

local function HasAPISession(mode, sessionType, sessionID)
    local dmType = MODE_TO_DM[EffMode(mode)]
    if not dmType or not C_DamageMeter then return false end

    if sessionID then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, dmType)
        return ok and s and s.combatSources ~= nil
    end

    if sessionType then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, dmType)
        return ok and s and s.combatSources ~= nil
    end

    return false
end

function UI:FillModeBars(bars, listObj, head, mode, seg, dur, sessionType, sessionID)
    mode = mode or "damage"
    local apiOk = (sessionType or sessionID) and HasAPISession(mode, sessionType, sessionID)

    if mode == "deaths" then
        if apiOk then
            self:RefreshHead(head, mode, nil, 0, sessionType, sessionID)
            self:FillDeathBars(seg, bars, listObj, sessionType, sessionID)
        else
            self:RefreshHead(head, mode, seg, dur)
            self:FillDeathBars(seg, bars, listObj)
        end
        return
    end

    if apiOk then
        self:RefreshHead(head, mode, nil, 0, sessionType, sessionID)
        self:FillBarsFromAPI(bars, listObj, EffMode(mode), sessionType, sessionID)
    else
        self:RefreshHead(head, mode, seg, dur)
        self:FillBars(bars, listObj, ns.Analysis and ns.Analysis:GetSorted(seg, mode) or {}, dur, mode)
    end
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    if self._sessionCache then
        for _, sub in pairs(self._sessionCache) do wipe(sub) end
    else
        self._sessionCache = {}
    end

    local segs = ns.Segments
    local seg  = segs and segs:GetViewSegment()
    local dur  = ns.Analysis and ns.Analysis:GetSegmentDuration(seg) or 0
    local sp   = ns.db.split
    local mode = ns.db.display.mode
    local useOvr = self:IsOverallColumnActive()
    local isSplitView = self:IsSplitActiveInCurrentScene() and (mode == "split")

    local now = GetTime()
    if not self._lastTitleRefresh or (now - self._lastTitleRefresh) > 0.5 then
        self._lastTitleRefresh = now
        self:RefreshTitle()
    end

    -- Summary 栏：总计仍直读 Overall API。
    if self.summaryBar:IsShown() then
        local ovrTitleWord = L["总计"]
        local ovrSeg = segs and segs.overall
        if ovrSeg and ovrSeg._isMerged then ovrTitleWord = L["全程"] end

        local durSafe = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or 0
        local dmDmg = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)
        local dmHeal = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.HealingDone)

        local dmgStr, healStr = "0", "0"
        if dmDmg then local ok, s = pcall(AbbreviateNumbers, dmDmg.totalAmount); if ok and s then dmgStr = s end end
        if dmHeal then local ok, s = pcall(AbbreviateNumbers, dmHeal.totalAmount); if ok and s then healStr = s end end

        if ns.state.inCombat then
            self.summText:SetFormattedText(L["全程 %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"], ns:FormatTime(durSafe), dmgStr, healStr)
        else
            self.summText:SetText(string.format(L["%s %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"], ovrTitleWord, ns:FormatTime(durSafe), dmgStr, healStr))
        end
    end

    if self.splitTab then
        if isSplitView then self.splitTab.abg:Show(); self.splitTab.text:SetTextColor(0, 0.75, 1)
        else self.splitTab.abg:Hide(); self.splitTab.text:SetTextColor(0.55, 0.55, 0.55) end
    end
    for _, t in ipairs(self.tabs) do
        if mode == t.mode then t.abg:Show(); t.text:SetTextColor(1, 1, 1)
        else t.abg:Hide(); t.text:SetTextColor(0.55, 0.55, 0.55) end
    end

    local isOverall = segs and segs:IsViewingOverall()
    local isVirtual = segs and segs:IsViewingVirtual()
    local isArchived = segs and segs:IsViewingArchived()
    local isCurrent = segs and segs:IsViewingCurrent()

    local apiSessionType, apiSessionID = nil, nil
    if isOverall then
        apiSessionType = Enum.DamageMeterSessionType.Overall
    elseif isCurrent and ns.state.inCombat then
        apiSessionType = Enum.DamageMeterSessionType.Current
    elseif (isVirtual or isArchived) and seg and seg._sessionID then
        apiSessionID = seg._sessionID
    end

    if isSplitView then
        self:FillModeBars(self.priBars, self.priList, self.priHead, sp.primaryMode, seg, dur, apiSessionType, apiSessionID)
        self:FillModeBars(self.secBars, self.secList, self.secHead, sp.secondaryMode, seg, dur, apiSessionType, apiSessionID)
        if useOvr then self:FillOvrBars(true, sp, mode) end
    else
        self:FillModeBars(self.priBars, self.priList, self.priHead, mode, seg, dur, apiSessionType, apiSessionID)
        if useOvr then self:FillOvrBars(false, sp, mode) end
    end

    if useOvr and self.ovrContainer and self.ovrContainer:IsShown() then
        local ovrTitleWord = L["总计"]
        if segs and segs.overall and segs.overall._isMerged then ovrTitleWord = L["全程"] end
        if isSplitView then
            local priLabel = L[ns.MODE_NAMES[sp.primaryMode] or ""]
            local secLabel = L[ns.MODE_NAMES[sp.secondaryMode] or ""]
            if sp.primaryMode == "damageTaken" and ns.state.damageTakenView == "enemy" then priLabel = L["敌人承伤"] end
            if sp.secondaryMode == "damageTaken" and ns.state.damageTakenView == "enemy" then secLabel = L["敌人承伤"] end
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, priLabel))
            self.ovrSecHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, secLabel))
        else
            local modeLabel = L[ns.MODE_NAMES[mode] or ""]
            if mode == "damageTaken" and ns.state.damageTakenView == "enemy" then modeLabel = L["敌人承伤"] end
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, modeLabel))
        end
    end
end

function UI:FillOvrBars(isSplitView, sp, mode)
    local sType = Enum.DamageMeterSessionType.Overall
    local seg = ns.Segments and ns.Segments.overall
    local dur = C_DamageMeter.GetSessionDurationSeconds(sType) or 0

    if isSplitView then
        self:FillModeBars(self.ovrPriBars, self.ovrPriList, self.ovrPriHead, sp.primaryMode, seg, dur, sType, nil)
        self:FillModeBars(self.ovrSecBars, self.ovrSecList, self.ovrSecHead, sp.secondaryMode, seg, dur, sType, nil)
    else
        self:FillModeBars(self.ovrPriBars, self.ovrPriList, self.ovrPriHead, mode, seg, dur, sType, nil)
    end
end

function UI:RefreshTitle()
    if not self.frame or not self.frame:IsShown() then return end
    if not self.titleText then return end

    local segs = ns.Segments
    local segL = segs and segs:GetViewLabel() or L["无数据"]
    local dot = ""
    local dur = 0

    if ns.state.inCombat and ns.state.combatStartTime and ns.state.combatStartTime > 0 then
        local isViewingOverall = segs and segs:IsViewingOverall()
        if isViewingOverall then dur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or 0
        else dur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current) or 0 end
    else
        local seg = segs and segs:GetViewSegment()
        if seg and seg._keystoneTime and seg._keystoneTime > 0 then dur = seg._keystoneTime else dur = seg and (seg.duration or 0) or 0 end
    end

    local tStr = dur > 0 and ("|cffaaaaaa" .. ns:FormatTime(dur) .. "|r") or ""
    if self.titleTime then self.titleTime:SetText(tStr) end

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

    if h.dtFriendly then
        if mode == "damageTaken" then
            local isEnemy = (ns.state.damageTakenView == "enemy")
            h.dtFriendlyText:SetText(L["友方"])
            h.dtEnemyText:SetText(L["敌方"])
            if isEnemy then
                h.dtFriendlyText:SetTextColor(0.3, 0.5, 0.3)
                h.dtEnemyText:SetTextColor(1.0, 0.4, 0.4)
                mn = L["敌人承伤"]
            else
                h.dtFriendlyText:SetTextColor(0.3, 1.0, 0.3)
                h.dtEnemyText:SetTextColor(0.5, 0.3, 0.3)
            end
            h.dtFriendly:Show(); h.dtEnemy:Show()
        else
            h.dtFriendly:Hide(); h.dtEnemy:Hide()
        end
    end

    local ac = mode=="damage" and T.dmgC or mode=="healing" and T.healC or mode=="damageTaken" and T.takenC or T.accent
    h.label:SetText(string.format("|cff%02x%02x%02x%s|r", ac[1]*255, ac[2]*255, ac[3]*255, mn))

    if mode == "damageTaken" and h.dtFriendly then
        if not h._dtMaxLabelW then
            local savedText = h.label:GetText()
            h.label:SetWidth(0)
            local fmt = "|cff%02x%02x%02x%s|r"
            h.label:SetText(string.format(fmt, ac[1]*255, ac[2]*255, ac[3]*255, L[ns.MODE_NAMES["damageTaken"]]))
            local w1 = h.label:GetStringWidth()
            h.label:SetText(string.format(fmt, ac[1]*255, ac[2]*255, ac[3]*255, L["敌人承伤"]))
            local w2 = h.label:GetStringWidth()
            h._dtMaxLabelW = math.max(w1, w2) + 2
            h.label:SetText(savedText)
        end
        h.dtFriendly:ClearAllPoints()
        h.dtFriendly:SetPoint("LEFT", h, "LEFT", 6 + h._dtMaxLabelW + 4, 0)
        h.dtEnemy:ClearAllPoints()
        h.dtEnemy:SetPoint("LEFT", h.dtFriendly, "RIGHT", 2, 0)
    end

    local function SetFromSession(session)
        if session and session.totalAmount then
            if COUNT_MODES[mode] then h.info:SetFormattedText(L["团队总%s: %s次"], mn, AbbreviateNumbers(session.totalAmount))
            else h.info:SetFormattedText(L["团队总%s: %s"], mn, AbbreviateNumbers(session.totalAmount)) end
        else
            h.info:SetText("")
        end
    end

    if apiSessionID then
        local dmType = MODE_TO_DM[EffMode(mode)]
        if dmType then
            local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, apiSessionID, dmType)
            SetFromSession(ok and session or nil)
        else h.info:SetText("") end
    elseif apiSessionType then
        local dmType = MODE_TO_DM[EffMode(mode)]
        if dmType then SetFromSession(self:GetCachedSession(apiSessionType, dmType))
        else h.info:SetText("") end
    elseif seg then
        local total = 0
        if mode == "damageTaken" and ns.state.damageTakenView == "enemy" then
            for _, entry in ipairs(seg.enemyDamageTakenList or {}) do total = total + (entry.total or 0) end
        elseif mode == "deaths" and ns.DeathTracker then
            local dl = ns.DeathTracker:GetDeathLog(seg)
            total = dl and #dl or 0
        elseif COUNT_MODES[mode] then
            for _, p in pairs(seg.players or {}) do total = total + (p[mode] or 0) end
        else
            total = mode=="damage" and seg.totalDamage or mode=="healing" and seg.totalHealing or mode=="damageTaken" and seg.totalDamageTaken or 0
        end
        local valStr = COUNT_MODES[mode] and (ns:FormatNumber(total)..L["次"]) or ns:FormatNumber(total)
        h.info:SetText(string.format(L["团队总%s: %s"], mn, valStr))
    else
        h.info:SetText("")
    end
end

-- ============================================================
-- Tooltip
-- ============================================================
function UI:AnchorTooltipToWindow(bar)
    local f = self.frame
    if not f then GameTooltip:SetOwner(bar.frame, "ANCHOR_LEFT"); return end
    GameTooltip:SetOwner(bar.frame, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local scale = f:GetEffectiveScale()
    local fLeft = (f:GetLeft() or 0) * scale
    local fTop = (f:GetTop() or 0) * scale
    local screenH = GetScreenHeight() * UIParent:GetEffectiveScale()
    if fLeft > 280 then GameTooltip:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
    elseif fTop < screenH * 0.7 then GameTooltip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    else GameTooltip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4) end
end

function UI:ShowTooltip(bar, section)
    local d = bar._data
    if not d then return end
    self:AnchorTooltipToWindow(bar)

    local guid = bar._guid
    local seg = ns.Segments and ns.Segments:GetViewSegment()
    local specID, ilvl, score

    if d and d.isAPI then
        specID = d.specID; ilvl = d.ilvl or 0; score = d.score or 0
    elseif seg and seg.isActive then
        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
        specID = (d and d.specID) or cache.specID
        ilvl = (d and d.ilvl) or cache.ilvl or 0
        score = cache.score or 0
        if guid == ns.state.playerGUID then
            local specIdx = GetSpecialization()
            if specIdx then specID = GetSpecializationInfo(specIdx) end
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
    if specName == "" and d and d.specIconID and d.specIconID > 0 and ns.ICON_TO_SPECID then
        local sid = ns.ICON_TO_SPECID[d.specIconID]
        if sid then
            local _, name = GetSpecializationInfoByID(sid)
            if name then specName = name end
        end
    end

    local function AddPlayerInfoLines()
        if specName ~= "" or (ilvl and ilvl > 0) or (score and score > 0) then
            GameTooltip:AddLine(" ")
            if specName ~= "" then GameTooltip:AddDoubleLine(L["专精"], specName, 0.7,0.7,0.7, 1,1,1) end
            if ilvl and ilvl > 0 then GameTooltip:AddDoubleLine(L["平均装等"], tostring(ilvl), 0.7,0.7,0.7, 1,0.85,0) end
            if score and score > 0 then
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if color then GameTooltip:AddDoubleLine(L["大秘境评分"], color:WrapTextInColorCode(tostring(score)), 0.7,0.7,0.7, 1,1,1)
                else GameTooltip:AddDoubleLine(L["大秘境评分"], tostring(score), 0.7,0.7,0.7, 1,0.5,0) end
            end
        end
    end

    if bar._isDeath then
        GameTooltip:AddLine(ns:GetClassHex(d.playerClass)..ns:DisplayName(d.playerName)..L["|r [死亡]"])
        AddPlayerInfoLines()
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["致命技能"], d.killingAbility or "?", 0.7,0.7,0.7, 1,0.3,0.3)
        GameTooltip:AddDoubleLine(L["击杀者"], ns:DisplayName(d.killerName) or "?", 0.7,0.7,0.7, 1,1,1)
        if d._incomplete then
            GameTooltip:AddLine(L["|cffaaaaaa死亡回放暂未释放，脱战或稍后会自动补齐|r"])
        else
            GameTooltip:AddDoubleLine(L["死前受伤"], ns:FormatNumber(d.totalDamageTaken or 0), 0.7,0.7,0.7, 1,0.5,0.5)
            GameTooltip:AddDoubleLine(L["死前受治"], ns:FormatNumber(d.totalHealingReceived or 0), 0.7,0.7,0.7, 0.5,1,0.5)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cff00ccff点击查看完整死亡日志|r"], 0.4,0.4,0.4)
        GameTooltip:Show()
        return
    end

    if d.isAPI then
        GameTooltip:AddLine(ns:GetClassHex(bar._classStr)..ns:DisplayName(bar._nameStr or "?").."|r")
        AddPlayerInfoLines()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cffaaaaaa— API 实时数据 —|r"])
        if COUNT_MODES[bar._mode] then
            GameTooltip:AddDoubleLine((L[ns.MODE_NAMES[bar._mode] or bar._mode])..L["次"], AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
        elseif ns.db.display.showPerSecond then
            GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
            GameTooltip:AddDoubleLine(L["每秒"], AbbreviateNumbers(d.amountPerSecond), 0.7,0.7,0.7, 1,0.85,0)
        else
            GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4)
        GameTooltip:Show()
        return
    end

    local mode = bar._mode or ns.db.display.mode
    local dur2 = ns.Analysis and ns.Analysis:GetSegmentDuration(seg) or 0
    local mn = L[ns.MODE_NAMES[mode] or mode]
    GameTooltip:AddLine(ns:GetClassHex(d.class)..ns:DisplayName(d.name or "?").."|r")
    AddPlayerInfoLines()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cffaaaaaa— 本段 —|r"])
    GameTooltip:AddDoubleLine(mn, ns:FormatNumber(d.value), 0.7,0.7,0.7, 1,1,1)
    if dur2 > 0 and ns.MODE_UNITS[mode] then GameTooltip:AddDoubleLine(ns.MODE_UNITS[mode], string.format("%.1f", d.value/dur2), 0.7,0.7,0.7, 1,0.85,0) end
    GameTooltip:AddDoubleLine(L["占比"], string.format("%.1f%%", d.percent or 0), 0.7,0.7,0.7, 1,1,1)
    if d.petDamage and d.petDamage > 0 and mode == "damage" then GameTooltip:AddDoubleLine(L["含宠物"], ns:FormatNumber(d.petDamage), 0.5,0.5,0.5, 0.7,0.7,0.7) end

    GameTooltip:AddLine(" ")
    if d.deaths and d.deaths > 0 then GameTooltip:AddDoubleLine(L["死亡"], d.deaths, 0.7,0.7,0.7, 1,0.3,0.3) end
    if d.interrupts and d.interrupts > 0 then GameTooltip:AddDoubleLine(L["打断"], d.interrupts, 0.7,0.7,0.7, 0.3,1,0.3) end
    if d.dispels and d.dispels > 0 then GameTooltip:AddDoubleLine(L["驱散"], d.dispels, 0.7,0.7,0.7, 0.3,0.8,1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4)
    GameTooltip:Show()
end
