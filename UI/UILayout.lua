--[[
    Light Damage - UILayout.lua
    排版：AnchorBarTexts, PrioritizeBarValue (窗口与网格布局见 UIGrid.lua)
]]

local addonName, ns = ...
local L = ns.L
local UI = ns.UI

function UI:AnchorBarTexts(bar)
    local rowH = ns.db.display.barHeight or 18
    local iconSize = rowH
    local thickness = ns.db.display.barThickness or rowH
    local vOffset = ns.db.display.barVOffset or 0
    local showIcon = ns.db.display.showSpecIcon

    local frameLevel = bar.frame:GetFrameLevel()
    local width = math.floor((bar.frame:GetWidth() or 0) + .5)
    if bar._anchorValid and bar._anchorShowIcon == showIcon
        and bar._anchorRowH == rowH and bar._anchorThickness == thickness
        and bar._anchorVOffset == vOffset and bar._anchorFrameLevel == frameLevel
        and bar._anchorWidth == width then return end
    bar._anchorValid = true
    bar._anchorShowIcon = showIcon; bar._anchorRowH = rowH
    bar._anchorThickness = thickness; bar._anchorVOffset = vOffset
    bar._anchorFrameLevel = frameLevel; bar._anchorWidth = width

    -- ★ 强制层级：数据条在底，文字/icon 在上
    bar.statusbar:SetFrameLevel(frameLevel + 1)
    bar.textFrame:SetFrameLevel(frameLevel + 5)

    local offset = 0

    if showIcon then
        bar.specIcon:SetSize(iconSize, iconSize)
        bar.specIcon:ClearAllPoints()
        bar.specIcon:SetPoint("LEFT", bar.frame, "LEFT", 2, 0)
        bar.specIcon:SetDrawLayer("OVERLAY", 7)

        offset = iconSize + 4
    else
        bar.specIcon:Hide()
        offset = 0
    end

    -- ★ 数据条不铺满，仍然从 icon 后面开始
    bar.bg:ClearAllPoints()
    bar.bg:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
    bar.bg:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
    bar.bg:SetHeight(thickness)
    bar.bg:SetDrawLayer("BACKGROUND", 0)

    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
    bar.fill:SetHeight(thickness)
    bar.fill:SetDrawLayer("BORDER", 0)

    bar.statusbar:ClearAllPoints()
    bar.statusbar:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
    bar.statusbar:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
    bar.statusbar:SetHeight(thickness)

    local tex = bar.statusbar:GetStatusBarTexture()
    if tex then
        tex:SetDrawLayer("BORDER", 1)
    end

    -- ★ 文字区域也从 icon 后面开始；没 icon 时自然靠左
    bar.textFrame:ClearAllPoints()
    if showIcon then
        bar.textFrame:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", offset, 0)
        bar.textFrame:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, 0)
    else
        bar.textFrame:SetAllPoints(bar.frame)
    end

    bar.rank:ClearAllPoints()
    bar.rank:SetPoint("LEFT", bar.textFrame, "LEFT", 3, 0)

    bar.value:ClearAllPoints()
    bar.value:SetPoint("RIGHT", bar.textFrame, "RIGHT", -2, 0)
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 3, 0)
    bar.name:SetPoint("RIGHT", bar.value, "LEFT", -5, 0)
    if bar.rawName then
        bar.rawName:ClearAllPoints()
        bar.rawName:SetPoint("LEFT", bar.rank, "RIGHT", 3, 0)
        bar.rawName:SetPoint("RIGHT", bar.value, "LEFT", -5, 0)
    end
    -- Every name string now hangs off bar.value; PrioritizeBarValue's anchor
    -- memo must re-derive from this state.
    bar._valuePointSet = true
    bar._prioName = nil; bar._prioValue = nil
end

-- Restore the 1.4.6 row contract: the value owns only a right anchor and keeps
-- its natural width; the name is bounded by the rank on the left and whichever
-- value FontString is active on the right. Protected values remain isolated in
-- dedicated FontStrings, but their geometry is handed back to the client rather
-- than guessed from probes. This also matches Details' rule that narrowing the
-- window compresses the name while rank, icon, total and rate remain present.
function UI:PrioritizeBarValue(bar, isSecret)
    if not bar or not bar.frame or not bar.value then return end
    local activeValue=bar.value
    if isSecret and bar.rawValue then
        bar.value:Hide()
        bar.rawBothLayer:Hide(); bar.rawTotalLayer:Hide(); bar.rawCountLayer:Hide()
        if bar._showingRawRate then
            bar.rawBothLayer:Show(); activeValue=bar.rawValue
        elseif bar._showingRawSuffix then
            bar.rawCountLayer:Show(); activeValue=bar.rawCountValue
        else
            bar.rawTotalLayer:Show(); activeValue=bar.rawTotalValue
        end
    else
        bar.rawBothLayer:Hide(); bar.rawTotalLayer:Hide(); bar.rawCountLayer:Hide()
        bar.value:Show()
        if not bar._valuePointSet then
            bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT",bar.textFrame,"RIGHT",-2,0)
            bar._valuePointSet = true
        end
    end

    -- FillBars controls whether the rank has text; never remove the configured
    -- column merely because the row is narrow.
    bar.rank:Show()
    local activeName=(bar.rawName and bar.rawName:IsShown()) and bar.rawName or bar.name
    -- Re-anchoring forces a text re-layout; this runs on every combat tick, so
    -- only move the name when the active name/value pair actually changed.
    if bar._prioName ~= activeName or bar._prioValue ~= activeValue then
        activeName:ClearAllPoints()
        activeName:SetPoint("LEFT",bar.rank,"RIGHT",3,0)
        activeName:SetPoint("RIGHT",activeValue,"LEFT",-5,0)
        bar._prioName = activeName; bar._prioValue = activeValue
    end
    bar._valueIsSecret=isSecret and true or false
end
