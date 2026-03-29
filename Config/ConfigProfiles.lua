--[[
    Light Damage - ConfigProfiles.lua
    配置管理页
]]
local addonName, ns = ...
local L = ns.L
local Config = ns.Config

StaticPopupDialogs["LIGHTDMG_RENAME_PROFILE"] = {
    text = L["输入新的配置名称:"], button1 = L["确定"], button2 = L["取消"], hasEditBox = 1,
    OnAccept = function(self, data)
        local eb = self.EditBox or self.editBox or _G[self:GetName().."EditBox"]; local newName = eb:GetText():trim()
        if newName ~= "" and newName ~= data then
            if LightDamageGlobal.profiles[newName] then print(L["配置名称已存在！"])
            else ns:RenameProfile(data, newName); if ns.Config then ns.Config:RefreshProfilesPage() end end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent(); local newName = self:GetText():trim(); local oldName = popup.data
        if newName ~= "" and newName ~= oldName then
            if LightDamageGlobal.profiles[newName] then print(L["配置名称已存在！"])
            else ns:RenameProfile(oldName, newName); if ns.Config then ns.Config:RefreshProfilesPage() end; popup:Hide() end
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["LIGHTDMG_CONFIRM_DELETE"] = {
    text = L["确定要删除配置 '%s' 吗？"], button1 = L["确定"], button2 = L["取消"],
    OnAccept = function(self, data) ns:DeleteProfile(data); if ns.Config then ns.Config:RefreshProfilesPage() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Config:BuildProfilesPage()
    local inner = self.pages["profiles"].inner; self._profileInner = inner
end

function Config:RefreshProfilesPage()
    local inner = self._profileInner; if not inner then return end
    for _, child in ipairs({inner:GetChildren()}) do child:Hide() end
    for _, region in ipairs({inner:GetRegions()}) do region:Hide() end

    local y = 0
    local curName = LightDamageDB.activeProfile or "默认"
    local displayCurName = (curName == "默认") and L["默认"] or curName
    y = self:H(inner, L["当前配置"] .. ": " .. displayCurName, y)

    local input = CreateFrame("EditBox", nil, inner); input:SetSize(180, 20); input:SetPoint("TOPLEFT", 6, y)
    input:SetAutoFocus(false); input:SetFontObject(ChatFontNormal)
    self:FillBg(input, 0.1, 0.1, 0.15, 1); self:CreateBorder(input, 0.3, 0.3, 0.4, 1); input:SetTextInsets(5, 5, 0, 0)
    local createBtn = CreateFrame("Button", nil, inner); createBtn:SetSize(80, 20); createBtn:SetPoint("LEFT", input, "RIGHT", 10, 0)
    self:FillBg(createBtn, 0.05, 0.20, 0.35, 1); self:CreateBorder(createBtn, 0.1, 0.45, 0.75, 1)
    local ct = createBtn:CreateFontString(nil, "OVERLAY"); ct:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); ct:SetPoint("CENTER"); ct:SetText(L["创建新配置"]); ct:SetTextColor(0.4, 0.85, 1)
    createBtn:SetScript("OnEnter", function() ct:SetTextColor(1, 1, 1) end); createBtn:SetScript("OnLeave", function() ct:SetTextColor(0.4, 0.85, 1) end)
    createBtn:SetScript("OnClick", function()
        local txt = input:GetText():trim()
        if txt ~= "" and not LightDamageGlobal.profiles[txt] then ns:CreateProfile(txt); self:RefreshProfilesPage()
        else print(L["配置名称不能为空或已存在"]) end
    end)

    y = y - 35; y = self:H(inner, L["已存配置"], y)
    for pName, _ in pairs(LightDamageGlobal.profiles) do
        local isSelf = (pName == curName); local displayName = (pName == "默认") and L["默认"] or pName
        local txt = inner:CreateFontString(nil, "OVERLAY"); txt:SetFont(STANDARD_TEXT_FONT, 11, isSelf and "OUTLINE" or "")
        txt:SetPoint("TOPLEFT", 6, y); txt:SetTextColor(isSelf and 0.5 or 0.85, isSelf and 0.8 or 0.85, isSelf and 1.0 or 0.85)
        txt:SetText(displayName .. (isSelf and (" |cff888888["..L["当前"].."]|r") or ""))

        local lastBtn = nil
        if not isSelf then
            local applyBtn = CreateFrame("Button", nil, inner); applyBtn:SetSize(50, 18); applyBtn:SetPoint("TOPLEFT", 180, y)
            self:FillBg(applyBtn, 0.05, 0.18, 0.30, 1); self:CreateBorder(applyBtn, 0.1, 0.4, 0.7, 1)
            local at = applyBtn:CreateFontString(nil, "OVERLAY"); at:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); at:SetPoint("CENTER"); at:SetText(L["应用"]); at:SetTextColor(0.4, 0.85, 1)
            applyBtn:SetScript("OnEnter", function() at:SetTextColor(1, 1, 1) end); applyBtn:SetScript("OnLeave", function() at:SetTextColor(0.4, 0.85, 1) end)
            applyBtn:SetScript("OnClick", function() ns:SwitchProfile(pName); self:RefreshProfilesPage() end); lastBtn = applyBtn
        end
        if pName ~= "默认" then
            local renBtn = CreateFrame("Button", nil, inner); renBtn:SetSize(50, 18)
            if lastBtn then renBtn:SetPoint("LEFT", lastBtn, "RIGHT", 8, 0) else renBtn:SetPoint("TOPLEFT", 180, y) end
            self:FillBg(renBtn, 0.2, 0.2, 0.25, 1); self:CreateBorder(renBtn, 0.4, 0.4, 0.5, 1)
            local rt = renBtn:CreateFontString(nil, "OVERLAY"); rt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); rt:SetPoint("CENTER"); rt:SetText(L["改名"]); rt:SetTextColor(0.8, 0.8, 0.8)
            renBtn:SetScript("OnEnter", function() rt:SetTextColor(1, 1, 1) end); renBtn:SetScript("OnLeave", function() rt:SetTextColor(0.8, 0.8, 0.8) end)
            renBtn:SetScript("OnClick", function()
                StaticPopupDialogs["LIGHTDMG_RENAME_PROFILE"].text = L["输入新的配置名称:"]; StaticPopupDialogs["LIGHTDMG_RENAME_PROFILE"].button1 = L["确定"]; StaticPopupDialogs["LIGHTDMG_RENAME_PROFILE"].button2 = L["取消"]
                local dialog = StaticPopup_Show("LIGHTDMG_RENAME_PROFILE"); if dialog then dialog.data = pName; local eb = dialog.EditBox or dialog.editBox or _G[dialog:GetName().."EditBox"]; if eb then eb:SetText(pName); eb:HighlightText() end end
            end); lastBtn = renBtn
            if not isSelf then
                local delBtn = CreateFrame("Button", nil, inner); delBtn:SetSize(50, 18); delBtn:SetPoint("LEFT", lastBtn, "RIGHT", 8, 0)
                self:FillBg(delBtn, 0.3, 0.05, 0.05, 1); self:CreateBorder(delBtn, 0.7, 0.1, 0.1, 1)
                local dt = delBtn:CreateFontString(nil, "OVERLAY"); dt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); dt:SetPoint("CENTER"); dt:SetText(L["删除"]); dt:SetTextColor(1, 0.4, 0.4)
                delBtn:SetScript("OnEnter", function() dt:SetTextColor(1, 1, 1) end); delBtn:SetScript("OnLeave", function() dt:SetTextColor(1, 0.4, 0.4) end)
                delBtn:SetScript("OnClick", function()
                    StaticPopupDialogs["LIGHTDMG_CONFIRM_DELETE"].text = L["确定要删除配置 '%s' 吗？"]; StaticPopupDialogs["LIGHTDMG_CONFIRM_DELETE"].button1 = L["确定"]; StaticPopupDialogs["LIGHTDMG_CONFIRM_DELETE"].button2 = L["取消"]
                    local dialog = StaticPopup_Show("LIGHTDMG_CONFIRM_DELETE", pName); if dialog then dialog.data = pName end
                end)
            end
        end
        y = y - 26
    end
    inner:SetHeight(math.abs(y) + 20)
end
