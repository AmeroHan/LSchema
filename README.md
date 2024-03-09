This Lua module validates values' data structures (or schema), easy to use.  
此Lua模块用于验证值的数据结构，用法简单。

Its simpleness makes documentation unnecessary. Read the code, _onegai_!  
懒得写文档了，看示例代码就行。

Designed as a MediaWiki Scibunto module initially, it has no validator of userdata or thread.  
由于最初是作为MediaWiki Scibunto模块设计的，所以没有userdata和thread和数据类型的校验器。

## Basic / 基础

```lua
local schema = require('schema')  -- 随便起个名，还可以是scm，再比如s

local valid, msg = schema.Number:test(1)
--> true, nil
local valid, msg = schema.Number:test('啊啊啊啊啊啊啊啊啊啊可爱的字符串')
--> false, '报错信息，我忘了是啥了，等它出来了自己看'
schema.Number:assert(1)  --> true
schema.Number:assert('OwO')  --> 抛出错误
-- 后面讲的几个类型都有test、assert这两个方法。
```

## Any

```lua
schema.Any  -- 任何值都能通过测试，是很随性的孩子

-- 约束选项有validator或validators：
schema.Any{validator=func}
schema.Any{validators={func1, func2, ...}}

-- validator的函数为(any) -> truthy | falsy，比如判断是否为非字符串：
local function is_string(v)
	return type(v) == 'string'
end
local function is_not_empty_string(v)
	return v ~= ''
end
local NonEmptyString = schema.Any{validators={is_string, is_not_empty_string}}
NonEmptyString:test('只有非空字符串能通过')  --> true
-- 仅作示例，实际使用String更便捷。

-- 可以在已有schema的基础上继续增加约束，这对于Number、String等其他支持约束的类型也适用。
-- 还是拿NonEmptyString举例
local String = schema.Any{validator=is_string}
local NonEmptyString = String{validator=is_not_empty_string}
```

## Nil、Boolean

```lua
schema.Nil  -- nil类型的值可以通过
schema.Boolean  -- boolean类型的值可以通过
-- 这两个无约束选项，因为Nil只能是nil，Boolean只能是true或false。
-- 如果需要“只能是true”或“只能是false”，请看Const。
```

## Number

```lua
schema.Number:test(0721)  --> true

-- 约束选项：
-- gt（大于）、lt（小于）、ge/min（大于等于）、le/max（小于等于）、ne（不等于），
-- 以及validator/validators（自定义约束）
-- 例如：
schema.Number{gt=0, le=100}:test(22/7)  --> true
```

## String

```lua
schema.String:test('Ciallo ~')  --> true

-- 约束选项：
-- min_len（最短长度）、max_len（最长长度）、pattern（正则），
-- 以及validator/validators（自定义约束）。
-- 例如，Any中的例子可以改为：
local NonEmptyString = schema.String{min_len=1}
-- 例二：
local HttpUrl = schema.String{pattern='^https?://'}
```

## Function

```lua
schema.Function:test(function() return 42 end)
-- 约束选项只有validator或validators
```

## Table

```lua
schema.Table  -- table类型的值可以通过

-- 示例
local CharacterInfo = schema.Table{
	name = schema.String{min_len=1},
	age = schema.Number{min=0},
}
local info1 = {
	name = '缠流子',
	age = '17',
}
local info2 = {
	name = '满舰饰真子',
	age = 16,
}
CharacterInfo:test(info1)  --> false, '好像会说什么age应该是数字而不是字符串'
CharacterInfo:test(info2)  --> true


-- 'validator'和'validators'两个字段被自定义校验器占用了，
-- 若你的结构中包含这两个字段，请使用schema.Const('validator')或schema.Const('validators')代替。
-- 作用对比如下：
local function check_children_num(t)
	return #t > 5
end
local array_with_6_children = {1, 2, 3, 4, 5, 6}
local table_with_validator_field = {
	validator = check_children_num
}

-- 这是为表格添加自定义校验：
schema.Table{
	validator = check_children_num
}:test(array_with_6_children)  --> true

-- 而这是设定表格validator字段的类型：
schema.Table{
	[schema.Const('validator')] = schema.Function,
}:test(table_with_validator_field)  --> true


-- 可以使用来schema作为键来匹配多个字段：
local hanzi_number_conversion = {
	'一', '二', '三',
	['一'] = 1, ['二'] = 2, ['三'] = 3,
}
schema.Table{
	[schema.String] = schema.Number,
	[schema.Number] = schema.String,
}:test(hanzi_number_conversion)  --> true
-- 这个例子中，只有数字键对应的值为字符串、字符串键对应的值为数字的表才能通过测试。
```

## Const

```lua
schema.Const(val)
-- Const是一个函数，本身不可以用作校验，它接收一个参数并返回一个schema，
-- 只有等于这个参数的值才能通过校验。
schema.Const('?'):test('!')  --> false, '好像是说这个不等于那个'
schema.Const('?'):test('?')  --> true

-- 当你传入相同的对象时，返回的schema也是同一个对象
local t = {}
local A, B = schema.Const(t), schema.Const(t)
rawequal(A, B)  --> true
```

## Union

```lua
schema.Union(scm1, scm2, ...)
-- 这个并集，被测值符合参数的其中一种就行。
-- 与Const一样，Union本身不可以用作校验，调用后返回的对象才可。
local QAQ = schema.Union('来测', '求你了，来测吧', schema.Boolean)
QAQ:test('来测')  --> true
QAQ:test('求你了，来测吧')  --> true
QAQ:test(false)  --> true
QAQ:test(6)  --> false, '说是union里的类型都不符合'

-- 有更方便的写法：
local WhatName = schema.String / schema.Number / nil
-- 等同于schema.Union(schema.String, schema.Number, nil)。
```

## 其他

```lua
schema.Integer  -- 用法同schema.Number，只不过这个只有整数能通过测试
schema.Callable  -- 可以调用的值，包含function和设置了__call元方法的表
schema.Truthy  -- 所有不是nil或false的值
schema.Falsy  -- nil或false
```
