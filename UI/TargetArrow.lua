--[[
    Light Damage - TargetArrow.lua
    Tools: the Final Fantasy XIV-style target arrow.

    The standalone TargetArrow addon (1.1), moved in unchanged: an arrow above
    the current target's nameplate that slides in on a target change and is
    coloured by who the target is.  What is new is only the switch
    (ns.db.tools.targetArrow): the frames are built on first use, and turning
    it off unregisters every event and parks the arrow.  While the standalone
    addon is still enabled this module stays off, so the arrow never shows
    twice.

    Works on WoW Forever's secret value system: on addon-restricted maps
    (dungeons, raids, PvP) some unit queries return secret values, and a
    boolean test on one raises an error.  Every such query goes through
    IsTrue(), and nameplate matching compares plate frames instead of calling
    UnitIsUnit().
]]

local addonName, ns = ...
local TA = {}
ns.TargetArrow = TA

local MEDIA = "Interface\\AddOns\\LightDamage\\Textures\\"

local issecretvalue = issecretvalue or function() return false end

-- A secret result is unknowable here; treat it as "no" and let the
-- remaining (non-secret) checks decide.
local function IsTrue(v)
    if issecretvalue(v) then return false end
    return v and true or false
end

local frame, textureFrame, baseTexture, slideAnimGroup, slide
-- The nameplate the arrow is currently attached to (nil while hidden).
local currentPlate
local active = false

local COLORS = {
    player   = {0.3, 0.6, 1.0},
    hostile  = {1.0, 0.2, 0.2},
    neutral  = {235/255, 222/255, 129/255},
    friendly = {113/255, 214/255, 64/255},
    dead     = {0.4, 0.4, 0.4},
}

local function PlaySlideIn()
    slideAnimGroup:Stop()
    textureFrame:SetAlpha(0)
    textureFrame:ClearAllPoints()
    textureFrame:SetPoint("BOTTOM", currentPlate, "TOP", 0, 45)
    slide:SetOffset(0, -25)
    slideAnimGroup:Play()
end

local function SetColor(c)
    baseTexture:SetVertexColor(c[1], c[2], c[3])
end

local function UpdateTextureColor()
    if not UnitExists("target") then return end

    if IsTrue(UnitIsUnit("target", "player"))
        or IsTrue(UnitInParty("target"))
        or IsTrue(UnitInRaid("target")) then
        SetColor(COLORS.player)
        return
    end

    if IsTrue(UnitIsDeadOrGhost("target")) then
        SetColor(COLORS.dead)
        return
    end

    if IsTrue(UnitAffectingCombat("player")) and IsTrue(UnitCanAttack("player", "target")) then
        SetColor(COLORS.hostile)
        return
    end

    if IsTrue(UnitIsPlayer("target")) then
        SetColor(COLORS.player)
        return
    end

    local reaction = UnitReaction("target", "player")
    if issecretvalue(reaction) then reaction = nil end

    if reaction then
        if reaction <= 3 then
            SetColor(COLORS.hostile)
        elseif reaction == 4 then
            SetColor(COLORS.neutral)
        else
            SetColor(COLORS.friendly)
        end
    else
        SetColor(COLORS.neutral)
    end
end

local function HideArrow()
    slideAnimGroup:Stop()
    textureFrame:Hide()
    textureFrame:ClearAllPoints()
    textureFrame:SetParent(UIParent)
    currentPlate = nil
end

local function UpdateTexturePosition(playAnimation)
    if not UnitExists("target") then
        HideArrow()
        return
    end

    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    if not nameplate then
        HideArrow()
        return
    end

    currentPlate = nameplate
    textureFrame:SetParent(nameplate)
    textureFrame:Show()
    UpdateTextureColor()

    if playAnimation then
        PlaySlideIn()
    else
        slideAnimGroup:Stop()
        textureFrame:ClearAllPoints()
        textureFrame:SetPoint("BOTTOM", nameplate, "TOP", 0, 20)
        textureFrame:SetAlpha(1)
    end
end

local function OnEvent(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        UpdateTexturePosition(true)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- Match by plate frame, not UnitIsUnit(): the comparison can be
        -- secret on restricted maps, a frame reference never is.
        if UnitExists("target") then
            local targetPlate = C_NamePlate.GetNamePlateForUnit("target")
            if targetPlate and targetPlate == C_NamePlate.GetNamePlateForUnit(unit) then
                UpdateTexturePosition(false)
            end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- Plates are recycled; leaving the arrow on a released plate would
        -- show it above whichever unit gets that plate next.
        if currentPlate and currentPlate == C_NamePlate.GetNamePlateForUnit(unit) then
            HideArrow()
        end
    else
        UpdateTextureColor()
    end
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame")
    textureFrame = CreateFrame("Frame", nil, UIParent)

    textureFrame:SetSize(90, 90)
    textureFrame:Hide()

    baseTexture = textureFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    baseTexture:SetAllPoints()
    baseTexture:SetTexture(MEDIA .. "TargetArrow.tga")

    local overlayTexture = textureFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    overlayTexture:SetAllPoints()
    overlayTexture:SetTexture(MEDIA .. "TargetArrow2.tga")
    overlayTexture:SetVertexColor(1, 1, 1)

    slideAnimGroup = textureFrame:CreateAnimationGroup()

    slide = slideAnimGroup:CreateAnimation("Translation")
    slide:SetDuration(0.30)
    slide:SetSmoothing("OUT")

    local fade = slideAnimGroup:CreateAnimation("Alpha")
    fade:SetDuration(0.30)
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetSmoothing("OUT")

    slideAnimGroup:SetToFinalAlpha(true)

    slideAnimGroup:SetScript("OnFinished", function()
        if not currentPlate then return end
        textureFrame:ClearAllPoints()
        textureFrame:SetPoint("BOTTOM", currentPlate, "TOP", 0, 20)
    end)

    frame:SetScript("OnEvent", OnEvent)
end

-- The standalone addon still loaded: it already draws this arrow.
function TA:IsStandaloneLoaded()
    local api = C_AddOns and C_AddOns.IsAddOnLoaded
    if not api then return false end
    local ok, loaded = pcall(api, "TargetArrow")
    return ok and loaded == true
end

function TA:IsActive() return active end

-- Follows ns.db.tools.targetArrow: on registers the events and attaches to
-- the current target at once (no slide); off unregisters and parks.
function TA:Apply()
    local tools = ns.db and ns.db.tools
    local want = tools and tools.targetArrow == true and not self:IsStandaloneLoaded()
    if want == active then return end
    active = want and true or false
    if active then
        Build()
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        frame:RegisterUnitEvent("UNIT_FACTION", "target")
        frame:RegisterUnitEvent("UNIT_FLAGS", "target")
        UpdateTexturePosition(false)
    elseif frame then
        frame:UnregisterAllEvents()
        HideArrow()
    end
end
