--[[
    Light Damage - ConfigTools.lua
    设置页面：小工具 (Final Fantasy XIV 风格目标箭头、姓名板增益提醒)
    所有方法挂载到 ns.Config 上（ConfigCore.lua 已创建）
]]
local addonName, ns = ...
local L = ns.L
local Config = ns.Config

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

-- A class name line in the class colour, above that class's buffs.
function Config:ToolsClassHeader(p, y, class)
    local t = p:CreateFontString(nil, "OVERLAY")
    t:SetFont(ns:LocaleFont(), 11, "OUTLINE")
    t:SetPoint("TOPLEFT", 4, y)
    local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
    local c = ns.CLASS_COLORS and ns.CLASS_COLORS[class] or {0.8, 0.8, 0.8}
    t:SetTextColor(c[1], c[2], c[3])
    t:SetText(name)
    return y - 20
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

    -- Final Fantasy XIV-style target arrow
    local arrow = ns.TargetArrow
    y = self:H(inner, L.TOOLS_TARGET_ARROW, y)
    y = self:Desc(inner, y, L.TOOLS_TARGET_ARROW_DESC)
    if arrow and arrow:IsStandaloneLoaded() then
        y = self:ToolsNote(inner, y, string.format(L.TOOLS_STANDALONE_ACTIVE, "TargetArrow", "TargetArrow"))
    end
    y = self:Check(inner, L.TOOLS_ENABLE, y,
        function() return Tools().targetArrow == true end,
        function(v) Tools().targetArrow = v and true or false; if arrow then arrow:Apply() end end)
    y = y - 16

    -- Nameplate buff reminder
    local NB = ns.NameplateBuffs
    local function ApplyBuffs() if NB then NB:Apply() end end
    y = self:H(inner, L.TOOLS_NAMEPLATE_BUFFS, y)
    y = self:Desc(inner, y, L.TOOLS_NAMEPLATE_BUFFS_DESC)
    if NB and NB:IsStandaloneLoaded() then
        y = self:ToolsNote(inner, y, string.format(L.TOOLS_STANDALONE_ACTIVE, "NameplateFortitude", "NameplateFortitude"))
    end
    y = self:Check(inner, L.TOOLS_ENABLE, y,
        function() return BuffSettings().enabled == true end,
        function(v) BuffSettings().enabled = v and true or false; ApplyBuffs() end)
    y = self:Check(inner, L.TOOLS_ONLY_MY_CLASS, y,
        function() return BuffSettings().onlyMyClass ~= false end,
        function(v) BuffSettings().onlyMyClass = v and true or false; ApplyBuffs() end,
        L.TOOLS_ONLY_MY_CLASS_TIP)
    y = self:Check(inner, L.TOOLS_SHOW_MISSING, y,
        function() return BuffSettings().showMissing ~= false end,
        function(v) BuffSettings().showMissing = v and true or false; ApplyBuffs() end,
        L.TOOLS_SHOW_MISSING_TIP)
    y = y - 8

    y = self:H(inner, L.TOOLS_BUFF_LIST, y)
    y = self:Desc(inner, y, L.TOOLS_BUFF_LIST_DESC)
    if NB then
        for _, class in ipairs(NB.CLASS_ORDER) do
            y = self:ToolsClassHeader(inner, y, class)
            for _, fam in ipairs(NB.FAMILIES) do
                if fam.class == class then
                    local key = fam.key
                    local text, loaded = NB:FamilyLabel(fam)
                    local label
                    y, label = self:Check(inner, text, y,
                        function() return BuffSettings().families[key] ~= false end,
                        function(v) BuffSettings().families[key] = v and true or false; ApplyBuffs() end)
                    if not loaded then RedrawWhenLoaded(fam, label) end
                end
            end
            y = y - 4
        end
    end

    inner:SetHeight(math.abs(y) + 30)
    self:UpdatePageScroll("tools")
end
