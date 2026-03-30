--!native
--!optimize 2
--!divine-intellect --david 
-- https://discord.gg/wx4ThpAsmw


local function string_find(s, pattern)
	return string.find(s, pattern, nil, true)
end

local function ArrayToDict(t, hybridMode, valueOverride, typeStrict)
	local tmp = {}

	if hybridMode then
		for any1, any2 in t do
			if type(any1) == "number" then
				tmp[any2] = valueOverride or true
			elseif type(any2) == "table" then
				tmp[any1] = ArrayToDict(any2, hybridMode)
			else
				tmp[any1] = any2
			end
		end
	else
		for _, key in t do
			if not typeStrict or typeStrict and type(key) == typeStrict then
				tmp[key] = true
			end
		end
	end

	return tmp
end

local global_container
do
	local filename = "UniversalMethodFinder"

	local finder
	finder, global_container = loadstring(
		game:HttpGet("https://raw.githubusercontent.com/luau/SomeHub/main/" .. filename .. ".luau", true),
		filename
	)()

	finder({
		base64encode = 'local a={...}local b=a[1]local function c(a,b)return string.find(a,b,nil,true)end;return c(b,"encode")and(c(b,"base64")or c(string.lower(tostring(a[2])),"base64"))',
		gethiddenproperty = 'string.find(...,"get",nil,true) and string.find(...,"h",nil,true) and string.find(...,"prop",nil,true) and string.sub(...,#...) ~= "s"',
		gethui = 'string.find(...,"get",nil,true) and string.find(...,"h",nil,true) and string.find(...,"ui",nil,true)',
		getnilinstances = 'string.find(...,"nil",nil,true) and string.find(...,"get",nil,true) and string.sub(...,#...) == "s"',
		getscriptbytecode = 'string.find(...,"get",nil,true) and string.find(...,"script",nil,true) and string.find(...,"bytecode",nil,true)',
		protectgui = 'string.find(...,"protect",nil,true) and string.find(...,"ui",nil,true) and not string.find(...,"un",nil,true)',
		setthreadidentity = 'string.find(...,"identity",nil,true) and string.find(...,"set",nil,true)',
	}, true, 10)
end

local identify_executor = identifyexecutor or getexecutorname or whatexecutor
local EXECUTOR_NAME = identify_executor and identify_executor() or ""

local gethiddenproperty = global_container.gethiddenproperty

local appendfile = appendfile
local isfile = isfile
local readfile = readfile
local writefile = writefile

local getscriptbytecode = global_container.getscriptbytecode
local base64encode = global_container.base64encode

local service = setmetatable({}, {
	__index = function(self, serviceName)
		local o, s = pcall(Instance.new, serviceName)
		local Service = o and s
			or game:GetService(serviceName)
			or settings():GetService(serviceName)
			or UserSettings():GetService(serviceName)

		if Service then
			self[serviceName] = Service
		end
		return Service
	end,
})

-- ──────────────────────────────────────────────────────────────
--  DECOMPILER OUTPUT CLEANUP
--  Runs after decompilation to rename generic variables and
--  strip decompiler noise like upvalue comments and INLINED funcs
-- ──────────────────────────────────────────────────────────────

local function CleanDecompiledSource(source)
	if not source or source == "" then
		return source
	end

	-- Strip --[[ Upvalues[N]: ... ]] blocks
	source = string.gsub(source, "%-%-%[%[%s*Upvalues%[%d+%]:.-%]%]%s*\n?", "")

	-- Strip -- Luau version / Time taken header lines
	source = string.gsub(source, "^%-%-[^\n]*\n", "")
	source = string.gsub(source, "\n%-%-[^\n]*version[^\n]*", "")
	source = string.gsub(source, "\n%-%-[^\n]*Time taken[^\n]*", "")

	-- Remove -- Line N comments (decompiler line annotations)
	source = string.gsub(source, "%s*%-%- Line %d+%s*\n", "\n")

	-- Remove INLINED internal function artifacts
	source = string.gsub(source, "%s*%-%- Internal function, doesn't exist in bytecode%s*\n", "\n")

	-- ── Variable renaming ──────────────────────────────────────
	-- Strategy: build a rename map from context clues, then apply.
	-- We handle the most common decompiler patterns:
	--   argN  → named by position/context
	--   varN  → named by first assignment RHS
	--   module_N_upvr → class name from .ClassName or _new pattern

	-- Rename module_N_upvr style metatable names
	-- Look for  module_X_upvr.ClassName = "SomeName"  to infer the real name
	local moduleRenames = {}
	for mangled, className in string.gmatch(source, "(%w+%_%d+%_upvr)%.ClassName%s*=%s*\"([^\"]+)\"") do
		moduleRenames[mangled] = className
	end
	-- Also catch: local module_X_upvr = {}  where there's a _new function returning setmetatable
	-- Fallback: if only one module_ name and no ClassName, call it Module
	local moduleNames = {}
	for name in string.gmatch(source, "local (%w+%_%d+%_upvr)") do
		moduleNames[name] = true
	end
	for name in pairs(moduleNames) do
		if not moduleRenames[name] then
			moduleRenames[name] = "Module"
		end
	end
	for mangled, clean in pairs(moduleRenames) do
		source = string.gsub(source, mangled, clean)
	end

	-- Rename arg1/arg2... in function signatures using parameter position heuristics.
	-- We do a line-by-line pass so we can scope renames to each function.
	local lines = string.split(source, "\n")
	local result = {}

	-- Common semantic mappings for arg positions by function name pattern
	local knownArgNames = {
		-- metamethods
		__index    = { "self", "key" },
		__newindex = { "self", "key", "value" },
		__eq       = { "a", "b" },
		__lt       = { "a", "b" },
		__le       = { "a", "b" },
		__add      = { "a", "b" },
		__sub      = { "a", "b" },
		__mul      = { "a", "b" },
		__div      = { "a", "b" },
		__mod      = { "a", "b" },
		__pow      = { "a", "b" },
		__unm      = { "self" },
		__len      = { "self" },
		__concat   = { "a", "b" },
		__call     = { "self" },
		__tostring = { "self" },
		-- common OOP patterns
		_new        = { "value" },
		Some        = { "value" },
		Wrap        = { "value" },
		Is          = { "object" },
		Assert      = { "object" },
		Deserialize = { "data" },
		Serialize   = { "self" },
		Match       = { "self", "matches" },
		IsSome      = { "self" },
		IsNone      = { "self" },
		Expect      = { "self", "msg" },
		ExpectNone  = { "self", "msg" },
		Unwrap      = { "self" },
		UnwrapOr    = { "self", "default" },
		UnwrapOrElse = { "self", "fn" },
		AndThen     = { "self", "fn" },
		OrElse      = { "self", "fn" },
		Filter      = { "self", "predicate" },
		Contains    = { "self", "value" },
		And         = { "self", "other" },
		Or          = { "self", "other" },
		XOr         = { "self", "other" },
		new         = { "self" },
		init        = { "self" },
		update      = { "self", "dt" },
		render      = { "self" },
		destroy     = { "self" },
		connect     = { "self", "fn" },
		disconnect  = { "self" },
		fire        = { "self", "..." },
	}

	-- Fallback generic arg names by index
	local function genericArgName(i)
		local names = { "self", "arg", "value", "other", "data", "fn", "callback", "options", "config", "extra" }
		return names[i] or ("arg" .. i)
	end

	-- Rename varN by looking at what it's first assigned to
	-- e.g. `local var3 = "Option"` → replace var3 with a name derived from the string
	local function inferVarName(rhs)
		-- string literal → strip quotes, camelCase it
		local str = string.match(rhs, '^"([^"]+)"') or string.match(rhs, "^'([^']+)'")
		if str then
			-- e.g. "Option" → "optionStr", "Hello World" → "helloWorldStr"
			local words = string.split(str, " ")
			local out = string.lower(string.sub(words[1], 1, 1)) .. string.sub(words[1], 2)
			for i = 2, #words do
				local w = words[i]
				if #w > 0 then
					out ..= string.upper(string.sub(w, 1, 1)) .. string.sub(w, 2)
				end
			end
			return out
		end
		-- boolean
		if rhs == "true" or rhs == "false" then return "flag" end
		-- number
		if string.match(rhs, "^%-?%d") then return "num" end
		-- nil
		if rhs == "nil" then return "val" end
		-- table constructor
		if string.match(rhs, "^{") then return "tbl" end
		-- function call → use function name
		local fnName = string.match(rhs, "^([%a_][%w_]*)%(")
		if fnName then
			return string.lower(string.sub(fnName, 1, 1)) .. string.sub(fnName, 2) .. "Result"
		end
		-- method call
		local methName = string.match(rhs, ":([%a_][%w_]*)%(")
		if methName then
			return string.lower(string.sub(methName, 1, 1)) .. string.sub(methName, 2) .. "Result"
		end
		return nil
	end

	-- Per-function scope rename pass
	local currentFuncArgs = {}  -- argN → name mapping for current function scope
	local varRenames = {}       -- varN → name mapping for current function scope

	for i, line in lines do
		-- Detect function definition and build arg rename map
		local funcName, argStr = string.match(line, "function%s+[%w_.:]+%.([%w_]+)%(([^)]*)%)")
		if not funcName then
			funcName, argStr = string.match(line, "function%s+([%w_]+)%(([^)]*)%)")
		end

		if funcName and argStr then
			currentFuncArgs = {}
			varRenames = {}

			local knownNames = knownArgNames[funcName]
			local argIdx = 0
			for argName in string.gmatch(argStr .. ",", "([%w_]+)%s*,") do
				argIdx += 1
				-- Only rename argN style names
				if string.match(argName, "^arg%d+$") then
					local newName
					if knownNames and knownNames[argIdx] then
						newName = knownNames[argIdx]
					else
						newName = genericArgName(argIdx)
					end
					currentFuncArgs[argName] = newName
				end
			end
		end

		-- Detect  local varN = <expr>  and build var rename map
		local varName, varRhs = string.match(line, "^%s*local (var%d+)%s*=%s*(.+)$")
		if varName and not varRenames[varName] then
			local inferred = inferVarName(string.gsub(varRhs, "%s+$", ""))
			if inferred then
				varRenames[varName] = inferred
			end
		end

		-- Apply arg renames to line
		for old, new in pairs(currentFuncArgs) do
			line = string.gsub(line, "%f[%w_]" .. old .. "%f[^%w_]", new)
		end

		-- Apply var renames to line
		for old, new in pairs(varRenames) do
			line = string.gsub(line, "%f[%w_]" .. old .. "%f[^%w_]", new)
		end

		-- Rename _result1, _result1_2 style decompiler temporaries
		line = string.gsub(line, "([%w_]+)_result1_%d+", "%1Result")
		line = string.gsub(line, "([%w_]+)_result1", "%1Result")

		-- Clean up any_IsSome_result / any_X_result patterns
		line = string.gsub(line, "any_([%w_]+)_result1_%d*", "%1Result")
		line = string.gsub(line, "any_([%w_]+)_result1", "%1Result")

		result[i] = line
	end

	source = table.concat(result, "\n")

	-- Final cleanup: collapse 3+ blank lines to 2
	source = string.gsub(source, "\n\n\n+", "\n\n")

	return source
end

-- ──────────────────────────────────────────────────────────────

local SharedString_identifier = 1e15
local SharedStrings = setmetatable({}, {
	__index = function(self, str)
		local identifier = base64encode(tostring(SharedString_identifier))
		SharedString_identifier += 1
		self[str] = identifier
		return identifier
	end,
})

local inherited_properties = {}
local default_instances = {}
local referents, ref_size = {}, 0

local function GetRef(instance)
	local ref = referents[instance]
	if not ref then
		ref = ref_size
		referents[instance] = ref
		ref_size += 1
	end
	return ref
end

local function index(self, index_name)
	return self[index_name]
end

local version = version
if not version then
	version = function()
		return "UNKNOWN"
	end
end

local FULL_VERSION = version()
local CLIENT_VERSION = tonumber(string.match(FULL_VERSION, "%d+%.(%d+)")) or 9e9

local attr_Type_IDs = {
	string = 0x02,
	boolean = 0x03,
	int32 = 0x04,
	number = 0x06,
	UDim = 0x09,
	UDim2 = 0x0A,
	Ray = 0x0B,
	Faces = 0x0C,
	Axes = 0x0D,
	BrickColor = 0x0E,
	Color3 = 0x0F,
	Vector2 = 0x10,
	Vector3 = 0x11,
	Vector2int16 = 0x12,
	Vector3int16 = 0x13,
	CFrame = 0x14,
	EnumItem = 0x15,
	NumberSequence = 0x17,
	NumberSequenceKeypoint = 0x18,
	ColorSequence = 0x19,
	ColorSequenceKeypoint = 0x1A,
	NumberRange = 0x1B,
	Rect = 0x1C,
	PhysicalProperties = 0x1D,
	Region3 = 0x1F,
	Region3int16 = 0x20,
	Font = 0x21,
	SecurityCapabilities = 0x22,
	Path2DControlPoint = 0x23,
}

local CFrame_Rotation_IDs = {
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x02,
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x03,
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x05,
	["\0\0\128\63\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x06,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x07,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x09,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x0a,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x0c,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x0d,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x0e,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x10,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\128"] = 0x11,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x14,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\128"] = 0x15,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x17,
	["\0\0\128\191\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\191\0\0\0\128"] = 0x18,
	["\0\0\0\0\0\0\128\63\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x19,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x1b,
	["\0\0\0\0\0\0\128\191\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x1c,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x1e,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x1f,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x20,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x22,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\191\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\128"] = 0x23,
}

local BASE_CAPABILITIES
pcall(function()
	BASE_CAPABILITIES = SecurityCapabilities.new()
end)

local CAPABILITY_BITS = {
	Plugin = 2 ^ 0,
	LocalUser = 2 ^ 1,
	WritePlayer = 2 ^ 2,
	RobloxScript = 2 ^ 3,
	RobloxEngine = 2 ^ 4,
	NotAccessible = 2 ^ 5,
	RunClientScript = 2 ^ 8,
	RunServerScript = 2 ^ 9,
	Unknown = 2 ^ 10,
	AccessOutsideWrite = 2 ^ 11,
	Unassigned = 2 ^ 15,
	LoadUnownedAsset = 2 ^ 16,
	LoadString = 2 ^ 17,
	ScriptGlobals = 2 ^ 18,
	CreateInstances = 2 ^ 19,
	Basic = 2 ^ 20,
	Audio = 2 ^ 21,
	DataStore = 2 ^ 22,
	Network = 2 ^ 23,
	Physics = 2 ^ 24,
	UI = 2 ^ 25,
	CSG = 2 ^ 26,
	Chat = 2 ^ 27,
	Animation = 2 ^ 28,
	AvatarAppearance = 2 ^ 29,
	Input = 2 ^ 30,
	Environment = 2 ^ 31,
	RemoteEvent = 2 ^ 32,
	LegacySound = 2 ^ 33,
	Players = 2 ^ 34,
	CapabilityControl = 2 ^ 35,
	AssetRead = 2 ^ 36,
	AssetManagement = 2 ^ 37,
	DynamicGeneration = 2 ^ 38,
	PlatformAvatarEditing = 2 ^ 39,
	AssetCreateUpdate = 2 ^ 40,
	Capture = 2 ^ 41,
	SensitiveInput = 2 ^ 42,
	Monetization = 2 ^ 43,
	LoadOwnedAsset = 2 ^ 44,
	Social = 2 ^ 45,
	ServerCommunication = 2 ^ 46,
	Logging = 2 ^ 47,
	PromptExternalPurchase = 2 ^ 48,
	Groups = 2 ^ 49,
	Teleport = 2 ^ 50,
	Consequences = 2 ^ 51,
	Material = 2 ^ 52,
	AvatarBehavior = 2 ^ 53,
	RemoteCommand = 2 ^ 59,
	InternalTest = 2 ^ 60,
	PluginOrOpenCloud = 2 ^ 61,
	Assistant = 2 ^ 62,
}

local function CountCapabilityBits(raw)
	local result = 0
	for _, flag in string.split(tostring(raw), " | ") do
		local bit = CAPABILITY_BITS[flag]
		if bit then
			result += bit
		end
	end
	return result
end

local function CountBits(...)
	local value = 0
	for i, bit in { ... } do
		if bit then
			value += 2 ^ (i - 1)
		end
	end
	return value
end

local Binary_Descriptors
Binary_Descriptors = {
	__PACK_MULTIPLE = function(descriptor, value1, value2, value3)
		local buf1, size1 = descriptor(value1)
		local buf2, size2 = descriptor(value2)

		local len = size1 + size2
		local buf3, size3

		if value3 ~= nil then
			buf3, size3 = descriptor(value3)
			len += size3
		end

		local b = buffer.create(len)
		buffer.copy(b, 0, buf1)
		buffer.copy(b, size1, buf2)

		if value3 ~= nil then
			buffer.copy(b, size1 + size2, buf3)
		end

		return b, len
	end,

	__construct_Sequence = function(keypoint_handler, keypointSize)
		return function(raw)
			local Keypoints = raw.Keypoints
			local count = #Keypoints
			local len = 4 + keypointSize * count
			local b = buffer.create(len)

			buffer.writeu32(b, 0, count)

			local offset = 4
			for _, keypoint in Keypoints do
				keypoint_handler(keypoint, b, offset)
				offset += keypointSize
			end

			return b, len
		end
	end,

	__writei64 = function(b, offset, raw)
		local low = bit32.band(raw, 0xFFFFFFFF)
		local high = (raw - low) / 0x100000000
		buffer.writei32(b, offset, low)
		buffer.writei32(b, offset + 4, high)
	end,

	__PACK_F32 = nil,
	__PACK_I16 = nil,

	__construct__PACKER = function(float)
		local writeFunc = float and buffer.writef32 or buffer.writei16
		local elementSize = float and 4 or 2

		return function(X, Y, Z)
			local len = Z and (elementSize * 3) or (elementSize * 2)
			local b = buffer.create(len)

			writeFunc(b, 0, X)
			writeFunc(b, elementSize, Y)
			if Z then
				writeFunc(b, elementSize * 2, Z)
			end

			return b, len
		end
	end,

	["string"] = function(raw)
		local raw_len = #raw
		local len = 4 + raw_len
		local b = buffer.create(len)
		buffer.writeu32(b, 0, raw_len)
		buffer.writestring(b, 4, raw)
		return b, len
	end,

	["boolean"] = function(raw)
		local b = buffer.create(1)
		buffer.writeu8(b, 0, raw and 1 or 0)
		return b, 1
	end,

	["number"] = function(raw)
		local b = buffer.create(8)
		buffer.writef64(b, 0, raw)
		return b, 8
	end,

	["UDim"] = function(raw)
		local b = buffer.create(8)
		buffer.writef32(b, 0, raw.Scale)
		buffer.writei32(b, 4, raw.Offset)
		return b, 8
	end,

	["UDim2"] = function(raw)
		return Binary_Descriptors.__PACK_MULTIPLE(Binary_Descriptors["UDim"], raw.X, raw.Y)
	end,

	["Ray"] = function(raw)
		return Binary_Descriptors.__PACK_MULTIPLE(Binary_Descriptors["Vector3"], raw.Origin, raw.Direction)
	end,

	["Faces"] = function(raw)
		local b = buffer.create(4)
		buffer.writeu32(b, 0, CountBits(raw.Right, raw.Top, raw.Back, raw.Left, raw.Bottom, raw.Front))
		return b, 4
	end,

	["Axes"] = function(raw)
		local b = buffer.create(4)
		buffer.writeu32(b, 0, CountBits(raw.X, raw.Y, raw.Z))
		return b, 4
	end,

	["BrickColor"] = function(raw)
		local b = buffer.create(4)
		buffer.writeu32(b, 0, raw.Number)
		return b, 4
	end,

	["Color3"] = function(raw)
		return Binary_Descriptors.__PACK_F32(raw.R, raw.G, raw.B)
	end,

	["Vector2"] = function(raw)
		return Binary_Descriptors.__PACK_F32(raw.X, raw.Y)
	end,

	["Vector3"] = function(raw)
		return Binary_Descriptors.__PACK_F32(raw.X, raw.Y, raw.Z)
	end,

	["Vector2int16"] = function(raw)
		return Binary_Descriptors.__PACK_I16(raw.X, raw.Y)
	end,

	["Vector3int16"] = function(raw)
		return Binary_Descriptors.__PACK_I16(raw.X, raw.Y, raw.Z)
	end,

	["CFrame"] = function(raw)
		local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = raw:GetComponents()
		local rotation_ID
		do
			local b = buffer.create(36)
			buffer.writef32(b, 0, R00)
			buffer.writef32(b, 4, R01)
			buffer.writef32(b, 8, R02)
			buffer.writef32(b, 12, R10)
			buffer.writef32(b, 16, R11)
			buffer.writef32(b, 20, R12)
			buffer.writef32(b, 24, R20)
			buffer.writef32(b, 28, R21)
			buffer.writef32(b, 32, R22)
			rotation_ID = CFrame_Rotation_IDs[buffer.tostring(b)]
		end

		local len = rotation_ID and 13 or 49
		local b = buffer.create(len)
		local packF32 = Binary_Descriptors.__PACK_F32
		local position = packF32(X, Y, Z)
		buffer.copy(b, 0, position)

		if rotation_ID then
			buffer.writeu8(b, 12, rotation_ID)
		else
			buffer.writeu8(b, 12, 0x0)
			buffer.copy(b, 13, packF32(R00, R01, R02))
			buffer.copy(b, 25, packF32(R10, R11, R12))
			buffer.copy(b, 37, packF32(R20, R21, R22))
		end

		return b, len
	end,

	["EnumItem"] = function(raw)
		local b_Name, Name_size = Binary_Descriptors["string"](tostring(raw.EnumType))
		local len = Name_size + 4
		local b = buffer.create(len)
		buffer.copy(b, 0, b_Name)
		buffer.writeu32(b, Name_size, raw.Value)
		return b, len
	end,

	["NumberSequence"] = nil,

	["NumberSequenceKeypoint"] = function(keypoint, b, offset)
		if not b then
			return Binary_Descriptors.__PACK_F32(keypoint.Envelope, keypoint.Time, keypoint.Value)
		end
		buffer.writef32(b, offset, keypoint.Envelope)
		buffer.writef32(b, offset + 4, keypoint.Time)
		buffer.writef32(b, offset + 8, keypoint.Value)
	end,

	["ColorSequence"] = nil,

	["ColorSequenceKeypoint"] = function(keypoint, b, offset)
		local colorBuf = Binary_Descriptors["Color3"](keypoint.Value)
		if not b then
			b = buffer.create(20)
			offset = 0
		end
		buffer.writef32(b, offset, 0)
		buffer.writef32(b, offset + 4, keypoint.Time)
		buffer.copy(b, offset + 8, colorBuf)
		return b, 20
	end,

	["NumberRange"] = function(raw)
		return Binary_Descriptors.__PACK_F32(raw.Min, raw.Max)
	end,

	["Rect"] = function(raw)
		return Binary_Descriptors.__PACK_MULTIPLE(Binary_Descriptors["Vector2"], raw.Min, raw.Max)
	end,

	["PhysicalProperties"] = function(raw)
		local len = raw and 25 or 1
		local b = buffer.create(len)
		buffer.writeu8(b, 0, raw and 3 or 0)
		if raw then
			buffer.writef32(b, 1, raw.Density)
			buffer.writef32(b, 5, raw.Friction)
			buffer.writef32(b, 9, raw.Elasticity)
			buffer.writef32(b, 13, raw.FrictionWeight)
			buffer.writef32(b, 17, raw.ElasticityWeight)
			buffer.writef32(b, 21, raw.AcousticAbsorption)
		end
		return b, len
	end,

	["Region3"] = function(raw)
		local Translation = raw.CFrame.Position
		local HalfSize = raw.Size * 0.5
		return Binary_Descriptors.__PACK_MULTIPLE(
			Binary_Descriptors["Vector3"],
			Translation - HalfSize,
			Translation + HalfSize
		)
	end,

	["Region3int16"] = function(raw)
		return Binary_Descriptors.__PACK_MULTIPLE(Binary_Descriptors["Vector3int16"], raw.Min, raw.Max)
	end,

	["Font"] = function(raw)
		local strDesc = Binary_Descriptors["string"]
		local b_Family, Family_size = strDesc(raw.Family)
		local b_CachedFaceId, CachedFaceId_size = strDesc("")
		local len = 3 + Family_size + CachedFaceId_size
		local b = buffer.create(len)
		local ok_w, weight = pcall(index, raw, "Weight")
		local ok_s, style = pcall(index, raw, "Style")
		buffer.writeu16(b, 0, ok_w and weight.Value or 0)
		buffer.writeu8(b, 2, ok_s and style.Value or 0)
		buffer.copy(b, 3, b_Family)
		buffer.copy(b, 3 + Family_size, b_CachedFaceId)
		return b, len
	end,

	["SecurityCapabilities"] = function(raw)
		local b = buffer.create(8)
		if raw ~= BASE_CAPABILITIES then
			Binary_Descriptors.__writei64(b, 0, CountCapabilityBits(raw))
		end
		return b, 8
	end,

	["Path2DControlPoint"] = function(raw)
		return Binary_Descriptors.__PACK_MULTIPLE(
			Binary_Descriptors["UDim2"],
			raw.Position,
			raw.LeftTangent,
			raw.RightTangent
		)
	end,
}

do
	Binary_Descriptors["NumberSequence"] =
		Binary_Descriptors.__construct_Sequence(Binary_Descriptors["NumberSequenceKeypoint"], 12)
	Binary_Descriptors["ColorSequence"] =
		Binary_Descriptors.__construct_Sequence(Binary_Descriptors["ColorSequenceKeypoint"], 20)
end

do
	Binary_Descriptors.__PACK_F32 = Binary_Descriptors.__construct__PACKER(true)
	Binary_Descriptors.__PACK_I16 = Binary_Descriptors.__construct__PACKER()
end

local ESCAPES_PATTERN = "[&<>\"'\0\1-\9\11-\12\14-\31\127-\255]"
local ESCAPES = {
	["&"] = "&amp;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	['"'] = "&#34;",
	["'"] = "&#39;",
	["\0"] = "",
}

for rangeStart, rangeEnd in string.gmatch(ESCAPES_PATTERN, "(.)%-(.)") do
	for charCode = string.byte(rangeStart), string.byte(rangeEnd) do
		ESCAPES[string.char(charCode)] = "&#" .. charCode .. ";"
	end
end

local XML_Descriptors
XML_Descriptors = {
	__CDATA = function(raw)
		return "<![CDATA[" .. raw .. "]]>"
	end,

	__NORMALIZE_NUMBER = function(raw)
		if raw ~= raw then return "NAN"
		elseif raw == math.huge then return "INF"
		elseif raw == -math.huge then return "-INF"
		end
		return raw
	end,

	__NORMALIZE_RANGE = function(raw)
		return raw ~= raw and "0" or raw
	end,

	__MINMAX = function(min, max, descriptor)
		return "<min>" .. descriptor(min) .. "</min><max>" .. descriptor(max) .. "</max>"
	end,

	__PROTECTEDSTRING = function(raw)
		return string_find(raw, "]]>")
			and string.gsub(raw, ESCAPES_PATTERN, ESCAPES)
			or XML_Descriptors.__CDATA(raw)
	end,

	__construct_Sequence = function(keypoint_handler)
		return function(raw)
			local sequence = ""
			for _, keypoint in raw.Keypoints do
				sequence ..= keypoint_handler(keypoint)
			end
			return sequence
		end
	end,

	__VECTOR = function(X, Y, Z)
		local value = "<X>" .. X .. "</X><Y>" .. Y .. "</Y>"
		if Z then
			value ..= "<Z>" .. Z .. "</Z>"
		end
		return value
	end,

	Axes = function(raw)
		return "<axes>" .. CountBits(raw.X, raw.Y, raw.Z) .. "</axes>"
	end,

	BinaryString = function(raw)
		return raw == "" and "" or base64encode(raw)
	end,

	BrickColor = function(raw)
		return raw.Number
	end,

	CFrame = function(raw)
		local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = raw:GetComponents()
		return XML_Descriptors.__VECTOR(X, Y, Z)
			.. "<R00>" .. R00 .. "</R00><R01>" .. R01 .. "</R01><R02>" .. R02 .. "</R02>"
			.. "<R10>" .. R10 .. "</R10><R11>" .. R11 .. "</R11><R12>" .. R12 .. "</R12>"
			.. "<R20>" .. R20 .. "</R20><R21>" .. R21 .. "</R21><R22>" .. R22 .. "</R22>",
			"CoordinateFrame"
	end,

	Color3 = function(raw)
		return "<R>" .. raw.R .. "</R><G>" .. raw.G .. "</G><B>" .. raw.B .. "</B>"
	end,

	Color3uint8 = function(raw)
		return 0xFF000000
			+ (math.floor(raw.R * 255) * 0x10000)
			+ (math.floor(raw.G * 255) * 0x100)
			+ math.floor(raw.B * 255)
	end,

	ColorSequence = nil,

	ColorSequenceKeypoint = function(keypoint)
		local normalize = XML_Descriptors.__NORMALIZE_RANGE
		local c = keypoint.Value
		return normalize(keypoint.Time) .. " "
			.. normalize(c.R) .. " "
			.. normalize(c.G) .. " "
			.. normalize(c.B) .. " 0 "
	end,

	Content = function(raw)
		local SourceType = raw.SourceType
		return SourceType == Enum.ContentSourceType.None and "<null></null>"
			or SourceType == Enum.ContentSourceType.Uri and "<uri>" .. XML_Descriptors.string(raw.Uri) .. "</uri>"
			or SourceType == Enum.ContentSourceType.Object and "<Ref>" .. GetRef(raw.Object) .. "</Ref>"
			or SourceType == Enum.ContentSourceType.Opaque and "<Ref>" .. GetRef(raw.Opaque) .. "</Ref>"
	end,

	ContentId = function(raw)
		return raw == "" and "<null></null>" or "<url>" .. XML_Descriptors.string(raw) .. "</url>", "Content"
	end,

	CoordinateFrame = function(raw)
		return "<CFrame>" .. XML_Descriptors.CFrame(raw) .. "</CFrame>"
	end,

	EnumItem = function(raw)
		return raw.Value, "token"
	end,

	Faces = function(raw)
		return "<faces>" .. CountBits(raw.Right, raw.Top, raw.Back, raw.Left, raw.Bottom, raw.Front) .. "</faces>"
	end,

	Font = function(raw)
		local ok_w, weight = pcall(index, raw, "Weight")
		local ok_s, style = pcall(index, raw, "Style")
		return "<Family>"
			.. XML_Descriptors.ContentId(raw.Family)
			.. "</Family><Weight>"
			.. (ok_w and XML_Descriptors.EnumItem(weight) or "")
			.. "</Weight><Style>"
			.. (ok_s and style.Name or "")
			.. "</Style>"
	end,

	NetAssetRef = nil,

	NumberRange = function(raw)
		local normalize = XML_Descriptors.__NORMALIZE_RANGE
		return normalize(raw.Min) .. " " .. normalize(raw.Max)
	end,

	NumberSequence = nil,

	NumberSequenceKeypoint = function(keypoint)
		local normalize = XML_Descriptors.__NORMALIZE_RANGE
		return normalize(keypoint.Time) .. " "
			.. normalize(keypoint.Value) .. " "
			.. normalize(keypoint.Envelope) .. " "
	end,

	PhysicalProperties = function(raw)
		local CustomPhysics = "<CustomPhysics>" .. XML_Descriptors.bool(raw and true or false) .. "</CustomPhysics>"
		return raw
			and CustomPhysics
				.. "<Density>" .. raw.Density .. "</Density>"
				.. "<Friction>" .. raw.Friction .. "</Friction>"
				.. "<Elasticity>" .. raw.Elasticity .. "</Elasticity>"
				.. "<FrictionWeight>" .. raw.FrictionWeight .. "</FrictionWeight>"
				.. "<ElasticityWeight>" .. raw.ElasticityWeight .. "</ElasticityWeight>"
				.. "<AcousticAbsorption>" .. raw.AcousticAbsorption .. "</AcousticAbsorption>"
			or CustomPhysics
	end,

	Ray = function(raw)
		local v3 = XML_Descriptors.Vector3
		return "<origin>" .. v3(raw.Origin) .. "</origin><direction>" .. v3(raw.Direction) .. "</direction>"
	end,

	Rect = function(raw)
		return XML_Descriptors.__MINMAX(raw.Min, raw.Max, XML_Descriptors.Vector2), "Rect2D"
	end,

	Region3 = function(raw)
		local Translation = raw.CFrame.Position
		local HalfSize = raw.Size * 0.5
		return XML_Descriptors.__MINMAX(
			Translation - HalfSize,
			Translation + HalfSize,
			XML_Descriptors.Vector3
		)
	end,

	Region3int16 = function(raw)
		return XML_Descriptors.__MINMAX(raw.Min, raw.Max, XML_Descriptors.Vector3int16)
	end,

	SharedString = function(raw)
		return SharedStrings[XML_Descriptors.BinaryString(raw)]
	end,

	SecurityCapabilities = function(raw)
		if raw == BASE_CAPABILITIES then return 0 end
		return CountCapabilityBits(raw)
	end,

	UDim = function(raw)
		return "<S>" .. raw.Scale .. "</S><O>" .. raw.Offset .. "</O>"
	end,

	UDim2 = function(raw)
		local X, Y = raw.X, raw.Y
		return "<XS>" .. X.Scale .. "</XS><XO>" .. X.Offset
			.. "</XO><YS>" .. Y.Scale .. "</YS><YO>" .. Y.Offset .. "</YO>"
	end,

	UniqueId = function(raw)
		return string.gsub(raw, "-", "")
	end,

	Vector2 = function(raw)
		return XML_Descriptors.__VECTOR(raw.X, raw.Y)
	end,

	Vector2int16 = nil,

	Vector3 = function(raw)
		return XML_Descriptors.__VECTOR(raw.X, raw.Y, raw.Z)
	end,

	Vector3int16 = nil,

	bool = function(raw)
		return raw and "true" or "false"
	end,

	double = nil,
	float = nil,
	int = nil,
	int64 = nil,

	string = function(raw)
		return (raw == nil or raw == "") and ""
			or string_find(raw, "]]>") and string.gsub(raw, ESCAPES_PATTERN, ESCAPES)
			or XML_Descriptors.__CDATA(string.gsub(raw, "\0", ""))
	end,
}

do
	XML_Descriptors.NumberSequence = XML_Descriptors.__construct_Sequence(XML_Descriptors.NumberSequenceKeypoint)
	XML_Descriptors.ColorSequence = XML_Descriptors.__construct_Sequence(XML_Descriptors.ColorSequenceKeypoint)
end

for descriptorName, redirectName in {
	NetAssetRef    = "SharedString",
	Vector2int16   = "Vector2",
	Vector3int16   = "Vector3",
	double         = "__NORMALIZE_NUMBER",
	float          = "__NORMALIZE_NUMBER",
	int            = "__NORMALIZE_NUMBER",
	int64          = "__NORMALIZE_NUMBER",
} do
	XML_Descriptors[descriptorName] = XML_Descriptors[redirectName]
end

local ClassList, FetchAPI

do
	local ClassPropertyExceptions = ArrayToDict({
		Whitelist = {
			MeshPart        = { "CollisionFidelity" },
			PartOperation   = { "CollisionFidelity" },
			TriangleMeshPart = { "CollisionFidelity" },
		},
		Blacklist = {
			LuaSourceContainer = { "ScriptGuid" },
			Instance           = { "UniqueId", "HistoryId" },
		},
	}, true)

	local function AttributesSerialize(attrs)
		local attrs_n = 0
		local buffer_size = 4
		local attrs_sorted = {}
		local attrs_formatted = table.clone(attrs)

		for attr, val in attrs do
			attrs_n += 1
			attrs_sorted[attrs_n] = attr
			local Descriptor = Binary_Descriptors[typeof(val)]
			local attr_size
			attrs_formatted[attr], attr_size = Descriptor(val)
			buffer_size += 5 + #attr + attr_size
		end

		table.sort(attrs_sorted)

		local b = buffer.create(buffer_size)
		buffer.writeu32(b, 0, attrs_n)

		local strDesc = Binary_Descriptors["string"]
		local offset = 4
		for _, attr in attrs_sorted do
			local b_Name, Name_size = strDesc(attr)
			buffer.copy(b, offset, b_Name)
			offset += Name_size
			buffer.writeu8(b, offset, attr_Type_IDs[typeof(attrs[attr])])
			offset += 1
			local bb = attrs_formatted[attr]
			buffer.copy(b, offset, bb)
			offset += buffer.len(bb)
		end

		return buffer.tostring(b)
	end

	local function AttenuationSerialize(attenuations)
		if not next(attenuations) then
			return "\0"
		end

		local count = 0
		local sorted = {}
		for key in attenuations do
			count += 1
			sorted[count] = key
		end
		table.sort(sorted)

		local b = buffer.create(1 + count * 8)
		local offset = 1
		for _, key in sorted do
			buffer.writef32(b, offset, key)
			buffer.writef32(b, offset + 4, attenuations[key])
			offset += 8
		end

		return buffer.tostring(b)
	end

	local function TransformsSerialize(transforms)
		local count = #transforms
		if count == 0 then
			return "\1\0\0\0\0\0\0\0"
		end

		local b = buffer.create(8 + count * 48)
		buffer.writeu32(b, 0, 1)
		buffer.writeu32(b, 4, count)

		local packF32 = Binary_Descriptors.__PACK_F32
		local offset = 8

		for _, transform in transforms do
			local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = transform:GetComponents()
			buffer.copy(b, offset,      packF32(R00, R01, R02))
			buffer.copy(b, offset + 12, packF32(R10, R11, R12))
			buffer.copy(b, offset + 24, packF32(R20, R21, R22))
			buffer.copy(b, offset + 36, packF32(X, Y, Z))
			offset += 48
		end

		return buffer.tostring(b)
	end

	local NotScriptableFixes = {
		Instance = {
			AttributesSerialize = function(instance)
				local attrs = instance:GetAttributes()
				if not next(attrs) then return "" end
				return AttributesSerialize(attrs)
			end,
			DefinesCapabilities = "Sandboxed",
			Tags = function(instance)
				local tags = service.CollectionService:GetTags(instance)
				if #tags == 0 then return "" end
				return table.concat(tags, "\0")
			end,
		},
		Path2D = {
			PropertiesSerialize = function(instance)
				local points = instance:GetControlPoints()
				local count = #points
				if count == 0 then return "\0\0\0\0" end

				local b = buffer.create(4 + count * 49)
				buffer.writeu32(b, 0, count)

				local typeID = attr_Type_IDs["Path2DControlPoint"]
				local desc = Binary_Descriptors["Path2DControlPoint"]
				local offset = 4
				for _, point in points do
					local buf = desc(point)
					buffer.writeu8(b, offset, typeID)
					offset += 1
					buffer.copy(b, offset, buf)
					offset += 48
				end

				return buffer.tostring(b)
			end,
		},
		PlayerEmulatorService = {
			SerializedEmulatedPolicyInfo = function(instance)
				local info = instance:GetEmulatedPolicyInfo()
				if not next(info) then return "" end
				return AttributesSerialize(info)
			end,
		},
		StyleRule = {
			PropertiesSerialize = function(instance)
				local props = instance:GetProperties()
				if not next(props) then return "\0\0\0\0" end
				return AttributesSerialize(props)
			end,
		},
		StyleQuery = {
			ConditionsSerialize = function(instance)
				local props = instance:GetConditions()
				if not next(props) then return "\0\0\0\0" end
				return AttributesSerialize(props)
			end,
		},
		MarkerCurve = {
			ValuesAndTimes = function(instance)
				local markers = instance:GetMarkers()
				local count = #markers
				if count == 0 then
					return "\2\0\0\0\0\0\0\0\1\0\0\0\0\0\0\0"
				end

				local stringsSize = 0
				for _, marker in markers do
					stringsSize += #marker.Value + 1
				end

				local b = buffer.create(8 + stringsSize + 8 + count * 4)

				buffer.writeu32(b, 0, 2)
				buffer.writeu32(b, 4, count)

				local offset = 8
				for _, marker in markers do
					local value = marker.Value
					buffer.writestring(b, offset, value)
					offset += #value + 1
				end

				buffer.writeu32(b, offset, 1)
				offset += 4
				buffer.writeu32(b, offset, count)
				offset += 4

				for _, marker in markers do
					buffer.writeu32(b, offset, math.round(marker.Time * 2400))
					offset += 4
				end

				return buffer.tostring(b)
			end,
		},
		AnimationNodeDefinition = {
			InputPinData = function(instance)
				local pins = instance:GetInputPins()
				local count = #pins
				if count == 0 then return "\1\0\0\0\0\0\0\0" end

				local bufSize = 8
				for _, pin in pins do bufSize += 4 + #pin end

				local b = buffer.create(bufSize)
				buffer.writeu32(b, 0, 1)
				buffer.writeu32(b, 4, count)

				local strDesc = Binary_Descriptors["string"]
				local offset = 8
				for _, pin in pins do
					local b_pin, pin_size = strDesc(pin)
					buffer.copy(b, offset, b_pin)
					offset += pin_size
				end

				return buffer.tostring(b)
			end,
		},
		AnimationClip = {
			GuidBinaryString = function(instance)
				local cleanGuid = string.gsub(instance.Guid, "[{}-]", "")
				local bytes = buffer.create(16)
				for i = 0, 15 do
					local hexByte = string.sub(cleanGuid, i * 2 + 1, i * 2 + 2)
					buffer.writeu8(bytes, i, tonumber(hexByte, 16) or 0)
				end
				return buffer.tostring(bytes)
			end,
		},
		AnimationRigData = {
			label = function(instance)
				local labels = instance:GetLabels()
				local count = #labels
				if count == 0 then return "\1\0\0\0\0\0\0\0" end
				local b = buffer.create(8 + count * 4)
				buffer.writeu32(b, 0, 1)
				buffer.writeu32(b, 4, count)
				local offset = 8
				for _, label in labels do
					buffer.writeu32(b, offset, label)
					offset += 4
				end
				return buffer.tostring(b)
			end,
			name = function(instance)
				local names = instance:GetNames()
				local count = #names
				if count == 0 then return "\1\0\0\0\0\0\0\0" end
				local bufSize = 8
				for _, name in names do bufSize += 4 + #name end
				local b = buffer.create(bufSize)
				buffer.writeu32(b, 0, 1)
				buffer.writeu32(b, 4, count)
				local offset = 8
				for _, name in names do
					buffer.writeu32(b, offset, #name)
					offset += 4
				end
				for _, name in names do
					buffer.writestring(b, offset, name)
					offset += #name
				end
				return buffer.tostring(b)
			end,
			parent = function(instance)
				local parents = instance:GetParents()
				local count = #parents
				if count == 0 then return "\1\0\0\0\0\0\0\0" end
				local b = buffer.create(8 + count * 2)
				buffer.writeu32(b, 0, 1)
				buffer.writeu32(b, 4, count)
				local offset = 8
				for _, parent in parents do
					buffer.writeu16(b, offset, parent)
					offset += 2
				end
				return buffer.tostring(b)
			end,
			postTransform = function(instance)
				return TransformsSerialize(instance:GetPostTransforms())
			end,
			preTransform = function(instance)
				return TransformsSerialize(instance:GetPreTransforms())
			end,
			transform = function(instance)
				return TransformsSerialize(instance:GetTransforms())
			end,
		},
		AudioDeviceInput = {
			AccessList = function(instance)
				local list = instance:GetUserIdAccessList()
				local count = #list
				if count == 0 then return "" end
				local b = buffer.create(count * 8)
				local writei64 = Binary_Descriptors.__writei64
				local offset = 0
				for _, userId in list do
					writei64(b, offset, userId)
					offset += 8
				end
				return buffer.tostring(b)
			end,
		},
		AudioEmitter = {
			AngleAttenuation = function(instance)
				return AttenuationSerialize(instance:GetAngleAttenuation())
			end,
			DistanceAttenuation = function(instance)
				return AttenuationSerialize(instance:GetDistanceAttenuation())
			end,
		},
		AudioListener = {
			AngleAttenuation = function(instance)
				return AttenuationSerialize(instance:GetAngleAttenuation())
			end,
			DistanceAttenuation = function(instance)
				return AttenuationSerialize(instance:GetDistanceAttenuation())
			end,
		},
		DebuggerBreakpoint = { line = "Line" },
		BallSocketConstraint = { MaxFrictionTorqueXml = "MaxFrictionTorque" },
		BasePart = {
			Color3uint8 = "Color",
			MaterialVariantSerialized = "MaterialVariant",
			size = "Size",
		},
		DoubleConstrainedValue = { value = "Value" },
		IntConstrainedValue = { value = "Value" },
		CustomEvent = {
			PersistedCurrentValue = function(instance)
				local receiver = instance:GetAttachedReceivers()[1]
				if receiver then
					return receiver:GetCurrentValue()
				end
			end,
		},
		Terrain = {
			AcquisitionMethod = "LastUsedModificationMethod",
			MaterialColors = function(instance)
				local TERRAIN_MATERIALS = {
					Enum.Material.Grass, Enum.Material.Slate, Enum.Material.Concrete,
					Enum.Material.Brick, Enum.Material.Sand, Enum.Material.WoodPlanks,
					Enum.Material.Rock, Enum.Material.Glacier, Enum.Material.Snow,
					Enum.Material.Sandstone, Enum.Material.Mud, Enum.Material.Basalt,
					Enum.Material.Ground, Enum.Material.CrackedLava, Enum.Material.Asphalt,
					Enum.Material.Cobblestone, Enum.Material.Ice, Enum.Material.LeafyGrass,
					Enum.Material.Salt, Enum.Material.Limestone, Enum.Material.Pavement,
				}

				local b = buffer.create(69)
				local offset = 6
				for _, material in TERRAIN_MATERIALS do
					local color = instance:GetMaterialColor(material)
					buffer.writeu8(b, offset,     math.floor(color.R * 255))
					buffer.writeu8(b, offset + 1, math.floor(color.G * 255))
					buffer.writeu8(b, offset + 2, math.floor(color.B * 255))
					offset += 3
				end
				return buffer.tostring(b)
			end,
		},
		TriangleMeshPart = { FluidFidelityInternal = "FluidFidelity" },
		MeshPart = { InitialSize = "MeshSize" },
		PartOperation = { InitialSize = "MeshSize" },
		Part = { shape = "Shape" },
		TrussPart = { style = "Style" },
		FormFactorPart = { formFactorRaw = "FormFactor" },
		Fire = { heat_xml = "Heat", size_xml = "Size" },
		Humanoid = {
			Health_XML = "Health",
			InternalBodyScale = function(instance)
				return instance:GetAccessoryHandleScale(instance.Parent.HumanoidRootPart, Enum.BodyPartR15.RootPart)
			end,
			InternalHeadScale = function(instance)
				return instance:GetAccessoryHandleScale(instance.Parent.Head, Enum.BodyPartR15.Head).X
			end,
		},
		HumanoidDescription = {
			EmotesDataInternal = function(instance)
				local data = ""
				for name, ids in instance:GetEmotes() do
					data ..= name .. "^" .. table.concat(ids, "^") .. "^\\"
				end
				return data
			end,
			EquippedEmotesDataInternal = function(instance)
				local data = ""
				for _, emote in instance:GetEquippedEmotes() do
					data ..= emote.Slot .. "^" .. emote.Name .. "\\"
				end
				return data
			end,
		},
		LocalizationTable = {
			Contents = function(instance)
				return instance:GetContents()
			end,
		},
		MaterialService = { Use2022MaterialsXml = "Use2022Materials" },
		VideoPlayer = { PlayingReplicating = "IsPlaying" },
		Model = {
			ModelMeshCFrame = function(instance)
				return instance:GetModelCFrame()
			end,
			ModelMeshSize = function(instance)
				return instance:GetExtentsSize()
			end,
			Scale = function(instance)
				return instance:GetScale()
			end,
			ScaleFactor = function(instance)
				return instance:GetScale()
			end,
			WorldPivotData = "WorldPivot",
		},
		PackageLink = { PackageIdSerialize = "PackageId", VersionIdSerialize = "VersionNumber" },
		Players = { MaxPlayersInternal = "MaxPlayers", PreferredPlayersInternal = "PreferredPlayers" },
		StarterPlayer = { AvatarJointUpgrade_Serialized = "AvatarJointUpgrade" },
		Smoke = { size_xml = "Size", opacity_xml = "Opacity", riseVelocity_xml = "RiseVelocity" },
		Sound = {
			xmlRead_MinDistance_3 = "RollOffMinDistance",
			xmlRead_MaxDistance_3 = "RollOffMaxDistance",
		},
		ViewportFrame = {
			CameraCFrame = function(instance)
				local cam = instance.CurrentCamera
				return cam and cam.CFrame or CFrame.identity
			end,
			CameraFieldOfView = function(instance)
				local cam = instance.CurrentCamera
				return math.rad(cam and cam.FieldOfView or 70)
			end,
		},
		WeldConstraint = {
			CFrame0 = function(instance)
				local Part0, Part1 = instance.Part0, instance.Part1
				return Part0 and Part1 and Part0.CFrame:ToObjectSpace(Part1.CFrame) or CFrame.identity
			end,
			Part0Internal = "Part0",
			Part1Internal = "Part1",
			State = function(instance)
				return CountBits(instance.Enabled, instance.Active)
			end,
		},
		Workspace = {
			CollisionGroupData = function()
				local groups = game:GetService("PhysicsService"):GetRegisteredCollisionGroups()
				local count = #groups

				if count == 0 then return "\1\0" end

				local bufSize = 2
				for _, group in groups do
					bufSize += 7 + #group.name
				end

				local b = buffer.create(bufSize)
				buffer.writeu8(b, 0, 1)
				buffer.writeu8(b, 1, count)

				local typeID_int32 = attr_Type_IDs["int32"]
				local offset = 2
				for i, group in groups do
					local name = group.name
					local nameLen = #name
					buffer.writeu8(b, offset, i - 1)
					offset += 1
					buffer.writeu8(b, offset, typeID_int32)
					offset += 1
					buffer.writei32(b, offset, group.mask)
					offset += 4
					buffer.writeu8(b, offset, nameLen)
					offset += 1
					buffer.writestring(b, offset, name)
					offset += nameLen
				end

				return buffer.tostring(b)
			end,
		},
	}

	for _, enumItem in Enum.Material:GetEnumItems() do
		NotScriptableFixes.MaterialService[enumItem.Name .. "Name"] = function(instance)
			return instance:GetBaseMaterialOverride(enumItem)
		end
	end

	FetchAPI = function()
		local API_Dump

		local Max_SecurityCapabilities = SecurityCapabilities.new(unpack(Enum.SecurityCapability:GetEnumItems()))
		local filter = { Security = Max_SecurityCapabilities, ExcludeDisplay = true, ExcludeInherited = true }

		local APIDUMP_FETCHERS = {
			[1] = function()
				local res = readfile(FULL_VERSION)
				if res and res ~= "" and service.HttpService:JSONDecode(res) then
					return res
				end
			end,
			[2] = function()
				local clientVersionStr = tostring(CLIENT_VERSION)
				local dump
				local matchingVersions, matched, isMatched, exactMatch = {}, {}

				local function processLine(line, noinsert)
					local fileVersion, patchCommit, versionHash =
						string.match(line, '"%d+%.(%d+)%.([^"]+)": "(version%-[^"]+)')
					if fileVersion == clientVersionStr then
						isMatched = true
						if versionHash and not matched[versionHash] then
							matched[versionHash] = true
							if not noinsert then
								table.insert(matchingVersions, versionHash)
							end
							if string.sub(FULL_VERSION, -#patchCommit) == patchCommit then
								return versionHash
							end
						end
					elseif isMatched then
						return false
					end
				end

				local function fetchFullApiDump(hash)
					local ok, res = pcall(function()
						local raw = game:HttpGet("https://setup.rbxcdn.com/" .. hash .. "-Full-API-Dump.json", true)
						return service.HttpService:JSONEncode(service.HttpService:JSONDecode(raw).Classes)
					end)
					return ok and res or nil
				end

				do
					local ok, r = pcall(game.HttpGet, game,
						"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/version-history.json",
						true)
					if ok then
						local history = string.split(r, "\n")
						history[#history] = nil
						for i = #history, 2, -1 do
							local res = processLine(history[i])
							if res == false then break
							elseif res then exactMatch = res
							end
						end
					end
				end

				do
					local function fallbackChannel(channel)
						local ok, res = pcall(function()
							return service.HttpService:JSONDecode(
								game:HttpGet(
									"https://clientsettings.rbxcdn.com/v2/client-version/WindowsStudio64"
										.. (channel and "/channel/" .. channel or ""),
									true
								)
							)
						end)
						if not ok then return end
						if res.version and res.clientVersionUpload then
							local line = '"' .. res.version .. '": "' .. res.clientVersionUpload
							return processLine(line, true)
						end
					end

					if not exactMatch then
						exactMatch = fallbackChannel("zbeta") or fallbackChannel()
					end
				end

				if exactMatch then
					dump = fetchFullApiDump(exactMatch)
				end
				if not dump then
					for _, hash in matchingVersions do
						dump = fetchFullApiDump(hash)
						if dump then break end
					end
				end

				return dump
			end,
			[3] = function()
				local classes, classesSize = {}, 1

				for _, apiClass in service.ReflectionService:GetClasses(filter) do
					local members, membersSize = {}, 1
					local className = apiClass.Name
					local class = { Name = className, Members = members, Superclass = apiClass.Superclass }
					local permits = apiClass.Permits

					local tags = {}
					if apiClass.Service then
						table.insert(tags, "Service")
					elseif permits and permits["GetService"] then
						table.insert(tags, "Service")
					elseif not permits or not permits["New"] then
						table.insert(tags, "NotCreatable")
					end
					if #tags ~= 0 then class.Tags = tags end

					local ok, props = pcall(
						service.ReflectionService.GetPropertiesOfClass,
						service.ReflectionService, className, filter
					)
					if ok then
						for _, prop in props do
							local propName = prop.Name
							local valueType = prop.Type
							local valueTypeName = valueType.EngineType
							local category = valueType.Category

							if valueTypeName == "Enum" then
								category, valueTypeName = "Enum", valueType.EnumType
							elseif valueTypeName == "RefType" then
								category, valueTypeName = "Class", valueType.InstanceType
							else
								local renames = {
									CoordinateFrame = "CFrame",
									Rect2D          = "Rect",
									Vector3Int16    = "Vector3int16",
									Vector2Int16    = "Vector2int16",
								}
								valueTypeName = renames[valueTypeName] or valueTypeName
							end

							members[membersSize] = {
								Name = propName,
								MemberType = "Property",
								ValueType = { Name = valueTypeName, Category = category },
								Serialization = { CanLoad = prop.Serialized, CanSave = prop.Serialized },
							}
							membersSize += 1
						end
					end

					classes[classesSize] = class
					classesSize += 1
				end

				return service.HttpService:JSONEncode(classes)
			end,
			[4] = function()
				return service.HttpService:JSONEncode(
					service.HttpService:JSONDecode(
						game:HttpGet(
							"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Mini-API-Dump.json",
							true
						)
					).Classes
				)
			end,
		}

		for i, fetcher in APIDUMP_FETCHERS do
			local ok, r = pcall(fetcher)
			if ok and r then
				API_Dump = r
				if i == 2 and writefile then
					writefile(FULL_VERSION, API_Dump)
				end
				break
			elseif r ~= false and 2 < i then
				warn("[USSI] Failed to fetch API dump (method " .. i .. "):", r)
			end
		end

		local classList = {}
		local tmpClassDict = {}
		local ClassesWhitelist = ClassPropertyExceptions.Whitelist
		local ClassesBlacklist = ClassPropertyExceptions.Blacklist
		local decodedDump = service.HttpService:JSONDecode(API_Dump)

		-- First pass: build a flat member lookup per class
		for _, apiClass in decodedDump do
			local className = apiClass.Name
			local props = {}
			for _, member in apiClass.Members do
				local memberType = member.MemberType
				if memberType == "Property" or memberType == "Function" then
					props[member.Name] = {
						ValueType = memberType == "Property" and member.ValueType.Name,
						MemberType = memberType,
					}
				end
			end
			tmpClassDict[className] = props
		end

		-- Second pass: build full class data
		for _, apiClass in decodedDump do
			local classProps, classPropSize = {}, 1
			local class = {
				Properties = classProps,
				Superclass = apiClass.Superclass,
				NotCreatable = nil,
			}

			local className = apiClass.Name
			local classTags = apiClass.Tags

			if classTags then
				local tags = ArrayToDict(classTags, nil, nil, "string")
				class.NotCreatable = tags.NotCreatable
				class.Service = tags.Service
			end

			local nsfClass = NotScriptableFixes[className]
			local classWhitelist = ClassesWhitelist[className]
			local classBlacklist = ClassesBlacklist[className]
			local contentProps

			for _, member in apiClass.Members do
				if member.MemberType == "Property" then
					local serialization = member.Serialization

					if serialization.CanLoad then
						local propName = member.Name
						local valueType = member.ValueType
						local valueTypeName = valueType.Name

						if valueTypeName == "Content" then
							if not contentProps then
								contentProps = {}
								local ok, properties = pcall(
									service.ReflectionService.GetPropertiesOfClass,
									service.ReflectionService, className, filter
								)
								if ok then
									for _, prop in properties do
										contentProps[prop.Name] = prop.Serialized
									end
								end
							end
							if contentProps[propName] ~= nil then
								serialization.CanSave = contentProps[propName]
							end
						end

						if (serialization.CanSave or classWhitelist and classWhitelist[propName])
							and not (classBlacklist and classBlacklist[propName])
						then
							local memberTags = member.Tags
							local isSpecial, preferredDescriptor

							if memberTags then
								for _, tag in memberTags do
									if type(tag) == "table" then
										preferredDescriptor = tag.PreferredDescriptorName
										if preferredDescriptor and isSpecial then break end
									elseif tag == "NotScriptable" then
										isSpecial = true
										if preferredDescriptor then break end
									end
								end
							end

							local preferredDescProp
							if preferredDescriptor then
								preferredDescProp = tmpClassDict[className][preferredDescriptor]
								if preferredDescProp == nil
									or (preferredDescProp.MemberType == "Property"
										and valueTypeName ~= preferredDescProp.ValueType)
								then
									preferredDescriptor = nil
								end
							end

							local property = {
								Name = propName,
								Category = valueType.Category,
								ValueType = valueTypeName,
								Special = isSpecial,
								CanRead = nil,
							}

							if string.sub(valueTypeName, 1, 8) == "Optional" then
								property.Optional = string.sub(valueTypeName, 9)
							end

							local nsfFix = nsfClass and nsfClass[propName]
							local accessFunc = preferredDescriptor
								and (
									preferredDescProp.MemberType == "Property"
									and function(instance) return instance[preferredDescriptor] end
									or function(instance) return instance[preferredDescriptor](instance) end
								)

							property.Fallback = nsfFix
								and (
									type(nsfFix) == "function" and nsfFix
									or accessFunc and function(instance)
										local ok, r = pcall(accessFunc, instance)
										if ok then return r end
										return instance[nsfFix]
									end
									or function(instance) return instance[nsfFix] end
								)
								or accessFunc

							classProps[classPropSize] = property
							classPropSize += 1
						end
					end
				end
			end

			classList[className] = class
		end

		return classList
	end
end

local GLOBAL_ENV = getgenv and getgenv() or _G or shared

--[=[
	@class USSI
	USSI — a clean, rebranded saveinstance with improved decompiler output.
	Original USSI codebase, extended with CleanDecompiledSource post-processing.

	Usage:
	```lua
	local USSI = loadstring(game:HttpGet("YOUR_URL_HERE"))()
	USSI({ SafeMode = true, timeout = 15, SaveBytecode = true })
	```
]=]

local function ripsave(CustomOptions, CustomOptions2)
	if GLOBAL_ENV.RIPSAVE then
		return
	end
	GLOBAL_ENV.RIPSAVE = true

	do
		local setthreadidentity = global_container.setthreadidentity
		if setthreadidentity then
			pcall(setthreadidentity, 8)
		end
	end

	local currentstr, currentsize, totalsize, chunks = "", 0, 0, table.create(1)
	local savebuffer, savebuffer_size = {}, 1
	local header = '<!-- Saved by USSI Ripoff --><roblox version="4">'

	local StatusText

	local OPTIONS = {
		mode = "optimized",
		noscripts = false,
		scriptcache = true,
		timeout = 10,
		__DEBUG_MODE = false,

		Callback = false,
		DecompileJobless = false,
		DecompileIgnore = {
			"TextChatService",
			ModuleScript = nil,
		},
		IgnoreDefaultPlayerScripts = true,
		SaveBytecode = false,
		CleanOutput = true, -- RipSave: run CleanDecompiledSource on all decompiled scripts

		IgnoreProperties = {},
		IgnoreList = { "CoreGui", "CorePackages" },
		ExtraInstances = {},
		NilInstances = false,
		NilInstancesFixes = {},

		SaveCacheInterval = 0x1600 * 10,
		ShowStatus = true,
		KillAllScripts = true,
		SafeMode = true,
		ShutdownWhenDone = false,
		AntiIdle = true,
		Anonymous = false,
		ReadMe = true,
		FilePath = false,
		AvoidFileOverwrite = true,
		Object = false,
		IsModel = false,

		IgnoreDefaultProperties = true,
		IgnoreNotArchivable = true,
		IgnorePropertiesOfNotScriptsOnScriptsMode = false,
		IgnoreSpecialProperties = ArrayToDict({ "Fluxus", "Delta", "Solara" })[EXECUTOR_NAME] or false,

		IsolateLocalPlayer = false,
		IsolateLocalPlayerCharacter = false,
		IsolatePlayers = false,
		IsolateStarterPlayer = false,
		RemovePlayerCharacters = true,

		SaveNotCreatable = false,
		NotCreatableFixes = {
			"",
			"AdvancedDragger",
			"AnimationTrack",
			"Dragger",
			"Player",
			"PlayerGui",
			"PlayerMouse",
			"PlayerScripts",
			"ScreenshotHud",
			"StudioData",
			"TextChatMessage",
			"TextSource",
			"TouchTransmitter",
			"Translator",
			CloudLocalizationTable = "LocalizationTable",
			Platform = "Part",
			Status = "Model",
		},

		IgnoreSharedStrings = EXECUTOR_NAME ~= "Wave",
		SharedStringOverwrite = false,
		TreatUnionsAsParts = EXECUTOR_NAME == "Solara",
		AlternativeWritefile = not ArrayToDict({ "WRD", "Xeno", "Zorara" })[EXECUTOR_NAME],

		OptionsAliases = {
			DecompileTimeout = "timeout",
			FileName = "FilePath",
			IgnoreArchivable = "IgnoreNotArchivable",
			IgnoreDefaultProps = "IgnoreDefaultProperties",
			InstancesBlacklist = "IgnoreList",
			IsolatePlayerGui = "IsolateLocalPlayer",
			SaveNonCreatable = "SaveNotCreatable",
			SavePlayers = "IsolatePlayers",
		},
	}

	local OPTIONS_lowercase, CustomOptions_valid = {}, {}
	for option_name in OPTIONS do
		local lower = string.lower(option_name)
		if OPTIONS_lowercase[lower] then
			warn("[RipSave] Duplicate option key:", option_name)
		else
			OPTIONS_lowercase[lower] = option_name
		end
	end
	for alias, option_name in OPTIONS.OptionsAliases do
		local lower = string.lower(alias)
		if OPTIONS_lowercase[lower] then
			warn("[RipSave] Duplicate alias key:", alias)
		else
			OPTIONS_lowercase[lower] = option_name
		end
	end

	do -- Load Settings
		local function construct_NilinstanceFix(name, className, separate)
			return function(instance, instancePropertyOverrides)
				local existing = not separate and OPTIONS.NilInstancesFixes[name]
				local fix

				if not existing then
					fix = Instance.new(className)
					if not separate then
						OPTIONS.NilInstancesFixes[name] = fix
					end
					instancePropertyOverrides[fix] = {
						__SaveSpecific = true,
						__Children = { instance },
						Properties = { Name = name },
					}
				else
					fix = existing
					table.insert(instancePropertyOverrides[fix].__Children, instance)
				end

				if not existing then
					return fix
				end
			end
		end

		OPTIONS.NilInstancesFixes.Animator =
			construct_NilinstanceFix("Animator has to be placed under Humanoid or AnimationController", "AnimationController")
		OPTIONS.NilInstancesFixes.AdPortal =
			construct_NilinstanceFix("AdPortal must be parented to a Part", "Part")
		OPTIONS.NilInstancesFixes.Attachment =
			construct_NilinstanceFix("Attachments must be parented to a BasePart or another Attachment", "Part")
		OPTIONS.NilInstancesFixes.BaseWrap =
			construct_NilinstanceFix("BaseWrap must be parented to a MeshPart", "MeshPart")
		OPTIONS.NilInstancesFixes.PackageLink =
			construct_NilinstanceFix("Package already has a PackageLink", "Folder", true)

		if CustomOptions2 and type(CustomOptions2) == "table" then
			local tmp = CustomOptions
			local tmpType = typeof(tmp)
			CustomOptions = CustomOptions2
			if tmpType == "Instance" then
				CustomOptions.Object = tmp
			elseif tmpType == "table" and typeof(tmp[1]) == "Instance" then
				CustomOptions.ExtraInstances = tmp
				OPTIONS.IsModel = true
			end
		end

		local optType = typeof(CustomOptions)

		if optType == "table" then
			if typeof(CustomOptions[1]) == "Instance" then
				OPTIONS.mode = "invalidmode"
				OPTIONS.ExtraInstances = CustomOptions
				OPTIONS.IsModel = true
				CustomOptions = {}
			else
				for key, value in CustomOptions do
					local option = OPTIONS_lowercase[string.lower(key)]
					if option then
						OPTIONS[option] = value
						CustomOptions_valid[option] = true
					end
				end
				if CustomOptions.Decompile ~= nil then
					OPTIONS.noscripts = not CustomOptions.Decompile
				end
				if CustomOptions.SavePlayerCharacters ~= nil then
					OPTIONS.RemovePlayerCharacters = not CustomOptions.SavePlayerCharacters
				end
				if CustomOptions.RemovePlayers ~= nil then
					OPTIONS.IsolatePlayers = not CustomOptions.RemovePlayers
				end
			end
		elseif optType == "Instance" then
			OPTIONS.mode = "invalidmode"
			OPTIONS.Object = CustomOptions
			CustomOptions = {}
		else
			CustomOptions = {}
		end
	end

	if not writefile and not OPTIONS.Callback then
		local function coreCall(method, ...)
			local StarterGui = service.StarterGui
			method = StarterGui[method]
			if not method then return end
			for _ = 1, 10 do
				local ok, result = pcall(method, StarterGui, ...)
				if ok then return result end
				task.wait(1)
			end
		end

		local text = '[RipSave] "writefile" is NOT available. Use the "Callback" option instead.'
		coreCall("SetCore", "SendNotification", {
			Title = "RipSave Error",
			Text = text,
			Duration = 15,
			Icon = "rbxassetid://9072920609",
		})
		warn(text)
		GLOBAL_ENV.RIPSAVE = nil
		return
	end

	if OPTIONS.IgnoreDefaultPlayerScripts then
		local DecompileIgnore = OPTIONS.DecompileIgnore
		local defaultScripts = ArrayToDict({
			ModuleScript = { "PlayerModule" },
			LocalScript = { "BubbleChat", "ChatScript", "PlayerScriptsLoader", "RbxCharacterSounds" },
		}, true)

		local function ignorePath(path)
			if path then
				for _, child in path:GetChildren() do
					local classMatch = defaultScripts[child.ClassName]
					if classMatch and classMatch[child.Name] then
						table.insert(DecompileIgnore, child)
					end
				end
			end
		end

		ignorePath(service.StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts"))
		local LocalPlayer = service.Players.LocalPlayer
		if LocalPlayer then
			ignorePath(LocalPlayer:FindFirstChildOfClass("PlayerScripts"))
		end
	end

	local InstancesOverrides = {}

	local DecompileIgnore = ArrayToDict(OPTIONS.DecompileIgnore, true)
	local IgnoreList      = ArrayToDict(OPTIONS.IgnoreList, true)
	local IgnoreProperties = ArrayToDict(OPTIONS.IgnoreProperties)
	local NotCreatableFixes = ArrayToDict(OPTIONS.NotCreatableFixes, true, "Folder")

	local DEBUG = OPTIONS.__DEBUG_MODE
	if DEBUG and type(DEBUG) ~= "function" then
		DEBUG = warn
	end

	local SafeMode = OPTIONS.SafeMode
	local FilePath = OPTIONS.FilePath
	local SaveCacheInterval = OPTIONS.SaveCacheInterval
	local ToSaveInstance = OPTIONS.Object
	local IsModel = OPTIONS.IsModel

	if ToSaveInstance and CustomOptions.IsModel == nil then
		IsModel = true
	end

	local IgnoreDefaultProperties = OPTIONS.IgnoreDefaultProperties
	local IgnoreNotArchivable = not OPTIONS.IgnoreNotArchivable
	local IgnorePropertiesOfNotScriptsOnScriptsMode = OPTIONS.IgnorePropertiesOfNotScriptsOnScriptsMode
	local CleanOutput = OPTIONS.CleanOutput

	local old_gethiddenproperty
	if OPTIONS and gethiddenproperty then
		old_gethiddenproperty = gethiddenproperty
		gethiddenproperty = nil
	end

	local SaveNotCreatable = OPTIONS.SaveNotCreatable
	local TreatUnionsAsParts = OPTIONS.TreatUnionsAsParts
	local DecompileJobless = OPTIONS.DecompileJobless

	if DecompileJobless then
		OPTIONS.scriptcache = true
	end

	local ScriptCache = OPTIONS.scriptcache and getscriptbytecode
	local Timeout = OPTIONS.timeout
	local IgnoreSharedStrings = OPTIONS.IgnoreSharedStrings
	local SharedStringOverwrite = OPTIONS.SharedStringOverwrite
	local ldeccache = GLOBAL_ENV.scriptcache

	local DecompileIgnoring, ToSaveList, ldecompile, placename, elapse_t, SaveNotCreatableWillBeEnabled, RecoveredScripts

	if OPTIONS.ReadMe then
		RecoveredScripts = {}
	end

	if ScriptCache and not ldeccache then
		ldeccache = {}
		GLOBAL_ENV.scriptcache = ldeccache
	end

	if ToSaveInstance == game then
		OPTIONS.mode = "full"
		ToSaveInstance = nil
		IsModel = nil
	end

	local function isLuaSourceContainer(instance)
		return instance:IsA("LuaSourceContainer")
	end

	do
		local mode = string.lower(OPTIONS.mode)
		local tmp = table.clone(OPTIONS.ExtraInstances)
		local PlaceName = game.PlaceId

		pcall(function()
			PlaceName ..= " " .. service.MarketplaceService:GetProductInfoAsync(PlaceName).Name
		end)

		local function sanitizeFileName(str)
			return string.sub(
				string.gsub(string.gsub(string.gsub(str, "[^%w _]", ""), " +", " "), " +$", ""),
				1, 240
			)
		end

		if ToSaveInstance then
			if mode == "optimized" then mode = "full" end
			for _, key in { "IsolateLocalPlayer", "IsolateLocalPlayerCharacter", "IsolatePlayers", "IsolateStarterPlayer", "NilInstances" } do
				if CustomOptions_valid[key] == nil then
					OPTIONS[key] = false
				end
			end
		end

		local filetype = IsModel and ".rbxmx" or ".rbxlx"

		if FilePath then
			placename = FilePath
		elseif IsModel then
			placename = sanitizeFileName("model " .. PlaceName .. " " .. (ToSaveInstance or tmp[1] or game):GetFullName())
		else
			placename = sanitizeFileName("place " .. PlaceName)
		end

		if OPTIONS.AvoidFileOverwrite and isfile then
			local counter = 0
			local temp = placename
			while isfile(temp .. filetype) do
				counter += 1
				temp = placename .. "(" .. counter .. ")"
			end
			placename = temp .. filetype
		else
			placename = placename .. filetype
		end

		if GLOBAL_ENV[placename] then return end
		GLOBAL_ENV[placename] = true
		GLOBAL_ENV.RIPSAVE = nil

		if mode ~= "scripts" then
			IgnorePropertiesOfNotScriptsOnScriptsMode = nil
		end

		local TempRoot = ToSaveInstance or game

		if mode == "full" then
			if not ToSaveInstance then
				local children = TempRoot:GetChildren()
				if #children > 0 then
					local tmpDict = ArrayToDict(tmp)
					for _, child in children do
						if not tmpDict[child] then
							table.insert(tmp, child)
						end
					end
				end
			end
		elseif mode == "optimized" then
			local tmpDict = ArrayToDict(tmp)
			for _, serviceName in {
				"Workspace", "Players", "Lighting", "MaterialService",
				"ReplicatedFirst", "ReplicatedStorage",
				"ServerScriptService", "ServerStorage",
				"StarterGui", "StarterPack", "StarterPlayer",
				"Teams", "SoundService", "Chat", "TextChatService",
				"LocalizationService", "JointsService",
			} do
				local svc = game:FindService(serviceName)
				if svc and not tmpDict[svc] then
					table.insert(tmp, svc)
				end
			end
		elseif mode == "scripts" then
			local unique = {}
			for _, instance in TempRoot:GetDescendants() do
				if isLuaSourceContainer(instance) then
					local parent = instance.Parent
					while parent and parent ~= TempRoot do
						instance = instance.Parent
						parent = instance.Parent
					end
					if parent then unique[instance] = true end
				end
			end
			for instance in unique do
				table.insert(tmp, instance)
			end
		end

		ToSaveList = tmp
		if ToSaveInstance then
			table.insert(ToSaveList, 1, ToSaveInstance)
		end
	end

	local IsolateLocalPlayer = OPTIONS.IsolateLocalPlayer
	local IsolateLocalPlayerCharacter = OPTIONS.IsolateLocalPlayerCharacter
	local IsolatePlayers = OPTIONS.IsolatePlayers
	local IsolateStarterPlayer = OPTIONS.IsolateStarterPlayer
	local NilInstances = OPTIONS.NilInstances

	if NilInstances and enablenilinstances then
		enablenilinstances()
	end

	local function get_size_format()
		for i, unit in { "B", "KB", "MB", "GB", "TB" } do
			if totalsize < 0x400 ^ i then
				return math.floor(totalsize / (0x400 ^ (i - 1)) * 10) / 10 .. " " .. unit
			end
		end
	end

	local RunService = service.RunService
	local function wait_for_render()
		RunService.RenderStepped:Wait()
	end

	local Loading
	local function run_with_loading(text, keepStatus, waitForRender, taskFunction, ...)
		local previousStatus

		if StatusText then
			if keepStatus then previousStatus = StatusText.Text end
			Loading = task.spawn(function()
				local spinnerCount = 0
				local chars = { "|", "/", "—", "\\" }
				local charsSize = #chars
				text ..= " "
				while true do
					spinnerCount = spinnerCount % charsSize + 1
					StatusText.Text = text .. chars[spinnerCount]
					task.wait(0.25)
				end
			end)
			if waitForRender then wait_for_render() end
		end

		local result = { taskFunction(...) }

		if Loading then
			task.cancel(Loading)
			Loading = nil
			if previousStatus then StatusText.Text = previousStatus end
		end

		return unpack(result)
	end

	local function construct_TimeoutHandler(timeout, f, timeout_ret)
		return timeout < 0 and function(script)
			return pcall(f, script)
		end or function(script)
			local thread = coroutine.running()
			local timeoutThread, isCancelled

			timeoutThread = task.delay(timeout, function()
				isCancelled = true
				coroutine.resume(thread, nil, timeout_ret)
			end)

			task.spawn(function()
				local ok, result = pcall(f, script)
				if isCancelled then return end
				task.cancel(timeoutThread)
				while coroutine.status(thread) ~= "suspended" do task.wait() end
				coroutine.resume(thread, ok, result)
			end)

			return coroutine.yield()
		end
	end

	local getbytecode
	if getscriptbytecode then
		getbytecode = construct_TimeoutHandler(3, getscriptbytecode)
	end

	local SaveBytecode
	if OPTIONS.SaveBytecode and getscriptbytecode then
		SaveBytecode = function(script)
			local ok, bytecode = getbytecode(script)
			if ok and bytecode and bytecode ~= "" then
				return "-- Bytecode (Base64):\n-- " .. base64encode(bytecode) .. "\n\n"
			end
		end
	end

	do
		local Decompiler = decompile

		if OPTIONS.noscripts then
			ldecompile = function()
				return "-- Decompiling is disabled"
			end
		elseif Decompiler then
			local decomp = construct_TimeoutHandler(Timeout, Decompiler, "Decompiler timed out")

			ldecompile = function(script)
				local bytecode
				if ScriptCache then
					local ok
					ok, bytecode = getbytecode(script)
					if ok then
						if not bytecode or bytecode == "" then
							return "-- The Script is Empty"
						end
						local cached = ldeccache[bytecode]
						if cached then
							if DEBUG then DEBUG("[RipSave] Cache hit:", script:GetFullName()) end
							return cached
						end
					else
						bytecode = nil
					end
				else
					if DecompileJobless then
						return "-- Not found in decompile cache"
					end
				end

				local ok, result = run_with_loading("Decompiling " .. script.Name, true, nil, decomp, script)
				if not result then ok, result = false, "Empty Output" end

				local output
				if ok then
					result = string.gsub(result, "\0", "\\0")
					-- ── RipSave: clean the decompiler output ──
					if CleanOutput then
						result = CleanDecompiledSource(result)
					end
					output = result
				else
					output = "--[[ Failed to decompile. Reason:\n" .. (result or "") .. "\n]]"
				end

				if ScriptCache and bytecode then
					ldeccache[bytecode] = output
					if DEBUG then DEBUG("[RipSave] Cached:", script:GetFullName()) end
				end

				return output
			end
		else
			ldecompile = function()
				return "-- Your executor does not have a decompiler"
			end
		end
	end

	local function GetLocalPlayer()
		return service.Players.LocalPlayer
			or service.Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
			or service.Players.LocalPlayer
	end

	local function filterLinkedSource(str)
		local ok, r = pcall(service.HttpService.JSONDecode, service.HttpService, str)
		if ok and r.errors then return end
		return true
	end

	local function replaceClassName(instance, instanceName, className)
		local override
		if instanceName ~= className then
			override = InstancesOverrides[instance]
			if not override then
				override = { Properties = { Name = "[" .. className .. "] " .. instanceName } }
				InstancesOverrides[instance] = override
			end
		end
		return override
	end

	local function filterPropVal(result, propName, category)
		return result == nil
			or result == "can't get value"
			or type(result) == "string"
				and (category == "Enum" or string_find(result, "Unable to get property " .. propName))
	end

	local BREAK_SENTINEL = "__RIPSAVE_BREAK__" .. service.HttpService:GenerateGUID(false)

	local function ReadProperty(instance, property, propName, special, category, optional)
		local raw = BREAK_SENTINEL

		local override = InstancesOverrides[instance]
		if override then
			local propsOverride = override.Properties
			if propsOverride then
				local propOverride = propsOverride[propName]
				if propOverride ~= nil then
					return propOverride
				end
			end
		end

		local canRead = property.CanRead
		if canRead == false then return BREAK_SENTINEL end

		if special then
			if gethiddenproperty then
				local ok, result = pcall(gethiddenproperty, instance, propName)
				if ok then raw = result end
				if filterPropVal(raw, propName, category) then
					if result ~= nil or not optional then
						if DEBUG then DEBUG("[RipSave] Filtered:", propName) end
						property.CanRead = false
					end
					return BREAK_SENTINEL
				end
			end
		else
			if canRead then
				raw = instance[propName]
			else
				local ok, result = pcall(index, instance, propName)
				if ok then
					raw = result
				elseif gethiddenproperty then
					ok, result = pcall(gethiddenproperty, instance, propName)
					if ok then
						raw = result
						property.Special = true
					end
				end
				property.CanRead = ok
				if not ok or filterPropVal(raw, propName, category) then
					return BREAK_SENTINEL
				end
			end
		end

		return raw
	end

	local function ReturnItem(className, instance)
		return '<Item class="' .. className .. '" referent="' .. GetRef(instance) .. '"><Properties>'
	end

	local function ReturnProperty(tag, propName, value)
		return "<" .. tag .. ' name="' .. propName .. '">' .. value .. "</" .. tag .. ">"
	end

	local function ReturnValueAndTag(raw, valueType, descriptor)
		local value, tag = (descriptor or XML_Descriptors[valueType])(raw)
		return value, tag or valueType
	end

	local function InheritsFix(fixes, className, instance)
		local fix = fixes[className]
		if fix then return fix end
		if fix == nil then
			for class_name, f in fixes do
				if instance:IsA(class_name) then return f end
			end
		end
	end

	local function GetInheritedProps(className)
		local cached = inherited_properties[className]
		if cached then return cached end

		local propList = {}
		local layer = ClassList[className]
		while layer do
			local layerProps = layer.Properties
			table.move(layerProps, 1, #layerProps, #propList + 1, propList)
			layer = ClassList[layer.Superclass]
		end

		inherited_properties[className] = propList
		return propList
	end

	local CHUNK_LIMIT = 200 * 1024 * 1024

	local function save_cache(final)
		local savestr = table.concat(savebuffer)
		currentstr ..= savestr

		local savestrLen = #savestr
		totalsize += savestrLen
		currentsize += savestrLen

		table.clear(savebuffer)
		savebuffer_size = 1

		if CHUNK_LIMIT < currentsize or final then
			table.insert(chunks, { size = currentsize, str = currentstr })
			currentstr, currentsize = "", 0
		end

		if StatusText then
			StatusText.Text = "Saving.. Size: " .. get_size_format()
		end

		wait_for_render()
	end

	local function save_specific(className, properties)
		local ref = Instance.new(className)
		local item = ReturnItem(ref.ClassName, ref)

		for propName, val in properties do
			local whitelisted, value, tag

			if propName == "Source" then
				tag = "ProtectedString"
				value = XML_Descriptors.__PROTECTEDSTRING(val)
				whitelisted = true
			elseif propName == "Name" then
				whitelisted = true
				value, tag = ReturnValueAndTag(val, "string")
			end

			if whitelisted then
				item ..= ReturnProperty(tag, propName, value)
			end
		end

		item ..= "</Properties>"
		return item
	end

	local gethiddenproperty_fallback

	local function save_hierarchy(hierarchy)
		for _, instance in hierarchy do
			local instanceOverride, classTagOverride, classNameOverride

			if not instanceOverride then
				instanceOverride = InstancesOverrides[instance]
				if instanceOverride then
					classTagOverride = instanceOverride.__ClassName
				end
			end

			local className = instance.ClassName
			local instanceName = instance.Name
			local skipEntirely

			if not classTagOverride then
				if IgnoreNotArchivable and not instance.Archivable then continue end

				skipEntirely = IgnoreList[instance]
				if skipEntirely then continue end

				do
					local onIgnoredList = IgnoreList[className]
					if onIgnoredList and (onIgnoredList == true or onIgnoredList[instanceName]) then
						continue
					end
				end

				if not DecompileIgnoring then
					DecompileIgnoring = DecompileIgnore[instance]
					if DecompileIgnoring == nil then
						local ignored = DecompileIgnore[className]
						if ignored then
							DecompileIgnoring = ignored == true or ignored[instanceName]
						end
					end
					if DecompileIgnoring then
						DecompileIgnoring = instance
					elseif DecompileIgnoring == false then
						DecompileIgnoring = 1
					end
				end

				do
					local fix = NotCreatableFixes[className]
					if fix then
						if SaveNotCreatable then
							className, instanceOverride = fix, replaceClassName(instance, instanceName, className)
						else
							continue
						end
					else
						if TreatUnionsAsParts and instance:IsA("PartOperation") then
							className, instanceOverride = "Part", replaceClassName(instance, instanceName, className)
							classNameOverride = "BasePart"
						elseif not ClassList[className] then
							if DEBUG then DEBUG("[RipSave] Unknown class:", className) end
							classTagOverride = className
							className = "Folder"
						end
					end
				end
			end

			if instanceOverride and instanceOverride.__SaveSpecific then
				savebuffer[savebuffer_size] = save_specific(className, instanceOverride.Properties)
				savebuffer_size += 1
			else
				savebuffer[savebuffer_size] = ReturnItem(classTagOverride or className, instance)
				savebuffer_size += 1

				if not (IgnorePropertiesOfNotScriptsOnScriptsMode and not isLuaSourceContainer(instance)) then
					local defaultInstance, newDefInst

					if IgnoreDefaultProperties then
						defaultInstance = default_instances[className]
						if not defaultInstance then
							local class = ClassList[className]
							if not class.NotCreatable then
								local ok, result = pcall(Instance.new, className)
								if ok then
									newDefInst = result
									defaultInstance = {}
									default_instances[className] = defaultInstance
								else
									class.NotCreatable = true
									if DEBUG then DEBUG("[RipSave] Can't create default instance:", className, result) end
								end
							elseif DEBUG then
								DEBUG("[RipSave] NotCreatable, skipping default instance:", className)
							end
						end
					end

					for _, property in GetInheritedProps(classNameOverride or className) do
						local propName = property.Name

						if IgnoreProperties[propName] then continue end

						local valueType = property.ValueType
						if IgnoreSharedStrings and valueType == "SharedString" then continue end

						local special, category, optional = property.Special, property.Category, property.Optional

						local raw = ReadProperty(instance, property, propName, special, category, optional)

						if raw == BREAK_SENTINEL then
							local ghpfFailed, fallback = property.GHPFFailed, property.Fallback
							if ghpfFailed and not fallback then continue end

							if not ghpfFailed then
								local ok, result = pcall(gethiddenproperty_fallback, instance, propName)
								if result == nil and not optional then ok = nil end
								if ok then
									raw = result
								else
									ghpfFailed = true
									property.GHPFFailed = ghpfFailed
								end
							end

							if ghpfFailed and fallback then
								local ok, result = pcall(fallback, instance)
								if ok then
									raw = result
								else
									property.Fallback = nil
									if DEBUG then DEBUG("[RipSave] Fallback failed:", propName, result) end
									continue
								end
							end

							if raw == BREAK_SENTINEL then continue end
						end

						if SharedStringOverwrite and valueType == "BinaryString" then
							valueType = "SharedString"
						end

						if defaultInstance
							and property.CanRead
							and not property.Special
							and not (propName == "Source" and isLuaSourceContainer(instance))
						then
							if newDefInst then
								defaultInstance[propName] = index(newDefInst, propName)
							end
							if defaultInstance[propName] == raw then continue end
						end

						local tag, value
						if category == "Class" then
							tag = "Ref"
							if raw then
								if SaveNotCreatableWillBeEnabled then
									local fix = NotCreatableFixes[raw.ClassName]
									if fix and (propName == "PlayerToHideFrom" or valueType ~= "Instance" and valueType ~= fix) then
										continue
									end
								end
								value = GetRef(raw)
							else
								value = "null"
							end
						elseif category == "Enum" then
							value, tag = XML_Descriptors.EnumItem(raw)
						else
							local descriptor = XML_Descriptors[valueType]
							if descriptor then
								value, tag = ReturnValueAndTag(raw, valueType, descriptor)
							elseif valueType == "ProtectedString" then
								tag = valueType
								if propName == "Source" then
									if DecompileIgnoring then
										if DecompileIgnoring == 1 then DecompileIgnoring = nil end
										value = "-- Ignored"
									else
										local shouldDecompile = true
										local linkedSource
										local linkedSourceUrl = instance.LinkedSource
										local hasLinkedSource = linkedSourceUrl ~= ""
										local linkedSourceType

										if hasLinkedSource then
											if RecoveredScripts then
												table.insert(RecoveredScripts, instance:GetFullName())
											end
											linkedSource = string.match(linkedSourceUrl, "%w+$")
											if linkedSource then
												if ScriptCache then
													local cached = ldeccache[linkedSource]
													if cached then
														value = cached
														shouldDecompile = nil
													end
												end
												if shouldDecompile then
													if DecompileJobless then
														value = "-- Not found in LinkedSource cache"
														shouldDecompile = nil
													end
													linkedSourceType = string.find(linkedSource, "%a") and "hash" or "id"
													local asset = linkedSourceType .. "=" .. linkedSource
													local ok, source = pcall(function()
														return game:HttpGet("https://assetdelivery.roproxy.com/v1/asset/?" .. asset)
													end)
													if ok and filterLinkedSource(source) then
														if ScriptCache then ldeccache[linkedSource] = source end
														value = source
														shouldDecompile = nil
													end
												end
											else
												warn("[RipSave] Could not extract original script source:", instance:GetFullName(), linkedSourceUrl)
											end
										end

										if shouldDecompile then
											local isLocalScript = instance:IsA("LocalScript")
											if (isLocalScript and instance.RunContext == Enum.RunContext.Server)
												or (not isLocalScript and instance:IsA("Script") and instance.RunContext ~= Enum.RunContext.Client)
											then
												value = "-- [FilteringEnabled] Server Scripts cannot be saved"
											else
												value = ldecompile(instance)
												if SaveBytecode then
													local byteOutput = SaveBytecode(instance)
													if byteOutput then value = byteOutput .. value end
												end
											end
										end

										value = "-- Saved by RipSave https://discord.gg/wx4ThpAsmw\n\n"
											.. (hasLinkedSource
												and "-- Original Source: https://assetdelivery.roblox.com/v1/asset/?"
													.. (linkedSourceType or "id") .. "=" .. (linkedSource or linkedSourceUrl) .. "\n\n"
												or "")
											.. value
									end
								end
								value = XML_Descriptors.__PROTECTEDSTRING(value)
							else
								if optional then
									local descriptor = XML_Descriptors[optional]
									if descriptor then
										if raw == nil then continue end
										value, tag = ReturnValueAndTag(raw, valueType, descriptor)
									end
								end
							end
						end

						if tag then
							savebuffer[savebuffer_size] = ReturnProperty(tag, propName, value)
							savebuffer_size += 1
						else
							warn("[RipSave] Unsupported type (please report):", valueType, className, propName)
						end
					end
				end

				savebuffer[savebuffer_size] = "</Properties>"
				savebuffer_size += 1

				if SaveCacheInterval < savebuffer_size then
					save_cache()
				end
			end

			if skipEntirely ~= false then
				local children = instanceOverride and instanceOverride.__Children or instance:GetChildren()
				if #children ~= 0 then
					save_hierarchy(children)
				end
			end

			if DecompileIgnoring and DecompileIgnoring == instance then
				DecompileIgnoring = nil
			end

			savebuffer[savebuffer_size] = "</Item>"
			savebuffer_size += 1
		end
	end

	local function save_extra(name, instanceOrTable, saveProps, customClassName, source)
		customClassName = customClassName or "Folder"
		local properties = { Name = name, Source = source }
		local hierarchy

		if instanceOrTable then
			if type(instanceOrTable) == "table" then
				hierarchy = instanceOrTable
			else
				hierarchy = instanceOrTable:GetChildren()
				if saveProps then
					InstancesOverrides[instanceOrTable] = {
						__ClassName = customClassName,
						__Children = hierarchy,
						Properties = properties,
					}
					save_hierarchy({ instanceOrTable })
				end
			end
		end

		if not saveProps then
			savebuffer[savebuffer_size] = save_specific(customClassName, properties)
			savebuffer_size += 1
			if hierarchy then save_hierarchy(hierarchy) end
			savebuffer[savebuffer_size] = "</Item>"
			savebuffer_size += 1
		end
	end

	local function save_game()
		do
			if IsModel then
				header ..= '<Meta name="ExplicitAutoJoints">true</Meta>'
			end
			if writefile and not OPTIONS.Callback then
				writefile(placename, header)
			end
		end

		SaveNotCreatableWillBeEnabled = SaveNotCreatable
			or (IsolateLocalPlayer or IsolateLocalPlayerCharacter) and IsolateLocalPlayer
			or IsolatePlayers
			or NilInstances and global_container.getnilinstances

		save_hierarchy(ToSaveList)

		if IsolateLocalPlayer or IsolateLocalPlayerCharacter then
			local lp = service.Players.LocalPlayer
			if lp then
				if IsolateLocalPlayer then
					SaveNotCreatable = true
					save_extra("LocalPlayer", lp, true)
				end
				if IsolateLocalPlayerCharacter then
					local char = lp.Character
					if char then
						save_extra("LocalPlayer Character", char, true, "Model")
					end
				end
			end
		end

		if IsolateStarterPlayer then
			save_extra("StarterPlayer", service.StarterPlayer)
		end

		if IsolatePlayers then
			SaveNotCreatable = true
			save_extra("Players", service.Players)
		end

		if NilInstances and global_container.getnilinstances then
			local nilInstances, nilCount = {}, 1
			local nilFixes = OPTIONS.NilInstancesFixes

			for _, instance in global_container.getnilinstances() do
				if instance == game then
					instance = nil
				else
					local className = instance.ClassName
					local fix = InheritsFix(nilFixes, className, instance)
					if fix then
						instance = fix(instance, InstancesOverrides)
					end
					local class = ClassList[className]
					if class and class.Service then
						instance = nil
					end
				end
				if instance then
					nilInstances[nilCount] = instance
					nilCount += 1
				end
			end

			SaveNotCreatable = true
			save_extra("Nil Instances", nilInstances)
		end

		if OPTIONS.ReadMe then
			save_extra(
				"README",
				nil, nil,
				"Script",
				"--[[\n"
					.. (#RecoveredScripts ~= 0
						and "\t\tIMPORTANT: Original source recovered for: "
							.. service.HttpService:JSONEncode(RecoveredScripts) .. "\n"
						or "")
					.. [[
	Thank you for using RipSave.

	If you saved as .rbxlx, open in Studio and re-save as .rbxl (File > Save to File As).

	ServerStorage, ServerScriptService and Server Scripts CANNOT be saved due to FilteringEnabled.

	If your character cannot spawn, move or delete scripts in StarterPlayer, then run:
	  game:GetService("Players").CharacterAutoLoads = true
	Use "Play Here" to spawn at your camera position.

	If chat doesn't work, run:
	  game:GetService("Chat"):ClearAllChildren()
	  game:GetService("TextChatService"):ClearAllChildren()

	If Union/MeshPart collisions are broken, run in the Studio Command Bar:
	  local C = game:GetService("CoreGui")
	  local D = Enum.CollisionFidelity.Default
	  for _, v in game:GetDescendants() do
	    if v:IsA("TriangleMeshPart") and not v:IsDescendantOf(C) then
	      v.CollisionFidelity = D
	    end
	  end
	  print("Done")

	If camera is stuck, run:
	  workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed

	Settings used:
	]]
					.. service.HttpService:JSONEncode(OPTIONS)
					.. "\n\n\tElapsed: " .. os.clock() - elapse_t
					.. " | Date (UTC): " .. DateTime.now():FormatUniversalTime("LL LTS", "en-gb")
					.. " | PlaceId: " .. game.PlaceId
					.. " | Version: " .. FULL_VERSION
					.. " | Executor: " .. (identify_executor and table.concat({ identify_executor() }, " ") or "Unknown")
					.. "\n]]"
			)
		end

		do
			local sharedStrings = { "<SharedStrings>" }
			for value, identifier in SharedStrings do
				table.insert(sharedStrings, '<SharedString md5="' .. identifier .. '">' .. value .. "</SharedString>")
			end
			if #sharedStrings > 1 then
				savebuffer[savebuffer_size] = table.concat(sharedStrings)
				savebuffer_size += 1
				savebuffer[savebuffer_size] = "</SharedStrings>"
				savebuffer_size += 1
			end
		end

		savebuffer[savebuffer_size] = "</roblox><!-- Saved by RipSave https://discord.gg/wx4ThpAsmw -->"
		savebuffer_size += 1
		save_cache(true)

		do
			if OPTIONS.Anonymous then
				local lp = service.Players.LocalPlayer
				if lp then
					local function gsubCaseInsensitive(input, search, replacement)
						local inputLower = string.lower(input)
						search = string.lower(search)
						local lastFinish, substrings, searchLen = 0, {}, #search
						while searchLen <= #input - lastFinish do
							local start, finish = string.find(inputLower, search, lastFinish + 1, true)
							if not start then break end
							table.insert(substrings, string.sub(input, lastFinish + 1, start - 1))
							lastFinish = finish
						end
						if lastFinish == 0 then return input end
						table.insert(substrings, string.sub(input, lastFinish + 1))
						return table.concat(substrings, replacement)
					end

					local anon = type(OPTIONS.Anonymous) == "table" and OPTIONS.Anonymous
						or { UserId = "1", Name = "Roblox" }

					for _, chunk in chunks do
						chunk.str = gsubCaseInsensitive(
							string.gsub(chunk.str, lp.UserId, anon.UserId),
							lp.Name,
							anon.Name
						)
					end
				end
			end

			local callback = OPTIONS.Callback
			if callback then
				local totalstr = header
				for _, chunk in chunks do totalstr ..= chunk.str end
				callback(totalstr, chunks, totalsize)
			elseif OPTIONS.AlternativeWritefile and appendfile then
				local SEGMENT_SIZE = 4145728
				local totalLen = math.ceil(totalsize / SEGMENT_SIZE)
				local currentLen = 1

				for _, chunk in chunks do
					local segCount = math.ceil(chunk.size / SEGMENT_SIZE)
					for i = 1, segCount do
						local seg = string.sub(chunk.str, (i - 1) * SEGMENT_SIZE + 1, i * SEGMENT_SIZE)
						run_with_loading(
							"Writing to File " .. math.round(currentLen / totalLen * 100) .. "%",
							nil, true, appendfile, placename, seg
						)
						currentLen += 1
						if i ~= segCount then task.wait() end
					end
				end
			else
				local totalstr = header
				for _, chunk in chunks do totalstr ..= chunk.str end
				run_with_loading(
					"Writing " .. get_size_format() .. " to File",
					nil, true, writefile, placename, totalstr
				)
			end
		end
	end

	local Connections = {}
	local function Connect(event, fn)
		table.insert(Connections, event:Connect(fn))
	end

	local function Cleanup()
		for _, conn in Connections do conn:Disconnect() end
		GLOBAL_ENV[placename] = nil
	end

	do
		local Players = service.Players

		if IgnoreList.Model ~= true then
			local function ignoreCharacter(player)
				Connect(player.CharacterAdded, function(char)
					IgnoreList[char] = true
				end)
				if player.Character then
					IgnoreList[player.Character] = true
				end
			end

			if OPTIONS.RemovePlayerCharacters then
				Connect(Players.PlayerAdded, function(player) ignoreCharacter(player) end)
				for _, player in Players:GetPlayers() do ignoreCharacter(player) end
			else
				IgnoreNotArchivable = false
				if IsolateLocalPlayerCharacter then
					task.spawn(function() ignoreCharacter(GetLocalPlayer()) end)
				end
			end
		end

		if IsolateLocalPlayer and IgnoreList.Player ~= true then
			task.spawn(function() IgnoreList[GetLocalPlayer()] = true end)
		end
	end

	if OPTIONS.KillAllScripts and not GLOBAL_ENV.RIPSAVE_KAS then
		GLOBAL_ENV.RIPSAVE_KAS = true
		game:GetService("ScriptContext"):SetTimeout(math.clamp(SaveCacheInterval * 0.000047, 10, 30))

		local self = coroutine.running()
		do
			local islclosure = islclosure
			local isexecutorclosure = isexecutorclosure or checkclosure or isourclosure
			local hookfunction = hookfunction

			local function filterNkill(f)
				if not f then return end
				for _, v in table.clone(f()) do
					local vtype = type(v)
					if vtype == "thread" then
						if v ~= self then pcall(coroutine.close, v) end
					elseif vtype == "function" then
						if (not islclosure or islclosure(v)) and (not isexecutorclosure or not isexecutorclosure(v)) then
							if hookfunction then pcall(hookfunction, v, coroutine.yield) end
						end
					end
				end
			end

			filterNkill(debug and debug.getregistry or getreg or getregistry)
			filterNkill(getallthreads)
			filterNkill(getgc)
		end
	end

	if IsolateStarterPlayer then IgnoreList.StarterPlayer = false end
	if IsolatePlayers then IgnoreList.Players = false end

	if OPTIONS.ShowStatus then
		do
			local existing = GLOBAL_ENV._ripsave_statustext
			if existing then existing:Destroy() end
		end

		local statusGui = Instance.new("ScreenGui")
		GLOBAL_ENV._ripsave_statustext = statusGui
		statusGui.DisplayOrder = 2e9
		pcall(function() statusGui.OnTopOfCoreBlur = true end)

		StatusText = Instance.new("TextLabel")
		StatusText.Text = "RipSave: Starting..."
		StatusText.BackgroundTransparency = 1
		StatusText.Font = Enum.Font.Code
		StatusText.AnchorPoint = Vector2.new(1)
		StatusText.Position = UDim2.new(1)
		StatusText.Size = UDim2.new(0.3, 0, 0, 20)
		StatusText.TextColor3 = Color3.new(1, 1, 1)
		StatusText.TextScaled = true
		StatusText.TextStrokeTransparency = 0.7
		StatusText.TextXAlignment = Enum.TextXAlignment.Right
		StatusText.TextYAlignment = Enum.TextYAlignment.Top
		StatusText.Parent = statusGui

		local function randomName()
			local chars = {}
			for i = 1, math.random(10, 20) do
				chars[i] = string.char(math.random(32, 126))
			end
			return table.concat(chars)
		end

		if global_container.gethui then
			statusGui.Name = randomName()
			statusGui.Parent = global_container.gethui()
		elseif global_container.protectgui then
			statusGui.Name = randomName()
			global_container.protectgui(statusGui)
			statusGui.Parent = game:GetService("CoreGui")
		else
			local rbxGui = game:GetService("CoreGui"):FindFirstChild("RobloxGui")
			statusGui.Name = randomName()
			statusGui.Parent = rbxGui or game:GetService("CoreGui")
		end
	end

	do
		if SafeMode then
			task.spawn(function()
				local lp = GetLocalPlayer()
				local playerScripts = lp:FindFirstChildOfClass("PlayerScripts")
				if playerScripts then
					local function buildOverride(instance)
						local children = instance:GetChildren()
						InstancesOverrides[instance] = { __Children = children }
						for _, child in children do buildOverride(child) end
					end
					buildOverride(playerScripts)
					InstancesOverrides[lp] = {
						__Children = lp:GetChildren(),
						Properties = { Name = "[" .. lp.ClassName .. "] " .. lp.Name },
					}
				end

				local msg = "[RipSave SafeMode] Saving — do NOT leave. Disable SafeMode=false to suppress this kick."
				local function kick() lp:Kick(msg) end
				kick()
				pcall(function()
					Connect(service.GuiService.ErrorMessageChanged, function()
						if service.GuiService:GetErrorMessage() ~= msg then kick() end
					end)
				end)
				wait_for_render()
			end)
			pcall(function() service.RunService:Set3dRenderingEnabled(false) end)
		end

		if OPTIONS.AntiIdle then
			Connect(GetLocalPlayer().Idled, function()
				local pos = service.UserInputService:GetMouseLocation()
				service.VirtualInputManager:SendMouseWheelEvent(pos.X, pos.Y, true, game)
			end)
		end

		if not ClassList then
			do
				local UGCValidationService

				gethiddenproperty_fallback = function(instance, propName)
					if not UGCValidationService then
						UGCValidationService = service.UGCValidationService
					end
					return UGCValidationService:GetPropertyValue(instance, propName)
				end

				if gethiddenproperty then
					local ok, r = pcall(gethiddenproperty, workspace, "StreamOutBehavior")
					if not ok or r ~= nil and typeof(r) ~= "EnumItem" then
						gethiddenproperty = nil
					else
						ok, r = pcall(gethiddenproperty,
							Instance.new("AnimationRigData", Instance.new("Folder")), "parent")
						if ok and r ~= nil and type(r) ~= "string" then
							gethiddenproperty = nil
						end
					end
				end

				local function benchmark(funcs, ...)
					local ranking = {}
					for i, f in funcs do
						local start = os.clock()
						for _ = 1, 50 do f(...) end
						ranking[i] = { t = os.clock() - start, f = f }
					end
					table.sort(ranking, function(a, b) return a.t < b.t end)
					return ranking[1].f
				end

				local testStr = string.rep("\1\0\0\0\1\2\3\4\5\6\7", 50)

				do
					if not bit32.byteswap or not (function()
						local ok, r = pcall(bit32.byteswap, 2712847316)
						return ok and r == 3569595041
					end)() then
						local b32 = table.clone(bit32)
						b32.byteswap = function(n)
							return bit32.bor(
								bit32.lshift(n, 24),
								bit32.band(bit32.lshift(n, 8), 0xFF0000),
								bit32.band(bit32.rshift(n, 8), 0xFF00),
								bit32.rshift(n, 24)
							)
						end
						if table.isfrozen(bit32) then b32 = table.freeze(b32) end
						GLOBAL_ENV.bit32 = b32
					end

					local rbxcryptBase64
					pcall(function()
						local enc = loadstring(
							game:HttpGet(
								"https://raw.githubusercontent.com/daily3014/rbx-cryptography/refs/heads/main/src/Utilities/Base64.luau",
								true
							), "Base64"
						)().Encode
						rbxcryptBase64 = function(raw)
							return buffer.tostring(enc(buffer.fromstring(raw)))
						end
					end)

					local EncodingService = game:GetService("EncodingService")
					local encodingServiceBase64 = function(raw)
						return buffer.tostring(EncodingService:Base64Encode(buffer.fromstring(raw)))
					end

					if base64encode and base64encode("\1\0\0\0\1") == "AQAAAAE=" then
						if rbxcryptBase64 then
							base64encode = benchmark(
								{ base64encode, rbxcryptBase64, encodingServiceBase64 },
								testStr
							)
						end
					else
						base64encode = rbxcryptBase64
					end

					if not base64encode then
						warn("[RipSave] base64encode not found — aborting")
						Cleanup()
						return
					end
				end
			end

			do
				local ok, result = pcall(FetchAPI)
				if ok then
					ClassList = result
				else
					warn("[RipSave] Failed to load API dump:", result)
					Cleanup()
					return
				end
			end
		end

		elapse_t = os.clock()

		local ok, err = xpcall(save_game, function(e)
			return debug.traceback(e)
		end)

		if SafeMode then
			pcall(function()
				local max = 5
				task.delay(
					math.clamp(max - (os.clock() - elapse_t), 0, max),
					service.GuiService.ClearError,
					service.GuiService
				)
				service.RunService:Set3dRenderingEnabled(true)
			end)
		end

		if old_gethiddenproperty then
			gethiddenproperty = old_gethiddenproperty
		end

		Cleanup()

		elapse_t = os.clock() - elapse_t
		local log10 = math.log10(elapse_t)
		local extraTime = 10

		if StatusText then
			task.spawn(function()
				if ok then
					StatusText.Text = string.format("RipSave: Done! %.3fs | %s", elapse_t, get_size_format())
					StatusText.TextColor3 = Color3.fromRGB(80, 220, 120)
					task.wait(log10 * 2 + extraTime)
				else
					if Loading then task.cancel(Loading) Loading = nil end
					StatusText.Text = "RipSave: Failed — check F9 console"
					StatusText.TextColor3 = Color3.fromRGB(255, 80, 80)
					warn("[RipSave] Error during save:")
					warn(err)
					task.wait(log10 + extraTime)
				end
				StatusText:Destroy()
			end)
		end

		if OPTIONS.ShutdownWhenDone and ok then
			task.wait(log10 * 2 + extraTime)
			game:Shutdown()
		end
	end
end

return ripsave
