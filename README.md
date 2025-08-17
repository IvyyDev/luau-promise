# 🌿 ivy's luau promises 🌿

<p align="center">
  <em>async flow • neat api • profiling friendly</em>
</p>

<p align="center">
  <a href="https://github.com/IvyyDev/luau-promise/stargazers">
    <img alt="stars" src="https://img.shields.io/github/stars/IvyyDev/luau-promise?color=6ade9f&style=flat-square">
  </a>
  <a href="https://github.com/IvyyDev/luau-promise/actions">
    <img alt="ci" src="https://img.shields.io/badge/ci-green?style=flat-square">
  </a>
  <a href="https://github.com/IvyyDev">
    <img alt="author" src="https://img.shields.io/badge/made%20by-ivy-9b6adb?style=flat-square">
  </a>
  <a href="https://discord.gg/YZ9wBpvdnx">
    <img alt="discord" src="https://img.shields.io/badge/chat-discord-6a82de?style=flat-square">
  </a>
</p>

---

## 🌸 what is this?
tiny promise implementation for **luau**.  
chained callbacks, async/await, profiling hooks.  
simple but powerful.

---

## 🍃 quick taste
```lua
Promise.new(function(resolve)
  task.delay(1, function()
    resolve("done!")
  end)
end):andThen(function(v)
  print(v) --> "done!"
end)
```

---

## 🌼 api
```lua
-- instance
Promise.new(executor)
Promise:andThen(onFulfilled?, onRejected?)
Promise:catch(onRejected)
Promise:finally(onFinally)
Promise:await() -> (boolean, any)

-- statics
Promise.resolve(value)
Promise.reject(reason)
Promise.all(list)
Promise.race(list)
Promise.any(list)
Promise.delay(seconds, value?)
Promise.configure(options)
```

---

## 🌷 profiling
opt‑in lightweight profiling with `debug.profilebegin/profileend`.

```lua
Promise.configure({
  profiling = true,
  profilePrefix = "ivy/promise/",
})
```

---

## 🌻 notes
- await must be inside a coroutine  
- then/catch/finally schedule async with `task.defer` by default  
- adopt & unwrap other promises automatically  

---

## 🪻 license
[MIT](./LICENSE) — use it, break it, ship it, whatever.  
just don’t forget to 🌸 credit 🌸
