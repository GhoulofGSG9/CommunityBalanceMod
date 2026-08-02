-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\MixinUtility.lua
--
--    Created by:   Brian Cronin (brianc@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Table.lua")
Script.Load("lua/MixinFinalizer.lua")

local classes = __CLASSES
if not classes then
    classes = {}
    __CLASSES = classes
end

local function GetMixinConstants(self)
    return self.__mixindata
end

local function GetMixinConstant(self, constantName)
    return self.__mixindata[constantName]
end

Entity.__is_ent = true

-- Entend class constructor to add mixin related fields and to use cached class methods
local oldclass = class
class = function(name)
    local oldbasesetter = oldclass(name)

    local cls = _G[name]
    cls.__is_ent = false
    cls.GetMixinConstants = GetMixinConstants
    cls.GetMixinConstant = GetMixinConstant

    classes[#classes+1] = cls

    local meta = getmetatable(cls)
    meta.name = name
    meta.mixintypes = {}
    meta.mixindata = {}
    meta.mixincache = {}
    meta.mixins = {}

    return function(base)
        assert(type(base) == "table", "Not a valid base class!")

        meta.base = base
        if base.__is_ent or base == Entity then
            cls.__is_ent = true
        end

        oldbasesetter(base)

        local cache = getmetatable(base) and getmetatable(base).mixincache
        if cache then
            for k, v in pairs(cache) do
                if type(k) ~= "number" then
                    cls[k] = v
                end
            end

            for i = 1, #cache do
                cls[cache[i]] = nil
            end
        end

    end

end

--
-- This function is used to create a mixin table. To allow for hot loading of scripts, the
-- existing mixin table should be passed in as the mixin parameter. This allows us to reuse
-- the mixin table.
--
function CreateMixin(mixin)
    if mixin then
        for k in pairs(mixin) do
            mixin[k] = nil
        end
    else
        mixin = {}
    end

    return mixin
end

--
-- This will add the mixin network vars to the passed in network var
-- table. It will do nothing if the mixin does not have network vars.
--
function AddMixinNetworkVars(theMixin, networkVars, overwrite)
    if theMixin.networkVars then

        for varName, varType in pairs(theMixin.networkVars) do

            if networkVars[varName] ~= nil and overwrite == nil then
                error("Variable " .. varName .. " already exists in network vars while adding mixin " .. theMixin.type)
            end

            if networkVars[varName] ~= nil and overwrite == false then
                Log("Explicit skip of variable " .. varName .. " previously defined in network vars while adding mixin " .. theMixin.type)
            end

            networkVars[varName] = varType

        end

    end
end

-- NB: You can only return __1__ value! I could implement multi-variable return though. Will do if someone wants it.
local function mergeFunctions(a, b, name)
    local ia = debug.getinfo(a)
    local ib = debug.getinfo(b)

    local args = ""
    if ia.isvararg or ib.isvararg then
        args = "..."
    else
        local arg_count = math.max(ia.nparams, ib.nparams)
        if arg_count > 0 then
            for i = 1, arg_count-1 do
                args = string.format("%sarg%s,", args, i)
            end
            args = string.format("%sarg%s", args, arg_count)
        end
    end

    local str = ([[
		local a, b = ...
		assert(type(a) == "function" and type(b) == "function")
		return function(%s)
			local ret = a(%s)
			b(%s)
			return ret
		end
	]]):format(args, args, args)

    return assert(loadstring(str, name))(a, b)
end

local void = function() end
local sink = setmetatable({}, {__newindex = void})

-- self is an instance of the class that was made prior to this.
-- This way it can be updated.
function InitMixinForClass(cls, mixin, self)
    local meta = getmetatable(cls)
    if meta.mixintypes[mixin.type] then return end

    self = self or sink

    -- Have to initialise subclasses first
    local subclasses = Script.GetDerivedClasses(meta.name or self.classname)
    for i = 1, #subclasses do
        InitMixinForClass(_G[subclasses[i]], mixin)
    end

    local overrideFunctionsSet = set(mixin.overrideFunctions or {})
    for k, v in pairs(mixin) do

        if type(v) == "function" and k ~= "__initmixin" then

            if not cls[k] then -- insert
                table.insert(meta.mixincache, k)
                self[k] = v
                cls[k] = v
            elseif overrideFunctionsSet[k] then -- override
                meta.mixincache[k] = cls[k]
                self[k] = v
                cls[k] = v
            else -- merge
                meta.mixincache[k] = cls[k]
                local func = mergeFunctions(cls[k], v, k.."_"..(meta.name or self.classname))
                self[k] = func
                cls[k] = func
            end

        end

    end

    if not mixin.__arguments then

        local args = {}
        mixin.__arguments = args

        if mixin.defaultConstants then
            for k in pairs(mixin.defaultConstants) do
                table.insert(args, k)
            end
        end

        if mixin.expectedConstants then
            for k in pairs(mixin.expectedConstants) do
                table.insert(args, k)
            end
        end

        if mixin.optionalConstants then
            for k in pairs(mixin.optionalConstants) do
                table.insert(args, k)
            end
        end

    end

    if mixin.defaultConstants then
        for k, v in pairs(mixin.defaultConstants) do
            meta.mixindata[k] = v
        end
    end

    meta.mixintypes[mixin.type] = true
end

function InitMixinForInstance(classInstance, theMixin)

    if not classInstance.__mixintypes then
        classInstance.__constructing = false
        classInstance.__mixintypes   = {}
        classInstance.__mixindata    = {}
    end

    if classInstance.__mixintypes[theMixin.type] then
        return
    end

    local overrideFunctionsSet = set(theMixin.overrideFunctions or {})
    for k, v in pairs(theMixin) do

        if type(v) == "function" and k ~= "__initmixin" then

            if not classInstance[k] then
                classInstance[k] = v
            elseif overrideFunctionsSet[k] then
                classInstance[k] = v
            else
                classInstance[k] = mergeFunctions(classInstance[k], v)
            end

        end

    end

    if not theMixin.__arguments then

        local args           = {}
        theMixin.__arguments = args

        if theMixin.defaultConstants then
            for k in pairs(theMixin.defaultConstants) do
                table.insert(args, k)
            end
        end

        if theMixin.expectedConstants then
            for k in pairs(theMixin.expectedConstants) do
                table.insert(args, k)
            end
        end

        if theMixin.optionalConstants then
            for k in pairs(theMixin.optionalConstants) do
                table.insert(args, k)
            end
        end

    end

    if theMixin.defaultConstants then

        for k, v in pairs(theMixin.defaultConstants) do
            classInstance.__mixindata[k] = v
        end

    end
end

-- InitMixin takes a class instance and adds the passed in mixin functions to it if the class instance
-- doesn't yet have the mixin. If the mixin was previously added, it reinitializes the mixin for the instance.
function InitMixin(classInstance, theMixin, optionalMixinData)

    if classInstance.__constructing then
        local meta = getmetatable(classInstance.__class)
        if not meta.mixintypes[theMixin.type] then
            InitMixinForClass(classInstance.__class, theMixin, classInstance)
        end
    else
        InitMixinForInstance(classInstance, theMixin)
    end

    if classInstance.__is_ent then
        Shared.AddTagToEntity(classInstance:GetId(), theMixin.type)
    end

    classInstance.__mixintypes[theMixin.type] = true

    if optionalMixinData then
        for i = 1, #theMixin.__arguments do
            local k = theMixin.__arguments[i]
            local v = optionalMixinData[k]
            if v then
                classInstance.__mixindata[k] = v
            end
        end
    end

    if theMixin.__initmixin then
        theMixin.__initmixin(classInstance)
    end
end

--
-- Returns true if the passed in class instance has a Mixin that
-- matches the passed in mixin type name.
-- Note, this type name can be shared by multiple Mixin types.
-- It is more of an implicit interface the Mixin adheres to.
--
function HasMixin(classInstance, mixinTypeName)

	-- Note: The check for a non-nil classInstance was added as a temporarily fix for Mantis report: 3003.
	if not classInstance then
		return false
	end

    local mixinlist = classInstance.__mixintypes
	return mixinlist and mixinlist[mixinTypeName] or false
    
end

-- Returns the number of mixins the passed in class instance currently is using.
function NumberOfMixins(classInstance)

    assert(type(classInstance) == "userdata", "First parameter to InitMixin() must be a class instance")
    
    if classInstance.__mixinlist then
        return table.countkeys(classInstance.__mixintypes)
    end

    return 0

end
