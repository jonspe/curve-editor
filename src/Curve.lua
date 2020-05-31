--[[
	Module for handling Curves, where the root is a Part
	and control points are represented as Attachment-objects.
--]]

local Selection = game:GetService("Selection")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local Helper = require(script.Parent.Helper)
local InstancePool = require(script.Parent.InstancePool)
local Signal = require(script.Parent.Signal)

local ROOT = script.Parent
local GIZMO_ROOT = CoreGui:FindFirstChild("GIZMO_ROOT")
if GIZMO_ROOT == nil then
	GIZMO_ROOT = Instance.new("Folder")
	GIZMO_ROOT.Name = "GIZMO_ROOT"
	GIZMO_ROOT.Parent = CoreGui
end


local function adorneeDtor(instance)
	instance.Adornee = nil
	return instance
end

local controlPointPool = InstancePool.new(ROOT.Adornments.ControlPoint, 20, nil, adorneeDtor)
local tangentPointPool = InstancePool.new(ROOT.Adornments.TangentPoint, 20, nil, adorneeDtor)
local tangentSegmentPool = InstancePool.new(ROOT.Adornments.TangentSegment, 20, nil, adorneeDtor)
local curveSegmentPool = InstancePool.new(ROOT.Adornments.CurveSegment, 5000, nil, adorneeDtor) -- max segment instances at one time parented to gizmo root

local function newAttachment(position, index)
	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.new(position)
	attachment.Name = tostring(index)
	return attachment
end


local function isControl(index)
	return (index - 1) % 3 == 0
end

local function isTangent(index)
	return not isControl(index)
end

local function isLeftTangent(index)
	return (index - 1) % 3 == 2
end

local function isRightTangent(index)
	return (index - 1) % 3 == 1
end


local DISPLAY_SETTINGS = {}

local Curve = {}
Curve.__index = Curve

function Curve.new(root)
	local self = {
		root = nil,
		_controlPointEnterSignal = Signal(),
		_controlPointPressedSignal = Signal(),
		_controlPointLeaveSignal = Signal(),
		
		_childrenChanged = false,
		_childAddedConn = nil,
		_childRemovedConn = nil,
		
		_cachedControlPoints = {},
		
		_indexToHandle = {},
		_indexToSegment = {},
		_handleConnections = {},
		
		_gaveValidateWarning = false,
	}
	
	self.controlPointEnter = self._controlPointEnterSignal.Event
	self.controlPointPressed = self._controlPointPressedSignal.Event
	self.controlPointLeave = self._controlPointLeaveSignal.Event
	
	if root == nil then
		error("Need root for new curve", 2)
	elseif not CollectionService:HasTag(root, "Curve") then
		error("Part is not tagged as Curve", 2)
	end
	
	self.root = root
	
	local function onChildrenChanged()
		self._childrenChanged = true
	end
	
	self._childAddedConn = self.root.ChildAdded:connect(onChildrenChanged)
	self._childRemovedConn = self.root.ChildRemoved:connect(onChildrenChanged)
	self._sizeChangedConn = self.root:GetPropertyChangedSignal("Size"):connect(function()
		self:drawLine(true, false)
	end)
	
	setmetatable(self, Curve)
	
	self:validateControlPoints()
	
	return self
end

function Curve.setDisplaySettings(displaySettings)
	DISPLAY_SETTINGS = displaySettings
end

function Curve:cleanUp()
	self._childAddedConn:Disconnect()
	self._childRemovedConn:Disconnect()
	self._sizeChangedConn:Disconnect()
	
	for _, conn in pairs(self._handleConnections) do
		conn:Disconnect()
	end
	
	self._controlPointEnterSignal:Destroy()
	self._controlPointPressedSignal:Destroy()
	self._controlPointLeaveSignal:Destroy()
		
	self:deallocateParts()
end

function Curve:deallocateParts()
	controlPointPool:giveAllKey(self.root)
	tangentPointPool:giveAllKey(self.root)
	tangentSegmentPool:giveAllKey(self.root)
	curveSegmentPool:giveAllKey(self.root)
end

function Curve:extend(position)
	local success, controlPoints = self:getControlPoints()
	if not success then return end
	
	local pointCount = #controlPoints
	
	-- Calculate convenient new positions for control points
	local pointPosition = position == nil and 2*controlPoints[pointCount].Position - controlPoints[pointCount-3].Position or position
	local tangentPosition1 = 2 * controlPoints[pointCount].Position - controlPoints[pointCount-1].Position
	local tangentPosition2 = pointPosition + controlPoints[pointCount-3].Position - controlPoints[pointCount-2].Position
	
	newAttachment(tangentPosition1, pointCount + 1).Parent = self.root -- Right tangent for last point
	newAttachment(tangentPosition2, pointCount + 2).Parent = self.root -- Left tangent for new point
	newAttachment(pointPosition, pointCount + 3).Parent = self.root -- New point
end

function Curve:shorten()
	local success, controlPoints = self:getControlPoints()
	if not success then return end
	
	local pointCount = #controlPoints
	
	-- If there is something to shorten (4 + n*3)
	if pointCount >= 7 then
		controlPoints[pointCount - 2].Parent = nil
		controlPoints[pointCount - 1].Parent = nil
		controlPoints[pointCount].Parent = nil
	else
		warn("Can't shorten curve: already at minimum length")
	end
end

function Curve:reverse()
	local success, controlPoints = self:getControlPoints()
	if not success then return end
	
	local pointCount = #controlPoints
	
	if not self:isLooped() then
		for index, attachment in pairs(controlPoints) do
			attachment.Name = tostring(pointCount - index + 1)
		end
	else
		-- need to shift indices by 2 left to account for loop tangents
		for index, attachment in pairs(controlPoints) do
			attachment.Name = tostring(pointCount - index - 1)
		end
		
		controlPoints[pointCount].Name = tostring(pointCount-1)
		controlPoints[pointCount-1].Name = tostring(pointCount)
	end
	
	self:validateControlPoints()
end

--[[ TODO
function Curve:getControlPointIndexByPart(part)
	for attachment, p in pairs(self._pointParts) do
		if p == part then
			return tonumber(attachment.Name)
		end
	end
	return nil
end
]]

-- function for handling relative positions with control points
function Curve:moveControlPoint(index, targetPos, modifier)
	local success, controlPoints = self:getControlPoints()
	if not success then return end
	
	local pointCount = #controlPoints
	local looped = self:isLooped()
	
	-- adjacent control point indices fixed for closed loops
	local indexm1 = looped and (index - 2) % pointCount + 1 or index - 1
	local indexm2 = looped and (index - 3) % pointCount + 1 or index - 2
	local indexp1 = looped and (index) % pointCount + 1 or index + 1
	local indexp2 = looped and (index + 1) % pointCount + 1 or index + 2
	
	--print(string.format("m1: %s\tm2: %s\tp1: %s\tp2: %s\tlooped: %s", indexm1, indexm2, indexp1, indexp2, tostring(looped)))
	
	local origPos = controlPoints[index].WorldPosition
	if isControl(index) then
		controlPoints[index].WorldPosition = targetPos
		
		-- move control point tangents along
		if controlPoints[indexm1] then
			controlPoints[indexm1].WorldPosition = controlPoints[indexm1].WorldPosition - origPos + targetPos
		end
		if controlPoints[indexp1] then
			controlPoints[indexp1].WorldPosition = controlPoints[indexp1].WorldPosition - origPos + targetPos
		end
	elseif isTangent(index) then
		controlPoints[index].WorldPosition = targetPos
		
		-- affect opposite tangents, but not with modifier key on
		if isLeftTangent(index) and not modifier then
			if controlPoints[indexp2] and controlPoints[indexp1] then
				controlPoints[indexp2].WorldPosition = controlPoints[indexp1].WorldPosition - targetPos + controlPoints[indexp1].WorldPosition
			end
		elseif isRightTangent(index) and not modifier then
			if controlPoints[indexm2] and controlPoints[indexm1] then
				controlPoints[indexm2].WorldPosition = controlPoints[indexm1].WorldPosition - targetPos + controlPoints[indexm1].WorldPosition
			end
		end
	end
end

function Curve:validateControlPoints()
	local success = true
	
	local children = self.root:GetChildren()
	local controlPoints = {}
	
	-- Add all attachments to list that match control point naming convention
	for _, child in ipairs(children) do
		if child.ClassName == "Attachment" and tonumber(child.Name) then
			table.insert(controlPoints, child)
		end
	end
	
	-- Sort control points by index
	table.sort(controlPoints, function(a, b)
		return tonumber(a.Name) < tonumber(b.Name)
	end)
	
	-- Check if indices start from 1 without any empty spaces in between
	for index, point in ipairs(controlPoints) do
		local pointIndex = tonumber(point.Name)
		if index ~= pointIndex then
			success = false
			break
		end
	end
	
	-- Check if there's a correct number of control points (4 + n*3)
	if (#controlPoints < 4) or not (((#controlPoints - 4) % 3 == 0) or (#controlPoints - 4) % 3 == 2) then
		success = false
	end
	
	if success then
		self._cachedControlPoints = controlPoints
		self._gaveValidateWarning = false
	
		--print("successfully validated control points")
	elseif not self._gaveValidateWarning then
		self._gaveValidateWarning = true
		self:deallocateParts()
		
		warn("Invalid curve data in root, fix by naming control points correctly "
		   .."starting from 1 and having the correct number of control points (4 + n*3)")
		
		return success
	end
	
	return success
end

function Curve:getControlPoints()
	if self._childrenChanged then
		local success = self:validateControlPoints()
		if not success then
			return false, self._cachedControlPoints
		else
			self._childrenChanged = false
		end
	end
	
	return true, self._cachedControlPoints
end

function Curve:isLooped()
	local valid, controlPoints = self:getControlPoints()
	if not valid then return end
	
	return (#controlPoints - 1) % 3 == 2
end

function Curve:setLooped(looped)
	if looped and self:isLooped() then
		warn("Curve is already looped")
	elseif not looped and not self:isLooped() then
		warn("Curve is already open")
	else
		local valid, controlPoints = self:getControlPoints()
		if not valid then return end
		
		local pointCount = #controlPoints
		
		if looped then
			local posLastRight = 2 * controlPoints[pointCount].Position - controlPoints[pointCount-1].Position
			local posFirstLeft = 2 * controlPoints[1].Position - controlPoints[2].Position
	
			newAttachment(posLastRight, pointCount + 1).Parent = self.root -- Right tangent for last point
			newAttachment(posFirstLeft, pointCount + 2).Parent = self.root -- Left tangent for first point
			
			self:validateControlPoints()
		else
			controlPoints[pointCount].Parent = nil
			controlPoints[pointCount-1].Parent = nil
			
			self:validateControlPoints()
		end
	end
end

function Curve:createOpenCurveFunction()
	local valid, controlPoints = self:getControlPoints()
	if not valid then return end
	
	local pointCount = #controlPoints
	local segmentCount = (pointCount - 1)/3
	
	local calculateBezierPoint = Helper.calculateBezierPoint
	return function(t)
		local t2 = t * segmentCount % 1
		local segmentIndex = math.floor(t * segmentCount)
		
		return calculateBezierPoint(t2,
			controlPoints[1 + segmentIndex * 3].Position,
			controlPoints[2 + segmentIndex * 3].Position,
			controlPoints[3 + segmentIndex * 3].Position,
			controlPoints[4 + segmentIndex * 3].Position
		)
	end
end

function Curve:createClosedCurveFunction()
	local valid, controlPoints = self:getControlPoints()
	if not valid then return end
	
	local pointCount = #controlPoints
	local segmentCount = pointCount/3  -- 1 segment for closed loop part
	
	local calculateBezierPoint = Helper.calculateBezierPoint
	return function(t)
		local t2 = t * segmentCount % 1
		local segmentIndex = math.floor(t * segmentCount)
		
		return calculateBezierPoint(t2,
			controlPoints[1 + segmentIndex * 3].Position,
			controlPoints[2 + segmentIndex * 3].Position,
			controlPoints[3 + segmentIndex * 3].Position,
			controlPoints[(4 + segmentIndex * 3) % (pointCount)].Position
		)
	end
end






--[[
	DRAWING DRAWING DRAWING DRAWING DRAWING DRAWING DRAWING DRAWING DRAWING 
	WING DRAWING DRAWING DRAWING DRAWING DRAWING DRAWING DRAWING DRAWING DR
--]]

-- TODO: draw partial curve
function Curve:drawLine(visible, redraw, cpIndex)
	local success, controlPoints = self:getControlPoints()
	if not success then return end

	local pointCount = #controlPoints
	
	if redraw or not visible then
		curveSegmentPool:giveAllKey(self.root)
		self._indexToSegment = {}
	end
	
	if not visible then return end
	
	local curveFunction, segmentCount, lineSegmentCount
	if self:isLooped() then
		curveFunction = self:createClosedCurveFunction()
		segmentCount = pointCount/3
	else
		curveFunction = self:createOpenCurveFunction()
		segmentCount = (pointCount-1)/3
	end
	lineSegmentCount = segmentCount * DISPLAY_SETTINGS.CurveFidelity
	
	for i = 1, lineSegmentCount do
		local pos0 = curveFunction((i-1)/lineSegmentCount)
		local pos1 = curveFunction(i*.9999/lineSegmentCount) -- if precise, out of bounds cus createcurvefunction 0->lim 1
		local dist = (pos1 - pos0).magnitude + DISPLAY_SETTINGS.CurveThickness/6
		
		local curveSegment = self._indexToSegment[i]
		if curveSegment == nil then
			curveSegment = curveSegmentPool:take(self.root)
			self._indexToSegment[i] = curveSegment
		end
		
		curveSegment.CFrame = CFrame.new(pos0, pos1) * CFrame.new(0, 0, -dist/2)
		curveSegment.Size = Vector3.new(DISPLAY_SETTINGS.CurveThickness, DISPLAY_SETTINGS.CurveThickness, dist)
		curveSegment.Color3 = Color3.new(.2, .5, 1)
			:Lerp(Color3.new(1, 1, 1), math.clamp(i/DISPLAY_SETTINGS.CurveFidelity, 0, 1))
		
		curveSegment.Adornee = self.root
		curveSegment.Parent = GIZMO_ROOT
	end
end

function Curve:drawHandles(visible, redraw)
	local success, controlPoints = self:getControlPoints()
	if not success then return end

	local pointCount = #controlPoints
	
	
	tangentSegmentPool:giveAllKey(self.root)
	
	if redraw or not visible then
		controlPointPool:giveAllKey(self.root)
		tangentPointPool:giveAllKey(self.root)
		
		for _, conn in pairs(self._handleConnections) do
			conn:Disconnect()
		end
		self._handleConnections = {}
		self._indexToHandle = {}
	end
	
	if not visible then return end
	
	for index, attachment in ipairs(controlPoints) do
		local pointBall = self._indexToHandle[index]
		
		if pointBall == nil then
			if isControl(index) then
				pointBall = controlPointPool:take(self.root)
			elseif isTangent(index) then
				pointBall = tangentPointPool:take(self.root)
			end
			
			self._indexToHandle[index] = pointBall
			
			table.insert(self._handleConnections, pointBall.MouseButton1Down:Connect(function()
				self._controlPointPressedSignal:Fire(self, index, pointBall)
			end))
			
			table.insert(self._handleConnections, pointBall.MouseEnter:Connect(function()
				self._controlPointEnterSignal:Fire(self, index, pointBall)
			end))
			
			table.insert(self._handleConnections, pointBall.MouseLeave:Connect(function()
				self._controlPointLeaveSignal:Fire(self, index, pointBall)
			end))
		end
		
		pointBall.Adornee = self.root
		pointBall.CFrame = CFrame.new(attachment.Position)
		pointBall.Parent = GIZMO_ROOT
			
		-- tangent line
		if isTangent(index) then
			local tangentSegment = tangentSegmentPool:take(self.root)
			
			local pos0 = attachment.Position
			local pos1
			if self:isLooped() then
				pos1 = isLeftTangent(index) and controlPoints[(index+1) % pointCount].Position or controlPoints[index-1].Position
			else
				pos1 = isLeftTangent(index) and controlPoints[index+1].Position or controlPoints[index-1].Position
			end
			
			local dist = (pos1 - pos0).magnitude
			
			tangentSegment.CFrame = CFrame.new(pos0, pos1) * CFrame.new(0, 0, -dist/2)
			tangentSegment.Size = Vector3.new(DISPLAY_SETTINGS.CurveThickness*0.75, DISPLAY_SETTINGS.CurveThickness*0.75, dist)
			tangentSegment.Adornee = self.root
			tangentSegment.Parent = GIZMO_ROOT
		end
	end
end

return Curve
