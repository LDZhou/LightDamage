--[[ Light Damage 2.0 - overview grid and shared single-stat renderer. ]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local TRIANGLE_UP = "Interface\\AddOns\\LightDamage\\Textures\\btn_collapse.tga"
local TRIANGLE_DOWN = "Interface\\AddOns\\LightDamage\\Textures\\btn_expand.tga"
local OTHER_ARROW_W, OTHER_ARROW_H = 10, 9

local baseEnsureCreated=UI.EnsureCreated
function UI:EnsureCreated()
    local existed=self.frame~=nil
    baseEnsureCreated(self)
    if not existed and self.frame then self:ApplySceneWorkspace(ns.state.sceneKey or "outdoor") end
end

local function activeScene()
    local ctx=UI._previewContext
    if ctx then return ctx.sceneKey or "outdoor" end
    return ns.state.sceneKey or "outdoor"
end

function UI:IsOverallColumnActive() return false end
function UI:IsSplitActiveInCurrentScene() return false end

function UI:GetRenderLayout()
    local ctx=self._previewContext
    local mode=(ctx and ctx.displayMode) or ns.db.display.mode
    return ns.Layouts:GetActiveLayout(activeScene(),mode)
end

function UI:GetRenderWorkspace()
    return ns.Layouts:GetWorkspace(activeScene())
end

function UI:BuildBody()
    self.bodyFrame=CreateFrame("Frame",nil,self.frame)
    self.bodyFrame:SetClipsChildren(true)
    self.gridRoot=CreateFrame("Frame",nil,self.bodyFrame)
    self.gridRoot:SetAllPoints(); self.gridRoot:SetClipsChildren(true)
    self.gridCells={}; self._activeGridCells={}
end

function UI:CreateGridCell(index)
    local cell={poolKey="cell"..index,index=index}
    local f=CreateFrame("Frame",nil,self.gridRoot,"BackdropTemplate")
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile=nil,edgeSize=0}); f:SetClipsChildren(true); f:Hide()
    cell.frame=f; cell.head=self:MakeSectHead(f); cell.list=self:MakeScrollArea(f); cell.list._poolKey=cell.poolKey
    cell.list._cell=cell
    cell.bars={}
    self._pinnedSelf=self._pinnedSelf or {}
    cell.pinned=self:MakePinnedSelfBar(f,cell.list.sf,cell.poolKey)
    self._pinnedSelf[cell.poolKey]=cell.pinned
    local original=cell.list.sf:GetScript("OnMouseWheel")
    cell.list.sf:SetScript("OnMouseWheel",function(frame,delta)
        if original then original(frame,delta) end
        local args=self._pinnedSelfCache and self._pinnedSelfCache[cell.poolKey]
        if args then
            if args.type=="bars" then self:CheckPinnedSelfForBars(cell.poolKey,cell.list,args.data,args.dur,args.mode,args.count)
            else self:CheckPinnedSelfForAPI(cell.poolKey,cell.list,args.sources,args.mode,args.maxAmt,args.sType,args.sessionID) end
        end
    end)
    self.gridCells[index]=cell
    return cell
end

function UI:EnsureGridCell(index)
    return self.gridCells[index] or self:CreateGridCell(index)
end

function UI:EnsureCellBars(cell, requiredCount)
    if not cell then return end
    requiredCount=math.min(self.MAX_BARS,math.max(0,tonumber(requiredCount) or 0))
    for i=#cell.bars+1,requiredCount do
        cell.bars[i]=self:MakeBar(cell.list.child,cell.poolKey,i)
    end
end

function UI:ResetCellData()
    for _,cell in ipairs(self.gridCells or {}) do
        for _,bar in ipairs(cell.bars or {}) do
            if self.ReleaseBarData then self:ReleaseBarData(bar) end
            bar.frame:Hide()
        end
        if cell.pinned then cell.pinned.frame:Hide() end
    end
    self._pinnedSelfCache={}
end

local TAB_DEFS={{m="overview",k="OVERVIEW"},{m="damage",k="DAMAGE"},{m="healing",k="HEALING"},{m="damageTaken",k="DAMAGE_TAKEN"},{m="deaths",k="DEATHS"},{m="enemyDamageTaken",k="ENEMY_DAMAGE_TAKEN"},{m="interrupts",k="INTERRUPTS"},{m="dispels",k="DISPELS"}}

local function safeTextWidth(fs)
    local getter=fs and (fs.GetUnboundedStringWidth or fs.GetStringWidth)
    if not getter then return 0 end
    local ok,value=pcall(getter,fs)
    return ok and type(value)=="number" and value or 0
end

function UI:GetBottomTabLabel(mode,short)
    if mode=="overview" then return short and L.OVERVIEW_SHORT or L.OVERVIEW end
    if short and ns.MODE_SHORT[mode] then return L[ns.MODE_SHORT[mode]] end
    return L[ns.MODE_NAMES[mode] or mode]
end

function UI:SetOtherTabArrowDirection(direction)
    if self.otherTab and self.otherTab.arrow then
        self.otherTab.arrow:SetTexture(direction=="up" and TRIANGLE_UP or TRIANGLE_DOWN)
    end
end

function UI:SetOtherTabArrowState(active)
    local field=active and "tabActiveFontColor" or "tabInactiveFontColor"
    local fallback=active and {1,1,1,1} or {.55,.55,.55,.9}
    local r,g,b,a=self:GetDisplayColor(field,fallback)
    if self.otherTab and self.otherTab.arrow then self.otherTab.arrow:SetVertexColor(r,g,b,a) end
end

function UI:SetBottomDisplayMode(mode)
    if self._previewContext then self._previewContext.displayMode=mode else ns.db.display.mode=mode end
    self:CloseOtherTabMenu()
    self:Layout()
end

function UI:BuildTabs()
    local tb=CreateFrame("Frame",nil,self.frame); tb:SetHeight(self.TAB_H); tb:SetPoint("BOTTOMLEFT",0,0); tb:SetPoint("BOTTOMRIGHT",0,0)
    self.tabBg=self:FillBg(tb,{0.05,0.05,0.07,1}); self.tabBar=tb
    self.tabs={}; self._tabByMode={}; self.splitTab=nil
    for i,d in ipairs(TAB_DEFS) do
        local mode=d.m
        local t=CreateFrame("Button",nil,tb); t.mode=mode; t.labelKey=d.k
        t.abg=t:CreateTexture(nil,"BORDER"); t.abg:SetAllPoints(); t.abg:SetColorTexture(0,0.65,1,.3); t.abg:Hide()
        t.text=self:FS(t,9,"OUTLINE"); t.text:SetPoint("LEFT",4,0); t.text:SetPoint("RIGHT",-4,0); t.text:SetJustifyH("CENTER"); t.text:SetWordWrap(false); if t.text.SetMaxLines then t.text:SetMaxLines(1) end
        t.text:SetText(L[d.k]); self:SetTabTextColor(t.text,false)
        t:SetScript("OnClick",function() self:SetBottomDisplayMode(mode) end)
        self.tabs[i]=t; self._tabByMode[mode]=t
    end

    local other=CreateFrame("Button",nil,tb); self.otherTab=other
    other.abg=other:CreateTexture(nil,"BORDER"); other.abg:SetAllPoints(); other.abg:SetColorTexture(0,0.65,1,.3); other.abg:Hide()
    other.hoverBg=other:CreateTexture(nil,"HIGHLIGHT"); other.hoverBg:SetAllPoints(); other.hoverBg:SetColorTexture(0,.65,1,.14)
    other.text=self:FS(other,9,"OUTLINE"); other.text:SetPoint("CENTER",-4,0); other.text:SetJustifyH("LEFT"); other.text:SetWordWrap(false); if other.text.SetMaxLines then other.text:SetMaxLines(1) end
    other.arrow=other:CreateTexture(nil,"ARTWORK"); other.arrow:SetSize(OTHER_ARROW_W,OTHER_ARROW_H); other.arrow:SetTexCoord(0,1,7/32,24/32); other.arrow:SetPoint("LEFT",other.text,"RIGHT",1,0); other.arrow:SetTexture(TRIANGLE_UP)
    self:SetTabTextColor(other.text,false); self:SetOtherTabArrowState(false)
    other:SetScript("OnClick",function() self:ToggleOtherTabMenu() end)
    other:SetScript("OnEnter",function()
        other._hovered=true
        self:SetTabTextColor(other.text,true)
        self:SetOtherTabArrowState(true)
    end)
    other:SetScript("OnLeave",function()
        other._hovered=nil
        self:SetTabTextColor(other.text,other._active and true or false)
        self:SetOtherTabArrowState(other._active and true or false)
    end)
    self.frame:HookScript("OnHide",function() self:CloseOtherTabMenu() end)
end

function UI:EnsureOtherTabMenu()
    if self._otherTabBlocker then return end
    local blocker=CreateFrame("Button","LightDamageOtherMenuBlocker",UIParent); self._otherTabBlocker=blocker
    blocker:SetAllPoints(UIParent); blocker:SetFrameStrata("TOOLTIP"); blocker:SetFrameLevel(800); blocker:EnableMouse(true); blocker:Hide()
    blocker:SetScript("OnClick",function() self:CloseOtherTabMenu() end)
    local registered=false; for _,name in ipairs(UISpecialFrames) do if name=="LightDamageOtherMenuBlocker" then registered=true; break end end
    if not registered then tinsert(UISpecialFrames,"LightDamageOtherMenuBlocker") end
    local menu=CreateFrame("Frame",nil,blocker,"BackdropTemplate"); self._otherTabMenu=menu
    menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    menu:SetBackdropColor(.035,.035,.05,.98); menu:SetBackdropBorderColor(.25,.4,.55,1); menu:SetClampedToScreen(true); menu:SetFrameLevel(802)
    menu.items={}
    for i=1,#ns.MODE_ORDER do
        local item=CreateFrame("Button",nil,menu); item:SetHeight(22); item:SetPoint("TOPLEFT",2,-2-(i-1)*22); item:SetPoint("TOPRIGHT",-2,-2-(i-1)*22)
        item.bg=item:CreateTexture(nil,"BACKGROUND"); item.bg:SetAllPoints(); item.bg:SetColorTexture(0,.65,1,.22); item.bg:Hide()
        item.hl=item:CreateTexture(nil,"HIGHLIGHT"); item.hl:SetAllPoints(); item.hl:SetColorTexture(1,1,1,.06)
        item.text=self:FS(item,9,"OUTLINE"); item.text:SetPoint("LEFT",8,0); item.text:SetPoint("RIGHT",-8,0); item.text:SetJustifyH("LEFT"); item.text:SetWordWrap(false); if item.text.SetMaxLines then item.text:SetMaxLines(1) end
        item:SetScript("OnClick",function() if item.mode then self:SetBottomDisplayMode(item.mode) end end)
        menu.items[i]=item
    end
end

function UI:GetOtherMenuDirection(menuH)
    local anchor=self.otherTab
    if not anchor then return "up" end
    local rootScale=UIParent:GetEffectiveScale() or 1
    local anchorScale=anchor:GetEffectiveScale() or rootScale
    local screenTop=(UIParent:GetTop() or UIParent:GetHeight() or 0)*rootScale
    local screenBottom=(UIParent:GetBottom() or 0)*rootScale
    local above=math.max(0,screenTop-(anchor:GetTop() or 0)*anchorScale)
    local below=math.max(0,(anchor:GetBottom() or 0)*anchorScale-screenBottom)
    local menuScale=self._otherTabMenu and self._otherTabMenu:GetEffectiveScale() or rootScale
    local required=menuH*menuScale
    if above>=required and below<required then return "up" end
    if below>=required and above<required then return "down" end
    return above>=below and "up" or "down"
end

function UI:RefreshOtherTabMenu()
    if not self._otherTabBlocker or not self._otherTabBlocker:IsShown() then return end
    local modes=self._otherModes or {}; local menu=self._otherTabMenu
    local font,size,outline,shadow=self:GetDisplayFontConfig("tab")
    local displayMode=(self._previewContext and self._previewContext.displayMode) or ns.db.display.mode
    local rootScale=UIParent:GetEffectiveScale() or 1
    local frameScale=self.frame and self.frame:GetEffectiveScale() or rootScale
    menu:SetScale(frameScale/rootScale)
    local maxW=96
    for i,item in ipairs(menu.items) do
        local mode=modes[i]; item.mode=mode; item:SetShown(mode~=nil)
        if mode then
            item.text:SetText(self:GetBottomTabLabel(mode,false)); self:ApplyFont(item.text,font,size,outline,shadow)
            maxW=math.max(maxW,math.ceil(safeTextWidth(item.text)+20)); local active=displayMode==mode; item.bg:SetShown(active); self:SetTabTextColor(item.text,active)
        end
    end
    local menuH=math.max(1,#modes*22+4); menu:SetSize(math.min(260,maxW),menuH); menu:ClearAllPoints()
    local direction=self:GetOtherMenuDirection(menuH)
    if direction=="up" then menu:SetPoint("BOTTOMRIGHT",self.otherTab,"TOPRIGHT",0,2) else menu:SetPoint("TOPRIGHT",self.otherTab,"BOTTOMRIGHT",0,-2) end
    self:SetOtherTabArrowDirection(direction)
end

function UI:ToggleOtherTabMenu()
    if not self._otherModes or #self._otherModes==0 then return end
    self:EnsureOtherTabMenu()
    if self._otherTabBlocker:IsShown() then self:CloseOtherTabMenu(); return end
    self._otherTabBlocker:Show(); self:RefreshOtherTabMenu()
end

function UI:CloseOtherTabMenu()
    if self._otherTabBlocker then self._otherTabBlocker:Hide() end
    if self.otherTab and self.otherTab:IsShown() then
        local h=(self._otherModes and #self._otherModes or 0)*22+4
        self:SetOtherTabArrowDirection(self:GetOtherMenuDirection(h))
    end
end

function UI:LayoutTabs()
    if not self.tabs or not self.tabBar then return end
    local w=self.tabBar:GetWidth(); if w<=0 then return end
    local tabFont,tabSize,tabOutline,tabShadow=self:GetDisplayFontConfig("tab")
    for _,tab in ipairs(self.tabs) do self:ApplyFont(tab.text,tabFont,tabSize,tabOutline,tabShadow) end
    self:ApplyFont(self.otherTab.text,tabFont,tabSize,tabOutline,tabShadow)
    local displayMode=(self._previewContext and self._previewContext.displayMode) or ns.db.display.mode
    self._lastTabDisplayMode=displayMode
    local configured=ns.db.display.bottomBarModes or {}
    local direct={self._tabByMode.overview}; local hiddenSet={}
    for _,mode in ipairs(ns.MODE_ORDER) do
        if configured[mode]==true then direct[#direct+1]=self._tabByMode[mode] else hiddenSet[mode]=true end
    end

    local labelStyle=ns.db.display.tabLabelStyle=="short" and "short" or "full"
    local responsiveShort=labelStyle=="short"
    local function SetLabels()
        for _,tab in ipairs(direct) do tab.text:SetText(self:GetBottomTabLabel(tab.mode,responsiveShort)) end
    end
    local function HiddenCount() local n=0; for _ in pairs(hiddenSet) do n=n+1 end; return n end
    local function CarrierLabel()
        if hiddenSet[displayMode] then return self:GetBottomTabLabel(displayMode,responsiveShort) end
        return L.MORE
    end
    local function CarrierWidth()
        local maxWidth=0
        self.otherTab.text:SetText(L.MORE); maxWidth=math.max(maxWidth,safeTextWidth(self.otherTab.text))
        for _,mode in ipairs(ns.MODE_ORDER) do
            self.otherTab.text:SetText(self:GetBottomTabLabel(mode,responsiveShort)); maxWidth=math.max(maxWidth,safeTextWidth(self.otherTab.text))
        end
        self.otherTab.text:SetText(CarrierLabel())
        return math.max(50,math.ceil(maxWidth+30))
    end
    local function DesiredTotal()
        SetLabels(); local total=0
        for _,tab in ipairs(direct) do total=total+math.max(38,math.ceil(safeTextWidth(tab.text)+18)) end
        if HiddenCount()>0 then total=total+CarrierWidth() end
        return total
    end

    local total=DesiredTotal()
    while total>w and #direct>1 do
        local moved=table.remove(direct); hiddenSet[moved.mode]=true; total=DesiredTotal()
    end

    local hidden={}; for _,mode in ipairs(ns.MODE_ORDER) do if hiddenSet[mode] then hidden[#hidden+1]=mode end end
    self._otherModes=hidden
    for _,tab in ipairs(self.tabs) do tab:Hide() end
    local showOther=#hidden>0; self.otherTab:SetShown(showOther)
    self.otherTab.text:SetText(CarrierLabel())
    local items={}; for _,tab in ipairs(direct) do items[#items+1]=tab end; if showOther then items[#items+1]=self.otherTab end
    local desired={}; local desiredSum=0
    for i,item in ipairs(items) do
        local dw
        if item==self.otherTab then dw=CarrierWidth() else dw=math.max(38,math.ceil(safeTextWidth(item.text)+18)) end
        desired[i]=dw; desiredSum=desiredSum+dw
    end
    local extra=math.max(0,w-desiredSum)/math.max(1,#items); local x=0
    for i,item in ipairs(items) do
        local iw=(i==#items) and math.max(1,w-x) or math.max(1,desired[i]+extra)
        item:ClearAllPoints(); item:SetPoint("TOPLEFT",self.tabBar,"TOPLEFT",x,0); item:SetSize(iw,self.TAB_H); item:Show(); x=x+iw
        local active=(item==self.otherTab) and hiddenSet[displayMode] or item.mode==displayMode
        item._active=active; item.abg:SetShown(active); self:SetTabTextColor(item.text,active)
        if item==self.otherTab then
            local labelW=math.min(safeTextWidth(item.text),math.max(1,iw-(OTHER_ARROW_W+9))); local groupW=labelW+OTHER_ARROW_W+1
            item.text:ClearAllPoints(); item.text:SetPoint("LEFT",item,"CENTER",-groupW/2,0); item.text:SetWidth(labelW)
            item.arrow:ClearAllPoints(); item.arrow:SetPoint("LEFT",item.text,"RIGHT",1,0)
            self:SetTabTextColor(item.text,active or item._hovered)
            self:SetOtherTabArrowState(active or item._hovered)
        end
    end
    if showOther then self:SetOtherTabArrowDirection(self:GetOtherMenuDirection(#hidden*22+4)) else self:CloseOtherTabMenu() end
    if self._otherTabBlocker and self._otherTabBlocker:IsShown() then self:RefreshOtherTabMenu() end
end

function UI:Layout()
    if not self.frame or not self.frame:IsShown() then return end
    self:LayoutTabs()
    if self.summaryBar then self.summaryBar:Hide() end
    self.bodyFrame:ClearAllPoints(); self.bodyFrame:SetPoint("TOPLEFT",self.titleBar,"BOTTOMLEFT",0,0); self.bodyFrame:SetPoint("BOTTOMRIGHT",self.tabBar,"TOPRIGHT",0,0)
    self:DoLayout()
    self:UpdateLockState()
end

local function tracks(ratios,total,gap)
    local count=#ratios; local usable=math.max(1,total-gap*(count-1)); local starts,sizes={},{}
    local pos=0
    for i=1,count do
        starts[i]=pos
        local size=(i==count) and (total-pos) or math.floor(usable*ratios[i]+.5)
        sizes[i]=math.max(1,size); pos=pos+size+gap
    end
    return starts,sizes
end

function UI:DoLayout()
    if not self.bodyFrame then return end
    local w,h=self.bodyFrame:GetWidth(),self.bodyFrame:GetHeight(); if w<=0 or h<=0 then return end
    self._pinnedSfOrigH={}; self._pinnedSfSavedAnchors={}
    local def=self:GetRenderLayout(); if not def then return end
    local gap=ns.Layouts.GAP; local xs,ws=tracks(def.colR,w,gap); local ys,hs=tracks(def.rowR,h,gap)
    wipe(self._activeGridCells)
    for i,layoutCell in ipairs(def.cells) do
        local cell=self:EnsureGridCell(i); self._activeGridCells[#self._activeGridCells+1]=cell
        cell.layoutCell=layoutCell; cell.stat=layoutCell.stat; cell.range=layoutCell.range; cell.frame:Show()
        local x=xs[layoutCell.c0]; local y=ys[layoutCell.r0]
        local cw=0; for c=layoutCell.c0,layoutCell.c1 do cw=cw+ws[c]; if c<layoutCell.c1 then cw=cw+gap end end
        local ch=0; for r=layoutCell.r0,layoutCell.r1 do ch=ch+hs[r]; if r<layoutCell.r1 then ch=ch+gap end end
        cell.frame:ClearAllPoints(); cell.frame:SetPoint("TOPLEFT",self.gridRoot,"TOPLEFT",x,-y); cell.frame:SetSize(cw,ch)
        cell.head:ClearAllPoints(); cell.head:SetPoint("TOPLEFT",cell.frame,"TOPLEFT",0,0); cell.head:SetPoint("TOPRIGHT",cell.frame,"TOPRIGHT",0,0); cell.head:Show()
        cell.list.sf:ClearAllPoints(); cell.list.sf:SetPoint("TOPLEFT",cell.head,"BOTTOMLEFT",0,0); cell.list.sf:SetPoint("BOTTOMRIGHT",cell.frame,"BOTTOMRIGHT",0,0); cell.list.sf:Show()
    end
    for i=#def.cells+1,#self.gridCells do
        local cell=self.gridCells[i]
        cell.frame:Hide()
        if cell.pinned then cell.pinned.frame:Hide() end
        if self._pinnedSelfCache then self._pinnedSelfCache[cell.poolKey]=nil end
        for _,bar in ipairs(cell.bars or {}) do if self.ReleaseBarData then self:ReleaseBarData(bar) end end
    end
    if not self._resizing then
        self:ApplyTheme(); self._lastFontHash=nil; self:ApplyAllFontsIfNeeded()
    end
    self:Refresh()
end

function UI:ApplyTheme()
    local dbw=ns.db.window; local tc=dbw.themeColor or {0,0,0,1}; local bc=dbw.bgColor or {.02,.02,.025,.58}
    if self.frame then self.frame:SetBackdropColor(unpack(bc)) end
    if self.titleBg then self.titleBg:SetColorTexture(unpack(tc)) end
    if self.tabBg then self.tabBg:SetColorTexture(unpack(tc)) end
    for _,cell in ipairs(self.gridCells or {}) do
        local sc={tc[1]*.9,tc[2]*.9,tc[3]*.9,tc[4]}; cell.head.bg:SetColorTexture(unpack(sc))
        local fill=(cell.range=="total") and (dbw.ovrBgColor or {.025,.035,.05,.62}) or bc
        cell.frame:SetBackdropColor(unpack(fill))
    end
end

local oldApplyAllFonts=UI.ApplyAllFonts
function UI:ApplyAllFonts()
    if oldApplyAllFonts then oldApplyAllFonts(self) end
    local hFont,hSz,hOut,hShad=self:GetDisplayFontConfig("header")
    local tFont,tSz,tOut,tShad=self:GetDisplayFontConfig("tab")
    if self.otherTab then self:ApplyFont(self.otherTab.text,tFont,tSz,tOut,tShad) end
    if self._otherTabMenu then for _,item in ipairs(self._otherTabMenu.items or {}) do self:ApplyFont(item.text,tFont,tSz,tOut,tShad) end end
    for _,cell in ipairs(self.gridCells or {}) do
        self:ApplyFont(cell.head.label,hFont,hSz,hOut,hShad); self:ApplyFont(cell.head.info,hFont,hSz,hOut,hShad)
        if cell.head.rawInfo then self:ApplyFont(cell.head.rawInfo,hFont,hSz,hOut,hShad) end
        self:SetFontStringColor(cell.head.info,"headerFontColor",{.55,.55,.55,.9})
        if cell.head.rawInfo then self:SetFontStringColor(cell.head.rawInfo,"headerFontColor",{.55,.55,.55,.9}) end
    end
end

function UI:GetPreviewSegment(range)
    local model=self._previewContext and self._previewContext.model
    if not model then return nil end
    if range=="total" then return model.overall end
    return model:GetViewSegment()
end

function UI:ResolveCellSource(cell)
    local source=self:GetDisplaySource(cell.range)
    return source.segment,source.duration,source.sessionType,source.sessionID,source
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:BeginDataRefresh()
    local displayMode=(self._previewContext and self._previewContext.displayMode) or ns.db.display.mode
    if self._lastTabDisplayMode~=displayMode then self:LayoutTabs() end
    local now=GetTime()
    local titleSegment=self._previewContext and self:GetPreviewSegment("current")
        or (ns.Segments and ns.Segments:GetViewSegment())
    local titleCombat=ns.state.inCombat==true
    if titleSegment~=self._lastTitleSegment or titleCombat~=self._lastTitleCombat
        or not self._lastTitleRefresh or now-self._lastTitleRefresh>=0.5 then
        self._lastTitleRefresh=now
        self._lastTitleSegment=titleSegment
        self._lastTitleCombat=titleCombat
        self:RefreshTitle()
    end
    if self._collapsed then return end
    for _,cell in ipairs(self._activeGridCells or {}) do
        local seg,dur,sessionType,sessionID,source=self:ResolveCellSource(cell)
        self:FillModeBars(cell.bars,cell.list,cell.head,cell.stat,seg,dur,sessionType,sessionID,source)
        if cell.range=="total" then
            local label=L[ns.MODE_NAMES[cell.stat] or cell.stat]
            self:SetModeHeaderText(cell.head.label,string.format(L.OVERALL_MODE_HEADER_FORMAT,L.OVERALL,label),cell.stat)
        end
        for _,bar in ipairs(cell.bars) do if bar.frame:IsShown() then bar._detailSegment=seg; bar._detailRange=cell.range; bar._detailDisplaySource=source end end
        if cell.pinned then cell.pinned._detailSegment=seg; cell.pinned._detailRange=cell.range; cell.pinned._detailDisplaySource=source end
    end
end

local oldRefreshTitle=UI.RefreshTitle
function UI:RefreshTitle()
    local ctx=self._previewContext
    if not ctx then return oldRefreshTitle(self) end
    local seg=ctx.model and ctx.model:GetViewSegment(); local dur=seg and (seg.duration or 0) or 0
    if self.titleTime then self.titleTime:SetText(dur>0 and ("|cffaaaaaa"..ns:FormatTime(dur).."|r") or "") end
    if self.titleText then self.titleText:SetText(seg and (seg.name or L.CURRENT) or L.NO_DATA) end
end

function UI:PersistWorkspaceGeometry()
    local ws=self:GetRenderWorkspace(); local point,_,relPoint,x,y=self.frame:GetPoint()
    ws.point=point; ws.relPoint=relPoint; ws.x=x; ws.y=y; ws.windowWidth=self.frame:GetWidth(); ws.windowHeight=(self._collapsed and self._savedHeight) or self.frame:GetHeight()
    if self._collapsed then self._savedAnchor={point,UIParent,relPoint,x,y} end
    if self._previewContext and ns.Config and ns.Config.RefreshLayoutStudio then ns.Config:RefreshLayoutStudio() end
end

function UI:SetupDrag()
    local function start() if not ns.db.window.locked then self.frame:StartMoving() end end
    local function stop() self.frame:StopMovingOrSizing(); self:PersistWorkspaceGeometry() end
    self.titleBar:EnableMouse(true); self.titleBar:RegisterForDrag("LeftButton"); self.titleBar:SetScript("OnDragStart",start); self.titleBar:SetScript("OnDragStop",stop)
end

function UI:BuildResize()
    local g=CreateFrame("Frame",nil,self.frame); self.resizeHandle=g; g:SetSize(16,16); g:SetPoint("BOTTOMRIGHT",0,0); g:SetFrameLevel(self.frame:GetFrameLevel()+15); g:EnableMouse(true)
    local t=g:CreateTexture(nil,"OVERLAY"); t:SetAllPoints(); t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"); t:SetVertexColor(.55,.58,.62,.9); g.iconTex=t
    g:SetScript("OnEnter",function() t:SetVertexColor(.15,.85,1,1) end)
    g:SetScript("OnLeave",function() t:SetVertexColor(.55,.58,.62,.9) end)
    g:SetScript("OnMouseDown",function() if ns.db.window.locked then return end; local minW,minH=ns.Layouts:GetMinimumWindowSize(self:GetRenderLayout()); if self.frame.SetResizeBounds then self.frame:SetResizeBounds(minW,minH,math.max(1600,minW),math.max(1200,minH)) end; self.frame:StartSizing("BOTTOMRIGHT"); self._resizing=true end)
    g:SetScript("OnMouseUp",function()
        if not self._resizing then return end
        self._resizing=false
        self._resizeLayoutToken=(self._resizeLayoutToken or 0)+1
        self._resizeLayoutPending=nil
        self.frame:StopMovingOrSizing(); self:PersistWorkspaceGeometry(); self:Layout()
    end)
end

function UI:OnResize()
    if self._applyingWorkspace then return end
    -- WoW may emit several OnSizeChanged callbacks in one rendered frame.
    -- Keep exactly one full, data-bearing layout for that frame; this preserves
    -- live bars/text while avoiding duplicate tab/grid work and timer closures.
    if self._resizeLayoutPending then return end
    self._resizeLayoutToken=(self._resizeLayoutToken or 0)+1
    local token=self._resizeLayoutToken
    self._resizeLayoutPending=true
    C_Timer.After(0,function()
        if token~=self._resizeLayoutToken then return end
        self._resizeLayoutPending=nil
        if self._applyingWorkspace then return end
        self:LayoutTabs()
        self:DoLayout()
    end)
end

function UI:ApplySceneWorkspace(scene)
    if not self.frame then return end
    scene=scene or activeScene(); local ws=ns.Layouts:GetWorkspace(scene); local def=self:GetRenderLayout()
    local minW,minH=ns.Layouts:GetMinimumWindowSize(def); local w=math.max(minW,tonumber(ws.windowWidth) or 420); local h=math.max(minH,tonumber(ws.windowHeight) or 300)
    ws.windowWidth,ws.windowHeight=w,h
    local appliedH=h; if self._collapsed and not self._previewContext then self._savedHeight=h; self._savedAnchor={ws.point or "CENTER",UIParent,ws.relPoint or ws.point or "CENTER",ws.x or 320,ws.y or -170}; appliedH=self.TITLE_H end
    self._applyingWorkspace=true; self.frame:ClearAllPoints(); self.frame:SetPoint(ws.point or "CENTER",UIParent,ws.relPoint or ws.point or "CENTER",ws.x or 320,ws.y or -170); self.frame:SetSize(w,appliedH); self._applyingWorkspace=false
    self:Layout()
end

function UI:UpdateLockState()
    local locked=ns.db.window.locked and true or false
    if self.frame then
        if locked then
            self.frame:StopMovingOrSizing(); self._resizing=false
            self._resizeLayoutToken=(self._resizeLayoutToken or 0)+1
            self._resizeLayoutPending=nil
        end
        self.frame:SetMovable(not locked); self.frame:SetResizable(not locked)
    end
    if self.resizeHandle then self.resizeHandle:SetShown(not locked and not self._collapsed) end
    if ns.DetailView and ns.DetailView.UpdateLockState then ns.DetailView:UpdateLockState() end
end
