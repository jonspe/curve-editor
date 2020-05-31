local function roundToNearestMultiple(value, multiple)
	return math.floor(value/multiple + 0.5) * multiple
end

local function roundVector3ToMultiple(vec, mult)
	return Vector3.new(
		roundToNearestMultiple(vec.x, mult),
		roundToNearestMultiple(vec.y, mult),
		roundToNearestMultiple(vec.z, mult)
	)
end

local function shallowCopy(tab)
	local copy = {}
	for key, value in pairs(tab) do
		copy[key] = value
	end
	return copy
end

local function calculateBezierPoint(t, p1, p2, p3, p4)
	local u = 1 - t;
	local tt = t*t;
	local uu = u*u;

	return uu*u * p1 + 3 * uu * t * p2 + 3 * u * tt * p3 + tt*t * p4
end

-- shamelessly copied from js source, translated to lua
local function intersectPlane(ray, planeNormal, planePoint)
	local diff = ray.Origin - planePoint
	local prod1 = diff:Dot(planeNormal)
	local prod2 = ray.Direction:Dot(planeNormal)
	local prod3 = prod1 / prod2
	return ray.Origin - ray.Direction * prod3
end

return {
	roundToNearestMultiple = roundToNearestMultiple,
	roundVector3ToMultiple = roundVector3ToMultiple,
	shallowCopy = shallowCopy,
	calculateBezierPoint = calculateBezierPoint,
	intersectPlane = intersectPlane,
}
