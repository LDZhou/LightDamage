--[[
    Light Damage - UITabs.lua
    底部标签栏
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local TAB_H = UI.TAB_H

function UI:BuildTabs()
    local tb = CreateFrame("Frame", nil, self.frame)
    tb:SetHeight(TAB_H); tb:SetPoint("BOTTOMLEFT",0,0); tb:SetPoint("BOTTOMRIGHT",0,0)
    self.tabBg = self:FillBg(tb, {0.05, 0.05, 0.07, 1}); self.tabBar = tb

    local st = CreateFrame("Button", nil, tb)
    st.abg = st:CreateTexture(nil,"BORDER"); st.abg:SetAllPoints(); st.abg:SetColorTexture(0,0.65,1,0.22); st.abg:Hide()
    st.text = self:FS(st, 9, "OUTLINE"); st.text:SetPoint("CENTER"); st.text:SetTextColor(0.55, 0.55, 0.55, 0.9)
    st:SetScript("OnClick", function() ns.db.display.mode = "split"; self:Layout() end)
    self.splitTab = st

    local defs = { {m="damage",l=L["伤害"]},{m="healing",l=L["治疗"]},{m="damageTaken",l=L["承伤"]},{m="deaths",l=L["死亡"]},{m="interrupts",l=L["打断"]},{m="dispels",l=L["驱散"]} }
    self.tabs = {}
    for i, d in ipairs(defs) do
        local t = CreateFrame("Button", nil, tb)
        t.abg = t:CreateTexture(nil,"BORDER"); t.abg:SetAllPoints(); t.abg:SetColorTexture(0, 0.65, 1, 0.3); t.abg:Hide()
        t.text = self:FS(t, 9, "OUTLINE"); t.text:SetPoint("CENTER"); t.text:SetText(d.l); t.text:SetTextColor(0.55, 0.55, 0.55, 0.9)
        t.mode = d.m
        t:SetScript("OnClick", function() ns.db.display.mode = d.m; self:Layout() end)
        self.tabs[i] = t
    end
end

function UI:LayoutTabs()
    if not self.tabs or not self.splitTab then return end
    local w = self.tabBar:GetWidth(); if w <= 0 then return end
    local sp = ns.db and ns.db.split; local visible = {}
    local isSplitActive = self:IsSplitActiveInCurrentScene()
    local useShort = ns.db and ns.db.display and ns.db.display.useShortTabs
    if sp and isSplitActive then
        local pName, sName
        if useShort and ns.MODE_SHORT[sp.primaryMode] then pName = L[ns.MODE_SHORT[sp.primaryMode]]
        else pName = L[ns.MODE_NAMES[sp.primaryMode] or sp.primaryMode] end
        if useShort and ns.MODE_SHORT[sp.secondaryMode] then sName = L[ns.MODE_SHORT[sp.secondaryMode]]
        else sName = L[ns.MODE_NAMES[sp.secondaryMode] or sp.secondaryMode] end
        self.splitTab.text:SetText(pName .. "|" .. sName); self.splitTab:Show(); table.insert(visible, self.splitTab)
    else self.splitTab:Hide() end
    for _, t in ipairs(self.tabs) do
        if t.mode and ns.MODE_NAMES[t.mode] then
            if useShort and ns.MODE_SHORT[t.mode] then
                t.text:SetText(L[ns.MODE_SHORT[t.mode]])
            else
                t.text:SetText(L[ns.MODE_NAMES[t.mode]])
            end
        end
        if sp and isSplitActive and (t.mode == sp.primaryMode or t.mode == sp.secondaryMode) then t:Hide()
        else t:Show(); table.insert(visible, t) end
    end
    local tw = w / #visible
    for i, t in ipairs(visible) do t:ClearAllPoints(); t:SetPoint("TOPLEFT", self.tabBar, "TOPLEFT", (i-1)*tw, 0); t:SetSize(tw, TAB_H) end
end