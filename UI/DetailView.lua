--[[
    LD Combat Stats - DetailView.lua
    详情面板：技能细分 + 死亡事件详情
]]

local addonName, ns = ...
local L = ns.L

ns.FONT_MAIN = ns.FONT_MAIN or STANDARD_TEXT_FONT

local DV = {}
ns.DetailView = DV

local PREVIEW_STRATA = "FULLSCREEN_DIALOG"

local ICON_W = 18

local ROW_BG = {
    {0.07, 0.07, 0.09, 0.92},
    {0.12, 0.12, 0.15, 0.92},
}
local BG_HEADER  = {0.04, 0.04, 0.08, 0.96}
local BG_SECTION = {0.05, 0.08, 0.13, 0.92}
local BG_FATAL   = {0.22, 0.03, 0.03, 0.96}

local function GetOpaqueAbbreviatedNumber(value)
    local formatter=ns.AbbrevProtectedNumber
    if formatter then
        local ok,text=pcall(formatter,value)
        if ok then return text end
    end
    return value
end

-- 获取动态外观参数
function DV:GetBarConfig()
    local db = ns.db and ns.db.detailDisplay or {}
    return db.barHeight or 20, 
           db.barGap or 1, 
           db.barAlpha or 0.92, 
           db.font or ns.FONT_MAIN, 
           db.fontSizeBase or 10, 
           db.fontOutline or "OUTLINE", 
           db.fontShadow or false,
           db.barThickness or db.barHeight or 20,
           db.barVOffset or 0,
           db.barTexture or "Interface\\Buttons\\WHITE8X8"
end

function DV:GetFontColor()
    local db = ns.db and ns.db.detailDisplay or {}
    local c = db.fontColor or {1, 1, 1, 1}
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

function DV:SetDetailTextColor(fs)
    if not fs then return end
    fs:SetTextColor(self:GetFontColor())
end

function DV:GetDetailBarColor(defaultColor, defaultAlpha)
    local db = ns.db and ns.db.detailDisplay or {}
    if db.barColorMode == "custom" then
        local c = db.barColor or {0, 0.65, 1, defaultAlpha or 1}
        return c[1] or 0, c[2] or 0.65, c[3] or 1, c[4] or defaultAlpha or 1
    end
    defaultColor = defaultColor or {0.5, 0.5, 0.7}
    return defaultColor[1] or 0.5, defaultColor[2] or 0.5, defaultColor[3] or 0.7, defaultColor[4] or defaultAlpha or 1
end

-- ============================================================
-- 面板创建
-- ============================================================
function DV:EnsureCreated()
    if self.frame then return end

    local f = CreateFrame("Frame", "LightDamageDetail", UIParent, "BackdropTemplate")
    local dbW = ns.db and ns.db.detailWindow or { width = 380, height = 420 }
    f:SetSize(dbW.width, dbW.height)
    f:SetFrameStrata("HIGH"); f:SetFrameLevel(20)
    f:SetClampedToScreen(true); f:SetMovable(true); f:SetResizable(true); f:EnableMouse(true)
    if f.SetResizeBounds then f:SetResizeBounds(250, 200, 1000, 1000) end
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    f:SetBackdropBorderColor(0.25, 0.25, 0.32, 0.9)

    -- 标题栏
    local tb = CreateFrame("Frame", nil, f)
    tb:SetHeight(24)
    tb:SetPoint("TOPLEFT", 1, -1); tb:SetPoint("TOPRIGHT", -1, -1)
    tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() if not (ns.db.window and ns.db.window.locked) then f:StartMoving() end end)
    tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    local tbg = tb:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints()
    tbg:SetColorTexture(0.06, 0.06, 0.10, 1)
    self.titleBg = tbg  -- ★ 新增

    -- 返回按钮
    local back = CreateFrame("Button", nil, tb)
    back:SetSize(24, 24); back:SetPoint("LEFT", 2, 0)
    local bt = back:CreateFontString(nil, "OVERLAY")
    bt:SetFont(ns.FONT_MAIN, 14, "OUTLINE")
    bt:SetPoint("CENTER"); bt:SetText("<"); bt:SetTextColor(0.6, 0.6, 0.6)
    self.backText = bt  -- ★ 新增

    back:SetScript("OnClick", function() f:Hide() end)
    back:SetScript("OnEnter", function() bt:SetTextColor(1, 1, 1) end)
    back:SetScript("OnLeave", function() bt:SetTextColor(0.6, 0.6, 0.6) end)

    self.titleText = tb:CreateFontString(nil, "OVERLAY")
    self.titleText:SetFont(ns.FONT_MAIN, 10, "OUTLINE")
    self.titleText:SetPoint("LEFT", back, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", -28, 0)
    self.titleText:SetJustifyH("LEFT"); self.titleText:SetWordWrap(false)
    self.titleText:SetTextColor(1, 1, 1)
    self.rawTitleText = tb:CreateFontString(nil, "OVERLAY")
    self.rawTitleText:SetFont(ns.FONT_MAIN,10,"OUTLINE")
    self.rawTitleText:SetPoint("LEFT",back,"RIGHT",4,0); self.rawTitleText:SetPoint("RIGHT",-28,0)
    self.rawTitleText:SetJustifyH("LEFT"); self.rawTitleText:SetWordWrap(false); self.rawTitleText:SetTextColor(1,1,1); self.rawTitleText:Hide()

    -- ★ 修复：✕ 在 ARHei.TTF 里没有字形会渲染成方块，改用 X
    local cb = CreateFrame("Button", nil, tb); cb:SetSize(20, 24); cb:SetPoint("RIGHT", -2, 0)
    local ct = cb:CreateFontString(nil, "OVERLAY")
    ct:SetFont(ns.FONT_MAIN, 12, "OUTLINE")
    ct:SetPoint("CENTER"); ct:SetText("X"); ct:SetTextColor(0.5, 0.5, 0.5)
    self.closeText = ct -- ★ 新增

    cb:SetScript("OnClick", function() f:Hide() end)
    cb:SetScript("OnEnter", function() ct:SetTextColor(1, 0.3, 0.3) end)
    cb:SetScript("OnLeave", function() ct:SetTextColor(0.5, 0.5, 0.5) end)

    -- ★ 修复：替换 UIPanelScrollFrameTemplate，改用自定义细滚动条
    local sc = CreateFrame("ScrollFrame", nil, f)
    sc:SetPoint("TOPLEFT",     tb,  "BOTTOMLEFT",  2,  -2)
    sc:SetPoint("BOTTOMRIGHT", f,   "BOTTOMRIGHT", -8,  4)

    local inner = CreateFrame("Frame", nil, sc)
    inner:SetSize(340, 1000)
    sc:SetScrollChild(inner)

    -- 自定义细滚动条（和主 UI 一致）
    local sb = CreateFrame("Slider", nil, sc)
    sb:SetWidth(3)
    sb:SetPoint("TOPRIGHT",    sc, "TOPRIGHT",    0,  0)
    sb:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0,  0)
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 0); sb:SetValue(0)

    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.2)

    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = sb:GetThumbTexture()
    thumb:SetVertexColor(0.4, 0.4, 0.4, 0.8); thumb:SetSize(3, 30)

    sc:SetScript("OnMouseWheel", function(_, delta)
        local bh = DV:GetBarConfig()
        local cur = sb:GetValue()
        local _, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(0, math.min(mx, cur - delta * bh * 3)))
    end)
    sb:SetScript("OnValueChanged", function(_, val)
        sc:SetVerticalScroll(val)
    end)
    
    -- ★ 新增：缩放手柄
    local resizeGrabber = CreateFrame("Frame", nil, f)
    self.resizeHandle = resizeGrabber
    resizeGrabber:SetSize(16, 16); resizeGrabber:SetPoint("BOTTOMRIGHT", 0, 0)
    resizeGrabber:SetFrameLevel(f:GetFrameLevel() + 15); resizeGrabber:EnableMouse(true)
    local gt = resizeGrabber:CreateTexture(nil, "OVERLAY"); gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"); gt:SetVertexColor(.55,.58,.62,.9)
    resizeGrabber.iconTex = gt
    resizeGrabber:SetScript("OnEnter", function() gt:SetVertexColor(.15,.85,1,1) end)
    resizeGrabber:SetScript("OnLeave", function() gt:SetVertexColor(.55,.58,.62,.9) end)
    resizeGrabber:SetScript("OnMouseDown", function()
        if not (ns.db.window and ns.db.window.locked) then f:StartSizing("BOTTOMRIGHT"); self._resizing = true end
    end)
    resizeGrabber:SetScript("OnMouseUp", function() 
        if not self._resizing then return end
        self._resizing = false
        f:StopMovingOrSizing()
        if not ns.db.detailWindow then ns.db.detailWindow = {} end
        ns.db.detailWindow.width = f:GetWidth()
        ns.db.detailWindow.height = f:GetHeight()
        self:UpdatePosition()
        if self._lastTotalH then self:UpdateScroll(self._lastTotalH) end
    end)

    f:HookScript("OnSizeChanged", function()
        if self._lastTotalH then
            local viewH = sc:GetHeight()
            local maxScroll = math.max(0, self._lastTotalH - viewH)
            sb:SetMinMaxValues(0, maxScroll)
            if self._lastTotalH > viewH then inner:SetWidth(sc:GetWidth() - 5) else inner:SetWidth(sc:GetWidth()) end
        end
        if self.RefreshValuePriorities then self:RefreshValuePriorities() end
    end)
    self.frame      = f
    self.content    = inner
    self.scrollFrame = sc
    self.scrollBar  = sb
    self.rows       = {}
    self:UpdateLockState()
    tinsert(UISpecialFrames, "LightDamageDetail")

    self:ApplyPreviewLayer()

    f:SetScript("OnShow", function() self:UpdatePosition() end)

    f:Hide()
end

function DV:SetPreviewLayer(active)
    self._previewLayerActive = active and true or false
    self:ApplyPreviewLayer()
end

function DV:UpdateLockState()
    local locked=ns.db and ns.db.window and ns.db.window.locked
    if self.frame then
        if locked then self.frame:StopMovingOrSizing(); self._resizing=false end
        self.frame:SetMovable(not locked)
        self.frame:SetResizable(not locked)
    end
    if self.resizeHandle then self.resizeHandle:SetShown(not locked) end
end

function DV:ApplyPreviewLayer()
    local f = self.frame
    if not f then return end
    if self._previewLayerActive then
        if not self._prePreviewLayer then
            self._prePreviewLayer = { strata = f:GetFrameStrata(), level = f:GetFrameLevel() }
        end
        f:SetFrameStrata(PREVIEW_STRATA)
        f:SetFrameLevel(self._prePreviewLayer.level or 20)
    elseif self._prePreviewLayer then
        f:SetFrameStrata(self._prePreviewLayer.strata or "HIGH")
        f:SetFrameLevel(self._prePreviewLayer.level or 20)
        self._prePreviewLayer = nil
    end
end

-- ============================================================
-- 动态更新位置 (智能贴靠)
-- ============================================================
function DV:UpdatePosition()
    if not self.frame then return end
    local uiFrame = ns.UI and ns.UI.frame
    
    -- 如果主窗口不存在或未显示，直接居中
    if not uiFrame or not uiFrame:IsShown() then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER")
        return
    end

    local screenW = UIParent:GetWidth()
    local uiRight = uiFrame:GetRight() or 0
    local uiTop   = uiFrame:GetTop() or 0
    
    local dw = self.frame:GetWidth()
    local dh = self.frame:GetHeight()

    -- 规则1 & 2: 默认右侧。如果主窗口太靠右，空间不够放详情面板，则放左侧
    local putRight = true
    if (uiRight + dw + 4) > screenW then
        putRight = false
    end

    -- 规则1 & 3: 默认顶部对齐。如果主窗口太靠下，详情面板向下展开会超出屏幕底部，则改为底部对齐
    local alignTop = true
    if (uiTop - dh) < 0 then
        alignTop = false
    end

    -- 规则4: 执行定位，彻底覆盖旧位置
    self.frame:ClearAllPoints()
    if putRight then
        if alignTop then
            self.frame:SetPoint("TOPLEFT", uiFrame, "TOPRIGHT", 4, 0)
        else
            self.frame:SetPoint("BOTTOMLEFT", uiFrame, "BOTTOMRIGHT", 4, 0)
        end
    else
        if alignTop then
            self.frame:SetPoint("TOPRIGHT", uiFrame, "TOPLEFT", -4, 0)
        else
            self.frame:SetPoint("BOTTOMRIGHT", uiFrame, "BOTTOMLEFT", -4, 0)
        end
    end
end

-- ============================================================
-- 应用动态外观主题
-- ============================================================
function DV:ApplyTheme()
    if not self.frame then return end
    local dbW = ns.db and ns.db.window or {}
    
    -- 1. 同步背景颜色
    local bg = dbW.bgColor or {0.02, 0.02, 0.025, 0.58}
    self.frame:SetBackdropColor(unpack(bg))
    
    -- 2. 同步标题栏颜色 (ThemeColor)
    local tc = dbW.themeColor or {0, 0, 0, 1}
    self.titleBg:SetColorTexture(unpack(tc))
    
    -- 3. ★ 使用全新 DetailDisplay 字体同步
    local _, _, _, font, fSz, fOut, fShad = self:GetBarConfig()
    fOut = ns.NormalizeFontOutline and ns:NormalizeFontOutline(fOut) or fOut
    local function _applyFont(fs, sz) ns.UI:ApplyFont(fs,font,sz,fOut,fShad) end
    
    if self.titleText then _applyFont(self.titleText, fSz + 1); self:SetDetailTextColor(self.titleText) end
    if self.rawTitleText then _applyFont(self.rawTitleText,fSz+1); self:SetDetailTextColor(self.rawTitleText) end
    if self.backText then _applyFont(self.backText, fSz + 4) end
    if self.closeText then _applyFont(self.closeText, fSz + 2) end
    
    for _, r in ipairs(self.rows) do
        _applyFont(r.name, fSz)
        _applyFont(r.rawName,fSz)
        _applyFont(r.value, fSz)
        _applyFont(r.rawValue,fSz)
        self:SetDetailTextColor(r.name)
        self:SetDetailTextColor(r.rawName)
        self:SetDetailTextColor(r.value)
        self:SetDetailTextColor(r.rawValue)
    end
end

local function IsSecret(value)
    local gateway = ns.DamageMeterGateway
    if gateway then return not gateway:IsAccessible(value) end
    return issecretvalue and issecretvalue(value) or false
end

local function OpaqueOr(value,fallback)
    if IsSecret(value) then return value end
    if value==nil or value=="" then return fallback end
    return value
end

function DV:SetNamedTitle(name,class,mode,titleSuffix)
    local shown=ns:DisplayName(OpaqueOr(name,"?"))
    if IsSecret(shown) then
        self.titleText:Hide(); self.rawTitleText:Show(); self.rawTitleText:SetText(shown)
        return
    end
    self.rawTitleText:Hide(); self.titleText:Show()
    local rawModeName=ns.MODE_NAMES[mode] or mode
    local modeName=L[rawModeName] or rawModeName
    self.titleText:SetFormattedText(L.PLAYER_MODE_BREAKDOWN_TITLE_FORMAT,ns:GetClassHex(class),shown,modeName,titleSuffix or "")
end

-- ============================================================
-- 滚动条高度更新
-- ============================================================
function DV:UpdateScroll(totalH)
    self._lastTotalH = totalH
    self.content:SetHeight(math.max(10, totalH))

    local viewH    = self.scrollFrame:GetHeight()
    local maxScroll = math.max(0, totalH - viewH)
    self.scrollBar:SetMinMaxValues(0, maxScroll)

    if maxScroll > 0 then
        self.scrollBar:Show()
        self.content:SetWidth(self.scrollFrame:GetWidth() - 5)
    else
        self.scrollBar:Hide()
        self.scrollBar:SetValue(0)
        self.content:SetWidth(self.scrollFrame:GetWidth())
    end
    self:RefreshValuePriorities()
end

-- ============================================================
-- 行管理
-- ============================================================
function DV:GetRow(idx)
    if self.rows[idx] then return self.rows[idx] end
    local r = {}

    r.frame = CreateFrame("Button", nil, self.content)
    r.frame:EnableMouse(true)
    r.frame:Hide()

    r.bg = r.frame:CreateTexture(nil, "BACKGROUND")
    r.fill = CreateFrame("StatusBar", nil, r.frame)
    r.fill:SetMinMaxValues(0, 1); r.fill:SetValue(0)

    -- ★ 核心修复：创建一个专门用于放图标和文字的子框架，并强行拔高它的渲染层级
    r.textFrame = CreateFrame("Frame", nil, r.frame)
    r.textFrame:SetFrameLevel(r.fill:GetFrameLevel() + 2)

    -- ★ 以下的 icon, name, value 统统挂载到新创建的 textFrame 上
    r.icon = r.textFrame:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:Hide()

    -- 先创建右侧的数值区域（宽度自适应）
    r.value = r.textFrame:CreateFontString(nil, "OVERLAY")
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetWidth(118)
    r.value:SetJustifyH("RIGHT")
    r.value:SetWordWrap(false); if r.value.SetMaxLines then r.value:SetMaxLines(1) end
    r.value:SetTextColor(1, 1, 1)
    r.rawValue = r.textFrame:CreateFontString(nil,"OVERLAY")
    r.rawValue:SetPoint("RIGHT",-4,0); r.rawValue:SetWidth(118); r.rawValue:SetJustifyH("RIGHT"); r.rawValue:SetWordWrap(false); if r.rawValue.SetMaxLines then r.rawValue:SetMaxLines(1) end; r.rawValue:SetTextColor(1,1,1); r.rawValue:Hide()

    -- 新增一个受限制的视觉裁剪框，右边界死死锚定在数值的前方 8 像素处
    r.nameClipFrame = CreateFrame("Frame", nil, r.textFrame)
    r.nameClipFrame:SetPoint("TOP", r.textFrame, "TOP")
    r.nameClipFrame:SetPoint("BOTTOM", r.textFrame, "BOTTOM")
    r.nameClipFrame:SetPoint("LEFT", r.textFrame, "LEFT", 0, 0)
    r.nameClipFrame:SetPoint("RIGHT", r.value, "LEFT", -8, 0) 
    r.nameClipFrame:SetClipsChildren(true) -- 开启裁剪：超出框范围的字直接一刀切

    -- 名字挂载到裁剪框上，解除本身的宽度限制
    r.name = r.nameClipFrame:CreateFontString(nil, "OVERLAY")
    r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.name:SetTextColor(1, 1, 1)
    r.rawName = r.nameClipFrame:CreateFontString(nil,"OVERLAY")
    r.rawName:SetJustifyH("LEFT"); r.rawName:SetWordWrap(false); r.rawName:SetTextColor(1,1,1); r.rawName:Hide()

    -- 悬停的高亮材质可以留在原底板上
    r.hl = r.frame:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)

    self.rows[idx] = r
    return r
end

function DV:ClearRows()
    for _, r in ipairs(self.rows) do
        r.frame:Hide()
        r.icon:Hide()
        r.name:Show(); r.rawName:Hide(); r.rawName:SetText("")
        r.fill:SetMinMaxValues(0, 1)
        r.fill:SetValue(0)
        r.frame:SetScript("OnEnter", nil)
        r.frame:SetScript("OnLeave", nil)
        r.value:Show(); r.rawValue:Hide(); r.rawValue:SetText("")
    end
end

function DV:PlaceRow(idx, yOff, h, bgOverride, thickness, vOffset)
    local r = self:GetRow(idx)
    r.frame:ClearAllPoints()
    r.frame:SetPoint("TOPLEFT",  self.content, "TOPLEFT",  0,  yOff)
    r.frame:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -2, yOff)
    r.frame:SetHeight(h)
    
    thickness = thickness or h
    vOffset = vOffset or 0
    
    r.icon:SetSize(h - 2, h - 2)
    r.icon:ClearAllPoints()
    r.icon:SetPoint("LEFT", r.textFrame, "LEFT", 3, 0)
    
    r.bg:ClearAllPoints()
    r.bg:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMLEFT", 0, vOffset)
    r.bg:SetPoint("BOTTOMRIGHT", r.frame, "BOTTOMRIGHT", 0, vOffset)
    r.bg:SetHeight(thickness)
    
    r.fill:ClearAllPoints()
    r.fill:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMLEFT", 0, vOffset)
    r.fill:SetPoint("BOTTOMRIGHT", r.frame, "BOTTOMRIGHT", 0, vOffset)
    r.fill:SetHeight(thickness)
    
    r.textFrame:ClearAllPoints()
    r.textFrame:SetAllPoints(r.frame)

    local bgc = bgOverride or ROW_BG[(idx % 2) + 1]
    r.bg:SetColorTexture(unpack(bgc))

    r.icon:Hide()
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r.nameClipFrame, "LEFT", 6, 0)
    r.rawName:ClearAllPoints(); r.rawName:SetPoint("LEFT",r.nameClipFrame,"LEFT",6,0)

    r.fill:SetMinMaxValues(0, 1)
    r.fill:SetValue(0)
    r.frame:Show()

    local _, _, _, font, fSz, fOut, fShad = self:GetBarConfig()
    fOut = ns.NormalizeFontOutline and ns:NormalizeFontOutline(fOut) or fOut
    local function _applyFont(fs, sz) ns.UI:ApplyFont(fs,font,sz,fOut,fShad) end
    _applyFont(r.name, fSz)
    _applyFont(r.rawName,fSz)
    _applyFont(r.value, fSz)
    _applyFont(r.rawValue,fSz)
    self:SetDetailTextColor(r.name)
    self:SetDetailTextColor(r.rawName)
    self:SetDetailTextColor(r.value)
    self:SetDetailTextColor(r.rawValue)

    return r
end

local function GetSafeDetailTextWidth(fs)
    if not fs then return nil end
    local getter = fs.GetUnboundedStringWidth or fs.GetStringWidth
    if not getter then return nil end
    local ok, width = pcall(getter, fs)
    if ok and type(width) == "number" then return width end
    return nil
end

-- Keep the complete right-hand value whenever the row has enough room.  The
-- name lives in a clipped frame whose right edge follows this column, so names
-- yield before values without changing either font's scale.
function DV:PrioritizeRowValue(r, isSecret)
    if not r or not r.frame or not r.value then return end
    local rowW = r.frame:GetWidth() or 0
    local maxValueW = math.max(1, rowW - 12)
    local wanted
    if isSecret then
        -- The protected value is already localized and integer-abbreviated by
        -- Blizzard. Reserve a fixed column without measuring the opaque text.
        wanted = math.min(118,maxValueW)
    else
        wanted = (GetSafeDetailTextWidth(r.value) or 0) + 8
    end
    local valueW = math.max(1, math.min(math.ceil(wanted), math.floor(maxValueW)))
    r.value:SetWidth(valueW)
    r._valueIsSecret = isSecret and true or false
end

function DV:RefreshValuePriorities()
    if not self.rows then return end
    for _, r in ipairs(self.rows) do
        if r.frame and r.frame:IsShown() then
            self:PrioritizeRowValue(r, r._valueIsSecret)
        end
    end
end

local function setNameWithIcon(r, iconTex, text)
    r.rawName:Hide(); r.name:Show()
    local iconIsSecret=IsSecret(iconTex)
    if iconIsSecret or iconTex ~= nil then
        local ok=pcall(r.icon.SetTexture,r.icon,iconTex)
        if ok then
            r.icon:Show()
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", r.nameClipFrame, "LEFT", ICON_W + 7, 0)
        else
            r.icon:Hide()
            r.name:ClearAllPoints(); r.name:SetPoint("LEFT",r.nameClipFrame,"LEFT",6,0)
        end
    else
        r.icon:Hide()
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r.nameClipFrame, "LEFT", 6, 0)
    end
    r.name:SetText(text)
end

local function setOpaqueNameWithIcon(r,iconTex,text)
    r.name:Hide(); r.rawName:Show()
    local iconIsSecret=IsSecret(iconTex)
    if iconIsSecret or iconTex ~= nil then
        local ok=pcall(r.icon.SetTexture,r.icon,iconTex)
        if ok then
            r.icon:Show()
            r.rawName:ClearAllPoints()
            r.rawName:SetPoint("LEFT",r.nameClipFrame,"LEFT",ICON_W+7,0)
        else
            r.icon:Hide()
            r.rawName:ClearAllPoints(); r.rawName:SetPoint("LEFT",r.nameClipFrame,"LEFT",6,0)
        end
    else
        r.icon:Hide()
        r.rawName:ClearAllPoints(); r.rawName:SetPoint("LEFT",r.nameClipFrame,"LEFT",6,0)
    end
    r.rawName:SetText(text)
end

local function GetSpellIcon(spellID)
    local idSecret=IsSecret(spellID)
    if not idSecret and not spellID then return nil end
    local ok, icon = pcall(function()
        if not idSecret and spellID == 0 then return nil end
        if C_Spell and C_Spell.GetSpellTexture then
            return C_Spell.GetSpellTexture(spellID)
        end
        if GetSpellTexture then
            return GetSpellTexture(spellID)
        end
        return nil
    end)
    if ok then return icon end
    return nil
end

-- ============================================================
-- 技能列表渲染
-- ============================================================
function DV:RenderSpellList(name, class, mode, spells, dur, titleSuffix, apiMaxAmount, hasSecretData)
    self._lastRenderArgs = { type = "spell", args = {name, class, mode, spells, dur, titleSuffix, apiMaxAmount, hasSecretData} }
    self:EnsureCreated()
    self.frame:Show()
    self:ApplyTheme()
    self:ClearRows()

    -- print("|cffff00ff[LD DEBUG RenderSpellList]|r frameShown=", self.frame:IsShown(), "spells=", #spells, "apiMaxAmount=", type(apiMaxAmount))

    self:SetNamedTitle(name,class,mode,titleSuffix)

    local bh, gap, alpha, _, _, _, _, thickness, vOffset, texPath = self:GetBarConfig()
    local currentY = 0

    if #spells == 0 then
        local r = self:PlaceRow(1, 0, bh, nil, thickness, vOffset)
        r.name:SetText(L.COLORED_NO_SPELL_DATA)
        r.value:SetText("")
        self:PrioritizeRowValue(r, false)
        self:UpdateScroll(bh + 5)
        return
    end

    local maxV
    if hasSecretData then
        -- ★ 战斗中：用 API 提供的 secret maxAmount（和暴雪做法一致）
        maxV = apiMaxAmount
    else
        maxV = spells[1] and spells[1].value or 0
        if maxV == 0 then maxV = 1 end
    end

    for i, sp in ipairs(spells) do
        local r = self:PlaceRow(i, currentY, bh, nil, thickness, vOffset)
        currentY = currentY - (bh + gap)

        r.fill:SetStatusBarTexture(texPath)
        pcall(function()
            r.fill:SetMinMaxValues(0, maxV)
            if sp.isSecretAmount then r.fill:SetValue(sp.rawAmount) else r.fill:SetValue(sp.value) end
        end)

        -- ★ 颜色：魔法学派颜色，透明度跟主界面统一
        local sc2 = ns.SCHOOL_COLORS and ns.SCHOOL_COLORS[sp.school] or {0.5, 0.5, 0.7}
        if sp.isPet then sc2 = {0.28, 0.65, 0.28} end
        r.fill:SetStatusBarColor(self:GetDetailBarColor(sc2, alpha))

        local sn = sp.name or "?"
        local nc = sp.isPet and "|cff55bb55" or "|cffffffff"
        
        if sp.isAvoidable then
            sc2 = {0.85, 0.70, 0.15}
            sn = sn .. " |cffffcc00" .. L.AVOIDABLE_MARKER .. "|r"
        end
        
        -- 【先】设定右侧值文字，让它把占位大小确定下来
        local isCount = (mode == "interrupts" or mode == "dispels")
        local valueIsSecret = sp.isSecretAmount or sp.isSecretRate
        local valStr
        if valueIsSecret then
            valStr = nil
        elseif isCount then
            valStr = string.format(L.COLORED_COUNT_TIMES_FORMAT, sp.value)
        elseif sp.hasRate and ns.MODE_UNITS[mode] then
            -- ★ 顺序与主界面数据条一致：总量 (每秒)
            valStr = string.format("%s (%s)", ns:FormatNumber(sp.value), ns:FormatNumber(sp.perSec))
        else
            valStr = ns:FormatNumber(sp.value)
        end
        
        if valueIsSecret then
            r.value:Hide(); r.rawValue:Show()
            local totalText
            if sp.isSecretAmount then totalText=GetOpaqueAbbreviatedNumber(sp.rawAmount)
            else totalText=ns.AbbrevNumber(sp.value) end
            if isCount then
                r.rawValue:SetFormattedText("%s%s",totalText,L.COUNT_SUFFIX)
            elseif sp.hasRate and ns.MODE_UNITS[mode] then
                local rateText
                if sp.isSecretRate then rateText=GetOpaqueAbbreviatedNumber(sp.rawRate)
                else rateText=ns.AbbrevNumber(sp.rate) end
                r.rawValue:SetFormattedText("%s (%s)",totalText,rateText)
            else
                r.rawValue:SetText(totalText)
            end
        else
            r.rawValue:Hide(); r.value:Show()
            local pctStr = string.format("%.1f%%", sp.percent or 0)
            r.value:SetText(valStr .. " |cffaaaaaa" .. pctStr .. "|r")
        end
        self:PrioritizeRowValue(r, valueIsSecret)

        -- 【后】再赋予左侧名字，此时超出裁剪框的部分会被完美隐藏
        local displaySpellID=sp.spellID
        if sp.isSecretSpellID then displaySpellID=sp.rawSpellID end
        if sp.isSecretName then
            setOpaqueNameWithIcon(r,GetSpellIcon(displaySpellID),sp.rawName)
        else
            setNameWithIcon(r, GetSpellIcon(displaySpellID), nc .. sn .. "|r")
        end

        local sp_c = sp
        r.frame:SetScript("OnEnter", function(fw)
            local useOpaque = sp_c.isSecretSpellID or sp_c.isSecretName
                or sp_c.isSecretAmount or sp_c.isSecretRate
            local tip
            if ns.PrivateTooltip then
                tip = useOpaque and ns.PrivateTooltip:GetOpaque() or ns.PrivateTooltip:Get()
            elseif useOpaque then
                return
            else
                tip = GameTooltip
            end
            tip:SetOwner(fw, "ANCHOR_RIGHT")
            if not useOpaque then pcall(function()
                if not sp_c.isSecretSpellID and sp_c.spellID and sp_c.spellID > 0 then
                    tip:SetSpellByID(sp_c.spellID)
                end
            end) end
            if not tip:NumLines() or tip:NumLines() == 0 then
                if sp_c.isSecretName then
                    tip:AddLine(sp_c.rawName)
                else
                    local nameOk, n = pcall(tostring, sp_c.name or "?")
                    tip:AddLine(nameOk and n or "?")
                end
            end
            tip:AddLine(" ")
            
            -- Tooltip 内的安全渲染
            if sp_c.isSecretAmount and useOpaque then
                tip:AddDoubleLine(L.TOTAL, GetOpaqueAbbreviatedNumber(sp_c.rawAmount), 0.7, 0.7, 0.7, 1, 1, 1)
            elseif not sp_c.isSecretAmount then
                tip:AddDoubleLine(L.TOTAL, ns:FormatNumber(sp_c.value), 0.7, 0.7, 0.7, 1, 1, 1)
            end

            if sp_c.isSecretRate and useOpaque and ns.MODE_UNITS[mode] then
                tip:AddDoubleLine(L.PER_SECONDS, GetOpaqueAbbreviatedNumber(sp_c.rawRate), 0.7,0.7,0.7,1,0.85,0)
            elseif not sp_c.isSecretRate and ns.MODE_UNITS[mode] then
                local visibleRate=sp_c.hasRate and (sp_c.rate or sp_c.perSec) or nil
                if visibleRate then tip:AddDoubleLine(L.PER_SECONDS,string.format("%.1f",visibleRate),0.7,0.7,0.7,1,0.85,0) end
            end

            if (sp_c.overhealing or 0) > 0 then
                tip:AddDoubleLine(L.OVERHEAL, ns:FormatNumber(sp_c.overhealing), 0.7, 0.7, 0.7, 0.8, 0.4, 0.4)
            end
            tip:Show()
        end)
        r.frame:SetScript("OnLeave", function() if ns.PrivateTooltip then ns.PrivateTooltip:Hide() else GameTooltip:Hide() end end)
    end

    self:UpdateScroll(math.abs(currentY))
end

-- ============================================================
-- 技能细分（脱战后）
-- ============================================================
function DV:ShowSpellBreakdown(guid, name, class, mode, seg)
    local displayMode = (mode == "deaths") and "damage" or mode
    local seg = seg or (ns.Segments and ns.Segments:GetViewSegment())
    local dur    = ns.Analysis and ns.Analysis:GetSegmentDuration(seg) or 0
    local spells = self:GetSpellBreakdownExt(seg, guid, displayMode)
    self:RenderSpellList(name, class, displayMode, spells, dur, "")
end

function DV:ShowSpellBreakdownFromAPI(sourceGUID,sourceCreatureID,name,class,mode,sessionType,sessionID,isLocalPlayer)
    if isLocalPlayer then
        sourceGUID=UnitGUID("player")
        sourceCreatureID=nil
    end
    -- 走通用 dmType 映射，承伤/打断/驱散/敌人承伤一并支持
    local dmType = ns.UI and ns.UI.MODE_TO_DM and ns.UI.MODE_TO_DM[mode]
    if not dmType then
        self:EnsureCreated(); self.frame:Show(); self:ApplyTheme()
        self:RenderSpellList(OpaqueOr(name,"?"), class, mode, {}, 0, "")
        self._lastRenderArgs = {
            type = "spellAPI",
            args = {sourceGUID,sourceCreatureID,name,class,mode,sessionType,sessionID,isLocalPlayer}
        }
        return
    end

    -- 路由：有 sessionID 走 FromID(虚拟段/归档段)，否则走 FromType(current/overall)
    local gateway = ns.DamageMeterGateway
    local srcData,srcState
    if sessionID then
        if gateway then srcData,srcState=gateway:GetRawSource(nil,sessionID,dmType,sourceGUID,sourceCreatureID) end
    else
        local sType = sessionType or Enum.DamageMeterSessionType.Current
        if gateway then srcData,srcState=gateway:GetRawSource(sType,nil,dmType,sourceGUID,sourceCreatureID) end
    end

    local rawSpells
    local sourceReadable=type(srcData)=="table" and gateway and gateway:IsTableAccessible(srcData)
    if sourceReadable then
        local ok,value=pcall(function() return srcData.combatSpells end)
        if ok and type(value)=="table" and gateway:IsTableAccessible(value) then rawSpells=value end
    end
    if not rawSpells then
        if ns.state.inCombat or IsSecret(name) or IsSecret(sourceGUID) then
            self:ShowCombatLocked(OpaqueOr(name,"?"))
            self._lastRenderArgs={type="spellAPI",args={sourceGUID,sourceCreatureID,name,class,mode,sessionType,sessionID,isLocalPlayer}}
            return
        end
        self:EnsureCreated(); self.frame:Show(); self:ApplyTheme()
        self:RenderSpellList(OpaqueOr(name,"?"), class, mode, {}, 0, "")
        self._lastRenderArgs = {
            type = "spellAPI",
            args = {sourceGUID,sourceCreatureID,name,class,mode,sessionType,sessionID,isLocalPlayer}
        }
        return
    end

    local spells = {}
    local isSecret = false

    -- 单次遍历官方技能行。宠物标记只接受 12.1 的
    -- combatSpellDetails.isPet；creatureName 本身不证明宠物关系。
    for _, sp in ipairs(rawSpells) do
        if type(sp)=="table" and gateway:IsTableAccessible(sp) then
        local amtOk, amt = pcall(function() return sp.totalAmount end)
        if amtOk then
            local isSec = IsSecret(amt)
            if isSec then isSecret = true end
            if isSec or type(amt)=="number" then

            local spellIDSafe
            pcall(function() spellIDSafe=sp.spellID end)
            local idSecret=IsSecret(spellIDSafe)
            local spellName,rawSpellName,isSecretName="?",nil,false
            if (idSecret or type(spellIDSafe)=="number") and C_Spell and C_Spell.GetSpellName then
                local nameOk,nameVal=pcall(C_Spell.GetSpellName,spellIDSafe)
                if nameOk and IsSecret(nameVal) then rawSpellName=nameVal; isSecretName=true
                elseif nameOk and type(nameVal)=="string" then spellName=nameVal
                elseif not idSecret then spellName="spell:"..tostring(spellIDSafe) end
            elseif not idSecret and type(spellIDSafe)=="number" then
                spellName="spell:"..tostring(spellIDSafe)
            end

            local rateOk,rateRaw=pcall(function() return sp.amountPerSecond end)
            local rateSecret=rateOk and IsSecret(rateRaw) or false
            local hasRate=rateOk and (rateSecret or type(rateRaw)=="number") or false

            local isPet, creatureName = false, nil
            local details, detailsState = gateway:ReadTableField(sp, "combatSpellDetails")
            if detailsState == gateway.ACCESSIBLE then
                local petFlag, petState = gateway:ReadField(details, "isPet")
                if petState == gateway.ACCESSIBLE and petFlag == true then
                    isPet = true
                    local unitName, unitNameState = gateway:ReadField(details, "unitName")
                    if unitNameState == gateway.ACCESSIBLE and type(unitName) == "string"
                        and unitName ~= "" then creatureName = unitName end
                end
            end
            if isPet and not creatureName then
                local cnVal, cnState = gateway:ReadField(sp, "creatureName")
                if cnState == gateway.ACCESSIBLE and type(cnVal) == "string"
                    and cnVal ~= "" then creatureName = cnVal end
            end
            if isPet and not isSecretName then
                if creatureName then spellName = creatureName .. ": " .. spellName end
            end

            -- 可规避标记
            local isAvoidable = false
            local avoidableRaw
            pcall(function() avoidableRaw=sp.isAvoidable end)
            if not IsSecret(avoidableRaw) then isAvoidable=avoidableRaw==true end

            local publicSpellID = nil
            if not idSecret then publicSpellID = spellIDSafe end
            local rawSpellID = nil
            if idSecret then rawSpellID = spellIDSafe end
            local rawRate = nil
            if rateSecret then rawRate = rateRaw end
            local entry={
                spellID     = publicSpellID,
                rawSpellID  = rawSpellID,
                isSecretSpellID=idSecret,
                name        = spellName,
                rawName     = rawSpellName,
                isSecretName=isSecretName,
                school      = nil,
                value       = isSec and 0 or amt,
                isSecretAmount=isSec,
                rate        = rateSecret and 0 or (hasRate and rateRaw or 0),
                rawRate     = rawRate,
                isSecretRate=rateSecret,
                hasRate     = hasRate,
                percent     = 0,
                isPet       = isPet,
                isAvoidable = isAvoidable,
            }
            if isSec then entry.rawAmount=amt end
            table.insert(spells,entry)
            end
        end
        end
    end

    -- 排序与百分比
    if not isSecret then
        table.sort(spells, function(a, b) return a.value > b.value end)
        local total
        local totalOK=pcall(function() total=srcData.totalAmount end)
        local totalIsSecret=totalOK and IsSecret(total)
        if totalIsSecret then isSecret=true end
        if totalOK and not totalIsSecret and type(total)=="number" and total > 0 then
            for _, s in ipairs(spells) do
                s.percent = s.value / total * 100
            end
        end
    end

    -- Duration is retained in the renderer signature for saved-data
    -- compatibility, but live API detail never substitutes a local timer.
    local dur = nil

    local apiMaxAmount=nil
    if isSecret then pcall(function() apiMaxAmount=srcData.maxAmount end) end

    self:EnsureCreated(); self.frame:Show(); self:ApplyTheme()
    self:RenderSpellList(OpaqueOr(name,"?"), class, mode, spells, dur, "", apiMaxAmount,isSecret)
    -- RenderSpellList records a local snapshot by default. Restore the API
    -- locator after rendering so periodic refreshes re-read live details.
    self._lastRenderArgs = {
        type = "spellAPI",
        args = {sourceGUID,sourceCreatureID,name,class,mode,sessionType,sessionID,isLocalPlayer}
    }
end

-- ============================================================
-- 战斗中队友数据受保护提示
-- ============================================================
function DV:ShowCombatLocked(safeName)
    self._lastRenderArgs = { type = "combat", args = {safeName} }
    self:EnsureCreated()
    self.frame:Show()
    self:ApplyTheme()
    self:ClearRows()
    local shown=ns:DisplayName(OpaqueOr(safeName,L.UNKNOWN))
    if IsSecret(shown) then self.titleText:Hide(); self.rawTitleText:Show(); self.rawTitleText:SetText(shown)
    else self.rawTitleText:Hide(); self.titleText:Show(); self.titleText:SetFormattedText(L.SPELL_BREAKDOWN_TITLE_FORMAT,shown) end
    
    local bh, gap, _, _, _, _, _, thickness, vOffset = self:GetBarConfig()
    local r = self:PlaceRow(1, 0, bh * 2, nil, thickness * 2, vOffset)
    
    r.name:SetText("|cffaaaaaa"..L.COMBAT_DATA_LOCKED.."|r")
    
    r.name:SetWidth(300)
    r.value:SetText("")
    self:PrioritizeRowValue(r, false)
    self:UpdateScroll(bh * 2 + 5)
end

-- ============================================================
-- 获取技能细分数据（从数据结构）
-- ============================================================
function DV:GetSpellBreakdownExt(seg, guid, mode)
    if not seg or not guid then return {} end

    -- ★ 架构升级：预留扩展模块路由 (敌人承伤 / 目标明细)
    -- 后续可以直接在这里拦截，并遍历 combatSpellDetails 来重组数据
    if mode == "enemyDamageTaken" or mode == "targetBreakdown" then
        -- TODO: 等待新增模块实现
        return {}
    end

    local pd = seg.players[guid]
    if not pd then return {} end

    -- 原有伤害/治疗逻辑交由 Analysis 处理
    if mode == "damage" or mode == "healing" then
        return ns.Analysis and ns.Analysis:GetSpellBreakdown(seg, guid, mode) or {}
    end

    -- 承伤模块：彻底剔除无效的暴击/极值字段
    if mode == "damageTaken" then
        if pd.damageTakenSpells and next(pd.damageTakenSpells) then
            local result = {}
            for spellKey, sd in pairs(pd.damageTakenSpells) do
                local spellID = sd.spellID or sd.id or spellKey
                if (sd.damage or 0) > 0 then
                    table.insert(result, {
                        spellID     = spellID,
                        name        = sd.name or ("spell:" .. spellID),
                        school      = sd.school,
                        value       = sd.damage,
                        hits        = sd.hits,
                        isAvoidable = sd.isAvoidable,
                    })
                end
            end
            table.sort(result, function(a, b) return a.value > b.value end)
            local tot = pd.damageTaken or 0
            for _, r2 in ipairs(result) do
                r2.percent = tot > 0 and (r2.value / tot * 100) or 0
            end
            return result
        else
            if (pd.damageTaken or 0) > 0 then
                return {{ spellID=0, name=L.TOTAL_DAMAGE_TAKEN, school=nil, value=pd.damageTaken,
                    hits=0, percent=100 }}
            end
        end
    end

    -- 打断/驱散模块：彻底剔除无效的暴击/极值字段
    if mode == "interrupts" or mode == "dispels" then
        local spellTable = (mode == "interrupts") and pd.interruptSpells or pd.dispelSpells
        local totalVal   = (mode == "interrupts") and pd.interrupts or pd.dispels
        
        -- 如果有具体的技能明细记录，则遍历显示
        if spellTable and next(spellTable) then
            local result = {}
            for spellKey, sd in pairs(spellTable) do
                local spellID = sd.spellID or sd.id or spellKey
                local amt = sd.damage or sd.hits or 0
                if amt > 0 then
                    local sName = sd.name or ("spell:" .. spellID)
                    
                    if mode == "interrupts" and spellID == 32747 then
                        sName = L.CC_INTERRUPTS
                    end
                    
                    table.insert(result, {
                        spellID     = spellID,
                        name        = sName,
                        school      = sd.school,
                        value       = amt,
                        hits        = amt,
                    })
                end
            end
            
            table.sort(result, function(a, b) return a.value > b.value end)
            local tot = totalVal or 0
            for _, r2 in ipairs(result) do
                r2.percent = tot > 0 and (r2.value / tot * 100) or 0
            end
            return result
        else
            -- 兜底逻辑
            if (totalVal or 0) > 0 then
                local fallbackName = (mode == "interrupts") and L.TOTAL_INTERRUPTS or L.TOTAL_DISPELS
                return {{ spellID=0, name=fallbackName, school=nil, value=totalVal,
                    hits=0, percent=100 }}
            end
        end
    end

    return {}
end

-- ============================================================
-- 死亡事件详情
-- ============================================================
function DV:ShowDeathDetail(death)
    self._lastRenderArgs = { type = "death", args = {death} }
    self:EnsureCreated()
    self.frame:Show()
    self:ApplyTheme()
    self:ClearRows()
    if not death then return end

    local selfTag = death.isSelf and (" "..L.COLORED_OWN_DEATH) or ""
    if IsSecret(death.playerName) then
        self.titleText:Hide(); self.rawTitleText:Show(); self.rawTitleText:SetText(death.playerName)
    elseif type(death.playerName) == "string" and death.playerName ~= "" then
        local playerShown = ns:DisplayName(death.playerName)
        self.rawTitleText:Hide(); self.titleText:Show()
        self.titleText:SetText(ns:GetClassHex(death.playerClass)..playerShown.."|r"..selfTag..L.DEATH_DETAILS_TITLE_SUFFIX)
    else
        self.rawTitleText:Hide(); self.titleText:Show(); self.titleText:SetText(L.DEATHS)
    end

    local events     = death.events or {}
    local evReversed = {}
    for i = #events, 1, -1 do
        table.insert(evReversed, events[i])
    end

    local bh, gap, alpha, _, _, _, _, thickness, vOffset, texPath = self:GetBarConfig()
    local ri        = 0
    local currentY  = 0
    local deathTime = events[#events] and events[#events].time or nil

    -- 致命一击行
    if type(death.killingAbility) == "string" and death.killingAbility ~= "" then
        ri = ri + 1
        local hr = self:PlaceRow(ri, currentY, bh + 4, BG_FATAL, thickness + 4, vOffset)
        currentY = currentY - (bh + 4 + gap)
        hr.fill:SetStatusBarTexture(texPath)
        hr.fill:SetMinMaxValues(0, 1)
        hr.fill:SetValue(1)
        hr.fill:SetStatusBarColor(self:GetDetailBarColor({0.70, 0.04, 0.04, 0.55}, 0.55))
        setNameWithIcon(hr,
            GetSpellIcon((evReversed[1] and not evReversed[1].isHeal) and evReversed[1].spellID or nil),
            L.COLORED_FATAL_PREFIX .. death.killingAbility
        )
        local killerShown = type(death.killerName) == "string" and death.killerName ~= ""
            and ns:DisplayName(death.killerName) or nil
        hr.rawValue:Hide(); hr.value:Show()
        hr.value:SetText(killerShown and (L.COLORED_KILLER_PREFIX .. killerShown) or "")
        self:PrioritizeRowValue(hr, false)
    end

    -- 分割线
    ri = ri + 1
    local sep = self:PlaceRow(ri, currentY, 15, BG_SECTION, 15, 0)
    currentY = currentY - (15 + gap)
    sep.fill:SetMinMaxValues(0, 1)
    sep.fill:SetValue(0)
    sep.name:SetText(L.EVENTS_BEFORE_DEATH_RECENT_OLD)
    sep.value:SetText(string.format(L.COLORED_ROW_COUNT_FORMAT, #evReversed))
    self:PrioritizeRowValue(sep, false)

    if #evReversed == 0 then
        ri = ri + 1
        local er = self:PlaceRow(ri, currentY, bh, nil, thickness, vOffset)
        currentY = currentY - (bh + gap)
        er.name:SetText(L.COLORED_NO_EVENT_DATA)
        er.value:SetText("")
        self:PrioritizeRowValue(er, false)
    end

    for idx, ev in ipairs(evReversed) do
        ri = ri + 1
        local r    = self:PlaceRow(ri, currentY, bh, nil, thickness, vOffset)
        currentY = currentY - (bh + gap)
        local isFatal = (idx == 1 and not ev.isHeal)

        local hpPct = type(ev.hpPercent) == "number"
            and math.min(1, math.max(0, ev.hpPercent / 100)) or nil
        r.fill:SetStatusBarTexture(texPath)
        r.fill:SetMinMaxValues(0, 1)
        if hpPct then r.fill:SetValue(hpPct); r.fill:Show()
        else r.fill:SetValue(0); r.fill:Hide() end

        local eventName = (type(ev.spellName) == "string" and ev.spellName ~= "" and ev.spellName)
            or (type(ev.eventType) == "string" and ev.eventType ~= "" and ev.eventType) or ""

        if ev.isHeal then
            r.fill:SetStatusBarColor(self:GetDetailBarColor({0.10, 0.50, 0.10}, alpha))
            r.bg:SetColorTexture(unpack(ROW_BG[(ri % 2) + 1]))
            setNameWithIcon(r, GetSpellIcon(ev.spellID), eventName)
        elseif isFatal then
            r.bg:SetColorTexture(0.20, 0.03, 0.03, 0.96)
            r.fill:SetStatusBarColor(self:GetDetailBarColor({0.80, 0.04, 0.04}, alpha))
            setNameWithIcon(r, GetSpellIcon(ev.spellID),
                string.format("|cffff7755%s|r", eventName))
        else
            r.fill:SetStatusBarColor(self:GetDetailBarColor({0.60, 0.08, 0.08}, alpha))
            setNameWithIcon(r, GetSpellIcon(ev.spellID), eventName)
        end

        local td = (type(deathTime) == "number" and type(ev.time) == "number")
            and (deathTime - ev.time) or nil
        local timeStr
        if type(td) == "number" and td < 0.05 then
            timeStr = L.COLORED_DEATH
        elseif type(td) == "number" then
            timeStr = string.format(L.COLORED_SECONDS_AGO_FORMAT, td)
        end
        local valueParts = {}
        if type(ev.amount) == "number" then
            valueParts[#valueParts + 1] = ev.isHeal
                and string.format("|cff44ee44+%s|r", ns:FormatNumber(math.abs(ev.amount)))
                or string.format("|cffff7777-%s|r", ns:FormatNumber(math.abs(ev.amount)))
        end
        if type(ev.hpPercent) == "number" then
            local hpColor = ev.isHeal and "44ee44" or (hpPct < 0.15 and "ff4444" or "bbbbbb")
            valueParts[#valueParts + 1] = string.format("|cff%s%.0f%%|r", hpColor, ev.hpPercent)
        end
        if timeStr then valueParts[#valueParts + 1] = timeStr end
        r.value:SetText(table.concat(valueParts, "  "))
        self:PrioritizeRowValue(r, false)

        local ev_c    = ev
        local td_c    = td
        local maxHP_c = ev.maxHP
        r.frame:SetScript("OnEnter", function(fw)
            local tip=(ns.PrivateTooltip and ns.PrivateTooltip:Get()) or GameTooltip
            tip:SetOwner(fw, "ANCHOR_RIGHT")
            if ev_c.spellID and ev_c.spellID > 0 then
                pcall(function() tip:SetSpellByID(ev_c.spellID) end)
            else
                local publicEventName = ev_c.spellName or ev_c.eventType
                if publicEventName then tip:AddLine(publicEventName) end
            end
            tip:AddLine(" ")
            if ev_c.isHeal and type(ev_c.amount) == "number" then
                tip:AddDoubleLine(L.HEALING_DONE,
                    ns:FormatNumber(math.abs(ev_c.amount)), 0.7, 0.7, 0.7, 0.3, 1, 0.3)
            elseif not ev_c.isHeal and type(ev_c.amount) == "number" then
                tip:AddDoubleLine(L.DAMAGE_DONE,
                    ns:FormatNumber(ev_c.amount), 0.7, 0.7, 0.7, 1, 0.3, 0.3)
                if type(ev_c.overkill) == "number" and ev_c.overkill > 0 then
                    tip:AddDoubleLine(L.OVERKILL,
                        ns:FormatNumber(ev_c.overkill), 0.7, 0.7, 0.7, 1, 0.5, 0)
                end
            end
            -- Public native GameTooltip is retained for the complete spell
            -- description.  An opaque source name is optional detail and must
            -- not be injected into GameTooltip's undocumented line storage.
            if not IsSecret(ev_c.srcName) and ev_c.srcName~=nil and ev_c.srcName~="" then
                tip:AddDoubleLine(L.SOURCE, ns:DisplayName(ev_c.srcName), 0.7, 0.7, 0.7, 1, 1, 1)
            end
            if type(ev_c.hp) == "number" and type(maxHP_c) == "number"
                and type(ev_c.hpPercent) == "number" then
                tip:AddDoubleLine(L.HP_REMAINING,
                    string.format("%s / %s (%.0f%%)",
                        ns:FormatNumber(ev_c.hp),
                        ns:FormatNumber(maxHP_c),
                        ev_c.hpPercent),
                    0.7, 0.7, 0.7, 1, 1, 1)
            end
            if type(td_c) == "number" and td_c >= 0.05 then
                tip:AddDoubleLine(L.TO_DEATH, string.format(L.SECONDS_FORMAT, td_c), 0.7, 0.7, 0.7, 1, 1, 1)
            end
            tip:Show()
        end)
        r.frame:SetScript("OnLeave", function() if ns.PrivateTooltip then ns.PrivateTooltip:Hide() else GameTooltip:Hide() end end)
    end

    -- 底部汇总行：只展示暴雪实际提供并可安全归档的字段。
    local hasDamageTotal = type(death.totalDamageTaken) == "number"
    local hasSpan = type(death.timeSpan) == "number" and death.timeSpan > 0
    if hasDamageTotal or hasSpan then
        ri = ri + 1
        local tr = self:PlaceRow(ri, currentY, bh + 4, BG_HEADER, thickness + 4, vOffset)
        currentY = currentY - (bh + 4 + gap)
        tr.fill:SetStatusBarTexture(texPath)
        tr.fill:SetMinMaxValues(0, 1)
        tr.fill:SetValue(1)
        tr.fill:SetStatusBarColor(self:GetDetailBarColor({0.04, 0.04, 0.08, 0.90}, 0.90))
        tr.name:SetText(L.DAMAGE_TAKEN_LABEL)
        local parts = {}
        if hasDamageTotal then
            parts[#parts + 1] = string.format("|cffff9966%s|r", ns:FormatNumber(death.totalDamageTaken))
        end
        if hasSpan then
            parts[#parts + 1] = string.format(L.COLORED_SPAN_SECONDS_FORMAT, death.timeSpan)
        end
        tr.value:SetText(table.concat(parts, "  "))
        self:PrioritizeRowValue(tr, false)
    end

    self:UpdateScroll(math.abs(currentY))
end

-- ============================================================
-- 接口
-- ============================================================
function DV:IsVisible() return self.frame and self.frame:IsShown() end

function DV:ShowEnemyDamageTakenDetail(enemyName, sources, totalDmg)
    self._lastRenderArgs = { type = "enemyDmgTaken", args = {enemyName, sources, totalDmg} }
    self:EnsureCreated()
    self.frame:Show()
    self:ApplyTheme()
    self:ClearRows()

    local shown=ns:DisplayName(OpaqueOr(enemyName,"?"))
    if IsSecret(shown) then self.titleText:Hide(); self.rawTitleText:Show(); self.rawTitleText:SetText(shown)
    else self.rawTitleText:Hide(); self.titleText:Show(); self.titleText:SetText(string.format(L.DAMAGE_TAKEN_SOURCE_TITLE_FORMAT,shown)) end

    local bh, gap, alpha, _, _, _, _, thickness, vOffset, texPath = self:GetBarConfig()
    local currentY = 0

    if not sources or #sources == 0 then
        local r = self:PlaceRow(1, 0, bh, nil, thickness, vOffset)
        r.name:SetText(L.COLORED_NO_DAMAGE_TAKEN_DATA); r.value:SetText("")
        self:PrioritizeRowValue(r, false)
        self:UpdateScroll(bh + 5); return
    end

    table.sort(sources, function(a, b) return a.amount > b.amount end)
    local maxV = sources[1].amount

    for i, src in ipairs(sources) do
        local r = self:PlaceRow(i, currentY, bh, nil, thickness, vOffset)
        currentY = currentY - (bh + gap)

        r.fill:SetStatusBarTexture(texPath)
        r.fill:SetMinMaxValues(0, maxV)
        r.fill:SetValue(src.amount)

        local classKey = type(src.class) == "string" and src.class or nil
        local ok, cc = pcall(ns.GetClassColor, ns, classKey)
        if not ok or not cc then cc = {0.5, 0.5, 0.5} end
        r.fill:SetStatusBarColor(self:GetDetailBarColor(cc, alpha))

        local nameOk, nameStr = pcall(ns.DisplayName, ns, src.name)
        r.name:SetText((nameOk and nameStr) or "")
        r.name:SetTextColor(cc[1], cc[2], cc[3])

        local totalSafe=(not IsSecret(totalDmg) and type(totalDmg)=="number") and totalDmg or 0
        local pct = totalSafe > 0 and (src.amount / totalSafe * 100) or 0
        r.value:SetText(string.format("%s  |cffaaaaaa%.0f%%|r", ns:FormatNumber(src.amount), pct))
        self:PrioritizeRowValue(r, false)

        r.frame:SetScript("OnEnter", nil)
        r.frame:SetScript("OnLeave", nil)
        r.frame:Show()
    end
    self:UpdateScroll(math.abs(currentY))
end

-- ============================================================
-- API 路径下的敌人承伤明细(虚拟段/current/overall)
-- 查 EnemyDamageTaken source，按攻击玩家聚合 → 复用 ShowEnemyDamageTakenDetail 渲染
-- ============================================================
function DV:ShowEnemyDamageTakenFromAPI(creatureID, enemyName, totalAmount, sessionType, sessionID)
    if IsSecret(creatureID) then
        self:ShowCombatLocked(OpaqueOr(enemyName,"?"))
        self._lastRenderArgs = {
            type = "enemyDmgTakenAPI",
            args = {creatureID, enemyName, totalAmount, sessionType, sessionID}
        }
        return
    end
    if creatureID == nil then
        if ns.state.inCombat or IsSecret(enemyName) or IsSecret(totalAmount) then self:ShowCombatLocked(OpaqueOr(enemyName,"?"))
        else self:ShowEnemyDamageTakenDetail(OpaqueOr(enemyName,"?"), {}, totalAmount or 0) end
        self._lastRenderArgs = {
            type = "enemyDmgTakenAPI",
            args = {creatureID, enemyName, totalAmount, sessionType, sessionID}
        }
        return
    end

    local dmType = Enum.DamageMeterType.EnemyDamageTaken
    local gateway = ns.DamageMeterGateway
    local srcData
    if sessionID then
        srcData = gateway and select(1, gateway:GetRawSource(
            nil, sessionID, dmType, nil, creatureID))
    else
        local sType = sessionType or Enum.DamageMeterSessionType.Current
        srcData = gateway and select(1, gateway:GetRawSource(
            sType, nil, dmType, nil, creatureID))
    end

    local sources = {}
    local protected=false
    local rawSpells
    local sourceType=type(srcData)
    local sourceReadable=sourceType=="table" and gateway and gateway:IsTableAccessible(srcData)
    if sourceType~="nil" and not sourceReadable then protected=true end
    if sourceReadable then
        local ok,value=pcall(function() return srcData.combatSpells end)
        if ok then rawSpells=value end
    end
    if type(rawSpells) ~= "nil" and (type(rawSpells)~="table" or not gateway:IsTableAccessible(rawSpells)) then
        protected = true
    elseif type(rawSpells) == "table" then
        local agg = {}  -- name → {name, class, amount}
        for _, sp in ipairs(rawSpells) do
            if type(sp)=="table" and gateway:IsTableAccessible(sp) then
            local details, detailsState = gateway:ReadTableField(sp, "combatSpellDetails")
            if detailsState == gateway.ACCESSIBLE then
                local pName, nameState = gateway:ReadField(details, "unitName")
                local pClass, classState = gateway:ReadField(details, "unitClassFilename")
                local amt, amountState = gateway:ReadField(details, "amount")
                if nameState == gateway.ACCESSIBLE and amountState == gateway.ACCESSIBLE
                    and type(pName)=="string" and type(amt)=="number" and amt>0 then
                    if classState ~= gateway.ACCESSIBLE or type(pClass) ~= "string" then pClass=nil end
                    if not agg[pName] then agg[pName]={name=pName,class=pClass,amount=0} end
                    agg[pName].amount=agg[pName].amount+amt
                end
            end
            end
        end
        for _, entry in pairs(agg) do
            table.insert(sources, entry)
        end
    end

    if protected or IsSecret(totalAmount) or (not srcData and ns.state.inCombat) then
        self:ShowCombatLocked(OpaqueOr(enemyName,"?"))
        self._lastRenderArgs={type="enemyDmgTakenAPI",args={creatureID,enemyName,totalAmount,sessionType,sessionID}}
        return
    end

    self:ShowEnemyDamageTakenDetail(OpaqueOr(enemyName,"?"), sources, totalAmount or 0)
    self._lastRenderArgs = {
        type = "enemyDmgTakenAPI",
        args = {creatureID, enemyName, totalAmount, sessionType, sessionID}
    }
end

function DV:Refresh()
    if self.frame and self.frame:IsShown() then
        if self._lastRenderArgs then
            local t = self._lastRenderArgs.type
            local a = self._lastRenderArgs.args
            if t == "spell" then self:RenderSpellList(unpack(a))
            elseif t == "spellAPI" then self:ShowSpellBreakdownFromAPI(unpack(a))
            elseif t == "enemyDmgTakenAPI" then self:ShowEnemyDamageTakenFromAPI(unpack(a))
            elseif t == "death" then self:ShowDeathDetail(unpack(a))
            elseif t == "combat" then self:ShowCombatLocked(unpack(a))
            elseif t == "enemyDmgTaken" then self:ShowEnemyDamageTakenDetail(unpack(a)) end
        else
            self:ApplyTheme()
        end
    end
end
