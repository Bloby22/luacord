<div align="center" style="border: 2px solid #7289DA; border-radius: 15px; padding: 25px; max-width: 800px; background-color: #f9f9f9;">

<h1 style="color:#7289DA;">🟣 Luacord</h1>

<p>
<img src="https://img.shields.io/badge/status-active-brightgreen?style=flat-square" />
<img src="https://img.shields.io/badge/language-lua-blue?style=flat-square" />
<img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" />
<img src="https://img.shields.io/badge/discord-bot_ready-purple?style=flat-square" />
</p>

<h2>💡 About</h2>
<p>**Luacord** is a modern Discord API written in Lua, focused on clean code, ease of use, and performance. Build and manage Discord bots effortlessly using Lua scripts.</p>

<h2>✨ Features</h2>
<ul>
<li>✅ Clean and modern API</li>
<li>✅ Full support for Discord events</li>
<li>✅ Easy setup and extensibility</li>
<li>✅ Optimized for speed and stability</li>
<li>✅ Cross-platform compatibility</li>
</ul>

<h2>🛠️ Installation</h2>
<pre><code>local Luacord = require("luacord")

local client = Luacord.Client({
    token = "YOUR_BOT_TOKEN"
})

client:on("ready", function()
    print("✅ Luacord is ready!")
end)

client:run()
</code></pre>

<h2>⚡ Quick Start</h2>
<pre><code>lua bot.lua
</code></pre>

<h2>📚 Example</h2>
<pre><code>client:on("messageCreate", function(message)
    if message.content == "!ping" then
        message.channel:send("Pong!")
    end
end)
</code></pre>

<h2>👑 Owner / Profile</h2>
<img src="https://github.com/bloby22.png" width="100" style="border-radius:50%;" /><br>
<b>Bloby22</b><br><br>

<p>
<a href="https://discord.com/users/12849595943" target="_blank">
<img src="https://img.shields.io/badge/Discord-12849595943-7289DA?style=flat-square&logo=discord&logoColor=white" />
</a>
<a href="mailto:michal@bloby.eu" target="_blank">
<img src="https://img.shields.io/badge/Email-michal@bloby.eu-orange?style=flat-square&logo=gmail&logoColor=white" />
</a>
<a href="https://github.com/bloby22" target="_blank">
<img src="https://img.shields.io/badge/GitHub-Bloby22-black?style=flat-square&logo=github&logoColor=white" />
</a>
<a href="https://bloby.eu" target="_blank">
<img src="https://img.shields.io/badge/Website-Bloby.eu-blue?style=flat-square&logo=internet&logoColor=white" />
</a>
</p>

</div>