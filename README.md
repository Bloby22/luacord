# ![Luacord Logo](https://img.icons8.com/color/48/discord-new.png) Luacord

![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat-square)
![Lua](https://img.shields.io/badge/language-lua-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)

## 🚀 About

**Luacord** is a modern **Discord API** written in **Lua**, designed for **clean code**, **modern design**, and **ease of use**.  
It allows you to control and integrate Discord bots effortlessly using Lua scripts.

---

## ✨ Features

- Clean and modern API
- Full support for Discord events
- Easy setup and extensibility
- Optimized for speed and stability
- Cross-platform compatibility

---

## 🖼️ Icons & Visualization

| Icon | Description |
|------|-------------|
| ![Bot](https://img.icons8.com/ios-filled/50/000000/bot.png) | Bot instance |
| ![Server](https://img.icons8.com/ios-filled/50/000000/server.png) | Discord server management |
| ![Message](https://img.icons8.com/ios-filled/50/000000/chat.png) | Message handling |
| ![User](https://img.icons8.com/ios-filled/50/000000/user.png) | User management |

---

## 🛠️ Installation

```lua
-- Example installation of Luacord
local Luacord = require("luacord")

local client = Luacord.Client({
    token = "YOUR_BOT_TOKEN"
})

client:on("ready", function()
    print("Luacord is ready!")
end)

client:run()