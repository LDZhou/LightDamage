--[[
    Light Damage - UIBars.lua
    数据条:MakeBar, FillBars, FillBarsFromAPI, FillDeathBars, MakeValueStr

    API-first:
    - FillDeathBars 新增 sessionType/sessionID 参数
    - 死亡条优先从 C_DamageMeter Deaths + C_DeathRecap 生成具体死亡信息
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local MAX_BARS = UI.MAX_BARS
local COUNT_MODES = UI.COUNT_MODES
local MODE_TO_DM = UI.MODE_TO_DM
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local DEFAULT_FONT_COLOR = {1, 1, 1, 0.93}
local NEUTRAL_CLASS_COLOR = {0.5, 0.5, 0.5}
-- Hostile red: vivid enough to read as an enemy at a glance, with a slight
-- deep-red bias so it remains distinct from alerts and healing/pastel bars.
local ENEMY_BAR_COLOR = {0.78, 0.08, 0.10}

local function _isSecretValue(value)
    local gateway=ns.DamageMeterGateway
    if gateway then return not gateway:IsAccessible(value) end
    return issecretvalue and issecretvalue(value) or false
end

local function _isReadableTable(value)
    if type(value) ~= "table" then return false end
    local gateway = ns.DamageMeterGateway
    return not gateway or gateway:IsTableAccessible(value)
end

local function _clearOpaqueText(fs)
    if not fs then return end
    if fs.ClearText then fs:ClearText() else fs:SetText("") end
end

local function _getOpaqueAbbreviatedNumber(value)
    local formatter=ns.AbbrevProtectedNumber
    if formatter then
        local ok,text=pcall(formatter,value)
        if ok then return text end
    end
    return value
end

local function _safeSetBarValue(fs, total, ps, showPS, isCount, suffix)
    if isCount then
        fs:SetFormattedText("%s" .. suffix, ns.AbbrevNumber(total))
    elseif showPS then
        fs:SetFormattedText("%s (%s)", ns.AbbrevNumber(total), ns.AbbrevNumber(ps))
    else
        fs:SetText(ns.AbbrevNumber(total))
    end
end

local function _safeSetStatusBar(sb, maxV, val)
    if INTERP then
        sb:SetMinMaxValues(0, maxV, INTERP)
        sb:SetValue(val, INTERP)
    else
        sb:SetMinMaxValues(0, maxV)
        sb:SetValue(val)
    end
end

function UI:ReleaseBarData(bar)
    if not bar then return end
    if bar._apiData then wipe(bar._apiData) end
    bar._data=nil; bar._guid=nil; bar._nameStr=nil; bar._classStr=nil
    bar._mode=nil; bar._isDeath=false; bar._detailSegment=nil
    bar._detailRange=nil; bar._detailDisplaySource=nil
end

function UI:PositionBarRow(bar, listObj, index, height, gap)
    if bar._rowParent == listObj.child and bar._rowIndex == index
        and bar._rowHeight == height and bar._rowGap == gap then return end
    bar._rowParent=listObj.child; bar._rowIndex=index
    bar._rowHeight=height; bar._rowGap=gap
    bar.frame:SetHeight(height); bar.frame:ClearAllPoints()
    bar.frame:SetPoint("TOPLEFT",listObj.child,"TOPLEFT",0,-((index-1)*(height+gap)))
    bar.frame:SetPoint("TOPRIGHT",listObj.child,"TOPRIGHT",0,-((index-1)*(height+gap)))
end

function UI:MakeBar(parent, section, index)
    local bar = {}

    bar.frame = CreateFrame("Button", nil, parent)
    bar.frame:SetHeight(18)
    bar.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.frame:Hide()

    bar.bg = bar.frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.1, 0.1, 0.12, 0)

    bar.fill = bar.frame:CreateTexture(nil, "BORDER", nil, 0)
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.fill:SetWidth(1)

    bar.statusbar = CreateFrame("StatusBar", nil, bar.frame)
    bar.statusbar:SetPoint("TOPLEFT")
    bar.statusbar:SetPoint("BOTTOMRIGHT")
    bar.statusbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.statusbar:SetMinMaxValues(0, 1)
    bar.statusbar:SetFrameLevel(bar.frame:GetFrameLevel() + 1)
    bar.statusbar:Hide()

    local sbTex = bar.statusbar:GetStatusBarTexture()
    if sbTex then
        sbTex:SetDrawLayer("BORDER", 1)
    end

    bar.textFrame = CreateFrame("Frame", nil, bar.frame)
    bar.textFrame:SetAllPoints()
    bar.textFrame:SetFrameLevel(bar.frame:GetFrameLevel() + 5)

    bar.specIcon = bar.textFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    bar.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.specIcon:Hide()

    bar.rank = self:FS(bar.textFrame, 9, "OUTLINE")
    bar.rank:SetPoint("LEFT", 3, 0)
    bar.rank:SetJustifyH("RIGHT")
    bar.rank:SetTextColor(1.0, 1.0, 1.0, 0.9)

    bar.name = self:FS(bar.textFrame, 10, "OUTLINE")
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    if bar.name.SetMaxLines then bar.name:SetMaxLines(1) end

    -- API protected names use a dedicated FontString so an opaque value is
    -- never recycled through the normal string-manipulation path.
    bar.rawName = self:FS(bar.textFrame, 10, "OUTLINE")
    bar.rawName:SetJustifyH("LEFT"); bar.rawName:SetWordWrap(false); bar.rawName:Hide()
    if bar.rawName.SetMaxLines then bar.rawName:SetMaxLines(1) end

    bar.value = self:FS(bar.textFrame, 9, "OUTLINE")
    bar.value:SetJustifyH("RIGHT")
    bar.value:SetWordWrap(false)
    if bar.value.SetMaxLines then bar.value:SetMaxLines(1) end

    -- Protected number geometry is isolated in fixed full-row parents. The
    -- client formats total/rate into one Text-aspect FontString, producing the
    -- exact same glyph spacing as accessible "total (rate)" text without Lua
    -- measuring, comparing, or doing arithmetic on protected values.
    bar.rawBothLayer=CreateFrame("Frame",nil,bar.textFrame); bar.rawBothLayer:SetAllPoints(bar.textFrame); bar.rawBothLayer:Hide()
    bar.rawValue=self:FS(bar.rawBothLayer,9,"OUTLINE"); bar.rawValue:SetJustifyH("RIGHT"); bar.rawValue:SetWordWrap(false); if bar.rawValue.SetMaxLines then bar.rawValue:SetMaxLines(1) end
    bar.rawValue:SetPoint("RIGHT",bar.rawBothLayer,"RIGHT",-2,0)

    bar.rawTotalLayer=CreateFrame("Frame",nil,bar.textFrame); bar.rawTotalLayer:SetAllPoints(bar.textFrame); bar.rawTotalLayer:Hide()
    bar.rawTotalValue=self:FS(bar.rawTotalLayer,9,"OUTLINE"); bar.rawTotalValue:SetJustifyH("RIGHT"); bar.rawTotalValue:SetWordWrap(false); if bar.rawTotalValue.SetMaxLines then bar.rawTotalValue:SetMaxLines(1) end
    bar.rawTotalValue:SetPoint("RIGHT",bar.rawTotalLayer,"RIGHT",-2,0)

    bar.rawCountLayer=CreateFrame("Frame",nil,bar.textFrame); bar.rawCountLayer:SetAllPoints(bar.textFrame); bar.rawCountLayer:Hide()
    bar.rawCountValue=self:FS(bar.rawCountLayer,9,"OUTLINE"); bar.rawCountValue:SetJustifyH("RIGHT"); bar.rawCountValue:SetWordWrap(false); if bar.rawCountValue.SetMaxLines then bar.rawCountValue:SetMaxLines(1) end
    bar.rawCountValue:SetPoint("RIGHT",bar.rawCountLayer,"RIGHT",-2,0)

    bar.deathTime = self:FS(bar.textFrame, 9, "OUTLINE")
    bar.deathPlayer = self:FS(bar.textFrame, 10, "OUTLINE")
    bar.deathReason = self:FS(bar.textFrame, 9, "OUTLINE")
    bar.deathCount = self:FS(bar.textFrame, 9, "OUTLINE")
    for _,fs in ipairs({bar.deathTime,bar.deathPlayer,bar.deathReason,bar.deathCount}) do fs:SetWordWrap(false); if fs.SetMaxLines then fs:SetMaxLines(1) end; fs:Hide() end
    bar.deathTime:SetJustifyH("LEFT"); bar.deathPlayer:SetJustifyH("LEFT"); bar.deathReason:SetJustifyH("LEFT"); bar.deathCount:SetJustifyH("RIGHT")

    bar.hl = bar.frame:CreateTexture(nil, "HIGHLIGHT")
    bar.hl:SetAllPoints()
    bar.hl:SetColorTexture(1, 1, 1, 0.05)

    bar.section = section
    bar.index = index

    bar.frame:SetScript("OnClick", function(self2, btn)
        if btn == "RightButton" then return end
        if not ns.DetailView then return end

        if bar._isDeath then
            ns.DetailView:ShowDeathDetail(bar._data)
            return
        end

        if bar._data and bar._data._isEnemy and bar._data._sources then
            ns.DetailView:ShowEnemyDamageTakenDetail(bar._data.name, bar._data._sources, bar._data.value)
            return
        end

        if bar._data and bar._data.isAPI and bar._mode == "enemyDamageTaken" then
            ns.DetailView:ShowEnemyDamageTakenFromAPI(
                bar._data.sourceCreatureID,
                bar._nameStr,
                bar._data.totalAmount,
                bar._data.sessionType,
                bar._data.sessionID
            )
            return
        end

        if bar._data and bar._data.isAPI then
            local resolvedGUID = bar._data.sourceGUID
            local resolvedCreatureID = bar._data.sourceCreatureID
            local gateway = ns.DamageMeterGateway
            local isLocalPlayer = bar._data.isLocalPlayer == true
            if isLocalPlayer then
                -- Player sources are keyed only by the player's accessible
                -- GUID. Passing the row's creature selector here can make the
                -- otherwise available local combatSpells come back protected.
                resolvedGUID = UnitGUID("player")
                resolvedCreatureID = nil
            elseif gateway and not gateway:IsAccessible(resolvedGUID) then
                resolvedGUID = nil
            end
            ns.DetailView:ShowSpellBreakdownFromAPI(
                resolvedGUID,
                resolvedCreatureID,
                bar._nameStr,
                bar._classStr,
                bar._mode,
                bar._data.sessionType,
                bar._data.sessionID,
                isLocalPlayer
            )
            return
        end

        local gateway = ns.DamageMeterGateway
        if gateway and not gateway:IsAccessible(bar._guid) then return end
        if bar._guid == nil then return end
        local seg = bar._detailSegment
        ns.DetailView:ShowSpellBreakdown(bar._guid, bar._nameStr, bar._classStr, bar._mode, seg)
    end)
    bar.frame:SetScript("OnEnter", function() UI:ShowTooltip(bar, bar.section) end)
    bar.frame:SetScript("OnLeave", function() if ns.PrivateTooltip then ns.PrivateTooltip:Hide() else GameTooltip:Hide() end end)
    return bar
end

function UI:ApplyBarValueFonts(bar,font,size,outline,shadow)
    self:ApplyFont(bar.value,font,size,outline,shadow)
    self:ApplyFont(bar.rawValue,font,size,outline,shadow)
    self:ApplyFont(bar.rawTotalValue,font,size,outline,shadow)
    self:ApplyFont(bar.rawCountValue,font,size,outline,shadow)
end

function UI:ApplyBarNameFonts(bar,font,size,outline,shadow)
    self:ApplyFont(bar.name,font,size,outline,shadow)
    self:ApplyFont(bar.rawName,font,size,outline,shadow)
end

function UI:SetBarValueTextColor(bar,r,g,b,a)
    bar.value:SetTextColor(r,g,b,a); bar.rawValue:SetTextColor(r,g,b,a)
    bar.rawTotalValue:SetTextColor(r,g,b,a); bar.rawCountValue:SetTextColor(r,g,b,a)
end

function UI:ResetBarValueDisplay(bar)
    if bar._showingRawValue then
        _clearOpaqueText(bar.rawValue); _clearOpaqueText(bar.rawTotalValue); _clearOpaqueText(bar.rawCountValue)
    end
    bar._showingRawValue=nil; bar._showingRawRate=nil; bar._showingRawSuffix=nil
    bar.rawBothLayer:Hide(); bar.rawTotalLayer:Hide(); bar.rawCountLayer:Hide(); bar.value:Show()
end

-- Returns independent secrecy states for total and rate. If either number is
-- protected, a dedicated Text-aspect FontString formats the complete display;
-- only accessible values may enter the addon's Lua formatting path.
function UI:SetAPIBarValue(bar,total,perSecond,showPerSecond,isCount,suffix)
    local totalSecret=_isSecretValue(total)
    local showRate=showPerSecond and not isCount
    local rateSecret=showRate and _isSecretValue(perSecond) or false

    if not totalSecret and not rateSecret then
        self:ResetBarValueDisplay(bar)
        pcall(_safeSetBarValue,bar.value,total,perSecond,showPerSecond,isCount,suffix)
        return false,false
    end

    self:ResetBarValueDisplay(bar)
    bar.value:Hide(); bar._showingRawValue=true
    local totalDisplay
    if totalSecret then totalDisplay=_getOpaqueAbbreviatedNumber(total)
    else
        local ok,text=pcall(ns.AbbrevNumber,total)
        totalDisplay=ok and text or total
    end
    bar.rawTotalValue:SetText(totalDisplay)

    if showRate then
        bar._showingRawRate=true
        local rateDisplay
        if rateSecret then rateDisplay=_getOpaqueAbbreviatedNumber(perSecond)
        else
            local ok,text=pcall(ns.AbbrevNumber,perSecond)
            rateDisplay=ok and text or perSecond
        end
        bar.rawValue:SetFormattedText("%s (%s)",totalDisplay,rateDisplay)
    elseif isCount then
        bar.rawCountValue:SetFormattedText("%s%s",totalDisplay,suffix or "")
    end
    bar._showingRawSuffix=isCount and true or nil
    return totalSecret,rateSecret
end

function UI:SetBarDisplayName(bar,rawName)
    local display=ns:DisplayName(rawName)
    local protected=issecretvalue and issecretvalue(display)
    if protected then
        bar.name:Hide(); bar.rawName:Show(); bar.rawName:SetText(display)
    else
        bar.rawName:Hide(); bar.name:Show(); bar.name:SetText(display)
    end
end

function UI:SetDeathColumnLayout(bar,active,width)
    if not active then
        if bar._deathLayoutActive ~= true then return end
        bar._deathLayoutActive=false
        bar.deathTime:Hide(); bar.deathPlayer:Hide(); bar.deathReason:Hide(); bar.deathCount:Hide()
        bar.rank:Show(); bar.name:Show(); bar.rawName:Hide(); self:ResetBarValueDisplay(bar)
        return
    end
    bar._deathLayoutActive=true
    -- A normal value row may have reclaimed the icon area while extremely
    -- narrow.  Death rows always restore the configured text offset before
    -- laying out their protected time/count columns, so a later icon cannot
    -- overlap those numbers.  Invalidate the normal anchor cache for reuse.
    bar.textFrame:ClearAllPoints()
    if ns.db.display.showSpecIcon then
        local offset = (ns.db.display.barHeight or 18) + 4
        bar.textFrame:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", offset, 0)
        bar.textFrame:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, 0)
    else
        bar.textFrame:SetAllPoints(bar.frame)
    end
    bar._anchorValid = nil
    bar.rank:Hide(); bar.name:Hide(); bar.rawName:Hide(); self:ResetBarValueDisplay(bar); bar.value:Hide()
    local available=math.max(1,tonumber(width) or bar.textFrame:GetWidth() or 1)
    local timeW=math.min(46,math.max(30,available*.16))
    local playerW=math.min(150,math.max(42,available*.34))
    bar.deathTime:ClearAllPoints(); bar.deathTime:SetPoint("LEFT",bar.textFrame,"LEFT",3,0); bar.deathTime:SetWidth(timeW-4)
    bar.deathPlayer:ClearAllPoints(); bar.deathPlayer:SetPoint("LEFT",bar.textFrame,"LEFT",timeW+2,0); bar.deathPlayer:SetWidth(playerW-4)
    bar.deathCount:ClearAllPoints(); bar.deathCount:SetPoint("RIGHT",bar.textFrame,"RIGHT",-3,0); bar.deathCount:SetWidth(1)
    bar.deathReason:ClearAllPoints(); bar.deathReason:SetPoint("LEFT",bar.textFrame,"LEFT",timeW+playerW+2,0); bar.deathReason:SetPoint("RIGHT",bar.deathCount,"LEFT",-4,0)
    bar.deathTime:Show(); bar.deathPlayer:Show(); bar.deathReason:Show(); bar.deathCount:Show()
end

function UI:PrioritizeDeathNumbers(bar, width)
    local available = math.max(1, tonumber(width) or bar.textFrame:GetWidth() or 1)
    local function TextWidth(fs)
        local getter = fs and (fs.GetUnboundedStringWidth or fs.GetStringWidth)
        if not getter then return 0 end
        local ok, value = pcall(getter, fs)
        return ok and type(value) == "number" and value or 0
    end
    local timeW = math.min(available, math.ceil(TextWidth(bar.deathTime) + 6))
    local countW = math.min(available, math.ceil(TextWidth(bar.deathCount) + 6))
    local playerW = math.min(150, math.max(42, available * .34))
    if timeW + playerW + countW + 12 > available then
        playerW = math.max(1, available - timeW - countW - 12)
    end
    bar.deathTime:SetWidth(math.max(1, timeW - 4))
    bar.deathPlayer:ClearAllPoints(); bar.deathPlayer:SetPoint("LEFT",bar.textFrame,"LEFT",timeW+2,0); bar.deathPlayer:SetWidth(playerW)
    bar.deathCount:SetWidth(math.max(1, countW))
    bar.deathReason:ClearAllPoints(); bar.deathReason:SetPoint("LEFT",bar.deathPlayer,"RIGHT",4,0); bar.deathReason:SetPoint("RIGHT",bar.deathCount,"LEFT",-4,0)
end

function UI:MakeValueStr(value, dur, mode, perSec, percent)
    if COUNT_MODES[mode] then return ns:FormatNumber(value) .. L.COUNT_SUFFIX end
    local baseStr
    if ns.db.display.showPerSecond then
        local ps = type(perSec) == "number" and perSec or nil
        if ps then baseStr = string.format("%s (%s)", ns:FormatNumber(value), ns:FormatNumber(ps))
        else baseStr = ns:FormatNumber(value) end
    else baseStr = ns:FormatNumber(value) end
    if ns.db.display.showPercent and percent and percent > 0 then return string.format("%s  %.1f%%", baseStr, percent)
    else return baseStr end
end

function UI:FillBars(bars, listObj, data, dur, mode)
    local count = math.min(#data, MAX_BARS)
    if listObj and listObj._cell and self.EnsureCellBars then
        self:EnsureCellBars(listObj._cell, count)
    end
    self:UpdateScrollState(listObj, count)
    local maxV = data[1] and data[1].value or 0
    local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    local nameFont, nameSz, nameOut, nameShad = self:GetDisplayFontConfig("name")
    local tr, tg, tb, ta = self:GetDisplayColor("fontColor", DEFAULT_FONT_COLOR)
    local fixedNameColor = (ns.db.display.nameColorMode == "custom") and ns.db.display.nameFontColor or nil

    for i, bar in ipairs(bars) do
        if i <= count then
            self:PositionBarRow(bar,listObj,i,bh,gap)
            self:AnchorBarTexts(bar)
            self:SetDeathColumnLayout(bar,false)
            self:ResetBarValueDisplay(bar)
            self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyBarNameFonts(bar,nameFont,nameSz,nameOut,nameShad); self:ApplyBarValueFonts(bar,font,fSz-1,fOut,fShad)
            local d = data[i]; bar._data = d; bar._mode = mode; bar._isDeath = false; bar._guid = d.guid; bar._nameStr = d.name; bar._classStr = d.class
            bar.fill:Hide(); bar.statusbar:Show()
            local cc = mode == "enemyDamageTaken" and ENEMY_BAR_COLOR
                or ns:GetClassColor(d.class) or {0.5, 0.5, 0.5}
            if INTERP then
                bar.statusbar:SetMinMaxValues(0, maxV > 0 and maxV or 1, INTERP)
                bar.statusbar:SetValue(d.value or 0, INTERP)
            else
                bar.statusbar:SetMinMaxValues(0, maxV > 0 and maxV or 1)
                bar.statusbar:SetValue(d.value or 0)
            end
            bar.statusbar:SetStatusBarTexture(texPath)
            bar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha)
            bar.rank:SetText(ns.db.display.showRank and (i..".") or "")
            bar.rank:SetTextColor(tr, tg, tb, ta)
            self:SetBarDisplayName(bar,d.name)
            if fixedNameColor then bar.name:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1); bar.rawName:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1)
            else bar.name:SetTextColor(cc[1], cc[2], cc[3]); bar.rawName:SetTextColor(cc[1], cc[2], cc[3]) end
            if bar.specIcon then
                local specID = d and d.specID
                if d.guid == ns.state.playerGUID then
                    local snapshot = self:GetLocalPlayerSnapshot()
                    specID = snapshot and snapshot.specID or specID
                    if d then d.specID = specID end
                end
                local icon = ns:GetSpecIcon(specID, bar._classStr, d.specIconID)
                if d._isEnemy then icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" end
                if ns.db.display.showSpecIcon and icon then bar.specIcon:SetTexture(icon); bar.specIcon:Show() else bar.specIcon:Hide() end
            end
            bar.value:SetText(self:MakeValueStr(d.value, dur, mode, d.perSec, d.percent))
            bar.value:SetTextColor(tr, tg, tb, ta)
            self:PrioritizeBarValue(bar, false)
            bar.frame:Show()
        else
            if bar.specIcon then bar.specIcon:Hide() end
            bar.frame:Hide()
            self:ReleaseBarData(bar)
        end
    end

    local listKey = listObj._poolKey
    if listObj == self.priList then listKey = "pri" elseif listObj == self.secList then listKey = "sec"
    elseif listObj == self.ovrPriList then listKey = "ovrPri" elseif listObj == self.ovrSecList then listKey = "ovrSec" end
    if listKey then self:CheckPinnedSelfForBars(listKey, listObj, data, dur, mode, count) end
end

function UI:FillBarsFromAPI(bars, listObj, mode, sessionType, sessionID, rawSession)
    local dmType = MODE_TO_DM[mode]
    if not dmType then self:UpdateScrollState(listObj, 0); for _, bar in ipairs(bars) do bar.frame:Hide(); self:ReleaseBarData(bar) end; return end

    local session = rawSession or self:GetRefreshRawSession(
        sessionType or (not sessionID and Enum.DamageMeterSessionType.Current or nil), sessionID, dmType)

    if not _isReadableTable(session) then self:UpdateScrollState(listObj, 0); for _, bar in ipairs(bars) do bar.frame:Hide(); self:ReleaseBarData(bar) end; return end
    local okSources, sources = pcall(function() return session.combatSources end)
    if not okSources or not _isReadableTable(sources) then self:UpdateScrollState(listObj, 0); for _, bar in ipairs(bars) do bar.frame:Hide(); self:ReleaseBarData(bar) end; return end
    local maxAmt
    pcall(function() maxAmt = session.maxAmount end)
    local count = math.min(#sources, MAX_BARS)
    if listObj and listObj._cell and self.EnsureCellBars then
        self:EnsureCellBars(listObj._cell, count)
    end
    self:UpdateScrollState(listObj, count)
    local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    local nameFont, nameSz, nameOut, nameShad = self:GetDisplayFontConfig("name")
    local tr, tg, tb, ta = self:GetDisplayColor("fontColor", DEFAULT_FONT_COLOR)
    local fixedNameColor = (ns.db.display.nameColorMode == "custom") and ns.db.display.nameFontColor or nil
    local gateway=ns.DamageMeterGateway
    local maxSecret=gateway and not gateway:IsAccessible(maxAmt)
        or (not gateway and issecretvalue and issecretvalue(maxAmt)) or false
    local maxValue
    if maxSecret then maxValue=maxAmt else maxValue=maxAmt or 1 end

    for i, bar in ipairs(bars) do
        if i <= count then
            local src = sources[i]
            if not _isReadableTable(src) then
                if bar.specIcon then bar.specIcon:Hide() end
                bar.frame:Hide()
                self:ReleaseBarData(bar)
            else
            self:ObserveDamageMeterSourceOnce(src)
            self:PositionBarRow(bar,listObj,i,bh,gap)
            self:AnchorBarTexts(bar); self:SetDeathColumnLayout(bar,false); self:ResetBarValueDisplay(bar); self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyBarNameFonts(bar,nameFont,nameSz,nameOut,nameShad); self:ApplyBarValueFonts(bar,font,fSz-1,fOut,fShad)
            bar.fill:Hide(); bar.statusbar:Show()
            local rawClass = src.classFilename
            local cls = (gateway and gateway:IsAccessible(rawClass)
                and type(rawClass) == "string" and rawClass ~= "") and rawClass or nil
            local rawSpecIconID = src.specIconID
            local specIconID = (gateway and gateway:IsAccessible(rawSpecIconID)
                and type(rawSpecIconID) == "number") and rawSpecIconID or nil
            local cc = mode == "enemyDamageTaken" and ENEMY_BAR_COLOR
                or (cls and ns.CLASS_COLORS[cls]) or NEUTRAL_CLASS_COLOR

            bar.statusbar:SetStatusBarTexture(texPath); bar.fill:SetTexture(texPath)
            bar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha)
            local tex = bar.statusbar:GetStatusBarTexture(); if tex then tex:SetVertexColor(cc[1], cc[2], cc[3], alpha) end
            bar.fill:SetVertexColor(cc[1], cc[2], cc[3], alpha)

            pcall(_safeSetStatusBar,bar.statusbar,maxValue,src.totalAmount)

            bar.rank:SetText(ns.db.display.showRank and (i .. ".") or "")
            bar.rank:SetTextColor(tr, tg, tb, ta)

            local nameRaw = src.name
            local nameStr = ""
            local isSecret = gateway and not gateway:IsAccessible(nameRaw)
                or (not gateway and issecretvalue and issecretvalue(nameRaw)) or false

            if isSecret then
                nameStr = nameRaw
            elseif nameRaw then
                local ok, str = pcall(tostring, nameRaw)
                if ok and str then nameStr = str end
            end
            self:SetBarDisplayName(bar,nameStr); bar._nameStr = nameStr

            if fixedNameColor then bar.name:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1); bar.rawName:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1)
            else bar.name:SetTextColor(cc[1], cc[2], cc[3]); bar.rawName:SetTextColor(cc[1], cc[2], cc[3]) end

            local rawRate = src.amountPerSecond
            local rateAvailable = _isSecretValue(rawRate) or type(rawRate) == "number"
            local amountSecret,rateSecret=self:SetAPIBarValue(bar,src.totalAmount,rawRate,
                ns.db.display.showPerSecond and rateAvailable,COUNT_MODES[mode],L.COUNT_SUFFIX)
            self:SetBarValueTextColor(bar,tr,tg,tb,ta)

            if not bar._apiData then bar._apiData = {} end
            bar._apiData.isAPI = true; bar._apiData.sourceGUID = src.sourceGUID; bar._apiData.sourceCreatureID = src.sourceCreatureID
            bar._apiData.isLocalPlayer = src.isLocalPlayer; bar._apiData.totalAmount = src.totalAmount; bar._apiData.amountPerSecond = src.amountPerSecond
            bar._apiData.sessionType = sessionType
            bar._apiData.sessionID = sessionID
            bar._apiData.isSecretAmount=amountSecret
            bar._apiData.isSecretRate=rateSecret
            bar._data = bar._apiData; bar._mode = mode; bar._isDeath = false
            local guid = src.sourceGUID; bar._guid = guid; bar._classStr = cls
            local isSecretGuid = gateway and not gateway:IsAccessible(guid)
                or (not gateway and issecretvalue and issecretvalue(guid)) or false
            local specID, ilvl, score = nil, 0, 0
            local localPlayer = (not gateway or gateway:IsAccessible(src.isLocalPlayer))
                and src.isLocalPlayer == true
            if localPlayer then
                local snapshot = self:GetLocalPlayerSnapshot()
                specID = snapshot and snapshot.specID
                ilvl = snapshot and snapshot.ilvl or 0
                score = snapshot and snapshot.score or 0
            elseif not isSecretGuid then
                local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                specID = cache.specID; ilvl = cache.ilvl or 0; score = cache.score or 0
            end
            bar._apiData.isLocalPlayer = localPlayer
            bar._apiData.specID = specID; bar._apiData.ilvl = ilvl; bar._apiData.score = score
            bar._apiData.specIconID = specIconID

            if bar.specIcon then
                local icon = ns:GetSpecIcon(specID, cls, specIconID)
                if bar._mode == "enemyDamageTaken" then icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" end
                if ns.db.display.showSpecIcon and icon then bar.specIcon:SetTexture(icon); bar.specIcon:Show() else bar.specIcon:Hide() end
            end
            self:PrioritizeBarValue(bar, amountSecret or rateSecret)
            bar.frame:Show()
            end
        else
            if bars[i].specIcon then bars[i].specIcon:Hide() end
            bar.statusbar:Hide(); bar.fill:Show(); bar.frame:Hide()
            self:ReleaseBarData(bar)
        end
    end

    local listKey = listObj._poolKey
    if listObj == self.priList then listKey = "pri" elseif listObj == self.secList then listKey = "sec"
    elseif listObj == self.ovrPriList then listKey = "ovrPri" elseif listObj == self.ovrSecList then listKey = "ovrSec" end
    if listKey then self:CheckPinnedSelfForAPI(listKey, listObj, sources, mode, maxAmt, sessionType, sessionID) end
end

function UI:FillDeathBars(seg, bars, listObj, sessionType, sessionID, rawSession)
    bars = bars or self.priBars
    listObj = listObj or self.priList

    if self._pinnedSelf then
        local listKey = listObj._poolKey
        if listObj == self.priList then listKey = "pri"
        elseif listObj == self.secList then listKey = "sec"
        elseif listObj == self.ovrPriList then listKey = "ovrPri"
        elseif listObj == self.ovrSecList then listKey = "ovrSec" end
        if listKey and self._pinnedSelf[listKey] then self._pinnedSelf[listKey].frame:Hide() end
    end

    local dl
    if ns.DeathTracker then
        if (sessionType or sessionID) and _isReadableTable(rawSession) then
            dl = ns.DeathTracker:GetDeathLogFromAPI(sessionType, sessionID, seg)
        else
            dl = ns.DeathTracker:GetDeathLog(seg)
        end
    else
        dl = {}
    end

    local selfDeaths, otherDeaths = {}, {}
    for _, d in ipairs(dl or {}) do
        if d.isSelf then table.insert(selfDeaths, d) else table.insert(otherDeaths, d) end
    end

    local items = {}
    local function DeathCount(list)
        local total, hasOfficialCount = 0, false
        for _, death in ipairs(list) do
            local n = death._deathCount
            if type(n) == "number" then
                total = total + math.floor(n)
                hasOfficialCount = true
            end
        end
        return hasOfficialCount and total or nil
    end
    if #selfDeaths > 0 then
        table.insert(items, {isSeparator=true, label=L.COLORED_OWN_DEATH, count=DeathCount(selfDeaths)})
        for _, d in ipairs(selfDeaths) do table.insert(items, {isSeparator=false, d=d}) end
    end
    if #otherDeaths > 0 then
        table.insert(items, {isSeparator=true, label=L.COLORED_ALLY_DEATH, count=DeathCount(otherDeaths)})
        for _, d in ipairs(otherDeaths) do table.insert(items, {isSeparator=false, d=d}) end
    end

    local count = math.max(1, math.min(#items, MAX_BARS))
    if listObj and listObj._cell and self.EnsureCellBars then
        self:EnsureCellBars(listObj._cell, count)
    end
    self:UpdateScrollState(listObj, count)
    local cw = listObj.child:GetWidth()
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    local nameFont, nameSz, nameOut, nameShad = self:GetDisplayFontConfig("name")
    local tr, tg, tb, ta = self:GetDisplayColor("fontColor", {1, 1, 1, 0.93})
    local fixedNameColor = (ns.db.display.nameColorMode == "custom") and ns.db.display.nameFontColor or nil

    if #items == 0 then
        for _, bar in ipairs(bars) do bar.frame:Hide(); self:ReleaseBarData(bar) end
        local bar = bars[1]; if not bar then return end
        self:PositionBarRow(bar,listObj,1,bh,gap)
        self:AnchorBarTexts(bar)
        self:SetDeathColumnLayout(bar,false)
        self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyBarNameFonts(bar,nameFont,nameSz,nameOut,nameShad); self:ApplyBarValueFonts(bar,font,fSz-1,fOut,fShad)
        bar._data = nil; bar._isDeath = false; bar._guid = nil
        bar.statusbar:Hide(); bar.fill:Show(); bar.fill:SetWidth(1); bar.fill:SetVertexColor(0,0,0,0)
        bar.rank:SetText("")
        bar.name:SetText(L.COLORED_NO_DEATHS_IN_SEGMENT)
        bar.name:SetTextColor(tr, tg, tb, ta)
        bar.value:SetText("")
        if bar.specIcon then bar.specIcon:Hide() end
        self:PrioritizeBarValue(bar, false)
        bar.frame:Show()
        return
    end

    for i = 1, #bars do
        local bar = bars[i]
        if i <= count then
            local item = items[i]
            self:PositionBarRow(bar,listObj,i,bh,gap)
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyBarNameFonts(bar,nameFont,nameSz,nameOut,nameShad); self:ApplyBarValueFonts(bar,font,fSz-1,fOut,fShad)
            bar.statusbar:Hide(); bar.fill:Show()

            if item.isSeparator then
                self:SetDeathColumnLayout(bar,false)
                bar._data = nil; bar._isDeath = false; bar._guid = nil
                bar.fill:SetWidth(cw); bar.fill:SetVertexColor(0.06,0.06,0.08,0.95)
                bar.rank:SetText("")
                bar.name:SetText(item.label)
                bar.name:SetTextColor(tr, tg, tb, ta)
                bar.value:SetText(type(item.count) == "number"
                    and string.format("|cff888888%d|r", item.count) or "")
                if bar.specIcon then bar.specIcon:Hide() end
                self:PrioritizeBarValue(bar, false)
            else
                local d = item.d
                local textWidth=math.max(1,cw-(ns.db.display.showSpecIcon and (bh+4) or 0))
                self:SetDeathColumnLayout(bar,true,textWidth)
                bar._data = d; bar._mode = "deaths"; bar._isDeath = true; bar._guid = d.playerGUID
                bar.fill:SetVertexColor(d.isSelf and 0.45 or 0.30, 0.05, 0.05, alpha); bar.fill:SetWidth(cw)
                bar.deathTime:SetText(type(d.timestamp) == "number" and date("%H:%M", d.timestamp) or ""); bar.deathTime:SetTextColor(.62,.62,.66,1)

                local cc = ns:GetClassColor(d.playerClass) or {0.7, 0.7, 0.7}
                local deathName
                if issecretvalue and issecretvalue(d.playerName) then
                    deathName = d.playerName
                    bar.deathPlayer:SetText(ns:DisplayName(deathName))
                else
                    deathName = type(d.playerName) == "string" and d.playerName or nil
                    bar.deathPlayer:SetText(deathName and ns:DisplayName(deathName) or "")
                end
                if fixedNameColor then bar.deathPlayer:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1)
                else bar.deathPlayer:SetTextColor(cc[1], cc[2], cc[3]) end

                local killStr = ""
                if type(d.killingAbility) == "string" and d.killingAbility ~= "" then
                    killStr = (d._incomplete and "|cffaaaaaa" or "|cffff5555")
                        .. d.killingAbility .. "|r"
                end
                if type(d.killerName) == "string" and d.killerName ~= "" then
                    local killer = ns:DisplayName(d.killerName)
                    killStr = killStr ~= "" and (killStr .. " - " .. killer) or killer
                end
                bar.deathReason:SetText(killStr); bar.deathReason:SetTextColor(1,.45,.45,1)
                local officialDeathCount = type(d._deathCount) == "number" and d._deathCount or nil
                bar.deathCount:SetText(officialDeathCount and officialDeathCount > 1
                    and string.format("x%d", officialDeathCount) or "")
                bar.deathCount:SetTextColor(.62,.62,.66,1)
                self:ApplyFont(bar.deathTime,font,fSz-1,fOut,fShad); self:ApplyFont(bar.deathPlayer,nameFont,nameSz,nameOut,nameShad); self:ApplyFont(bar.deathReason,font,fSz-1,fOut,fShad); self:ApplyFont(bar.deathCount,font,fSz-1,fOut,fShad)
                self:PrioritizeDeathNumbers(bar, textWidth)

                if bar.specIcon then
                    local guid = d.playerGUID
                    local specID = nil
                    if guid == ns.state.playerGUID then
                        local snapshot = self:GetLocalPlayerSnapshot()
                        specID = snapshot and snapshot.specID
                    end
                    local icon = ns:GetSpecIcon(specID, d.playerClass, d._specIconID)
                    if ns.db.display.showSpecIcon and icon then bar.specIcon:SetTexture(icon); bar.specIcon:Show() else bar.specIcon:Hide() end
                end
            end
            bar.frame:Show()
        else
            bars[i].frame:Hide()
            self:ReleaseBarData(bars[i])
        end
    end
end
