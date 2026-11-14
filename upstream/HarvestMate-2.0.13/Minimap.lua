local _, HG = ...

-- Кнопка у миникарты (без внешних библиотек) и меню модификаций.

local ICON = "Interface\\Icons\\INV_Misc_Herb_01"
local atan2 = math.atan2 or math.atan
local button

local function Radius()
	return (Minimap:GetWidth() / 2) + 8
end

local function Position()
	local angle = math.rad(HG.db.angle or 215)
	local r = Radius()
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	HG.db.angle = math.deg(atan2(cy - my, cx - mx)) % 360
	Position()
end

local function ShowTip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine(HG.title)
	GameTooltip:AddLine(HG.L.CLICK_OPEN, 1, 1, 1)
	GameTooltip:AddLine(HG.L.RCLICK_SESSION, 1, 1, 1)
	GameTooltip:AddLine(HG.L.DRAG_MOVE, 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function Create()
	button = CreateFrame("Button", "HarvestMateMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	back:SetSize(20, 20)
	back:SetPoint("CENTER")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local ring = button:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			HG.ToggleSession()
		else
			HG.ToggleHub()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", FollowCursor)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", ShowTip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	Position()
end

local function Update()
	if not HG.db then
		return
	end
	if HG.db.opt.minimap then
		if not button then
			Create()
		end
		Position()
		button:Show()
	elseif button then
		button:Hide()
	end
end

HG.On("PLAYER_LOGIN", Update)
HG.Listen("OPTIONS", Update)

-- Меню модификаций (AddonCompartmentFunc в .toc).
function _G.HarvestMate_OnCompartmentClick()
	HG.ToggleHub()
end

function _G.HarvestMate_OnCompartmentEnter(_, owner)
	if owner then
		ShowTip(owner)
	end
end

function _G.HarvestMate_OnCompartmentLeave()
	GameTooltip:Hide()
end
