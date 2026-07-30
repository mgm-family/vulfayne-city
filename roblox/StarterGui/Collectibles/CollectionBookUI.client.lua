-- StarterGui/Collectibles/CollectionBookUI.client.lua
-- "図鑑" (album) UI shared by all three collection systems. Tabs switch
-- between シール / オーパーツ / 骨董品; arrows flip through the 10 sheets
-- of the active category; each sheet shows its 9 slots in a 3x3 grid.
-- Hovering highlights a slot; clicking it opens a large preview with the
-- item's image + description (or a "???" placeholder if not yet owned).
-- Press [C] or the corner button to toggle. Toast popups fire regardless
-- of whether the book is open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local ClientState = require(ReplicatedStorage.Collectibles.ClientState)

local CATEGORIES = {
	require(ReplicatedStorage.Collectibles.SealData),
	require(ReplicatedStorage.Collectibles.OopartData),
	require(ReplicatedStorage.Collectibles.AntiqueData),
}

local COLOR_BG = Color3.fromRGB(20, 17, 9)
local COLOR_PANEL = Color3.fromRGB(40, 34, 20)
local COLOR_PANEL_DIM = Color3.fromRGB(26, 22, 13)
local COLOR_GOLD = Color3.fromRGB(201, 162, 39)
local COLOR_TEXT = Color3.fromRGB(234, 226, 205)
local COLOR_TEXT_DIM = Color3.fromRGB(190, 180, 150)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------

local activeCategoryIndex = 1
local activeSheetIndex = 1
local bookOpen = false

--------------------------------------------------------------------------
-- gui scaffold
--------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CollectionBookGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- toggle button ----------------------------------------------------------

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.AnchorPoint = Vector2.new(1, 1)
toggleButton.Position = UDim2.new(1, -20, 1, -20)
toggleButton.Size = UDim2.new(0, 110, 0, 44)
toggleButton.BackgroundColor3 = COLOR_BG
toggleButton.BorderSizePixel = 0
toggleButton.Text = "図鑑 [C]"
toggleButton.TextColor3 = COLOR_TEXT
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.TextSize = 18
toggleButton.Parent = screenGui
Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0, 8)
do
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_GOLD
	stroke.Thickness = 1.5
	stroke.Parent = toggleButton
end

-- toast --------------------------------------------------------------

local toastHolder = Instance.new("Frame")
toastHolder.Name = "ToastHolder"
toastHolder.AnchorPoint = Vector2.new(0.5, 0)
toastHolder.Position = UDim2.new(0.5, 0, 0, 20)
toastHolder.Size = UDim2.new(0, 440, 0, 320)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 8)
toastLayout.Parent = toastHolder

local function showToast(text)
	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.new(1, 0, 0, 44)
	toast.BackgroundColor3 = COLOR_BG
	toast.BackgroundTransparency = 0.1
	toast.TextColor3 = COLOR_TEXT
	toast.Font = Enum.Font.SourceSansBold
	toast.TextSize = 16
	toast.Text = text
	toast.TextWrapped = true
	toast.Parent = toastHolder
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_GOLD
	stroke.Thickness = 1
	stroke.Parent = toast

	task.delay(4, function()
		local tween = TweenService:Create(toast, TweenInfo.new(0.5), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		stroke:Destroy()
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

-- main book frame ----------------------------------------------------------

local book = Instance.new("Frame")
book.Name = "Book"
book.AnchorPoint = Vector2.new(0.5, 0.5)
book.Position = UDim2.new(0.5, 0, 0.5, 0)
book.Size = UDim2.new(0, 680, 0, 620)
book.BackgroundColor3 = COLOR_BG
book.BorderSizePixel = 0
book.Visible = false
book.Parent = screenGui
Instance.new("UICorner", book).CornerRadius = UDim.new(0, 12)
do
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_GOLD
	stroke.Thickness = 2
	stroke.Parent = book
end

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.BackgroundColor3 = COLOR_PANEL
closeButton.Text = "×"
closeButton.TextColor3 = COLOR_TEXT
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 22
closeButton.Parent = book
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 6)

-- tabs --------------------------------------------------------------

local tabHolder = Instance.new("Frame")
tabHolder.Name = "Tabs"
tabHolder.Position = UDim2.new(0, 16, 0, 12)
tabHolder.Size = UDim2.new(1, -64, 0, 36)
tabHolder.BackgroundTransparency = 1
tabHolder.Parent = book

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabHolder

local tabButtons = {}

-- sheet header --------------------------------------------------------

local header = Instance.new("Frame")
header.Name = "Header"
header.Position = UDim2.new(0, 16, 0, 58)
header.Size = UDim2.new(1, -32, 0, 60)
header.BackgroundTransparency = 1
header.Parent = book

local prevButton = Instance.new("TextButton")
prevButton.Size = UDim2.new(0, 40, 0, 40)
prevButton.BackgroundColor3 = COLOR_PANEL
prevButton.Text = "◀"
prevButton.TextColor3 = COLOR_TEXT
prevButton.Font = Enum.Font.SourceSansBold
prevButton.TextSize = 22
prevButton.Parent = header
Instance.new("UICorner", prevButton).CornerRadius = UDim.new(0, 6)

local nextButton = Instance.new("TextButton")
nextButton.Size = UDim2.new(0, 40, 0, 40)
nextButton.AnchorPoint = Vector2.new(1, 0)
nextButton.Position = UDim2.new(1, 0, 0, 0)
nextButton.BackgroundColor3 = COLOR_PANEL
nextButton.Text = "▶"
nextButton.TextColor3 = COLOR_TEXT
nextButton.Font = Enum.Font.SourceSansBold
nextButton.TextSize = 22
nextButton.Parent = header
Instance.new("UICorner", nextButton).CornerRadius = UDim.new(0, 6)

local sheetTitle = Instance.new("TextLabel")
sheetTitle.Position = UDim2.new(0, 50, 0, 0)
sheetTitle.Size = UDim2.new(1, -100, 0, 24)
sheetTitle.BackgroundTransparency = 1
sheetTitle.Font = Enum.Font.SourceSansBold
sheetTitle.TextSize = 20
sheetTitle.TextColor3 = COLOR_TEXT
sheetTitle.TextXAlignment = Enum.TextXAlignment.Center
sheetTitle.Parent = header

local sheetStatus = Instance.new("TextLabel")
sheetStatus.Position = UDim2.new(0, 50, 0, 26)
sheetStatus.Size = UDim2.new(1, -100, 0, 22)
sheetStatus.BackgroundTransparency = 1
sheetStatus.Font = Enum.Font.SourceSans
sheetStatus.TextSize = 15
sheetStatus.TextColor3 = COLOR_GOLD
sheetStatus.TextXAlignment = Enum.TextXAlignment.Center
sheetStatus.Parent = header

-- 3x3 grid --------------------------------------------------------------

local CELL_SIZE, CELL_PAD = 150, 10
local GRID_WIDTH = CELL_SIZE * 3 + CELL_PAD * 2

local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.AnchorPoint = Vector2.new(0.5, 0)
grid.Position = UDim2.new(0.5, 0, 0, 130)
grid.Size = UDim2.new(0, GRID_WIDTH, 0, CELL_SIZE * 3 + CELL_PAD * 2)
grid.BackgroundTransparency = 1
grid.Parent = book

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellPadding = UDim2.new(0, CELL_PAD, 0, CELL_PAD)
gridLayout.CellSize = UDim2.new(0, CELL_SIZE, 0, CELL_SIZE)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

-- parallel arrays: slot index -> gui refs / current data
local slotFrames, slotImages, slotLabels = {}, {}, {}
local slotItems, slotOwned = {}, {}

-- detail modal ------------------------------------------------------------

local modal = Instance.new("Frame")
modal.Name = "DetailModal"
modal.Size = UDim2.new(1, 0, 1, 0)
modal.BackgroundColor3 = Color3.new(0, 0, 0)
modal.BackgroundTransparency = 0.4
modal.Active = true
modal.Visible = false
modal.ZIndex = 10
modal.Parent = screenGui

local modalCard = Instance.new("Frame")
modalCard.AnchorPoint = Vector2.new(0.5, 0.5)
modalCard.Position = UDim2.new(0.5, 0, 0.5, 0)
modalCard.Size = UDim2.new(0, 360, 0, 440)
modalCard.BackgroundColor3 = COLOR_BG
modalCard.ZIndex = 11
modalCard.Parent = modal
Instance.new("UICorner", modalCard).CornerRadius = UDim.new(0, 12)
do
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_GOLD
	stroke.Thickness = 2
	stroke.Parent = modalCard
end

local modalImage = Instance.new("ImageLabel")
modalImage.Position = UDim2.new(0, 20, 0, 20)
modalImage.Size = UDim2.new(1, -40, 0, 240)
modalImage.BackgroundColor3 = COLOR_PANEL
modalImage.ScaleType = Enum.ScaleType.Fit
modalImage.ZIndex = 11
modalImage.Parent = modalCard
Instance.new("UICorner", modalImage).CornerRadius = UDim.new(0, 8)

local modalName = Instance.new("TextLabel")
modalName.Position = UDim2.new(0, 20, 0, 270)
modalName.Size = UDim2.new(1, -40, 0, 30)
modalName.BackgroundTransparency = 1
modalName.Font = Enum.Font.SourceSansBold
modalName.TextSize = 22
modalName.TextColor3 = COLOR_TEXT
modalName.TextXAlignment = Enum.TextXAlignment.Left
modalName.ZIndex = 11
modalName.Parent = modalCard

local modalDesc = Instance.new("TextLabel")
modalDesc.Position = UDim2.new(0, 20, 0, 306)
modalDesc.Size = UDim2.new(1, -40, 0, 110)
modalDesc.BackgroundTransparency = 1
modalDesc.Font = Enum.Font.SourceSans
modalDesc.TextSize = 16
modalDesc.TextColor3 = COLOR_TEXT_DIM
modalDesc.TextWrapped = true
modalDesc.TextXAlignment = Enum.TextXAlignment.Left
modalDesc.TextYAlignment = Enum.TextYAlignment.Top
modalDesc.ZIndex = 11
modalDesc.Parent = modalCard

local modalClose = Instance.new("TextButton")
modalClose.AnchorPoint = Vector2.new(1, 0)
modalClose.Position = UDim2.new(1, -14, 0, 14)
modalClose.Size = UDim2.new(0, 30, 0, 30)
modalClose.BackgroundColor3 = COLOR_PANEL
modalClose.Text = "×"
modalClose.TextColor3 = COLOR_TEXT
modalClose.Font = Enum.Font.SourceSansBold
modalClose.TextSize = 20
modalClose.ZIndex = 12
modalClose.Parent = modalCard
Instance.new("UICorner", modalClose).CornerRadius = UDim.new(0, 6)

local function closeModal()
	modal.Visible = false
end

modalClose.MouseButton1Click:Connect(closeModal)
modal.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not modal.Visible then
		return
	end
	local pos, size = modalCard.AbsolutePosition, modalCard.AbsoluteSize
	local mouse = input.Position
	local inside = mouse.X >= pos.X and mouse.X <= pos.X + size.X and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y
	if not inside then
		closeModal()
	end
end)

local function openModal(item, owned)
	if owned then
		modalImage.Image = item.Image or ""
		modalName.Text = item.Name
		modalDesc.Text = item.Description
	else
		modalImage.Image = ""
		modalName.Text = "？？？"
		modalDesc.Text = "まだ手に入れていない。マップのどこかに隠されている。"
	end
	modal.Visible = true
end

--------------------------------------------------------------------------
-- rendering
--------------------------------------------------------------------------

local function activeData()
	return CATEGORIES[activeCategoryIndex]
end

local function refreshHeader()
	local data = activeData()
	local sheet = data.Sheets[activeSheetIndex]
	sheetTitle.Text = ("%s ― %d / %d"):format(sheet.Name, activeSheetIndex, #data.Sheets)

	local owned = 0
	for _, item in ipairs(sheet.Items) do
		if ClientState.IsOwned(data.CategoryId, item.Id) then
			owned += 1
		end
	end

	if owned >= #sheet.Items then
		if ClientState.IsClaimed(data.CategoryId, activeSheetIndex) then
			sheetStatus.Text = ("コンプリート！ 景品受け取り済み ― %s"):format(sheet.Reward.DisplayName)
		else
			sheetStatus.Text = "コンプリート！ NPCに話しかけて景品を受け取ろう"
		end
	else
		sheetStatus.Text = ("%d / %d 個収集済み"):format(owned, #sheet.Items)
	end
end

local function refreshGrid()
	local data = activeData()
	local sheet = data.Sheets[activeSheetIndex]

	for i, item in ipairs(sheet.Items) do
		local owned = ClientState.IsOwned(data.CategoryId, item.Id)

		if owned then
			slotFrames[i].BackgroundColor3 = COLOR_PANEL
			slotImages[i].Image = item.Image or ""
			slotImages[i].ImageTransparency = 0
			slotLabels[i].Text = item.Name
			slotLabels[i].TextTransparency = 0
		else
			slotFrames[i].BackgroundColor3 = COLOR_PANEL_DIM
			slotImages[i].Image = ""
			slotImages[i].ImageTransparency = 1
			slotLabels[i].Text = "？？？"
			slotLabels[i].TextTransparency = 0.4
		end

		slotItems[i] = item
		slotOwned[i] = owned
	end

	refreshHeader()
end

local function refreshTabs()
	for i in ipairs(CATEGORIES) do
		local tabButton = tabButtons[i]
		if i == activeCategoryIndex then
			tabButton.BackgroundColor3 = COLOR_GOLD
			tabButton.TextColor3 = COLOR_BG
		else
			tabButton.BackgroundColor3 = COLOR_PANEL
			tabButton.TextColor3 = COLOR_TEXT
		end
	end
end

--------------------------------------------------------------------------
-- build tabs + slots
--------------------------------------------------------------------------

for i, data in ipairs(CATEGORIES) do
	local tabButton = Instance.new("TextButton")
	tabButton.Size = UDim2.new(0, 120, 1, 0)
	tabButton.BackgroundColor3 = COLOR_PANEL
	tabButton.Text = data.CategoryName
	tabButton.TextColor3 = COLOR_TEXT
	tabButton.Font = Enum.Font.SourceSansBold
	tabButton.TextSize = 16
	tabButton.LayoutOrder = i
	tabButton.Parent = tabHolder
	Instance.new("UICorner", tabButton).CornerRadius = UDim.new(0, 6)

	tabButton.MouseButton1Click:Connect(function()
		activeCategoryIndex = i
		activeSheetIndex = 1
		refreshTabs()
		refreshGrid()
	end)

	tabButtons[i] = tabButton
end

for i = 1, 9 do
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. i
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = COLOR_PANEL_DIM
	button.LayoutOrder = i
	button.Parent = grid
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

	local slotStroke = Instance.new("UIStroke")
	slotStroke.Color = Color3.fromRGB(90, 78, 45)
	slotStroke.Thickness = 1
	slotStroke.Parent = button

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.Position = UDim2.new(0, 8, 0, 8)
	image.Size = UDim2.new(1, -16, 1, -34)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -6)
	label.Size = UDim2.new(1, -8, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.TextSize = 13
	label.TextScaled = true
	label.TextColor3 = COLOR_TEXT
	label.Parent = button

	button.MouseEnter:Connect(function()
		slotStroke.Color = COLOR_GOLD
		slotStroke.Thickness = 2
	end)
	button.MouseLeave:Connect(function()
		slotStroke.Color = Color3.fromRGB(90, 78, 45)
		slotStroke.Thickness = 1
	end)
	button.MouseButton1Click:Connect(function()
		local item = slotItems[i]
		if item then
			openModal(item, slotOwned[i])
		end
	end)

	slotFrames[i] = button
	slotImages[i] = image
	slotLabels[i] = label
end

--------------------------------------------------------------------------
-- open/close + navigation
--------------------------------------------------------------------------

local function setBookOpen(open)
	bookOpen = open
	book.Visible = open
	if open then
		refreshTabs()
		refreshGrid()
	else
		closeModal()
	end
end

toggleButton.MouseButton1Click:Connect(function()
	setBookOpen(not bookOpen)
end)
closeButton.MouseButton1Click:Connect(function()
	setBookOpen(false)
end)

prevButton.MouseButton1Click:Connect(function()
	local data = activeData()
	activeSheetIndex -= 1
	if activeSheetIndex < 1 then
		activeSheetIndex = #data.Sheets
	end
	refreshGrid()
end)

nextButton.MouseButton1Click:Connect(function()
	local data = activeData()
	activeSheetIndex += 1
	if activeSheetIndex > #data.Sheets then
		activeSheetIndex = 1
	end
	refreshGrid()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.C then
		setBookOpen(not bookOpen)
	end
end)

--------------------------------------------------------------------------
-- server sync
--------------------------------------------------------------------------

ClientState.Init()

ClientState.OnUpdate(function(payload)
	if payload.Type == "ItemCollected" then
		showToast(("「%s」を手に入れた！"):format(payload.Name))
		if bookOpen and payload.CategoryId == activeData().CategoryId and payload.SheetIndex == activeSheetIndex then
			refreshGrid()
		end
	elseif payload.Type == "SheetCompleted" then
		showToast(("「%s」コンプリート！ NPCに話しかけよう"):format(payload.SheetName))
		if bookOpen then
			refreshHeader()
		end
	elseif payload.Type == "RewardGranted" then
		for _, entry in ipairs(payload.Granted) do
			showToast(("景品「%s」を受け取った！"):format(entry.Reward.DisplayName))
		end
		if bookOpen then
			refreshGrid()
		end
	elseif payload.Type == "Sync" or payload.Type == "InitialSync" then
		if bookOpen then
			refreshGrid()
		end
	end
end)
