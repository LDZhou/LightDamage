--[[
    Light Damage - ConfigPages.lua
    设置页面：底部栏快捷按钮与外观页 (布局/数据/行为页见 ConfigLayouts.lua)
    注意：所有方法挂载到 ns.Config 上（ConfigCore.lua 已创建）
]]
local addonName, ns = ...
local L = ns.L
local Config = ns.Config


-- ============================================================
-- Data 页
-- ============================================================
-- The short labels' legend ("DMG = Damage, ..."), built from the labels the
-- bar really shows, so the two can never disagree.  A label the language
-- cannot shorten is left out.
function Config:BottomBarAbbreviationLegend()
    local UI = ns.UI
    if not (UI and UI.GetBottomTabLabel) then return "" end
    local modes = { "overview" }
    for _, m in ipairs(ns.MODE_ORDER) do modes[#modes + 1] = m end
    local parts = {}
    for _, m in ipairs(modes) do
        local short, full = UI:GetBottomTabLabel(m, true), UI:GetBottomTabLabel(m, false)
        if short and full and short ~= full then parts[#parts + 1] = short .. " = " .. full end
    end
    return table.concat(parts, L.LIST_SEPARATOR or ", ")
end

function Config:BuildBottomBarSettings(page)
    local y = 0
    y = self:H(page, L.BOTTOM_BAR_SETTINGS, y)
    local function BottomModes()
        ns.db.display.bottomBarModes=type(ns.db.display.bottomBarModes)=="table" and ns.db.display.bottomBarModes or {}
        return ns.db.display.bottomBarModes
    end
    local function RefreshBottomBar()
        if ns.UI then
            if ns.UI.CloseOtherTabMenu then ns.UI:CloseOtherTabMenu() end
            ns.UI:LayoutTabs(); ns.UI:Refresh()
        end
    end
    -- Short labels: one switch, its legend right under it.  (A dropdown
    -- above the statistics list, with the legend below the list, read as
    -- if ticking a statistic were what abbreviated it.)
    y = self:Check(page, L.BOTTOM_BAR_ABBREVIATE, y,
        function() return ns.db.display.tabLabelStyle == "short" end,
        function(v)
            ns.db.display.tabLabelStyle = v and "short" or "full"
            ns.db.display.useShortTabs = v and true or false
            RefreshBottomBar()
        end)
    y = self:Desc(page, y, self:BottomBarAbbreviationLegend())
    y = y - 8
    -- Which statistics sit on the bar.
    y = self:Desc(page, y, L.BOTTOM_BAR_SETTINGS_DESC)
    for _,mode in ipairs(ns.MODE_ORDER) do
        local m=mode
        y = self:Check(page, L[ns.MODE_NAMES[m] or m], y,
            function() return BottomModes()[m] == true end,
            function(v) BottomModes()[m]=v and true or false; RefreshBottomBar() end)
    end
    return y
end

-- ============================================================
-- Look 页
-- ============================================================
function Config:ShowLookSubPage(id)
    if not (self.lookSubPages and self.lookSubPages[id]) then id="general" end
    self.activeLookSubPage = id
    for sid, page in pairs(self.lookSubPages or {}) do
        if sid == id then page:Show() else page:Hide() end
    end
    for sid, btn in pairs(self.lookSubBtns or {}) do
        local active = sid == id
        btn.bg:SetShown(active)
        btn.text:SetTextColor(active and 1 or 0.6, active and 1 or 0.6, active and 1 or 0.6)
    end
    local page = self.lookSubPages and self.lookSubPages[id]
    local inner = self.pages["look"].inner
    if page and inner then
        inner:SetHeight((page:GetHeight() or 0) + 44)
        self:UpdatePageScroll("look")
    end
end

function Config:BuildLookSubTabs(inner)
    local tabs = {
        {id="general",  label=L.LOOK_TAB_GENERAL},
        {id="colors",   label=L.LOOK_TAB_COLORS},
        {id="fonts",    label=L.LOOK_TAB_FONTS},
        {id="bars",     label=L.LOOK_TAB_BARS},
        {id="details",  label=L.LOOK_TAB_DETAILS},
    }
    self.lookSubBtns = {}
    local w, gap = 78, 2
    for i, tab in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, inner)
        btn:SetSize(w, 22)
        btn:SetPoint("TOPLEFT", inner, "TOPLEFT", (i - 1) * (w + gap), 0)
        self:FillBg(btn, 0.07, 0.07, 0.09, 1)
        self:CreateBorder(btn, 0.22, 0.22, 0.28, 1)
        btn.bg = btn:CreateTexture(nil, "BORDER")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0, 0.65, 1, 0.18)
        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(ns:LocaleFont(), 10, "OUTLINE")
        text:SetPoint("CENTER")
        text:SetText(tab.label)
        text:SetTextColor(0.6, 0.6, 0.6)
        btn.text = text
        btn:SetScript("OnClick", function() self:ShowLookSubPage(tab.id) end)
        btn:SetScript("OnEnter", function() if self.activeLookSubPage ~= tab.id then text:SetTextColor(1, 1, 1) end end)
        btn:SetScript("OnLeave", function() if self.activeLookSubPage ~= tab.id then text:SetTextColor(0.6, 0.6, 0.6) end end)
        self.lookSubBtns[tab.id] = btn
    end
end

function Config:AddFontSettingsBlock(parent, y, title, fields, defaultSize, refreshFn)
    y = self:H(parent, title, y)
    local fonts = self:GetSharedMediaFonts()
    local outlines = self:GetSharedMediaFontOutlines()
    local dbKey=fields.dbKey or "display"
    local function getDB() return (ns.db and ns.db[dbKey]) or {} end
    local function getFont() local db=getDB(); return db[fields.font] or db.font or STANDARD_TEXT_FONT end
    local function getSize() local db=getDB(); return db[fields.size] or defaultSize end
    local function getOutline() local db=getDB(); return db[fields.outline] or db.fontOutline or "OUTLINE" end
    local function getShadow() local db=getDB(); return db[fields.shadow] or false end
    local function getColor()
        local db=getDB()
        local c = db[fields.color] or fields.colorFallback or {1, 1, 1, 1}
        return c[1], c[2], c[3], c[4]
    end
    local fontDropdown
    y,fontDropdown = self:Dropdown(parent, L.CONFIG_FONT_FAMILY, y, fonts, getFont, function(v) local db=getDB(); db[fields.font] = v; refreshFn() end)
    self._fontDropdowns=self._fontDropdowns or {}; self._fontDropdowns[#self._fontDropdowns+1]=fontDropdown
    y = self:Slider(parent, L.CONFIG_FONT_SIZE, y, 8, 22, 1, getSize, function(v) local db=getDB(); db[fields.size] = v; refreshFn() end)
    y = self:Dropdown(parent, L.CONFIG_FONT_OUTLINE, y, outlines, getOutline, function(v) local db=getDB(); db[fields.outline] = v; refreshFn() end)
    y = self:Check(parent, L.CONFIG_ENABLE_TEXT_SHADOW, y, getShadow, function(v) local db=getDB(); db[fields.shadow] = v; refreshFn() end)
    if fields.color then
        y = self:ColorSwatch(parent, fields.colorLabel or L.CONFIG_FONT_COLOR, y, getColor,
            function(r, g, b, a) local db=getDB(); db[fields.color] = {r, g, b, a}; refreshFn() end)
    end
    return y - 8
end

function Config:RefreshMediaOptions()
    local fonts=self:GetSharedMediaFonts()
    for _,dropdown in ipairs(self._fontDropdowns or {}) do
        if dropdown and dropdown.UpdateOpts then dropdown.UpdateOpts(fonts) end
    end
end

function Config:AddDataTitleColorControls(parent, y, refreshFn)
    if not ns.db.display.dataTitleColors then ns.db.display.dataTitleColors = {} end
    local function Add(label, key, fallback)
        y = self:ColorSwatch(parent, label, y,
            function()
                local colors=ns.db.display.dataTitleColors or {}
                local c = colors[key] or fallback
                return c[1], c[2], c[3], c[4] or 1
            end,
            function(r, g, b, a)
                ns.db.display.dataTitleColors=ns.db.display.dataTitleColors or {}
                local colors=ns.db.display.dataTitleColors
                colors[key] = {r, g, b, a}
                if refreshFn then refreshFn() elseif ns.UI then ns.UI:Refresh() end
            end)
    end
    local fallbacks = {
        damage = {1.0, 0.82, 0.0, 1}, healing = {0.4, 1.0, 0.4, 1},
        interrupts = {0.0, 0.65, 1.0, 1}, dispels = {0.0, 0.65, 1.0, 1},
        deaths = {0.0, 0.65, 1.0, 1}, damageTaken = {1.0, 0.3, 0.3, 1},
        avoidableDamageTaken = {1.0, 0.65, 0.1, 1}, enemyDamageTaken = {1.0, 0.3, 0.3, 1},
    }
    for _, mode in ipairs(ns.MODE_ORDER) do
        Add(L[ns.MODE_NAMES[mode] or mode] .. L.CONFIG_TITLE_COLOR_SUFFIX, mode,
            fallbacks[mode] or {1, 1, 1, 1})
    end
    return y
end

function Config:BuildLookPage()
    local inner = self.pages["look"].inner
    self._fontDropdowns={}
    local textures = self:GetSharedMediaTextures()
    self:BuildLookSubTabs(inner)

    self.lookSubPages = {}
    local function NewSubPage(id)
        local page = CreateFrame("Frame", nil, inner)
        page:SetWidth(inner:GetWidth())
        page:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -34)
        page:Hide()
        self.lookSubPages[id] = page
        return page
    end
    local function RefreshFonts()
        if ns.UI then
            ns.UI._lastFontHash = nil
            -- A font/shadow edit must repaint the bars even if the player is in
            -- combat, so bypass the Tier-1 "nothing changed" render gate.
            ns.UI._barsDirty = true
            ns.UI:ApplyAllFonts()
            ns.UI:LayoutTabs()
            ns.UI:Refresh()
        end
        self:RefreshUI()
    end

    local page = NewSubPage("general"); local y = 0
    y = self:H(page, L.CONFIG_MAIN_WINDOW, y)
    y = self:Slider(page, L.CONFIG_WINDOW_SCALE, y, 0.5, 2.0, 0.05, function() return ns.db.window.scale end, function(v) ns.db.window.scale = v; if ns.UI and ns.UI.frame then ns.UI.frame:SetScale(v); ns.UI:LayoutTabs() end end)
    y = self:Slider(page, L.CONFIG_WINDOW_OPACITY, y, 0.1, 1.0, 0.05, function() return ns.db.window.alpha or 0.92 end, function(v) ns.db.window.alpha = v; if ns.UI and ns.UI.frame then ns.UI.frame:SetAlpha(v) end end, true)
    y = self:Check(page, L.CONFIG_LOCK_WINDOW, y, function() return ns.db.window.locked end, function(v) ns.db.window.locked = v; if ns.UI then ns.UI:UpdateLockState() end end)
    y = y - 12; y = self:H(page, L.CONFIG_ICON_STYLE, y)
    y = self:Dropdown(page, L.CONFIG_SPEC_ICON_PACK, y,
        { {l=L.DEFAULT, v="default"}, {l="Apex", v="apex"}, {l="Cartoon", v="cartoon"}, {l="ToxiUI", v="toxiui"} , {l="LightDamage", v="lightdamage"}},
        function() return ns.db.display.iconPack or "default" end,
        function(v) ns.db.display.iconPack = v; self:RefreshUI() end)
    page:SetHeight(math.abs(y) + 8)

    page = NewSubPage("colors"); y = 0
    y = self:H(page, L.CONFIG_WINDOW_AND_BACKGROUND_COLORS, y)
    y = self:ColorSwatch(page, L.CONFIG_TITLE_TAB_THEME_COLOR, y, function() local c = ns.db.window.themeColor or {0, 0, 0, 1}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.themeColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)
    y = self:ColorSwatch(page, L.CONFIG_DATA_BACKGROUND_COLOR, y, function() local c = ns.db.window.bgColor or {0.02, 0.02, 0.025, 0.80}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.bgColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)
    y = self:ColorSwatch(page, L.CONFIG_OVERALL_COLUMN_BACKGROUND_COLOR, y, function() local c = ns.db.window.ovrBgColor or {0.025, 0.035, 0.05, 0.82}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.ovrBgColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)
    y = y - 8; y = self:H(page, L.CONFIG_DATA_TITLE_COLORS, y)
    y = self:AddDataTitleColorControls(page, y, RefreshFonts)
    page:SetHeight(math.abs(y) + 8)

    page = NewSubPage("fonts"); y = 0
    -- The shadow is a fixed (+1, -1) drop with no size control: it is drawn by
    -- the addon (the client never paints FontString shadows) and one real pixel
    -- is the whole point of a drop shadow at these font sizes.
    y = self:AddFontSettingsBlock(page, y, L.CONFIG_BASE_TEXT_FONT_SETTINGS, {font="font", size="fontSizeBase", outline="fontOutline", shadow="fontShadow", color="fontColor", colorFallback={1, 1, 1, 0.93}}, 13, RefreshFonts)
    y = self:AddFontSettingsBlock(page, y, L.CONFIG_TOP_TITLE_FONT_SETTINGS, {font="titleFont", size="titleFontSize", outline="titleFontOutline", shadow="titleFontShadow", color="titleFontColor", colorFallback={1, 1, 1, 0.93}}, 10, RefreshFonts)
    y = self:AddFontSettingsBlock(page, y, L.CONFIG_DATA_HEADER_FONT_SETTINGS, {font="headerFont", size="headerFontSize", outline="headerFontOutline", shadow="headerFontShadow"}, 9, RefreshFonts)
    y = self:AddFontSettingsBlock(page, y, L.CONFIG_PLAYER_NAME_FONT_SETTINGS, {font="nameFont", size="nameFontSize", outline="nameFontOutline", shadow="nameFontShadow"}, 13, RefreshFonts)
    local nameColorModeOpts = {{l=L.CONFIG_CLASS_COLOR, v="class"}, {l=L.CUSTOM, v="custom"}}
    y = self:Dropdown(page, L.CONFIG_PLAYER_NAME_COLOR_MODE, y, nameColorModeOpts,
        function() return ns.db.display.nameColorMode or "class" end,
        function(v) ns.db.display.nameColorMode = v; RefreshFonts() end)
    y = self:ColorSwatch(page, L.CONFIG_CUSTOM_PLAYER_NAME_COLOR, y,
        function() local c = ns.db.display.nameFontColor or {1, 1, 1, 1}; return c[1], c[2], c[3], c[4] end,
        function(r, g, b, a) ns.db.display.nameFontColor = {r, g, b, a}; RefreshFonts() end)
    y = self:AddFontSettingsBlock(page, y, L.CONFIG_BOTTOM_TAB_FONT_SETTINGS, {font="tabFont", size="tabFontSize", outline="tabFontOutline", shadow="tabFontShadow", color="tabActiveFontColor", colorLabel=L.CONFIG_TAB_ACTIVE_FONT_COLOR, colorFallback={1, 1, 1, 1}}, 9, RefreshFonts)
    y = self:ColorSwatch(page, L.CONFIG_TAB_INACTIVE_FONT_COLOR, y, function() local c = ns.db.display.tabInactiveFontColor or {0.55, 0.55, 0.55, 0.9}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.display.tabInactiveFontColor = {r, g, b, a}; RefreshFonts() end)
    page:SetHeight(math.abs(y) + 8)

    page = NewSubPage("bars"); y = 0
    y = self:H(page, L.CONFIG_BAR_APPEARANCE, y)
    y = self:Slider(page, L.CONFIG_LAYOUT_ROW_HEIGHT_TEXT_ICON_AREA, y, 10, 30, 1, function() return ns.db.display.barHeight end, function(v) ns.db.display.barHeight=v; self:RefreshUI() end)
    y = self:Slider(page, L.CONFIG_BAR_ACTUAL_THICKNESS, y, 1, 30, 1, function() return ns.db.display.barThickness or ns.db.display.barHeight or 19 end, function(v) ns.db.display.barThickness=v; self:RefreshUI() end)
    y = self:Slider(page, L.CONFIG_BAR_VERTICAL_OFFSET_BOTTOM_UP, y, 0, 30, 1, function() return ns.db.display.barVOffset or 0 end, function(v) ns.db.display.barVOffset=v; self:RefreshUI() end)
    y = self:Slider(page, L.CONFIG_DATA_BAR_SPACING, y, 0, 10, 1, function() return ns.db.display.barGap or 1 end, function(v) ns.db.display.barGap=v; self:RefreshUI() end)
    y = self:Slider(page, L.CONFIG_DATA_BAR_OPACITY, y, 0.1, 1.0, 0.05, function() return ns.db.display.barAlpha or 0.85 end, function(v) ns.db.display.barAlpha=v; self:RefreshUI() end)
    y = self:Dropdown(page, L.CONFIG_DATA_BAR_MATERIAL, y, textures, function() return ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8" end, function(v) ns.db.display.barTexture=v; self:RefreshUI() end)
    page:SetHeight(math.abs(y) + 8)

    page = NewSubPage("details"); y = 0
    y = self:H(page, L.SPELL_DETAILS_APPEARANCE, y)
    y = self:Slider(page, L.CONFIG_LAYOUT_ROW_HEIGHT_TEXT_ICON_AREA, y, 10, 40, 1, function() return ns.db.detailDisplay.barHeight end, function(v) ns.db.detailDisplay.barHeight=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(page, L.CONFIG_BAR_ACTUAL_THICKNESS, y, 1, 40, 1, function() return ns.db.detailDisplay.barThickness or ns.db.detailDisplay.barHeight or 20 end, function(v) ns.db.detailDisplay.barThickness=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(page, L.CONFIG_BAR_VERTICAL_OFFSET_BOTTOM_UP, y, 0, 30, 1, function() return ns.db.detailDisplay.barVOffset or 0 end, function(v) ns.db.detailDisplay.barVOffset=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(page, L.CONFIG_DATA_BAR_SPACING, y, 0, 10, 1, function() return ns.db.detailDisplay.barGap or 1 end, function(v) ns.db.detailDisplay.barGap=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(page, L.CONFIG_DATA_BAR_OPACITY, y, 0.1, 1.0, 0.05, function() return ns.db.detailDisplay.barAlpha or 0.92 end, function(v) ns.db.detailDisplay.barAlpha=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Dropdown(page, L.CONFIG_DATA_BAR_MATERIAL, y, textures, function() return ns.db.detailDisplay.barTexture or "Interface\\Buttons\\WHITE8X8" end, function(v) ns.db.detailDisplay.barTexture=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    local detailBarColorModeOpts = {{l=L.CONFIG_DEFAULT_COLORS, v="default"}, {l=L.CUSTOM, v="custom"}}
    y = self:Dropdown(page, L.CONFIG_DETAIL_BAR_COLOR_MODE, y, detailBarColorModeOpts,
        function() return ns.db.detailDisplay.barColorMode or "default" end,
        function(v) ns.db.detailDisplay.barColorMode = v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:ColorSwatch(page, L.CONFIG_DETAIL_CUSTOM_BAR_COLOR, y,
        function() local c = ns.db.detailDisplay.barColor or {0, 0.65, 1, 0.92}; return c[1], c[2], c[3], c[4] end,
        function(r, g, b, a) ns.db.detailDisplay.barColor = {r, g, b, a}; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:AddFontSettingsBlock(page, y, L.CONFIG_SPELL_DETAILS_FONT, {dbKey="detailDisplay", font="font", size="fontSizeBase", outline="fontOutline", shadow="fontShadow", color="fontColor", colorFallback={1, 1, 1, 1}}, 10,
        function() if ns.DetailView then ns.DetailView:ApplyTheme(); ns.DetailView:Refresh() end end)
    page:SetHeight(math.abs(y) + 8)

    self:ShowLookSubPage(self.activeLookSubPage or "general")
end
