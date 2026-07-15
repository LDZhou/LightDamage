-- Light Damage 2.0 - immediate-save layout library and scene assignment studio.
local addonName,ns=...
local L=ns.L
local Config=ns.Config

local STAT_KEYS={damage="DAMAGE",healing="HEALING",damageTaken="DAMAGE_TAKEN",deaths="DEATHS",enemyDamageTaken="ENEMY_DAMAGE_TAKEN",interrupts="INTERRUPTS",dispels="DISPELS"}
local SCENE_KEYS={mplus="SCENE_MPLUS",raid="SCENE_RAID",dungeon="SCENE_DUNGEON",arena="SCENE_ARENA",battleground="SCENE_BATTLEGROUND",outdoor="SCENE_OUTDOOR"}

local function txt(parent,size,text,point,x,y)
 local f=parent:CreateFontString(nil,"OVERLAY"); f:SetFont(STANDARD_TEXT_FONT,size or 10,""); f:SetPoint(point or "TOPLEFT",x or 0,y or 0); f:SetText(text or ""); return f
end

local function btn(self,parent,w,h,label,fn)
 local b=CreateFrame("Button",nil,parent); b:SetSize(w,h or 22); self:FillBg(b,.08,.11,.16,1); self:CreateBorder(b,.25,.35,.48,1)
 b.text=txt(b,10,label,"CENTER",0,0); b.text:ClearAllPoints(); b.text:SetPoint("LEFT",4,0); b.text:SetPoint("RIGHT",-4,0); b.text:SetJustifyH("CENTER"); b.text:SetWordWrap(false)
 b:SetScript("OnClick",fn); b:SetScript("OnEnter",function() b.text:SetTextColor(.3,.85,1) end); b:SetScript("OnLeave",function() b.text:SetTextColor(1,1,1) end); return b
end

local function menuBtn(self,parent,w,h,label,fn)
 local b=btn(self,parent,w,h,label,fn); b.text:ClearAllPoints(); b.text:SetPoint("LEFT",8,0); b.text:SetPoint("RIGHT",-24,0); b.text:SetJustifyH("LEFT")
 local arrow=txt(b,10,"v","RIGHT",-8,0); arrow:SetTextColor(.65,.72,.8,1); b.arrow=arrow
 return b
end

local function controlGroup(self,parent,w)
 local f=CreateFrame("Frame",nil,parent,"BackdropTemplate"); f:SetSize(w,22); f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); f:SetBackdropColor(.045,.06,.08,1); self:CreateBorder(f,.18,.28,.38,1); return f
end

local function cellAt(def,r,c) return ns.Layouts:FindCell(def,r,c) end

function Config:BuildLayoutPage()
 local inner=self.pages.layout.inner; inner:SetHeight(510)
 local s={root=inner,tab="library",selectedId="preset2",cellButtons={},dividers={},layoutButtons={},sceneCards={}}
 self._layoutStudio=s
 s.libraryTab=btn(self,inner,126,26,L.LAYOUT_LIBRARY,function() s.tab="library"; self:RefreshLayoutStudio() end); s.libraryTab:SetPoint("TOPLEFT",0,0)
 s.sceneTab=btn(self,inner,150,26,L.SCENE_ASSIGNMENTS,function() s.tab="scenes"; self:RefreshLayoutStudio() end); s.sceneTab:SetPoint("LEFT",s.libraryTab,"RIGHT",6,0)
 s.saved=txt(inner,10,"","TOPRIGHT",-4,-7); s.saved:SetTextColor(.3,1,.5)

 s.library=CreateFrame("Frame",nil,inner); s.library:SetPoint("TOPLEFT",0,-36); s.library:SetSize(600,450)
 s.left=CreateFrame("Frame",nil,s.library,"BackdropTemplate"); s.left:SetSize(176,438); s.left:SetPoint("TOPLEFT"); s.left:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); s.left:SetBackdropColor(.035,.035,.045,1)
 s.left:EnableMouseWheel(true); s.left:SetScript("OnMouseWheel",function(_,delta) local customCount=math.max(0,#ns.Layouts:ListLayouts()-3); local visible=11; s.layoutOffset=math.max(0,math.min(math.max(0,customCount-visible),(s.layoutOffset or 0)-delta)); self:RefreshLayoutStudio() end)
 s.officialLabel=txt(s.left,10,L.OFFICIAL_PRESETS,"TOPLEFT",8,-8); s.officialLabel:SetWidth(160); s.officialLabel:SetWordWrap(false); s.officialLabel:SetTextColor(0,.8,1)
 for i=1,3 do local index=i; local b=btn(self,s.left,160,24,"",function() local d=s.layoutButtons[index]._def; if d then s.selectedId=d.id; s.selection=nil; s.ratioSelection=nil; self:RefreshLayoutStudio() end end); b:SetPoint("TOPLEFT",8,-26-(i-1)*25); b.sel=b:CreateTexture(nil,"OVERLAY"); b.sel:SetWidth(3); b.sel:SetPoint("TOPLEFT",1,-1); b.sel:SetPoint("BOTTOMLEFT",1,1); b.sel:SetColorTexture(0,.8,1,1); b.sel:Hide(); s.layoutButtons[i]=b end
 s.sectionLine=s.left:CreateTexture(nil,"ARTWORK"); s.sectionLine:SetHeight(1); s.sectionLine:SetPoint("TOPLEFT",8,-105); s.sectionLine:SetPoint("TOPRIGHT",-8,-105); s.sectionLine:SetColorTexture(.15,.22,.3,1)
 s.customLabel=txt(s.left,10,L.CUSTOM_LAYOUT,"TOPLEFT",8,-111); s.customLabel:SetWidth(160); s.customLabel:SetWordWrap(false); s.customLabel:SetTextColor(.65,.75,.85)
 for i=4,14 do local index=i; local b=btn(self,s.left,160,24,"",function() local d=s.layoutButtons[index]._def; if d then s.selectedId=d.id; s.selection=nil; s.ratioSelection=nil; self:RefreshLayoutStudio() end end); b:SetPoint("TOPLEFT",8,-130-(i-4)*25); b.sel=b:CreateTexture(nil,"OVERLAY"); b.sel:SetWidth(3); b.sel:SetPoint("TOPLEFT",1,-1); b.sel:SetPoint("BOTTOMLEFT",1,1); b.sel:SetColorTexture(0,.8,1,1); b.sel:Hide(); s.layoutButtons[i]=b end
 s.newBtn=btn(self,s.left,160,24,L.NEW_LAYOUT,function() local d=ns.Layouts:CreateCustom(); s.selectedId=d.id; s.selection=nil; s.ratioSelection=nil; self:StudioSaved(); self:RefreshLayoutStudio() end); s.newBtn:SetPoint("BOTTOMLEFT",8,8)

 s.editor=CreateFrame("Frame",nil,s.library); s.editor:SetPoint("TOPLEFT",s.left,"TOPRIGHT",12,0); s.editor:SetSize(410,438)
 s.name=CreateFrame("EditBox",nil,s.editor); s.name:SetSize(210,24); s.name:SetPoint("TOPLEFT",0,0); s.name:SetAutoFocus(false); s.name:SetFont(STANDARD_TEXT_FONT,12,"OUTLINE"); self:FillBg(s.name,.07,.07,.09,1); self:CreateBorder(s.name,.25,.35,.45,1); s.name:SetTextInsets(6,6,0,0)
 s.name:SetScript("OnEscapePressed",function(e) e:SetText(ns.Layouts:GetLayoutName(ns.Layouts:GetLayout(s.selectedId))); e:ClearFocus() end)
 local function validName(def,name)
  if not def or def.isPreset then return false end
  local duplicate=false
  for id,d in pairs(ns.db.layoutDefs or {}) do if id~=def.id and ns.Layouts:GetLayoutName(d):lower()==name:lower() then duplicate=true end end
  local nameLength=strlenutf8 and strlenutf8(name) or #name
  return name~="" and not duplicate and nameLength<=40
 end
 local function refreshNameInList(def)
  for _,listButton in ipairs(s.layoutButtons) do
   if listButton._def and listButton._def.id==def.id then listButton.text:SetText(ns.Layouts:GetLayoutName(def)) end
  end
 end
 local function commitName(e)
  local def=ns.Layouts:GetLayout(s.selectedId); if not def or def.isPreset then return end
  local name=(e:GetText() or ""):trim()
  if not validName(def,name) then s._settingName=true; e:SetText(ns.Layouts:GetLayoutName(def)); s._settingName=nil; s.error:SetText(L.INVALID_LAYOUT_NAME); return end
  if name~=ns.Layouts:GetLayoutName(def) then
   def.name=name; def.migratedScene=nil; s.error:SetText(""); refreshNameInList(def); self:StudioSaved()
  end
 end
 s.name:SetScript("OnTextChanged",function(e,userInput)
  if not userInput or s._settingName then return end
  local def=ns.Layouts:GetLayout(s.selectedId); local name=(e:GetText() or ""):trim()
  if validName(def,name) then def.name=name; def.migratedScene=nil; s.error:SetText(""); refreshNameInList(def); self:StudioSaved()
  else s.error:SetText(L.INVALID_LAYOUT_NAME) end
 end)
 s.name:SetScript("OnEnterPressed",function(e) commitName(e); e:ClearFocus() end); s.name:SetScript("OnEditFocusLost",commitName)
 s.copy=btn(self,s.editor,104,24,L.COPY_CUSTOM,function() local d=ns.Layouts:GetLayout(s.selectedId); if d then local n=ns.Layouts:CreateCustom(d); s.selectedId=n.id; s.selection=nil; s.ratioSelection=nil; self:StudioSaved(); self:RefreshLayoutStudio() end end); s.copy:SetPoint("LEFT",s.name,"RIGHT",8,0)
 s.delete=btn(self,s.editor,80,24,L.DELETE,function() self:ShowLayoutDeleteConfirm() end); s.delete:SetPoint("LEFT",s.copy,"RIGHT",8,0)
 s.rowGroup=controlGroup(self,s.editor,112); s.rowGroup:SetPoint("TOPLEFT",0,-32); s.rowLabel=txt(s.rowGroup,10,"","LEFT",8,0); s.rowLabel:SetWidth(52); s.rowLabel:SetWordWrap(false); s.rowLabel:SetJustifyH("LEFT")
 s.rowMinus=btn(self,s.rowGroup,22,20,"-",function() self:StudioTrack("row",false) end); s.rowMinus:SetPoint("RIGHT",s.rowGroup,"RIGHT",-25,0); s.rowPlus=btn(self,s.rowGroup,22,20,"+",function() self:StudioTrack("row",true) end); s.rowPlus:SetPoint("RIGHT",s.rowGroup,"RIGHT",-2,0)
 s.colGroup=controlGroup(self,s.editor,112); s.colGroup:SetPoint("TOPLEFT",120,-32); s.colLabel=txt(s.colGroup,10,"","LEFT",8,0); s.colLabel:SetWidth(52); s.colLabel:SetWordWrap(false); s.colLabel:SetJustifyH("LEFT")
 s.colMinus=btn(self,s.colGroup,22,20,"-",function() self:StudioTrack("col",false) end); s.colMinus:SetPoint("RIGHT",s.colGroup,"RIGHT",-25,0); s.colPlus=btn(self,s.colGroup,22,20,"+",function() self:StudioTrack("col",true) end); s.colPlus:SetPoint("RIGHT",s.colGroup,"RIGHT",-2,0)
 s.merge=btn(self,s.editor,78,22,L.MERGE,function() self:StudioMerge() end); s.merge:SetPoint("TOPLEFT",246,-32)
 s.split=btn(self,s.editor,78,22,L.SPLIT,function() self:StudioSplit() end); s.split:SetPoint("TOPRIGHT",0,-32)

 s.board=CreateFrame("Frame",nil,s.editor,"BackdropTemplate"); s.board:SetSize(410,267); s.board:SetPoint("TOPLEFT",0,-64); s.board:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); s.board:SetBackdropColor(.025,.025,.035,1); self:CreateBorder(s.board,.2,.3,.4,1)
 s.board._dragOnUpdate=function() self:UpdateStudioRatioDrag(); self:UpdateStudioCellSelection() end
 s.board:EnableKeyboard(true); s.board:SetPropagateKeyboardInput(true); s.board:SetScript("OnKeyDown",function(frame,key) if key=="ESCAPE" and (s.selection or s.drag or s.ratioPreview) then frame:SetPropagateKeyboardInput(false); s.selection=nil; s.drag=nil; s.dragSelect=nil; s.ratioPreview=nil; s.sliderBase=nil; s.board:SetScript("OnUpdate",nil); s.error:SetText(""); self:RefreshLayoutStudio(); C_Timer.After(0,function() frame:SetPropagateKeyboardInput(true) end) end end)
 s.statLabel=txt(s.editor,10,L.STAT_TYPE,"TOPLEFT",0,-345); s.statLabel:SetWidth(201); s.statLabel:SetWordWrap(false); s.stat=menuBtn(self,s.editor,201,22,"",function() self:ShowStudioStatMenu() end); s.stat:SetPoint("TOPLEFT",0,-361)
 s.rangeLabel=txt(s.editor,10,L.DATA_RANGE,"TOPLEFT",209,-345); s.rangeLabel:SetWidth(201); s.rangeLabel:SetWordWrap(false); s.range=menuBtn(self,s.editor,201,22,"",function() self:ShowStudioRangeMenu() end); s.range:SetPoint("TOPLEFT",209,-361)
 s.ratioLabel=txt(s.editor,10,L.PRECISE_RATIO,"TOPLEFT",0,-397); s.ratioLabel:SetWidth(72); s.ratioLabel:SetWordWrap(false); s.ratioSlider=CreateFrame("Slider",nil,s.editor); s.ratioSlider:SetSize(145,12); s.ratioSlider:SetPoint("TOPLEFT",74,-393); s.ratioSlider:SetOrientation("HORIZONTAL"); s.ratioSlider:SetMinMaxValues(.06,.94); s.ratioSlider:SetValueStep(.01); s.ratioSlider:SetObeyStepOnDrag(true)
 local ratioTrack=s.ratioSlider:CreateTexture(nil,"BACKGROUND"); ratioTrack:SetHeight(2); ratioTrack:SetPoint("LEFT"); ratioTrack:SetPoint("RIGHT"); ratioTrack:SetColorTexture(.2,.25,.3,1); s.ratioSlider:SetThumbTexture("Interface\\Buttons\\WHITE8X8"); s.ratioSlider:GetThumbTexture():SetSize(10,12); s.ratioSlider:GetThumbTexture():SetVertexColor(0,.8,1,1)
 s.ratioValue=txt(s.editor,10,"-","TOPLEFT",222,-397); s.ratioValue:SetWidth(102); s.ratioValue:SetJustifyH("CENTER"); s.equalize=btn(self,s.editor,80,22,L.EQUALIZE,function() self:EqualizeStudioBoundary() end); s.equalize:SetPoint("TOPRIGHT",0,-389)
 s.ratioSlider:SetScript("OnMouseDown",function() self:BeginStudioSlider() end); s.ratioSlider:SetScript("OnMouseUp",function() self:CommitStudioSlider() end); s.ratioSlider:SetScript("OnValueChanged",function(_,v) self:PreviewStudioSlider(v) end)
 s.error=txt(s.editor,10,"","TOPLEFT",0,-424); s.error:SetWidth(410); s.error:SetJustifyH("LEFT"); s.error:SetTextColor(1,.35,.35)
 s.editControls={s.name,s.delete,s.rowGroup,s.colGroup,s.merge,s.split,s.statLabel,s.stat,s.rangeLabel,s.range,s.ratioLabel,s.ratioSlider,s.ratioValue,s.equalize,s.error}

 s.scenes=CreateFrame("Frame",nil,inner); s.scenes:SetPoint("TOPLEFT",0,-42); s.scenes:SetSize(600,450)
 local intro=txt(s.scenes,10,L.SCENE_ASSIGNMENTS_DESC,"TOPLEFT",0,0); intro:SetWidth(590); intro:SetJustifyH("LEFT"); intro:SetTextColor(.6,.6,.65)
 for i,scene in ipairs(ns.Layouts.SCENES) do
  local sceneId=scene
  local card=CreateFrame("Frame",nil,s.scenes,"BackdropTemplate"); card:SetSize(286,116); card:SetPoint("TOPLEFT",((i-1)%2)*304,-48-math.floor((i-1)/2)*128); card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); card:SetBackdropColor(.045,.045,.06,1); self:CreateBorder(card,.18,.25,.35,1)
  card.title=txt(card,12,L[SCENE_KEYS[sceneId]],"TOPLEFT",10,-10); card.title:SetTextColor(0,.8,1)
  card.layout=menuBtn(self,card,260,26,"",function() self:ShowSceneLayoutMenu(sceneId,card.layout) end); card.layout:SetPoint("TOPLEFT",10,-38)
  card.meta=txt(card,10,"","TOPLEFT",10,-74); card.meta:SetWidth(266); card.meta:SetHeight(30); card.meta:SetJustifyH("LEFT"); card.meta:SetWordWrap(false); card.meta:SetTextColor(.6,.6,.65); s.sceneCards[sceneId]=card
 end

 s.confirm=CreateFrame("Frame",nil,s.editor,"BackdropTemplate"); s.confirm:SetAllPoints(); s.confirm:SetFrameLevel(s.editor:GetFrameLevel()+30); s.confirm:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); s.confirm:SetBackdropColor(.03,.03,.04,.98); s.confirm:Hide()
 s.confirmText=txt(s.confirm,11,"","TOPLEFT",28,-80); s.confirmText:SetWidth(350); s.confirmText:SetJustifyH("LEFT")
 local yes=btn(self,s.confirm,110,26,L.CONFIRM_DELETE,function() local id=s.confirm._id; s.confirm:Hide(); if ns.Layouts:DeleteCustom(id) then s.selectedId="preset1"; s.selection=nil; s.ratioSelection=nil; self:StudioSaved(); self:RefreshLayoutStudio() end end); yes:SetPoint("BOTTOMLEFT",70,70)
 local no=btn(self,s.confirm,110,26,L.CANCEL,function() s.confirm:Hide() end); no:SetPoint("BOTTOMRIGHT",-70,70)
 self:RefreshLayoutStudio()
end

function Config:StudioSaved()
 local s=self._layoutStudio; if not s then return end; s.saved:SetText(L.SAVED); if s._savedTimer then s._savedTimer:Cancel() end
 s._savedTimer=C_Timer.NewTimer(1.2,function() if s.saved then s.saved:SetText("") end end)
end

function Config:GetStudioDef()
 local s=self._layoutStudio; if not s then return end
 local def=ns.Layouts:GetLayout(s.selectedId); if not def then s.selectedId="preset2"; def=ns.Layouts:GetLayout("preset2") end
 if s.ratioPreview then return s.ratioPreview end
 if s.drag and s.drag.preview then return s.drag.preview end
 return def
end

function Config:GetStudioSelectedCell(def)
 local s=self._layoutStudio; local q=s and s.selection; if not q or not def then return nil end
 for _,cell in ipairs(def.cells or {}) do
  if cell.r0==q.r0 and cell.c0==q.c0 and cell.r1==q.r1 and cell.c1==q.c1 then return cell end
 end
end

function Config:RefreshLayoutStudio()
 local s=self._layoutStudio; if not s then return end
 s.library:SetShown(s.tab=="library"); s.scenes:SetShown(s.tab=="scenes"); s.libraryTab.text:SetTextColor(s.tab=="library" and 0 or 1,s.tab=="library" and .85 or 1,1); s.sceneTab.text:SetTextColor(s.tab=="scenes" and 0 or 1,s.tab=="scenes" and .85 or 1,1)
 if s.tab=="scenes" then
  local layouts=ns.Layouts:ListLayouts()
  for scene,card in pairs(s.sceneCards) do local ws=ns.Layouts:GetWorkspace(scene); local d=ns.Layouts:GetLayout(ws.layoutId); card.layout.text:SetText(ns.Layouts:GetLayoutName(d)); card.meta:SetText(string.format(L.SCENE_GEOMETRY_FORMAT,d.rows,d.cols,ws.windowWidth,ws.windowHeight,ws.point or "CENTER",ws.x or 0,ws.y or 0)) end
  return
 end
 local list=ns.Layouts:ListLayouts()
 for i=1,3 do local b=s.layoutButtons[i]; local d=list[i]; b._def=d; b:SetShown(d~=nil); if d then local active=d.id==s.selectedId; b.text:SetText(ns.Layouts:GetLayoutName(d)); b.text:SetTextColor(active and 0 or .85,active and .85 or .85,active and 1 or .85); b.sel:SetShown(active) end end
 local selectedCustomIndex
 for i=4,#list do if list[i].id==s.selectedId then selectedCustomIndex=i-3; break end end
 local visible=11; local customCount=math.max(0,#list-3)
 if selectedCustomIndex then
  if selectedCustomIndex<(s.layoutOffset or 0)+1 then s.layoutOffset=selectedCustomIndex-1 elseif selectedCustomIndex>(s.layoutOffset or 0)+visible then s.layoutOffset=selectedCustomIndex-visible end
 end
 local offset=math.max(0,math.min(s.layoutOffset or 0,math.max(0,customCount-visible))); s.layoutOffset=offset
 for i=4,14 do local b=s.layoutButtons[i]; local d=list[4+offset+(i-4)]; b._def=d; b:SetShown(d~=nil); if d then local active=d.id==s.selectedId; b.text:SetText(ns.Layouts:GetLayoutName(d)); b.text:SetTextColor(active and 0 or .85,active and .85 or .85,active and 1 or .85); b.sel:SetShown(active) else b.sel:Hide() end end
 local def=self:GetStudioDef(); local preset=def.isPreset
 s._settingName=true; s.name:SetText(ns.Layouts:GetLayoutName(def)); s._settingName=nil; s.name:SetEnabled(not preset); s.name:SetTextColor(1,1,1)
 for _,w in ipairs(s.editControls) do w:SetShown(not preset) end
 s.copy.text:SetText(preset and L.COPY_CUSTOM or L.DUPLICATE)
 s.copy:ClearAllPoints(); s.board:ClearAllPoints()
 if preset then
  s.copy:SetPoint("TOPLEFT",0,0); s.board:SetPoint("TOPLEFT",0,-36); s.board:SetSize(410,365); s.error:SetText("")
 else
  s.copy:SetPoint("LEFT",s.name,"RIGHT",8,0); s.board:SetPoint("TOPLEFT",0,-64); s.board:SetSize(410,267)
 end
 for _,w in ipairs({s.rowMinus,s.rowPlus,s.colMinus,s.colPlus,s.merge,s.split,s.stat,s.range}) do w:SetEnabled(not preset); w:SetAlpha(preset and .35 or 1) end
 s.rowLabel:SetText(L.ROWS.."  "..def.rows); s.colLabel:SetText(L.COLUMNS.."  "..def.cols)
 self:RefreshStudioRatioControl(def,preset)
 self:DrawStudioBoard()
 local selected=self:GetStudioSelectedCell(def)
  if selected then s.stat.text:SetText(L[STAT_KEYS[selected.stat]]); s.range.text:SetText(selected.range=="total" and L.LAYOUT_RANGE_TOTAL or L.LAYOUT_RANGE_CURRENT)
  else s.stat.text:SetText("-"); s.range.text:SetText("-") end
 if not preset then
  local q=s.selection; local canMerge=q and q.valid and not(q.r0==q.r1 and q.c0==q.c1); local canSplit=selected and (selected.r0~=selected.r1 or selected.c0~=selected.c1)
  s.merge:SetEnabled(canMerge and true or false); s.merge:SetAlpha(canMerge and 1 or .35); s.split:SetEnabled(canSplit and true or false); s.split:SetAlpha(canSplit and 1 or .35)
  s.stat:SetEnabled(selected and true or false); s.stat:SetAlpha(selected and 1 or .35); s.range:SetEnabled(selected and true or false); s.range:SetAlpha(selected and 1 or .35)
 end
end

function Config:DrawStudioBoard()
 local s=self._layoutStudio; local def=self:GetStudioDef(); if not s or not def then return end
 local W,H=s.board:GetWidth(),s.board:GetHeight(); local gap=2; local usableW=W-gap*(def.cols-1); local usableH=H-gap*(def.rows-1)
 local xs,ys={[1]=0},{[1]=0}; local ws,hs={},{}
 for c=1,def.cols do ws[c]=usableW*def.colR[c]; if c<def.cols then xs[c+1]=xs[c]+ws[c]+gap end end
 for r=1,def.rows do hs[r]=usableH*def.rowR[r]; if r<def.rows then ys[r+1]=ys[r]+hs[r]+gap end end
 for i,cell in ipairs(def.cells) do
  local boundCell=cell
  local b=s.cellButtons[i]; if not b then
   b=CreateFrame("Button",nil,s.board,"BackdropTemplate"); b:SetClipsChildren(true); b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
   b.label=txt(b,10,"","CENTER",0,6); b.label:SetJustifyH("CENTER"); b.label:SetJustifyV("MIDDLE"); b.label:SetWordWrap(false); if b.label.SetMaxLines then b.label:SetMaxLines(1) end
   b.rangeText=txt(b,9,"","CENTER",0,-8); b.rangeText:SetJustifyH("CENTER"); b.rangeText:SetJustifyV("MIDDLE"); b.rangeText:SetWordWrap(false); if b.rangeText.SetMaxLines then b.rangeText:SetMaxLines(1) end
   s.cellButtons[i]=b
  end
  b._cell=cell; b:ClearAllPoints(); local cw=0; for c=cell.c0,cell.c1 do cw=cw+ws[c]+(c<cell.c1 and gap or 0) end; local ch=0; for r=cell.r0,cell.r1 do ch=ch+hs[r]+(r<cell.r1 and gap or 0) end
  b:SetPoint("TOPLEFT",s.board,"TOPLEFT",xs[cell.c0],-ys[cell.r0]); b:SetSize(cw,ch); b:SetBackdropColor(.07,.12,.17,.98)
  local selected=s.selection and not(cell.r1<s.selection.r0 or cell.r0>s.selection.r1 or cell.c1<s.selection.c0 or cell.c0>s.selection.c1)
  local invalid=selected and s.selection and s.selection.valid==false
  b:SetBackdropColor(invalid and .28 or .07,invalid and .035 or .12,invalid and .035 or .17,.98)
  b:SetBackdropBorderColor(invalid and 1 or (selected and 0 or .2),invalid and .2 or (selected and .85 or .45),invalid and .2 or (selected and 1 or .65),1)
  local fullStat=L[STAT_KEYS[cell.stat]] or cell.stat; local shortStat=L[ns.MODE_SHORT[cell.stat] or STAT_KEYS[cell.stat]] or fullStat
  local rangeFull=cell.range=="total" and L.LAYOUT_RANGE_TOTAL or L.LAYOUT_RANGE_CURRENT
  local rangeShort=cell.range=="total" and L.LAYOUT_RANGE_TOTAL_SHORT or L.LAYOUT_RANGE_CURRENT_SHORT
  local singleLine=ch<32 or cw<56; local compact=cw<88
  b.label:ClearAllPoints(); b.rangeText:ClearAllPoints()
  if singleLine then
   b.label:SetFont(STANDARD_TEXT_FONT,9,""); b.label:SetPoint("LEFT",b,"LEFT",3,0); b.label:SetPoint("RIGHT",b,"RIGHT",-3,0); b.label:SetHeight(math.max(10,ch)); b.label:SetText(shortStat.."/"..rangeShort); b.rangeText:Hide()
  else
   b.label:SetFont(STANDARD_TEXT_FONT,10,""); b.label:SetPoint("LEFT",b,"LEFT",4,7); b.label:SetPoint("RIGHT",b,"RIGHT",-4,7); b.label:SetHeight(14); b.label:SetText(compact and shortStat or fullStat)
   b.rangeText:SetPoint("LEFT",b,"LEFT",4,-8); b.rangeText:SetPoint("RIGHT",b,"RIGHT",-4,-8); b.rangeText:SetHeight(12); b.rangeText:SetText(rangeFull); b.rangeText:SetTextColor(cell.range=="total" and 1 or .3,cell.range=="total" and .78 or .82,cell.range=="total" and .25 or 1,1); b.rangeText:Show()
  end
  b:Show()
  b:SetScript("OnMouseDown",function(_,button)
   if button~="LeftButton" or def.isPreset then return end
  s.dragSelect={cell={r0=boundCell.r0,c0=boundCell.c0,r1=boundCell.r1,c1=boundCell.c1}}
  s.board:SetScript("OnUpdate",s.board._dragOnUpdate)
   s.selection={r0=boundCell.r0,c0=boundCell.c0,r1=boundCell.r1,c1=boundCell.c1,
       anchorR=boundCell.r0,anchorC=boundCell.c0,valid=true}; s.error:SetText(""); self:DrawStudioBoard()
  end)
  b:SetScript("OnMouseUp",function(_,button) if button=="LeftButton" then self:UpdateStudioCellSelection(true) end end)
 end
 for i=#def.cells+1,#s.cellButtons do s.cellButtons[i]:Hide() end
 local n=0
 for c=1,def.cols-1 do n=n+1; local d=s.dividers[n] or self:CreateStudioDivider("col",n); s.dividers[n]=d; self:SetStudioDividerAxis(d,"col"); d.boundary=c; d:ClearAllPoints(); d:SetPoint("TOPLEFT",s.board,"TOPLEFT",xs[c]+ws[c]-4,0); d:SetSize(10,H); local active=s.ratioSelection and s.ratioSelection.axis=="col" and s.ratioSelection.boundary==c; d.line:SetColorTexture(0,active and .9 or .65,1,active and 1 or .55); d:SetShown(not def.isPreset) end
 for r=1,def.rows-1 do n=n+1; local d=s.dividers[n] or self:CreateStudioDivider("row",n); s.dividers[n]=d; self:SetStudioDividerAxis(d,"row"); d.boundary=r; d:ClearAllPoints(); d:SetPoint("TOPLEFT",s.board,"TOPLEFT",0,-(ys[r]+hs[r]-4)); d:SetSize(W,10); local active=s.ratioSelection and s.ratioSelection.axis=="row" and s.ratioSelection.boundary==r; d.line:SetColorTexture(0,active and .9 or .65,1,active and 1 or .55); d:SetShown(not def.isPreset) end
 for i=n+1,#s.dividers do s.dividers[i]:Hide() end
end

function Config:UpdateStudioCellSelection(forceFinish)
 local s=self._layoutStudio; local drag=s and s.dragSelect; if not drag then return end
 local def=self:GetStudioDef(); if not def or def.isPreset then s.dragSelect=nil; return end
 local scale=s.board:GetEffectiveScale(); local cursorX,cursorY=GetCursorPosition(); local x=cursorX/scale-(s.board:GetLeft() or 0); local y=(s.board:GetTop() or 0)-cursorY/scale
 if x>=0 and y>=0 and x<=s.board:GetWidth() and y<=s.board:GetHeight() then
  local function hitTrack(pos,total,ratios)
   local gap=2; local usable=total-gap*(#ratios-1); local edge=0
   for i,ratio in ipairs(ratios) do local size=usable*ratio; if pos<=edge+size+(i<#ratios and gap*.5 or 0) then return i end; edge=edge+size+gap end
   return #ratios
  end
  local row=hitTrack(y,s.board:GetHeight(),def.rowR); local col=hitTrack(x,s.board:GetWidth(),def.colR); local target=cellAt(def,row,col)
  if target then
   local start=drag.cell; local r0=math.min(start.r0,target.r0); local c0=math.min(start.c0,target.c0); local r1=math.max(start.r1,target.r1); local c1=math.max(start.c1,target.c1)
   local ok=ns.Layouts:SelectionValid(def,r0,c0,r1,c1); local old=s.selection
   if not old or old.r0~=r0 or old.c0~=c0 or old.r1~=r1 or old.c1~=c1 or old.valid~=ok then
    s.selection={r0=r0,c0=c0,r1=r1,c1=c1,anchorR=start.r0,anchorC=start.c0,valid=ok}
    s.error:SetText(ok and "" or L.PARTIAL_MERGE_ERROR); self:DrawStudioBoard()
   end
  end
 end
 if forceFinish or not IsMouseButtonDown("LeftButton") then s.dragSelect=nil; if not s.drag then s.board:SetScript("OnUpdate",nil) end; self:RefreshLayoutStudio() end
end

function Config:CreateStudioDivider(axis,index)
 local s=self._layoutStudio; local d=CreateFrame("Button",nil,s.board); d:SetFrameLevel(s.board:GetFrameLevel()+20); local line=d:CreateTexture(nil,"OVERLAY"); line:SetColorTexture(0,.75,1,.65); d.line=line; self:SetStudioDividerAxis(d,axis)
 d:SetScript("OnMouseDown",function(self2,button) if button~="LeftButton" then return end; local def=ns.Layouts:GetLayout(s.selectedId); if not def or def.isPreset then return end; local x,y=GetCursorPosition(); s.ratioSelection={axis=self2.axis,boundary=self2.boundary}; self:RefreshStudioRatioControl(def,false); s.drag={axis=self2.axis,boundary=self2.boundary,start=CopyTable(self2.axis=="col" and def.colR or def.rowR),preview=CopyTable(def),startX=x,startY=y,moved=false}; s.board:SetScript("OnUpdate",s.board._dragOnUpdate) end)
 return d
end

function Config:SetStudioDividerAxis(divider,axis)
 divider.axis=axis; local line=divider.line; line:ClearAllPoints()
 if axis=="col" then line:SetWidth(2); line:SetPoint("TOP"); line:SetPoint("BOTTOM")
 else line:SetHeight(2); line:SetPoint("LEFT"); line:SetPoint("RIGHT") end
end

function Config:RefreshStudioRatioControl(def,preset)
 local s=self._layoutStudio; local q=s.ratioSelection
 local boundary=tonumber(q and q.boundary); local valid=q and (q.axis=="col" or q.axis=="row") and boundary and boundary>=1 and boundary < (q.axis=="col" and def.cols or def.rows)
 if valid then q.boundary=boundary end
 if not preset and not valid then
  if def.cols>1 then q={axis="col",boundary=1} elseif def.rows>1 then q={axis="row",boundary=1} else q=nil end
  s.ratioSelection=q
 end
 local enabled=q and not preset
 for _,w in ipairs({s.ratioLabel,s.ratioSlider,s.ratioValue,s.equalize}) do w:SetShown(enabled and true or false) end
 if not enabled then s.ratioValue:SetText("-"); return end
 local values=q.axis=="col" and def.colR or def.rowR; local pair=values[q.boundary]+values[q.boundary+1]; local first=values[q.boundary]; local second=pair-first; local floor=math.min(q.axis=="col" and .08 or .06,pair*.45,first,second)
 s.ratioSlider:SetEnabled(true); s.ratioSlider:SetAlpha(1); s.equalize:SetEnabled(true); s.equalize:SetAlpha(1)
 s._settingSlider=true; s.ratioSlider:SetMinMaxValues(floor,pair-floor); s.ratioSlider:SetValue(first); s._settingSlider=false
 s.ratioValue:SetFormattedText(q.axis=="col" and L.RATIO_LR_FORMAT or L.RATIO_TB_FORMAT,first*100,(pair-first)*100)
end

function Config:BeginStudioSlider()
 local s=self._layoutStudio; local q=s.ratioSelection; local def=ns.Layouts:GetLayout(s.selectedId); if not q or not def or def.isPreset then return end; s.sliderBase=CopyTable(def); s.ratioPreview=CopyTable(def)
end

function Config:PreviewStudioSlider(v)
 local s=self._layoutStudio; if s._settingSlider then return end; local q=s.ratioSelection; if not q then return end
 if not s.ratioPreview then self:BeginStudioSlider() end; if not s.ratioPreview then return end
 local values=q.axis=="col" and s.ratioPreview.colR or s.ratioPreview.rowR; local base=q.axis=="col" and s.sliderBase.colR or s.sliderBase.rowR; local pair=base[q.boundary]+base[q.boundary+1]; values[q.boundary]=v; values[q.boundary+1]=pair-v; s.ratioValue:SetFormattedText(q.axis=="col" and L.RATIO_LR_FORMAT or L.RATIO_TB_FORMAT,v*100,(pair-v)*100); self:DrawStudioBoard()
 if not IsMouseButtonDown("LeftButton") then self:CommitStudioSlider() end
end

function Config:CommitStudioSlider()
 local s=self._layoutStudio; local q=s.ratioSelection; if not s.ratioPreview or not q then return end; local values=CopyTable(q.axis=="col" and s.ratioPreview.colR or s.ratioPreview.rowR); local axis=q.axis; s.ratioPreview=nil; s.sliderBase=nil
 if ns.Layouts:Commit(s.selectedId,function(d) if axis=="col" then d.colR=values else d.rowR=values end end) then self:StudioSaved() end; self:RefreshLayoutStudio()
end

function Config:EqualizeStudioBoundary()
 local s=self._layoutStudio; local q=s.ratioSelection; if not q then return end
 if ns.Layouts:Commit(s.selectedId,function(d) local values=q.axis=="col" and d.colR or d.rowR; local pair=values[q.boundary]+values[q.boundary+1]; values[q.boundary]=pair/2; values[q.boundary+1]=pair/2 end) then self:StudioSaved() end; self:RefreshLayoutStudio()
end

function Config:UpdateStudioRatioDrag()
 local s=self._layoutStudio; local drag=s and s.drag; if not drag then return end
 local rawX,rawY=GetCursorPosition(); if not drag.moved then local dx,dy=rawX-(drag.startX or rawX),rawY-(drag.startY or rawY); drag.moved=math.abs(drag.axis=="col" and dx or dy)>=3 end
  if not drag.moved then if not IsMouseButtonDown("LeftButton") then s.drag=nil; if not s.dragSelect then s.board:SetScript("OnUpdate",nil) end; self:RefreshLayoutStudio() end; return end
 local def=drag.preview; local scale=s.board:GetEffectiveScale(); local x,y=rawX/scale,rawY/scale
 local pos=drag.axis=="col" and (x-(s.board:GetLeft() or 0))/s.board:GetWidth() or ((s.board:GetTop() or 0)-y)/s.board:GetHeight(); pos=math.max(0,math.min(1,pos))
 local values=CopyTable(drag.start); local before=0; for i=1,drag.boundary-1 do before=before+values[i] end; local pair=values[drag.boundary]+values[drag.boundary+1]; local currentFirst,currentSecond=values[drag.boundary],values[drag.boundary+1]; local floor=math.min(drag.axis=="col" and .08 or .06,pair*.45,currentFirst,currentSecond); local a=math.max(floor,math.min(pair-floor,pos-before)); values[drag.boundary]=a; values[drag.boundary+1]=pair-a
 if drag.axis=="col" then def.colR=values else def.rowR=values end; self:DrawStudioBoard()
 if not IsMouseButtonDown("LeftButton") then
   local final=values; local axis=drag.axis; s.drag=nil; if not s.dragSelect then s.board:SetScript("OnUpdate",nil) end; local ok=ns.Layouts:Commit(s.selectedId,function(d) if axis=="col" then d.colR=final else d.rowR=final end end); if ok then self:StudioSaved() end; self:RefreshLayoutStudio()
 end
end

function Config:StudioTrack(axis,add)
 local s=self._layoutStudio; local ok,why
 if add then ok,why=ns.Layouts:AddTrack(s.selectedId,axis) else ok,why=ns.Layouts:RemoveTrack(s.selectedId,axis) end
 if ok then s.selection=nil; s.ratioSelection=nil; s.error:SetText(""); self:StudioSaved() else s.error:SetText(why=="merged" and L.SPLIT_BEFORE_REMOVE or L.LAYOUT_LIMIT) end; self:RefreshLayoutStudio()
end

function Config:StudioMerge()
 local s=self._layoutStudio; local q=s.selection; if not q or not q.valid or (q.r0==q.r1 and q.c0==q.c1) then s.error:SetText(L.SELECT_RECTANGLE); return end
 local ok=ns.Layouts:Merge(s.selectedId,q.r0,q.c0,q.r1,q.c1,q.anchorR,q.anchorC); if ok then s.selection={r0=q.r0,c0=q.c0,r1=q.r1,c1=q.c1,anchorR=q.anchorR,anchorC=q.anchorC,valid=true}; s.error:SetText(""); self:StudioSaved() end; self:RefreshLayoutStudio()
end

function Config:StudioSplit()
 local s=self._layoutStudio; local q=s.selection; if not q then return end; local def=ns.Layouts:GetLayout(s.selectedId); local cell=cellAt(def,q.r0,q.c0); if ns.Layouts:Split(s.selectedId,cell) then s.selection={r0=q.r0,c0=q.c0,r1=q.r0,c1=q.c0,valid=true}; self:StudioSaved() end; self:RefreshLayoutStudio()
end

function Config:CycleStudioCellStat()
 local s=self._layoutStudio; local q=s.selection; local def=ns.Layouts:GetLayout(s.selectedId); local cell=self:GetStudioSelectedCell(def); if not cell then return end; local idx=1; for i,v in ipairs(ns.Layouts.STATS) do if v==cell.stat then idx=i end end; local nextStat=ns.Layouts.STATS[idx%#ns.Layouts.STATS+1]
 if ns.Layouts:Commit(s.selectedId,function(d) ns.Layouts:FindCell(d,q.r0,q.c0).stat=nextStat end) then self:StudioSaved() end; self:RefreshLayoutStudio()
end

function Config:CycleStudioCellRange()
 local s=self._layoutStudio; local q=s.selection; local def=ns.Layouts:GetLayout(s.selectedId); if not self:GetStudioSelectedCell(def) then return end; if ns.Layouts:Commit(s.selectedId,function(d) local c=ns.Layouts:FindCell(d,q.r0,q.c0); c.range=c.range=="total" and "follow" or "total" end) then self:StudioSaved() end; self:RefreshLayoutStudio()
end

function Config:ShowStudioMenu(anchor,options,onSelect)
 local s=self._layoutStudio; if not s.choiceMenu then
  local m=CreateFrame("Frame",nil,self.panel,"BackdropTemplate"); m:SetFrameStrata("TOOLTIP"); m:SetFrameLevel(900); m:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); m:SetBackdropColor(.045,.045,.06,1); self:CreateBorder(m,.2,.45,.7,1); m.items={}; m:EnableMouseWheel(true); m:SetScript("OnMouseWheel",function(_,delta) m._offset=math.max(0,math.min(math.max(0,#(m._options or {})-14),(m._offset or 0)-delta)); self:RefreshStudioMenu() end); s.choiceMenu=m
 end
 local m=s.choiceMenu; m._onSelect=onSelect; m._options=options; m._offset=0; m:ClearAllPoints(); m:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-3); m:SetWidth(math.max(130,anchor:GetWidth())); m:SetHeight(math.min(#options,14)*22+4); self:RefreshStudioMenu(); m:Show()
end

function Config:RefreshStudioMenu()
 local m=self._layoutStudio and self._layoutStudio.choiceMenu; if not m then return end; local options=m._options or {}; local count=math.min(#options,14)
 for i=1,count do local opt=options[i+(m._offset or 0)]; local b=m.items[i]; if not b then b=btn(self,m,126,20,"",function(selfBtn) local item=selfBtn._opt; local cb=m._onSelect; m:Hide(); if item and cb then cb(item.v) end end); b:SetPoint("TOPLEFT",2,-2-(i-1)*22); b:SetPoint("TOPRIGHT",-2,-2-(i-1)*22); m.items[i]=b end; b._opt=opt; b.text:SetText(opt.l); b:Show() end
 for i=count+1,#m.items do m.items[i]:Hide() end
end

function Config:ShowStudioStatMenu()
 local s=self._layoutStudio; local def=ns.Layouts:GetLayout(s.selectedId); if not self:GetStudioSelectedCell(def) then return end; local opts={}; for _,stat in ipairs(ns.Layouts.STATS) do opts[#opts+1]={l=L[STAT_KEYS[stat]],v=stat} end
 self:ShowStudioMenu(s.stat,opts,function(value) local q=s.selection; if ns.Layouts:Commit(s.selectedId,function(d) ns.Layouts:FindCell(d,q.r0,q.c0).stat=value end) then self:StudioSaved() end; self:RefreshLayoutStudio() end)
end

function Config:ShowStudioRangeMenu()
 local s=self._layoutStudio; local def=ns.Layouts:GetLayout(s.selectedId); if not self:GetStudioSelectedCell(def) then return end
 self:ShowStudioMenu(s.range,{{l=L.LAYOUT_RANGE_CURRENT,v="follow"},{l=L.LAYOUT_RANGE_TOTAL,v="total"}},function(value) local q=s.selection; if ns.Layouts:Commit(s.selectedId,function(d) ns.Layouts:FindCell(d,q.r0,q.c0).range=value end) then self:StudioSaved() end; self:RefreshLayoutStudio() end)
end

function Config:ShowSceneLayoutMenu(scene,anchor)
 local opts={}; for _,d in ipairs(ns.Layouts:ListLayouts()) do opts[#opts+1]={l=ns.Layouts:GetLayoutName(d),v=d.id} end
 self:ShowStudioMenu(anchor,opts,function(id) ns.Layouts:Assign(scene,id); self:StudioSaved(); self:RefreshLayoutStudio() end)
end

function Config:ShowLayoutDeleteConfirm()
 local s=self._layoutStudio; local def=ns.Layouts:GetLayout(s.selectedId); if not def or def.isPreset then return end; local refs=ns.Layouts:GetReferencingScenes(def.id); local names={}; for _,scene in ipairs(refs) do names[#names+1]=L[SCENE_KEYS[scene]] end
 s.confirm._id=def.id; s.confirmText:SetText(string.format(L.DELETE_LAYOUT_CONFIRM,ns.Layouts:GetLayoutName(def),#names>0 and table.concat(names,", ") or L.NONE)); s.confirm:Show()
end

function Config:CycleSceneLayout(scene,direction)
 local list=ns.Layouts:ListLayouts(); local ws=ns.Layouts:GetWorkspace(scene); local idx=1; for i,d in ipairs(list) do if d.id==ws.layoutId then idx=i end end; idx=((idx-1+(direction or 1))%#list)+1; ns.Layouts:Assign(scene,list[idx].id); self:StudioSaved(); self:RefreshLayoutStudio()
end

-- Data page: the full-run and trash-cleanup switches are intentionally
-- independent. Outdoor has no full-run switch in 2.0.
function Config:BuildDataPage()
 local inner=self.pages.data.inner; local y=0
 y=self:H(inner,L.CONFIG_DATA_DISPLAY_FORMAT,y)
 y=self:Check(inner,L.CONFIG_SHOW_TOTAL_DAMAGE_AND_DPS,y,function() return ns.db.display.showPerSecond end,function(v) ns.db.display.showPerSecond=v; self:RefreshUI() end)
 y=self:Check(inner,L.CONFIG_SHOW_CONTRIBUTION_PERCENT_OUT_OF_COMBAT,y,function() return ns.db.display.showPercent end,function(v) ns.db.display.showPercent=v; self:RefreshUI() end)
 y=self:Check(inner,L.CONFIG_SHOW_RANK_NUM,y,function() return ns.db.display.showRank end,function(v) ns.db.display.showRank=v; self:RefreshUI() end)
 y=self:Check(inner,L.CONFIG_SPEC_ICON_ON_LEFT,y,function() return ns.db.display.showSpecIcon end,function(v) ns.db.display.showSpecIcon=v; self:RefreshUI() end)
 y=self:Check(inner,L.CONFIG_SHOW_PLAYER_REALM,y,function() return ns.db.display.showRealm end,function(v) ns.db.display.showRealm=v; self:RefreshUI() end)
 y=self:Check(inner,L.CONFIG_ALWAYS_SHOW_SELF_IN_RANKING,y,function() return ns.db.display.alwaysShowSelf end,function(v) ns.db.display.alwaysShowSelf=v; self:RefreshUI() end)
 y=y-10
 local bottomBarSection=CreateFrame("Frame",nil,inner); bottomBarSection:SetWidth(inner:GetWidth())
 bottomBarSection:SetPoint("TOPLEFT",inner,"TOPLEFT",0,y)
 local bottomBarY=self:BuildBottomBarSettings(bottomBarSection)
 bottomBarSection:SetHeight(math.abs(bottomBarY)+8)
 y=y-bottomBarSection:GetHeight()-10
 y=self:H(inner,L.FULL_RUN_SETTINGS,y); y=self:Desc(inner,y,L.FULL_RUN_DESC)
 y=self:Check(inner,L.GENERATE_OVERALL_SEGMENT_AFTER_LEAVING_INSTANCE,y,function() return ns.db.mythicPlus.enabled end,function(v) ns.db.mythicPlus.enabled=v end)
 local fullRunScenes={"mplus","raid","dungeon","arena","battleground"}
 local fullRunSub=CreateFrame("Frame",nil,inner); fullRunSub:SetWidth(inner:GetWidth()-16); fullRunSub:SetPoint("TOPLEFT",inner,"TOPLEFT",16,y); local sy=0
 for _,scene in ipairs(fullRunScenes) do local sceneId=scene; sy=self:Check(fullRunSub,L[SCENE_KEYS[sceneId]],sy,function() return ns.db.fullRunSettings[sceneId] end,function(v) ns.db.fullRunSettings[sceneId]=v end) end
 fullRunSub:SetHeight(math.abs(sy)); y=y-math.abs(sy)
 y=y-8; y=self:H(inner,L.CLEAN_TRASH_SETTINGS,y)
 y=self:Check(inner,L.CONFIG_AUTO_DELETE_TRASH_SEGMENTS_AFTER_LEAVING_INSTANCE,y,function() return ns.db.mythicPlus.autoCleanTrash end,function(v) ns.db.mythicPlus.autoCleanTrash=v end)
 local cleanSub=CreateFrame("Frame",nil,inner); cleanSub:SetWidth(inner:GetWidth()-16); cleanSub:SetPoint("TOPLEFT",inner,"TOPLEFT",16,y); sy=0
 local trashScenes={"mplus","raid","dungeon"}
 for _,scene in ipairs(trashScenes) do local sceneId=scene; sy=self:Check(cleanSub,L[SCENE_KEYS[sceneId]],sy,function() return ns.db.cleanTrashSettings[sceneId] end,function(v) ns.db.cleanTrashSettings[sceneId]=v end) end
 cleanSub:SetHeight(math.abs(sy)); y=y-math.abs(sy)
 y=y-8; y=self:H(inner,L.DATA_TRACKING,y)
y=self:Slider(inner,L.MAX_HISTORY_SEGMENTS,y,5,100,1,
    function()
        return ns.db.tracking.historyDisplayLimit or ns.db.tracking.maxSegments or 20
    end,
    function(v)
        ns.db.tracking.historyDisplayLimit = v
        ns.db.tracking.maxSegments = v
        if ns.Segments then
            ns.Segments:SetViewSegment(ns.Segments.viewIndex)
        end
    end)
 inner:SetHeight(math.abs(y)+30)
end

function Config:RebuildBehaviorPage()
 local inner=self.pages and self.pages.perf and self.pages.perf.inner; if not inner then return end
 for _,child in ipairs({inner:GetChildren()}) do child:Hide(); child:SetParent(nil) end
 for _,region in ipairs({inner:GetRegions()}) do region:Hide() end
 local y=0
 local function RefreshFade() if ns.UI then ns.UI:UpdateFadeHoverDriver(); ns.UI:CheckAutoFade(true) end end
 local function RefreshCollapse() if ns.UI then ns.UI:CheckAutoCollapse() end end

 y=self:H(inner,L.CONFIG_COLLAPSE,y)
 y=self:Check(inner,L.CONFIG_AUTO_COLLAPSE_OUT_OF_COMBAT,y,function() return ns.db.collapse.autoCollapse end,function(v) ns.db.collapse.autoCollapse=v; RefreshCollapse() end)
 y=self:Check(inner,L.CONFIG_NEVER_AUTO_COLLAPSE_IN_INSTANCES,y,function() return ns.db.collapse.neverInInstance end,function(v) ns.db.collapse.neverInInstance=v; RefreshCollapse() end)
 y=self:Slider(inner,L.CONFIG_AUTO_COLLAPSE_DELAY_SECONDS,y,0,10,.5,function() return ns.db.collapse.delay or 1.5 end,function(v) ns.db.collapse.delay=v end)
 y=self:Check(inner,L.CONFIG_ENABLE_COLLAPSE_ANIMATION,y,function() return ns.db.collapse.enableAnim end,function(v) ns.db.collapse.enableAnim=v end)
 y=self:Slider(inner,L.CONFIG_ANIMATION_DURATION,y,.1,2,.1,function() return ns.db.collapse.animDuration or .4 end,function(v) ns.db.collapse.animDuration=v end)

 y=y-10; y=self:H(inner,L.CONFIG_AUTO_HIDE,y)
 y=self:Check(inner,L.CONFIG_UNHIDE_ON_MOUSE_HOVER,y,function() return ns.db.fade.unfadeOnHover end,function(v) ns.db.fade.unfadeOnHover=v; RefreshFade() end)
 y=self:Slider(inner,L.CONFIG_AUTO_HIDE_DELAY_SECONDS,y,0,10,.5,function() return ns.db.fade.delay or 1.5 end,function(v) ns.db.fade.delay=v; RefreshFade() end)
 y=self:Check(inner,L.CONFIG_TITLE_AND_TAB_BAR,y,function() return ns.db.fade.fadeBars end,function(v) ns.db.fade.fadeBars=v; RefreshFade() end)
 local sub=CreateFrame("Frame",nil,inner); sub:SetWidth(inner:GetWidth()-16); sub:SetPoint("TOPLEFT",inner,"TOPLEFT",16,y); local sy=0
 local whenOpts={{l=L.ALWAYS,v="always"},{l=L.OUT_OF_COMBAT,v="ooc"}}
 sy=self:Dropdown(sub,L.CONFIG_HIDE_TITLE_TAB_WHEN,sy,whenOpts,function() return ns.db.fade.barsWhen or "ooc" end,function(v) ns.db.fade.barsWhen=v; RefreshFade() end)
 sy=self:Check(sub,L.CONFIG_NEVER_HIDE_TITLE_TAB_IN_INSTANCES,sy,function() return ns.db.fade.barsNeverInInstance end,function(v) ns.db.fade.barsNeverInInstance=v; RefreshFade() end)
 sy=self:Slider(sub,L.CONFIG_TITLE_TAB_HIDDEN_ALPHA,sy,0,1,.05,function() return ns.db.fade.barsAlpha or .3 end,function(v) ns.db.fade.barsAlpha=v; RefreshFade() end,true)
 sub:SetHeight(math.abs(sy)); y=y-math.abs(sy)
 y=self:Check(inner,L.DATA_AREA,y,function() return ns.db.fade.fadeBody end,function(v) ns.db.fade.fadeBody=v; RefreshFade() end)
 sub=CreateFrame("Frame",nil,inner); sub:SetWidth(inner:GetWidth()-16); sub:SetPoint("TOPLEFT",inner,"TOPLEFT",16,y); sy=0
 sy=self:Dropdown(sub,L.CONFIG_HIDE_DATA_AREA_WHEN,sy,whenOpts,function() return ns.db.fade.bodyWhen or "ooc" end,function(v) ns.db.fade.bodyWhen=v; RefreshFade() end)
 sy=self:Check(sub,L.CONFIG_NEVER_HIDE_DATA_AREA_IN_INSTANCES,sy,function() return ns.db.fade.bodyNeverInInstance end,function(v) ns.db.fade.bodyNeverInInstance=v; RefreshFade() end)
 sy=self:Slider(sub,L.CONFIG_DATA_AREA_HIDDEN_ALPHA,sy,0,1,.05,function() return ns.db.fade.bodyAlpha or .15 end,function(v) ns.db.fade.bodyAlpha=v; RefreshFade() end,true)
 sub:SetHeight(math.abs(sy)); y=y-math.abs(sy)
 y=self:Check(inner,L.CONFIG_ENABLE_HIDE_ANIMATION,y,function() return ns.db.fade.enableAnim end,function(v) ns.db.fade.enableAnim=v end)
 y=self:Slider(inner,L.CONFIG_HIDE_ANIMATION_DURATION,y,.1,2,.1,function() return ns.db.fade.animDuration or .5 end,function(v) ns.db.fade.animDuration=v end)

 y=y-10; y=self:H(inner,L.CONFIG_SMART_REFRESH,y)
 y=self:Slider(inner,L.CONFIG_COMBAT_REFRESH_SECONDS,y,.1,1,.1,function() return ns.db.smartRefresh.combatInterval end,function(v) ns.db.smartRefresh.combatInterval=v end)
 y=self:Slider(inner,L.CONFIG_OUT_OF_COMBAT_REFRESH_SECONDS,y,.5,5,.5,function() return ns.db.smartRefresh.idleInterval end,function(v) ns.db.smartRefresh.idleInterval=v end)
 inner:SetHeight(math.abs(y)+30)
 self:UpdatePageScroll("perf")
end

function Config:BuildPerfPage()
 self:RebuildBehaviorPage()
end
