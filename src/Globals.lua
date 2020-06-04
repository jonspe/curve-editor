local CoreGui = game:GetService("CoreGui")

local gizmoRootFolder = CoreGui:FindFirstChild("GIZMO_ROOT")
if gizmoRootFolder == nil then
	gizmoRootFolder = Instance.new("Folder")
	gizmoRootFolder.Name = "GIZMO_ROOT"
	gizmoRootFolder.Parent = CoreGui
end

return {
    GIZMO_ROOT = gizmoRootFolder
}