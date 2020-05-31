local StudioService = game:GetService("StudioService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local UserInputService = game:GetService("UserInputService")

local Helper = require(script.Parent.Helper)

local GizmoAxis = {}
GizmoAxis.__index = GizmoAxis

function GizmoAxis.new(mouse)
	local self = {
		name = "Axis",
		description = "Move control points with axis handles",
		icon = "rbxassetid://4459262762",
		
		_mouse = mouse,
		_enabled = false,
		_dragging = false,
		
		_modifier = false,
		
		_selectedCurve = nil,
		_selectedIndex = nil,
		_selectedHandle = nil,
		
		_dragOffset = nil,
	}
	
	setmetatable(self, GizmoAxis)
	
	mouse.Button1Up:Connect(function() self:onMouseUp() end)
	mouse.Move:Connect(function() self:onMouseMove() end)
	
	return self
end

function GizmoAxis:enable(enabled)
	self._enabled = enabled
	self._dragging = false
	
	self._selectedCurve = nil
	self._selectedIndex = nil
	self._selectedHandle = nil
	
	self._dragOffset = nil
end

function GizmoAxis:onControlPointPressed(curve, controlPointIndex, handle)
	if not self._enabled then return end
	
	self._selectedCurve = curve
	self._selectedIndex = controlPointIndex
	self._selectedHandle = handle
	
	self:onControlPointEnter(nil, nil, handle)
	
	self._dragOffset = workspace.CurrentCamera.CFrame:PointToObjectSpace(
		handle.Adornee.CFrame:PointToWorldSpace(handle.CFrame.p))
	
	self._dragging = true
	
	ChangeHistoryService:SetWaypoint("Start Move Curve Control Point")
end

function GizmoAxis:onControlPointEnter(curve, controlPointIndex, handle)
	if not self._enabled then return end
	
	if self._dragging then return end
	handle.Color3 = Color3.new(1, 0, 0)
end

function GizmoAxis:onControlPointLeave(curve, controlPointIndex, handle)
	if not self._enabled then return end
	
	if self._dragging then return end
	handle.Color3 = handle.DefaultColor.Value
end

function GizmoAxis:onMouseUp()
	if not self._enabled then return end
	
	self._dragging = false
	if self._selectedHandle then
		self:onControlPointLeave(nil, nil, self._selectedHandle)
	end
	
	self._selectedCurve = nil
	self._selectedIndex = nil
	self._selectedHandle = nil
	
	ChangeHistoryService:SetWaypoint("Move Curve Control Point")
end

function GizmoAxis:onMouseMove()
	if not self._enabled then return end
	
	if self._dragging then
		local ray = self._mouse.UnitRay
		local point = Helper.intersectPlane(
			ray,
			workspace.CurrentCamera.CFrame.lookVector,
			workspace.CurrentCamera.CFrame:PointToWorldSpace(self._dragOffset))
		
		local snapPoint = Helper.roundVector3ToMultiple(point, StudioService.GridSize)
		self._selectedCurve:moveControlPoint(self._selectedIndex, snapPoint, UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt))
		self._selectedCurve:drawLine(true, false)
		self._selectedCurve:drawHandles(true, false)
		return true --moved point
	end
	
	return false --didnt move point
end


return GizmoAxis
