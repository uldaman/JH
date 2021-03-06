-- @Author: Webster
-- @Date:   2015-01-21 15:21:19
-- @Last Modified by:   Administrator
-- @Last Modified time: 2016-12-14 21:45:47
local _L = JH.LoadLangPack
-----------------------------------------------
-- 重构 @ 2015 赶时间 很多东西写的很粗略
-----------------------------------------------
-- global cache
local pairs, ipairs = pairs, ipairs
local type, unpack = type, unpack
local floor, mmax = math.floor, math.max
local setmetatable = setmetatable
local GetDistance, GetBuff, GetEndTime, GetTarget = JH.GetDistance, JH.GetBuff, JH.GetEndTime, JH.GetTarget
local GetClientPlayer, GetClientTeam, GetPlayer = GetClientPlayer, GetClientTeam, GetPlayer
local Station, SetTarget, Target_GetTargetData = Station, SetTarget, Target_GetTargetData
local Table_BuffIsVisible = Table_BuffIsVisible
local CFG                    = Cataclysm_Main
-- global STR cache
local COINSHOP_SOURCE_NULL   = g_tStrings.COINSHOP_SOURCE_NULL
local STR_FRIEND_NOT_ON_LINE = g_tStrings.STR_FRIEND_NOT_ON_LINE
local FIGHT_DEATH            = g_tStrings.FIGHT_DEATH
local CAMP_GOOD              = CAMP.GOOD
local CAMP_EVIL              = CAMP.EVIL
-- STATE cache
local MOVE_STATE_ON_STAND    = MOVE_STATE.ON_STAND
local MOVE_STATE_ON_DEATH    = MOVE_STATE.ON_DEATH
-- local value
local CTM_ALPHA_STEP         = 15    -- 240 / CTM_ALPHA_STEP
local CTM_BOX_HEIGHT         = 42    -- 注意::受限ini 这里只是作用于动态修改
local CTM_GROUP_COUNT        = 5 - 1 -- 防止以后开个什么40人本 估计不太可能 就和剑三这还得好几年
local CTM_MEMBER_COUNT       = 5
local CTM_DRAG               = false
local CTM_INIFILE            = JH.GetAddonInfo().szRootPath .. "JH_Cataclysm/ui/Cataclysm_Party.ini"
local CTM_DRAG_ID
local CTM_TARGET
local CTM_TTARGET
local CTM_CACHE              = setmetatable({}, { __mode = "v" })
local CTM_LIFE_CACHE         = {}
local CTM_BUFF_CACHE         = {}
local CTM_BORDER_FRAME       = Random(4)
-- Package func
local HIDE_FORCE = {
	[7]  = true,
	[8]  = true,
	[10] = true,
	[21] = true,
}
local KUNGFU_TYPE = {
	TIAN_CE   = 1,      -- 天策内功
	WAN_HUA   = 2,      -- 万花内功
	CHUN_YANG = 3,      -- 纯阳内功
	QI_XIU    = 4,      -- 七秀内功
	SHAO_LIN  = 5,      -- 少林内功
	CANG_JIAN = 6,      -- 藏剑内功
	GAI_BANG  = 7,      -- 丐帮内功
	MING_JIAO = 8,      -- 明教内功
	WU_DU     = 9,      -- 五毒内功
	TANG_MEN  = 10,     -- 唐门内功
	CANG_YUN  = 18,     -- 苍云内功
}
local function IsPlayerManaHide(dwForceID, dwMountType)
	if dwMountType then
		if dwMountType == KUNGFU_TYPE.CANG_JIAN or           --藏剑
			dwMountType == KUNGFU_TYPE.TANG_MEN or           --唐门
			dwMountType == KUNGFU_TYPE.MING_JIAO or          --明教
			dwMountType == KUNGFU_TYPE.CANG_YUN then         --苍云
			return true
		else
			return false
		end
	else
		return HIDE_FORCE[dwForceID]
	end
end

local function OpenRaidDragPanel(dwMemberID)
	local hTeam = GetClientTeam()
	local tMemberInfo = hTeam.GetMemberInfo(dwMemberID)
	if not tMemberInfo then
		return
	end
	local hFrame = Wnd.OpenWindow("RaidDragPanel")

	local nX, nY = Cursor.GetPos()
	hFrame:SetAbsPos(nX, nY)
	hFrame:StartMoving()

	hFrame.dwID = dwMemberID
	local hMember = hFrame:Lookup("", "")

	local szPath, nFrame = GetForceImage(tMemberInfo.dwForceID)
	hMember:Lookup("Image_Force"):FromUITex(szPath, nFrame)

	local hTextName = hMember:Lookup("Text_Name")
	hTextName:SetText(tMemberInfo.szName)

	local hImageLife = hMember:Lookup("Image_Health")
	local hImageMana = hMember:Lookup("Image_Mana")
	if tMemberInfo.bIsOnLine then
		if tMemberInfo.nMaxLife > 0 then
			hImageLife:SetPercentage(tMemberInfo.nCurrentLife / tMemberInfo.nMaxLife)
		end
		if tMemberInfo.nMaxMana > 0 and tMemberInfo.nMaxMana ~= 1 then
			hImageMana:SetPercentage(tMemberInfo.nCurrentMana / tMemberInfo.nMaxMana)
		end
	else
		hImageLife:SetPercentage(0)
		hImageMana:SetPercentage(0)
	end
	hMember:Show()
	hFrame:BringToTop()
	hFrame:Scale(CFG.fScaleX, CFG.fScaleY)
end

local function CloseRaidDragPanel()
	local hFrame = Station.Lookup("Normal/RaidDragPanel")
	if hFrame then
		hFrame:EndMoving()
		Wnd.CloseWindow(hFrame)
	end
end
-- OutputTeamMemberTip 系统的API不好用所以这是改善版
local function OutputTeamMemberTip(dwID, rc)
	local team = GetClientTeam()
	local tMemberInfo = team.GetMemberInfo(dwID)
	if not tMemberInfo then
		return
	end
	local r, g, b = JH.GetForceColor(tMemberInfo.dwForceID)
	local szPath, nFrame = GetForceImage(tMemberInfo.dwForceID)
	local xml = {}
	table.insert(xml, GetFormatImage(szPath, nFrame, 22, 22))
	table.insert(xml, GetFormatText(FormatString(g_tStrings.STR_NAME_PLAYER, tMemberInfo.szName), 80, r, g, b))
	if tMemberInfo.bIsOnLine then
		local p = GetPlayer(dwID)
		if p and p.dwTongID > 0 then
			if GetTongClient().ApplyGetTongName(p.dwTongID) then
				table.insert(xml, GetFormatText("[" .. GetTongClient().ApplyGetTongName(p.dwTongID) .. "]\n", 41))
			end
		end
		table.insert(xml, GetFormatText(FormatString(g_tStrings.STR_PLAYER_H_WHAT_LEVEL, tMemberInfo.nLevel), 82))
		table.insert(xml, GetFormatText(JH.GetSkillName(tMemberInfo.dwMountKungfuID, 1) .. "\n", 82))
		local szMapName = Table_GetMapName(tMemberInfo.dwMapID)
		if szMapName then
			table.insert(xml, GetFormatText(szMapName .. "\n", 82))
		end
		local nCamp = tMemberInfo.nCamp
		table.insert(xml, GetFormatText(g_tStrings.STR_GUILD_CAMP_NAME[nCamp] .. "\n", 82))
	else
		table.insert(xml, GetFormatText(g_tStrings.STR_FRIEND_NOT_ON_LINE .. "\n", 82, 128, 128, 128))
	end
	if IsCtrlKeyDown() then
		table.insert(xml, GetFormatText(FormatString(g_tStrings.TIP_PLAYER_ID, dwID), 102))
	end
	OutputTip(table.concat(xml), 345, rc)
end

local function InsertChangeGroupMenu(tMenu, dwMemberID)
	local hTeam = GetClientTeam()
	local tSubMenu = { szOption = g_tStrings.STR_RAID_MENU_CHANG_GROUP }

	local nCurGroupID = hTeam.GetMemberGroupIndex(dwMemberID)
	for i = 0, hTeam.nGroupNum - 1 do
		if i ~= nCurGroupID then
			local tGroupInfo = hTeam.GetGroupInfo(i)
			if tGroupInfo and tGroupInfo.MemberList then
				local tSubSubMenu =
				{
					szOption = g_tStrings.STR_NUMBER[i + 1],
					bDisable = (#tGroupInfo.MemberList >= CTM_MEMBER_COUNT),
					fnAction = function() GetClientTeam().ChangeMemberGroup(dwMemberID, i, 0) end,
					fnAutoClose = function() return true end,
				}
				table.insert(tSubMenu, tSubSubMenu)
			end
		end
	end
	if #tSubMenu > 0 then
		table.insert(tMenu, tSubMenu)
	end
end

local CTM_FORCE_COLOR = {
	-- [0] =  { 255, 255, 255 },
	[1] =  { 255, 255, 170 },
	[2] =  { 175, 25 , 255 },
	[3] =  { 250, 75 , 100 },
	[4] =  { 148, 178, 255 },
	[5] =  { 255, 125, 255 },
	[6] =  { 140, 80 , 255 },
	[7] =  { 0  , 128, 192 },
	[8] =  { 255, 200, 0   },
	[9] =  { 185, 125, 60  },
	[10] = { 240, 50 , 200 },
	-- [21] = { 180, 60 , 0   },
}
setmetatable(CTM_FORCE_COLOR, { __index = JH_FORCE_COLOR, __metatable = true })
local function GetForceColor(dwForceID) --获得成员颜色
	return unpack(CTM_FORCE_COLOR[dwForceID])
end

-- 有各个版本之间的文本差异，所以做到翻译中
local CTM_KUNGFU_TEXT = {
	[10080] = _L["KUNGFU_10080"], -- "云",
	[10081] = _L["KUNGFU_10081"], -- "冰",
	[10021] = _L["KUNGFU_10021"], -- "花",
	[10028] = _L["KUNGFU_10028"], -- "离",
	[10026] = _L["KUNGFU_10026"], -- "傲",
	[10062] = _L["KUNGFU_10062"], -- "铁",
	[10002] = _L["KUNGFU_10002"], -- "洗",
	[10003] = _L["KUNGFU_10003"], -- "易",
	[10014] = _L["KUNGFU_10014"], -- "气",
	[10015] = _L["KUNGFU_10015"], -- "剑",
	[10144] = _L["KUNGFU_10144"], -- "问",
	[10145] = _L["KUNGFU_10145"], -- "山",
	[10175] = _L["KUNGFU_10175"], -- "毒",
	[10176] = _L["KUNGFU_10176"], -- "补",
	[10224] = _L["KUNGFU_10224"], -- "羽",
	[10225] = _L["KUNGFU_10225"], -- "诡",
	[10242] = _L["KUNGFU_10242"], -- "焚",
	[10243] = _L["KUNGFU_10243"], -- "尊",
	[10268] = _L["KUNGFU_10268"], -- "丐",
	[10390] = _L["KUNGFU_10390"], -- "分",
	[10389] = _L["KUNGFU_10389"], -- "衣",
	[10448] = _L["KUNGFU_10448"], -- "相",
	[10447] = _L["KUNGFU_10447"], -- "莫",
	[10464] = _L["KUNGFU_10464"], -- "刀",
}
setmetatable(CTM_KUNGFU_TEXT, { __index = function() return _L["KUNGFU_0"] end, __metatable = true })

-- CODE --
local CTM = {}

CTM_Party_Base = class()

function CTM_Party_Base.OnFrameCreate()
	this:Lookup("", "Handle_BG/Shadow_BG"):SetAlpha(CFG.nAlpha)
	this:RegisterEvent("CTM_SET_ALPHA")
end

function CTM_Party_Base.OnEvent(szEvent)
	if szEvent == "CTM_SET_ALPHA" then
		this:Lookup("", "Handle_BG/Shadow_BG"):SetAlpha(CFG.nAlpha)
	end
end

function CTM_Party_Base.OnLButtonDown()
	CTM:BringToTop()
end

function CTM_Party_Base.OnRButtonDown()
	CTM:BringToTop()
end

function CTM_Party_Base.OnItemLButtonDrag()
	if not this.dwID then return end
	local team = GetClientTeam()
	local me = GetClientPlayer()
	if (IsAltKeyDown() or CFG.bEditMode) and me.IsInRaid() and JH.IsLeader() then
		CTM_DRAG = true
		CTM_DRAG_ID = this.dwID
		CTM:DrawAllParty()
		CTM:AutoLinkAllPanel()
		CTM:BringToTop()
		OpenRaidDragPanel(this.dwID)
	end
end

-- DragEnd bug fix
function CTM_Party_Base.OnItemLButtonUp()
	JH.DelayCall(function()
		if CTM_DRAG then
			CTM_DRAG, CTM_DRAG_ID = false, nil
			CTM:CloseParty()
			CTM:ReloadParty()
			CloseRaidDragPanel()
		end
	end, 50)
end

function CTM_Party_Base.OnItemLButtonDragEnd()
	if CTM_DRAG and this.dwID ~= CTM_DRAG_ID then
		local team = GetClientTeam()
		team.ChangeMemberGroup(CTM_DRAG_ID, this.nGroup, this.dwID or 0)
		CTM_DRAG, CTM_DRAG_ID = false, nil
		CloseRaidDragPanel()
		CTM:CloseParty()
		CTM:ReloadParty()
	end
end

function CTM_Party_Base.OnItemLButtonDown()
	if not this.dwID then return end
	local info = CTM:GetMemberInfo(this.dwID)
	if IsCtrlKeyDown() then
		EditBox_AppendLinkPlayer(info.szName)
	elseif info.bIsOnLine and GetPlayer(this.dwID) then -- 有待考证
		SetTarget(TARGET.PLAYER, this.dwID)
		FireUIEvent("JH_TAR_TEMP_UPDATE", this.dwID)
	end
end

function CTM_Party_Base.OnItemMouseEnter()
	if CTM_DRAG then
		this:Lookup("Image_Selected"):Show()
	end
	if not this.dwID then return end
	local nX, nY = this:GetRoot():GetAbsPos()
	local nW, nH = this:GetRoot():GetSize()
	local me = GetClientPlayer()
	if CFG.bTempTargetFightTip and not me.bFightState or not CFG.bTempTargetFightTip then
		OutputTeamMemberTip(this.dwID, { nX, nY + 5, nW, nH })
	end
	local info = CTM:GetMemberInfo(this.dwID)
	if info.bIsOnLine and GetPlayer(this.dwID) and CFG.bTempTargetEnable then
		JH.SetTempTarget(this.dwID, true)
	end
end

function CTM_Party_Base.OnItemMouseLeave()
	if CTM_DRAG and this:Lookup("Image_Selected") and this:Lookup("Image_Selected"):IsValid() then
		this:Lookup("Image_Selected"):Hide()
	end
	HideTip()
	if not this.dwID then return end
	local info = CTM:GetMemberInfo(this.dwID)
	if not info then return end -- 退租的问题
	if info.bIsOnLine and GetPlayer(this.dwID) and CFG.bTempTargetEnable then
		JH.SetTempTarget(this.dwID, false)
	end
end

function CTM_Party_Base.OnItemRButtonClick()
	if not this.dwID then return end
	local dwID = this.dwID
	local menu = {}
	local me = GetClientPlayer()
	local info = CTM:GetMemberInfo(dwID)
	local szPath, nFrame = GetForceImage(info.dwForceID)
	table.insert(menu, {
		szOption = info.szName,
		szLayer = "ICON_RIGHT",
		rgb = { JH.GetForceColor(info.dwForceID) },
		szIcon = szPath,
		nFrame = nFrame
	})
	if JH.IsLeader() and me.IsInRaid() then
		table.insert(menu, { bDevide = true })
		InsertChangeGroupMenu(menu, dwID)
	end
	local info = CTM:GetMemberInfo(dwID)
	if dwID ~= me.dwID then
		if JH.IsLeader() then
			table.insert(menu, { bDevide = true })
		end
		InsertTeammateMenu(menu, dwID)
		local t = {}
		InsertTargetMenu(t, dwID)
		for _, v in ipairs(t) do
			if v.szOption == g_tStrings.LOOKUP_INFO then
				for _, vv in ipairs(v) do
					if vv.szOption == g_tStrings.LOOKUP_NEW_TANLENT then
						table.insert(menu, vv)
						break
					end
				end
				break
			end
		end
		table.insert(menu, { szOption = g_tStrings.STR_LOOKUP, bDisable = not info.bIsOnLine, fnAction = function()
			ViewInviteToPlayer(dwID)
		end })
		if ViewCharInfoToPlayer then
			table.insert(menu, {
				szOption = g_tStrings.STR_LOOK .. g_tStrings.STR_EQUIP_ATTR, bDisable = not info.bIsOnLine, fnAction = function()
					ViewCharInfoToPlayer(dwID)
				end
			})
		end
	else
		table.insert(menu, { bDevide = true })
		InsertPlayerMenu(menu, dwID)
		if JH.IsLeader() or JH.bDebugClient then
			table.insert(menu, { bDevide = true })
			table.insert(menu, { szOption = _L["take back all permissions"], rgb = { 255, 255, 0 }, fnAction = function()
				if JH.IsLeader() then
					local team = GetClientTeam()
					team.SetAuthorityInfo(TEAM_AUTHORITY_TYPE.MARK, UI_GetClientPlayerID())
					team.SetAuthorityInfo(TEAM_AUTHORITY_TYPE.DISTRIBUTE, UI_GetClientPlayerID())
				else
					JH.BgTalk(PLAYER_TALK_CHANNEL.RAID, "JH_ABOUT", "TeamAuth")
				end
			end	})
		end
	end
	if #menu > 0 then
		PopupMenu(menu)
	end
end

function CTM:GetPartyFrame(nIndex) -- 获得组队面板
	return Station.Lookup("Normal/Cataclysm_Party_" .. nIndex)
end

function CTM:BringToTop()
	Cataclysm_Main.GetFrame():BringToTop()
	for i = 0, CTM_GROUP_COUNT do
		if self:GetPartyFrame(i) then
			self:GetPartyFrame(i):BringToTop()
		end
	end
end

function CTM:GetMemberHandle(nGroup, nIndex)
	local frame = self:GetPartyFrame(nGroup)
	if frame then
		return frame:Lookup("", "Handle_Roles"):Lookup(nIndex)
	end
end

-- 创建面板
function CTM:CreatePanel(nIndex)
	local me = GetClientPlayer()
	local frame = self:GetPartyFrame(nIndex)
	if not frame then
		frame = Wnd.OpenWindow(CTM_INIFILE, "Cataclysm_Party_" .. nIndex)
		frame:Scale(CFG.fScaleX, CFG.fScaleY)
	end
	self:AutoLinkAllPanel()
	self:RefreshGroupText()
end
-- 刷新团队组编号
function CTM:RefreshGroupText()
	local team = GetClientTeam()
	local me = GetClientPlayer()
	for i = 0, team.nGroupNum - 1 do
		local frame = self:GetPartyFrame(i)
		if frame then
			local TextGroup = frame:Lookup("", "Handle_BG/Text_GroupIndex")
			if me.IsInRaid() then
				TextGroup:SetText(g_tStrings.STR_NUMBER[i + 1])
				TextGroup:SetFontScheme(7)
				local tGroup = team.GetGroupInfo(i)
				if tGroup and tGroup.MemberList then
					for k, v in ipairs(tGroup.MemberList) do
						if v == UI_GetClientPlayerID() then
							-- TextGroup:SetFontScheme(2)
							TextGroup:SetFontColor(255, 128, 0) -- 自己所在的小队 黄色
							break
						end
					end
				end
			else
				TextGroup:SetText(g_tStrings.STR_TEAM)
			end
		end
	end
end
 -- 连接所有面板
function CTM:AutoLinkAllPanel()
	local frameMain = Cataclysm_Main.GetFrame()
	local nX, nY = frameMain:GetRelPos()
	nY = nY + 24
	local nShownCount = 0
	local tPosnSize = {}
	-- { nX = nX, nY = nY, nW = 0, nH = 0 }
	for i = 0, CTM_GROUP_COUNT do
		local hPartyPanel = self:GetPartyFrame(i)
		if hPartyPanel then
			local nW, nH = hPartyPanel:GetSize()

			if nShownCount < CFG.nAutoLinkMode then
				tPosnSize[nShownCount] = { nX = nX + (128 * CFG.fScaleX * nShownCount), nY = nY, nW = nW, nH = nH }
			else
				local nUpperIndex = math.min(nShownCount - CFG.nAutoLinkMode, CFG.nAutoLinkMode - 1)
				local tPS = tPosnSize[nUpperIndex] or {nH = 235 * CFG.fScaleY}
				tPosnSize[nShownCount] = {
					nX = nX + (128 * CFG.fScaleX * (nShownCount - CFG.nAutoLinkMode)),
					nY = nY + tPosnSize[nUpperIndex].nH,
					nW = nW,
					nH = nH
				}
			end
			local _nX, _nY = hPartyPanel:GetRelPos()
			if _nX ~= tPosnSize[nShownCount].nX or _nY ~= tPosnSize[nShownCount].nY then
				hPartyPanel:SetRelPos(tPosnSize[nShownCount].nX, tPosnSize[nShownCount].nY)
			end
			nShownCount = nShownCount + 1
		end
	end
end

function CTM:GetMemberInfo(dwID)
	local team = GetClientTeam()
	if not team then
		return
	end
	return team.GetMemberInfo(dwID)
end

function CTM:GetTeamInfo()
	local team = GetClientTeam()
	return {
		[TEAM_AUTHORITY_TYPE.LEADER]     = team.GetAuthorityInfo(TEAM_AUTHORITY_TYPE.LEADER),
		[TEAM_AUTHORITY_TYPE.MARK]       = team.GetAuthorityInfo(TEAM_AUTHORITY_TYPE.MARK),
		[TEAM_AUTHORITY_TYPE.DISTRIBUTE] = team.GetAuthorityInfo(TEAM_AUTHORITY_TYPE.DISTRIBUTE),
	}
end

local function HideTarget()
	if CTM_CACHE[CTM_TARGET] and CTM_CACHE[CTM_TARGET]:IsValid() then
		if CTM_CACHE[CTM_TARGET]:Lookup("Image_Selected") and CTM_CACHE[CTM_TARGET]:Lookup("Image_Selected"):IsValid() then
			CTM_CACHE[CTM_TARGET]:Lookup("Image_Selected"):Hide()
		end
	end
end

function CTM:RefreshTarget(dwOldID, nOldType, dwNewID, nNewType)
	if dwOldID == CTM_TARGET then
		HideTarget()
	end
	if nNewType == TARGET.PLAYER then
		if CTM_CACHE[dwNewID] and CTM_CACHE[dwNewID]:IsValid() then
			if CTM_CACHE[dwNewID]:Lookup("Image_Selected") and CTM_CACHE[dwNewID]:Lookup("Image_Selected"):IsValid() then
				CTM_CACHE[dwNewID]:Lookup("Image_Selected"):Show()
				CTM_CACHE[dwNewID]:Lookup("Image_Selected"):SetFrame(CTM_BORDER_FRAME)
			end
		end
	end
	CTM_TARGET = dwNewID
end

local function HideTTarget()
	if CTM_CACHE[CTM_TTARGET] and CTM_CACHE[CTM_TTARGET]:IsValid() then
		if CTM_CACHE[CTM_TTARGET]:Lookup("Animate_TargetTarget") and CTM_CACHE[CTM_TTARGET]:Lookup("Animate_TargetTarget"):IsValid() then
			CTM_CACHE[CTM_TTARGET]:Lookup("Animate_TargetTarget"):Hide()
		end
	end
end

function CTM:RefreshTTarget()
	if CFG.bShowTargetTargetAni then
		local dwType, dwID = Target_GetTargetData()
		if dwID then
			local KObject = GetTarget(dwID)
			if KObject then
				local tdwType, tdwID = KObject.GetTarget()
				if tdwID ~= CTM_TTARGET then
					HideTTarget()
				end
				if tdwID and tdwID ~= 0 and tdwType == TARGET.PLAYER then
					if CTM_CACHE[tdwID] and CTM_CACHE[tdwID]:IsValid() then
						if CTM_CACHE[tdwID]:Lookup("Animate_TargetTarget") and CTM_CACHE[tdwID]:Lookup("Animate_TargetTarget"):IsValid() then
							CTM_CACHE[tdwID]:Lookup("Animate_TargetTarget"):Show()
						end
					end
				end
				CTM_TTARGET = tdwID
			else
				HideTTarget()
			end
		else
			HideTTarget()
		end
	else
		HideTTarget()
	end
end

function CTM:RefreshMark()
	local team = GetClientTeam()
	local tPartyMark = team.GetTeamMark()
	if not tPartyMark then return end
	for k, v in pairs(CTM_CACHE) do
		if v:IsValid() then
			if tPartyMark[k] then
				local nMarkID = tPartyMark[k]
				if nMarkID and PARTY_MARK_ICON_FRAME_LIST[nMarkID] then
					-- assert(nMarkID > 0 and nMarkID <= #PARTY_MARK_ICON_FRAME_LIST)
					nIconFrame = PARTY_MARK_ICON_FRAME_LIST[nMarkID]
				end
				v:Lookup("Image_MarkImage"):FromUITex(PARTY_MARK_ICON_PATH, nIconFrame)
				v:Lookup("Image_MarkImage"):Show()
				local fScale = (CFG.fScaleY + CFG.fScaleX) / 2
				v:Lookup("Image_MarkImage"):SetSize(24 * fScale, 24 * fScale)
			else
				v:Lookup("Image_MarkImage"):Hide()
			end
		end
	end
end

function CTM:CallRefreshImages(dwID, ...)
	if type(dwID) == "number" then
		local info = self:GetMemberInfo(dwID)
		if info and CTM_CACHE[dwID] and CTM_CACHE[dwID]:IsValid() then
			self:RefreshImages(CTM_CACHE[dwID], dwID, info, ...)
		end
	else
		for k, v in pairs(CTM_CACHE) do
			if v:IsValid() then
				local info = self:GetMemberInfo(k)
				self:RefreshImages(v, k, info, ...)
			end
		end
	end
end

function CTM:KungFuSwitch(dwID)
	local handle = CTM_CACHE[dwID]
	if handle and handle:IsValid() then
		if GetPlayer(dwID) then
			local key = "CTM_KUNFU_" .. dwID
			local img = handle:Lookup("Image_Icon")
			JH.BreatheCall(key, function()
				local player = GetPlayer(dwID)
				local nType, dwSkillID, dwSkillLevel, fCastPercent = player.GetSkillOTActionState()
				if img and img:IsValid() and player and (nType == CHARACTER_OTACTION_TYPE.ACTION_SKILL_PREPARE or nType == CHARACTER_OTACTION_TYPE.ACTION_SKILL_CHANNEL) then
					local alpha = 255 * (math.abs(math.mod(fCastPercent * 300, 32) - 7) + 4) / 12
					if alpha <= 255 then
						img:SetAlpha(alpha)
					end
				else
					if img and img:IsValid() then
						img:SetAlpha(255)
					end
					JH.UnBreatheCall(key)
				end
			end)
		end
	end
end

-- 刷新图标和名字之类的信息
function CTM:RefreshImages(h, dwID, info, tSetting, bIcon, bFormationLeader, bName)
	-- assert(info)
	if not info then return end
	-- 刷新团队权限标记
	if type(tSetting) ~= "nil" then
		local fnAction = function(t)
			local hTotal = {
				[TEAM_AUTHORITY_TYPE.LEADER]     = h:Lookup("Handle_Icons/Image_Leader"),
				[TEAM_AUTHORITY_TYPE.MARK]       = h:Lookup("Handle_Icons/Image_Marker"),
				[TEAM_AUTHORITY_TYPE.DISTRIBUTE] = h:Lookup("Handle_Icons/Image_Looter"),
			}
			for k, v in pairs(hTotal) do
				if t[k] == dwID then
					v:Show()
					local fScale = (CFG.fScaleY + CFG.fScaleX) / 2
					v:SetSize(14 * fScale, 14 * fScale)
				else
					v:Hide()
				end
			end
		end

		if type(tSetting) == "table" then -- 根据表的内容刷新标记队长等信息
			fnAction(tSetting)
		elseif type(tSetting) == "boolean" and tSetting then
			fnAction(self:GetTeamInfo())
		end
	end
	-- 刷新阵眼
	if type(bFormationLeader) == "boolean" then
		if bFormationLeader then
			local fScale = (CFG.fScaleY + CFG.fScaleX) / 2
			h:Lookup("Handle_Icons/Image_Matrix"):SetSize(14 * fScale, 14 * fScale)
			h:Lookup("Handle_Icons/Image_Matrix"):Show()
		else
			h:Lookup("Handle_Icons/Image_Matrix"):Hide()
		end
	end
	-- 刷新内功
	if bIcon then -- 刷新icon
		local img = h:Lookup("Image_Icon")
		if CFG.nShowIcon ~= 4 then
			if CFG.nShowIcon == 2 then
				local _, nIconID = JH.GetSkillName(info.dwMountKungfuID, 1)
				if nIconID == 1435 then nIconID = 889 end
				img:FromIconID(nIconID)
			elseif CFG.nShowIcon == 1 then
				img:FromUITex(GetForceImage(info.dwForceID))
			elseif CFG.nShowIcon == 3 then
				img:FromUITex("ui/Image/UICommon/CommonPanel2.UITex", GetCampImageFrame(info.nCamp, false) or -1)
			end
			local fScale = (CFG.fScaleY + CFG.fScaleX) / 2
			if fScale * 0.9 > 1 then
				fScale = fScale * 0.9
			end
			img:SetSize(28 * fScale, 28 * fScale)
			local pos = -10 - (fScale - 1) * 15
			img:SetRelPos(pos, pos)
			h:FormatAllItemPos()
			img:Show()
		else -- 不再由icon控制 转交给textname
			img:Hide()
			bName = true
		end
	end
	-- 刷新名字
	if bName then
		local TextName = h:Lookup("Text_Name")
		TextName:SetText(info.szName)
		-- TextName:SetText("测试测试测试")
		TextName:SetFontScheme(CFG.nFont)
		if CFG.nColoredName == 1 then
			TextName:SetFontColor(GetForceColor(info.dwForceID))
		elseif CFG.nColoredName == 0 then
			TextName:SetFontColor(255, 255, 255)
		elseif CFG.nColoredName == 2 then
			if info.nCamp == 0 then
				TextName:SetFontColor(255, 255, 255)
			elseif info.nCamp == CAMP_GOOD then
				TextName:SetFontColor(60, 128, 220)
			elseif info.nCamp == CAMP_EVIL then
				TextName:SetFontColor(160, 30, 30)
			end
		end
		if CFG.nShowIcon == 4 then
			TextName:SetRelPos(-6, 0 - (CFG.fScaleY - 1) * 8)
			TextName:SetText(string.format("%s %s", CTM_KUNGFU_TEXT[info.dwMountKungfuID], info.szName))
		else
			TextName:SetRelPos(17 + (CFG.fScaleX - 1) * 15, 0 - (CFG.fScaleY - 1) * 5)
		end
		h:FormatAllItemPos()
	end
end

function CTM:DrawAllParty()
	for i = 0, CTM_GROUP_COUNT do
		if not self:GetPartyFrame(i) then
			self:CreatePanel(i)
			self:DrawParty(i)
		else
			self:FormatFrame(self:GetPartyFrame(i), CTM_MEMBER_COUNT)
		end
	end
end

function CTM:CloseParty(nIndex)
	if nIndex then
		if self:GetPartyFrame(nIndex) then
			Wnd.CloseWindow(self:GetPartyFrame(nIndex))
		end
	else
		for i = 0, CTM_GROUP_COUNT do
			if self:GetPartyFrame(i) then
				Wnd.CloseWindow(self:GetPartyFrame(i))
			end
		end
	end
end

function CTM:ReloadParty()
	local team = GetClientTeam()
	for i = 0, team.nGroupNum - 1 do
		local tGroup = team.GetGroupInfo(i)
		if tGroup then
			if #tGroup.MemberList == 0 then
				self:CloseParty(i)
			else
				self:CreatePanel(i)
				self:DrawParty(i)
			end
		end
	end
	self:AutoLinkAllPanel()
	self:RefreshMark()
	self:RefreshDistance()
	self:RefresFormation()
	CTM_LIFE_CACHE = {}
end

-- 哎 事件太蛋疼 就这样吧
function CTM:RefresFormation()
	local team = GetClientTeam()
	for i = 0, team.nGroupNum - 1 do
		local tGroup = team.GetGroupInfo(i)
		if tGroup and tGroup.dwFormationLeader and #tGroup.MemberList > 0 then
			local dwFormationLeader = tGroup.dwFormationLeader
			for k, v in ipairs(tGroup.MemberList) do
				local info = self:GetMemberInfo(v)
				if CTM_CACHE[v] and CTM_CACHE[v]:IsValid() then
					self:RefreshImages(CTM_CACHE[v], v, info, false, false, dwFormationLeader == v)
				end
			end
		end
	end
end

-- 绘制面板
function CTM:DrawParty(nIndex)
	local team = GetClientTeam()
	local tGroup = team.GetGroupInfo(nIndex)
	local frame = self:GetPartyFrame(nIndex)
	local handle = frame:Lookup("", "Handle_Roles")
	local tSetting = self:GetTeamInfo()
	local hMember = Cataclysm_Main.GetFrame().hMember
	handle:Clear()
	for i = 1, CTM_MEMBER_COUNT do
		local dwID = tGroup.MemberList[i]
		local h = handle:AppendItemFromData(hMember, i)
		h.nGroup = nIndex
		if dwID then
			h.dwID = dwID
			CTM_CACHE[dwID] = h
			local info = self:GetMemberInfo(dwID)
			h:Lookup("Handle_Common/Image_BG_Force"):Show()
			self:RefreshImages(h, dwID, info, tSetting, true, dwID == tGroup.dwFormationLeader, true)
		end
		self:Scale(CFG.fScaleX, CFG.fScaleY, h)
	end
	handle:FormatAllItemPos()
	frame.nMemberCount = #tGroup.MemberList
	-- 先缩放后画
	self:FormatFrame(frame, #tGroup.MemberList)
	self:RefreshDistance() -- 立即刷新一次
	for k, v in pairs(CTM_CACHE) do
		if v:IsValid() and v.nGroup == nIndex then
			self:CallDrawHPMP(k, true)
		end
	end
	CTM_LIFE_CACHE = {}
	-- 刷新
	CTM_TTARGET = nil
	CTM_TARGET = nil
	local dwType, dwID = Target_GetTargetData()
	self:RefreshTarget(dwID, dwType, dwID, dwType)
	self:RefreshTTarget()
end

function CTM:Scale(fX, fY, frame)
	if frame then
		frame:Scale(fX, fY)
	else
		for i = 0, CTM_GROUP_COUNT do
			if self:GetPartyFrame(i) then
				self:GetPartyFrame(i):Scale(fX, fY)
				self:FormatFrame(self:GetPartyFrame(i))
			end
		end
	end
	self:AutoLinkAllPanel()
	self:CallRefreshImages(true, true, true, nil, true) -- 缩放其他图标
	self:RefresFormation() -- 缩放阵眼
	self:RefreshMark() -- 缩放标记
end

function CTM:FormatFrame(frame, nMemberCount)
	local fX, fY = CFG.fScaleX, CFG.fScaleY
	local helgit, nGrouphelgit = (CFG.fScaleY - 1) * 18, 0
	local h = frame:Lookup("", "Handle_BG")
	if CTM_DRAG or CFG.bShowAllGrid then
		nMemberCount = CTM_MEMBER_COUNT
		local handle = frame:Lookup("", "Handle_Roles")
		for i = 0, handle:GetItemCount() - 1 do
			local h = handle:Lookup(i)
			if h and h:IsValid() and not h.dwID then
				handle:Lookup(i):Lookup("Image_BG_Slot"):Show()
			end
		end
	else
		nMemberCount = frame.nMemberCount or CTM_MEMBER_COUNT
		local handle = frame:Lookup("", "Handle_Roles")
		for i = 0, handle:GetItemCount() - 1 do
			handle:Lookup(i):Lookup("Image_BG_Slot"):Hide()
		end
	end
	if not CFG.bShowGropuNumber then
		nGrouphelgit = 21
	end
	frame:SetSize(128 * fX, (25 + nMemberCount * CTM_BOX_HEIGHT) * fY - helgit - nGrouphelgit)
	h:Lookup("Shadow_BG"):SetSize(120 * fX, (20 + nMemberCount * CTM_BOX_HEIGHT) * fY - helgit - nGrouphelgit)
	h:Lookup("Image_BG_L"):SetSize(18 * fX, nMemberCount * (CTM_BOX_HEIGHT + 3) * fY - helgit - nGrouphelgit)
	h:Lookup("Image_BG_R"):SetSize(18 * fX, nMemberCount * (CTM_BOX_HEIGHT + 3) * fY - helgit - nGrouphelgit)
	h:Lookup("Image_BG_BL"):SetRelPos(0, (11 + nMemberCount * CTM_BOX_HEIGHT) * fY - helgit - nGrouphelgit)
	h:Lookup("Image_BG_T"):SetSize(110 * fX, 18 * fY)
	h:Lookup("Image_BG_B"):SetSize(110 * fX, 18 * fY)
	h:Lookup("Image_BG_B"):SetRelPos(14 * fX, (11 + nMemberCount * CTM_BOX_HEIGHT) * fY - helgit - nGrouphelgit)
	h:Lookup("Image_BG_BR"):SetRelPos(112 * fX, (11 + nMemberCount * CTM_BOX_HEIGHT) * fY - helgit - nGrouphelgit)
	if CFG.bShowGropuNumber then
		h:Lookup("Text_GroupIndex"):SetSize(128 * fX, 26 * fY - helgit)
		h:Lookup("Text_GroupIndex"):SetRelPos(0, nMemberCount * CTM_BOX_HEIGHT * fY)
	else
		h:Lookup("Text_GroupIndex"):Hide()
	end
	h:FormatAllItemPos()
end

-- 注册buff
function CTM:RecBuff(dwMemberID, data)
	CTM_BUFF_CACHE[data.dwID] = data
end

function CTM:RefresBuff()
	local team, me = GetClientTeam(), GetClientPlayer()
	local tCheck = {}
	for k, v in ipairs(team.GetTeamMemberList()) do
		local p = GetPlayer(v)
		if CTM_CACHE[v] and CTM_CACHE[v]:IsValid() and p then
			local handle = CTM_CACHE[v]:Lookup("Handle_Buff_Boxes")
			for dwID, data in pairs(CTM_BUFF_CACHE) do
				local KBuff = GetBuff(dwID, data.nLevel, p)
				local key = dwID .. "," .. data.nLevel
				local item = handle:Lookup(key)
				local nEndFrame, _, nStackNum
				-- init check
				if KBuff then
					if not data.bOnlySelf then
						nEndFrame, nStackNum = KBuff.GetEndTime(), KBuff.nStackNum
					else
						for kk, vv in ipairs(JH.GetBuffList(p)) do
							if vv.dwID == dwID and vv.dwSkillSrcID == me.dwID and (data.nLevel == 0 or data.nLevel == vv.nLevel) then
								nEndFrame, _, nStackNum = select(4, p.GetBuff(vv.nCount - 1))
								break
							end
						end
					end
				end
				if nEndFrame and (not data.nStackNum or nStackNum >= data.nStackNum) then
					-- create
					if not item and handle:GetItemCount() < CFG.nMaxShowBuff then
						 item = handle:AppendItemFromData(Cataclysm_Main.GetFrame().hBuff, key)
						if not data.col then
							item:Lookup("Shadow"):Hide()
						else
							item:Lookup("Shadow"):SetColorRGB(unpack(data.col))
						end
						local szName, icon = JH.GetBuffName(data.dwID, data.nLevelEx)
						if data.nIcon and tonumber(data.nIcon) then
							icon = data.nIcon
						end
						local box = item:Lookup("Box")
						box:SetObject(UI_OBJECT_NOT_NEED_KNOWN, data.dwID, data.nLevelEx)
						box:SetObjectIcon(icon)
						box:SetOverTextPosition(0, ITEM_POSITION.RIGHT_BOTTOM)
						box:SetObjectStaring(CFG.bStaring)
						if CFG.bAutoBuffSize then
							if CFG.fScaleY > 1 then
								item:Scale(CFG.fScaleY, CFG.fScaleY)
							end
						else
							item:Scale(CFG.fBuffScale, CFG.fBuffScale)
						end
						handle:FormatAllItemPos()
					end
					-- revise
					if item then
						local hBox = item:Lookup("Box")
						if CFG.bShowBuffTime then
							local nTime = GetEndTime(nEndFrame)
							if nTime < 5 then
								if nTime >= 0 then
									hBox:SetOverTextFontScheme(0, 219)
									hBox:SetOverText(0, floor(nTime) .. " ")
								end
							elseif nTime < 10 then
								hBox:SetOverTextFontScheme(0, 27)
								hBox:SetOverText(0, floor(nTime) .. " ")
							else
								hBox:SetOverText(0, "")
							end
						else
							hBox:SetOverText(0, "")
						end
						if CFG.bShowBuffNum and nStackNum > 1 then
							hBox:SetOverTextFontScheme(1, 15)
							hBox:SetOverText(1, nStackNum .. " ")
						else
							hBox:SetOverText(1, "")
						end
					end
					tCheck[dwID] = true
				else
					if item then
						handle:RemoveItem(item)
						handle:FormatAllItemPos() -- 格式化buff的位置
					end
				end
			end
		elseif CTM_CACHE[v] and CTM_CACHE[v]:IsValid() then
			local handle = CTM_CACHE[v]:Lookup("Handle_Buff_Boxes")
			handle:Clear()
		end
	end
	for k, v in pairs(CTM_BUFF_CACHE) do
		if not tCheck[k] then
			CTM_BUFF_CACHE[k] = nil
		end
	end
	-- print(CTM_BUFF_CACHE)
end

function CTM:RefreshDistance()
	if CFG.bEnableDistance then
		for k, v in pairs(CTM_CACHE) do
			if v:IsValid() then
				local p = GetPlayer(k) -- info.nPoX 刷新太慢了 对于治疗来说 这个太重要了
				local Lsha = v:Lookup("Handle_Common/Shadow_Life")
				if p then
					local nDistance = GetDistance(p.nX, p.nY) -- 只计算平面
					if CFG.nBGClolrMode == 1 then
						local find
						for kk, vv in ipairs(CFG.tDistanceLevel) do
							if nDistance <= vv then
								if Lsha.nLevel ~= kk then
									Lsha.nLevel = kk
									self:CallDrawHPMP(k, true)
								end
								find = true
								break
							end
						end
						-- 如果上面都不匹配的话 默认认为出了同步范围 feedback 桥之于水
						if not find and Lsha.nLevel then
							Lsha.nLevel = nil
							self:CallDrawHPMP(k, true)
						end
					else
						local _nDistance = Lsha.nDistance or 0
						Lsha.nDistance = nDistance
						if (nDistance > 20 and _nDistance <= 20) or (nDistance <= 20 and _nDistance > 20) then
							self:CallDrawHPMP(k, true)
						end
					end
					if CFG.bShowDistance then
						v:Lookup("Handle_Common/Text_Distance"):SetText(string.format("%.1f", nDistance))
						v:Lookup("Handle_Common/Text_Distance"):SetFontColor(255, math.max(0, 255 - nDistance * 8), math.max(0, 255 - nDistance * 8))
					else
						v:Lookup("Handle_Common/Text_Distance"):SetText("")
					end
				else
					if CFG.bShowDistance then
						v:Lookup("Handle_Common/Text_Distance"):SetText("")
					end
					if Lsha.nLevel or Lsha.nDistance then
						Lsha.nLevel = nil
						Lsha.nDistance = nil
						self:CallDrawHPMP(k, true)
					end
				end
			end
		end
	else
		for k, v in pairs(CTM_CACHE) do
			if v:IsValid() then
				local Lsha = v:Lookup("Handle_Common/Shadow_Life")
				if Lsha.nLevel or Lsha.nDistance ~= 0 then
					Lsha.nLevel = 1
					Lsha.nDistance = 0
					self:CallDrawHPMP(k, true)
				end
			end
		end
	end
end

-- 血量 / 内力
function CTM:CallDrawHPMP(dwID, ...)
	if type(dwID) == "number" then
		local info = self:GetMemberInfo(dwID)
		if info and CTM_CACHE[dwID] and CTM_CACHE[dwID]:IsValid() then
			self:DrawHPMP(CTM_CACHE[dwID], dwID, info, ...)
		end
	else
		for k, v in pairs(CTM_CACHE) do
			if v:IsValid() then
				local info = self:GetMemberInfo(k)
				if info then
					self:DrawHPMP(v, k, info, ...)
				end
			end
		end
	end
end

-- 缩放对动态构建的UI不会缩放 所以需要后处理
function CTM:DrawHPMP(h, dwID, info, bRefresh)
	if not info then return end
	local Lsha = h:Lookup("Handle_Common/Shadow_Life")
	local Msha = h:Lookup("Handle_Common/Shadow_Mana")
	local p, dwMountType
	if CFG.bFasterHP then
		p = GetPlayer(dwID)
	end
	-- 气血计算 因为sync 必须拿出来单独算
	local nLifePercentage, nCurrentLife, nMaxLife
	if p and p.nMaxLife ~= 1 and p.nCurrentLife ~= 1 and p.nCurrentLife ~= 255 and p.nMaxLife ~= 255 and p.nCurrentLife < 10000000 and p.nCurrentLife > - 1000 then -- p sync err fix
		nCurrentLife = p.nCurrentLife
		nMaxLife = p.nMaxLife
	else
		nCurrentLife = info.nCurrentLife
		nMaxLife = info.nMaxLife
	end
	nMaxLife     = mmax(1, nMaxLife)
	nCurrentLife = mmax(0, nCurrentLife)
	nLifePercentage = nCurrentLife / nMaxLife
	if not nLifePercentage or nLifePercentage < 0 or nLifePercentage > 1 then nLifePercentage = 1 end

	local bDeathFlag = info.bDeathFlag
	-- 有待验证
	if p then
		if p.GetKungfuMount() then
			dwMountType = p.GetKungfuMount().dwMountType
		end
		if p.nMoveState == MOVE_STATE_ON_STAND then
			if info.bDeathFlag then
				bDeathFlag = true
			end
		else
			bDeathFlag = p.nMoveState == MOVE_STATE_ON_DEATH
		end
	end
	local nAlpha = 255
	if CFG.nBGClolrMode ~= 1 then
		if (Lsha.nDistance and Lsha.nDistance > 20) or not Lsha.nDistance then
			if info.bIsOnLine then
				nAlpha = nAlpha * 0.6
			end
		end
	end
	-- 内力
	if not bDeathFlag then
		local nPercentage, nManaShow = 1, 1
		local mana = h:Lookup("Handle_Common/Text_Mana")
		if not IsPlayerManaHide(info.dwForceID, dwMountType) then -- 内力不需要那么准
			nPercentage = info.nCurrentMana / info.nMaxMana
			nManaShow = info.nCurrentMana
			if not CFG.nShowMP then
				mana:SetText("")
			else
				mana:SetText(nManaShow)
			end
		end
		if not nPercentage or nPercentage < 0 or nPercentage > 1 then nPercentage = 1 end
		local r, g, b = unpack(CFG.tManaColor)
		self:DrawShadow(Msha, 119 * nPercentage, 9, r, g, b, nAlpha, CFG.bManaGradient)
		Msha:Show()
	else
		Msha:Hide()
	end
	-- 缓存
	if not CFG.bFasterHP or bRefresh or (CFG.bFasterHP and CTM_LIFE_CACHE[dwID] ~= nLifePercentage) then
		-- 颜色计算
		local nNewW = 119 * nLifePercentage
		local r, g, b = unpack(CFG.tOtherCol[2]) -- 不在线就灰色了
		if info.bIsOnLine then
			if CFG.nBGClolrMode == 1 then
				if p or GetPlayer(dwID) then
					if Lsha.nLevel then
						r, g, b = unpack(CFG.tDistanceCol[Lsha.nLevel])
					else
						r, g, b = unpack(CFG.tOtherCol[3])
					end
				else
					r, g, b = unpack(CFG.tOtherCol[3]) -- 在线使用白色
				end
			elseif CFG.nBGClolrMode == 0 then
				r, g, b = unpack(CFG.tDistanceCol[1]) -- 使用用户配色1
			elseif CFG.nBGClolrMode == 2 then
				r, g, b = JH.GetForceColor(info.dwForceID)
			end
		else
			nAlpha = 255
		end
		self:DrawShadow(Lsha, nNewW, 32, r, g, b, nAlpha, CFG.bLifeGradient)
		Lsha:Show()
		if CFG.bHPHitAlert then
			local lifeFade = h:Lookup("Handle_Common/Shadow_Life_Fade")
			if CTM_LIFE_CACHE[dwID] and CTM_LIFE_CACHE[dwID] > nLifePercentage then
				local alpha = lifeFade:GetAlpha()
				if alpha == 0 then
					lifeFade:SetSize(CTM_LIFE_CACHE[dwID] * 119 * CFG.fScaleX, 31 * CFG.fScaleY)
				end
				if CFG.nBGClolrMode ~= 1 then
					if (Lsha.nDistance and Lsha.nDistance > 20) or not Lsha.nDistance then
						lifeFade:SetAlpha(0)
						lifeFade:Hide()
					else
						lifeFade:SetAlpha(240)
						lifeFade:Show()
					end
				else
					lifeFade:SetAlpha(240)
					lifeFade:Show()
				end
				local key = "CTM_HIT_" .. dwID
				JH.UnBreatheCall(key)
				JH.BreatheCall(key, function()
					if lifeFade:IsValid() then
						local nFadeAlpha = math.max(lifeFade:GetAlpha() - CTM_ALPHA_STEP, 0)
						lifeFade:SetAlpha(nFadeAlpha)
						if nFadeAlpha <= 0 then
							JH.UnBreatheCall(key)
						end
					else
						JH.UnBreatheCall(key)
					end
				end)
			end
		else
			h:Lookup("Handle_Common/Shadow_Life_Fade"):Hide()
		end

		if not CTM_LIFE_CACHE[dwID] then
			CTM_LIFE_CACHE[dwID] = 0
		else
			CTM_LIFE_CACHE[dwID] = nLifePercentage
		end
		-- 数值绘制
		local life = h:Lookup("Handle_Common/Text_Life")
		life:SetFontScheme(CFG.nLifeFont)
		if CFG.nBGClolrMode ~= 1 then
			if (Lsha.nDistance and Lsha.nDistance > 20) or not Lsha.nDistance then
				life:SetAlpha(150)
			else
				life:SetAlpha(255)
			end
		else
			life:SetAlpha(255)
		end

		if not bDeathFlag and info.bIsOnLine then
			life:SetFontColor(255, 255, 255)
			if CFG.nHPShownMode2 == 0 then
				life:SetText("")
			else
				local fnAction = function(val, max)
					if CFG.nHPShownNumMode == 1 then
						if val > 9999 then
							return string.format("%.1fw", val / 10000)
						else
							return val
						end
					elseif CFG.nHPShownNumMode == 2 then
						return string.format("%.1f", val / max * 100) .. "%"
					elseif CFG.nHPShownNumMode == 3 then
						return val
					end
				end
				if CFG.nHPShownMode2 == 2 then
					life:SetText(fnAction(nCurrentLife, nMaxLife))
				elseif CFG.nHPShownMode2 == 1 then
					local nShownLife = nMaxLife - nCurrentLife
					if nShownLife > 0 then
						life:SetText("-" .. fnAction(nShownLife, nMaxLife))
					else
						life:SetText("")
					end
				end
			end
		elseif not info.bIsOnLine then
			life:SetFontColor(128, 128, 128)
			life:SetText(STR_FRIEND_NOT_ON_LINE)
		elseif bDeathFlag then
			life:SetFontColor(255, 0, 0)
			life:SetText(FIGHT_DEATH)
		else
			life:SetFontColor(128, 128, 128)
			life:SetText(COINSHOP_SOURCE_NULL)
		end
		-- if info.dwMountKungfuID == 0 then -- 没有同步成功时显示的内容
			-- life:SetText("sync ...")
		-- end
	end
end

function CTM:DrawShadow(sha, x, y, r, g, b, a, bGradient) -- 重绘三角扇
	sha:SetTriangleFan(GEOMETRY_TYPE.TRIANGLE)
	sha:ClearTriangleFanPoint()
	x = x * CFG.fScaleX
	y = y * CFG.fScaleY
	if bGradient then
		sha:AppendTriangleFanPoint(0, 0, 64, 64, 64, a)
		sha:AppendTriangleFanPoint(x, 0, 64, 64, 64, a)
		sha:AppendTriangleFanPoint(x, y, r, g, b, a)
		sha:AppendTriangleFanPoint(0, y, r, g, b, a)
	else
		sha:AppendTriangleFanPoint(0, 0, r, g, b, a)
		sha:AppendTriangleFanPoint(x, 0, r, g, b, a)
		sha:AppendTriangleFanPoint(x, y, r, g, b, a)
		sha:AppendTriangleFanPoint(0, y, r, g, b, a)
	end
end

function CTM:Send_RaidReadyConfirm(bDisable)
	if JH.IsLeader() then
		self:Clear_RaidReadyConfirm()
		for k, v in pairs(CTM_CACHE) do
			if v:IsValid() then
				local info = self:GetMemberInfo(k)
				if info.bIsOnLine and k ~= UI_GetClientPlayerID() then
					v:Lookup("Image_ReadyCover"):Show()
				end
			end
		end
		if not bDisable then
			Send_RaidReadyConfirm()
			JH.DelayCall(function()
				for k, v in pairs(CTM_CACHE) do
					if v:IsValid() then
						if v:Lookup("Image_ReadyCover"):IsVisible() or v:Lookup("Image_NotReady"):IsVisible() then
							JH.Confirm(g_tStrings.STR_RAID_READY_CONFIRM_RESET .. "?", function()
								self:Clear_RaidReadyConfirm()
							end)
							break
						end
					end
				end
			end, 5000)
		end
	end
end

function CTM:Clear_RaidReadyConfirm()
	for k, v in pairs(CTM_CACHE) do
		if v:IsValid() then
			v:Lookup("Image_ReadyCover"):Hide()
			v:Lookup("Image_NotReady"):Hide()
			v:Lookup("Animate_Ready"):Hide()
		end
	end
end

function CTM:ChangeReadyConfirm(dwID, status)
	if CTM_CACHE[dwID] and CTM_CACHE[dwID]:IsValid() then
		local h = CTM_CACHE[dwID]
		h:Lookup("Image_ReadyCover"):Hide()
		if status then
			local key = "CTM_READY_" .. dwID
			h:Lookup("Animate_Ready"):Show()
			h:Lookup("Animate_Ready"):SetAlpha(240)
			JH.BreatheCall(key, function()
				if h:Lookup("Animate_Ready"):IsValid() then
					local nAlpha = math.max(h:Lookup("Animate_Ready"):GetAlpha() - 15, 0)
					h:Lookup("Animate_Ready"):SetAlpha(nAlpha)
					if nAlpha <= 0 then
						JH.UnBreatheCall(key)
					end
				end
			end)
		else
			h:Lookup("Image_NotReady"):Show()
		end
	end
end

function CTM:CallEffect(dwTargetID, nDelay)
	if CTM_CACHE[dwTargetID] and CTM_CACHE[dwTargetID]:IsValid() then
		CTM_CACHE[dwTargetID]:Lookup("Image_Effect"):Show()
		JH.DelayCall(function()
			if CTM_CACHE[dwTargetID] and CTM_CACHE[dwTargetID]:IsValid() then
				CTM_CACHE[dwTargetID]:Lookup("Image_Effect"):Hide()
			end
		end, nDelay)
	end
end

Grid_CTM = setmetatable({}, { __index = CTM, __newindex = function() end, __metatable = true })
-- public
function CTM_GetMemberHandle(dwID)
	if CTM_CACHE[dwID] and CTM_CACHE[dwID]:IsValid() then
		return CTM_CACHE[dwID]
	end
end
