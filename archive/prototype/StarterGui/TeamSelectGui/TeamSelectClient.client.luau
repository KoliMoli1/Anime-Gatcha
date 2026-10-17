local RS = game:GetService('ReplicatedStorage')
local UIS = game:GetService('UserInputService')
local gui = script.Parent
local panel = gui:WaitForChild('Panel')
local toggle = gui:WaitForChild('ToggleIcon')
local close = panel:WaitForChild('CloseButton')
local ownedList = panel:WaitForChild('OwnedList')
local slotsFrame = panel:WaitForChild('RosterSlots')
local statsLabel = panel:WaitForChild('Stats')
local status = panel:WaitForChild('Status')
local save = panel:WaitForChild('SaveButton')
local remotes = RS:WaitForChild('AnimeCombatCore'):WaitForChild('Remotes')
local getSnapshot = remotes:WaitForChild('GetTeamSelectSnapshot')
local setTeam = remotes:WaitForChild('SetSelectedTeam')
local defs = require(RS.AnimeCombatCore.Shared.CharacterDefinitions)
local team = {}
local owned = {}
local draggingId
local draggingCard
local draggingOriginalText
local dragStart
local moved
local ghost
local highlightedSlot
local lastPointerPosition = Vector2.zero

local function classOf(def)
    for class in pairs(def.Classes or {}) do return class end
    return 'Unknown'
end

local function showStats(id)
    local def = defs[id]
    local entry = owned[id]
    if not def then return end
    local s = def.BaseStats
    statsLabel.Text = string.format('%s\nRarity: %s   Class: %s\n\nHealth: %d\nAttack: %d\nDefense: %d\nSpeed: %d\nCrit Chance: %d%%\nCrit Damage: %.1fx\nOwned: %d', def.DisplayName, tostring(def.Rarity), classOf(def), s.MaxHealth, s.Attack, s.Defense, s.Speed, math.floor((s.CritChance or 0) * 100), s.CritDamage or 0, entry and entry.Count or 1)
end

local function slotIndexAt(position)
    for i = 1, 3 do
        local slot = slotsFrame:FindFirstChild('Slot'..i)
        local p, z = slot.AbsolutePosition, slot.AbsoluteSize
        if position.X >= p.X and position.X <= p.X + z.X and position.Y >= p.Y and position.Y <= p.Y + z.Y then return i end
    end
end

local function renderSlots()
    for i = 1, 3 do
        local slot = slotsFrame:FindFirstChild('Slot'..i)
        local id = team[i]
        if id and owned[id] then
            local def = defs[id]
            slot.Text = string.format('SLOT %d\n%s\n[%s]', i, def.DisplayName, classOf(def))
            slot.BackgroundColor3 = Color3.fromRGB(43, 75, 105)
        else
            slot.Text = 'SLOT '..i..'\nDrop Character Here'
            slot.BackgroundColor3 = Color3.fromRGB(29, 36, 58)
        end
    end
end

local function findTeamIndex(id)
    for i = 1, 3 do
        if team[i] == id then return i end
    end
end

local function placeCharacter(id, index)
    local currentIndex = findTeamIndex(id)
    if currentIndex and currentIndex ~= index then
        team[currentIndex], team[index] = team[index], team[currentIndex]
        status.Text = 'Roster reordered: '..(defs[id] and defs[id].DisplayName or id)..' moved to Slot '..index..'.'
        status.TextColor3 = Color3.fromRGB(150, 220, 255)
        return true
    end
    if team[index] and team[index] ~= id then
        status.Text = 'Slot '..index..' is occupied. Drag a roster character to reorder, or use an empty slot.'
        status.TextColor3 = Color3.fromRGB(255, 210, 100)
        return false
    end
    team[index] = id
    status.Text = 'Character placed in Slot '..index..'.'
    status.TextColor3 = Color3.fromRGB(150, 220, 170)
    return true
end

local function finishDrag(position)
    if not draggingId then return end
    local id = draggingId
    if ghost then ghost:Destroy(); ghost = nil end
    highlightedSlot = nil
    if moved then
        local index = slotIndexAt(position)
        if index then
            placeCharacter(id, index)
        else
            status.Text = 'Drop the character onto Slot 1, Slot 2, or Slot 3.'
            status.TextColor3 = Color3.fromRGB(255, 210, 100)
        end
        renderSlots()
    end
    if draggingCard then
        draggingCard.BackgroundColor3 = Color3.fromRGB(38, 48, 73)
        draggingCard.Text = draggingOriginalText
    end
    draggingId = nil
    draggingCard = nil
    draggingOriginalText = nil
    moved = false
end

local function beginDrag(card, id, input)
    draggingId = id
    draggingCard = card
    draggingOriginalText = card.Text
    dragStart = input.Position
    moved = false
    status.Text = 'Dragging '..(defs[id] and defs[id].DisplayName or id)..' — move it into a roster slot.'
    status.TextColor3 = Color3.fromRGB(255, 220, 110)
    card.BackgroundColor3 = Color3.fromRGB(85, 125, 185)
    card.Text = 'DRAGGING...\n'..(defs[id] and defs[id].DisplayName or id)
    for i = 1, 3 do
        local slot = slotsFrame:FindFirstChild('Slot'..i)
        if team[i] then
            slot.BackgroundColor3 = Color3.fromRGB(55, 70, 105)
            slot.Text = 'SWAP WITH\nSLOT '..i
        else
            slot.BackgroundColor3 = Color3.fromRGB(50, 100, 145)
            slot.Text = 'DROP HERE\nSLOT '..i
        end
    end
end

ownedList.ChildAdded:Connect(function(child)
    if child:IsA('TextButton') then
        child.InputChanged:Connect(function(input)
            if draggingId and input.UserInputType == Enum.UserInputType.MouseMovement then end
        end)
    end
end)

UIS.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        lastPointerPosition = input.Position
    end
    if draggingId and input.UserInputType == Enum.UserInputType.MouseMovement then
        if (input.Position - dragStart).Magnitude > 6 then
            moved = true
            if not ghost then
                ghost = Instance.new('TextLabel')
                ghost.Size = UDim2.fromOffset(draggingCard.AbsoluteSize.X, draggingCard.AbsoluteSize.Y)
                ghost.BackgroundColor3 = Color3.fromRGB(65, 115, 165)
                ghost.TextColor3 = Color3.new(1,1,1)
                ghost.Text = draggingCard.Text
                ghost.TextWrapped = true
                ghost.Font = Enum.Font.GothamBold
                ghost.TextSize = 13
                ghost.ZIndex = 20
                ghost.Parent = gui
                Instance.new('UICorner', ghost).CornerRadius = UDim.new(0, 8)
            end
            ghost.Position = UDim2.fromOffset(input.Position.X - ghost.AbsoluteSize.X / 2, input.Position.Y - ghost.AbsoluteSize.Y / 2)
            local over = slotIndexAt(input.Position)
            if over ~= highlightedSlot then
                highlightedSlot = over
                for i = 1, 3 do
                    local slot = slotsFrame:FindFirstChild('Slot'..i)
                    if i == over then
                        slot.BackgroundColor3 = Color3.fromRGB(75, 125, 175)
                        slot.Text = 'RELEASE TO PLACE\nSLOT '..i
                    elseif team[i] then
                        slot.BackgroundColor3 = Color3.fromRGB(43, 75, 105)
                    else
                        slot.BackgroundColor3 = Color3.fromRGB(29, 36, 58)
                    end
                end
            end
            if over then
                status.Text = 'Release to place '..(defs[draggingId] and defs[draggingId].DisplayName or draggingId)..' in Slot '..over..'.'
            else
                status.Text = 'Dragging '..(defs[draggingId] and defs[draggingId].DisplayName or draggingId)..' — move over a roster slot.'
            end
            status.TextColor3 = Color3.fromRGB(255, 220, 110)
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local position = lastPointerPosition
        if position == Vector2.zero then position = UIS:GetMouseLocation() end
        finishDrag(position)
    end
end)

local function render()
    for _, child in ipairs(ownedList:GetChildren()) do if child:IsA('TextButton') then child:Destroy() end end
    for id, entry in pairs(owned) do
        local def = defs[id]
        if def then
            local card = Instance.new('TextButton')
            card.Name = id
            card.Size = UDim2.new(1, -14, 0, 58)
            card.BackgroundColor3 = Color3.fromRGB(38, 48, 73)
            card.TextColor3 = Color3.fromRGB(235, 240, 250)
            card.Text = string.format('%s\n%s  •  Owned ×%d', def.DisplayName, classOf(def), entry.Count)
            card.TextWrapped = true
            card.Font = Enum.Font.GothamBold
            card.TextSize = 13
            card.Parent = ownedList
            Instance.new('UICorner', card).CornerRadius = UDim.new(0, 7)
            card.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then beginDrag(card, id, input) end
            end)
            card.Activated:Connect(function()
                if not moved then showStats(id) end
            end)
        end
    end
    ownedList.CanvasSize = UDim2.fromOffset(0, ownedList.UIListLayout.AbsoluteContentSize.Y + 16)
    renderSlots()
end

for i = 1, 3 do
    local slot = slotsFrame:FindFirstChild('Slot'..i)
    slot.Activated:Connect(function()
        if team[i] then
            team[i] = nil
            status.Text = 'Slot '..i..' cleared.'
            status.TextColor3 = Color3.fromRGB(180, 190, 210)
            renderSlots()
        end
    end)
end

toggle.Activated:Connect(function() panel.Visible = true; toggle.Visible = false end)
close.Activated:Connect(function() panel.Visible = false; toggle.Visible = true end)
save.Activated:Connect(function()
    if not team[1] or not team[2] or not team[3] then
        status.Text = 'Fill all three roster slots before saving.'
        status.TextColor3 = Color3.fromRGB(255, 210, 100)
        return
    end
    if team[1] == team[2] or team[1] == team[3] or team[2] == team[3] then
        status.Text = 'Duplicate characters are not allowed in one team.'
        status.TextColor3 = Color3.fromRGB(255, 110, 110)
        return
    end
    local result = setTeam:InvokeServer(team)
    if result.success then
        status.Text = '3v3 roster saved to your profile.'
        status.TextColor3 = Color3.fromRGB(150, 240, 170)
    else
        status.Text = result.message or 'Unable to save team.'
        status.TextColor3 = Color3.fromRGB(255, 110, 110)
    end
end)

panel.Visible = false
toggle.Visible = true
local snapshot = getSnapshot:InvokeServer()
for _, entry in ipairs(snapshot.OwnedCharacters or {}) do owned[entry.Id] = entry end
for i = 1, 3 do team[i] = snapshot.SelectedTeam and snapshot.SelectedTeam[i] end
render()
