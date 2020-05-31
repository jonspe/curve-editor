local ROOT = script

local CollectionService = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local StudioService = game:GetService("StudioService")

ChangeHistoryService:SetEnabled(true)

local Helper = require(script.Helper)
local Curve = require(script.Curve)
local GizmoToolbar = require(script.GizmoToolbar)
local GizmoDrag = require(script.GizmoDrag)
local GizmoAxis = require(script.GizmoAxis)

local Editor = {
	EditMode = false,
	SelectedCurves = {},
}

local function retrieveSettings()
	Editor.DrawAllCurves = plugin:GetSetting("DrawAllCurves") or true
	Editor.CurveFidelity = 12 or plugin:GetSetting("CurveFidelity") or 12
	Editor.CurveThickness = 0.5 or plugin:GetSetting("CurveThickness") or 0.5
	Editor.MovementMode = plugin:GetSetting("MovementMode") or "ViewPlane"
end

local function syncSettings()
	plugin:SetSetting("DrawAllCurves", Editor.DrawAllCurves)
	plugin:SetSetting("CurveFidelity", Editor.CurveFidelity)
	plugin:SetSetting("CurveThickness", Editor.CurveThickness)
	plugin:SetSetting("MovementMode", Editor.MovementMode)
end

retrieveSettings()

-- temp hack
Curve.setDisplaySettings(Editor)

local toolbar = plugin:CreateToolbar("Curve Tools")

local createCurveAction = plugin:CreatePluginAction("CreateCurveAction", "Create Curve", "Create a new curve", "rbxassetid://4459262762", true)
local makeRootAction = plugin:CreatePluginAction("MakeRootAction", "Make Root", "Make selected part a curve root", "rbxassetid://4459262762", true)
local editCurveAction = plugin:CreatePluginAction("EditCurveAction", "Edit Curve", "Edit selected curve", "rbxassetid://4459262762", true)
local extendCurveAction = plugin:CreatePluginAction("ExtendCurveAction", "Extend Curve", "Extend selected curve", "rbxassetid://4459262762", true)
local shortenCurveAction = plugin:CreatePluginAction("ShortenCurveAction", "Shorten Curve", "Shorten selected curve", "rbxassetid://4459262762", true)
local toggleLoopedAction = plugin:CreatePluginAction("ToggleCurveLoopedAction", "Toggle Curve Looped", "Toggle curve closed or open", "rbxassetid://4459262762", true)
local reverseCurveAction = plugin:CreatePluginAction("ReverseCurveAction", "Reverse Direction", "Reverse curve direction", "rbxassetid://4459262762", true)

local createCurveButton = toolbar:CreateButton("Create", "Create a new curve", "rbxassetid://4459262762")
local makeRootButton = toolbar:CreateButton("Make Root", "Make selected part a curve root", "rbxassetid://4459262762")
local editCurveButton = toolbar:CreateButton("Edit", "Edit selected curve", "rbxassetid://4459262762")
local extendCurveButton = toolbar:CreateButton("Extend", "Extend selected curve", "rbxassetid://4459262762")
local shortenCurveButton = toolbar:CreateButton("Shorten", "Shorten selected curve", "rbxassetid://4459262762")
local toggleLoopedButton = toolbar:CreateButton("Loop", "Toggle loop closed or open", "rbxassetid://4459262762")
local reverseCurveButton = toolbar:CreateButton("Reverse", "Reverse curve direction", "rbxassetid://4459262762")
createCurveButton.Enabled = true
makeRootButton.Enabled = false
editCurveButton.Enabled = false
extendCurveButton.Enabled = false
shortenCurveButton.Enabled = false
toggleLoopedButton.Enabled = false
reverseCurveButton.Enabled = false

local pluginMouse = plugin:GetMouse()
local gizmoToolbar = GizmoToolbar.new(plugin:CreateToolbar("Curve Gizmos"))
gizmoToolbar:addGizmo(GizmoDrag.new(pluginMouse))
gizmoToolbar:addGizmo(GizmoAxis.new(pluginMouse))


local function createNewCurveRoot()
	local root = ROOT.CurveRoot:Clone()
	root.CFrame = CFrame.new(
		Helper.roundVector3ToMultiple(
			workspace.CurrentCamera.CFrame * CFrame.new(0, 0, -20).p,
			1
		)
    )
    CollectionService:AddTag(root, "Curve")
	root.Parent = workspace --Selection:Get()[1] or workspace
	return root
end

local function makeCurveRoot(obj)
	if not obj:IsA("BasePart") then
		warn("Can't turn anything not BasePart into curve root")
		return
	end
	
	if CollectionService:HasTag(obj, "Curve") then
		warn("Selected object is already a curve")
		return
	end
	
	for _, attachment in pairs(ROOT.CurveRoot:GetChildren()) do
		local clone = attachment:Clone()
		clone.Parent = obj
	end
	CollectionService:AddTag(obj, "Curve")
	
	return obj
end


local function editButtonsLogic()
	if not Editor.EditMode then
		editCurveButton:SetActive(false)
		toggleLoopedButton:SetActive(false)
		toggleLoopedButton.Enabled = false
		extendCurveButton.Enabled = false
		shortenCurveButton.Enabled = false
		reverseCurveButton.Enabled = false
		return
	end
	
	-- in edit mode and curve is selected
	
	local curve = Editor.SelectedCurves[1]
	local success, controlPoints = curve:getControlPoints()
	if not success then return end
	
	local looped = curve:isLooped()
	
	editCurveButton.Enabled = true
	editCurveButton:SetActive(true)
	toggleLoopedButton.Enabled = true
	--toggleLoopedButton:SetActive(looped)
	extendCurveButton.Enabled = not looped
	shortenCurveButton.Enabled = (#controlPoints > 6) and (not looped)
	reverseCurveButton.Enabled = true
end

function enterEditMode()
	for _, curve in pairs(Editor.SelectedCurves) do
		curve:drawLine(true, true)
		curve:drawHandles(true, true)
	end
	
	Editor.EditMode = true
	plugin:Activate(true)
	
	editButtonsLogic()
end

function exitEditMode()
	Editor.SelectedControlPointIndex = nil
	Editor.EditMode = false
	
	for _, curve in pairs(Editor.SelectedCurves) do
		curve:drawLine(true, true)
		curve:drawHandles(false, false)
	end
	
	editButtonsLogic()
	plugin:Deactivate()
end

local function evaluateSelection()
	local items = Selection:Get()
	local rootSet = {}
	local selectedSet = {}
	
	-- mark potential curve roots
	for _, item in pairs(items) do
		if item:IsA("BasePart") and CollectionService:HasTag(item, "Curve") then
			rootSet[item] = true
		end
	end
	
	-- discard previously selected curves if deselected
	for index, curve in pairs(Editor.SelectedCurves) do
		if not rootSet[curve.root] then
			curve:cleanUp()
			Editor.SelectedCurves[index] = nil
		end
		selectedSet[curve.root] = true
	end
	
	-- find new selected curves and draw them, connect gizmo events
	for _, item in pairs(items) do
		if rootSet[item] and not selectedSet[item] then
			local curve = Curve.new(item)
			curve:drawLine(true, true)
			curve:drawHandles(false, false)
			
			for _, gizmo in pairs(gizmoToolbar:getGizmos()) do
				curve.controlPointPressed:Connect(function(...)
					gizmo:onControlPointPressed(...)
				end)
				curve.controlPointEnter:Connect(function(...)
					gizmo:onControlPointEnter(...)
				end)
				curve.controlPointLeave:Connect(function(...)
					gizmo:onControlPointLeave(...)
				end)
			end
			
			table.insert(Editor.SelectedCurves, curve)
		end
	end
	
	if #Editor.SelectedCurves > 0 then
		editCurveButton.Enabled = true
	else
		editCurveButton.Enabled = false
		if Editor.EditMode then
			exitEditMode()
		end
	end
	
	if #items == 1 and items[1]:IsA("BasePart") and not CollectionService:HasTag(items[1], "Curve") then
		makeRootButton.Enabled = true
	else
		makeRootButton.Enabled = false
	end
end

Selection.SelectionChanged:Connect(evaluateSelection)




--[[
	BUTTON FUNCTIONS BUTTON FUNCTIONS BUTTON FUNCTIONS BUTTON FUNCTIONS
	CTIONS BUTTON FUNCTIONS BUTTON FUNCTIONS BUTTON FUNCTIONS BUTTON FU
--]]




local function onCreateCurve()
	if not createCurveButton.Enabled then return end
	--createCurveButton:SetActive(false)
	
	ChangeHistoryService:SetWaypoint("Start Create Curve")
	Selection:Set{createNewCurveRoot()}
	exitEditMode()
	ChangeHistoryService:SetWaypoint("End Create Curve")
end

local function onMakeCurveRoot()
	if not makeRootButton.Enabled then return end
	local items = Selection:Get()
	if #items == 1 and items[1]:IsA("BasePart") then
		ChangeHistoryService:SetWaypoint("Start Make Curve Root")
		
		local root = makeCurveRoot(items[1])
		Selection:Set{root}
		evaluateSelection()
		
		ChangeHistoryService:SetWaypoint("End Make Curve Root")
	end
end

local function onEditCurve()
	if not editCurveButton.Enabled then return end
	
	if Editor.EditMode then
		exitEditMode()
	else
		enterEditMode()
		plugin:Activate(true)
	end
end

local function onShortenCurve()
	if not shortenCurveButton.Enabled then return end
	
	--shortenCurveButton:SetActive(false)
	
	ChangeHistoryService:SetWaypoint("Start Shorten Curve")
	Editor.SelectedCurves[1]:shorten()
	Editor.SelectedCurves[1]:drawLine(true, true)
	Editor.SelectedCurves[1]:drawHandles(true, true)
	editButtonsLogic()
	ChangeHistoryService:SetWaypoint("End Shorten Curve")
end


local function onExtendCurve()
	if not extendCurveButton.Enabled then return end
	
	--extendCurveButton:SetActive(false)
	
	ChangeHistoryService:SetWaypoint("Start Extend Curve")
	Editor.SelectedCurves[1]:extend()
	Editor.SelectedCurves[1]:drawLine(true, true)
	Editor.SelectedCurves[1]:drawHandles(true, true)
	editButtonsLogic()
	ChangeHistoryService:SetWaypoint("End Extend Curve")
end


local function onToggleLooped()
	if not toggleLoopedButton.Enabled then return end
	
	local curve = Editor.SelectedCurves[1]
	local looped = not curve:isLooped()
	local success, controlPoints = curve:getControlPoints()
	if not success then return end
	
	ChangeHistoryService:SetWaypoint("Starting Toggle Curve Looped")
	curve:setLooped(looped)
	curve:drawLine(true, true)
	curve:drawHandles(true, true)
	editButtonsLogic()
	ChangeHistoryService:SetWaypoint("Ended Toggle Curve Looped")
end

local function onReverseCurve()
	if not reverseCurveButton.Enabled then return end
	
	local curve = Editor.SelectedCurves[1]
	
	ChangeHistoryService:SetWaypoint("Start Reverse Curve")
	--reverseCurveButton:SetActive(false)
	curve:reverse()
	curve:drawLine(true, true)
	curve:drawHandles(true, true)
	editButtonsLogic()
	ChangeHistoryService:SetWaypoint("End Reverse Curve")
end

createCurveButton.Click:Connect(onCreateCurve)
makeRootButton.Click:Connect(onMakeCurveRoot)
editCurveButton.Click:Connect(onEditCurve)
shortenCurveButton.Click:Connect(onShortenCurve)
extendCurveButton.Click:Connect(onExtendCurve)
toggleLoopedButton.Click:Connect(onToggleLooped)
reverseCurveButton.Click:connect(onReverseCurve)

createCurveAction.Triggered:Connect(onCreateCurve)
makeRootAction.Triggered:Connect(onMakeCurveRoot)
editCurveAction.Triggered:Connect(onEditCurve)
shortenCurveAction.Triggered:Connect(onShortenCurve)
extendCurveAction.Triggered:Connect(onExtendCurve)
toggleLoopedAction.Triggered:Connect(onToggleLooped)
reverseCurveAction.Triggered:Connect(onReverseCurve)




ChangeHistoryService.OnUndo:Connect(function(action)
	editButtonsLogic()
	evaluateSelection()
	
	for _, curve in pairs(Editor.SelectedCurves) do
		curve:drawLine(true, true)
		curve:drawHandles(Editor.EditMode, true)
	end
end)

plugin.Deactivation:Connect(function()
	exitEditMode()
	print("curve editor plugin deactivated")
end)

plugin.Unloading:Connect(function()
	syncSettings()
	
	local gizmoRoot = CoreGui:FindFirstChild("GIZMO_ROOT")
	if gizmoRoot ~= nil then
		gizmoRoot:Destroy()
	end
end)
