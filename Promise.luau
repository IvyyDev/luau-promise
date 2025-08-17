--!strict

local Promise = {}
Promise.__index = Promise

export type State = "pending" | "fulfilled" | "rejected"

export type Config = {
	profiling: boolean?,      	   -- default false
	profilePrefix: string?,   	   -- default "promise/"
	schedule: ((() -> ()) -> ())?, -- default task.defer
}

local DEFAULTS: Config = {
	profiling = false,
	profilePrefix = "promise/",
	schedule = function(fn) task.defer(fn) end,
}

local cfg: Config = table.clone(DEFAULTS)

local function profileBegin(name: string)
	if cfg.profiling and debug and typeof(debug.profilebegin) == "function" then
		debug.profilebegin((cfg.profilePrefix :: string) .. name)
	end
end
local function profileEnd()
	if cfg.profiling and debug and typeof(debug.profileend) == "function" then
		debug.profileend()
	end
end

local function schedule(fn: () -> ())
	(cfg.schedule :: any)(fn)
end

local function isPromiseLike(x: any): boolean
	return typeof(x) == "table" and (getmetatable(x) == Promise)
end

local function adopt(result: any, resolve: (any) -> (), reject: (any) -> ())
	if isPromiseLike(result) then
		(result :: any):andThen(resolve, reject)
	else
		resolve(result)
	end
end

type QueueItem = {
	onFulfilled: ((any) -> any)?,
	onRejected: ((any) -> any)?,
	resolve: (any) -> (),
	reject: (any) -> (),
}
type Queue = { QueueItem }

function Promise.new(executor: (resolve: (any) -> (), reject: (any) -> ()) -> ()): any
	local self = setmetatable({
		_state = "pending" :: State,
		_value = nil :: any,
		_reason = nil :: any,
		_queue = {} :: Queue,
	}, Promise)

	local settled = false

	local function drain()
		if #self._queue == 0 then return end
		local queue = self._queue
		self._queue = {}
		for _, q in queue do
			if self._state == "fulfilled" then
				schedule(function()
					profileBegin("then/fulfilled")
					if q.onFulfilled == nil then
						q.resolve(self._value)
						profileEnd()
						return
					end
					local ok, res = pcall(q.onFulfilled, self._value)
					if ok then adopt(res, q.resolve, q.reject) else q.reject(res) end
					profileEnd()
				end)
			else
				schedule(function()
					profileBegin("then/rejected")
					if q.onRejected == nil then
						q.reject(self._reason)
						profileEnd()
						return
					end
					local ok, res = pcall(q.onRejected, self._reason)
					if ok then adopt(res, q.resolve, q.reject) else q.reject(res) end
					profileEnd()
				end)
			end
		end
	end

	local function resolve(value: any)
		if settled or self._state ~= "pending" then return end
		if value == self then
			reject("cannot resolve promise with itself")
			return
		end
		if isPromiseLike(value) then
			settled = true
			(value :: any):andThen(function(v)
				settled = false
				resolve(v)
			end, function(e)
				settled = false
				reject(e)
			end)
			return
		end
		self._state = "fulfilled"
		self._value = value
		drain()
	end

	function reject(reason: any)
		if settled or self._state ~= "pending" then return end
		self._state = "rejected"
		self._reason = reason
		drain()
	end

	profileBegin("executor")
	local ok, err = pcall(function()
		executor(resolve, reject)
	end)
	profileEnd()
	if not ok then
		reject(err)
	end

	return self
end

function Promise:andThen(onFulfilled: ((any) -> any)?, onRejected: ((any) -> any)?)
	return Promise.new(function(resolve, reject)
		if self._state == "pending" then
			table.insert(self._queue, {
				onFulfilled = onFulfilled,
				onRejected = onRejected,
				resolve = resolve,
				reject = reject,
			})
			return
		end
		schedule(function()
			if self._state == "fulfilled" then
				profileBegin("inline/fulfilled")
				if onFulfilled == nil then
					resolve(self._value)
					profileEnd()
					return
				end
				local ok, res = pcall(onFulfilled, self._value)
				if ok then adopt(res, resolve, reject) else reject(res) end
				profileEnd()
			else
				profileBegin("inline/rejected")
				if onRejected == nil then
					reject(self._reason)
					profileEnd()
					return
				end
				local ok, res = pcall(onRejected, self._reason)
				if ok then adopt(res, resolve, reject) else reject(res) end
				profileEnd()
			end
		end)
	end)
end

function Promise:catch(onRejected: (any) -> any)
	return self:andThen(nil, onRejected)
end

function Promise:finally(onFinally: () -> ())
	return self:andThen(function(v)
		local ok, err = pcall(onFinally)
		if not ok then error(err, 0) end
		return v
	end, function(e)
		local ok, err = pcall(onFinally)
		if not ok then error(err, 0) end
		error(e, 0)
	end)
end

function Promise:await(): (boolean, any)
	if self._state == "fulfilled" then
		return true, self._value
	elseif self._state == "rejected" then
		return false, self._reason
	end
	local thread = coroutine.running()
	if thread == nil then
		error("await must be called inside a running coroutine", 0)
	end
	self:andThen(function(v)
		task.defer(coroutine.resume, thread, true, v)
	end, function(e)
		task.defer(coroutine.resume, thread, false, e)
	end)
	return coroutine.yield()
end

-- statics

function Promise.resolve(value: any)
	return Promise.new(function(res) res(value) end)
end

function Promise.reject(reason: any)
	return Promise.new(function(_, rej) rej(reason) end)
end

function Promise.all(list: { any })
	return Promise.new(function(resolve, reject)
		local n = #list
		if n == 0 then
			resolve({})
			return
		end
		local results: { any } = table.create(n)
		local remaining = n
		for i = 1, n do
			Promise.resolve(list[i]):andThen(function(v)
				results[i] = v
				remaining -= 1
				if remaining == 0 then resolve(results) end
			end, reject)
		end
	end)
end

function Promise.race(list: { any })
	return Promise.new(function(resolve, reject)
		for i = 1, #list do
			Promise.resolve(list[i]):andThen(resolve, reject)
		end
	end)
end

function Promise.any(list: { any })
	return Promise.new(function(resolve, reject)
		local n = #list
		if n == 0 then
			reject("Promise.any([])")
			return
		end
		local rejections: { any } = table.create(n)
		local remaining = n
		for i = 1, n do
			Promise.resolve(list[i]):andThen(resolve, function(err)
				rejections[i] = err
				remaining -= 1
				if remaining == 0 then reject(rejections) end
			end)
		end
	end)
end

function Promise.delay(seconds: number, value: any?)
	return Promise.new(function(resolve)
		task.delay(seconds, function()
			resolve(value)
		end)
	end)
end

function Promise.configure(options: Config)
	for k, v in options do
		(cfg :: any)[k] = v
	end
end

return Promise
