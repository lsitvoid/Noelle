# noelle-win 使用手册

> 适用版本：noelle-win 0.1.0 (Python 3.9+)
> 平台：Windows 10/11 · Linux · macOS

---

## 一、安装

### Windows

```powershell
winget install Python.Python.3.12
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

装到 `%LOCALAPPDATA%\noelle`，自动加入用户 PATH。

**验证**：

```powershell
noelle --version
# noelle-win 0.1.0 (python)
```

若提示找不到命令，重开终端，或临时：

```powershell
$env:Path += ";$env:LOCALAPPDATA\noelle"
```

### Linux / macOS

```bash
chmod +x noelle.py
./noelle.py --version
```

---

## 二、首次设置

```bash
noelle
```

向导流程：

```
noelle 首次设置
────────────────────────────────────────────────────
可用 provider:
  1) zhipu      https://open.bigmodel.cn/api/paas/v4  (glm-4-flash)
  2) deepseek   https://api.deepseek.com/v1           (deepseek-chat)
  3) openai     https://api.openai.com/v1             (gpt-4o-mini)
  4) ollama     http://localhost:11434/v1             (qwen2.5:7b)
  5) custom     自行填写 base_url / model

选择 provider 编号 ›
API Key ›
人格提示词（可留空） ›
```

完成后配置写入 `<config_dir>/config.json`。

---

## 三、日常使用

### 3.1 对话模式

```bash
noelle normal
```

```
███╗   ██╗ ██████╗ ███████╗██╗     ██╗     ███████╗
...

zhipu/glm-4-flash · /exit 退出 · /reset 清空上下文 · /config 配置

你 › 解释一下 Python 的 GIL
```

REPL 命令：

| 输入 | 作用 |
|---|---|
| `/exit` `/quit` | 退出 |
| `/reset` | 清空上下文（保留历史文件） |
| `/config` | 显示配置文件位置 |
| `/help` | 帮助 |

### 3.2 单次提问

```bash
noelle ask "把这段 bash 改成 powershell: ls -la"
noelle ask "一句话解释什么是 WSL2"
```

也支持管道：

```bash
cat error.log | noelle ask "这个报错什么意思"
```

### 3.3 直接提问

不带子命令的词会被当作问题：

```bash
noelle 什么是 KISS 原则
```

---

## 四、配置

### 4.1 查看

```bash
noelle config
```

```
noelle 配置
────────────────────────────────────────────────────
  当前 provider : zhipu
  base_url      : https://open.bigmodel.cn/api/paas/v4
  model         : glm-4-flash
  api_key       : ********7UpW
  temperature   : 0.7
  max_tokens    : 2048
  stream        : True
  history_turns : 10
  配置文件      : C:\Users\you\AppData\Roaming\noelle\config.json
```

### 4.2 手动编辑

直接改 JSON：

```json
{
  "provider": "deepseek",
  "temperature": 0.3,
  "max_tokens": 4096,
  "stream": true,
  "history_turns": 20
}
```

| 字段 | 说明 |
|---|---|
| `provider` | 当前使用的 provider 名 |
| `temperature` | 0–2，越低越确定 |
| `max_tokens` | 单次回复上限 |
| `stream` | `true` 逐字输出，`false` 一次性输出 |
| `history_turns` | 保留最近几轮对话作为上下文 |
| `system_prompt` | 基础系统提示词 |

### 4.3 切换模型

改 `provider` 字段即可，或重跑向导：

```bash
noelle setup
```

---

## 五、人格

人格是独立文件 `<config_dir>/persona.md`，会作为**额外的 system 消息**注入。

### 设置

```bash
noelle persona "你是 Noelle，一位严谨的 Arch Linux 架构师。回复简短，直接给命令。"
```

### 查看

```bash
noelle persona
```

### 清除

```bash
noelle persona clear
```

### 优先级

```
system_prompt (config.json)
    ↓
persona.md
    ↓
历史对话
    ↓
当前用户消息
```

---

## 六、接入自定义服务

任何 **OpenAI 兼容**的 `/chat/completions` 端点都能用。

### 例：OpenRouter

```json
{
  "provider": "custom",
  "providers": {
    "custom": {
      "base_url": "https://openrouter.ai/api/v1",
      "model": "anthropic/claude-3.5-sonnet",
      "api_key": "sk-or-v1-..."
    }
  }
}
```

### 例：本地 Ollama

```bash
ollama serve
ollama pull qwen2.5:7b
noelle setup   # 选 4) ollama
```

无需 API Key，`api_key` 填任意值即可。

### 例：LM Studio / vLLM / 任何自建

```json
{
  "provider": "custom",
  "providers": {
    "custom": {
      "base_url": "http://192.168.1.10:1234/v1",
      "model": "local-model",
      "api_key": "not-needed"
    }
  }
}
```

---

## 七、文件位置

| 平台 | 配置 | 数据 |
|---|---|---|
| Windows | `%APPDATA%\noelle` | 同左 |
| Linux | `~/.config/noelle` | `~/.local/share/noelle` |
| macOS | `~/Library/Application Support/noelle` | 同左 |

```bash
noelle paths
```

```
配置文件 : C:\Users\you\AppData\Roaming\noelle\config.json
数据目录 : C:\Users\you\AppData\Roaming\noelle
历史记录 : C:\Users\you\AppData\Roaming\noelle\history.jsonl
人格文件 : C:\Users\you\AppData\Roaming\noelle\persona.md
```

---

## 八、Windows 集成技巧

### 8.1 加别名

PowerShell 启动脚本里加：

```powershell
Set-Alias n noelle
```

写进 `$PROFILE`：

```powershell
Add-Content $PROFILE "`nSet-Alias n noelle"
```

### 8.2 Windows Terminal 配置片段

```json
{
    "name": "noelle",
    "commandline": "noelle normal",
    "startingDirectory": "%USERPROFILE%",
    "colorScheme": "One Half Dark"
}
```

### 8.3 右键菜单（发送文件给 AI）

```powershell
noelle ask "解释这个脚本"
```

配合管道：

```powershell
Get-Content .\script.ps1 -Raw | noelle ask "审查这段代码"
```

---

## 九、常见问题

### Q1：`noelle` 不是内部或外部命令

PATH 未生效。重开终端，或临时：

```powershell
$env:Path += ";$env:LOCALAPPDATA\noelle"
```

### Q2：中文乱码

Windows 控制台编码问题：

```powershell
chcp 65001
```

或在 Windows Terminal 设置里把 profile 编码设为 UTF-8。

### Q3：颜色不显示 / 全是转义字符

旧版 `cmd.exe` 不支持 ANSI。用 **Windows Terminal** 或 PowerShell 7+。

### Q4：HTTP 401

API Key 错误或过期。检查 `noelle config` 里的 key 尾部是否正确。

### Q5：HTTP 429 / 余额不足

账户额度用尽。换 provider 或充值。

### Q6：网络超时

企业网络/代理环境：

```powershell
$env:HTTPS_PROXY = "http://proxy:8080"
noelle ask "test"
```

### Q7：如何完全重置

```powershell
Remove-Item "$env:APPDATA\noelle\config.json"
noelle   # 重新走向导
```

只清历史：

```bash
noelle reset
```

---

## 十、卸载

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\noelle"
Remove-Item -Recurse -Force "$env:APPDATA\noelle"
```

再从「系统属性 → 环境变量 → 用户变量 Path」删掉对应条目。

---

## 附：与 noelle（Linux）对比

| 特性 | noelle (Linux) | noelle-win |
|---|---|---|
| 底层 | 封装 Miyu 二进制 | 纯 Python |
| 平台 | 仅 Linux | 全平台 |
| 依赖 | AUR 包 | 仅 Python 标准库 |
| daemon | 有 | 无 |
| 记忆/知识库 | 有 | 无 |
| Shell 回车劫持 | 有 | 无 |
| 体积 | ~80 MB | < 30 KB |
| 人格 | prompts/*.md + oobe | persona.md |
