--[[
    Light Damage - ItemLevel.lua  (WoW Forever)
    Tools: item levels on the character panel.

    * Each equipped item's level at the bottom of its slot, in the item's
      quality colour.  Shirt, tabard and ammo carry none (nor do they on
      retail).
    * The average equipped item level, centred under the paper doll's sidebar
      tabs (the top-right icons), shown and hidden with them.

    Built on Blizzard's own Forever character frame (CharacterHeadSlot ...,
    PaperDollSidebarTabs), so it works on the stock sheet and under skins such
    as EllesmereUI's, with or without them installed.

    A slot is painted from Blizzard's own per-slot update
    (PaperDollItemSlotButton_Update, hooked), so it runs only when Blizzard
    repaints that slot.  WoW Forever streams item data from the server: a slot
    whose item the client has not loaded yet waits on GET_ITEM_INFO_RECEIVED,
    which is listened to only while such a slot waits.  The average is
    Blizzard's own figure (PaperDollFrame_SetItemLevel on Forever): the
    equipped average or the client's minimum item level, whichever is higher,
    rounded down.  Off (the default): no events, and nothing drawn.
    Settings: ns.db.tools.itemLevel.
]]
local addonName, ns = ...
local L = ns.L

local IL = {}
ns.ItemLevel = IL

local SLOT_FONT_SIZE = 12
local AVERAGE_FONT_SIZE = 12
local SLOT_TEXT_Y = 2          -- the slot text's baseline, up from the slot's bottom edge

-- The slots that carry an item level, by Blizzard's button names.
local SLOT_NAMES = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}
local IS_LEVEL_SLOT = {}
for _, name in ipairs(SLOT_NAMES) do IS_LEVEL_SLOT[name] = true end

local active = false
local hooked = false
local texts = {}               -- slot button -> its item level FontString
local waiting = {}             -- slot button -> true while its item data is not loaded
local averageText
local events = CreateFrame("Frame")

local function Enabled()
    local tools = ns.db and ns.db.tools
    return tools and tools.itemLevel == true
end

-- The equipped item's level: its ItemLocation first (exact for that very
-- piece, uncached), then its link (EllesmereUI's GetEquippedItemLevel).
-- nil while the client has not loaded the item.
local function EquippedLevel(slotID)
    if ItemLocation and C_Item.GetCurrentItemLevel then
        local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
        if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
            local level = C_Item.GetCurrentItemLevel(loc)
            if type(level) == "number" and level > 0 then return level end
        end
    end
    local link = GetInventoryItemLink("player", slotID)
    if link then
        local level = C_Item.GetDetailedItemLevelInfo(link)
        if type(level) == "number" and level > 0 then return level end
    end
    return nil
end

-- One text per slot, on a mouse-transparent layer above the slot's own art
-- and any skin's border, at the bottom of the icon.
local function SlotText(button)
    local fs = texts[button]
    if fs then return fs end
    local layer = CreateFrame("Frame", nil, button)
    layer:SetAllPoints(button)
    layer:SetFrameLevel(button:GetFrameLevel() + 5)
    layer:EnableMouse(false)
    fs = layer:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns:LocaleFont(), SLOT_FONT_SIZE, "OUTLINE")
    fs:SetPoint("BOTTOM", button, "BOTTOM", 0, SLOT_TEXT_Y)
    fs:SetJustifyH("CENTER")
    fs:Hide()
    texts[button] = fs
    return fs
end

local function WaitForItemData(button)
    waiting[button] = true
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

local function PaintSlot(button)
    if not active then return end
    local fs = SlotText(button)
    local slotID = button:GetID()
    if not GetInventoryItemLink("player", slotID) then
        waiting[button] = nil
        fs:Hide()
        return
    end
    local level = EquippedLevel(slotID)
    if not level then
        fs:Hide()
        WaitForItemData(button)
        return
    end
    waiting[button] = nil
    local r, g, b = 1, 1, 1
    local quality = GetInventoryItemQuality("player", slotID)
    if quality and C_Item.GetItemQualityColor then
        local qr, qg, qb = C_Item.GetItemQualityColor(quality)
        if qr then r, g, b = qr, qg, qb end
    end
    fs:SetText(level)
    fs:SetTextColor(r, g, b)
    fs:Show()
end

-- Blizzard's own "Item Level" figure on Forever.
local function AverageLevel()
    local _, equipped = GetAverageItemLevel()
    local minLevel = C_PaperDollInfo and C_PaperDollInfo.GetMinItemLevel and C_PaperDollInfo.GetMinItemLevel()
    return math.floor(math.max(minLevel or 0, equipped or 0))
end

-- Centred under the sidebar tabs, which Blizzard shows only on the paper
-- doll with its right pane open: the text shows and hides with them.
local function AverageText()
    if averageText then return averageText end
    local tabs = _G.PaperDollSidebarTabs
    if not tabs then return nil end
    averageText = tabs:CreateFontString(nil, "OVERLAY")
    averageText:SetFont(ns:LocaleFont(), AVERAGE_FONT_SIZE, "OUTLINE")
    averageText:SetJustifyH("CENTER")
    averageText:Hide()
    return averageText
end

local function PaintAverage()
    local fs = AverageText()
    if not fs then return end
    local level = active and AverageLevel() or 0
    if level <= 0 then fs:Hide() return end
    -- The tabs sit 5px down from the top of their frame (PaperDollFrame.lua).
    local tab = _G.PaperDollSidebarTab2 or _G.PaperDollSidebarTab1
    local drop = 5 + ((tab and tab:GetHeight()) or 32) + 4
    fs:ClearAllPoints()
    fs:SetPoint("TOP", _G.PaperDollSidebarTabs, "TOP", 0, -drop)
    fs:SetFormattedText(L.TOOLS_ITEM_LEVEL_AVERAGE, level)
    fs:SetTextColor(1, 0.82, 0)
    fs:Show()
end

local function PaintAll()
    for _, name in ipairs(SLOT_NAMES) do
        local button = _G[name]
        if button then PaintSlot(button) end
    end
    PaintAverage()
end

local function PaperDollShown()
    local frame = _G.PaperDollFrame
    return frame and frame:IsVisible()
end

events:SetScript("OnEvent", function(_, event)
    if event == "GET_ITEM_INFO_RECEIVED" then
        for button in pairs(waiting) do PaintSlot(button) end
        if not next(waiting) then events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
        if active and PaperDollShown() then PaintAverage() end
    elseif event == "ADDON_LOADED" then
        if _G.PaperDollFrame then
            events:UnregisterEvent("ADDON_LOADED")
            IL:Apply()
        end
    else -- PLAYER_EQUIPMENT_CHANGED, PLAYER_AVG_ITEM_LEVEL_UPDATE
        if active and PaperDollShown() then PaintAverage() end
    end
end)

-- Hooks are permanent; each does nothing while the tool is off.
local function Hook()
    if hooked then return end
    hooked = true
    hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
        if active and button and IS_LEVEL_SLOT[button:GetName() or ""] then PaintSlot(button) end
    end)
    _G.PaperDollFrame:HookScript("OnShow", function()
        if active then PaintAll() end
    end)
end

function IL:IsActive() return active end

-- Follows ns.db.tools.itemLevel: on hooks Blizzard's character frame (once)
-- and paints; off hides every text and drops the events.
function IL:Apply()
    if Enabled() and not _G.PaperDollFrame then
        -- The character frame's addon has not loaded yet: try again when it does.
        events:RegisterEvent("ADDON_LOADED")
        return
    end
    local want = Enabled() and true or false
    if want then
        Hook()
        active = true
        events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        events:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
        PaintAll()
    else
        active = false
        events:UnregisterAllEvents()
        wipe(waiting)
        for _, fs in pairs(texts) do fs:Hide() end
        if averageText then averageText:Hide() end
    end
end
