--[[
    LD Combat Stats - HistoryList.lua
    历史段落选择器

    ★ 改造说明 (虚拟段架构):
    - SetupItem 用 entry.key / entry.localID / entry.sessionID 判断高亮
    - delBtn 不再 table.remove,改为 Segments:HideSession(entry) 黑名单
    - clearBtn 一键清野外:批量黑名单 + (野外时) ResetAllCombatSessions + 清 sessionID 黑名单
]]

local addonName, ns = ...
local L = ns.L

local HL = {}
ns.HistoryList = HL

local LIST_W   = 220
local ITEM_H   = 20
local MAX_SHOW = 12

local T = {
    bg       = {0.04, 0.04, 0.07, 0.97},
    border   = {0.22, 0.22, 0.30, 0.90},
    hover    = {0.15, 0.45, 0.75, 0.30},
    active   = {0.10, 0.60, 1.00, 0.25},
    text     = {1,    1,    1,    0.90},
    dim      = {0.55, 0.55, 0.55, 0.85},
    sep      = {0.25, 0.25, 0.30, 0.60},
}

function HL:EnsureCreated()
    if self.frame then return end
    self:Build()
end

function HL:Build()
    local f = CreateFrame("Frame", "LightDamageHistory", UIParent, "BackdropTemplate")
    f:SetWidth(LIST_W)
    f:SetFrameStrata("HIGH"); f:SetFrameLevel(100)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(unpack(T.bg))

    local bc = ns.db and ns.db.window and ns.db.window.borderColor or {0.2, 0.2, 0.25, 1}
    f:SetBackdropBorderColor(unpack(bc))
    f:Hide(); f:EnableMouse(true)
    f:SetScript("OnHide", function() self._open = false end)

    local clickOut = CreateFrame("Frame", nil, UIParent)
    clickOut:SetAllPoints(UIParent); clickOut:SetFrameStrata("HIGH"); clickOut:SetFrameLevel(99)
    clickOut:EnableMouse(true); clickOut:Hide()
    clickOut:SetScript("OnMouseDown", function() self:Hide() end)
    self._clickOut = clickOut

    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", 1, -1)
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(LIST_W - 18)
    sf:SetScrollChild(child)

    local sb = CreateFrame("Slider", nil, sf)
    sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 0, 0)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(1); sb:SetValue(0)
    sb:SetWidth(4); sb:SetOrientation("VERTICAL")

    local sbTrack = sb:CreateTexture(nil, "BACKGROUND")
    sbTrack:SetAllPoints()
    sbTrack:SetColorTexture(0.05, 0.05, 0.06, 1)

    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local sbThumb = sb:GetThumbTexture()
    sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1)
    sbThumb:SetSize(4, 30)

    sb:SetScript("OnEnter", function() sbThumb:SetVertexColor(0.4, 0.4, 0.45, 1) end)
    sb:SetScript("OnLeave", function() sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1) end)

    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local maxVal = select(2, sb:GetMinMaxValues())
        sb:SetValue(math.max(0, math.min(maxVal, cur - delta * ITEM_H * 2)))
    end)
    sb:SetScript("OnValueChanged", function(_, value) sf:SetVerticalScroll(value) end)

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(unpack(T.sep))
    local pinned = CreateFrame("Frame", nil, f)

    -- 一键清空野外按钮
    local clrBtn = CreateFrame("Button", nil, f)
    clrBtn:SetHeight(18)
    local cbBg = clrBtn:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints(); cbBg:SetColorTexture(0.20, 0.05, 0.05, 0.8)
    local cbHl = clrBtn:CreateTexture(nil, "HIGHLIGHT")
    cbHl:SetAllPoints(); cbHl:SetColorTexture(0.40, 0.10, 0.10, 0.9)
    local cbTxt = clrBtn:CreateFontString(nil, "OVERLAY")
    cbTxt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    cbTxt:SetPoint("CENTER")
    cbTxt:SetText(L["[一键清空野外战斗]"])
    cbTxt:SetTextColor(1, 0.4, 0.4)

    clrBtn:SetScript("OnClick", function()
        if not ns.Segments then self:Hide(); return end
        local segs = ns.Segments
        self:Hide()

        -- 1. 清掉所有标记为野外的归档段
        ns.db.hiddenLocalIDs = ns.db.hiddenLocalIDs or {}
        local cleared = 0
        for _, seg in ipairs(segs.history) do
            if seg._wasOutdoor
               and not seg._isBoss
               and not seg._isMerged
               and seg._localID
            then
                ns.db.hiddenLocalIDs[seg._localID] = true
                cleared = cleared + 1
            end
        end

        -- 2. 当前在野外:暴雪 API 的 sessions 全是野外产生的,直接 reset 干掉所有虚拟段
        --    当前在副本:不动 meter,副本里跑的 sessions 都要保留
        if not ns.state.isInInstance then
            if ns.CombatTracker then
                ns.CombatTracker:ResetMeterForNewRun()
            end
            segs.overall = segs:NewSegment("overall", L["总计"])
        end

        -- 3. 视图修正：清完后总是跳到合并列表第一条
        local merged = segs:GetMergedSegmentList()
        if merged[1] then
            if merged[1]._isVirtual then
                segs:ViewVirtual(merged[1]._sessionID)
            elseif merged[1]._localID then
                segs:ViewArchived(merged[1]._localID)
            end
        else
            segs:ViewCurrent()
        end

        if ns.SaveSessionHistory then ns:SaveSessionHistory() end
        if ns.Analysis then ns.Analysis:InvalidateCache() end
        if ns.UI then ns.UI:Refresh() end

        print(L["|cff00ccff[Light Damage]|r 已清空所有野外历史记录，只保留副本与首领战数据。"])
    end)
    self.clearBtn = clrBtn

    self.frame = f; self.scrollFrame = sf; self.scrollChild = child
    self.scrollBar = sb; self.sep = sep; self.pinnedContainer = pinned
    self._histItems = {}; self._pinnedItems = {}; self._open = false
end

function HL:Toggle(anchorFrame)
    self:EnsureCreated()
    if self._open then self:Hide() else self:Show(anchorFrame) end
end

function HL:Show(anchorFrame)
    self:Rebuild()
    self.frame:ClearAllPoints()
    if anchorFrame then
        self.frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 2)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER")
    end
    self.frame:Show(); self._clickOut:Show(); self._open = true
end

function HL:Hide()
    if self.frame then self.frame:Hide() end
    if self._clickOut then self._clickOut:Hide() end
    self._open = false
end

function HL:Rebuild()
    local segs = ns.Segments
    if not segs then self.frame:Hide(); return end
    local list = segs:GetHistoryList()
    if not list or #list == 0 then self.frame:Hide(); return end

    -- 分离常驻项 (current) 和历史区项 (archived/virtual)
    local histData = {}; local pinnedData = {}
    for _, data in ipairs(list) do
        if data.key == "current" then
            table.insert(pinnedData, data)
        elseif data.key == "archived" or data.key == "virtual" then
            table.insert(histData, data)
        end
        -- overall 不显示在弹出列表里(原行为一致)
    end

    local curKey, curID = segs:GetViewKey()   -- ★ key-based
    local isLocked = segs._locked

    for i, data in ipairs(histData) do
        local item = self._histItems[i]
        if not item then item = self:MakeItem(self.scrollChild); self._histItems[i] = item end
        self:SetupItem(item, data, curKey, curID, isLocked)
        item.frame:ClearAllPoints()
        item.frame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(i-1)*ITEM_H)
        item.frame:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, -(i-1)*ITEM_H)
        item.frame:Show()
    end
    for i = #histData + 1, #self._histItems do self._histItems[i].frame:Hide() end

    for i, data in ipairs(pinnedData) do
        local item = self._pinnedItems[i]
        if not item then item = self:MakeItem(self.pinnedContainer); self._pinnedItems[i] = item end
        self:SetupItem(item, data, curKey, curID, isLocked)
        item.frame:ClearAllPoints()
        item.frame:SetPoint("TOPLEFT", self.pinnedContainer, "TOPLEFT", 1, -(i-1)*ITEM_H)
        item.frame:SetPoint("TOPRIGHT", self.pinnedContainer, "TOPRIGHT", -1, -(i-1)*ITEM_H)
        item.frame:Show()
    end
    for i = #pinnedData + 1, #self._pinnedItems do self._pinnedItems[i].frame:Hide() end

    local showHistCount = math.min(#histData, MAX_SHOW)
    local histHeight = showHistCount * ITEM_H
    local pinnedHeight = #pinnedData * ITEM_H

    self.scrollChild:SetHeight(#histData * ITEM_H)
    if #histData > MAX_SHOW then
        self.scrollFrame:SetHeight(histHeight)
        self.scrollBar:SetMinMaxValues(0, (#histData - MAX_SHOW) * ITEM_H)
        self.scrollBar:Show()
        self.scrollFrame:SetPoint("TOPRIGHT", -5, -1)
    else
        self.scrollFrame:SetHeight(histHeight)
        self.scrollBar:SetMinMaxValues(0, 0)
        self.scrollBar:Hide()
        self.scrollFrame:SetPoint("TOPRIGHT", -1, -1)
    end

    self.sep:ClearAllPoints()
    self.sep:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -(histHeight + 2))
    self.sep:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -4, -(histHeight + 2))

    if #histData > 0 and #pinnedData > 0 then
        self.sep:Show()
        self.pinnedContainer:SetPoint("TOPLEFT", self.sep, "BOTTOMLEFT", -4, -2)
        self.pinnedContainer:SetPoint("TOPRIGHT", self.sep, "BOTTOMRIGHT", 4, -2)
    else
        self.sep:Hide()
        self.pinnedContainer:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -(histHeight + 1))
        self.pinnedContainer:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -(histHeight + 1))
    end
    self.pinnedContainer:SetHeight(pinnedHeight)

    self.clearBtn:ClearAllPoints()
    self.clearBtn:SetPoint("TOPLEFT", self.pinnedContainer, "BOTTOMLEFT", 1, -2)
    self.clearBtn:SetPoint("TOPRIGHT", self.pinnedContainer, "BOTTOMRIGHT", -1, -2)

    local totalFrameHeight = histHeight + pinnedHeight + 18 + (#histData > 0 and #pinnedData > 0 and 5 or 2) + 2
    self.frame:SetHeight(totalFrameHeight)

    if #histData > MAX_SHOW then
        local maxVal = (#histData - MAX_SHOW) * ITEM_H
        self.scrollBar:SetValue(maxVal)
        self.scrollFrame:SetVerticalScroll(maxVal)
    end
end

function HL:SetupItem(item, data, curKey, curID, isLocked)
    item.data = data; item.text:SetText(data.label)
    local isHistEntry = (data.key == "archived" or data.key == "virtual")

    -- ★ 高亮判定:key 一致 + ID 一致(overall/current 没有 ID,key 一致即可)
    local isActive = false
    if data.key == curKey then
        if data.key == "overall" or data.key == "current" then
            isActive = true
        elseif data.key == "archived" and data.localID == curID then
            isActive = true
        elseif data.key == "virtual" and data.sessionID == curID then
            isActive = true
        end
    end

    -- 战斗中允许查看,但禁止隐藏(防止竞态)
    if isHistEntry and not isLocked then
        item.delBtn:Show()
    else
        item.delBtn:Hide()
    end

    if isActive then
        item.activeBg:Show(); item.text:SetTextColor(1, 1, 1, 1)
    else
        item.activeBg:Hide(); item.text:SetTextColor(unpack(T.text))
    end
    item.frame:SetEnabled(true)
end

function HL:MakeItem(parent)
    local item = {}
    local f = CreateFrame("Button", nil, parent); f:SetHeight(ITEM_H)

    local activeBg = f:CreateTexture(nil, "BACKGROUND"); activeBg:SetAllPoints(); activeBg:SetColorTexture(unpack(T.active)); activeBg:Hide()
    item.activeBg = activeBg
    local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(unpack(T.hover))

    local delBtn = CreateFrame("Button", nil, f)
    delBtn:SetSize(16, 16)
    delBtn:SetPoint("RIGHT", -4, 0)
    local delTxt = delBtn:CreateFontString(nil, "OVERLAY")
    delTxt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    delTxt:SetPoint("CENTER")
    delTxt:SetText("X")
    delTxt:SetTextColor(0.6, 0.2, 0.2)
    delBtn:SetScript("OnEnter", function() delTxt:SetTextColor(1, 0.2, 0.2) end)
    delBtn:SetScript("OnLeave", function() delTxt:SetTextColor(0.6, 0.2, 0.2) end)
    item.delBtn = delBtn

    local txt = f:CreateFontString(nil, "OVERLAY"); txt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    txt:SetPoint("LEFT", 8, 0)
    txt:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
    txt:SetJustifyH("LEFT"); txt:SetWordWrap(false)
    item.text = txt

    -- ★ 删除按钮:不再 table.remove,改为 HideSession 加黑名单
    delBtn:SetScript("OnClick", function()
        local data = item.data
        if not data or not ns.Segments then return end
        if ns.Segments._locked then return end

        ns.Segments:HideSession(data)

        if ns.SaveSessionHistory then ns:SaveSessionHistory() end
        if ns.UI then ns.UI:Refresh() end
        self:Rebuild()
    end)

    f:SetScript("OnClick", function()
        local data = item.data; if not data then return end
        if ns.Segments then
            if data.key == "current" then ns.Segments:ViewCurrent()
            elseif data.key == "overall" then ns.Segments:ViewOverall()
            elseif data.key == "archived" then ns.Segments:ViewArchived(data.localID)
            elseif data.key == "virtual" then ns.Segments:ViewVirtual(data.sessionID) end
            if ns.Analysis then ns.Analysis:InvalidateCache() end
            if ns.UI then ns.UI:Refresh() end
        end
        self:Hide()
    end)

    item.frame = f
    return item
end

function HL:IsOpen() return self._open end