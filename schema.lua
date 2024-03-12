local fmt = string.format
local next = next
local type = type
local error = error
local pairs = pairs
local assert = assert
local ipairs = ipairs
local get_mt = getmetatable
local set_mt = setmetatable


local schema = {}


--- 值的表示形式
---@param v any
---@return string
local function repr(v)
	local typ = type(v)
	if typ == 'string' then
		return fmt('%q', v)
	elseif typ == 'table' then
		local s = tostring(v)
		if not s:match('^table') then
			s = 'table: '..s
		end
		return s
	end
	return tostring(v)
end


local function indent_new_ln(str)
	return str:gsub('(\r?\n)', '%1  ')
end


local function map(array, func)
	local t = {}
	for i, v in ipairs(array) do
		t[i] = func(v)
	end
	return t
end


local schema_mts = set_mt({}, {__mode = 'k'})  ---@type {[metatable]: true}

---@param name string
---@param super_mt metatable?
---@param without_override boolean?
---@return metatable
local function reg_mt(name, super_mt, without_override)
	local index = super_mt and super_mt.__index or {}
	if not without_override then
		index = set_mt({}, {__index = index})
	end

	local mt = {
		__name = name,
		__index = index,
	}
	schema_mts[mt] = true
	return mt
end

---@param v any
---@return string | nil
local function get_scm_type(v)
	local mt =  get_mt(v)
	if not schema_mts[mt] then return nil end
	return mt.__name
end


local function is_callable(v)
	if type(v) == 'function' then return true end
	local mt = get_mt(v)
	local call = mt and rawget(mt, '__call')
	if not call then return false end
	return is_callable(call)
end


---@param constraints table
---@return table?
local function get_validators_from_constraints(constraints)
	local inputs = constraints.validator
	if not inputs then return nil end
	if type(inputs) ~= 'table' or get_mt(inputs) then
		inputs = {inputs}
	end
	local validators = {}
	for i, v in ipairs(inputs) do
		if not is_callable(v) then
			error(fmt("%s isn't callable", repr(v)), 3)
		end
		validators[i] = v
	end
	return validators
end


local SUPER = '__s__'
local VALIDATORS = '__v__'
local always_true = function() return true end

local Any_mt = reg_mt('Any', nil)
schema.Any = set_mt({
	test = always_true,
}, Any_mt)

function Any_mt:__call(constraints)
	return set_mt({
		[SUPER] = self,
		[VALIDATORS] = get_validators_from_constraints(constraints),
	}, get_mt(self))
end

Any_mt.__index._test = always_true

function Any_mt.__index:test(testee)
	if self[SUPER] then
		local valid, msg = self[SUPER]:test(testee)
		if not valid then
			return false, msg
		end
	end

	local valid, msg = self:_test(testee)
	if not valid then
		return false, msg
	end

	if not self[VALIDATORS] then return true end
	for _, validator in ipairs(self[VALIDATORS]) do
		local valid, msg = validator(testee)
		if not valid then
			return false, msg and 'custom validation failed: '..msg or 'custom validation failed'
		end
	end
	return true
end

function Any_mt.__index:assert(testee)
	if self[SUPER] then
		self[SUPER]:assert(testee)
	end

	assert(self:_test(testee))

	if not self[VALIDATORS] then return true end
	for _, validator in ipairs(self[VALIDATORS]) do
		assert(validator(testee))
	end
	return true
end


---@param typ string 类型
---@param a string? 冠词
---@return function
local function TypeChecker(typ, a)
	local fmt_str = "%s (type: %s) isn't "..(a and a..' ' or '')..typ
	return function(_self, testee)
		if type(testee) == typ then
			return true
		end
		return false, fmt(fmt_str, repr(testee), type(testee))
	end
end


local Nil_mt = reg_mt('Nil', Any_mt, true)
schema.Nil = set_mt({
	_test = TypeChecker('nil'),
}, Nil_mt)


local Boolean_mt = reg_mt('Boolean', Any_mt, true)
schema.Boolean = set_mt({
	_test = TypeChecker('boolean', 'a'),
}, Boolean_mt)


local Number_mt = reg_mt('Number', Any_mt)
schema.Number = set_mt({
	_test = TypeChecker('number', 'a'),
}, Number_mt)

---@type {[string]: fun(testee: number, n: number): boolean, string?}
local num_cmps = {
	lt = function(testee, n)
		if testee < n then return true end
		return false, fmt("%s isn't < %s", testee, n)
	end,
	gt = function(testee, n)
		if testee > n then return true end
		return false, fmt("%s isn't > %s", testee, n)
	end,
	le = function(testee, n)
		if testee <= n then return true end
		return false, fmt("%s isn't <= %s", testee, n)
	end,
	ge = function(testee, n)
		if testee >= n then return true end
		return false, fmt("%s isn't >= %s", testee, n)
	end,
	ne = function(testee, n)
		if testee ~= n then return true end
		return false, fmt('testee equals %s', n)
	end,
}

function Number_mt:__call(constraints)
	return set_mt({
		[SUPER] = self,
		cmp = {
			lt = constraints.lt,
			gt = constraints.gt,
			le = constraints.le or constraints.max,
			ge = constraints.ge or constraints.min,
			ne = constraints.ne,
		},
		[VALIDATORS] = get_validators_from_constraints(constraints),
	}, Number_mt)
end

function Number_mt.__index:_test(testee)
	for method_name, n in pairs(self.cmp) do
		local valid, msg = num_cmps[method_name](testee, n)
		if not valid then
			return false, msg
		end
	end
	return true
end


local String_mt = reg_mt('String', Any_mt)
schema.String = set_mt({
	_test = TypeChecker('string', 'a')
}, String_mt)

function String_mt:__call(constraints)
	return set_mt({
		[SUPER] = self,
		max_len = constraints.max_len,
		min_len = constraints.min_len,
		pattern = constraints.pattern,
		[VALIDATORS] = get_validators_from_constraints(constraints),
	}, String_mt)
end

function String_mt.__index:_test(testee)
	if self.max_len and #testee > self.max_len then
		return false, fmt("the length of %q (%d) exceeds %s", testee, #testee, self.max_len)
	end
	if self.min_len and #testee < self.min_len then
		return false, fmt("the length of %q (%d) is under %s", testee, #testee, self.min_len)
	end
	if self.pattern and not testee:match(self.pattern) then
		return false, fmt("%q doesn't match the pattern %q", testee, self.pattern)
	end
	return true
end


local Function_mt = reg_mt('Function', Any_mt)
schema.Function = set_mt({
	_test = TypeChecker('function', 'a'),
}, Function_mt)

Function_mt.__call = Any_mt.__call


local Table_mt = reg_mt('Table', Any_mt)
schema.Table = set_mt({
	_test = TypeChecker('table', 'a')
}, Table_mt)

function Table_mt:__call(constraints)
	local specific = {}
	local generic = {}
	for k, v in pairs(constraints) do
		if not get_scm_type(v) then
			v = schema.Const(v)
		end
		local scm_type = get_scm_type(k)
		if scm_type then
			if scm_type == 'Const' then
				specific[k[1]] = v
			else
				generic[k] = v
			end
		elseif k ~= 'validator' then
			specific[k] = v
		end
	end
	return set_mt({
		[SUPER] = self,
		specific = specific,
		generic = generic,
		[VALIDATORS] = get_validators_from_constraints(constraints)
	}, Table_mt)
end

function Table_mt.__index:_test(testee)
	for key_scm, val_scm in pairs(self.generic) do
		for testee_key, testee_val in pairs(testee) do
			if key_scm:test(testee_key) then
				local valid, msg = val_scm:test(testee_val)
				if not valid then
					return false, fmt(
						'in %s, field %s:\n- %s',
						repr(testee), repr(testee_key), indent_new_ln(msg or 'no message provided')
					)
				end
			end
		end
	end
	for key, val_scm in pairs(self.specific) do
		local valid, msg = val_scm:test(testee[key])
		if not valid then
			return false, fmt(
				'in %s, field %s:\n- %s',
				repr(testee), repr(key), indent_new_ln(msg or 'no message provided')
			)
		end
	end
	return true
end


local Const_mt = reg_mt('Const', Any_mt)
local existing_const_scms = set_mt({}, {__mode = 'kv'})

--- 获得一个Const实例，以相同参数多次调用将会返回同一对象
function schema.Const(val)
	if val == nil then
		return schema.Nil
	elseif existing_const_scms[val] then
		return existing_const_scms[val]
	end
	local obj = set_mt({val}, Const_mt)
	existing_const_scms[val] = obj
	return obj
end

function Const_mt.__index:_test(testee)
	if self[1] == testee then return true end
	return false, fmt("%s doesn't equals %s", repr(testee), repr(self[1]))
end


local Union_mt = reg_mt('Union', Any_mt)

function schema.Union(...)
	local union = {}
	for i = 1, select('#', ...) do
		local sub_scm = select(i, ...)
		if sub_scm == nil then
			union[schema.Nil] = true
		elseif get_scm_type(sub_scm) == 'Union' then
			for scm_in_union in next, sub_scm do
				union[scm_in_union] = true
			end
		elseif get_scm_type(sub_scm) then
			union[sub_scm] = true
		else
			union[schema.Const(sub_scm)] = true
		end
	end
	return set_mt(union, Union_mt)
end

function Union_mt.__index:_test(testee)
	local msgs = {}
	for allowed_scm in next, self do
		local valid, msg = allowed_scm:test(testee)
		if valid then return true end
		msgs[#msgs+1] = msg or 'no message provided'
	end
	return false, fmt(
		'%s fails to match any value in the union:\n- %s',
		repr(testee),
		table.concat(map(msgs, indent_new_ln), '\n- ')
	)
end

-- 必须放在所有reg_mt()之后
for mt in next, schema_mts do
	mt.__bor = schema.Union
	mt.__div = schema.Union
end
reg_mt = nil  -- 防止后续意外调用


schema.Integer = schema.Number{validator=function(v)
	if math.fmod(v, 1) == 0 then return true end
	return false, fmt("%s isn't an integer", v)
end}

schema.Callable = schema.Any{validator=function(v)
	if is_callable(v) then return true end
	return false, fmt("%s isn't callable", repr(v))
end}

schema.Truthy = schema.Any{validator=function(v)
	if v then return true end
	return false, fmt("%s isn't truthy", v)
end}

schema.Falsy = schema.Any{validator=function(v)
	if not v then return true end
	return false, fmt("%s isn't falsy", repr(v))
end}


return schema
