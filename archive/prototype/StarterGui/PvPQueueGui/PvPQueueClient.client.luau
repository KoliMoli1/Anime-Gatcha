local RS = game:GetService('ReplicatedStorage')
local gui = script.Parent
local panel = gui:WaitForChild('Panel')
local status = panel:WaitForChild('Status')
local button = panel:WaitForChild('QueueButton')
local remotes = RS:WaitForChild('AnimeCombatCore'):WaitForChild('Remotes')
local getSnapshot = remotes:WaitForChild('GetPvPQueueSnapshot')
local joinQueue = remotes:WaitForChild('JoinPvPQueue')
local leaveQueue = remotes:WaitForChild('LeavePvPQueue')
local updated = remotes:WaitForChild('PvPQueueUpdated')
local found = remotes:WaitForChild('PvPMatchFound')
local function render(s)
    status.Text = s.Status or 'Ready.'
    if s.OpponentName then status.Text = 'MATCH FOUND: '..s.OpponentName..'\n'..(s.Status or '') end
    button.Text = s.InQueue and 'CANCEL SEARCH' or (s.MatchId and 'MATCH READY' or 'FIND OPPONENT')
    button.BackgroundColor3 = s.InQueue and Color3.fromRGB(155, 85, 75) or Color3.fromRGB(55, 125, 210)
    button.Active = not s.MatchId
end
button.Activated:Connect(function()
    if button.Text == 'CANCEL SEARCH' then render(leaveQueue:InvokeServer()) else render(joinQueue:InvokeServer()) end
end)
updated.OnClientEvent:Connect(render)
found.OnClientEvent:Connect(function(data) render({MatchId=data.MatchId, OpponentName=data.OpponentName, Status=data.Status}) end)
render(getSnapshot:InvokeServer())
