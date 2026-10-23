# Noelle

> 我为我自己写的一个适应于我的人工智能。

本仓库包含 **两个独立的 Noelle 实现**，按平台选择：

| 版本 | 平台 | 技术栈 | 入口 |
|---|---|---|---|
| **Linux 版** | Arch / Debian / Fedora | 封装上游 Miyu 二进制 | `./install.sh` |
| **Windows 版** | Windows 10/11 · 也可跑 Linux/macOS | 纯 Python 标准库 | `install.ps1` 或 `noelle.cmd` |

两者**完全独立**，配置目录分离，可以共存。

---

## 快速开始

### Windows

```powershell
winget install Python.Python.3.12
powershell -ExecutionPolicy Bypass -File .\install.ps1
noelle
```

不想安装，双击 `noelle.cmd` 也能直接用。

### Linux (Arch)

```bash
./install.sh
noelle normal
```

安装脚本会自动从 AUR 装上游 `miyu`、复制二进制、初始化独立数据目录、部署 fish 集成。

---

## 功能对照

| 特性 | Linux 版 | Windows 版 |
|---|---|---|
| 终端对话 REPL | ✓ | ✓ |
| 流式输出 | ✓ | ✓ |
| 单次提问 | ✓ | ✓ |
| 人格提示词 | ✓ | ✓ |
| 多 provider | ✓ | ✓ |
| Shell 回车劫持 | ✓ | ✗ |
| 后台 daemon | ✓ | ✗（不需要） |
| 记忆 / 知识库 / 语音 / WebUI | ✓ | ✗ |
| 依赖 | AUR 包（~80 MB） | 仅 Python 标准库（<30 KB） |
| 支持平台 | 仅 Linux | Windows / Linux / macOS |

**选哪个**：

- 只想在终端问答 → **Windows 版**（更轻，零依赖，跨平台）
- 需要记忆、知识库、语音、WebUI、shell 集成 → **Linux 版**

---

## 命令速查

两个版本命令基本一致：

| 命令 | 作用 |
|---|---|
| `noelle` | 首次运行 → 配置向导；之后进对话 |
| `noelle normal` | 普通对话模式 |
| `noelle ask "问题"` | 单次提问（支持管道） |
| `noelle setup` | 重跑配置向导 |
| `noelle config` | 查看当前配置 |
| `noelle persona "你是..."` | 设置人格 |
| `noelle persona clear` | 清除人格 |
| `noelle models` | 列出 provider |
| `noelle paths` | 显示配置路径 |
| `noelle reset` | 清空历史 |

**Linux 版额外**：`noelle dev`（无人格极简编码模式）、`noelle oobe`、`noelle web`、`noelle kb`、`noelle memory`、`noelle session list`、`noelle daemon status`。

详见 [`docs/使用手册-Linux.md`](docs/使用手册-Linux.md) 与 [`docs/使用手册-Windows.md`](docs/使用手册-Windows.md)。

---

## 支持的模型

统一走 **OpenAI 兼容**协议，任何兼容端点都能接：

| provider | endpoint | 默认模型 |
|---|---|---|
| zhipu | open.bigmodel.cn/api/paas/v4 | glm-4-flash |
| deepseek | api.deepseek.com/v1 | deepseek-chat |
| openai | api.openai.com/v1 | gpt-4o-mini |
| ollama | localhost:11434/v1 | qwen2.5:7b |
| custom | 自行填写 | 自行填写 |

---

## 目录结构

```
Noelle/
├── install.sh              # Linux 安装
├── uninstall.sh
├── bin/noelle              # Linux 启动器
├── tools/patch-title.py    # 终端标题补丁
├── noelle.fish             # fish 集成
│
├── noelle.py               # Windows 版核心（纯 Python）
├── noelle.cmd              # Windows 启动器
├── install.ps1             # Windows 安装
│
├── assets/banner.txt       # NOELLE 字形
├── docs/
│   ├── 使用手册-Linux.md
│   └── 使用手册-Windows.md
└── legacy/                 # 早期实验（Jarvis 语音部署脚本、角色卡）
```

---

## 设计说明

### Linux 版

不改上游源码，用 `MIYU_HOME` 环境变量做实例隔离：

- 数据目录 `~/noelle/.noelle`，与 `~/.miyu` 完全分离
- daemon 各自独立，可同时运行
- 人格默认清空，首次运行强制走引导
- 内置 banner 是编译期常量，关掉后由启动器自绘 `assets/banner.txt`
- 终端标题是 4 字节立即数，补丁脚本改成 `NOEL`（`--revert` 可还原）

### Windows 版

上游没有 Windows 构建（依赖 Unix 信号、PTY、systemd），因此用 Python 重写：

- 零第三方依赖，仅 `urllib` 做 HTTP
- 流式输出逐行解析 SSE `data:` 帧
- Windows 下用 `ctypes` 开启控制台 VT 转义以支持 ANSI 颜色
- 无 daemon：每次调用直接请求 API

---

## 历史

`legacy/` 目录保留了早期实验：基于 `interpreter` + `faster-whisper` + Ollama 的 Windows 语音助手部署脚本，以及诺艾伊角色卡。仅供存档参考。

---

## 致谢

- [SHORiN-KiWATA/miyu-agent](https://github.com/SHORiN-KiWATA/miyu-agent) —— 设计灵感来源
