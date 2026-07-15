-- Addon-owned tooltip channels.
--
-- Opaque combat values are rendered only by ordinary FontStrings.  They never
-- enter GameTooltip's line storage, where secret-value support is undocumented.
-- Public spell tooltips keep a separate GameTooltip channel so the native spell
-- description and links remain intact after combat.
local addonName, ns = ...

local PrivateTooltip = {}
ns.PrivateTooltip = PrivateTooltip

local OPAQUE_WIDTH = 280
local ROW_HEIGHT = 15
local PAD_X, PAD_Y = 10, 9

local function clearFontString(fs)
    if fs.ClearText then fs:ClearText() else fs:SetText("") end
end

local function createOpaqueTooltip()
    local frame = CreateFrame("Frame", "LightDamageOpaqueTooltip", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:SetSize(OPAQUE_WIDTH, PAD_Y * 2 + ROW_HEIGHT)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    frame:SetBackdropColor(0.035, 0.035, 0.055, 0.96)
    frame:SetBackdropBorderColor(0.45, 0.55, 0.70, 1)
    frame._rows = {}
    frame._lineCount = 0
    frame._contentHeight = 0

    -- UI:AnchorTooltipToWindow supplies the final anchor immediately after
    -- SetOwner.  Keep the familiar API without inheriting GameTooltipTemplate.
    function frame:SetOwner(owner)
        self._owner = owner
    end

    local function acquireRow(self, index)
        local row = self._rows[index]
        if row then return row end
        row = {}
        row.left = self:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.left:SetPoint("TOPLEFT", self, "TOPLEFT", PAD_X, -PAD_Y)
        row.left:SetSize(OPAQUE_WIDTH - PAD_X * 2, ROW_HEIGHT)
        row.right = self:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        row.right:SetJustifyH("RIGHT")
        row.right:SetWordWrap(false)
        row.right:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD_X, -PAD_Y)
        row.right:SetSize(104, ROW_HEIGHT)
        self._rows[index] = row
        return row
    end

    function frame:ClearLines()
        self._lineCount = 0
        self._contentHeight = 0
        for _, row in ipairs(self._rows) do
            clearFontString(row.left)
            clearFontString(row.right)
            row.left:Hide()
            row.right:Hide()
        end
        self:SetHeight(PAD_Y * 2 + ROW_HEIGHT)
    end

    function frame:NumLines()
        return self._lineCount
    end

    function frame:AddLine(value, r, g, b)
        self._lineCount = self._lineCount + 1
        local row = acquireRow(self, self._lineCount)
        local public = not ns.DamageMeterGateway or ns.DamageMeterGateway:IsAccessible(value)
        local multiline = public and type(value) == "string" and #value > 42
        local rowHeight = multiline and (ROW_HEIGHT * 2) or ROW_HEIGHT
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", self, "TOPLEFT", PAD_X, -PAD_Y - self._contentHeight)
        row.left:SetWidth(OPAQUE_WIDTH - PAD_X * 2)
        row.left:SetHeight(rowHeight)
        row.left:SetWordWrap(multiline)
        row.left:SetTextColor(r or 1, g or 1, b or 1)
        row.left:SetText(value)
        row.left:Show()
        clearFontString(row.right)
        row.right:Hide()
        self._contentHeight = self._contentHeight + rowHeight
        self:SetHeight(PAD_Y * 2 + self._contentHeight)
    end

    function frame:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
        self._lineCount = self._lineCount + 1
        local row = acquireRow(self, self._lineCount)
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", self, "TOPLEFT", PAD_X, -PAD_Y - self._contentHeight)
        row.right:ClearAllPoints()
        row.right:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD_X, -PAD_Y - self._contentHeight)
        row.left:SetWidth(OPAQUE_WIDTH - PAD_X * 2 - 108)
        row.left:SetHeight(ROW_HEIGHT)
        row.left:SetWordWrap(false)
        row.right:SetHeight(ROW_HEIGHT)
        row.left:SetTextColor(lr or 1, lg or 1, lb or 1)
        row.right:SetTextColor(rr or 1, rg or 1, rb or 1)
        -- Values are assigned directly.  Do not concatenate, stringify, measure
        -- or use either value as a Lua table key: either side may be opaque.
        row.left:SetText(left)
        row.right:SetText(right)
        row.left:Show()
        row.right:Show()
        self._contentHeight = self._contentHeight + ROW_HEIGHT
        self:SetHeight(PAD_Y * 2 + self._contentHeight)
    end

    frame:Hide()
    return frame
end

function PrivateTooltip:GetOpaque()
    if not self.opaqueFrame then self.opaqueFrame = createOpaqueTooltip() end
    self.opaqueFrame:Hide()
    self.opaqueFrame:ClearLines()
    return self.opaqueFrame
end

-- Public-only native tooltip channel.  Callers must never add secret values.
function PrivateTooltip:Get()
    if not self.frame then
        self.frame = CreateFrame("GameTooltip", "LightDamagePrivateTooltip", UIParent, "GameTooltipTemplate")
        self.frame:SetFrameStrata("TOOLTIP")
    end
    self.frame:Hide()
    self.frame:ClearLines()
    return self.frame
end

function PrivateTooltip:Hide()
    if self.opaqueFrame then self.opaqueFrame:Hide(); self.opaqueFrame:ClearLines() end
    if self.frame then self.frame:Hide(); self.frame:ClearLines() end
end
