--[[
    Light Damage - UICore.lua
    主界面:框架创建、标题栏、基础结构

    ★ 改造说明:
    - hookScroll 里 args.sessionID 透传给 CheckPinnedSelfForAPI
]]

local addonName, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local BAR_H   = 18
local BAR_GAP = 1
local TITLE_H = 22
local SUMM_H  = 16
local SECTH_H = 18
local TAB_H   = 20
local MAX_BARS = 40

UI.BAR_H = BAR_H; UI.BAR_GAP = BAR_GAP; UI.TITLE_H = TITLE_H
UI.SUMM_H = SUMM_H; UI.SECTH_H = SECTH_H; UI.TAB_H = TAB_H; UI.MAX_BARS = MAX_BARS

local T = {
    dmgC   = {1.0, 0.82, 0.0},
    healC  = {0.4, 1.0, 0.4},
    takenC = {1.0, 0.3, 0.3},
    accent = {0.0, 0.65, 1.0},
}
UI.T = T

local MODE_TO_DM = {
    damage      = Enum.DamageMeterType.DamageDone,
    healing     = Enum.DamageMeterType.HealingDone,
    damageTaken = Enum.DamageMeterType.DamageTaken,
    interrupts  = Enum.DamageMeterType.Interrupts,
    dispels     = Enum.DamageMeterType.Dispels,
    deaths      = Enum.DamageMeterType.Deaths,
    enemyDamageTaken   = Enum.DamageMeterType.EnemyDamageTaken,
}
UI.MODE_TO_DM = MODE_TO_DM

local COUNT_MODES = { deaths=true, interrupts=true, dispels=true }
UI.COUNT_MODES = COUNT_MODES

local TEX = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
UI.TEX = TEX

function UI:FillBg(f, c)
    local t = f:CreateTexture(nil,"BACKGROUND"); t:SetAllPoints()
    t:SetColorTexture(unpack(c)); return t
end

function UI:FS(p, sz, fl)
    local f = p:CreateFontString(nil,"OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT, sz, fl or "")
    f:SetTextColor(1, 1, 1, 0.93); return f
end

function UI:Btn(p, lbl, sz, fn)
    local b = CreateFrame("Button", nil, p); b:SetSize(18, TITLE_H)
    b.text = self:FS(b, sz, "OUTLINE"); b.text:SetPoint("CENTER")
    b.text:SetText(lbl); b.text:SetTextColor(0.55, 0.55, 0.55)
    b:SetScript("OnClick", function(...)
        if GameTooltip then GameTooltip:Hide() end
        if fn then fn(...) end
    end)
    b:SetScript("OnEnter", function() b.text:SetTextColor(1,1,1) end)
    b:SetScript("OnLeave", function() b.text:SetTextColor(0.55,0.55,0.55) end)
    return b
end

function UI:IconBtn(p, texNormal, texHover, btnW, fn, tooltipText)
    local iconSize = TITLE_H - 6
    local b = CreateFrame("Button", nil, p); b:SetSize(btnW or 20, TITLE_H); b:EnableMouse(true)
    local t = b:CreateTexture(nil, "ARTWORK"); t:SetSize(iconSize, iconSize); t:SetPoint("CENTER")
    t:SetTexture(texNormal); t:SetVertexColor(0.65, 0.65, 0.65, 1)
    b.iconTex = t; b.texNormal = texNormal; b.texHover = texHover or texNormal
    b:SetScript("OnEnter", function()
        t:SetTexture(b.texHover); t:SetVertexColor(1, 1, 1, 1)
        local resolvedTooltip = type(tooltipText) == "function" and tooltipText()
            or (tooltipText and (L[tooltipText] or tooltipText))
        if resolvedTooltip and GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:SetText(resolvedTooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        t:SetTexture(b.texNormal); t:SetVertexColor(0.65, 0.65, 0.65, 1)
        if tooltipText and GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(...)
        if GameTooltip then GameTooltip:Hide() end
        if fn then fn(...) end
    end)
    return b
end

function UI:IsOverallColumnActive()
    if not ns.db or not ns.db.split then return false end
    if not ns.db.split.showOverall then return false end
    local cat = ns.state.instanceCategory or "outdoor"
    if cat == "mplus" and ns.db.split.overallShowMPlus then return true end
    if cat == "raid" and ns.db.split.overallShowRaid then return true end
    if cat == "dungeon" and ns.db.split.overallShowDungeon then return true end
    if cat == "outdoor" and ns.db.split.overallShowOutdoor then return true end
    return false
end

function UI:IsSplitActiveInCurrentScene()
    if not ns.db or not ns.db.split then return false end
    if not ns.db.split.enabled then return false end
    local cat = ns.state.instanceCategory or "outdoor"
    if cat == "mplus" and ns.db.split.splitShowMPlus then return true end
    if cat == "raid" and ns.db.split.splitShowRaid then return true end
    if cat == "dungeon" and ns.db.split.splitShowDungeon then return true end
    if cat == "outdoor" and ns.db.split.splitShowOutdoor then return true end
    return false
end

function UI:ApplyTheme()
    local dbw = ns.db.window
    local tc = dbw.themeColor or {0, 0, 0, 1}
    local bc = dbw.bgColor    or {0.02, 0.02, 0.025, 0.58}
    if self.frame    then self.frame:SetBackdropColor(unpack(bc)) end
    if self.titleBg  then self.titleBg:SetColorTexture(unpack(tc)) end
    if self.tabBg    then self.tabBg:SetColorTexture(unpack(tc)) end
    if self.summBg   then self.summBg:SetColorTexture(tc[1]*0.8, tc[2]*0.8, tc[3]*0.8, tc[4]) end
    local sc = {tc[1]*0.9, tc[2]*0.9, tc[3]*0.9, tc[4]}
    if self.priHead    then self.priHead.bg:SetColorTexture(unpack(sc)) end
    if self.secHead    then self.secHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrPriHead then self.ovrPriHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrSecHead then self.ovrSecHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrContainer then
    local c = dbw.ovrBgColor or {0.025, 0.035, 0.05, 0.62}
        self.ovrContainer:SetBackdropColor(unpack(c))
    end
end

function UI:GetBarConfig()
    local db = ns.db.display
    return db.barHeight or 18, db.barGap or 1, db.barAlpha or 0.85,
           db.font or STANDARD_TEXT_FONT, db.fontSizeBase or 12,
           db.fontOutline or "OUTLINE", db.fontShadow or false
end

function UI:GetDisplayFontConfig(kind)
    local db = ns.db.display or {}
    if kind == "title" then
        return db.titleFont or db.font or STANDARD_TEXT_FONT,
               db.titleFontSize or db.fontSizeBase or 10,
               db.titleFontOutline or db.fontOutline or "OUTLINE",
               db.titleFontShadow or false
    elseif kind == "header" then
        return db.headerFont or db.font or STANDARD_TEXT_FONT,
               db.headerFontSize or db.fontSizeBase or 9,
               db.headerFontOutline or db.fontOutline or "OUTLINE",
               db.headerFontShadow or false
    elseif kind == "name" then
        return db.nameFont or db.font or STANDARD_TEXT_FONT,
               db.nameFontSize or db.fontSizeBase or 12,
               db.nameFontOutline or db.fontOutline or "OUTLINE",
               db.nameFontShadow or false
    elseif kind == "tab" then
        return db.tabFont or db.font or STANDARD_TEXT_FONT,
               db.tabFontSize or math.max(8, (db.fontSizeBase or 10) - 1),
               db.tabFontOutline or db.fontOutline or "OUTLINE",
               db.tabFontShadow or false
    end
    local _, _, _, font, size, outline, shadow = self:GetBarConfig()
    return font, size, outline, shadow
end

function UI:GetDisplayColor(field, fallback)
    local db = ns.db and ns.db.display or {}
    local c = db[field] or fallback or {1, 1, 1, 1}
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

function UI:SetFontStringColor(fs, field, fallback)
    if not fs then return end
    fs:SetTextColor(self:GetDisplayColor(field, fallback))
end

function UI:GetModeTitleColor(mode)
    local colors = ns.db and ns.db.display and ns.db.display.dataTitleColors
    local fallback = mode == "damage" and T.dmgC
        or mode == "healing" and T.healC
        or mode == "damageTaken" and T.takenC
        or mode == "enemyDamageTaken" and T.takenC
        or T.accent
    local c = colors and colors[mode] or fallback
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

function UI:ColorizeText(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5),
        text or "")
end

function UI:SetModeHeaderText(label, text, mode)
    if not label then return end
    local r, g, b = self:GetModeTitleColor(mode)
    label:SetText(self:ColorizeText(text, r, g, b))
end

function UI:SetTabTextColor(tabText, active)
    if active then
        self:SetFontStringColor(tabText, "tabActiveFontColor", {1, 1, 1, 1})
    else
        self:SetFontStringColor(tabText, "tabInactiveFontColor", {0.55, 0.55, 0.55, 0.9})
    end
end

function UI:ApplyFont(fs, font, size, outline, shadow)
    if not fs then return false end
    font = font or STANDARD_TEXT_FONT
    size = tonumber(size) or 10
    outline = ns.NormalizeFontOutline and ns:NormalizeFontOutline(outline) or outline
    shadow = shadow and true or false
    if fs._ldFontValid and fs._ldFont == font and fs._ldFontSize == size
        and fs._ldFontOutline == outline and fs._ldFontShadow == shadow then
        return true
    end
    local ok, applied = pcall(fs.SetFont, fs, font, size, outline)
    if not ok or applied == false then
        -- Keep the configured path untouched, make the text readable, and do
        -- not cache the failed request so a later media registration retries.
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, outline)
        fs._ldFontValid = nil
        fs._ldFont = nil; fs._ldFontSize = nil
        fs._ldFontOutline = nil; fs._ldFontShadow = nil
        self._lastFontHash = nil
    else
        fs._ldFontValid = true
        fs._ldFont = font; fs._ldFontSize = size
        fs._ldFontOutline = outline; fs._ldFontShadow = shadow
    end
    if shadow then fs:SetShadowColor(0,0,0,1); fs:SetShadowOffset(1,-1)
    else fs:SetShadowOffset(0,0) end
    return ok and applied ~= false
end

function UI:ClampSize(w, h)
    if type(w) ~= "number" or w ~= w or w <= 0 then w = ns.defaults.window.width end
    if type(h) ~= "number" or h ~= h or h <= 0 then h = ns.defaults.window.height end
    return w, h
end

function UI:ApplyAllFontsIfNeeded()
    local db = ns.db.display
    local hash = table.concat({
        db.font or "", db.fontSizeBase or 10, db.fontOutline or "", db.fontShadow and "1" or "0",
        db.titleFont or "", db.titleFontSize or 10, db.titleFontOutline or "", db.titleFontShadow and "1" or "0",
        db.headerFont or "", db.headerFontSize or 9, db.headerFontOutline or "", db.headerFontShadow and "1" or "0",
        db.nameFont or "", db.nameFontSize or 12, db.nameFontOutline or "", db.nameFontShadow and "1" or "0",
        db.tabFont or "", db.tabFontSize or 9, db.tabFontOutline or "", db.tabFontShadow and "1" or "0",
        tostring(db.fontColor), tostring(db.titleFontColor), tostring(db.headerFontColor),
        tostring(db.nameFontColor), tostring(db.tabActiveFontColor), tostring(db.tabInactiveFontColor),
    }, "|")
    if hash == self._lastFontHash then return end
    self._lastFontHash = hash
    self:ApplyAllFonts()
end

function UI:ApplyAllFonts()
    if not self.frame then return end
    local font, fSz, fOut, fShad = self:GetDisplayFontConfig("title")
    if self.titleText then self:ApplyFont(self.titleText, font, fSz, fOut, fShad) end
    if self.titleTime then self:ApplyFont(self.titleTime, font, fSz, fOut, fShad) end
    if self.summText then self:ApplyFont(self.summText, font, math.max(8, fSz - 1), fOut, fShad) end
    self:SetFontStringColor(self.titleText, "titleFontColor", {1, 1, 1, 0.93})
    local function applyHead(h)
        if not h then return end
        local hFont, hSz, hOut, hShad = self:GetDisplayFontConfig("header")
        self:ApplyFont(h.label, hFont, hSz, hOut, hShad)
        self:ApplyFont(h.info, hFont, hSz, hOut, hShad)
        if h.rawInfo then self:ApplyFont(h.rawInfo, hFont, hSz, hOut, hShad) end
        self:SetFontStringColor(h.info, "headerFontColor", {0.55, 0.55, 0.55, 0.9})
        if h.rawInfo then self:SetFontStringColor(h.rawInfo, "headerFontColor", {0.55, 0.55, 0.55, 0.9}) end
    end
    applyHead(self.priHead); applyHead(self.secHead); applyHead(self.ovrPriHead); applyHead(self.ovrSecHead)
    local tFont, tSz, tOut, tShad = self:GetDisplayFontConfig("tab")
    if self.tabs then for _, t in ipairs(self.tabs) do self:ApplyFont(t.text, tFont, tSz, tOut, tShad) end end
    if self.splitTab then self:ApplyFont(self.splitTab.text, tFont, tSz, tOut, tShad) end
end

function UI:GetCachedSession(sessionType, dmType)
    local cache = self._sessionCache
    local sub = cache[sessionType]
    if not sub then
        sub = {}
        cache[sessionType] = sub
    end
    local v = sub[dmType]
    if v == nil then
        local gateway = ns.DamageMeterGateway
        v = gateway and select(1, gateway:GetRawSession(sessionType, nil, dmType)) or false
        sub[dmType] = v
    end
    if v == false then return nil end
    return v
end

function UI:EnsureCreated() if self.frame then return end; self:Build() end

function UI:Build()
    local db = ns.db.window
    BAR_H = ns.db.display.barHeight or 18

    local f = CreateFrame("Frame","LightDamageFrame",UIParent,"BackdropTemplate")
    f:SetSize(self:ClampSize(db.width, db.height))
    if db.rememberSceneSize and db.sceneSizes then
        local cat = ns.state.instanceCategory or "outdoor"
        local s = db.sceneSizes[cat]
        if s then f:SetSize(self:ClampSize(s.width, s.height)) end
    end
    f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    f:SetScale(db.scale); f:SetAlpha(db.alpha)
    f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    f:SetMovable(true); f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(250, 180, 1000, 900) end
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 })
    f:SetClipsChildren(true)
    self.frame = f

    self:BuildTitle(); self:BuildMPlusSummary(); self:BuildBody()
    self:BuildTabs(); self:BuildResize(); self:SetupDrag()
    self:ApplyTheme()
    f:HookScript("OnSizeChanged", function() self:OnResize() end)

    if ns.db.window.visible == false then f:Hide()
    else f:Show(); self:Layout() end

    self:CheckAutoCollapse(true)
    self._lastFontHash = nil
    self._sessionCache = {}

    self._faded = false; self._fadeAnimating = false; self._wasMouseOver = false
    local fadeHoverFrame = CreateFrame("Frame")
    fadeHoverFrame._timer = 0
    fadeHoverFrame:SetScript("OnUpdate", function(frame, elapsed)
        frame._timer = frame._timer + elapsed
        if frame._timer < 0.1 then return end; frame._timer = 0
        if not ns.db or not ns.db.fade then return end
        if not (ns.db.fade.fadeBars or ns.db.fade.fadeBody) then return end
        if not ns.db.fade.unfadeOnHover then return end
        if not self.frame or not self.frame:IsShown() then return end
        local isOver = self.frame:IsMouseOver()
        if isOver and not self._wasMouseOver then
            if self._faded then self:ApplyFadeAlpha(false, false) end
        elseif not isOver and self._wasMouseOver then
            self:CheckAutoFade(true)
        end
        self._wasMouseOver = isOver
    end)
    fadeHoverFrame:Hide()
    f:HookScript("OnShow", function() fadeHoverFrame._timer = 0; self:UpdateFadeHoverDriver() end)
    f:HookScript("OnHide", function() fadeHoverFrame:Hide() end)
    self._fadeHoverFrame = fadeHoverFrame
    self:UpdateFadeHoverDriver()
    C_Timer.After(0.5, function()
        if self.frame and self.frame:IsShown() and not ns.state.inCombat then self:CheckAutoFade(true) end
    end)
end

function UI:UpdateFadeHoverDriver()
    local driver=self._fadeHoverFrame
    if not driver then return end
    local fade=ns.db and ns.db.fade
    local enabled=self.frame and self.frame:IsShown() and fade
        and (fade.fadeBars or fade.fadeBody) and fade.unfadeOnHover
    if enabled then
        driver._timer=0
        driver:Show()
    else
        driver:Hide()
        self._wasMouseOver=false
    end
end

function UI:BuildTitle()
    local b = CreateFrame("Frame", nil, self.frame)
    b:SetHeight(TITLE_H); b:SetPoint("TOPLEFT",0,0); b:SetPoint("TOPRIGHT",0,0)
    self.titleBg = self:FillBg(b, {0, 0, 0, 1})
    self.titleBar = b

    local listBtn = self:Btn(b, "[=]", 12, function() if ns.HistoryList then ns.HistoryList:Toggle(b) end end)
    listBtn:SetPoint("LEFT", 4, 0); listBtn:SetSize(22, TITLE_H); self.listBtn = listBtn

    self.titleText = self:FS(b, 10, "OUTLINE")
    self.titleText:SetPoint("LEFT", listBtn, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", b, "RIGHT", -72, 0)
    self.titleText:SetJustifyH("LEFT"); self.titleText:SetWordWrap(false)

    local titleBtn = CreateFrame("Button", nil, b)
    titleBtn:SetPoint("LEFT", listBtn, "RIGHT", 0, 0); titleBtn:SetPoint("RIGHT", b, "RIGHT", -72, 0); titleBtn:SetHeight(TITLE_H)
    titleBtn:SetScript("OnClick", function() if ns.HistoryList then ns.HistoryList:Toggle(b) end end)
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnDragStart", function() if not ns.db.window.locked then self.frame:StartMoving() end end)
    titleBtn:SetScript("OnDragStop", function()
        self.frame:StopMovingOrSizing()
        if self.PersistWorkspaceGeometry then self:PersistWorkspaceGeometry() else
            local db = ns.db.window
            local point, relativeTo, relPoint, x, y = self.frame:GetPoint()
            db.point = point; db.relPoint = relPoint; db.x = x; db.y = y
            if self._collapsed then self._savedAnchor = { point, relativeTo, relPoint, x, y } end
        end
    end)

    self._collapsed = false
    local colBtn = self:IconBtn(b, TEX.."btn_collapse", TEX.."btn_collapse", 20, function() if not self._previewContext then self:ToggleCollapse(not self._collapsed) end end, "TOOLTIP_EXPAND_COLLAPSE")
    colBtn:SetPoint("RIGHT", -4, 0); self.collapseBtn = colBtn

    local cfgBtn = self:IconBtn(b, TEX.."btn_settings", TEX.."btn_settings", 20, function() if not self._previewContext and ns.Config then ns.Config:Toggle() end end, "TOOLTIP_SETTINGS")
    cfgBtn:SetPoint("RIGHT", colBtn, "LEFT", -2, 0); self.cfgBtn = cfgBtn

    local rstBtn = self:IconBtn(b, TEX.."btn_reset", TEX.."btn_reset", 20, function() if not self._previewContext and ns.Segments then ns.Segments:ResetAll() end end, "TOOLTIP_CLEAR_ALL_DATA")
    rstBtn:SetPoint("RIGHT", cfgBtn, "LEFT", -2, 0); self.rstBtn = rstBtn

    self.titleTime = self:FS(b, 10, "OUTLINE")
    self.titleTime:SetPoint("LEFT", listBtn, "RIGHT", 4, 0)
    self.titleTime:SetJustifyH("LEFT"); self.titleTime:SetTextColor(0.67, 0.67, 0.67)
    self.titleText:ClearAllPoints()
    self.titleText:SetPoint("LEFT", self.titleTime, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", rstBtn, "LEFT", -4, 0)
end

function UI:BuildMPlusSummary()
    local b = CreateFrame("Frame", nil, self.frame)
    b:SetHeight(SUMM_H); b:SetPoint("TOPLEFT", self.titleBar,"BOTTOMLEFT", 0,0); b:SetPoint("TOPRIGHT", self.titleBar,"BOTTOMRIGHT", 0,0)
    self.summBg = self:FillBg(b, {0.06, 0.06, 0.10, 1})
    self.summText = self:FS(b, 9, "OUTLINE"); self.summText:SetPoint("LEFT",6,0); self.summText:SetPoint("RIGHT",-6,0)
    self.summText:SetJustifyH("LEFT"); self.summText:SetTextColor(0.3, 0.8, 1.0, 0.90)
    b:Hide(); self.summaryBar = b
end

function UI:MakeScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:EnableMouse(true); sf:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, sf); sf:SetScrollChild(child)
    local sb = CreateFrame("Slider", nil, sf)
    sb:SetWidth(3); sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0); sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    sb:SetOrientation("VERTICAL"); sb:SetMinMaxValues(0,0); sb:SetValue(0)
    local track = sb:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.2)
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = sb:GetThumbTexture(); thumb:SetVertexColor(0.4, 0.4, 0.4, 0.8); thumb:SetSize(3, 30)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue(); local _, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(0, math.min(mx, cur - delta * (BAR_H * 2))))
    end)
    sb:SetScript("OnValueChanged", function(_, val) sf:SetVerticalScroll(val) end)
    local area = { sf = sf, child = child, sb = sb, _hasOverflow = false, _mouseInside = false, _extraHoverFrames = {} }
    sf._ldScrollArea = area

    function area:RefreshScrollBarVisibility()
        self.sb:SetShown(self._hasOverflow and (self._mouseInside or self._scrollbarDragging))
    end

    sb:SetScript("OnMouseDown", function()
        area._scrollbarDragging = true
        area:RefreshScrollBarVisibility()
    end)
    sb:SetScript("OnMouseUp", function()
        area._scrollbarDragging = nil
        area._mouseInside = sf:IsMouseOver() or sb:IsMouseOver()
        area:RefreshScrollBarVisibility()
    end)
    sb:SetScript("OnHide", function() area._scrollbarDragging = nil end)

    self._hoverScrollAreas = self._hoverScrollAreas or {}
    self._hoverScrollAreas[#self._hoverScrollAreas + 1] = area
    if not self._scrollHoverDriver then
        local driver = CreateFrame("Frame", nil, self.frame)
        driver._elapsed = 0
        driver:SetScript("OnUpdate", function(_, elapsed)
            driver._elapsed = driver._elapsed + elapsed
            if driver._elapsed < .06 then return end
            driver._elapsed = 0
            for _, item in ipairs(self._hoverScrollAreas or {}) do
                local inside=false
                if item._hasOverflow then
                    inside=item.sf:IsVisible() and (item.sf:IsMouseOver() or item.sb:IsMouseOver()) or false
                end
                if item._hasOverflow and not inside then
                    for _, hoverFrame in ipairs(item._extraHoverFrames) do
                        if hoverFrame:IsVisible() and hoverFrame:IsMouseOver() then
                            inside = true
                            break
                        end
                    end
                end
                if inside ~= item._mouseInside then
                    item._mouseInside = inside
                    item:RefreshScrollBarVisibility()
                end
            end
        end)
        driver:Hide()
        self._scrollHoverDriver = driver
    end
    sb:Hide()
    return area
end

function UI:UpdateScrollHoverDriver()
    local driver=self._scrollHoverDriver
    if not driver then return end
    local active=false
    if self.frame and self.frame:IsShown() then
        for _,area in ipairs(self._hoverScrollAreas or {}) do
            if area._hasOverflow and area.sf:IsVisible() then active=true; break end
        end
    end
    driver:SetShown(active)
end

function UI:MakeSectHead(parent)
    local h = CreateFrame("Frame", nil, parent); h:SetHeight(SECTH_H)
    h.bg = self:FillBg(h, {0.06, 0.06, 0.08, 0.9})
    h.label = self:FS(h, 9, "OUTLINE"); h.label:SetPoint("LEFT",6,0); h.label:SetJustifyH("LEFT")
    h.info = self:FS(h, 9, "OUTLINE"); h.info:SetJustifyH("RIGHT"); h.info:SetTextColor(0.55, 0.55, 0.55, 0.9)
    h.info:SetPoint("LEFT", h.label, "RIGHT", 4, 0); h.info:SetPoint("RIGHT", h, "RIGHT", -6, 0)
    h.rawInfo = self:FS(h, 9, "OUTLINE"); h.rawInfo:SetJustifyH("RIGHT"); h.rawInfo:SetTextColor(0.55, 0.55, 0.55, 0.9)
    h.rawInfo:SetPoint("LEFT", h.label, "RIGHT", 4, 0); h.rawInfo:SetPoint("RIGHT", h, "RIGHT", -6, 0); h.rawInfo:Hide()
    local line = h:CreateTexture(nil,"ARTWORK"); line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT",0,0); line:SetPoint("BOTTOMRIGHT",0,0); line:SetColorTexture(0.3,0.3,0.35,0.4)

    return h
end

function UI:BuildBody()
    self.bodyFrame = CreateFrame("Frame", nil, self.frame); self.bodyFrame:SetClipsChildren(true)
    self.ovrSepLine = self.bodyFrame:CreateTexture(nil, "ARTWORK"); self.ovrSepLine:SetWidth(1); self.ovrSepLine:SetColorTexture(0, 0, 0, 0.8); self.ovrSepLine:Hide()

    self.leftContainer = CreateFrame("Frame", nil, self.bodyFrame); self.leftContainer:SetClipsChildren(true)
    self.ovrContainer = CreateFrame("Frame", nil, self.bodyFrame, "BackdropTemplate"); self.ovrContainer:SetClipsChildren(true)
    self.ovrContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = nil, edgeSize = 0 })
    local c = ns.db.window.ovrBgColor or {0.025, 0.035, 0.05, 0.62}; self.ovrContainer:SetBackdropColor(unpack(c)); self.ovrContainer:Hide()

    self.priHead = self:MakeSectHead(self.leftContainer)
    self.priList = self:MakeScrollArea(self.leftContainer)
    self.priBars = {}; for i = 1, MAX_BARS do self.priBars[i] = self:MakeBar(self.priList.child, "primary", i) end

    self.secHead = self:MakeSectHead(self.leftContainer)
    self.secList = self:MakeScrollArea(self.leftContainer)
    self.secBars = {}; for i = 1, MAX_BARS do self.secBars[i] = self:MakeBar(self.secList.child, "secondary", i) end

    self.ovrPriHead = self:MakeSectHead(self.ovrContainer)
    self.ovrPriList = self:MakeScrollArea(self.ovrContainer)
    self.ovrPriBars = {}; for i = 1, MAX_BARS do self.ovrPriBars[i] = self:MakeBar(self.ovrPriList.child, "ovrPri", i) end

    self.ovrSecHead = self:MakeSectHead(self.ovrContainer)
    self.ovrSecList = self:MakeScrollArea(self.ovrContainer)
    self.ovrSecBars = {}; for i = 1, MAX_BARS do self.ovrSecBars[i] = self:MakeBar(self.ovrSecList.child, "ovrSec", i) end

    self._pinnedSelf = {
        pri    = self:MakePinnedSelfBar(self.leftContainer, self.priList.sf,    "primary"),
        sec    = self:MakePinnedSelfBar(self.leftContainer, self.secList.sf,    "secondary"),
        ovrPri = self:MakePinnedSelfBar(self.ovrContainer,  self.ovrPriList.sf, "ovrPri"),
        ovrSec = self:MakePinnedSelfBar(self.ovrContainer,  self.ovrSecList.sf, "ovrSec"),
    }

    -- ★ hookScroll 透传 sessionID
    local function hookScroll(listObj, listKey)
        local origOnWheel = listObj.sf:GetScript("OnMouseWheel")
        listObj.sf:SetScript("OnMouseWheel", function(frame, delta)
            if origOnWheel then origOnWheel(frame, delta) end
            if self._pinnedSelfCache and self._pinnedSelfCache[listKey] then
                local args = self._pinnedSelfCache[listKey]
                if args.type == "bars" then self:CheckPinnedSelfForBars(listKey, listObj, args.data, args.dur, args.mode, args.count)
                elseif args.type == "api" then self:CheckPinnedSelfForAPI(listKey, listObj, args.sources, args.mode, args.maxAmt, args.sType, args.sessionID) end
            end
        end)
    end
    hookScroll(self.priList, "pri"); hookScroll(self.secList, "sec")
    hookScroll(self.ovrPriList, "ovrPri"); hookScroll(self.ovrSecList, "ovrSec")
end

function UI:BuildResize()
    local g = CreateFrame("Frame", nil, self.frame); self.resizeHandle = g
    g:SetSize(16,16); g:SetPoint("BOTTOMRIGHT", 0, 0)
    g:SetFrameLevel(self.frame:GetFrameLevel() + 15); g:EnableMouse(true)
    local t = g:CreateTexture(nil,"OVERLAY"); t:SetAllPoints(); t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetScript("OnMouseDown", function() if ns.db.window.locked then return end; self.frame:StartSizing("BOTTOMRIGHT"); self._resizing = true end)
    g:SetScript("OnMouseUp", function()
        if not self._resizing then return end; self._resizing = false; self.frame:StopMovingOrSizing()
        if self._collapsed then return end
        local w, h = self:ClampSize(self.frame:GetWidth(), self.frame:GetHeight())
        self.frame:SetSize(w, h)
        ns.db.window.width = w; ns.db.window.height = h
        if ns.db.window.rememberSceneSize then
            local cat = ns.state.instanceCategory or "outdoor"
            if not ns.db.window.sceneSizes then ns.db.window.sceneSizes = {} end
            ns.db.window.sceneSizes[cat] = { width = w, height = h }
        end
        self:Layout()
    end)
end

function UI:SetupDrag()
    self.titleBar:EnableMouse(true); self.titleBar:RegisterForDrag("LeftButton")
    self.titleBar:SetScript("OnDragStart", function() if not ns.db.window.locked then self.frame:StartMoving() end end)
    self.titleBar:SetScript("OnDragStop", function() self.frame:StopMovingOrSizing(); local db = ns.db.window; db.point,_,db.relPoint,db.x,db.y = self.frame:GetPoint() end)
end

function UI:OnResize() self:LayoutTabs(); self:Layout() end

function UI:OnCombatStateChanged(inCombat)
    self:RefreshTitle(); self:Refresh()
    if inCombat then self:CheckAutoCollapse(); self:CheckAutoFade(true)
    else
        local collapseDelay = ns.db.collapse.delay or 1.5
        if collapseDelay <= 0 then self:CheckAutoCollapse() else C_Timer.After(collapseDelay, function() self:CheckAutoCollapse() end) end
        local fadeDelay = (ns.db.fade and ns.db.fade.delay) or 1.5
        if fadeDelay <= 0 then self:CheckAutoFade(true) else C_Timer.After(fadeDelay, function() self:CheckAutoFade(true) end) end
    end
end

function UI:Toggle()
    self:EnsureCreated()
    if self.frame:IsShown() then self.frame:Hide(); ns.db.window.visible = false
    else self.frame:Show(); ns.db.window.visible = true; self:Layout()
        C_Timer.After(0.1, function() self:CheckAutoFade(true) end)
    end
end
function UI:IsVisible() return self.frame and self.frame:IsShown() end
function UI:UpdateLock() self:UpdateLockState() end
function UI:UpdateLockState()
    if not self.resizeHandle then return end
    if ns.db.window.locked then self.resizeHandle:Hide() else self.resizeHandle:Show() end
end

function UI:UpdateScrollState(listObj, dataCount)
    local bh, gap = self:GetBarConfig()
    local viewH,viewW=listObj.sf:GetHeight(),listObj.sf:GetWidth()
    dataCount=math.max(0,tonumber(dataCount) or 0)
    if listObj._scrollDataCount==dataCount and listObj._scrollBarHeight==bh
        and listObj._scrollBarGap==gap and listObj._scrollViewH==viewH
        and listObj._scrollViewW==viewW then
        listObj:RefreshScrollBarVisibility()
        self:UpdateScrollHoverDriver()
        return
    end
    listObj._scrollDataCount=dataCount; listObj._scrollBarHeight=bh; listObj._scrollBarGap=gap
    listObj._scrollViewH=viewH; listObj._scrollViewW=viewW
    local totalH = dataCount * (bh + gap); listObj.child:SetHeight(math.max(10, totalH))
    local maxScroll = math.max(0, totalH - viewH)
    listObj.sb:SetMinMaxValues(0, maxScroll)
    listObj._hasOverflow = maxScroll > 0
    if listObj._hasOverflow then listObj.child:SetWidth(listObj.sf:GetWidth() - 4)
    else listObj.sb:SetValue(0); listObj.child:SetWidth(listObj.sf:GetWidth()) end
    listObj:RefreshScrollBarVisibility()
    self:UpdateScrollHoverDriver()
end

function UI:ApplySceneSize(cat)
    if not self.frame or not self.frame:IsShown() then return end
    if not ns.db.window.rememberSceneSize then return end
    local sizes = ns.db.window.sceneSizes
    if not sizes or not sizes[cat] then return end
    local s = sizes[cat]
    local anchor = ns.db.window.sceneAnchor or "TOPLEFT"

    local left, bottom = self.frame:GetLeft(), self.frame:GetBottom()
    local oldW, oldH = self.frame:GetWidth(), self.frame:GetHeight()
    if not left or not bottom then return end

    local ax, ay
    if anchor:find("LEFT") then ax = left
    elseif anchor:find("RIGHT") then ax = left + oldW
    else ax = left + oldW / 2 end
    if anchor:find("TOP") then ay = bottom + oldH
    elseif anchor:find("BOTTOM") then ay = bottom
    else ay = bottom + oldH / 2 end

    self.frame:SetSize(self:ClampSize(s.width, s.height))

    local newLeft, newBottom
    if anchor:find("LEFT") then newLeft = ax
    elseif anchor:find("RIGHT") then newLeft = ax - s.width
    else newLeft = ax - s.width / 2 end
    if anchor:find("TOP") then newBottom = ay - s.height
    elseif anchor:find("BOTTOM") then newBottom = ay
    else newBottom = ay - s.height / 2 end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
    local point, _, relPoint, x, y = self.frame:GetPoint()
    ns.db.window.point = point; ns.db.window.relPoint = relPoint; ns.db.window.x = x; ns.db.window.y = y
    self:Layout()
end
