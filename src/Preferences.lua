local DEFAULTS = {
    curveFidelity = 12,
    curveThickness = 0.5,
    movementMode = "Drag",
}

local plugin = nil


local Preferences = {}

function Preferences.init(_plugin)
    plugin = _plugin
    return Preferences
end

function Preferences.get(setting)
    local cached = plugin:GetSetting(setting)
    if cached == nil then
        cached = DEFAULTS[setting]
        plugin:SetSetting(setting, cached)
    end

    return cached
end

function Preferences.set(setting, value)
    plugin:SetSetting(setting, value)
end

return Preferences