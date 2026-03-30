--!optimize 2

local GlobalEnv = getgenv and getgenv() or _G or shared

local GlobalContainer = GlobalEnv.GlobalContainer
if not GlobalContainer then
	GlobalContainer = {}
	GlobalEnv.GlobalContainer = GlobalContainer
end

local Environments = {}

if getgenv then
	table.insert(Environments, getgenv())
end

table.insert(Environments, shared)
table.insert(Environments, _G)

local function IsEmpty(Table)
	for _ in pairs(Table) do
		return false
	end
	return true
end

local Visited
local SearchQuery
local MaxDepth
local CurrentDepth
local PrintResults
local AllMatched

local function ScanEnvironment(Environment)
	if Visited[Environment] or Environment == GlobalContainer then
		return
	end

	Visited[Environment] = true
	CurrentDepth += 1

	for Key, Value in pairs(Environment) do
		if AllMatched then break end

		local ValueType = type(Value)

		if ValueType == "table" then
			if CurrentDepth < MaxDepth then
				ScanEnvironment(Value)
			end
		elseif ValueType == "function" then
			local FunctionName = string.lower(tostring(Key))
			local MatchedKeys = {}

			for TargetName, Pattern in pairs(SearchQuery) do
				if string.find(FunctionName, Pattern, 1, true) then
					GlobalContainer[TargetName] = Value
					table.insert(MatchedKeys, TargetName)

					if PrintResults then
						print(TargetName, FunctionName)
					end
				end
			end

			for _, Name in ipairs(MatchedKeys) do
				SearchQuery[Name] = nil
			end

			AllMatched = IsEmpty(SearchQuery)
		end
	end

	CurrentDepth -= 1
end

local function Finder(QueryTable, ForceSearch, DepthLimit, ShouldPrint)
	Visited = {}
	SearchQuery = {}

	for Name, Pattern in pairs(QueryTable) do
		if not GlobalContainer[Name] or ForceSearch then
			SearchQuery[Name] = string.lower(Pattern)
		end
	end

	CurrentDepth = 0
	MaxDepth = DepthLimit or 5
	PrintResults = ShouldPrint
	AllMatched = false

	for _, Environment in ipairs(Environments) do
		ScanEnvironment(Environment)
	end

	local FallbackEnv = getfenv()
	for Name in pairs(QueryTable) do
		if not GlobalContainer[Name] then
			GlobalContainer[Name] = FallbackEnv[Name]
		end
	end

	Visited = nil
	SearchQuery = nil
end

return Finder, GlobalContainer
