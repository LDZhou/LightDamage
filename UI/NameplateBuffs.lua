--[[
    Light Damage - NameplateBuffs.lua  (WoW Forever)
    Tools: the nameplate buff reminder.

    Group buffs on friendly player nameplates, right of the name, on any
    nameplates: Blizzard's own or any nameplate addon's.  Nothing outside the
    game client is required; EllesmereUI's plates are merely recognised.
    * Has it: the buff's icon, its swipe running down the time left.  Every
      class's buff can show; "only my class" keeps the ones your class casts.
    * Lacks it: the buff's icon with a glow, only for a buff YOU can cast (your
      class, a rank in your spellbook), whatever "only my class" says.
    * Unknown (offline, out of sight, or the game hides the buff from addons
      right now): no missing icon, never a false alarm.

    The buffs: the WoW Forever group buffs (FAMILIES below) plus Battle Shout,
    which only ever shows while present (a warrior's shout covers the whole
    party at once).

    Missing rules (as EllesmereUI's raid frames apply them on WoW Forever):
    * Arcane Intellect only on the classes it serves (its beneficiaries).
    * Salvation only in a group, never on a tank (a secret role reads unknown).
    * One blessing per member at most, by role: Might for a tank, Wisdom for a
      healer, Might for damage or no role; none once the member carries a
      blessing of yours; none solo (the raid frames' solo Kings reminder is
      for the player, who has no nameplate here).
    * The same look-up by localized names covering every rank, the same trust
      rule under the aura restriction (a buff counts only while every rank
      reads non-secret, asked again each frame), the same UNIT_AURA probe,
      coalesced to one pass per frame, and the same re-read at every
      restriction edge.

    Has it: Blizzard's aura container (Blizzard_AuraContainer), one
    flow-layout aura GROUP per plate, so the engine packs whatever buffs are
    up into one row.  The group's includeSpellIDs candidate filter is the
    shown families' spells; a settings change swaps it on every bundle.  The
    engine reads the auras and drives the icons and the swipes in C, so
    secret auras still show.

    Layout: [name][EllesmereUI's right target arrow, if any][missing icons]
    [buffs].  The missing icons come first because their count is known here;
    the buffs row is engine-sized and only its start is placed.

    Bundles (holder + container + missing overlay) are pooled across plates;
    attaching parents, anchors and shows the holder and binds the unit once,
    detaching parks it.  Settings: ns.db.tools.nameplateBuffs (enabled,
    onlyMyClass, showMissing, families[key] == false switches a buff off).
    Off, or while the standalone NameplateFortitude addon is still enabled:
    no events, no bundles.
]]

local addonName, ns = ...
local NB = {}
ns.NameplateBuffs = NB

-- Fixed look
local ICON_SIZE = 16          -- icon edge, in UI units
local ICON_CROP = 0.08        -- the icon art's border trimmed off each side
local GAP = 2                 -- space between the name (or target arrow), the missing icons and the buffs
local EDGE = 1                -- the cell's border and the space between icons
local PREWARM = 6             -- bundles built on enable, before the first plates need them
local PLATE_TOKENS = 200      -- nameplate1..N walked on enable (more than any crowd's plates)
local BUILD_BUDGET_MS = 4     -- bundle building per frame (each makes a batch of engine buttons)
local GROUP_KEY = "buffs"

-- One entry per buff.  class: the class that casts it; icon: the spell whose
-- texture stands for it; tex: the icon used while the client has not loaded
-- that spell (WoW Forever streams spell data from the server, so a spell this
-- character has never met has no name or icon until it is asked for).
-- names: spells whose localized names cover every rank and the group version
-- (the aura look-up); single / group: the trainable ranks of the buff and of
-- its group version (the "can cast" and restriction tests); ids: every spell
-- that applies it, NPC and item casts included (what the row shows); only:
-- the classes it serves (nil = everyone).  notTank: never reminded on a tank;
-- blessing: one of the paladin blessings (one reminder per member, by role);
-- displayOnly: shown while present, never reminded.
-- Spell lists: WoW Forever's, as EllesmereUI 9.8.3 records them
-- (FOREVER_BUFF_FAMILIES).  Blessing of Light no longer exists in the game.
local MANA_USERS = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true,
    SHAMAN = true, WARLOCK = true }
local FAMILIES = {
    { key = "fort", class = "PRIEST", icon = 1243, tex = "Interface\\Icons\\Spell_Holy_WordFortitude",
      names = { 1243, 21562 },
      single = { 1243, 1244, 1245, 2791, 10937, 10938 }, group = { 21562, 21564 },
      ids = { 1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 23947, 23948,
              21562, 21564, 450086 } },
    { key = "mark", class = "DRUID", icon = 1126, tex = "Interface\\Icons\\Spell_Nature_Regeneration",
      names = { 1126, 21849 },
      single = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, group = { 21849, 21850 },
      ids = { 1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878, 24752,
              364163, 1291335, 1310503, 21849, 21850 } },
    { key = "intellect", class = "MAGE", icon = 1459, tex = "Interface\\Icons\\Spell_Holy_MagicalSentry",
      names = { 1459, 23028 },
      single = { 1459, 1460, 1461, 10156, 10157 }, group = { 23028 },
      ids = { 1459, 1460, 1461, 10156, 10157, 13326, 16876, 364161, 23028 },
      only = MANA_USERS },
    { key = "spirit", class = "PRIEST", icon = 14752, tex = "Interface\\Icons\\Spell_Holy_DivineSpirit",
      names = { 14752, 27681 },
      single = { 14752, 14818, 14819, 27841 }, group = { 27681 },
      ids = { 14752, 14818, 14819, 16875, 27841, 27681 } },
    { key = "thorns", class = "DRUID", icon = 467, tex = "Interface\\Icons\\Spell_Nature_Thorns",
      names = { 467 },
      single = { 467, 782, 1075, 8914, 9756, 9910 }, group = {},
      ids = { 467, 782, 1075, 8914, 9756, 9910, 15438, 16877, 21335, 21337, 22128, 22351, 22696,
              25640, 25777, 438294, 438326, 1213813, 1213816, 1213834, 1236308, 1291338, 1312955 } },
    -- Salvation and Mass Salvation (1912 is the client's other copy).
    { key = "salvation", class = "PALADIN", icon = 1038, tex = "Interface\\Icons\\Spell_Holy_SealOfSalvation",
      notTank = true,
      names = { 1038, 25895 }, single = { 1038 }, group = { 25895 }, ids = { 1038, 1912, 25895 } },
    -- The blessings, each with its Greater version (1213408 is the client's
    -- non-trainable copy of Kings).
    { key = "might", class = "PALADIN", icon = 19740, tex = "Interface\\Icons\\Spell_Holy_FistOfJustice",
      blessing = true, names = { 19740, 25782 },
      single = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, group = { 25782, 25916 },
      ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 } },
    { key = "wisdom", class = "PALADIN", icon = 19742, tex = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
      blessing = true, names = { 19742, 25894 },
      single = { 19742, 19850, 19852, 19853, 19854, 25290 }, group = { 25894, 25918 },
      ids = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 } },
    { key = "kings", class = "PALADIN", icon = 20217, tex = "Interface\\Icons\\Spell_Magic_MageArmor",
      blessing = true, names = { 20217, 25898 },
      single = { 20217 }, group = { 25898 }, ids = { 20217, 1213408, 25898 } },
    { key = "bshout", class = "WARRIOR", icon = 6673, tex = "Interface\\Icons\\Ability_Warrior_BattleShout",
      displayOnly = true, names = { 6673 },
      single = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, group = {},
      ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 9128, 24438, 25101, 26043, 26099, 27578 } },
}
local NUM = #FAMILIES
NB.FAMILIES = FAMILIES
-- The options page lists the buffs by class, in this order.
NB.CLASS_ORDER = { "PRIEST", "DRUID", "MAGE", "PALADIN", "WARRIOR" }

-- The default blessing per role.
local BLESS_CHOICE = { TANK = { "might" }, HEALER = { "wisdom" }, DAMAGER = { "might" } }

local pairs, ipairs, select, pcall, next, type = pairs, ipairs, select, pcall, next, type
local tremove = table.remove
local issecretvalue = issecretvalue or function() return false end

local initialized, initOK = false, false
local PLAYER_CLASS
local FAMILY_BY_ID = {}        -- spell id -> family index
local BLESS_INDEX = {}         -- blessing key -> family index
local NONE = { [0] = true }    -- a candidate set that matches nothing

-------------------------------------------------------------------------------
--  Availability: Blizzard's own aura container (the engine piece that reads
--  a unit's auras and drives the icons and swipes in C, so even auras the
--  game hides from addons still show).  Nothing else is needed.
-------------------------------------------------------------------------------
local CONTAINER_ADDON = "Blizzard_AuraContainer"

function NB:IsAvailable()
    local api = C_AddOns
    if not (api and api.IsAddOnLoaded) then return false end
    if api.IsAddOnLoaded(CONTAINER_ADDON) then return true end
    if api.LoadAddOn then pcall(api.LoadAddOn, CONTAINER_ADDON) end
    return api.IsAddOnLoaded(CONTAINER_ADDON) == true
end

-- True while the game keeps auras secret from addons (in restricted content).
-- Only the restricted answer is cached, for the rest of the frame: probing
-- throws then, and a stale "clear" would send readers into secret values.
local restrictedStamp = -1
local function AurasRestricted()
    local now = GetTime()
    local S = C_Secrets
    if S and S.ShouldAurasBeSecret and S.ShouldAurasBeSecret() then
        restrictedStamp = now
        return true
    end
    if now == restrictedStamp then return true end
    if pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL") then return false end
    restrictedStamp = now
    return true
end

-- The standalone addon still loaded: it already draws Fortitude here.
function NB:IsStandaloneLoaded()
    local api = C_AddOns and C_AddOns.IsAddOnLoaded
    if not api then return false end
    local ok, loaded = pcall(api, "NameplateFortitude")
    return ok and loaded == true
end

local function Settings()
    local tools = ns.db and ns.db.tools
    return tools and tools.nameplateBuffs
end

-- A buff's own switch (nil = on).
local function FamOn(s, fam)
    local switches = s and s.families
    return not (type(switches) == "table" and switches[fam.key] == false)
end

-- ranks: the player ranks and the group version together; the look-up tables
-- by spell id and by blessing.
local function BuildFamilies()
    for i = 1, NUM do
        local fam = FAMILIES[i]
        local ranks = {}
        for _, id in ipairs(fam.single) do ranks[#ranks + 1] = id end
        for _, id in ipairs(fam.group) do ranks[#ranks + 1] = id end
        fam.ranks = ranks
        for _, id in ipairs(fam.ids) do FAMILY_BY_ID[id] = i end
        if fam.blessing then BLESS_INDEX[fam.key] = i end
    end
end

-- Only a failed container load (never on WoW Forever) is retried later.
local function Init()
    if initOK then return true end
    initialized = true
    if not NB:IsAvailable() then return false end
    BuildFamilies()
    PLAYER_CLASS = select(2, UnitClass("player"))
    initOK = true
    return true
end

-------------------------------------------------------------------------------
--  What shows and what is read (rebuilt on every settings or spellbook change)
-------------------------------------------------------------------------------
local provider = {}            -- key -> the player can cast it (a rank in the spellbook)
local tracked = {}             -- key -> its missing icon can show (read on each unit)
local anyTracked = false       -- any buff is read: UNIT_AURA is listened to
local blessTracked = false     -- any blessing is read
local displayIDs = NONE        -- the shown buffs' spells (the group's candidate filter)
local displayAny = false
local filterGen = 0            -- bumped on every filter change; bundles carry the one they show
local solo = true              -- not in a group (full passes)

-- A buff counts only while the player can cast it: their class casts it and
-- a trained rank (or the group version) is in their spellbook.  Divine
-- Spirit is a talent, so a priest without it gets no Spirit reminders.
local function Knows(fam)
    if fam.class ~= PLAYER_CLASS then return false end
    local ranks = fam.ranks
    for r = 1, #ranks do
        if C_SpellBook.IsSpellKnown(ranks[r]) then return true end
    end
    return false
end

-- Re-reads what the player can cast; true when any buff changed.
local function ScanProviders()
    local changed = false
    for i = 1, NUM do
        local fam = FAMILIES[i]
        local can = Knows(fam)
        if (provider[fam.key] == true) ~= can then
            provider[fam.key] = can
            changed = true
        end
    end
    return changed
end

local function Recompute()
    local s = Settings()
    local missingOn = s and s.showMissing ~= false
    local onlyMine = s and s.onlyMyClass ~= false
    local ids, any = {}, false
    anyTracked, blessTracked = false, false
    for i = 1, NUM do
        local fam = FAMILIES[i]
        local on = FamOn(s, fam)
        if on and (not onlyMine or fam.class == PLAYER_CLASS) then
            for _, id in ipairs(fam.ids) do ids[id] = true end
            any = true
        end
        local t = missingOn and on and not fam.displayOnly and provider[fam.key] == true
        tracked[fam.key] = t and true or false
        if t then
            anyTracked = true
            if fam.blessing then blessTracked = true end
        end
    end
    displayIDs = any and ids or NONE
    displayAny = any
    filterGen = filterGen + 1
end

-------------------------------------------------------------------------------
--  Missing buffs: reading a unit
-------------------------------------------------------------------------------
-- state[unit][key] = true (has it), false (lacks it) or nil (unknown);
-- inst[unit] = the aura instances found, for the removed-aura probe.
local state, inst = {}, {}
local names = {}               -- family index -> { localized names }
local icons = {}               -- family index -> texture

local function FamilyNames(i)
    local n = names[i]
    if n then return n end
    n = {}
    for _, id in ipairs(FAMILIES[i].names) do
        local name = C_Spell.GetSpellName(id)
        if name then n[#n + 1] = name end
    end
    -- Spell data can be cold this early: keep an empty answer uncached.
    if #n > 0 then names[i] = n end
    return n
end

local function FamilyIcon(i)
    local tex = icons[i]
    if not tex then
        tex = C_Spell.GetSpellTexture(FAMILIES[i].icon)
        icons[i] = tex
    end
    return tex or FAMILIES[i].tex or 134400
end

-- Whether every player rank of a buff reads non-secret right now. The
-- answer follows the current restriction (outside one no aura is secret),
-- so it is rebuilt once per frame and never kept across a restriction edge:
-- a look-up can only find a non-secret aura, so a stale "readable" turns a
-- secret buff into a false "missing".
local trusted, trustedAt = {}, nil
local function Trusted(i)
    local now = GetTime()
    if trustedAt ~= now then
        trustedAt = now
        local S = C_Secrets
        for fi = 1, NUM do
            local ok = true
            if S and S.ShouldSpellAuraBeSecret then
                for _, id in ipairs(FAMILIES[fi].ranks) do
                    local good, secret = pcall(S.ShouldSpellAuraBeSecret, id)
                    if not good or issecretvalue(secret) or secret ~= false then ok = false; break end
                end
            end
            trusted[FAMILIES[fi].key] = ok
        end
    end
    return trusted[FAMILIES[i].key]
end

-- The member's assigned role ("TANK", "HEALER", "DAMAGER", "NONE"), or nil
-- while it reads secret.
local function RoleOf(unit)
    local role = UnitGroupRolesAssigned(unit)
    if issecretvalue(role) then return nil end
    return role
end

-- Salvation: every group member but a tank (no role assigned counts as not a
-- tank; a secret role reads unknown: no icon).  Never solo.
local function SalvationHere(unit)
    if solo then return false end
    local role = RoleOf(unit)
    return role ~= nil and role ~= "TANK"
end

-- Whether the buff serves the member's class (no list = everyone); a class
-- the game keeps secret reads as unknown, so no icon.
local function Serves(fam, unit)
    local only = fam.only
    if not only then return true end
    local _, class = UnitClass(unit)
    if issecretvalue(class) then return false end
    return only[class] == true
end

local function Evaluate(unit, restricted)
    local st = state[unit]
    if not st then st = {}; state[unit] = st end
    local found = inst[unit]
    if found then wipe(found) else found = {}; inst[unit] = found end
    local known = UnitExists(unit) and UnitIsConnected(unit) and UnitIsVisible(unit)
    -- st.mine: the member has a blessing the player cast (a paladin keeps one
    -- blessing per target, so theirs is then done); nil while unknown.
    local mine = false
    for i = 1, NUM do
        local fam = FAMILIES[i]
        local key = fam.key
        local value
        if known and tracked[key] and not (restricted and not Trusted(i)) and Serves(fam, unit) then
            local list = FamilyNames(i)
            if #list > 0 then
                value = false
                for n = 1, #list do
                    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, list[n], "HELPFUL")
                    if not ok or issecretvalue(aura) then value = nil; break end
                    if aura then
                        value = true
                        -- The caster, not isFromPlayerOrPlayerPet: that is
                        -- true for any player's aura, another paladin's too.
                        if fam.blessing and mine ~= true then
                            local src = aura.sourceUnit
                            if issecretvalue(src) then mine = nil elseif src == "player" then mine = true end
                        end
                        local iid = aura.auraInstanceID
                        if iid and not issecretvalue(iid) then found[iid] = true end
                        break
                    end
                end
            end
        end
        st[key] = value
        if value == nil and mine == false and fam.blessing and tracked[key] then mine = nil end
    end
    st.mine = mine
end

-- The blessing a member is reminded of (a family index) or nil: none once
-- they carry one of the player's blessings or while that is unknown, none
-- solo, otherwise the first of their role's list (no role assigned: the
-- damage list) that the player reads and the member lacks.
local function MissingBlessing(st, unit)
    if st.mine ~= false then return nil end
    if solo then return nil end
    local role = RoleOf(unit)
    if not role then return nil end
    local want = BLESS_CHOICE[role] or BLESS_CHOICE.DAMAGER
    for w = 1, #want do
        local key = want[w]
        local i = BLESS_INDEX[key]
        if i and tracked[key] then
            local has = st[key]
            if has == nil then return nil end
            if has == false then return i end
        end
    end
    return nil
end

local paintList = {}
local function MissingList(unit)
    local st = state[unit]
    if not (st and anyTracked) then return 0 end
    local n = 0
    for i = 1, NUM do
        local fam = FAMILIES[i]
        if not fam.blessing and tracked[fam.key] and st[fam.key] == false
           and (not fam.notTank or SalvationHere(unit)) then
            n = n + 1
            paintList[n] = i
        end
    end
    -- One blessing at most, last: the member's role picks it.
    if blessTracked then
        local bi = MissingBlessing(st, unit)
        if bi then
            n = n + 1
            paintList[n] = bi
        end
    end
    return n
end

-------------------------------------------------------------------------------
--  Bundles: holder + one-group container + missing overlay
-------------------------------------------------------------------------------
local pool = {}     -- free bundles
local active = {}   -- unit -> the bundle on that unit's plate
local waiting = {}  -- unit -> true: wants a bundle, none free yet
local Attach        -- forward: serving a waiting plate attaches it
local running = false

-- Why plates got no row, for /ld np: the last failure per plate, a session
-- tally by reason, and the first anchor and bundle-build errors.
local lastFail, failCounts = {}, {}
local anchorError, buildError, buildFailures = nil, nil, 0
local function Fail(unit, reason)
    lastFail[unit] = reason
    failCounts[reason] = (failCounts[reason] or 0) + 1
end

local function Park(holder)
    holder:Hide()
    holder:SetParent(UIParent)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)
end

local function FlowDir(token)
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if not FD then return nil end
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

-- The missing icon cells: a black cell, the cropped icon inset by one pixel,
-- a glow host per cell.  Every rect is anchored on two points with a width
-- (inside the restricted plate subtree a point + size region renders
-- displaced).
local function MissingOverlay(holder)
    local o = CreateFrame("Frame", nil, holder)
    o:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    o:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    o:SetWidth(ICON_SIZE)
    o:EnableMouse(false)
    o.slots = {}
    for i = 1, NUM do
        local x = (i - 1) * (ICON_SIZE + EDGE)
        local bg = o:CreateTexture(nil, "ARTWORK", nil, 0)
        bg:SetColorTexture(0, 0, 0, 1)
        bg:SetPoint("TOPLEFT", o, "TOPLEFT", x, 0)
        bg:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", x, 0)
        bg:SetWidth(ICON_SIZE)
        local tex = o:CreateTexture(nil, "ARTWORK", nil, 1)
        tex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
        tex:SetPoint("TOPLEFT", bg, "TOPLEFT", EDGE, -EDGE)
        tex:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -EDGE, EDGE)
        bg:Hide(); tex:Hide()
        o.slots[i] = { bg = bg, tex = tex }
    end
    o:Hide()
    return o
end

-- A group's frame cap.  Where the client can, a cap of 0 also switches the
-- group off: a disabled group is neither parsed nor refreshed, and a
-- container with nothing on stops listening to its unit's auras.
local function SetCap(container, cap)
    if container.SetAuraGroupEnabled then
        if cap > 0 then container:SetAuraGroupEnabled(GROUP_KEY, true) end
        container:SetAuraGroupMaxFrameCount(GROUP_KEY, cap)
        if cap <= 0 then container:SetAuraGroupEnabled(GROUP_KEY, false) end
    else
        container:SetAuraGroupMaxFrameCount(GROUP_KEY, cap)
    end
end

-- The group's candidate filter: the shown buffs' spells, or nothing (cap 0).
local function ApplyDisplayFilter(b)
    if b.filterGen == filterGen then return false end
    b.filterGen = filterGen
    b.container:SetAuraGroupCandidateFilters(GROUP_KEY, { includeSpellIDs = displayIDs })
    SetCap(b.container, displayAny and NUM or 0)
    return true
end

-- Each engine button, dressed while the engine creates it: the one window in
-- which addon code may touch it even while auras are secret.  A black cell,
-- the cropped icon inset one pixel, the time-left swipe over it; no clicks or
-- tooltips, so the plate under the icon still takes a targeting click.
local function InitButton(button)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(button)
    bg:SetColorTexture(0, 0, 0, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    -- The template brings the swipe art; a bare Cooldown draws none.
    local swipe = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    swipe:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    swipe:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    swipe:SetReverse(true)
    swipe:SetDrawEdge(false)
    swipe:SetHideCountdownNumbers(true)
    if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
    if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
    -- Registered last: each registration makes the engine repaint the button.
    button:SetIcon(icon)
    button:SetDurationCooldown(swipe)
end

-- The container's flow layout, on either API generation (the SetFlowLayout*
-- setters replaced SetAuraLayout*): anchored top-left, growing right.
local function SetFlowLayout(container)
    local anchor = container.SetFlowLayoutAnchorPoint or container.SetAuraLayoutAnchorPoint
    if anchor then anchor(container, "TOPLEFT") end
    local grow = container.SetFlowLayoutGrowthDirection or container.SetAuraLayoutGrowthDirection
    if grow then grow(container, FlowDir("RIGHT"), FlowDir("DOWN")) end
end

local function NewBundle()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(ICON_SIZE, ICON_SIZE)
    Park(holder)
    local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    -- A renderable rect from the start: the engine lays out from an OnUpdate
    -- that only runs while the container can be drawn; it sizes it after.
    container:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    container:SetSize(1, 1)
    SetFlowLayout(container)
    container:AddAuraGroup(GROUP_KEY, "HELPFUL", {
        maxFrameCount = NUM,
        candidateFilters = { includeSpellIDs = displayIDs },
        initializeFrame = InitButton,
        layout = { elementWidth = ICON_SIZE, elementHeight = ICON_SIZE,
                   elementSpacing = EDGE, lineSpacing = EDGE },
    })
    container:SetUnit("none")
    container:UpdateAllAuras()
    local b = { holder = holder, container = container, missing = MissingOverlay(holder), rowOffset = 0 }
    b.filterGen = filterGen
    if not displayAny then SetCap(container, 0) end
    return b
end

-- The glow on a missing icon: Blizzard's icon-alert ants over a soft gold
-- halo, the look of the action-button proc glow.  A looping FlipBook drives
-- it, so a glowing icon costs nothing per frame.
local ANTS_TEX = "Interface\\SpellActivationOverlay\\IconAlertAnts"
local HALO_TEX = "Interface\\SpellActivationOverlay\\IconAlert"

local function NewGlow(o, cell)
    local g = CreateFrame("Frame", nil, o)
    g:SetAllPoints(cell)
    g:SetFrameLevel(o:GetFrameLevel() + 2)
    g:EnableMouse(false)
    local size = ICON_SIZE * 1.25
    local halo = g:CreateTexture(nil, "OVERLAY", nil, 6)
    halo:SetTexture(HALO_TEX)
    halo:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
    halo:SetBlendMode("ADD")
    halo:SetDesaturated(true)
    halo:SetVertexColor(1, 0.788, 0.137, 1)
    halo:SetSize(size * 1.3, size * 1.3)
    halo:SetPoint("CENTER")
    local ants = g:CreateTexture(nil, "OVERLAY", nil, 7)
    ants:SetTexture(ANTS_TEX)
    ants:SetSize(size, size)
    ants:SetPoint("CENTER")
    -- 5 x 5 cells of 48 px; the last three are blank, so 22 frames.
    local loop = ants:CreateAnimationGroup()
    loop:SetLooping("REPEAT")
    local flip = loop:CreateAnimation("FlipBook")
    flip:SetFlipBookRows(5)
    flip:SetFlipBookColumns(5)
    flip:SetFlipBookFrames(22)
    flip:SetFlipBookFrameWidth(48)
    flip:SetFlipBookFrameHeight(48)
    flip:SetDuration(0.3)
    g.loop = loop
    g:Hide()
    return g
end

-- Every cell that goes and every overlay that hides stops its glow.
local function StopGlows(o, from)
    for i = from, NUM do
        local g = o.slots[i].glow
        if g and g.on then
            g.loop:Stop()
            g:Hide()
            g.on = nil
        end
    end
end

local function HideOverlay(o)
    StopGlows(o, 1)
    o:Hide()
end

local function ApplyGlows(o, n)
    for i = 1, n do
        local slot = o.slots[i]
        local g = slot.glow
        if not g then
            g = NewGlow(o, slot.bg)
            slot.glow = g
        end
        if not g.on then
            g:Show()
            g.loop:Play()
            g.on = true
        end
    end
    StopGlows(o, n + 1)
end

-- Lays the n missing icons (paintList) at the row's start and moves the
-- buffs row past them.
local function LayoutMissing(b, n)
    local o = b.missing
    for i = 1, NUM do
        local slot = o.slots[i]
        if i <= n then
            slot.tex:SetTexture(FamilyIcon(paintList[i]))
            slot.bg:Show(); slot.tex:Show()
        else
            slot.bg:Hide(); slot.tex:Hide()
        end
    end
    local offset = 0
    if n == 0 then
        HideOverlay(o)
    else
        local w = n * ICON_SIZE + (n - 1) * EDGE
        o:SetWidth(w)
        ApplyGlows(o, n)
        o:Show()
        offset = w + GAP
    end
    b.holder:SetWidth(math.max(ICON_SIZE, offset))
    if b.rowOffset ~= offset then
        b.rowOffset = offset
        local c = b.container
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", b.holder, "TOPLEFT", offset, 0)
    end
end

local function Paint(unit)
    local b = active[unit]
    if not b then return end
    LayoutMissing(b, MissingList(unit))
end

local function ServeWaiting()
    for unit in pairs(waiting) do
        if #pool == 0 then return end
        waiting[unit] = nil
        Attach(unit)
    end
end

-- Bundles are built within a small budget per frame: each one's aura group
-- makes a batch of engine buttons up front (a few ms), so a crowd of plates
-- appearing at once must not all land in one frame.  A failed build is kept
-- for /ld np and reported once.
local builds, builder = 0, nil
local function RunBuilds(self)
    local start = debugprofilestop()
    while builds > 0 do
        builds = builds - 1
        local ok, b = pcall(NewBundle)
        if ok then
            pool[#pool + 1] = b
            if running then ServeWaiting() end
        else
            buildFailures = buildFailures + 1
            if not buildError then
                buildError = tostring(b)
                geterrorhandler()(b)
            end
        end
        if debugprofilestop() - start >= BUILD_BUDGET_MS then return end
    end
    self:Hide()
end

local function QueueBundleBuild()
    if not builder then
        builder = CreateFrame("Frame")
        builder:Hide()
        builder:SetScript("OnUpdate", RunBuilds)
    end
    builds = builds + 1
    builder:Show()
end

-------------------------------------------------------------------------------
--  Where the row hangs, whatever draws the plate
-------------------------------------------------------------------------------
-- In order:
-- 1. EllesmereUI's friendly plate (health-bar mode), recognised by its shape:
--    a child of the nameplate carrying .unit, .nameplate, .name and .health.
-- 2. Blizzard's own name, while its frame is on the plate and drawn: the
--    default nameplates and name-only modes.  Addons that replace the plate
--    hide Blizzard's frame, reparent it or fade it out.
-- 3. Any other addon's name: a drawn FontString under the plate whose text
--    holds the unit's name (or its first word: plates often shorten names).
--    Text the game keeps secret is never read.
-- 4. Nothing found: the plate itself, the row starting at its right edge.
local SCAN_DEPTH = 4

local function EUIPlate(nameplate, unit)
    local children = { nameplate:GetChildren() }
    for i = 1, #children do
        local f = children[i]
        if not f:IsForbidden() and f.nameplate == nameplate and f.unit == unit
            and f.health and f.name and f:IsShown() then
            return f
        end
    end
end

-- Shown on screen: visible, and neither it nor its frame faded out.
local function Drawn(region)
    if not region:IsVisible() then return false end
    local own = region.GetAlpha and region:GetAlpha()
    if own ~= nil and not issecretvalue(own) and own <= 0.01 then return false end
    local frame = region.GetEffectiveAlpha and region or region:GetParent()
    local alpha = frame and frame.GetEffectiveAlpha and frame:GetEffectiveAlpha()
    if alpha ~= nil and not issecretvalue(alpha) and alpha <= 0.01 then return false end
    return true
end

local function ShowsText(fs, want)
    local text = fs:GetText()
    if text == nil or issecretvalue(text) or type(text) ~= "string" then return false end
    return text:find(want, 1, true) ~= nil
end

local function FindNameText(frame, want, depth)
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r:GetObjectType() == "FontString" and Drawn(r) and ShowsText(r, want) then return r end
    end
    if depth <= 0 then return nil end
    local children = { frame:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        if not c:IsForbidden() and c:IsVisible() then
            local fs = FindNameText(c, want, depth - 1)
            if fs then return fs end
        end
    end
end

local function NameText(nameplate, unit)
    local name = UnitName(unit)
    if name == nil or issecretvalue(name) or type(name) ~= "string" or name == "" then return nil end
    local fs = FindNameText(nameplate, name, SCAN_DEPTH)
    if fs then return fs end
    local first = name:match("^(%S+)")
    if first and first ~= name then return FindNameText(nameplate, first, SCAN_DEPTH) end
end

-- The frame the row is parented to, the region it hangs off, EllesmereUI's
-- plate if it is one, and how the spot was found.
local function NameOf(nameplate, unit)
    local plate = EUIPlate(nameplate, unit)
    if plate then return plate, plate.name, plate, "addon plate" end
    local uf = nameplate.UnitFrame
    if uf and not uf:IsForbidden() and uf:GetParent() == nameplate and uf.name and Drawn(uf.name) then
        return uf, uf.name, nil, "Blizzard name"
    end
    local fs = NameText(nameplate, unit)
    if fs then return fs:GetParent(), fs, nil, "nameplate addon's name" end
    return nameplate, nameplate, nil, "plate edge"
end

-- EllesmereUI's right target arrow hangs off the same RIGHT point while the
-- plate is your target (FriendlyFrame:ApplyTarget toggles it).
local arrowBundle = setmetatable({}, { __mode = "k" })  -- right arrow -> bundle beside it
local hookedArrows = setmetatable({}, { __mode = "k" })

local function ArrowShift(plate)
    local arrow = plate and plate.rightArrow
    if arrow and arrow:IsShown() then return 2 + (plate._arrowW or 16) end
    return 0
end

-- A fully anchored rect: its left edge right of the name (and the arrow) or
-- of the plate, one icon tall, centred on it.
local function Place(b)
    local h = b.holder
    local x = GAP + ArrowShift(b.plate)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", b.anchor, "RIGHT", x, ICON_SIZE / 2)
    h:SetPoint("BOTTOMLEFT", b.anchor, "RIGHT", x, -ICON_SIZE / 2)
end

local function OnArrowToggled(arrow)
    local b = arrowBundle[arrow]
    if b and b.anchor then pcall(Place, b) end
end

local function WatchArrow(b, plate)
    local arrow = plate and plate.rightArrow
    if not arrow then return end
    arrowBundle[arrow] = b
    if hookedArrows[arrow] then return end
    hookedArrows[arrow] = true
    hooksecurefunc(arrow, "Show", OnArrowToggled)
    hooksecurefunc(arrow, "Hide", OnArrowToggled)
    hooksecurefunc(arrow, "SetShown", OnArrowToggled)
end

local function UnwatchArrow(b)
    local arrow = b.plate and b.plate.rightArrow
    if arrow and arrowBundle[arrow] == b then arrowBundle[arrow] = nil end
end

-------------------------------------------------------------------------------
--  Attach / detach
-------------------------------------------------------------------------------
-- A nameplate's unit token.  WoW Forever keeps it in unitToken (the base
-- mixin's SetUnit; GetUnit returns it); namePlateUnitToken is retail's field
-- and is never set here.
local function PlateToken(np)
    if not np then return nil end
    local t = np.unitToken or np.namePlateUnitToken
    if t == nil and np.GetUnit then
        local ok, u = pcall(np.GetUnit, np)
        if ok then t = u end
    end
    if t == nil or issecretvalue(t) or type(t) ~= "string" then return nil end
    return t
end

local function Wanted(unit)
    return UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") and not UnitCanAttack("player", unit)
end

local function Detach(unit)
    waiting[unit] = nil
    state[unit], inst[unit] = nil, nil
    local b = active[unit]
    if not b then return end
    active[unit] = nil
    UnwatchArrow(b)
    HideOverlay(b.missing)
    -- Unbound only: a hidden container neither listens nor parses, and the
    -- next attach binds its unit afresh.
    b.plate, b.anchor, b.via, b.unit = nil, nil, nil, nil
    Park(b.holder)
    pool[#pool + 1] = b
    if running then ServeWaiting() end
end

function Attach(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then Fail(unit, "no nameplate"); Detach(unit) return end
    if not Wanted(unit) then Fail(unit, "not a friendly player"); Detach(unit) return end
    if nameplate:IsForbidden() then Fail(unit, "the game locks this plate"); Detach(unit) return end
    local found, parent, anchor, plate, via = pcall(NameOf, nameplate, unit)
    if not found then
        anchorError = anchorError or tostring(parent)
        Fail(unit, "the plate could not be read")
        Detach(unit)
        return
    end
    local b = active[unit]
    if not b then
        b = tremove(pool)
        if not b then
            if not waiting[unit] then
                waiting[unit] = true
                QueueBundleBuild()
            end
            return
        end
        waiting[unit] = nil
        active[unit] = b
    end
    if b.plate ~= plate then
        UnwatchArrow(b)
        WatchArrow(b, plate)
    end
    b.plate, b.anchor, b.via = plate, anchor, via
    -- A plate may refuse a child or an anchor in some content: no row on
    -- that plate then.
    local ok, err = pcall(b.holder.SetParent, b.holder, parent)
    if ok then ok, err = pcall(Place, b) end
    if not ok then
        anchorError = anchorError or tostring(err)
        Fail(unit, "the name refused the row")
        Detach(unit)
        return
    end
    lastFail[unit] = nil
    b.holder:Show()
    local refiltered = ApplyDisplayFilter(b)
    if b.unit ~= unit then
        b.unit = unit
        b.container:SetUnit(unit)
        b.container:UpdateAllAuras()
        if anyTracked then Evaluate(unit, AurasRestricted()) end
    elseif refiltered then
        b.container:UpdateAllAuras()
    end
    Paint(unit)
end

-------------------------------------------------------------------------------
--  Passes (one per frame)
-------------------------------------------------------------------------------
-- A plate is settled one frame after it appears, once a nameplate addon has
-- built (or skipped) its own plate for it.
local pending, armed = {}, false

local function Flush()
    armed = false
    for unit in pairs(pending) do
        pending[unit] = nil
        if running then Attach(unit) end
    end
end

local function Settle(unit)
    pending[unit] = true
    if not armed then
        armed = true
        C_Timer.After(0, Flush)
    end
end

-- Members to read again, coalesced to one pass per frame.
local dirty, auraArmed = {}, false

local function FlushAuras()
    auraArmed = false
    local restricted = running and AurasRestricted()
    for unit in pairs(dirty) do
        dirty[unit] = nil
        if running and active[unit] then
            if anyTracked then Evaluate(unit, restricted) else state[unit], inst[unit] = nil, nil end
            Paint(unit)
        end
    end
end

local function MarkDirty(unit)
    dirty[unit] = true
    if not auraArmed then
        auraArmed = true
        C_Timer.After(0, FlushAuras)
    end
end

local function MarkAll()
    for unit in pairs(active) do MarkDirty(unit) end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
-- The payload is secret while auras are restricted (UNIT_AURA is
-- SecretWhenAurasRestricted): nothing in it can be read, so the unit is
-- looked up again, but only while a buff the player provides stays readable
-- under the restriction.  The restriction edge re-reads everyone.
local function Unprobeable(unit)
    for i = 1, NUM do
        if tracked[FAMILIES[i].key] and Trusted(i) then MarkDirty(unit) return end
    end
end

-- Probe the payload first: only an added reminded buff or a removed instance
-- found before sends the unit back for a look-up; a full update always does.
local function OnUnitAura(unit, info)
    if not active[unit] then return end
    if not info then MarkDirty(unit) return end
    if issecretvalue(info) then Unprobeable(unit) return end
    local full = info.isFullUpdate
    if issecretvalue(full) then Unprobeable(unit) return end
    if full then MarkDirty(unit) return end
    local added = info.addedAuras
    if added then
        if issecretvalue(added) then Unprobeable(unit) return end
        for i = 1, #added do
            local aura = added[i]
            if issecretvalue(aura) then Unprobeable(unit) return end
            local sid = aura.spellId
            if issecretvalue(sid) then Unprobeable(unit) return end
            local fi = sid and FAMILY_BY_ID[sid]
            if fi and tracked[FAMILIES[fi].key] then MarkDirty(unit) return end
        end
    end
    local removed, found = info.removedAuraInstanceIDs, inst[unit]
    if removed and found and next(found) then
        if issecretvalue(removed) then Unprobeable(unit) return end
        for i = 1, #removed do
            local iid = removed[i]
            if issecretvalue(iid) then Unprobeable(unit) return end
            if found[iid] then MarkDirty(unit) return end
        end
    end
end

-- One watcher per player plate.  Friend or foe: a duel or a PvP flag turns a
-- player's plate hostile, and back, without a new NAME_PLATE_UNIT_ADDED, so
-- it listens on the events EllesmereUI's own friendly/enemy watchers use and
-- settles the plate only when friend or foe really changed.  Auras: UNIT_AURA
-- while any buff is reminded.
local watchers = {}  -- nameplate token -> its watcher frame (the tokens are a fixed set)
local watching = {}  -- nameplate token -> true while its plate is up

local function OnWatchedUnit(_, event, unit, info)
    if event == "UNIT_AURA" then
        OnUnitAura(unit, info)
        return
    end
    local has = active[unit] ~= nil or waiting[unit] ~= nil
    if (Wanted(unit) and true or false) ~= has then Settle(unit) end
end

local function Watch(unit)
    local w = watchers[unit]
    if not w then
        w = CreateFrame("Frame")
        w:SetScript("OnEvent", OnWatchedUnit)
        watchers[unit] = w
    end
    w:RegisterUnitEvent("UNIT_FLAGS", unit)
    w:RegisterUnitEvent("UNIT_FACTION", unit)
    if anyTracked then w:RegisterUnitEvent("UNIT_AURA", unit) end
    watching[unit] = true
end

local function Unwatch(unit)
    local w = watchers[unit]
    if w then w:UnregisterAllEvents() end
    watching[unit] = nil
end

local function SyncAuraWatches()
    for unit in pairs(watching) do
        local w = watchers[unit]
        if anyTracked then w:RegisterUnitEvent("UNIT_AURA", unit) else w:UnregisterEvent("UNIT_AURA") end
    end
end

-- Settings or spellbook changed: new filters on every bundle, the aura
-- watches follow, and every plate is read again.
local function Refresh()
    Recompute()
    for _, b in ipairs(pool) do ApplyDisplayFilter(b) end
    for _, b in pairs(active) do
        if ApplyDisplayFilter(b) and b.unit then b.container:UpdateAllAuras() end
    end
    SyncAuraWatches()
    MarkAll()
end

local CHAT_RESTRICTION = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
            Watch(unit)
            Settle(unit)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        Unwatch(unit)
        pending[unit], dirty[unit] = nil, nil
        Detach(unit)
    elseif event == "SPELLS_CHANGED" then
        -- A rank trained or a talent (Divine Spirit) taken or dropped.
        if ScanProviders() then Refresh() end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- A restriction starting or lifting changes which buffs can be read.
        -- The pass runs next frame, after the activation dispatch, so it
        -- reads the settled state; addon chat restrictions never touch auras.
        if unit ~= CHAT_RESTRICTION then MarkAll() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        solo = not IsInGroup()
        MarkAll()
    else -- PLAYER_ENTERING_WORLD, PLAYER_ROLES_ASSIGNED
        MarkAll()
    end
end)

local prewarmed = false

local function Start()
    running = true
    solo = not IsInGroup()
    ScanProviders()
    Recompute()
    for _, b in ipairs(pool) do ApplyDisplayFilter(b) end
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    -- Only a class that casts one of these buffs ever reads a member.
    local castsAny = false
    for i = 1, NUM do
        if FAMILIES[i].class == PLAYER_CLASS and not FAMILIES[i].displayOnly then castsAny = true end
    end
    if castsAny then
        events:RegisterEvent("SPELLS_CHANGED")
        events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Roles pick the blessing and keep Salvation off tanks.
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    end
    if not prewarmed then
        prewarmed = true
        for _ = 1, PREWARM do QueueBundleBuild() end
    end
    -- Plates already up when the reminder turns on.  GetNamePlates leaves
    -- friendly player plates out (EllesmereUINameplatesFriendly.lua notes
    -- it too), so the plate tokens are walked as well: turning the reminder
    -- on in a crowd otherwise showed nothing until each plate came back.
    local seen = {}
    local function Adopt(unit)
        if unit and not seen[unit] and UnitExists(unit) and UnitIsPlayer(unit)
           and not UnitIsUnit(unit, "player") then
            seen[unit] = true
            Watch(unit)
            Settle(unit)
        end
    end
    local plates = C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
    for _, nameplate in ipairs(plates) do Adopt(PlateToken(nameplate)) end
    for i = 1, PLATE_TOKENS do Adopt("nameplate" .. i) end
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    local units = {}
    for unit in pairs(watching) do units[#units + 1] = unit end
    for _, unit in ipairs(units) do Unwatch(unit) end
    wipe(waiting); wipe(pending); wipe(dirty)
    units = {}
    for unit in pairs(active) do units[#units + 1] = unit end
    for _, unit in ipairs(units) do Detach(unit) end
    wipe(state); wipe(inst)
end

function NB:IsActive() return running end

-- Follows ns.db.tools.nameplateBuffs: on starts the events and attaches to
-- the plates already up, a change while on re-filters every bundle, off
-- detaches everything.
function NB:Apply()
    local s = Settings()
    local want = s and s.enabled == true and not self:IsStandaloneLoaded() and Init()
    if not want then
        if running then Stop() end
        return
    end
    if running then Refresh() else Start() end
end

-- /ld np: where the reminder stands and, for a targeted friendly player,
-- each step of putting the row on their plate.  Developer lines, English.
local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local STATE_WORD = { [true] = "has", [false] = "LACKS" }

-- Why a buff reads unknown on a unit, in Evaluate's own order.
local function UnknownWhy(i, unit, restricted)
    if not UnitExists(unit) then return "no unit" end
    if not UnitIsConnected(unit) then return "offline" end
    if not UnitIsVisible(unit) then return "out of sight" end
    if restricted and not Trusted(i) then return "hidden by the game" end
    if not Serves(FAMILIES[i], unit) then return "not for this class" end
    if #FamilyNames(i) == 0 then return "spell names not loaded" end
    return "aura read was secret"
end

function NB:Diagnose()
    local out = {}
    local function add(fmt, ...) out[#out + 1] = "|cff00ccffLD np|r " .. string.format(fmt, ...) end
    local s = Settings()
    add("enabled=%s onlyMyClass=%s showMissing=%s standalone=%s auraContainer=%s init=%s running=%s class=%s",
        tostring(s and s.enabled), tostring(s and s.onlyMyClass), tostring(s and s.showMissing),
        tostring(self:IsStandaloneLoaded()), tostring(self:IsAvailable()),
        initialized and tostring(initOK) or "not yet", tostring(running), tostring(PLAYER_CLASS))
    local cast, reminded = {}, {}
    for i = 1, NUM do
        local key = FAMILIES[i].key
        if provider[key] then cast[#cast + 1] = key end
        if tracked[key] then reminded[#reminded + 1] = key end
    end
    add("can cast: %s | reminded: %s | shown buffs: %s",
        #cast > 0 and table.concat(cast, ",") or "none",
        #reminded > 0 and table.concat(reminded, ",") or "none", tostring(displayAny))
    add("plates watched=%d rows=%d waiting=%d spare=%d builds failed=%d",
        Count(watching), Count(active), Count(waiting), #pool, buildFailures)
    -- Every friendly player that has a plate right now, against the plates
    -- the reminder is tracking: a gap means plates it never heard about.
    local okScan, scanErr = pcall(function()
        local now, untracked = 0, {}
        for i = 1, PLATE_TOKENS do
            local u = "nameplate" .. i
            if UnitExists(u) and C_NamePlate.GetNamePlateForUnit(u) and Wanted(u) then
                now = now + 1
                if not watching[u] then untracked[#untracked + 1] = u end
            end
        end
        add("friendly player plates on screen=%d, not tracked=%d%s", now, #untracked,
            #untracked > 0 and (" (" .. table.concat(untracked, ",", 1, math.min(#untracked, 4)) .. ")") or "")
        local cvar = C_CVar and C_CVar.GetCVar
        if cvar then
            local parts = {}
            for _, name in ipairs({"nameplateShowFriends", "nameplateShowFriendlyPlayers",
                "nameplateShowOnlyNames", "nameplateMaxDistance"}) do
                local ok, v = pcall(cvar, name)
                if ok and v ~= nil then parts[#parts + 1] = name:gsub("^nameplate", "") .. "=" .. tostring(v) end
            end
            if #parts > 0 then add("cvars: %s", table.concat(parts, " ")) end
        end
    end)
    if not okScan then add("plate scan failed: %s", tostring(scanErr)) end
    if buildError then add("build error: %s", buildError) end
    if anchorError then add("anchor error: %s", anchorError) end
    for reason, n in pairs(failCounts) do add("no row x%d: %s", n, reason) end

    if not UnitExists("target") then
        add("target a friendly player for that plate's details")
        return out
    end
    local ok, err = pcall(function()
        local np = C_NamePlate.GetNamePlateForUnit("target")
        if not np then add("target: no nameplate") return end
        local token = PlateToken(np)
        add("target plate=%s tracked=%s player=%s attackable=%s",
            tostring(token), tostring(token ~= nil and watching[token] == true),
            tostring(UnitIsPlayer("target")), tostring(UnitCanAttack("player", "target")))
        local uf = np.UnitFrame
        local forbidden = uf and uf:IsForbidden()
        local _, _, _, via = NameOf(np, token or "target")
        add("target row hangs off: %s | plate locked=%s | Blizzard frame=%s locked=%s onPlate=%s",
            via, tostring(np:IsForbidden()), tostring(uf ~= nil), tostring(forbidden),
            tostring(uf and not forbidden and uf:GetParent() == np))
        local b = token and active[token]
        if not b then
            add("target row: none (%s)", token and (waiting[token] and "waiting for a spare row"
                or lastFail[token] or "never attached") or "no token")
            return
        end
        add("target row: shown=%s visible=%s missing icons=%d",
            tostring(b.holder:IsShown()), tostring(b.holder:IsVisible()), b.missing:IsShown() and MissingList(token) or 0)
        -- Where the row was hung when it attached, and whether that spot is
        -- still on screen: a plate addon can hide or swap the frame later.
        local parent = b.holder:GetParent()
        add("target row attached via: %s | that frame visible=%s | anchor visible=%s",
            tostring(b.via), tostring(parent and parent:IsVisible()),
            tostring(b.anchor and b.anchor.IsVisible and b.anchor:IsVisible()))
        local st, parts = state[token], {}
        local restricted = AurasRestricted()
        for i = 1, NUM do
            local key = FAMILIES[i].key
            if tracked[key] then
                local word = STATE_WORD[st and st[key]]
                if not word then word = "unknown(" .. UnknownWhy(i, token, restricted) .. ")" end
                parts[#parts + 1] = key .. "=" .. word
            end
        end
        if #parts > 0 then add("target buffs: %s", table.concat(parts, " ")) end
        add("target read: restricted=%s solo=%s role=%s", tostring(restricted), tostring(solo),
            tostring(RoleOf(token)))
    end)
    if not ok then add("target check failed: %s", tostring(err)) end
    return out
end

-- The options page: a buff's localized name and icon, and whether they are
-- the client's own.  A spell the client has not loaded yet reads as the
-- addon's translation and icon; the caller asks for it (RequestFamilyData)
-- and redraws when it arrives.
function NB:FamilyLabel(fam)
    local name = C_Spell.GetSpellName(fam.icon)
    local tex = C_Spell.GetSpellTexture(fam.icon)
    local loaded = type(name) == "string" and name ~= "" and tex ~= nil
    if type(name) ~= "string" or name == "" then
        name = ns.L and ns.L["TOOLS_BUFF_" .. fam.key:upper()]
        if type(name) ~= "string" or name == "" then name = fam.key end
    end
    tex = tex or fam.tex
    if tex then
        return string.format("|T%s:14:14:0:0:64:64:5:59:5:59|t %s", tostring(tex), name), loaded
    end
    return name, loaded
end

-- Asks the client for a buff's spell data; SPELL_DATA_LOAD_RESULT(spellID)
-- follows with fam.icon.  False when the client has no such request.
function NB:RequestFamilyData(fam)
    local request = C_Spell and C_Spell.RequestLoadSpellData
    if not request then return false end
    return (pcall(request, fam.icon))
end
