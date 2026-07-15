--[[
    Light Damage - UIPinned.lua
    固定自己排名系统

    ★ 改造说明:
    - CheckPinnedSelfForAPI / FillPinnedFromAPI 增加 sessionID 透传
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local function _safeSetStatusBar(sb, maxV, val)
    if INTERP then
        sb:SetMinMaxValues(0, maxV, INTERP)
        sb:SetValue(val, INTERP)
    else
        sb:SetMinMaxValues(0, maxV)
        sb:SetValue(val)
    end
end

local function IsReadableTable(value)
    if type(value) ~= "table" then return false end
    local gateway = ns.DamageMeterGateway
    return not gateway or gateway:IsTableAccessible(value)
end

function UI:MakePinnedSelfBar(container, sf, section)
    local bar = self:MakeBar(container, section, 0)
    local scrollArea = sf and sf._ldScrollArea
    if scrollArea then scrollArea._extraHoverFrames[#scrollArea._extraHoverFrames + 1] = bar.frame end
    bar.frame:SetFrameLevel(sf:GetFrameLevel() + 10); bar._isPinned = true; bar.frame:Hide(); return bar
end

function UI:GetSelfViewportPosition(listObj, selfIdx)
    local bh, gap = self:GetBarConfig(); local rowH = bh + gap; if rowH <= 0 then return "visible" end
    local viewH = listObj.sf:GetHeight(); local scrollOffset = listObj.sf:GetVerticalScroll() or 0
    local selfTop = (selfIdx - 1) * rowH; local selfBottom = selfTop + bh
    local viewTop = scrollOffset; local viewBottom = scrollOffset + viewH
    -- A partially clipped row is not meaningfully "visible".  Keep the
    -- direction names identical to PositionPinnedBar/ShrinkSfForPinned so the
    -- top branch cannot silently fall through to the bottom branch.
    if selfTop < viewTop then return "top" end
    if selfBottom > viewBottom then return "bottom" end
    return "visible"
end

function UI:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, _, font, fSz, fOut, fShad = self:GetBarConfig()
    local nameFont, nameSz, nameOut, nameShad = self:GetDisplayFontConfig("name")
    self:ResetBarValueDisplay(pinnedBar)
    pinnedBar.frame:ClearAllPoints(); pinnedBar.frame:SetHeight(bh)
    if position == "top" then
        pinnedBar.frame:SetPoint("BOTTOMLEFT", listObj.sf, "TOPLEFT", 0, 0); pinnedBar.frame:SetPoint("BOTTOMRIGHT", listObj.sf, "TOPRIGHT", 0, 0)
    else
        pinnedBar.frame:SetPoint("TOPLEFT", listObj.sf, "BOTTOMLEFT", 0, 0); pinnedBar.frame:SetPoint("TOPRIGHT", listObj.sf, "BOTTOMRIGHT", 0, 0)
    end
    self:AnchorBarTexts(pinnedBar)
    self:SetDeathColumnLayout(pinnedBar,false)
    self:ApplyFont(pinnedBar.rank, font, fSz-1, fOut, fShad); self:ApplyBarNameFonts(pinnedBar,nameFont,nameSz,nameOut,nameShad); self:ApplyBarValueFonts(pinnedBar,font,fSz-1,fOut,fShad)
end

function UI:FillPinnedFromData(pinnedBar, listObj, d, rank, dur, mode, maxV, position)
    self:PositionPinnedBar(pinnedBar, listObj, position)
    self:ResetBarValueDisplay(pinnedBar)
    local bh, gap, alpha = self:GetBarConfig(); local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local tr, tg, tb, ta = self:GetDisplayColor("fontColor", {1, 1, 1, 0.93})
    local fixedNameColor = (ns.db.display.nameColorMode == "custom") and ns.db.display.nameFontColor or nil
    pinnedBar.statusbar:Hide(); pinnedBar.fill:Show()
    local cc = ns:GetClassColor(d.class) or {0.5, 0.5, 0.5}
    local offset = ns.db.display.showSpecIcon and (bh + 4) or 0
    local maxBarW = math.max(1, listObj.child:GetWidth() - offset)
    pinnedBar.fill:SetWidth(math.max(1, maxBarW * (maxV > 0 and (d.value / maxV) or 0)))
    pinnedBar.fill:SetTexture(texPath); pinnedBar.fill:SetVertexColor(cc[1], cc[2], cc[3], alpha)
    pinnedBar.statusbar:SetStatusBarTexture(texPath)
    pinnedBar.rank:SetText(ns.db.display.showRank and (rank .. ".") or "")
    pinnedBar.rank:SetTextColor(tr, tg, tb, ta)
    self:SetBarDisplayName(pinnedBar,d.name)
    if fixedNameColor then pinnedBar.name:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1); pinnedBar.rawName:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1)
    else pinnedBar.name:SetTextColor(cc[1], cc[2], cc[3]); pinnedBar.rawName:SetTextColor(cc[1], cc[2], cc[3]) end
    pinnedBar.value:SetText(self:MakeValueStr(d.value, dur, mode, d.perSec, d.percent))
    pinnedBar.value:SetTextColor(tr, tg, tb, ta)
    pinnedBar._data = d; pinnedBar._mode = mode; pinnedBar._isDeath = false; pinnedBar._guid = d.guid; pinnedBar._nameStr = d.name; pinnedBar._classStr = d.class
    if pinnedBar.specIcon then
        local specID = d.specID
        if d.guid == ns.state.playerGUID then
            local snapshot = self:GetLocalPlayerSnapshot()
            specID = snapshot and snapshot.specID or specID
        end
        local icon = ns:GetSpecIcon(specID, d.class, d.specIconID)
        if ns.db.display.showSpecIcon and icon then
            pinnedBar.specIcon:SetTexture(icon)
            pinnedBar.specIcon:Show()
        else
            pinnedBar.specIcon:Hide()
        end
    end
    self:PrioritizeBarValue(pinnedBar, false)
    pinnedBar.frame:Show()
end

-- ★ 增加 sessionID 透传
function UI:FillPinnedFromAPI(pinnedBar, listObj, src, rank, mode, maxAmt, sType, position, sessionID)
    if not IsReadableTable(src) then pinnedBar.frame:Hide(); if self.ReleaseBarData then self:ReleaseBarData(pinnedBar) end; return end
    self:ObserveDamageMeterSourceOnce(src)
    self:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, alpha = self:GetBarConfig(); local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local tr, tg, tb, ta = self:GetDisplayColor("fontColor", {1, 1, 1, 0.93})
    local fixedNameColor = (ns.db.display.nameColorMode == "custom") and ns.db.display.nameFontColor or nil
    pinnedBar.fill:Hide(); pinnedBar.statusbar:Show()
    local rawClass=src.classFilename
    local cls=(ns.DamageMeterGateway and ns.DamageMeterGateway:IsAccessible(rawClass)
        and type(rawClass)=="string" and rawClass~="") and rawClass or nil
    local cc = ns:GetClassColor(cls) or {0.5, 0.5, 0.5}
    pinnedBar.statusbar:SetStatusBarTexture(texPath); pinnedBar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha)

    local gateway=ns.DamageMeterGateway
    local maxSecret=gateway and not gateway:IsAccessible(maxAmt)
        or (not gateway and issecretvalue and issecretvalue(maxAmt)) or false
    local maxValue
    if maxSecret then maxValue=maxAmt else maxValue=maxAmt or 1 end
    pcall(_safeSetStatusBar,pinnedBar.statusbar,maxValue,src.totalAmount)

    pinnedBar.rank:SetText(ns.db.display.showRank and (rank .. ".") or "")
    pinnedBar.rank:SetTextColor(tr, tg, tb, ta)

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
    self:SetBarDisplayName(pinnedBar,nameStr)
    if fixedNameColor then pinnedBar.name:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1); pinnedBar.rawName:SetTextColor(fixedNameColor[1], fixedNameColor[2], fixedNameColor[3], fixedNameColor[4] or 1)
    else pinnedBar.name:SetTextColor(cc[1], cc[2], cc[3]); pinnedBar.rawName:SetTextColor(cc[1], cc[2], cc[3]) end

    local amountSecret,rateSecret=self:SetAPIBarValue(pinnedBar,src.totalAmount,src.amountPerSecond,ns.db.display.showPerSecond,UI.COUNT_MODES[mode],L.COUNT_SUFFIX)
    self:SetBarValueTextColor(pinnedBar,tr,tg,tb,ta)
    if not pinnedBar._apiData then pinnedBar._apiData = {} end
    pinnedBar._apiData.isAPI = true; pinnedBar._apiData.sourceGUID = src.sourceGUID; pinnedBar._apiData.sourceCreatureID = src.sourceCreatureID
    pinnedBar._apiData.isLocalPlayer = true; pinnedBar._apiData.totalAmount = src.totalAmount; pinnedBar._apiData.amountPerSecond = src.amountPerSecond; pinnedBar._apiData.sessionType = sType
    pinnedBar._apiData.sessionID = sessionID
    pinnedBar._apiData.isSecretAmount=amountSecret
    pinnedBar._apiData.isSecretRate=rateSecret
    pinnedBar._apiData.specIconID = src.specIconID
    local snapshot = self:GetLocalPlayerSnapshot()
    local specID = snapshot and snapshot.specID
    pinnedBar._apiData.specID = specID
    pinnedBar._apiData.ilvl = snapshot and snapshot.ilvl or 0
    pinnedBar._apiData.score = snapshot and snapshot.score or 0
    pinnedBar._data = pinnedBar._apiData; pinnedBar._mode = mode; pinnedBar._isDeath = false; pinnedBar._guid = src.sourceGUID; pinnedBar._nameStr = src.name; pinnedBar._classStr = cls
    if pinnedBar.specIcon then
        local icon = ns:GetSpecIcon(specID, cls, src.specIconID)
        if ns.db.display.showSpecIcon and icon then pinnedBar.specIcon:SetTexture(icon); pinnedBar.specIcon:Show() else pinnedBar.specIcon:Hide() end
    end
    self:PrioritizeBarValue(pinnedBar, amountSecret or rateSecret)
    pinnedBar.frame:Show()
end

function UI:ShrinkSfForPinned(listKey, listObj, dataCount, position)
    local bh = self:GetBarConfig()
    if not self._pinnedSfSavedAnchors then self._pinnedSfSavedAnchors = {} end
    if not self._pinnedSfSavedAnchors[listKey] then
        local n = listObj.sf:GetNumPoints(); local anchors = {}
        for i = 1, n do anchors[i] = { listObj.sf:GetPoint(i) } end
        self._pinnedSfSavedAnchors[listKey] = anchors

        -- Grid scroll frames are constrained by both TOP and BOTTOM anchors.
        -- SetHeight cannot reliably make room in that layout, so reserve one
        -- row inside the cell by moving the anchor on the pinned side inward.
        local adjusted = false
        listObj.sf:ClearAllPoints()
        for _, a in ipairs(anchors) do
            local point, rel, relPoint, x, y = unpack(a)
            if position == "top" and point:find("TOP") then
                y = y - bh; adjusted = true
            elseif position == "bottom" and point:find("BOTTOM") then
                y = y + bh; adjusted = true
            end
            listObj.sf:SetPoint(point, rel, relPoint, x, y)
        end

        -- Compatibility fallback for a future scroll frame that has no anchor
        -- on the requested side.
        if not adjusted then
            if not self._pinnedSfOrigH then self._pinnedSfOrigH = {} end
            self._pinnedSfOrigH[listKey] = listObj.sf:GetHeight()
            listObj.sf:SetHeight(math.max(1, self._pinnedSfOrigH[listKey] - bh))
        end
    end
    self:UpdateScrollState(listObj, dataCount)
end

function UI:RestoreSfForPinned(listKey, listObj, dataCount)
    local restored = false
    if self._pinnedSfOrigH and self._pinnedSfOrigH[listKey] then listObj.sf:SetHeight(self._pinnedSfOrigH[listKey]); self._pinnedSfOrigH[listKey] = nil; restored = true end
    if self._pinnedSfSavedAnchors and self._pinnedSfSavedAnchors[listKey] then
        listObj.sf:ClearAllPoints(); for _, a in ipairs(self._pinnedSfSavedAnchors[listKey]) do listObj.sf:SetPoint(unpack(a)) end
        self._pinnedSfSavedAnchors[listKey] = nil; restored = true
    end
    if restored then self:UpdateScrollState(listObj, dataCount) end
end

function UI:CheckPinnedSelfForBars(listKey, listObj, data, dur, mode, count)
    if not self._pinnedSelf then return end; local pinnedBar = self._pinnedSelf[listKey]; if not pinnedBar then return end
    if not self._pinnedSelfCache then self._pinnedSelfCache = {} end
    self:RestoreSfForPinned(listKey, listObj, count)
    if not ns.db.display.alwaysShowSelf or mode == "deaths" or mode == "enemyDamageTaken" then self._pinnedSelfCache[listKey]=nil; pinnedBar.frame:Hide(); return end
    local selfIdx, selfData = nil, nil
    for i, d in ipairs(data) do if d.guid == ns.state.playerGUID then selfIdx = i; selfData = d; break end end
    if not selfIdx or not selfData then self._pinnedSelfCache[listKey]=nil; pinnedBar.frame:Hide(); return end
    self._pinnedSelfCache[listKey] = { type = "bars", data = data, dur = dur, mode = mode, count = count }
    local position = self:GetSelfViewportPosition(listObj, selfIdx)
    if position == "visible" then pinnedBar.frame:Hide(); return end
    self:ShrinkSfForPinned(listKey, listObj, count, position)
    local maxV = data[1] and data[1].value or 0
    self:FillPinnedFromData(pinnedBar, listObj, selfData, selfIdx, dur, mode, maxV, position)
end

-- ★ 增加 sessionID 参数,透传给 FillPinnedFromAPI
function UI:CheckPinnedSelfForAPI(listKey, listObj, sources, mode, maxAmt, sType, sessionID)
    if not self._pinnedSelf then return end; local pinnedBar = self._pinnedSelf[listKey]; if not pinnedBar then return end
    if not IsReadableTable(sources) then pinnedBar.frame:Hide(); return end
    local count = math.min(#sources, UI.MAX_BARS)
    if not self._pinnedSelfCache then self._pinnedSelfCache = {} end
    self:RestoreSfForPinned(listKey, listObj, count)
    if not ns.db.display.alwaysShowSelf or mode == "deaths" or mode == "enemyDamageTaken" then self._pinnedSelfCache[listKey]=nil; pinnedBar.frame:Hide(); return end
    local selfIdx, selfSrc = nil, nil
    local gateway = ns.DamageMeterGateway
    for i, src in ipairs(sources) do
        if IsReadableTable(src) and (not gateway or gateway:IsAccessible(src.isLocalPlayer))
            and src.isLocalPlayer == true then
            selfIdx = i; selfSrc = src; break
        end
    end
    if not selfIdx or not selfSrc then self._pinnedSelfCache[listKey]=nil; pinnedBar.frame:Hide(); return end
    self._pinnedSelfCache[listKey] = { type = "api", sources = sources, mode = mode, maxAmt = maxAmt, sType = sType, sessionID = sessionID }
    local position = self:GetSelfViewportPosition(listObj, selfIdx)
    if position == "visible" then pinnedBar.frame:Hide(); return end
    self:ShrinkSfForPinned(listKey, listObj, count, position)
    self:FillPinnedFromAPI(pinnedBar, listObj, selfSrc, selfIdx, mode, maxAmt, sType, position, sessionID)
end
