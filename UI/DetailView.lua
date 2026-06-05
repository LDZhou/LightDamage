--[[
    LD Combat Stats - DetailView.lua
    详情面板：技能细分 + 死亡事件详情
]]

local addonName, ns = ...
local L = ns.L

ns.FONT_MAIN = ns.FONT_MAIN or STANDARD_TEXT_FONT

local DV = {}
ns.DetailView = DV

local ICON_W = 18

local ROW_BG = {
    {0.07, 0.07, 0.09, 0.92},
    {0.12, 0.12, 0.15, 0.92},
}
local BG_HEADER  = {0.04, 0.04, 0.08, 0.96}
local BG_SECTION = {0.05, 0.08, 0.13, 0.92}
local BG_FATAL   = {0.22, 0.03, 0.03, 0.96}

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
    bt:SetPoint("CENTER"); bt:SetText("←"); bt:SetTextColor(0.6, 0.6, 0.6)
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
    resizeGrabber:SetSize(16, 16); resizeGrabber:SetPoint("BOTTOMRIGHT", 0, 0)
    resizeGrabber:SetFrameLevel(f:GetFrameLevel() + 15); resizeGrabber:EnableMouse(true)
    local gt = resizeGrabber:CreateTexture(nil, "OVERLAY"); gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
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
    end)

    self.frame      = f
    self.content    = inner
    self.scrollFrame = sc
    self.scrollBar  = sb
    self.rows       = {}
    tinsert(UISpecialFrames, "LightDamageDetail")

    f:SetScript("OnShow", function() self:UpdatePosition() end)

    f:Hide()
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
    local bg = dbW.bgColor or {0.04, 0.04, 0.05, 0.90}
    self.frame:SetBackdropColor(unpack(bg))
    
    -- 2. 同步标题栏颜色 (ThemeColor)
    local tc = dbW.themeColor or {0.08, 0.08, 0.12, 1}
    self.titleBg:SetColorTexture(unpack(tc))
    
    -- 3. ★ 使用全新 DetailDisplay 字体同步
    local _, _, _, font, fSz, fOut, fShad = self:GetBarConfig()
    fOut = ns.NormalizeFontOutline and ns:NormalizeFontOutline(fOut) or fOut
    local function _applyFont(fs, sz)
        fs:SetFont(font, sz, fOut)
        if fShad then fs:SetShadowColor(0,0,0,1); fs:SetShadowOffset(1,-1)
        else fs:SetShadowOffset(0,0) end
    end
    
    if self.titleText then _applyFont(self.titleText, fSz + 1); self:SetDetailTextColor(self.titleText) end
    if self.backText then _applyFont(self.backText, fSz + 4) end
    if self.closeText then _applyFont(self.closeText, fSz + 2) end
    
    for _, r in ipairs(self.rows) do
        _applyFont(r.name, fSz)
        _applyFont(r.value, fSz)
        self:SetDetailTextColor(r.name)
        self:SetDetailTextColor(r.value)
    end
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
    r.value:SetJustifyH("RIGHT")
    r.value:SetTextColor(1, 1, 1)

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
        r.fill:SetMinMaxValues(0, 1)
        r.fill:SetValue(0)
        r.frame:SetScript("OnEnter", nil)
        r.frame:SetScript("OnLeave", nil)
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

    r.fill:SetMinMaxValues(0, 1)
    r.fill:SetValue(0)
    r.frame:Show()

    local _, _, _, font, fSz, fOut, fShad = self:GetBarConfig()
    fOut = ns.NormalizeFontOutline and ns:NormalizeFontOutline(fOut) or fOut
    local function _applyFont(fs, sz)
        fs:SetFont(font, sz, fOut)
        if fShad then fs:SetShadowColor(0,0,0,1); fs:SetShadowOffset(1,-1)
        else fs:SetShadowOffset(0,0) end
    end
    _applyFont(r.name, fSz)
    _applyFont(r.value, fSz)
    self:SetDetailTextColor(r.name)
    self:SetDetailTextColor(r.value)

    return r
end

local function setNameWithIcon(r, iconTex, text)
    if iconTex then
        r.icon:SetTexture(iconTex)
        r.icon:Show()
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r.nameClipFrame, "LEFT", r.icon:GetWidth() + 7, 0)
    else
        r.icon:Hide()
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r.nameClipFrame, "LEFT", 6, 0)
    end
    r.name:SetText(text)
end

local function GetSpellIcon(spellID)
    if not spellID then return nil end
    local ok, icon = pcall(function()
        if spellID == 0 then return nil end
        if C_Spell and C_Spell.GetSpellTexture then
            return C_Spell.GetSpellTexture(spellID)
        end
        if GetSpellTexture then
            return GetSpellTexture(spellID)
        end
        return nil
    end)
    if ok and icon then return icon end
    return nil
end

-- ============================================================
-- 技能列表渲染
-- ============================================================
function DV:RenderSpellList(name, class, mode, spells, dur, titleSuffix, apiMaxAmount)
    self._lastRenderArgs = { type = "spell", args = {name, class, mode, spells, dur, titleSuffix, apiMaxAmount} }
    self:EnsureCreated()
    self.frame:Show()
    self:ApplyTheme()
    self:ClearRows()

    -- print("|cffff00ff[LD DEBUG RenderSpellList]|r frameShown=", self.frame:IsShown(), "spells=", #spells, "apiMaxAmount=", type(apiMaxAmount))

    local ch = ns:GetClassHex(class)
    -- ★ 在这里实时获取翻译
    local rawModeName = ns.MODE_NAMES[mode] or mode
    local mn = L[rawModeName] or rawModeName
    local suffix = titleSuffix or ""
    self.titleText:SetFormattedText(L.PLAYER_MODE_BREAKDOWN_TITLE_FORMAT, ch, ns:DisplayName(name), mn, suffix)

    local bh, gap, alpha, _, _, _, _, thickness, vOffset, texPath = self:GetBarConfig()
    local currentY = 0

    if #spells == 0 then
        local r = self:PlaceRow(1, 0, bh, nil, thickness, vOffset)
        r.name:SetText(L.COLORED_NO_SPELL_DATA)
        r.value:SetText("")
        self:UpdateScroll(bh + 5)
        return
    end

    local maxV
    if apiMaxAmount then
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
            r.fill:SetValue(sp.secretAmt or sp.value)
        end)

        -- ★ 颜色：魔法学派颜色，透明度跟主界面统一
        local sc2 = ns.SCHOOL_COLORS and ns.SCHOOL_COLORS[sp.school] or {0.5, 0.5, 0.7}
        if sp.isPet then sc2 = {0.28, 0.65, 0.28} end
        r.fill:SetStatusBarColor(self:GetDetailBarColor(sc2, alpha))

        local sn = sp.name or "?"
        local nc = sp.isPet and "|cff55bb55" or "|cffffffff"
        
        if sp.isAvoidable then
            sc2 = {0.85, 0.70, 0.15}
            sn = sn .. " |cffffcc00[可规避]|r"
        end
        
        -- 【先】设定右侧值文字，让它把占位大小确定下来
        local isCount = (mode == "interrupts" or mode == "dispels")
        local valStr
        if sp.secretAmt then
            valStr = AbbreviateNumbers(sp.secretAmt)
        elseif isCount then
            valStr = string.format(L.COLORED_COUNT_TIMES_FORMAT, sp.value)
        elseif dur and dur > 0 and ns.MODE_UNITS[mode] then
            -- ★ 顺序与主界面数据条一致：总量 (每秒)
            valStr = string.format("%s (%s)", ns:FormatNumber(sp.value), ns:FormatNumber(sp.value / dur))
        else
            valStr = ns:FormatNumber(sp.value)
        end
        
        if sp.secretAmt then
            r.value:SetText(valStr)
        else
            local pctStr = string.format("%.1f%%", sp.percent or 0)
            r.value:SetText(valStr .. " |cffaaaaaa" .. pctStr .. "|r")
        end

        -- 【后】再赋予左侧名字，此时超出裁剪框的部分会被完美隐藏
        setNameWithIcon(r, GetSpellIcon(sp.spellID), nc .. sn .. "|r")

        local sp_c = sp
        r.frame:SetScript("OnEnter", function(fw)
            GameTooltip:SetOwner(fw, "ANCHOR_RIGHT")
            pcall(function()
                if sp_c.spellID and sp_c.spellID > 0 then
                    GameTooltip:SetSpellByID(sp_c.spellID)
                end
            end)
            if not GameTooltip:NumLines() or GameTooltip:NumLines() == 0 then
                local nameOk, n = pcall(tostring, sp_c.name or "?")
                GameTooltip:AddLine(nameOk and n or "?")
            end
            GameTooltip:AddLine(" ")
            
            -- Tooltip 内的安全渲染
            local amtStr = sp_c.secretAmt and AbbreviateNumbers(sp_c.secretAmt) or ns:FormatNumber(sp_c.value)
            GameTooltip:AddDoubleLine(L.TOTAL, amtStr, 0.7, 0.7, 0.7, 1, 1, 1)
            
            if not sp_c.secretAmt and dur and dur > 0 and ns.MODE_UNITS[mode] then
                GameTooltip:AddDoubleLine(L.PER_SECONDS, string.format("%.1f", sp_c.value / dur), 0.7, 0.7, 0.7, 1, 0.85, 0)
            end

            if (sp_c.overhealing or 0) > 0 then
                GameTooltip:AddDoubleLine(L.OVERHEAL, ns:FormatNumber(sp_c.overhealing), 0.7, 0.7, 0.7, 0.8, 0.4, 0.4)
            end
            GameTooltip:Show()
        end)
        r.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

function DV:ShowSpellBreakdownFromAPI(sourceGUID, sourceCreatureID, name, class, mode, sessionType, sessionID)
    -- 走通用 dmType 映射，承伤/打断/驱散/敌人承伤一并支持
    local dmType = ns.UI and ns.UI.MODE_TO_DM and ns.UI.MODE_TO_DM[mode]
    if not dmType then
        self:EnsureCreated(); self.frame:Show(); self:ApplyTheme()
        self:RenderSpellList(name or "?", class or "WARRIOR", mode, {}, 0, "")
        self._lastRenderArgs = {
            type = "spellAPI",
            args = {sourceGUID, sourceCreatureID, name, class, mode, sessionType, sessionID}
        }
        return
    end

    -- 路由：有 sessionID 走 FromID(虚拟段/归档段)，否则走 FromType(current/overall)
    local ok, srcData
    if sessionID then
        ok, srcData = pcall(
            C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, dmType, sourceGUID, sourceCreatureID
        )
    else
        local sType = sessionType or Enum.DamageMeterSessionType.Current
        ok, srcData = pcall(
            C_DamageMeter.GetCombatSessionSourceFromType,
            sType, dmType, sourceGUID, sourceCreatureID
        )
    end

    if not ok or type(srcData) ~= "table" or type(srcData.combatSpells) ~= "table" then
        self:EnsureCreated(); self.frame:Show(); self:ApplyTheme()
        self:RenderSpellList(name or "?", class or "WARRIOR", mode, {}, 0, "")
        self._lastRenderArgs = {
            type = "spellAPI",
            args = {sourceGUID, sourceCreatureID, name, class, mode, sessionType, sessionID}
        }
        return
    end

    local spells = {}
    local isSecret = false

    -- 单次遍历：玩家法术 + 宠物法术(creatureName 非空就是宠物施放的)
    for _, sp in ipairs(srcData.combatSpells) do
        local amtOk, amt = pcall(function() return sp.totalAmount end)
        if amtOk and amt then
            local isSec = issecretvalue and issecretvalue(amt)
            if isSec then isSecret = true end

            local spellName = ""
            local nameOk, nameVal = pcall(function()
                if C_Spell and C_Spell.GetSpellName then
                    return C_Spell.GetSpellName(sp.spellID)
                end
                return nil
            end)
            if nameOk and nameVal then
                spellName = nameVal
            else
                local sidOk, sid = pcall(function() return sp.spellID end)
                spellName = sidOk and sid and ("spell:" .. sid) or "?"
            end

            -- 宠物名直接从 sp.creatureName 读，不需要二次查询
            local creatureName = nil
            local cnOk, cnVal = pcall(function() return sp.creatureName end)
            if cnOk and type(cnVal) == "string"
            and not (issecretvalue and issecretvalue(cnVal)) then
                if cnVal ~= "" then
                    creatureName = cnVal
                end
            end
            local isPet = creatureName ~= nil
            if isPet then
                spellName = creatureName .. ": " .. spellName
            end

            local spellIDSafe = nil
            pcall(function() spellIDSafe = sp.spellID end)

            -- 可规避标记
            local isAvoidable = false
            pcall(function() isAvoidable = sp.isAvoidable and true or false end)

            table.insert(spells, {
                spellID     = spellIDSafe,
                name        = spellName,
                school      = 1,
                value       = isSec and 0 or amt,
                secretAmt   = isSec and amt or nil,
                percent     = 0,
                isPet       = isPet,
                isAvoidable = isAvoidable,
            })
        end
    end

    -- 排序与百分比
    if not isSecret then
        table.sort(spells, function(a, b) return a.value > b.value end)
        local total = srcData.totalAmount or 0
        if total > 0 then
            for _, s in ipairs(spells) do
                s.percent = s.value / total * 100
            end
        end
    end

    local dur = 0
    if ns.state.inCombat and ns.state.combatStartTime and ns.state.combatStartTime > 0 then
        dur = GetTime() - ns.state.combatStartTime
    end

    local apiMaxAmount = isSecret and srcData.maxAmount or nil

    self._lastRenderArgs = {
        type = "spellAPI",
        args = {sourceGUID, sourceCreatureID, name, class, mode, sessionType, sessionID}
    }

    self:EnsureCreated(); self.frame:Show(); self:ApplyTheme()
    self:RenderSpellList(name or "?", class or "WARRIOR", mode, spells, dur, "", apiMaxAmount)
end

-- ============================================================
-- 战斗中队友数据受保护提示
-- ============================================================
function DV:ShowCombatLocked(safeName)
    self._lastRenderArgs = { type = "combat", args = {safeName} }
    self:EnsureCreated()
    self.frame:Show()
    self:ClearRows()
    self.titleText:SetFormattedText(L.SPELL_BREAKDOWN_TITLE_FORMAT, ns:DisplayName(safeName) or L.UNKNOWN) -- ★ 添加DisplayName
    
    local bh, gap, _, _, _, _, _, thickness, vOffset = self:GetBarConfig()
    local r = self:PlaceRow(1, 0, bh * 2, nil, thickness * 2, vOffset)
    
    r.name:SetText("|cffaaaaaa[API限制，请脱战后查看")
    
    r.name:SetWidth(300)
    r.value:SetText("")
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
            for spellID, sd in pairs(pd.damageTakenSpells) do
                if (sd.damage or 0) > 0 then
                    table.insert(result, {
                        spellID     = spellID,
                        name        = sd.name or ("spell:" .. spellID),
                        school      = sd.school or 1,
                        value       = sd.damage,
                        hits        = sd.hits or 1,
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
                return {{ spellID=0, name=L.TOTAL_DAMAGE_TAKEN, school=1, value=pd.damageTaken,
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
            for spellID, sd in pairs(spellTable) do
                local amt = sd.damage or sd.hits or 0
                if amt > 0 then
                    local sName = sd.name or ("spell:" .. spellID)
                    
                    if mode == "interrupts" and spellID == 32747 then
                        sName = L.CC_INTERRUPTS
                    end
                    
                    table.insert(result, {
                        spellID     = spellID,
                        name        = sName,
                        school      = sd.school or 1,
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
                return {{ spellID=0, name=fallbackName, school=1, value=totalVal,
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

    local ch      = ns:GetClassHex(death.playerClass)
    local selfTag = death.isSelf and " |cffff8888[自己]|r" or ""
    self.titleText:SetText(ch .. ns:DisplayName(death.playerName or "?") .. "|r" .. selfTag .. L.DEATH_DETAILS_TITLE_SUFFIX) -- ★ 玩家名

    local events     = death.events or {}
    local evReversed = {}
    for i = #events, 1, -1 do
        table.insert(evReversed, events[i])
    end

    local bh, gap, alpha, _, _, _, _, thickness, vOffset, texPath = self:GetBarConfig()
    local ri        = 0
    local currentY  = 0
    local deathTime = events[#events] and events[#events].time or GetTime()

    -- 致命一击行
    ri = ri + 1
    local hr = self:PlaceRow(ri, currentY, bh + 4, BG_FATAL, thickness + 4, vOffset)
    currentY = currentY - (bh + 4 + gap)
    hr.fill:SetStatusBarTexture(texPath)
    hr.fill:SetMinMaxValues(0, 1)
    hr.fill:SetValue(1)
    hr.fill:SetStatusBarColor(self:GetDetailBarColor({0.70, 0.04, 0.04, 0.55}, 0.55))
    setNameWithIcon(hr,
        death.killingAbility ~= "?" and GetSpellIcon(
            (evReversed[1] and not evReversed[1].isHeal) and evReversed[1].spellID or 0
        ) or nil,
        L.COLORED_FATAL_PREFIX .. (death.killingAbility or "?")
    )
    hr.value:SetText(L.COLORED_KILLER_PREFIX .. (death.killerName ~= "" and ns:DisplayName(death.killerName) or L.UNKNOWN)) -- ★ 击杀者名

    -- 分割线
    ri = ri + 1
    local sep = self:PlaceRow(ri, currentY, 15, BG_SECTION, 15, 0)
    currentY = currentY - (15 + gap)
    sep.fill:SetMinMaxValues(0, 1)
    sep.fill:SetValue(0)
    sep.name:SetText(L.EVENTS_BEFORE_DEATH_RECENT_OLD)
    sep.value:SetText(string.format(L.COLORED_ROW_COUNT_FORMAT, #evReversed))

    if #evReversed == 0 then
        ri = ri + 1
        local er = self:PlaceRow(ri, currentY, bh, nil, thickness, vOffset)
        currentY = currentY - (bh + gap)
        er.name:SetText(L.COLORED_NO_EVENT_DATA)
        er.value:SetText("")
    end

    for idx, ev in ipairs(evReversed) do
        ri = ri + 1
        local r    = self:PlaceRow(ri, currentY, bh, nil, thickness, vOffset)
        currentY = currentY - (bh + gap)
        local isFatal = (idx == 1 and not ev.isHeal)

        local hpPct = math.min(1, math.max(0, (ev.hpPercent or 0) / 100))
        r.fill:SetStatusBarTexture(texPath)
        r.fill:SetMinMaxValues(0, 1)
        r.fill:SetValue(hpPct)

        if ev.isHeal then
            r.fill:SetStatusBarColor(self:GetDetailBarColor({0.10, 0.50, 0.10}, alpha))
            r.bg:SetColorTexture(unpack(ROW_BG[(ri % 2) + 1]))
            setNameWithIcon(r, GetSpellIcon(ev.spellID),
                string.format("|cff44ee44+%s|r %s",
                    ns:FormatNumber(math.abs(ev.amount)), ev.spellName or L.HEALING))
        elseif isFatal then
            r.bg:SetColorTexture(0.20, 0.03, 0.03, 0.96)
            r.fill:SetStatusBarColor(self:GetDetailBarColor({0.80, 0.04, 0.04}, alpha))
            setNameWithIcon(r, GetSpellIcon(ev.spellID),
                string.format("|cffff1111-%s|r |cffff7755%s|r",
                    ns:FormatNumber(ev.amount), ev.spellName or "?"))
        else
            r.fill:SetStatusBarColor(self:GetDetailBarColor({0.60, 0.08, 0.08}, alpha))
            setNameWithIcon(r, GetSpellIcon(ev.spellID),
                string.format("|cffff9977-%s|r %s",
                    ns:FormatNumber(ev.amount), ev.spellName or "?"))
        end

        local td = deathTime - (ev.time or deathTime)
        local timeStr
        if td < 0.05 then
            timeStr = L.COLORED_DEATH
        else
            timeStr = string.format(L.COLORED_SECONDS_AGO_FORMAT, td)
        end
        local hpColor = ev.isHeal and "44ee44" or (hpPct < 0.15 and "ff4444" or "bbbbbb")
        r.value:SetText(string.format("|cff%s%.0f%%|r %s", hpColor, ev.hpPercent or 0, timeStr))

        local ev_c    = ev
        local td_c    = td
        local maxHP_c = death.maxHP or 0
        r.frame:SetScript("OnEnter", function(fw)
            GameTooltip:SetOwner(fw, "ANCHOR_RIGHT")
            if ev_c.spellID and ev_c.spellID > 0 then
                pcall(function() GameTooltip:SetSpellByID(ev_c.spellID) end)
            else
                GameTooltip:AddLine(ev_c.spellName or "?")
            end
            GameTooltip:AddLine(" ")
            if ev_c.isHeal then
                GameTooltip:AddDoubleLine(L.HEALING_DONE,
                    ns:FormatNumber(math.abs(ev_c.amount)), 0.7, 0.7, 0.7, 0.3, 1, 0.3)
            else
                GameTooltip:AddDoubleLine(L.DAMAGE_DONE,
                    ns:FormatNumber(ev_c.amount), 0.7, 0.7, 0.7, 1, 0.3, 0.3)
                if (ev_c.overkill or 0) > 0 then
                    GameTooltip:AddDoubleLine(L.OVERKILL,
                        ns:FormatNumber(ev_c.overkill), 0.7, 0.7, 0.7, 1, 0.5, 0)
                end
            end
            if ev_c.srcName and ev_c.srcName ~= "" then
                GameTooltip:AddDoubleLine(L.SOURCE, ns:DisplayName(ev_c.srcName), 0.7, 0.7, 0.7, 1, 1, 1) -- ★ 来源名
            end
            GameTooltip:AddDoubleLine(L.HP_REMAINING,
                string.format("%s / %s (%.0f%%)",
                    ns:FormatNumber(ev_c.hp or 0),
                    ns:FormatNumber(maxHP_c),
                    ev_c.hpPercent or 0),
                0.7, 0.7, 0.7, 1, 1, 1)
            if td_c >= 0.05 then
                GameTooltip:AddDoubleLine(L.TO_DEATH, string.format(L.SECONDS_FORMAT, td_c), 0.7, 0.7, 0.7, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        r.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- 底部汇总行
    ri = ri + 1
    local tr   = self:PlaceRow(ri, currentY, bh + 4, BG_HEADER, thickness + 4, vOffset)
    currentY = currentY - (bh + 4 + gap)
    tr.fill:SetStatusBarTexture(texPath)
    tr.fill:SetMinMaxValues(0, 1)
    tr.fill:SetValue(1)
    tr.fill:SetStatusBarColor(self:GetDetailBarColor({0.04, 0.04, 0.08, 0.90}, 0.90))
    tr.name:SetText(string.format(
        L.DAMAGE_TAKEN_LINE_FORMAT,
        ns:FormatNumber(death.totalDamageTaken or 0)))
    local spanStr = (death.timeSpan and death.timeSpan > 0)
        and string.format(L.COLORED_SPAN_SECONDS_FORMAT, death.timeSpan) or ""
    tr.value:SetText(spanStr)

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

    self.titleText:SetText(string.format(L.DAMAGE_TAKEN_SOURCE_TITLE_FORMAT, ns:DisplayName(enemyName)))

    local bh, gap, alpha, _, _, _, _, thickness, vOffset, texPath = self:GetBarConfig()
    local currentY = 0

    if not sources or #sources == 0 then
        local r = self:PlaceRow(1, 0, bh, nil, thickness, vOffset)
        r.name:SetText(L.COLORED_NO_DAMAGE_TAKEN_DATA); r.value:SetText("")
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

        local classKey = type(src.class) == "string" and src.class or "NPC"
        local ok, cc = pcall(ns.GetClassColor, ns, classKey)
        if not ok or not cc then cc = {0.5, 0.5, 0.5} end
        r.fill:SetStatusBarColor(self:GetDetailBarColor(cc, alpha))

        local nameOk, nameStr = pcall(ns.DisplayName, ns, src.name)
        r.name:SetText((nameOk and nameStr) or tostring(src.name or "?"))
        r.name:SetTextColor(cc[1], cc[2], cc[3])

        local pct = totalDmg > 0 and (src.amount / totalDmg * 100) or 0
        r.value:SetText(string.format("%s  |cffaaaaaa%.0f%%|r", ns:FormatNumber(src.amount), pct))

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
    if not creatureID then
        self:EnsureCreated(); self.frame:Show(); self:ApplyTheme()
        self:ShowEnemyDamageTakenDetail(enemyName or "?", {}, totalAmount or 0)
        self._lastRenderArgs = {
            type = "enemyDmgTakenAPI",
            args = {creatureID, enemyName, totalAmount, sessionType, sessionID}
        }
        return
    end

    local dmType = Enum.DamageMeterType.EnemyDamageTaken
    local ok, srcData
    if sessionID then
        ok, srcData = pcall(
            C_DamageMeter.GetCombatSessionSourceFromID,
            sessionID, dmType, nil, creatureID
        )
    else
        local sType = sessionType or Enum.DamageMeterSessionType.Current
        ok, srcData = pcall(
            C_DamageMeter.GetCombatSessionSourceFromType,
            sType, dmType, nil, creatureID
        )
    end

    local sources = {}
    if ok and srcData and type(srcData.combatSpells) == "table" then
        local agg = {}  -- name → {name, class, amount}
        pcall(function()
            for _, sp in ipairs(srcData.combatSpells) do
                local details = sp.combatSpellDetails
                if details then
                    local pName = details.unitName
                    local pClass = details.unitClassFilename
                    if not pClass or pClass == "" then pClass = "NPC" end

                    local amt = 0
                    pcall(function() amt = details.amount or 0 end)
                    if amt == 0 then
                        pcall(function() amt = sp.totalAmount or 0 end)
                    end

                    if pName and type(pName) == "string" and amt > 0
                       and not (issecretvalue and issecretvalue(pName)) then
                        if not agg[pName] then
                            agg[pName] = { name = pName, class = pClass, amount = 0 }
                        end
                        agg[pName].amount = agg[pName].amount + amt
                    end
                end
            end
        end)
        for _, entry in pairs(agg) do
            table.insert(sources, entry)
        end
    end

    self:ShowEnemyDamageTakenDetail(enemyName or "?", sources, totalAmount or 0)
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
