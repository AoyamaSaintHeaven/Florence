-- ============================================================
--  FLORENCE HUB  |  Aim Assist v3 (Lock-On)
--  Private test build • Mobile-aware • Draggable toggle • M key
-- ============================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ============================================================
--  PLATFORM
-- ============================================================
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local WIN_W      = IS_MOBILE and 460 or 740
local WIN_H      = IS_MOBILE and 400 or 540
local SIDEBAR_W  = IS_MOBILE and 120 or 168
local FONT_SCALE = IS_MOBILE and 0.9 or 1

local function fs(n) return math.floor(n * FONT_SCALE + 0.5) end

-- ============================================================
--  PALETTE
-- ============================================================
local P = {
	Accent      = Color3.fromRGB(120,  90, 255),
	AccentLight = Color3.fromRGB(150, 120, 255),
	AccentDark  = Color3.fromRGB( 88,  64, 200),
	Bg          = Color3.fromRGB( 14,  14,  20),
	BgLight     = Color3.fromRGB( 20,  20,  28),
	Panel       = Color3.fromRGB( 24,  24,  34),
	PanelAlt    = Color3.fromRGB( 30,  30,  42),
	Sidebar     = Color3.fromRGB( 17,  17,  24),
	Row         = Color3.fromRGB( 32,  32,  46),
	RowHover    = Color3.fromRGB( 42,  42,  58),
	Text        = Color3.fromRGB(242, 242, 248),
	Sub         = Color3.fromRGB(148, 148, 168),
	Muted       = Color3.fromRGB(100, 100, 120),
	Good        = Color3.fromRGB( 82, 220, 140),
	Warn        = Color3.fromRGB(240, 180,  70),
	Bad         = Color3.fromRGB(240,  90,  90),
	Border      = Color3.fromRGB( 44,  44,  60),
	Lock        = Color3.fromRGB(255, 170,  60),
}

-- ============================================================
--  HELPERS
-- ============================================================
local function getGuiParent()
	if gethui then return gethui() end
	if syn and syn.protect_gui then return game:GetService("CoreGui") end
	local ok, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok and cg then return cg end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local parent = getGuiParent()
pcall(function()
	local old = parent:FindFirstChild("FlorenceAimHub")
	if old then old:Destroy() end
end)

local function new(cls, props, prnt)
	local i = Instance.new(cls)
	for k, v in pairs(props or {}) do i[k] = v end
	i.Parent = prnt
	return i
end

local function corner(r, p)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end

local function stroke(c, t, p, transparency)
	return new("UIStroke", {
		Color = c, Thickness = t or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, p)
end

local function padding(p, all)
	return new("UIPadding", {
		PaddingTop    = UDim.new(0, all or 0),
		PaddingBottom = UDim.new(0, all or 0),
		PaddingLeft   = UDim.new(0, all or 0),
		PaddingRight  = UDim.new(0, all or 0),
	}, p)
end

local function tween(obj, time, props, style, dir)
	TweenService:Create(obj,
		TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props):Play()
end

local rebindingActive = false

-- ============================================================
--  SETTINGS
-- ============================================================
local settings = {
	AimbotEnabled     = false,
	TargetLockEnabled = false,
	WallCheck         = true,
	FovDetection      = true,
	HighlightTarget   = true,
	HoldMode          = false,
	TargetSort        = "Crosshair",
	FOV               = 150,
	Smoothness        = 0.15,
	AimPart           = "Head",
	LockDistance      = 500,
	LockGrace         = 0.2,
	AimKey            = Enum.KeyCode.E,
	SwitchKey         = Enum.KeyCode.Q,
	LockKey           = Enum.KeyCode.F,
}

-- Runtime state
local runtime = {
	keyHeld       = false,
	switchPending = false,
	targetIndex   = 1,
}

-- Lock-on state
local lock = {
	target   = nil,
	lockedAt = 0,
	lostAt   = nil,
}

-- ============================================================
--  GUI ROOT
-- ============================================================
local gui = new("ScreenGui", {
	Name = "FlorenceAimHub",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, parent)
if syn and syn.protect_gui then
	pcall(function() syn.protect_gui(gui) end)
end

-- ============================================================
--  TOASTS
-- ============================================================
local TOAST_W = IS_MOBILE and 240 or 300
local toastHolder = new("Frame", {
	Name = "ToastHolder",
	Size = UDim2.fromOffset(TOAST_W, 400),
	Position = UDim2.new(1, -(TOAST_W + 20), 1, -420),
	BackgroundTransparency = 1,
	ZIndex = 100,
}, gui)
new("UIListLayout", {
	Padding = UDim.new(0, 8),
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, toastHolder)

local toastOrder = 0

local function notify(title, content, kind, duration)
	kind = kind or "info"
	local accent =
		kind == "success" and P.Good or
		kind == "error"   and P.Bad or
		kind == "warn"    and P.Warn or
		kind == "lock"    and P.Lock or P.Accent

	toastOrder += 1

	local toast = new("Frame", {
		Size = UDim2.new(1, 0, 0, 54),
		Position = UDim2.new(1, TOAST_W + 20, 0, 0),
		BackgroundColor3 = P.Panel,
		BorderSizePixel = 0,
		LayoutOrder = toastOrder,
		ClipsDescendants = true,
	}, toastHolder)
	corner(10, toast)
	stroke(P.Border, 1, toast)

	new("Frame", {
		Size = UDim2.new(0, 3, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
	}, toast)

	new("TextLabel", {
		Size = UDim2.new(1, -30, 0, 18),
		Position = UDim2.fromOffset(16, 8),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = P.Text,
		Font = Enum.Font.GothamBold,
		TextSize = fs(13),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, toast)

	new("TextLabel", {
		Size = UDim2.new(1, -30, 0, 22),
		Position = UDim2.fromOffset(16, 26),
		BackgroundTransparency = 1,
		Text = content or "",
		TextColor3 = P.Sub,
		Font = Enum.Font.Gotham,
		TextSize = fs(11),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, toast)

	tween(toast, 0.35, { Position = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Quart)

	task.delay(duration or 3.5, function()
		tween(toast, 0.3, { Position = UDim2.new(1, TOAST_W + 20, 0, 0) }, Enum.EasingStyle.Quart)
		task.wait(0.35)
		pcall(function() toast:Destroy() end)
	end)

	return toast
end

-- ============================================================
--  MAIN WINDOW
-- ============================================================
local TITLE_H = IS_MOBILE and 34 or 38

local win = new("Frame", {
	Name = "Window",
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
	BackgroundColor3 = P.Bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, gui)
corner(14, win)
stroke(P.Border, 1, win)

-- ============================================================
--  FLOATING TOGGLE
-- ============================================================
local TOGGLE_SIZE = IS_MOBILE and 46 or 50

local toggleBtn = new("TextButton", {
	Name = "Toggle",
	Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
	Position = UDim2.new(0, 20, 0.5, -TOGGLE_SIZE / 2),
	BackgroundColor3 = P.Accent,
	Text = "🎯",
	TextSize = IS_MOBILE and 20 or 24,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
	BorderSizePixel = 0,
	ZIndex = 10,
}, gui)
corner(TOGGLE_SIZE / 2, toggleBtn)
stroke(P.AccentDark, 2, toggleBtn)

do
	local dragging   = false
	local dragged    = false
	local dragStart  = Vector2.new()
	local startPos   = UDim2.new()
	local DRAG_THRESHOLD = 6

	local function toggleWindow()
		win.Visible = not win.Visible
		if win.Visible then
			local vp = workspace.CurrentCamera.ViewportSize
			local absPos = win.AbsolutePosition
			if absPos.X < -WIN_W * 0.5 or absPos.Y < -WIN_H * 0.5
			or absPos.X > vp.X or absPos.Y > vp.Y then
				win.Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2)
			end
		end
	end

	toggleBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging  = true
			dragged   = false
			dragStart = input.Position
			startPos  = toggleBtn.Position
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			if not dragged
			and (math.abs(delta.X) > DRAG_THRESHOLD
			or math.abs(delta.Y) > DRAG_THRESHOLD) then
				dragged = true
				tween(toggleBtn, 0.1, { BackgroundColor3 = P.AccentLight })
			end
			if dragged then
				toggleBtn.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not dragging then return end

		if dragged then
			local vp = workspace.CurrentCamera.ViewportSize
			local absPos = toggleBtn.AbsolutePosition
			local absSize = toggleBtn.AbsoluteSize
			local cx = math.clamp(absPos.X, 0, vp.X - absSize.X)
			local cy = math.clamp(absPos.Y, 0, vp.Y - absSize.Y)
			toggleBtn.Position = UDim2.fromOffset(cx, cy)
		else
			toggleWindow()
		end

		dragging = false
		tween(toggleBtn, 0.1, { BackgroundColor3 = P.Accent })
	end)

	toggleBtn.MouseEnter:Connect(function()
		if not IS_MOBILE then
			tween(toggleBtn, 0.15, {
				Size = UDim2.fromOffset(TOGGLE_SIZE + 6, TOGGLE_SIZE + 6),
				Position = UDim2.new(
					toggleBtn.Position.X.Scale, toggleBtn.Position.X.Offset - 3,
					toggleBtn.Position.Y.Scale, toggleBtn.Position.Y.Offset - 3),
			})
		end
	end)
	toggleBtn.MouseLeave:Connect(function()
		if not IS_MOBILE then
			tween(toggleBtn, 0.15, {
				Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
				Position = UDim2.new(
					toggleBtn.Position.X.Scale, toggleBtn.Position.X.Offset + 3,
					toggleBtn.Position.Y.Scale, toggleBtn.Position.Y.Offset + 3),
			})
		end
	end)
end

-- ============================================================
--  TITLE BAR
-- ============================================================
local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, TITLE_H),
	BackgroundColor3 = P.BgLight,
	BorderSizePixel = 0,
}, win)
corner(14, titleBar)
new("Frame", {
	Size = UDim2.new(1, 0, 0, 14),
	Position = UDim2.new(0, 0, 1, -14),
	BackgroundColor3 = P.BgLight,
	BorderSizePixel = 0,
}, titleBar)

new("TextLabel", {
	Size = UDim2.new(1, -160, 1, 0),
	Position = UDim2.fromOffset(14, 0),
	BackgroundTransparency = 1,
	Text = "🎯  Florence Hub — Aim Assist v3" .. (IS_MOBILE and " • Mobile" or ""),
	TextColor3 = P.Text,
	Font = Enum.Font.GothamBold,
	TextSize = fs(12),
	TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local ctrlSize = IS_MOBILE and 24 or 26

local minBtn = new("TextButton", {
	Size = UDim2.fromOffset(ctrlSize, ctrlSize),
	Position = UDim2.new(1, -(ctrlSize * 2 + 12), 0, (TITLE_H - ctrlSize) / 2),
	BackgroundColor3 = P.Panel,
	Text = "–",
	TextColor3 = P.Sub,
	TextSize = fs(14),
	Font = Enum.Font.GothamBold,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, titleBar)
corner(6, minBtn)
stroke(P.Border, 1, minBtn)
minBtn.MouseEnter:Connect(function() minBtn.BackgroundColor3 = P.Row end)
minBtn.MouseLeave:Connect(function() minBtn.BackgroundColor3 = P.Panel end)

local closeBtn = new("TextButton", {
	Size = UDim2.fromOffset(ctrlSize, ctrlSize),
	Position = UDim2.new(1, -(ctrlSize + 6), 0, (TITLE_H - ctrlSize) / 2),
	BackgroundColor3 = P.Panel,
	Text = "×",
	TextColor3 = P.Sub,
	TextSize = fs(14),
	Font = Enum.Font.GothamBold,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, titleBar)
corner(6, closeBtn)
stroke(P.Border, 1, closeBtn)
closeBtn.MouseEnter:Connect(function()
	closeBtn.BackgroundColor3 = P.Bad
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
end)
closeBtn.MouseLeave:Connect(function()
	closeBtn.BackgroundColor3 = P.Panel
	closeBtn.TextColor3 = P.Sub
end)
closeBtn.MouseButton1Click:Connect(function()
	notify("Goodbye", "Florence Hub closed.", "info", 2)
	gui:Destroy()
end)

-- ============================================================
--  SIDEBAR
-- ============================================================
local sidebar = new("Frame", {
	Name = "Sidebar",
	Size = UDim2.new(0, SIDEBAR_W, 1, -TITLE_H),
	Position = UDim2.fromOffset(0, TITLE_H),
	BackgroundColor3 = P.Sidebar,
	BorderSizePixel = 0,
}, win)

new("Frame", {
	Size = UDim2.new(0, 1, 1, 0),
	Position = UDim2.new(1, -1, 0, 0),
	BackgroundColor3 = P.Border,
	BorderSizePixel = 0,
}, sidebar)

local sidebarScroll = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -50),
	Position = UDim2.fromOffset(0, 8),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = P.Accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, sidebar)

new("UIListLayout", {
	Padding = UDim.new(0, 3),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, sidebarScroll)

padding(sidebarScroll, 6)

-- ============================================================
--  CONTENT AREA
-- ============================================================
local STATUSBAR_H = IS_MOBILE and 22 or 26

local content = new("Frame", {
	Name = "Content",
	Size = UDim2.new(1, -SIDEBAR_W, 1, -TITLE_H - STATUSBAR_H),
	Position = UDim2.fromOffset(SIDEBAR_W, TITLE_H),
	BackgroundTransparency = 1,
}, win)

local statusBar = new("Frame", {
	Size = UDim2.new(1, -SIDEBAR_W, 0, STATUSBAR_H),
	Position = UDim2.new(0, SIDEBAR_W, 1, -STATUSBAR_H),
	BackgroundColor3 = P.BgLight,
	BorderSizePixel = 0,
}, win)
new("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = P.Border,
	BorderSizePixel = 0,
}, statusBar)

local statusLeft = new("TextLabel", {
	Size = UDim2.new(0.5, 0, 1, 0),
	Position = UDim2.fromOffset(10, 0),
	BackgroundTransparency = 1,
	Text = "● Ready",
	TextColor3 = P.Good,
	Font = Enum.Font.Gotham,
	TextSize = fs(10),
	TextXAlignment = Enum.TextXAlignment.Left,
}, statusBar)

local statusRight = new("TextLabel", {
	Size = UDim2.new(0.5, -10, 1, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	BackgroundTransparency = 1,
	Text = "Aim v3  •  " .. (IS_MOBILE and "mobile" or "desktop"),
	TextColor3 = P.Muted,
	Font = Enum.Font.Gotham,
	TextSize = fs(10),
	TextXAlignment = Enum.TextXAlignment.Right,
}, statusBar)

local function setStatus(text, kind)
	statusLeft.Text = "● " .. text
	statusLeft.TextColor3 =
		kind == "error" and P.Bad or
		kind == "warn"  and P.Warn or
		kind == "lock"  and P.Lock or P.Good
end

-- ============================================================
--  TAB MANAGER
-- ============================================================
local tabs = {}
local currentTab

local function switchTab(id)
	if not tabs[id] then return end
	for n, data in pairs(tabs) do
		local active = (n == id)
		data.page.Visible = active
		if active then
			data.page.Position = UDim2.fromOffset(16, 0)
			tween(data.page, 0.2, { Position = UDim2.fromOffset(0, 0) })
			tween(data.button, 0.2, { BackgroundColor3 = P.Accent })
			tween(data.indicator, 0.2, { BackgroundColor3 = P.Accent })
			tween(data.label, 0.2, { TextColor3 = Color3.new(1, 1, 1) })
			tween(data.icon, 0.2, { TextColor3 = Color3.new(1, 1, 1) })
		else
			tween(data.button, 0.2, { BackgroundColor3 = P.Sidebar })
			tween(data.indicator, 0.2, { BackgroundColor3 = Color3.fromRGB(0, 0, 0) })
			tween(data.label, 0.2, { TextColor3 = P.Sub })
			tween(data.icon, 0.2, { TextColor3 = P.Sub })
		end
	end
	currentTab = id
	setStatus(tabs[id].title .. " loaded")
end

local TAB_ROW_H = IS_MOBILE and 32 or 36

local function makeTab(id, icon, title)
	local btn = new("TextButton", {
		Name = id .. "Btn",
		Size = UDim2.new(1, 0, 0, TAB_ROW_H),
		BackgroundColor3 = P.Sidebar,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		LayoutOrder = #tabs + 1,
	}, sidebarScroll)
	corner(8, btn)

	local indicator = new("Frame", {
		Size = UDim2.new(0, 3, 0, 16),
		Position = UDim2.fromOffset(-3, (TAB_ROW_H - 16) / 2),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BorderSizePixel = 0,
	}, btn)
	corner(2, indicator)

	local iconLbl = new("TextLabel", {
		Size = UDim2.fromOffset(IS_MOBILE and 24 or 30, TAB_ROW_H),
		Position = UDim2.fromOffset(IS_MOBILE and 8 or 10, 0),
		BackgroundTransparency = 1,
		Text = icon or "•",
		TextColor3 = P.Sub,
		Font = Enum.Font.GothamBold,
		TextSize = fs(13),
	}, btn)

	local textLbl = new("TextLabel", {
		Size = UDim2.new(1, -(IS_MOBILE and 36 or 46), 1, 0),
		Position = UDim2.fromOffset(IS_MOBILE and 32 or 40, 0),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = P.Sub,
		Font = Enum.Font.GothamMedium,
		TextSize = fs(11),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, btn)

	local page = new("ScrollingFrame", {
		Name = id .. "Page",
		Size = UDim2.new(1, -32, 1, -16),
		Position = UDim2.fromOffset(16, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = P.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, content)
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, page)

	btn.MouseEnter:Connect(function()
		if currentTab ~= id then
			tween(btn, 0.15, { BackgroundColor3 = P.Panel })
		end
	end)
	btn.MouseLeave:Connect(function()
		if currentTab ~= id then
			tween(btn, 0.15, { BackgroundColor3 = P.Sidebar })
		end
	end)

	btn.MouseButton1Click:Connect(function() switchTab(id) end)

	tabs[id] = {
		button = btn, page = page, indicator = indicator,
		icon = iconLbl, label = textLbl, title = title,
	}

	return page
end

-- ============================================================
--  WIDGETS
-- ============================================================
local order = 0
local function nextOrder() order += 1; return order end

local function makeSection(parent, title, collapsible)
	local sec = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = P.Panel,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
	}, parent)
	corner(10, sec)
	stroke(P.Border, 1, sec)

	local HEADER_H = IS_MOBILE and 26 or 30
	local headerBtn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, sec)

	new("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = P.Accent,
		Font = Enum.Font.GothamBold,
		TextSize = fs(11),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, headerBtn)

	local chevron = new("TextLabel", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -24, 0.5, -10),
		BackgroundTransparency = 1,
		Text = "▾",
		TextColor3 = P.Sub,
		Font = Enum.Font.GothamBold,
		TextSize = fs(11),
	}, headerBtn)

	local body = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(0, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
	}, sec)
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, body)
	padding(body, 10)

	if collapsible then
		local collapsed = false
		headerBtn.MouseButton1Click:Connect(function()
			collapsed = not collapsed
			body.Visible = not collapsed
			chevron.Text = collapsed and "▸" or "▾"
			sec.AutomaticSize = collapsed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y
			sec.Size = collapsed and UDim2.new(1, 0, 0, HEADER_H) or UDim2.new(1, 0, 0, 0)
		end)
	end

	return body
end

local TOGGLE_ROW_H = IS_MOBILE and 38 or 42

local function makeToggle(parent, title, desc, default, callback)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, TOGGLE_ROW_H),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, parent)

	new("TextLabel", {
		Size = UDim2.new(1, -60, 0, 16),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = P.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = fs(12),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	if desc and desc ~= "" then
		new("TextLabel", {
			Size = UDim2.new(1, -60, 0, 14),
			Position = UDim2.fromOffset(0, 16),
			BackgroundTransparency = 1,
			Text = desc,
			TextColor3 = P.Sub,
			Font = Enum.Font.Gotham,
			TextSize = fs(10),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, holder)
	end

	local swW = IS_MOBILE and 38 or 42
	local swH = IS_MOBILE and 20 or 22
	local sw = new("TextButton", {
		Size = UDim2.fromOffset(swW, swH),
		Position = UDim2.new(1, -swW, 0.5, -swH / 2),
		BackgroundColor3 = default and P.Accent or P.PanelAlt,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, holder)
	corner(swH / 2, sw)
	stroke(P.Border, 1, sw)

	local knobS = swH - 6
	local knob = new("Frame", {
		Size = UDim2.fromOffset(knobS, knobS),
		Position = default and UDim2.new(1, -(knobS + 3), 0.5, -knobS / 2)
			or UDim2.new(0, 3, 0.5, -knobS / 2),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
	}, sw)
	corner(knobS / 2, knob)

	local state = default
	local function animate(on)
		tween(knob, 0.18, {
			Position = on and UDim2.new(1, -(knobS + 3), 0.5, -knobS / 2)
				or UDim2.new(0, 3, 0.5, -knobS / 2)
		})
		tween(sw, 0.18, {
			BackgroundColor3 = on and P.Accent or P.PanelAlt
		})
	end

	sw.MouseButton1Click:Connect(function()
		state = not state
		animate(state)
		if callback then callback(state) end
	end)

	return {
		set   = function(v) state = v; animate(v) end,
		get   = function() return state end,
		click = function()
			state = not state
			animate(state)
			if callback then callback(state) end
		end,
	}
end

local BTN_H = IS_MOBILE and 30 or 32

local function makeButton(parent, title, desc, variant, callback)
	local bgColor =
		variant == "danger"  and P.Bad or
		variant == "success" and P.Good or
		variant == "ghost"   and P.PanelAlt or P.Accent

	local textColor = variant == "ghost" and P.Text or Color3.new(1, 1, 1)

	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, BTN_H),
		BackgroundColor3 = bgColor,
		Text = title,
		TextColor3 = textColor,
		Font = Enum.Font.GothamBold,
		TextSize = fs(11),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
	}, parent)
	corner(6, btn)

	local hover = variant == "ghost" and P.Row or P.AccentDark
	btn.MouseEnter:Connect(function()
		tween(btn, 0.12, { BackgroundColor3 = hover })
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, 0.12, { BackgroundColor3 = bgColor })
	end)
	btn.MouseButton1Click:Connect(function()
		if callback then callback() end
	end)

	if desc and desc ~= "" then
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromOffset(2, BTN_H),
			BackgroundTransparency = 1,
			Text = desc,
			TextColor3 = P.Sub,
			Font = Enum.Font.Gotham,
			TextSize = fs(10),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder(),
		}, parent)
	end

	return btn
end

local function makeSlider(parent, title, min, max, default, callback)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, parent)

	new("TextLabel", {
		Size = UDim2.new(1, -60, 0, 16),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = P.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = fs(11),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local valLbl = new("TextLabel", {
		Size = UDim2.fromOffset(60, 16),
		Position = UDim2.new(1, -60, 0, 0),
		BackgroundTransparency = 1,
		Text = string.format("%.2f", default),
		TextColor3 = P.Accent,
		Font = Enum.Font.GothamBold,
		TextSize = fs(11),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, holder)

	local trackPad = new("Frame", {
		Size = UDim2.new(1, 0, 0, IS_MOBILE and 22 or 16),
		Position = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1,
	}, holder)

	local track = new("Frame", {
		Size = UDim2.new(1, 0, 0, 5),
		Position = UDim2.new(0, 0, 0.5, -2.5),
		BackgroundColor3 = P.PanelAlt,
		BorderSizePixel = 0,
	}, trackPad)
	corner(3, track)

	local fill = new("Frame", {
		Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = P.Accent,
		BorderSizePixel = 0,
	}, track)
	corner(3, fill)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new((default - min) / (max - min), -7, 0.5, -7),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, track)
	corner(7, knob)

	local dragging = false
	local function setVal(v)
		v = math.clamp(v, min, max)
		local alpha = (v - min) / (max - min)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, -7, 0.5, -7)
		valLbl.Text = (max - min > 5)
			and tostring(math.floor(v))
			or string.format("%.2f", v)
		if callback then callback(v) end
	end

	local function getFromInput(input)
		local rel = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		setVal(min + (max - min) * rel)
	end

	trackPad.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			getFromInput(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
			getFromInput(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return { set = setVal }
end

local function makeKeybind(parent, title, default, callback)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, parent)

	new("TextLabel", {
		Size = UDim2.new(1, -100, 1, 0),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = P.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = fs(12),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)

	local btn = new("TextButton", {
		Size = UDim2.fromOffset(90, 24),
		Position = UDim2.new(1, -90, 0.5, -12),
		BackgroundColor3 = P.PanelAlt,
		Text = default and default.Name or "None",
		TextColor3 = P.Text,
		Font = Enum.Font.GothamBold,
		TextSize = fs(11),
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, holder)
	corner(6, btn)
	stroke(P.Border, 1, btn)

	local binding = false
	local currentKey = default

	btn.MouseButton1Click:Connect(function()
		binding = true
		rebindingActive = true
		btn.Text = "Press key…"
		btn.TextColor3 = P.Accent
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if binding then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				binding = false
				rebindingActive = false
				currentKey = input.KeyCode
				btn.Text = currentKey.Name
				btn.TextColor3 = P.Text
				if callback then callback(currentKey) end
			end
			return
		end
	end)

	return {
		get = function() return currentKey end,
		set = function(k)
			currentKey = k
			btn.Text = k and k.Name or "None"
		end,
	}
end

local function makeParagraph(parent, text)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = P.Sub,
		Font = Enum.Font.Gotham,
		TextSize = fs(11),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LayoutOrder = nextOrder(),
	}, parent)
end

local function makeLabel(parent, text, color)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color or P.Sub,
		Font = Enum.Font.Gotham,
		TextSize = fs(11),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = nextOrder(),
	}, parent)
end

-- ============================================================
--  TAB 1 — HOME
-- ============================================================
local homePage = makeTab("home", "🏠", "Home")

local heroSec = makeSection(homePage, "Welcome")
makeParagraph(heroSec,
	"Florence Hub — Aim Assist v3 private test build. "
	.. "Drag the 🎯 button anywhere, tap it to open/close the window.")
makeLabel(heroSec, "🎯  Aim Assist — keybinds, wall check, target switching, FOV detection")
makeLabel(heroSec, "🔒  Lock-On — sticks to one target until lost or killed")
makeLabel(heroSec, "⌨️  E = aim • Q = switch • F = lock • M = window")

-- ============================================================
--  TAB 2 — AIM ASSIST
-- ============================================================
local aimPage = makeTab("aim", "🎯", "Aim Assist")

-- ----- Main toggles -----
local aimMainSec = makeSection(aimPage, "Main")

local aimToggleWidget = makeToggle(aimMainSec, "Toggle",
	"Master switch — runs the aim assist loop",
	settings.AimbotEnabled, function(state)
		settings.AimbotEnabled = state
		setStatus(state and "Aim Assist on" or "Aim Assist off",
			state and nil or "warn")
		notify("Aim Assist", state and "Enabled." or "Disabled.",
			state and "success" or "info", 2)
	end)

local lockToggleWidget = makeToggle(aimMainSec, "Target Lock",
	"Lock-On: stick to one target until it dies or breaks line-of-sight",
	settings.TargetLockEnabled, function(state)
		settings.TargetLockEnabled = state
		-- Clear any existing lock when toggled
		lock.target = nil
		lock.lockedAt = 0
		lock.lostAt = nil
		notify("Lock-On", state and "Enabled." or "Disabled.",
			state and "lock" or "info", 2)
	end)

-- ----- Keybinds -----
local aimKbSec = makeSection(aimPage, "Keybinds", true)

if IS_MOBILE then
	makeParagraph(aimKbSec,
		"Keybinds are desktop-only. On mobile, tap the 🎯 floating button "
		.. "to toggle the window and use the on-screen switches.")
else
	makeKeybind(aimKbSec, "Toggle Aim", settings.AimKey,
		function(k) settings.AimKey = k end)

	makeKeybind(aimKbSec, "Switch Target", settings.SwitchKey,
		function(k) settings.SwitchKey = k end)

	makeKeybind(aimKbSec, "Lock-On", settings.LockKey,
		function(k) settings.LockKey = k end)

	makeToggle(aimKbSec, "Hold Mode",
		"When ON: hold the aim key. When OFF: press to toggle.",
		settings.HoldMode, function(v) settings.HoldMode = v end)

	makeParagraph(aimKbSec,
		"E toggles/holds the aim. Q cycles targets. F activates lock-on "
		.. "mode (grabs best target, sticks until broken).")
end

-- ----- Parameters -----
local aimParamsSec = makeSection(aimPage, "Parameters", true)

makeSlider(aimParamsSec, "FOV", 10, 500, settings.FOV, function(val)
	settings.FOV = val
end)

makeSlider(aimParamsSec, "Smoothness", 0.01, 1, settings.Smoothness, function(val)
	settings.Smoothness = val
end)

-- ----- Targeting -----
local aimTargetSec = makeSection(aimPage, "Targeting", true)

makeToggle(aimTargetSec, "Wall Check",
	"Ignore targets behind walls (raycast line-of-sight)",
	settings.WallCheck, function(v) settings.WallCheck = v end)

makeToggle(aimTargetSec, "FOV Detection",
	"Only target players inside the FOV circle",
	settings.FovDetection, function(v)
		settings.FovDetection = v
		notify("FOV Detection", v and "Enabled." or "Disabled.",
			v and "success" or "info", 2)
	end)

makeToggle(aimTargetSec, "Highlight Target",
	"Outline around the currently tracked target",
	settings.HighlightTarget, function(v) settings.HighlightTarget = v end)

-- Target sort cycle button
local sortModes = { "Crosshair", "Distance", "Health" }
local sortDesc = {
	Crosshair = "Closest to crosshair (screen center)",
	Distance  = "Closest by world distance",
	Health    = "Lowest health first",
}

local sortDescLbl
local sortBtn = makeButton(aimTargetSec, "Sort: " .. settings.TargetSort,
	nil, "ghost", function()
		local i = 1
		for idx, m in ipairs(sortModes) do
			if m == settings.TargetSort then i = idx end
		end
		i = (i % #sortModes) + 1
		settings.TargetSort = sortModes[i]
		sortBtn.Text = "Sort: " .. settings.TargetSort
		if sortDescLbl then sortDescLbl.Text = sortDesc[settings.TargetSort] end
		notify("Target Sort", "Now sorting by " .. settings.TargetSort,
			"info", 2)
	end)

sortDescLbl = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Text = sortDesc[settings.TargetSort],
	TextColor3 = P.Sub,
	Font = Enum.Font.Gotham,
	TextSize = fs(10),
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = nextOrder(),
}, aimTargetSec)

-- ----- Lock-On Config -----
local aimLockSec = makeSection(aimPage, "Lock-On Settings", true)

makeSlider(aimLockSec, "Max Lock Distance", 50, 2000, settings.LockDistance, function(v)
	settings.LockDistance = v
end)

makeSlider(aimLockSec, "Lock Grace (s)", 0, 1, settings.LockGrace, function(v)
	settings.LockGrace = v
end)

makeParagraph(aimLockSec,
	"Max Lock Distance drops a lock if the target moves further than this. "
	.. "Lock Grace holds the lock briefly when line-of-sight or FOV is "
	.. "momentarily broken (walking behind a pole, edge of circle) before "
	.. "the lock releases.")

-- ----- Status -----
local aimStatusSec = makeSection(aimPage, "Status", true)
local aimStatusLbl  = makeLabel(aimStatusSec, "● Idle.", P.Sub)
local aimTargetLbl  = makeLabel(aimStatusSec, "Target: —", P.Muted)
local aimListLbl    = makeLabel(aimStatusSec, "Valid targets: 0", P.Muted)
local aimLockLbl    = makeLabel(aimStatusSec, "Lock: —", P.Muted)
local aimFovLbl     = makeLabel(aimStatusSec, "FOV: 150  •  Smooth: 0.15", P.Muted)

local aimInfoSec = makeSection(aimPage, "Info", true)
makeParagraph(aimInfoSec,
	"Aim Assist picks the best target each frame. Lock-On picks one target "
	.. "and sticks to it — it only releases if the target dies, is destroyed, "
	.. "goes out of range, or loses line-of-sight for longer than the grace "
	.. "period. Use the Switch Target key to cycle candidates.")

-- ============================================================
--  TAB 3 — SETTINGS
-- ============================================================
local settingsPage = makeTab("settings", "⚙️", "Settings")

local kbSec = makeSection(settingsPage, "Window Keybind")
if IS_MOBILE then
	makeParagraph(kbSec, "Tap the 🎯 button to toggle the window.")
else
	makeParagraph(kbSec, "Press M to open or close the window.")
end

local aboutSec = makeSection(settingsPage, "About")
makeParagraph(aboutSec,
	"Florence Hub — Aim Assist v3. Private test build. Adds full lock-on "
	.. "logic: acquire on toggle, hold across soft failures with a grace "
	.. "window, auto-release on hard failures (death/destruction).")

-- ============================================================
--  FOV CIRCLE + TARGET HIGHLIGHT
-- ============================================================
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5
fovCircle.NumSides = 64
fovCircle.Radius = settings.FOV
fovCircle.Filled = false
fovCircle.Transparency = 0.8
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Visible = false

local targetHighlight = Instance.new("Highlight")
targetHighlight.Name = "AimTargetHighlight"
targetHighlight.FillColor = Color3.fromRGB(255, 80, 80)
targetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
targetHighlight.FillTransparency = 0.55
targetHighlight.OutlineTransparency = 0
targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
targetHighlight.Enabled = false
targetHighlight.Parent = gui

-- ============================================================
--  TARGETING HELPERS
-- ============================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasLineOfSight(targetPart)
	if not settings.WallCheck then return true end
	local origin = Camera.CFrame.Position
	local targetPos = targetPart.Position
	local dir = targetPos - origin

	rayParams.FilterDescendantsInstances = { LocalPlayer.Character, Camera }
	local result = workspace:Raycast(origin, dir, rayParams)

	if not result then return true end
	return result.Instance:IsDescendantOf(targetPart.Parent)
end

local function buildTargetList()
	local list = {}
	local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end
		local char = player.Character
		if not char then continue end

		local part = char:FindFirstChild(settings.AimPart)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not part or not humanoid or humanoid.Health <= 0 then continue end

		local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
		local crosshairDist = math.huge

		if onScreen then
			crosshairDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
		end

		if settings.FovDetection then
			if not onScreen or crosshairDist > settings.FOV then
				continue
			end
		end

		if settings.WallCheck and not hasLineOfSight(part) then
			continue
		end

		table.insert(list, {
			part          = part,
			character     = char,
			player        = player,
			humanoid      = humanoid,
			crosshairDist = crosshairDist,
			worldDist     = (part.Position - Camera.CFrame.Position).Magnitude,
			health        = humanoid.Health,
		})
	end

	if settings.TargetSort == "Distance" then
		table.sort(list, function(a, b) return a.worldDist < b.worldDist end)
	elseif settings.TargetSort == "Health" then
		table.sort(list, function(a, b) return a.health < b.health end)
	else
		table.sort(list, function(a, b) return a.crosshairDist < b.crosshairDist end)
	end

	return list
end

-- ============================================================
--  LOCK-ON LOGIC
-- ============================================================
-- Hard failures: release immediately
local function lockHardFail(entry)
	if not entry then return true end
	if not entry.part or not entry.part.Parent then return true end
	if not entry.character or not entry.character.Parent then return true end
	if not entry.humanoid or entry.humanoid.Health <= 0 then return true end
	return false
end

-- Soft failures: allow a grace window before releasing
local function lockSoftFail(entry)
	if not entry or not entry.part then return true end
	local dist = (entry.part.Position - Camera.CFrame.Position).Magnitude
	if dist > settings.LockDistance then return true end
	if settings.WallCheck and not hasLineOfSight(entry.part) then return true end
	return false
end

local function releaseLock(reason)
	if not lock.target then return end
	local name = lock.target.player.Name
	lock.target   = nil
	lock.lockedAt = 0
	lock.lostAt   = nil
	if reason then
		notify("Lock-On", "Released " .. name .. " — " .. reason, "warn", 1.8)
	end
end

local function acquireLock(list)
	if #list == 0 then return nil end
	local idx = math.clamp(runtime.targetIndex, 1, #list)
	local entry = list[idx]
	lock.target   = entry
	lock.lockedAt = tick()
	lock.lostAt   = nil
	notify("Lock-On", "Locked onto " .. entry.player.Name, "lock", 1.5)
	return entry
end

-- Refresh the current lock's live fields from the newest list build.
-- If the locked character is still in the list, use that fresh entry so
-- crosshairDist / worldDist / health values stay current.
local function refreshLockEntry(list)
	if not lock.target then return end
	local char = lock.target.character
	for _, e in ipairs(list) do
		if e.character == char then
			-- Keep the reference but update fields
			lock.target.crosshairDist = e.crosshairDist
			lock.target.worldDist     = e.worldDist
			lock.target.health        = e.health
			lock.target.part          = e.part
			lock.target.humanoid      = e.humanoid
			return
		end
	end
end

-- ============================================================
--  GLOBAL INPUT
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or rebindingActive then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == settings.AimKey then
		if settings.HoldMode then
			runtime.keyHeld = true
			setStatus("Aim held", nil)
		else
			aimToggleWidget.click()
		end
	elseif input.KeyCode == settings.SwitchKey then
		runtime.switchPending = true
	elseif input.KeyCode == settings.LockKey then
		-- Toggle lock-on mode
		lockToggleWidget.click()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == settings.AimKey and settings.HoldMode then
		runtime.keyHeld = false
	end
end)

-- ============================================================
--  MAIN LOOP
-- ============================================================
local function isAimActive()
	if settings.HoldMode and runtime.keyHeld then return true end
	return settings.AimbotEnabled
end

RunService.RenderStepped:Connect(function()
	local aimActive  = isAimActive()
	local lockActive = settings.TargetLockEnabled

	-- FOV circle
	local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	fovCircle.Position = center
	fovCircle.Radius = settings.FOV
	fovCircle.Visible = (aimActive or lockActive) and settings.FovDetection

	aimFovLbl.Text = string.format("FOV: %d  •  Smooth: %.2f",
		settings.FOV, settings.Smoothness)

	-- Idle state
	if not aimActive and not lockActive then
		targetHighlight.Enabled = false
		aimStatusLbl.Text = "● Idle."
		aimStatusLbl.TextColor3 = P.Sub
		aimTargetLbl.Text = "Target: —"
		aimListLbl.Text = "Valid targets: 0"
		aimLockLbl.Text = "Lock: —"
		aimLockLbl.TextColor3 = P.Muted
		releaseLock(nil)
		return
	end

	-- Build the list of currently valid targets
	local list = buildTargetList()
	aimListLbl.Text = "Valid targets: " .. #list

	-- Handle switch request
	if runtime.switchPending then
		runtime.switchPending = false
		if #list > 0 then
			runtime.targetIndex = (runtime.targetIndex % #list) + 1
		end
		-- If locked, force a release so the next frame re-acquires
		if lockActive and lock.target then
			releaseLock("switched")
		end
		setStatus("Target switched", nil)
	end

	-- Decide the active target
	local activeTarget

	if lockActive then
		-- --- LOCK-ON MODE ---
		-- 1. Try to keep the existing lock alive
		if lock.target then
			if lockHardFail(lock.target) then
				releaseLock("target lost")
			else
				refreshLockEntry(list)

				if lockSoftFail(lock.target) then
					-- Start the grace timer if it's not running
					if not lock.lostAt then lock.lostAt = tick() end
					local elapsed = tick() - lock.lostAt
					if elapsed > settings.LockGrace then
						releaseLock("out of sight")
					else
						-- Grace: keep aiming at the last known position
						activeTarget = lock.target
					end
				else
					-- Recovered
					lock.lostAt = nil
					activeTarget = lock.target
				end
			end
		end

		-- 2. If still no target, acquire one from the current list
		if not activeTarget and not lock.target and #list > 0 then
			activeTarget = acquireLock(list)
		end

		-- --- Lock status label ---
		if lock.target then
			local held = tick() - lock.lockedAt
			aimLockLbl.Text = string.format("Lock: %s  (%.1fs)",
				lock.target.player.Name, held)
			aimLockLbl.TextColor3 = lock.lostAt and P.Warn or P.Lock
		else
			aimLockLbl.Text = "Lock: acquiring…"
			aimLockLbl.TextColor3 = P.Sub
		end

	else
		-- --- REGULAR AIM MODE ---
		if #list == 0 then
			runtime.targetIndex = 1
		else
			runtime.targetIndex = math.clamp(runtime.targetIndex, 1, #list)
			activeTarget = list[runtime.targetIndex]
		end

		aimLockLbl.Text = "Lock: —"
		aimLockLbl.TextColor3 = P.Muted
	end

	-- No target this frame
	if not activeTarget then
		targetHighlight.Enabled = false
		aimStatusLbl.Text = "● Searching…"
		aimStatusLbl.TextColor3 = P.Warn
		aimTargetLbl.Text = "Target: —"
		return
	end

	-- Highlight
	if settings.HighlightTarget then
		targetHighlight.Adornee = activeTarget.character
		targetHighlight.Enabled = true
		-- Tint differently when locked
		if lockActive and lock.target then
			targetHighlight.FillColor      = P.Lock
			targetHighlight.OutlineColor   = Color3.fromRGB(255, 220, 140)
		else
			targetHighlight.FillColor      = Color3.fromRGB(255, 80, 80)
			targetHighlight.OutlineColor   = Color3.fromRGB(255, 255, 255)
		end
	else
		targetHighlight.Enabled = false
	end

	-- Status
	if lockActive and lock.target then
		aimStatusLbl.Text = lock.lostAt and "● Lock (grace)" or "● Locked"
		aimStatusLbl.TextColor3 = lock.lostAt and P.Warn or P.Lock
	else
		aimStatusLbl.Text = "● Tracking"
		aimStatusLbl.TextColor3 = P.Good
	end
	aimTargetLbl.Text = string.format("Target: %s  [%d/%d]",
		activeTarget.player.Name, runtime.targetIndex, math.max(#list, 1))

	-- Aim
	local currentCFrame = Camera.CFrame
	local desiredCFrame = CFrame.new(currentCFrame.Position, activeTarget.part.Position)
	Camera.CFrame = currentCFrame:Lerp(desiredCFrame, settings.Smoothness)
end)

-- ============================================================
--  WINDOW DRAG
-- ============================================================
do
	local dragging, dragStart, startPos
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = win.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			win.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

-- ============================================================
--  WINDOW KEYBIND (M)
-- ============================================================
if not IS_MOBILE then
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or rebindingActive then return end
		if input.KeyCode == Enum.KeyCode.M then
			win.Visible = not win.Visible
		end
	end)
end

-- ============================================================
--  MINIMIZE / BOOT
-- ============================================================
local minimized = false
local fullH = WIN_H

minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	win.Size = UDim2.fromOffset(WIN_W, minimized and TITLE_H or fullH)
	for _, ch in ipairs(win:GetChildren()) do
		if ch ~= titleBar then ch.Visible = not minimized end
	end
end)

switchTab("home")
setStatus("Ready")

task.delay(0.4, function()
	notify("Florence Hub",
		IS_MOBILE and "Tap 🎯 to toggle. Drag it to move."
			or "E = aim • Q = switch • F = lock • M = window",
		"success", 4)
end)

print("[Florence Hub] Aim Assist v3 (Lock-On) loaded (" ..
	(IS_MOBILE and "mobile" or "desktop") .. ").")