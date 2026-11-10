--[[
    Light Damage - ConfigTools.lua
    设置页面：小工具 (Final Fantasy XIV 风格目标箭头、角色面板物品等级、姓名板增益提醒)
    所有方法挂载到 ns.Config 上（ConfigCore.lua 已创建）

    Compact layout: one switch per tool, its explanation behind the "?" next
    to it; the reminder's two options side by side under its switch; the buff
    list one row per class with two buffs a row (paladins take two rows), its
    rules behind the list's own "?".
]]
local addonName, ns = ...
local L = ns.L
local Config = ns.Config

local INDENT     = 24   -- the reminder's own options, under its switch
local SUB_COL2   = 300  -- the second option column, from the page's left edge
local CLASS_W    = 80   -- the buff list's class name column
local BUFF_COL_W = 230  -- each of the buff list's two columns
local ROW_H      = 22

-- A frame `x` px in from the page's left edge: Config:Check anchors at its
-- parent's top-left, so a check placed on it sits in that column.
local function Column(p, x)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", p, "TOPLEFT", x, 0)
    f:SetSize(1, 1)
    return f
end

local function Tools()
    ns.db.tools = type(ns.db.tools) == "table" and ns.db.tools or {}
    return ns.db.tools
end

local function BuffSettings()
    local tools = Tools()
    tools.nameplateBuffs = type(tools.nameplateBuffs) == "table" and tools.nameplateBuffs or {}
    local s = tools.nameplateBuffs
    s.families = type(s.families) == "table" and s.families or {}
    return s
end

-- A class name in the class colour, at the start of that class's buff row.
function Config:ToolsClassHeader(p, x, y, class)
    local t = p:CreateFontString(nil, "OVERLAY")
    t:SetFont(ns:LocaleFont(), 11, "OUTLINE")
    t:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
    local c = ns.CLASS_COLORS and ns.CLASS_COLORS[class] or {0.8, 0.8, 0.8}
    t:SetTextColor(c[1], c[2], c[3])
    t:SetText(name)
end

-- A plain label with a "?" that explains it (the look of Config:Check's).
function Config:ToolsLabel(p, x, y, text, tip)
    local t = p:CreateFontString(nil, "OVERLAY")
    t:SetFont(ns:LocaleFont(), 11, "")
    t:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    t:SetTextColor(0.8, 0.8, 0.8)
    t:SetText(text)
    if tip then
        local qm = CreateFrame("Frame", nil, p); qm:SetSize(14, 14); qm:SetPoint("LEFT", t, "RIGHT", 4, 0); qm:EnableMouse(true)
        local qt = qm:CreateFontString(nil, "OVERLAY"); qt:SetFont(ns:LocaleFont(), 11, "OUTLINE"); qt:SetPoint("CENTER"); qt:SetText("?"); qt:SetTextColor(0, 0.75, 1)
        qm:SetScript("OnEnter", function(self2) qt:SetTextColor(0.2, 0.85, 1); GameTooltip:SetOwner(self2, "ANCHOR_TOPRIGHT"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
        qm:SetScript("OnLeave", function() qt:SetTextColor(0, 0.75, 1); GameTooltip:Hide() end)
    end
    return y - ROW_H
end

-- Buff labels whose spell the client has not loaded yet (WoW Forever streams
-- spell data from the server, so a spell this character has never met reads
-- as nothing).  Each shows the addon's translation until the client answers
-- SPELL_DATA_LOAD_RESULT, then is redrawn with the spell's own name and icon.
local waiting = {}             -- spell id -> { {fam=, label=}, ... }
local loader
local function OnSpellData(_, _, spellID)
    local list = waiting[spellID]
    if not list then return end
    waiting[spellID] = nil
    local NB = ns.NameplateBuffs
    for _, w in ipairs(list) do
        local text, loaded = NB:FamilyLabel(w.fam)
        if loaded then w.label:SetText(text) end
    end
    if not next(waiting) then loader:UnregisterEvent("SPELL_DATA_LOAD_RESULT") end
end

local function RedrawWhenLoaded(fam, label)
    local NB = ns.NameplateBuffs
    if not (label and label.SetText) then return end
    local id = fam.icon
    local list = waiting[id]
    if not list then list = {}; waiting[id] = list end
    list[#list + 1] = {fam = fam, label = label}
    if not loader then
        loader = CreateFrame("Frame")
        loader:SetScript("OnEvent", OnSpellData)
    end
    loader:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    if not NB:RequestFamilyData(fam) then waiting[id] = nil end
end

-- A status line (why a tool does nothing right now), in a warning colour.
function Config:ToolsNote(p, y, text)
    local d = p:CreateFontString(nil, "OVERLAY")
    d:SetFont(ns:LocaleFont(), 10, "")
    d:SetPoint("TOPLEFT", 4, y)
    d:SetWidth(p:GetWidth() - 10)
    d:SetJustifyH("LEFT")
    d:SetTextColor(1, 0.65, 0.2)
    d:SetText(text)
    local h = d:GetStringHeight()
    if not h or h == 0 then h = 13 end
    return y - h - 10
end

function Config:BuildToolsPage()
    local inner = self.pages["tools"].inner
    local y = 0
    y = self:H(inner, L.CATEGORY_TOOLS, y)

    -- One switch per tool; what it does is under its "?".
    local arrow, itemLevel, NB = ns.TargetArrow, ns.ItemLevel, ns.NameplateBuffs
    local function ApplyBuffs() if NB then NB:Apply() end end

    y = self:Check(inner, L.TOOLS_TARGET_ARROW, y,
        function() return Tools().targetArrow == true end,
        function(v) Tools().targetArrow = v and true or false; if arrow then arrow:Apply() end end,
        L.TOOLS_TARGET_ARROW_DESC)
    if arrow and arrow:IsStandaloneLoaded() then
        y = self:ToolsNote(inner, y, string.format(L.TOOLS_STANDALONE_ACTIVE, "TargetArrow", "TargetArrow"))
    end

    y = self:Check(inner, L.TOOLS_ITEM_LEVEL, y,
        function() return Tools().itemLevel == true end,
        function(v) Tools().itemLevel = v and true or false; if itemLevel then itemLevel:Apply() end end,
        L.TOOLS_ITEM_LEVEL_DESC)

    y = self:Check(inner, L.TOOLS_NAMEPLATE_BUFFS, y,
        function() return BuffSettings().enabled == true end,
        function(v) BuffSettings().enabled = v and true or false; ApplyBuffs() end,
        L.TOOLS_NAMEPLATE_BUFFS_DESC)
    if NB and NB:IsStandaloneLoaded() then
        y = self:ToolsNote(inner, y, string.format(L.TOOLS_STANDALONE_ACTIVE, "NameplateFortitude", "NameplateFortitude"))
    end

    -- The reminder's two options, side by side under its switch.
    self:Check(Column(inner, INDENT), L.TOOLS_ONLY_MY_CLASS, y,
        function() return BuffSettings().onlyMyClass ~= false end,
        function(v) BuffSettings().onlyMyClass = v and true or false; ApplyBuffs() end,
        L.TOOLS_ONLY_MY_CLASS_TIP)
    y = self:Check(Column(inner, SUB_COL2), L.TOOLS_SHOW_MISSING, y,
        function() return BuffSettings().showMissing ~= false end,
        function(v) BuffSettings().showMissing = v and true or false; ApplyBuffs() end,
        L.TOOLS_SHOW_MISSING_TIP)

    -- Which buffs: one row per class, two buffs a row.
    y = self:ToolsLabel(inner, INDENT + 4, y - 1, L.TOOLS_BUFF_LIST, L.TOOLS_BUFF_LIST_DESC)
    if NB then
        local columns = {
            Column(inner, INDENT + CLASS_W),
            Column(inner, INDENT + CLASS_W + BUFF_COL_W),
        }
        for _, class in ipairs(NB.CLASS_ORDER) do
            self:ToolsClassHeader(inner, INDENT + 4, y - 1, class)
            local n = 0
            for _, fam in ipairs(NB.FAMILIES) do
                if fam.class == class then
                    n = n + 1
                    if n > 1 and n % 2 == 1 then y = y - ROW_H end
                    local key = fam.key
                    local text, loaded = NB:FamilyLabel(fam)
                    local _, label = self:Check(columns[(n - 1) % 2 + 1], text, y,
                        function() return BuffSettings().families[key] ~= false end,
                        function(v) BuffSettings().families[key] = v and true or false; ApplyBuffs() end)
                    if not loaded then RedrawWhenLoaded(fam, label) end
                end
            end
            y = y - ROW_H
        end
    end

    inner:SetHeight(math.abs(y) + 30)
    self:UpdatePageScroll("tools")
end
