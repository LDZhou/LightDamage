--[[
    Light Damage - ConfigPages.lua
    设置页面：Layout, Data, Look, Perf
    注意：所有方法挂载到 ns.Config 上（ConfigCore.lua 已创建）
]]
local addonName, ns = ...
local L = ns.L
local Config = ns.Config

local PANEL_W   = 500
local SIDEBAR_W = 110

-- ============================================================
-- Layout 页
-- ============================================================
function Config:BuildLayoutPage()
    local inner = self.pages["layout"].inner


    local sec1 = CreateFrame("Frame", nil, inner); sec1:SetWidth(inner:GetWidth()); local y1 = 0
    y1 = self:H(sec1, L.CONFIG_UI_LANGUAGE, y1)
    y1 = self:Dropdown(sec1, L.CONFIG_LANGUAGE_REQUIRES_RELOAD, y1, { {l=L.CONFIG_AUTO_CLIENT, v="auto"}, {l="简体中文", v="zhCN"}, {l="繁体中文", v="zhTW"}, {l="English", v="enUS"}, {l="Русский", v="ruRU"} }, function() return ns.db.display.language or "auto" end, function(v) ns.db.display.language = v; ReloadUI() end)
    sec1:SetHeight(math.abs(y1)); self.laySec1 = sec1

    local posesLR = { {l=L.LEFT, v=1}, {l=L.RIGHT, v=2} }; local posesTB = { {l=L.TOP, v=1}, {l=L.BOTTOM, v=2} }
    local dirs = { {l=L.CONFIG_LEFT_RIGHT_SPLIT, v="LR"}, {l=L.CONFIG_TOP_BOTTOM_SPLIT, v="TB"} }
    local allModes = { {l=L.DAMAGE, v="damage"}, {l=L.HEALING, v="healing"}, {l=L.DAMAGE_TAKEN, v="damageTaken"}, {l=L.DEATHS, v="deaths"}, {l=L.ENEMY_DAMAGE_TAKEN, v="enemyDamageTaken"}, {l=L.INTERRUPTS, v="interrupts"}, {l=L.DISPELS, v="dispels"} }

    local sec2 = CreateFrame("Frame", nil, inner); sec2:SetWidth(inner:GetWidth()); local y2 = 0
    y2 = self:H(sec2, L.CONFIG_CURRENT_AND_OVERALL_WINDOW, y2)
    y2 = self:Check(sec2, L.CONFIG_SHOW_CURRENT_AND_OVERALL, y2, function() return ns.db.split.showOverall end, function(v) ns.db.split.showOverall = v; self:RefreshUI(); self:UpdateLayoutVisibility() end, L.OVERALL_DATA_TOOLTIP)
    local sec2_sub = CreateFrame("Frame", nil, sec2); sec2_sub:SetWidth(inner:GetWidth() - 16); sec2_sub:SetPoint("TOPLEFT", sec2, "TOPLEFT", 16, y2); local y2s = 0
    y2s = self:Desc(sec2_sub, y2s, L.CONFIG_ENABLE_SCENARIO)
    y2s = self:Check(sec2_sub, L.MYTHIC_PLUS, y2s, function() return ns.db.split.overallShowMPlus end, function(v) ns.db.split.overallShowMPlus=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = self:Check(sec2_sub, L.RAID_INSTANCE, y2s, function() return ns.db.split.overallShowRaid end, function(v) ns.db.split.overallShowRaid=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = self:Check(sec2_sub, L.OTHER_INSTANCES_INCL_DELVES_BGS_ARENAS, y2s, function() return ns.db.split.overallShowDungeon end, function(v) ns.db.split.overallShowDungeon=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = self:Check(sec2_sub, L.NON_INSTANCE_OPEN_WORLD, y2s, function() return ns.db.split.overallShowOutdoor end, function(v) ns.db.split.overallShowOutdoor=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = y2s - 8
    local curPosBtn
    y2s, self.ovrDirBtn = self:Dropdown(sec2_sub, L.CONFIG_CURRENT_OVERALL_SPLIT, y2s, dirs, function() return ns.db.split.overallDir or "LR" end, function(v) ns.db.split.overallDir = v; ns.db.split.splitDir = (v == "LR") and "TB" or "LR"; if curPosBtn then curPosBtn.UpdateOpts(v == "TB" and posesTB or posesLR) end; if self.priPosBtn then self.priPosBtn.UpdateOpts(ns.db.split.splitDir == "TB" and posesTB or posesLR) end; if self.splitDirBtn then self.splitDirBtn.UpdateOpts(dirs) end; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s, curPosBtn = self:Dropdown(sec2_sub, L.CURRENT_DATA_POSITION, y2s, (ns.db.split.overallDir == "TB") and posesTB or posesLR, function() return ns.db.split.currentPos or 1 end, function(v) ns.db.split.currentPos = v; self:RefreshUI() end)
    sec2_sub:SetHeight(math.abs(y2s)); self.laySec2Sub = sec2_sub; self.laySec2 = sec2

    local sec3 = CreateFrame("Frame", nil, inner); sec3:SetWidth(inner:GetWidth()); local y3 = 0
    y3 = self:H(sec3, L.CONFIG_DUAL_DATA_DISPLAY, y3)
    y3 = self:Check(sec3, L.CONFIG_ENABLE_DUAL_DATA, y3, function() return ns.db.split.enabled end, function(v) ns.db.split.enabled = v; if v then if ns.db.display.mode ~= "split" then ns.db.display.mode = "split" end else if ns.db.display.mode == "split" then ns.db.display.mode = ns.db.split.primaryMode or "damage" end end; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    local sec3_sub = CreateFrame("Frame", nil, sec3); sec3_sub:SetWidth(inner:GetWidth() - 16); sec3_sub:SetPoint("TOPLEFT", sec3, "TOPLEFT", 16, y3); local y3s = 0
    y3s = self:Desc(sec3_sub, y3s, L.CONFIG_ENABLE_SCENARIO)
    y3s = self:Check(sec3_sub, L.MYTHIC_PLUS, y3s, function() return ns.db.split.splitShowMPlus end, function(v) ns.db.split.splitShowMPlus=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "mplus" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = self:Check(sec3_sub, L.RAID_INSTANCE, y3s, function() return ns.db.split.splitShowRaid end, function(v) ns.db.split.splitShowRaid=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "raid" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = self:Check(sec3_sub, L.OTHER_INSTANCES_INCL_DELVES_BGS_ARENAS, y3s, function() return ns.db.split.splitShowDungeon end, function(v) ns.db.split.splitShowDungeon=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "dungeon" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = self:Check(sec3_sub, L.NON_INSTANCE_OPEN_WORLD, y3s, function() return ns.db.split.splitShowOutdoor end, function(v) ns.db.split.splitShowOutdoor=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "outdoor" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = y3s - 8
    y3s, self.splitDirBtn = self:Dropdown(sec3_sub, L.CONFIG_DUAL_DATA_SPLIT, y3s, dirs, function() return ns.db.split.splitDir or "TB" end, function(v) ns.db.split.splitDir = v; ns.db.split.overallDir = (v == "LR") and "TB" or "LR"; if self.priPosBtn then self.priPosBtn.UpdateOpts(v == "TB" and posesTB or posesLR) end; if curPosBtn then curPosBtn.UpdateOpts(ns.db.split.overallDir == "TB" and posesTB or posesLR) end; if self.ovrDirBtn then self.ovrDirBtn.UpdateOpts(dirs) end; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y3s, self.priPosBtn = self:Dropdown(sec3_sub, L.PRIMARY_DATA_POSITION, y3s, (ns.db.split.splitDir == "TB") and posesTB or posesLR, function() return ns.db.split.primaryPos or 1 end, function(v) ns.db.split.primaryPos = v; self:RefreshUI() end)
    y3s = self:Dropdown(sec3_sub, L.CONFIG_PRIMARY_CONTENT, y3s, allModes, function() return ns.db.split.primaryMode end, function(v) ns.db.split.primaryMode=v; self:RefreshUI() end)
    y3s = self:Dropdown(sec3_sub, L.CONFIG_SECONDARY_CONTENT, y3s, allModes, function() return ns.db.split.secondaryMode end, function(v) ns.db.split.secondaryMode=v; self:RefreshUI() end)
    sec3_sub:SetHeight(math.abs(y3s)); self.laySec3Sub = sec3_sub; self.laySec3 = sec3

    local sec4 = CreateFrame("Frame", nil, inner); sec4:SetWidth(inner:GetWidth()); local y4 = 0
    y4 = self:H(sec4, L.CONFIG_ADAPTIVE_LAYOUT_RATIO, y4)
    y4 = self:Slider(sec4, L.CONFIG_TOP_BOTTOM_RATIO, y4, 0.2, 0.8, 0.01, function() return ns.db.split.tbRatio or 0.5 end, function(v) ns.db.split.tbRatio = v; self:RefreshUI() end, true)
    y4 = self:Slider(sec4, L.CONFIG_LEFT_RIGHT_RATIO, y4, 0.2, 0.8, 0.01, function() return ns.db.split.lrRatio or 0.5 end, function(v) ns.db.split.lrRatio = v; self:RefreshUI() end, true)
    sec4:SetHeight(math.abs(y4)); self.laySec4 = sec4

    local sec5 = CreateFrame("Frame", nil, inner); sec5:SetWidth(inner:GetWidth()); local y5 = 0
    y5 = self:H(sec5, L.CONFIG_PER_SCENE_WINDOW_SIZE, y5)
    y5 = self:Check(sec5, L.CONFIG_PER_SCENE_WINDOW_SIZE, y5,
        function() return ns.db.window.rememberSceneSize end,
        function(v)
            ns.db.window.rememberSceneSize = v
            if v then
                local cat = ns.state.instanceCategory or "outdoor"
                if not ns.db.window.sceneSizes then ns.db.window.sceneSizes = {} end
                if not ns.db.window.sceneSizes[cat] then
                    ns.db.window.sceneSizes[cat] = { width = ns.db.window.width, height = ns.db.window.height }
                end
            end
            self:UpdateLayoutVisibility()
        end)
    y5 = self:Desc(sec5, y5, L.SCENE_SIZE_DESC)
    self._laySec5BaseH = math.abs(y5)

    local sec5_sub = CreateFrame("Frame", nil, sec5); sec5_sub:SetWidth(inner:GetWidth() - 16); sec5_sub:SetPoint("TOPLEFT", sec5, "TOPLEFT", 16, y5); local y5s = 0
    local anchorOpts = {
        {l=L.TOP_LEFT, v="TOPLEFT"}, {l=L.TOP, v="TOP"}, {l=L.TOP_RIGHT, v="TOPRIGHT"},
        {l=L.LEFT, v="LEFT"}, {l=L.CENTER, v="CENTER"}, {l=L.RIGHT, v="RIGHT"},
        {l=L.BOTTOM_LEFT, v="BOTTOMLEFT"}, {l=L.BOTTOM, v="BOTTOM"}, {l=L.BOTTOM_RIGHT, v="BOTTOMRIGHT"},
    }
    y5s = self:Dropdown(sec5_sub, L.CONFIG_RESIZE_ANCHOR, y5s, anchorOpts,
        function() return ns.db.window.sceneAnchor or "TOPLEFT" end,
        function(v) ns.db.window.sceneAnchor = v end)
    y5s = self:Desc(sec5_sub, y5s, L.SCENE_ANCHOR_DESC)
    sec5_sub:SetHeight(math.abs(y5s)); self.laySec5Sub = sec5_sub; self.laySec5 = sec5

    self:UpdateLayoutVisibility()
end

function Config:UpdateLayoutVisibility()
    local inner = self.pages["layout"].inner
    if ns.db.split.showOverall then self.laySec2Sub:Show(); self.laySec2:SetHeight(48 + self.laySec2Sub:GetHeight()) else self.laySec2Sub:Hide(); self.laySec2:SetHeight(48) end
    if ns.db.split.enabled then self.laySec3Sub:Show(); self.laySec3:SetHeight(48 + self.laySec3Sub:GetHeight()) else self.laySec3Sub:Hide(); self.laySec3:SetHeight(48) end
    self.laySec1:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
    self.laySec2:SetPoint("TOPLEFT", self.laySec1, "BOTTOMLEFT", 0, -12)
    self.laySec3:SetPoint("TOPLEFT", self.laySec2, "BOTTOMLEFT", 0, -12)
    self.laySec4:SetPoint("TOPLEFT", self.laySec3, "BOTTOMLEFT", 0, -12)

    local sec5BaseH = self._laySec5BaseH or 48
    if ns.db.window.rememberSceneSize then self.laySec5Sub:Show(); self.laySec5:SetHeight(sec5BaseH + self.laySec5Sub:GetHeight()) else self.laySec5Sub:Hide(); self.laySec5:SetHeight(sec5BaseH) end
    self.laySec5:SetPoint("TOPLEFT", self.laySec4, "BOTTOMLEFT", 0, -12)

    local totalH = self.laySec1:GetHeight() + self.laySec2:GetHeight() + self.laySec3:GetHeight() + self.laySec4:GetHeight() + self.laySec5:GetHeight() + 60
    inner:SetHeight(totalH); self:UpdatePageScroll("layout")
end

-- ============================================================
-- Data 页
-- ============================================================
function Config:BuildBottomBarSettings(page)
    local y = 0
    y = self:H(page, L.BOTTOM_BAR_SETTINGS, y)
    y = self:Desc(page, y, L.BOTTOM_BAR_SETTINGS_DESC)
    y = self:Desc(page, y, L.BOTTOM_BAR_OVERVIEW_ALWAYS)
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
    y = self:Dropdown(page, L.BOTTOM_BAR_LABEL_STYLE, y, {
            {l=L.TAB_LABEL_STYLE_FULL, v="full"},
            {l=L.TAB_LABEL_STYLE_SHORT, v="short"},
        },
        function() return ns.db.display.tabLabelStyle=="short" and "short" or "full" end,
        function(v)
            ns.db.display.tabLabelStyle=v
            ns.db.display.useShortTabs=(v=="short")
            RefreshBottomBar()
        end)
    y = y - 8
    for _,mode in ipairs(ns.MODE_ORDER) do
        local m=mode
        y = self:Check(page, L[ns.MODE_NAMES[m] or m], y,
            function() return BottomModes()[m] == true end,
            function(v) BottomModes()[m]=v and true or false; RefreshBottomBar() end)
    end
    y = y - 8
    y = self:Desc(page, y, L.CONFIG_WHEN_ENABLED_DAMAGE_DAMAGE_HEAL_HEAL_TAKEN_TKN_DEATHS_DTH_INTERR)
    return y
end

-- Kept only as a migration/reference implementation. The active data page is
-- built by ConfigLayouts.lua; giving this legacy builder a distinct name
-- prevents load order from silently replacing either implementation again.
function Config:BuildLegacyDataPage()
    local inner = self.pages["data"].inner; local y = 0
    y = self:H(inner, L.CONFIG_DATA_DISPLAY_FORMAT, y)
    y = self:Check(inner, L.CONFIG_SHOW_TOTAL_DAMAGE_AND_DPS, y, function() return ns.db.display.showPerSecond end, function(v) ns.db.display.showPerSecond=v; self:RefreshUI() end)
    y = self:Check(inner, L.CONFIG_SHOW_CONTRIBUTION_PERCENT_OUT_OF_COMBAT, y, function() return ns.db.display.showPercent end, function(v) ns.db.display.showPercent=v; self:RefreshUI() end)
    y = self:Check(inner, L.CONFIG_SHOW_RANK_NUM, y, function() return ns.db.display.showRank end, function(v) ns.db.display.showRank=v; self:RefreshUI() end)
    y = self:Check(inner, L.CONFIG_SPEC_ICON_ON_LEFT, y, function() return ns.db.display.showSpecIcon end, function(v) ns.db.display.showSpecIcon=v; self:RefreshUI() end)
    y = self:Check(inner, L.CONFIG_SHOW_PLAYER_REALM, y, function() return ns.db.display.showRealm end, function(v) ns.db.display.showRealm=v; self:RefreshUI() end)
    y = self:Check(inner, L.CONFIG_ALWAYS_SHOW_SELF_IN_RANKING, y, function() return ns.db.display.alwaysShowSelf end, function(v) ns.db.display.alwaysShowSelf=v; self:RefreshUI() end)
    y = self:Check(inner, L.CONFIG_SHOW_OVERALL_SUMMARY_ROW_INSTANCE_ONLY, y, function() return ns.db.mythicPlus.dualDisplay end, function(v) ns.db.mythicPlus.dualDisplay=v; self:RefreshUI() end)
    self._dataTopY = y

    -- Section: 生成全程段落
    local secGen = CreateFrame("Frame", nil, inner); secGen:SetWidth(inner:GetWidth()); local yGen = 0
    yGen = self:Check(secGen, L.GENERATE_OVERALL_SEGMENT_AFTER_LEAVING_INSTANCE, yGen,
        function() return ns.db.mythicPlus.enabled end,
        function(v) ns.db.mythicPlus.enabled=v; self:UpdateDataVisibility() end)
    local dataGenSub = CreateFrame("Frame", nil, secGen); dataGenSub:SetWidth(inner:GetWidth() - 16)
    dataGenSub:SetPoint("TOPLEFT", secGen, "TOPLEFT", 16, yGen); local yg = 0
    yg = self:Desc(dataGenSub, yg, L.GENERATE_OVERALL_SEGMENT_IN)
    yg = self:Check(dataGenSub, L.MYTHIC_PLUS, yg, function() return ns.db.mythicPlus.genOverallMPlus end, function(v) ns.db.mythicPlus.genOverallMPlus=v end)
    yg = self:Check(dataGenSub, L.RAID_INSTANCE, yg, function() return ns.db.mythicPlus.genOverallRaid end, function(v) ns.db.mythicPlus.genOverallRaid=v end)
    yg = self:Check(dataGenSub, L.OTHER_INSTANCES_INCL_DELVES_BGS_ARENAS, yg, function() return ns.db.mythicPlus.genOverallDungeon end, function(v) ns.db.mythicPlus.genOverallDungeon=v end)
    dataGenSub:SetHeight(math.abs(yg))
    self._dataGenSub = dataGenSub; self._dataSecGen = secGen; self._dataSecGenBaseH = math.abs(yGen)

    -- Section: 删除小怪段落
    local secClean = CreateFrame("Frame", nil, inner); secClean:SetWidth(inner:GetWidth()); local yClean = 0
    yClean = self:Check(secClean, L.CONFIG_AUTO_DELETE_TRASH_SEGMENTS_AFTER_LEAVING_INSTANCE, yClean,
        function() return ns.db.mythicPlus.autoCleanTrash end,
        function(v) ns.db.mythicPlus.autoCleanTrash=v; self:UpdateDataVisibility() end)
    local dataCleanSub = CreateFrame("Frame", nil, secClean); dataCleanSub:SetWidth(inner:GetWidth() - 16)
    dataCleanSub:SetPoint("TOPLEFT", secClean, "TOPLEFT", 16, yClean); local yc = 0
    yc = self:Desc(dataCleanSub, yc, L.DELETE_TRASH_SEGMENTS_IN)
    yc = self:Check(dataCleanSub, L.MYTHIC_PLUS, yc, function() return ns.db.mythicPlus.cleanTrashMPlus end, function(v) ns.db.mythicPlus.cleanTrashMPlus=v end)
    yc = self:Check(dataCleanSub, L.RAID_INSTANCE, yc, function() return ns.db.mythicPlus.cleanTrashRaid end, function(v) ns.db.mythicPlus.cleanTrashRaid=v end)
    yc = self:Check(dataCleanSub, L.OTHER_INSTANCES_INCL_DELVES_BGS_ARENAS, yc, function() return ns.db.mythicPlus.cleanTrashDungeon end, function(v) ns.db.mythicPlus.cleanTrashDungeon=v end)
    dataCleanSub:SetHeight(math.abs(yc))
    self._dataCleanSub = dataCleanSub; self._dataSecClean = secClean; self._dataSecCleanBaseH = math.abs(yClean)

    -- Bottom-bar shortcuts are data navigation, so they live with data options.
    local secRest = CreateFrame("Frame", nil, inner); secRest:SetWidth(inner:GetWidth()); local yRest = 0
    yRest = self:BuildBottomBarSettings(secRest)
    secRest:SetHeight(math.abs(yRest) + 8)
    self._dataSecRest = secRest

    self:UpdateDataVisibility()
end

function Config:UpdateDataVisibility()
    if not self._dataSecGen then return end
    local inner = self.pages["data"].inner; if not inner then return end

    if ns.db.mythicPlus.enabled then
        self._dataGenSub:Show()
        self._dataSecGen:SetHeight(self._dataSecGenBaseH + self._dataGenSub:GetHeight())
    else
        self._dataGenSub:Hide()
        self._dataSecGen:SetHeight(self._dataSecGenBaseH)
    end

    if ns.db.mythicPlus.autoCleanTrash then
        self._dataCleanSub:Show()
        self._dataSecClean:SetHeight(self._dataSecCleanBaseH + self._dataCleanSub:GetHeight())
    else
        self._dataCleanSub:Hide()
        self._dataSecClean:SetHeight(self._dataSecCleanBaseH)
    end

    self._dataSecGen:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, self._dataTopY)
    self._dataSecClean:SetPoint("TOPLEFT", self._dataSecGen, "BOTTOMLEFT", 0, 0)
    self._dataSecRest:SetPoint("TOPLEFT", self._dataSecClean, "BOTTOMLEFT", 0, 0)

    local totalH = math.abs(self._dataTopY) + self._dataSecGen:GetHeight() + self._dataSecClean:GetHeight() + self._dataSecRest:GetHeight() + 20
    inner:SetHeight(totalH)
    self:UpdatePageScroll("data")
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
        text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
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
    Add(L.DAMAGE .. L.CONFIG_TITLE_COLOR_SUFFIX, "damage", {1.0, 0.82, 0.0, 1})
    Add(L.HEALING .. L.CONFIG_TITLE_COLOR_SUFFIX, "healing", {0.4, 1.0, 0.4, 1})
    Add(L.DAMAGE_TAKEN .. L.CONFIG_TITLE_COLOR_SUFFIX, "damageTaken", {1.0, 0.3, 0.3, 1})
    Add(L.ENEMY_DAMAGE_TAKEN .. L.CONFIG_TITLE_COLOR_SUFFIX, "enemyDamageTaken", {1.0, 0.3, 0.3, 1})
    Add(L.DEATHS .. L.CONFIG_TITLE_COLOR_SUFFIX, "deaths", {0.0, 0.65, 1.0, 1})
    Add(L.INTERRUPTS .. L.CONFIG_TITLE_COLOR_SUFFIX, "interrupts", {0.0, 0.65, 1.0, 1})
    Add(L.DISPELS .. L.CONFIG_TITLE_COLOR_SUFFIX, "dispels", {0.0, 0.65, 1.0, 1})
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
    y = self:ColorSwatch(page, L.CONFIG_DATA_BACKGROUND_COLOR, y, function() local c = ns.db.window.bgColor or {0.02, 0.02, 0.025, 0.58}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.bgColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)
    y = self:ColorSwatch(page, L.CONFIG_OVERALL_COLUMN_BACKGROUND_COLOR, y, function() local c = ns.db.window.ovrBgColor or {0.025, 0.035, 0.05, 0.62}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.ovrBgColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)
    y = y - 8; y = self:H(page, L.CONFIG_DATA_TITLE_COLORS, y)
    y = self:AddDataTitleColorControls(page, y, RefreshFonts)
    page:SetHeight(math.abs(y) + 8)

    page = NewSubPage("fonts"); y = 0
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

-- ============================================================
-- Perf 页
-- ============================================================
function Config:BuildPerfPage()
    local inner = self.pages["perf"].inner; local y = 0
    y = self:H(inner, L.CONFIG_SMART_REFRESH, y)
    y = self:Slider(inner, L.CONFIG_COMBAT_REFRESH_SECONDS, y, 0.1, 1.0, 0.1, function() return ns.db.smartRefresh.combatInterval end, function(v) ns.db.smartRefresh.combatInterval=v end)
    y = self:Slider(inner, L.CONFIG_OUT_OF_COMBAT_REFRESH_SECONDS, y, 0.5, 5.0, 0.5, function() return ns.db.smartRefresh.idleInterval end, function(v) ns.db.smartRefresh.idleInterval=v end)
    y = y - 12
    y = self:H(inner, L.DATA_TRACKING, y)
    y = self:Slider(inner, L.MAX_HISTORY_SEGMENTS, y, 5, 100, 1,
        function() return ns.db.tracking.historyDisplayLimit or ns.db.tracking.maxSegments or 20 end,
        function(v)
            ns.db.tracking.historyDisplayLimit = v
            ns.db.tracking.maxSegments = v -- legacy readers/migration compatibility
            ns.Segments:SetViewSegment(ns.Segments.viewIndex)
        end)
    inner:SetHeight(math.abs(y) + 20)
end
