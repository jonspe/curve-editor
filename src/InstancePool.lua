

local function emptyCtor(instance)
	return instance
end
local function emptyDtor(instance)
	return instance
end

local InstancePool = {}
InstancePool.__index = InstancePool

function InstancePool.new(baseInstance, preferredSize, ctor, dtor)
	local self = {
		_baseInstance = baseInstance,
		_preferredSize = preferredSize, --max instances for immediate access
		_poolCount = 0,
		
		_ctor = ctor or emptyCtor,
		_dtor = dtor or emptyDtor,
		
		_keySets = {},
		_availableSet = {},
	}
	
	setmetatable(self, InstancePool)
	return self
end

function InstancePool:_newInstance(key)
	local instance = self._ctor(self._baseInstance:Clone())
	if self._keySets[key] == nil then
		self._keySets[key] = {}
	end
	self._keySets[key][instance] = true
	self._poolCount = self._poolCount + 1
	
	return instance
end

function InstancePool:_takeNext(key)
	local instance = next(self._availableSet)
	
	if instance then
		if self._keySets[key] == nil then
			self._keySets[key] = {}
		end
		
		self._availableSet[instance] = nil
		self._keySets[key][instance] = true
		
		return instance
	end
end

function InstancePool:take(key)
	return self:_takeNext(key) or self:_newInstance(key)
end

function InstancePool:give(key, instance)
	self._keySets[key][instance] = nil
	
	if self._poolCount > self._preferredSize then
		instance:Destroy()
		self._poolCount = self._poolCount - 1
	else
		self._dtor(instance)
		self._availableSet[instance] = true
	end
end

function InstancePool:giveAllKey(key)
	if self._keySets[key] == nil then return end
	for instance, _ in pairs(self._keySets[key]) do
		self:give(key, instance)
	end
end




return InstancePool
