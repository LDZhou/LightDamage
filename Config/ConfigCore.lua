--[[
    Light Damage - ConfigCore.lua
    设置面板：框架创建、页面切换、控件工厂
]]
local addonName, ns = ...
local L = ns.L

local SCROLL_EXTRA_PAD = 150
local Config = {}
ns.Config = Config

local PANEL_W   = 500
local PANEL_H   = 480
local SIDEBAR_W = 110
local CAT_H     = 34

local categories = {
    {id="layout", labelKey="布局",   icon="-"},
    {id="data",   labelKey="数据",   icon="-"},
    {id="look",   labelKey="外观",   icon="-"},
    {id="perf",   labelKey="性能",   icon="-"},
    {id="profiles", labelKey="配置管理", icon="-"},
}

-- ============================================================
-- LibSharedMedia 材质/字体列表
-- ============================================================
function Config:GetSharedMediaTextures()
    local result = {}
    local builtins = {
        {l=L["极简纯色 (Minimal Flat)"],    v="Interface\\Buttons\\WHITE8X8"},
        {l=L["暴雪默认 (Blizz Default)"],   v="Interface\\TargetingFrame\\UI-StatusBar"},
        {l=L["平滑渐变 (Smooth)"],           v="Interface\\RaidFrame\\Raid-Bar-Hp-Fill"},
    }
    local builtinPaths = {}
    for _, b in ipairs(builtins) do table.insert(result, b); builtinPaths[b.v] = true end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local list = LSM:List(LSM.MediaType.STATUSBAR)
        if list then for _, name in ipairs(list) do local path = LSM:Fetch(LSM.MediaType.STATUSBAR, name); if path and not builtinPaths[path] then table.insert(result, { l = name, v = path }) end end end
    end
    return result
end

function Config:GetSharedMediaFonts()
    local chatFont = select(1, ChatFontNormal:GetFont())
    local result = { {l=L["系统默认"], v=STANDARD_TEXT_FONT}, {l=L["伤害数字"], v=DAMAGE_TEXT_FONT}, {l=L["聊天框字体"], v=chatFont}, {l=L["单位名称"], v=UNIT_NAME_FONT} }
    local builtinPaths = {}; for _, b in ipairs(result) do builtinPaths[b.v] = true end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local list = LSM:List(LSM.MediaType.FONT)
        if list then for _, name in ipairs(list) do local path = LSM:Fetch(LSM.MediaType.FONT, name); if path and not builtinPaths[path] then table.insert(result, { l = name, v = path }) end end end
    end
    return result
end

-- ============================================================
-- 原生颜色选择器封装
-- ============================================================
local function OpenColorPicker(r, g, b, a, onApply, onCancel)
    local prev = { r=r, g=g, b=b, a=a }
    local function Apply() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); local na = ColorPickerFrame:GetColorAlpha(); onApply(nr, ng, nb, na) end
    ColorPickerFrame:SetupColorPickerAndShow({ r=r, g=g, b=b, opacity=a, hasOpacity=true, swatchFunc=Apply, opacityFunc=Apply, cancelFunc=function() onCancel(prev.r, prev.g, prev.b, prev.a) end })
end

-- ============================================================
-- 工具
-- ============================================================
function Config:FillBg(f, r, g, b, a) local t = f:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(r, g, b, a); return t end
function Config:CreateBorder(f, r, g, b, a, size) local s = size or 1; local t = f:CreateTexture(nil, "BACKGROUND", nil, -8); t:SetPoint("TOPLEFT", -s, s); t:SetPoint("BOTTOMRIGHT", s, -s); t:SetColorTexture(r, g, b, a); return t end

function Config:AddCheckerboard(btn, w, h)
    w = w or 48; h = h or 16; local size = 8
    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -2); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 1)
    for y = 0, math.ceil(h/size)-1 do for x = 0, math.ceil(w/size)-1 do
        if (x + y) % 2 == 1 then local sq = btn:CreateTexture(nil, "BACKGROUND", nil, -1); sq:SetSize(size, size); sq:SetPoint("TOPLEFT", btn, "TOPLEFT", x*size, -y*size); sq:SetColorTexture(0.75, 0.75, 0.75, 1) end
    end end
end

function Config:RefreshTitle()
    if self.titleText then
        local pName = LightDamageDB and LightDamageDB.activeProfile or "默认"
        local displayName = (pName == "默认") and L["默认"] or pName
        self.titleText:SetText(string.format(L["|cff00ccffLight Damage|r 设置 - %s"], displayName))
    end
end

function Config:Toggle()
    if not self.panel then self:Build() end
    if self.panel:IsShown() then self.panel:Hide() else self.panel:Show() end
end

-- ============================================================
-- Build 主面板
-- ============================================================
function Config:Build()
    local p = CreateFrame("Frame", "LightDamageConfig", UIParent, "BackdropTemplate")
    p:SetSize(PANEL_W, PANEL_H); p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG"); p:SetFrameLevel(100)
    p:SetMovable(true); p:EnableMouse(true); p:SetClampedToScreen(true)
    p:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 })
    p:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
    p:Hide(); self.panel = p
    p:SetScale(ns.db and ns.db.window and ns.db.window.configScale or 1.0)

    local tc = ns.db.window.themeColor or {0.08, 0.08, 0.12, 1}
    local title = CreateFrame("Frame", nil, p)
    title:SetHeight(30); title:SetPoint("TOPLEFT", 0, 0); title:SetPoint("TOPRIGHT", 0, 0)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() p:StartMoving() end)
    title:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    self.titleBg = self:FillBg(title, unpack(tc))
    self._configTitle = title

    local tt = title:CreateFontString(nil, "OVERLAY")
    tt:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE"); tt:SetPoint("LEFT", 12, 0)
    self.titleText = tt; self:RefreshTitle()

    local cb = CreateFrame("Button", nil, title); cb:SetSize(24, 24); cb:SetPoint("RIGHT", -4, 0)
    local ct = cb:CreateFontString(nil, "OVERLAY"); ct:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE"); ct:SetPoint("CENTER"); ct:SetText("X"); ct:SetTextColor(0.5, 0.5, 0.5)
    cb:SetScript("OnClick", function() p:Hide() end)
    cb:SetScript("OnEnter", function() ct:SetTextColor(1, 0.2, 0.2) end)
    cb:SetScript("OnLeave", function() ct:SetTextColor(0.5, 0.5, 0.5) end)

    local sidebar = CreateFrame("Frame", nil, p); sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", 0, -30); sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    self:FillBg(sidebar, 0.03, 0.03, 0.04, 1)

    local content = CreateFrame("Frame", nil, p)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0); content:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    self.contentArea = content

    self.catBtns = {}; self.pages = {}
    for i, cat in ipairs(categories) do
        local btn = CreateFrame("Button", nil, sidebar); btn:SetSize(SIDEBAR_W, CAT_H); btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -((i-1)*CAT_H))
        btn.activeBg = btn:CreateTexture(nil, "BORDER"); btn.activeBg:SetAllPoints(); btn.activeBg:SetColorTexture(0, 0.65, 1, 0.15); btn.activeBg:Hide()
        local icon = btn:CreateFontString(nil, "OVERLAY"); icon:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE"); icon:SetPoint("LEFT", 14, 0); icon:SetText(cat.icon); icon:SetTextColor(0.5, 0.5, 0.5)
        local label = btn:CreateFontString(nil, "OVERLAY"); label:SetFont(STANDARD_TEXT_FONT, 11, ""); label:SetPoint("LEFT", icon, "RIGHT", 8, 0); label:SetText(L[cat.labelKey]); label:SetTextColor(0.6, 0.6, 0.6)
        btn.icon = icon; btn.label = label
        btn:SetScript("OnClick", function() self:ShowPage(cat.id) end)
        btn:SetScript("OnEnter", function() if self.activeCat ~= cat.id then label:SetTextColor(1,1,1); icon:SetTextColor(0.8,0.8,0.8) end end)
        btn:SetScript("OnLeave", function() if self.activeCat ~= cat.id then label:SetTextColor(0.6,0.6,0.6); icon:SetTextColor(0.5,0.5,0.5) end end)
        self.catBtns[cat.id] = btn

        local page = CreateFrame("ScrollFrame", nil, content)
        page:SetPoint("TOPLEFT", 12, -12); page:SetPoint("BOTTOMRIGHT", -8, 12)
        local inner = CreateFrame("Frame", nil, page); inner:SetWidth(PANEL_W - SIDEBAR_W - 30); inner:SetHeight(800)
        page:SetScrollChild(inner)
        local sb = CreateFrame("Slider", nil, page); sb:SetWidth(4)
        sb:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0); sb:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        sb:SetOrientation("VERTICAL"); sb:SetMinMaxValues(0, 0); sb:SetValue(0)
        local sbTrack = sb:CreateTexture(nil, "BACKGROUND"); sbTrack:SetAllPoints(); sbTrack:SetColorTexture(0.05, 0.05, 0.06, 1)
        sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8"); local sbThumb = sb:GetThumbTexture(); sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1); sbThumb:SetSize(4, 30)
        sb:SetScript("OnEnter", function() sbThumb:SetVertexColor(0.4, 0.4, 0.45, 1) end)
        sb:SetScript("OnLeave", function() sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1) end)
        page:SetScript("OnMouseWheel", function(_, delta) local cur = sb:GetValue(); local _, mx = sb:GetMinMaxValues(); sb:SetValue(math.max(0, math.min(mx, cur - delta * 32))) end)
        sb:SetScript("OnValueChanged", function(_, val) page:SetVerticalScroll(val) end)
        page:Hide(); self.pages[cat.id] = { scroll = page, inner = inner, sb = sb }
    end

    self:BuildLayoutPage(); self:BuildDataPage(); self:BuildLookPage(); self:BuildPerfPage(); self:BuildProfilesPage()
    self:ShowPage("layout")
    self:BuildPreviewBtn(); self:BuildSceneSwitcher()
    p:HookScript("OnHide", function() self:ClosePreview() end)
    tinsert(UISpecialFrames, "LightDamageConfig")
end

function Config:BuildPreviewBtn()
    local titleFrame = self._configTitle; if not titleFrame then return end
    local btn = CreateFrame("Button", nil, titleFrame); btn:SetSize(52, 22); btn:SetPoint("RIGHT", titleFrame, "RIGHT", -32, 0)
    self:FillBg(btn, 0.05, 0.20, 0.35, 1); self:CreateBorder(btn, 0.1, 0.45, 0.75, 1)
    local bt = btn:CreateFontString(nil, "OVERLAY"); bt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); bt:SetPoint("CENTER"); bt:SetText(L["预览"]); bt:SetTextColor(0.4, 0.85, 1)
    btn:SetScript("OnClick", function() self:TogglePreview() end)
    btn:SetScript("OnEnter", function() bt:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnLeave", function() bt:SetTextColor(0.4, 0.85, 1) end)
    self._previewBtn = btn; self._previewBtnT = bt
end

function Config:ShowPage(id)
    self.activeCat = id
    for cid, btn in pairs(self.catBtns) do
        if cid == id then btn.activeBg:Show(); btn.icon:SetTextColor(0, 0.75, 1); btn.label:SetTextColor(1, 1, 1)
        else btn.activeBg:Hide(); btn.icon:SetTextColor(0.5, 0.5, 0.5); btn.label:SetTextColor(0.6, 0.6, 0.6) end
    end
    for pid, page in pairs(self.pages) do if pid == id then page.scroll:Show() else page.scroll:Hide() end end
    if id == "profiles" then self:RefreshProfilesPage() end
    self:UpdatePageScroll(id)
end

function Config:UpdatePageScroll(id)
    local pg = self.pages[id]; if not pg or not pg.sb then return end
    local viewH = pg.scroll:GetHeight(); local contentH = pg.inner:GetHeight()
    local maxScroll = math.max(0, contentH + SCROLL_EXTRA_PAD - viewH)
    pg.sb:SetMinMaxValues(0, maxScroll)
    if maxScroll > 0 then pg.sb:Show() else pg.sb:Hide(); pg.sb:SetValue(0) end
end

function Config:RefreshUI()
    if self.colorSwatches then for _, updateFn in ipairs(self.colorSwatches) do updateFn() end end
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.UI:Layout() end
    if self._previewFrame and self._previewFrame:IsShown() then self:RefreshPreviewTheme(); self:UpdatePreviewScene(self._previewSceneId or "mplus") end
end

-- ============================================================
-- 控件工厂
-- ============================================================
function Config:H(p, text, y)
    local h = p:CreateFontString(nil, "OVERLAY"); h:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE"); h:SetPoint("TOPLEFT", 0, y); h:SetTextColor(0, 0.8, 1); h:SetText(text); return y - 24
end

function Config:Desc(p, y, text)
    local d = p:CreateFontString(nil, "OVERLAY"); d:SetFont(STANDARD_TEXT_FONT, 10, ""); d:SetPoint("TOPLEFT", 4, y); d:SetWidth(PANEL_W - SIDEBAR_W - 40); d:SetJustifyH("LEFT"); d:SetTextColor(0.5, 0.5, 0.5); d:SetText(text)
    local h = d:GetStringHeight(); if h == 0 then h = ((select(2, text:gsub("\n","\n")) + 1) * 13 + 6) end; return y - h - 12
end

function Config:Check(p, label, y, getter, setter, tooltipText)
    local btn = CreateFrame("Button", nil, p); btn:SetSize(20, 14); btn:SetPoint("TOPLEFT", 4, y)
    self:FillBg(btn, 0.1, 0.1, 0.15, 1); self:CreateBorder(btn, 0.3, 0.3, 0.4, 1)
    local fill = btn:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 3, -3); fill:SetPoint("BOTTOMRIGHT", -3, 3); fill:SetColorTexture(0, 0.75, 1, 1); fill:SetShown(getter())
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
    local t = btn:CreateFontString(nil, "OVERLAY"); t:SetFont(STANDARD_TEXT_FONT, 11, ""); t:SetPoint("LEFT", btn, "RIGHT", 8, 0); t:SetTextColor(0.8, 0.8, 0.8); t:SetText(label)
    btn:SetScript("OnClick", function() local nxt = not getter(); fill:SetShown(nxt); setter(nxt) end)
    if tooltipText then
        local qm = CreateFrame("Frame", nil, p); qm:SetSize(14, 14); qm:SetPoint("LEFT", t, "RIGHT", 4, 0); qm:EnableMouse(true)
        local qt = qm:CreateFontString(nil, "OVERLAY"); qt:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE"); qt:SetPoint("CENTER"); qt:SetText("?"); qt:SetTextColor(0, 0.75, 1)
        qm:SetScript("OnEnter", function(self2) qt:SetTextColor(0.2, 0.85, 1); GameTooltip:SetOwner(self2, "ANCHOR_TOPRIGHT"); GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true); GameTooltip:Show() end)
        qm:SetScript("OnLeave", function() qt:SetTextColor(0, 0.75, 1); GameTooltip:Hide() end)
    end
    return y - 24
end

function Config:Slider(p, label, y, mn, mx, step, getter, setter, isPercent)
    local lt = p:CreateFontString(nil, "OVERLAY"); lt:SetFont(STANDARD_TEXT_FONT, 10, ""); lt:SetPoint("TOPLEFT", 6, y); lt:SetTextColor(0.7, 0.7, 0.7); lt:SetText(label)
    local vt = p:CreateFontString(nil, "OVERLAY"); vt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); vt:SetPoint("TOPRIGHT", p, "TOPRIGHT", -20, y); vt:SetTextColor(0, 0.75, 1)
    y = y - 16
    local s = CreateFrame("Slider", nil, p); s:SetSize(280, 12); s:SetPoint("TOPLEFT", 6, y); s:SetOrientation("HORIZONTAL")
    local track = s:CreateTexture(nil, "BACKGROUND"); track:SetHeight(2); track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetColorTexture(0.2, 0.2, 0.25, 1)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8"); local thumb = s:GetThumbTexture(); thumb:SetSize(10, 10); thumb:SetVertexColor(0, 0.75, 1, 1)
    local fill = s:CreateTexture(nil, "ARTWORK"); fill:SetHeight(2); fill:SetPoint("LEFT", track, "LEFT"); fill:SetPoint("RIGHT", thumb, "CENTER"); fill:SetColorTexture(0, 0.75, 1, 1)
    s:SetScript("OnEnter", function() thumb:SetVertexColor(0.2, 0.85, 1, 1); fill:SetColorTexture(0.2, 0.85, 1, 1) end)
    s:SetScript("OnLeave", function() thumb:SetVertexColor(0, 0.75, 1, 1); fill:SetColorTexture(0, 0.75, 1, 1) end)
    s:SetMinMaxValues(mn, mx); s:SetValueStep(step); s:SetObeyStepOnDrag(true); s:SetValue(getter())
    local function upd(v) if isPercent then vt:SetText(string.format("%.0f%%", v * 100)) else vt:SetText(step < 1 and string.format("%.2f", v) or string.format("%.0f", v)) end end
    upd(getter()); s:SetScript("OnValueChanged", function(_, v) setter(v); upd(v) end); return y - 26
end

function Config:Dropdown(p, label, y, opts, getter, setter)
    local MAX_VISIBLE = 10; local ITEM_H = 20
    local lt = p:CreateFontString(nil, "OVERLAY"); lt:SetFont(STANDARD_TEXT_FONT, 10, ""); lt:SetPoint("TOPLEFT", 6, y); lt:SetTextColor(0.7, 0.7, 0.7); lt:SetText(label)
    y = y - 16
    local btn = CreateFrame("Button", nil, p); btn:SetSize(220, 20); btn:SetPoint("TOPLEFT", 6, y); self:FillBg(btn, 0.1, 0.1, 0.15, 1); self:CreateBorder(btn, 0.3, 0.3, 0.4, 1)
    local bt = btn:CreateFontString(nil, "OVERLAY"); bt:SetFont(STANDARD_TEXT_FONT, 11, ""); bt:SetPoint("LEFT", 6, 0); bt:SetTextColor(0.9, 0.9, 0.9)
    local arrow = btn:CreateTexture(nil, "OVERLAY"); arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\AddOns\\"..addonName.."\\Textures\\btn_expand.tga"); arrow:SetVertexColor(0.7, 0.7, 0.7)
    local hlBtn = btn:CreateTexture(nil, "HIGHLIGHT"); hlBtn:SetAllPoints(); hlBtn:SetColorTexture(1, 1, 1, 0.05)
    local function refreshText() local cur = getter(); for _, o in ipairs(opts) do if o.v == cur then bt:SetText(o.l); return end end; bt:SetText(opts[1] and opts[1].l or "") end; refreshText()

    local blocker = CreateFrame("Button", nil, p); blocker:SetAllPoints(UIParent); blocker:SetFrameStrata("TOOLTIP"); blocker:SetFrameLevel(90); blocker:Hide()
    blocker:SetScript("OnClick", function() blocker:Hide(); arrow:SetTexture("Interface\\AddOns\\"..addonName.."\\Textures\\btn_expand.tga") end)
    local visibleCount = math.min(#opts, MAX_VISIBLE); local listH = visibleCount * ITEM_H + 4; local needScroll = #opts > MAX_VISIBLE
    local list = CreateFrame("Frame", nil, blocker); list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2); list:SetSize(220, listH); list:SetFrameLevel(95)
    self:FillBg(list, 0.08, 0.08, 0.1, 1); self:CreateBorder(list, 0.3, 0.3, 0.4, 1)
    local sf = CreateFrame("ScrollFrame", nil, list); sf:SetPoint("TOPLEFT", 2, -2)
    if needScroll then sf:SetPoint("BOTTOMRIGHT", -6, 2) else sf:SetPoint("BOTTOMRIGHT", -2, 2) end
    local child = CreateFrame("Frame", nil, sf); child:SetWidth(needScroll and 208 or 216); child:SetHeight(#opts * ITEM_H); sf:SetScrollChild(child)
    local sb
    if needScroll then
        sb = CreateFrame("Slider", nil, list); sb:SetWidth(4); sb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2); sb:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 2)
        sb:SetOrientation("VERTICAL"); sb:SetMinMaxValues(0, math.max(0, (#opts - MAX_VISIBLE) * ITEM_H)); sb:SetValue(0); sb:SetValueStep(1)
        local sbTrack = sb:CreateTexture(nil, "BACKGROUND"); sbTrack:SetAllPoints(); sbTrack:SetColorTexture(0.05, 0.05, 0.06, 1)
        sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8"); local sbThumb = sb:GetThumbTexture(); sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1); sbThumb:SetSize(4, 20)
        sb:SetScript("OnValueChanged", function(_, val) sf:SetVerticalScroll(val) end)
        sf:SetScript("OnMouseWheel", function(_, delta) local cur = sb:GetValue(); local _, mx = sb:GetMinMaxValues(); sb:SetValue(math.max(0, math.min(mx, cur - delta * ITEM_H * 2))) end)
        list:EnableMouseWheel(true); list:SetScript("OnMouseWheel", function(_, delta) local cur = sb:GetValue(); local _, mx = sb:GetMinMaxValues(); sb:SetValue(math.max(0, math.min(mx, cur - delta * ITEM_H * 2))) end)
    end
    btn.items = {}
    for i, o in ipairs(opts) do
        local item = CreateFrame("Button", nil, child); item:SetHeight(ITEM_H)
        item:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((i-1) * ITEM_H)); item:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -((i-1) * ITEM_H))
        local hl = item:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0, 0.75, 1, 0.2)
        local itx = item:CreateFontString(nil, "OVERLAY"); itx:SetFont(STANDARD_TEXT_FONT, 11, ""); itx:SetPoint("LEFT", 6, 0); itx:SetTextColor(0.8, 0.8, 0.8); itx:SetText(o.l)
        item:SetScript("OnClick", function() setter(o.v); bt:SetText(o.l); blocker:Hide(); arrow:SetTexture("Interface\\AddOns\\"..addonName.."\\Textures\\btn_expand.tga") end)
        if needScroll then item:EnableMouseWheel(true); item:SetScript("OnMouseWheel", function(_, delta) local cur = sb:GetValue(); local _, mx = sb:GetMinMaxValues(); sb:SetValue(math.max(0, math.min(mx, cur - delta * ITEM_H * 2))) end) end
        table.insert(btn.items, {btn = item, txt = itx})
    end
    btn.UpdateOpts = function(newOpts)
        opts = newOpts; local newNeedScroll = #opts > MAX_VISIBLE; local newVisCount = math.min(#opts, MAX_VISIBLE); list:SetHeight(newVisCount * ITEM_H + 4); child:SetHeight(#opts * ITEM_H)
        if sb then if newNeedScroll then sb:SetMinMaxValues(0, math.max(0, (#opts - MAX_VISIBLE) * ITEM_H)); sb:SetValue(0); sb:Show() else sb:Hide(); sb:SetValue(0) end end
        for i, o in ipairs(opts) do local row = btn.items[i]; if row then row.txt:SetText(o.l); row.btn:SetScript("OnClick", function() setter(o.v); bt:SetText(o.l); blocker:Hide(); arrow:SetTexture("Interface\\AddOns\\"..addonName.."\\Textures\\btn_expand.tga") end); row.btn:Show() end end
        for i = #opts + 1, #btn.items do btn.items[i].btn:Hide() end; refreshText()
    end
    btn:SetScript("OnClick", function() if blocker:IsShown() then blocker:Hide(); arrow:SetTexture("Interface\\AddOns\\"..addonName.."\\Textures\\btn_expand.tga") else blocker:Show(); arrow:SetTexture("Interface\\AddOns\\"..addonName.."\\Textures\\btn_collapse.tga"); if sb then sb:SetValue(0) end end end)
    return y - 28, btn
end

function Config:ColorSwatch(p, label, y, getter, setter)
    local lt = p:CreateFontString(nil, "OVERLAY"); lt:SetFont(STANDARD_TEXT_FONT, 10, ""); lt:SetPoint("TOPLEFT", 6, y); lt:SetTextColor(0.7, 0.7, 0.7); lt:SetText(label)
    local btn = CreateFrame("Button", nil, p); btn:SetSize(48, 16); btn:SetPoint("TOPLEFT", 6, y - 18)
    self:AddCheckerboard(btn, 48, 16)
    local swatch = btn:CreateTexture(nil, "ARTWORK"); swatch:SetAllPoints(); swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    self:CreateBorder(btn, 0.4, 0.4, 0.5, 1)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
    local function UpdateSwatch() local r, g, b, a = getter(); swatch:SetVertexColor(r, g, b, a) end; UpdateSwatch()
    if not self.colorSwatches then self.colorSwatches = {} end; table.insert(self.colorSwatches, UpdateSwatch)
    btn:SetScript("OnClick", function() local r, g, b, a = getter(); OpenColorPicker(r, g, b, a, function(nr, ng, nb, na) setter(nr, ng, nb, na); swatch:SetVertexColor(nr, ng, nb, na) end, function(pr, pg, pb, pa) setter(pr, pg, pb, pa); swatch:SetVertexColor(pr, pg, pb, pa) end) end)
    return y - 42
end

function Config:ColorSwatchNoAlpha(p, label, y, getter, setter)
    local lt = p:CreateFontString(nil, "OVERLAY"); lt:SetFont(STANDARD_TEXT_FONT, 10, ""); lt:SetPoint("TOPLEFT", 6, y); lt:SetTextColor(0.7, 0.7, 0.7); lt:SetText(label)
    local btn = CreateFrame("Button", nil, p); btn:SetSize(48, 16); btn:SetPoint("TOPLEFT", 6, y - 18)
    self:AddCheckerboard(btn, 48, 16)
    local swatch = btn:CreateTexture(nil, "ARTWORK"); swatch:SetAllPoints(); swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    self:CreateBorder(btn, 0.4, 0.4, 0.5, 1)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.12)
    local function UpdateSwatch() local r, g, b = getter(); swatch:SetVertexColor(r, g, b, 1) end; UpdateSwatch()
    if not self.colorSwatches then self.colorSwatches = {} end; table.insert(self.colorSwatches, UpdateSwatch)
    btn:SetScript("OnClick", function()
        local r, g, b = getter()
        ColorPickerFrame:SetupColorPickerAndShow({ r=r, g=g, b=b, hasOpacity=false,
            swatchFunc = function() local nr, ng, nb = ColorPickerFrame:GetColorRGB(); setter(nr, ng, nb); swatch:SetVertexColor(nr, ng, nb, 1) end,
            cancelFunc = function() setter(r, g, b); swatch:SetVertexColor(r, g, b, 1) end })
    end)
    return y - 42
end
