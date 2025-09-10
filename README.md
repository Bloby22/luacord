<p align="center">
  <b style="font-size: 2.5em; color:#7289DA;">🟣 Luacord</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active-brightgreen?style=flat-square" />
  <img src="https://img.shields.io/badge/language-lua-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" />
  <img src="https://img.shields.io/badge/discord-bot_ready-purple?style=flat-square" />
</p>

---

## 💡 About

**Luacord** is a **modern Discord API** written in **Lua**, focused on **clean code**, **ease of use**, and **performance**.  
Build and manage Discord bots effortlessly using Lua scripts.

---

## ✨ Features

- ✅ Clean and modern API  
- ✅ Full support for Discord events  
- ✅ Easy setup and extensibility  
- ✅ Optimized for speed and stability  
- ✅ Cross-platform compatibility  

---

## 🖼️ Icons & Visualization

| Icon | Description |
|------|-------------|
| 🤖 | Bot instance |
| 🏰 | Server management |
| 💬 | Message handling |
| 👤 | User management |
| ⚡ | Event handling |

---

## 🛠️ Installation

```lua
local Luacord = require("luacord")

local client = Luacord.Client({
    token = "YOUR_BOT_TOKEN"
})

client:on("ready", function()
    print("✅ Luacord is ready!")
end)

client:run()