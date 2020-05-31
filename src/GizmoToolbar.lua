local GizmoToolbar = {}
GizmoToolbar.__index = GizmoToolbar

function GizmoToolbar.new(pluginToolbar)
	local self = {
		_toolbar = pluginToolbar,
		_selectedGizmo = nil,
		
		_gizmoToButtonDict = {},
		_gizmos = {},
	}
	
	setmetatable(self, GizmoToolbar)
	return self
end

function GizmoToolbar:selectGizmo(gizmo)
	--self._gizmoToButtonDict[gizmo]:SetActive(true)
	
	if self._selectedGizmo then
		self._selectedGizmo:enable(false)
		--self._gizmoToButtonDict[self._selectedGizmo]:SetActive(false)
	end
	
	self._selectedGizmo = gizmo
	self._selectedGizmo:enable(true)
end

function GizmoToolbar:addGizmo(gizmo)
	local gizmoButton = self._toolbar:CreateButton(gizmo.name, gizmo.description, gizmo.icon)
	gizmoButton.Click:connect(function()
		self:selectGizmo(gizmo)
	end)
	
	self._gizmoToButtonDict[gizmo] = gizmoButton
	table.insert(self._gizmos, gizmo)
	
	if self._selectedGizmo == nil then
		self:selectGizmo(gizmo)
	end
end

function GizmoToolbar:getSelectedGizmo()
	return self._selectedGizmo
end

function GizmoToolbar:getGizmos()
	return self._gizmos
end

return GizmoToolbar
