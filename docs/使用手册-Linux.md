# noelle 使用手册

> 适用版本：noelle 0.7.0（封装上游 miyu 0.7.0）
> 最后更新：2026-10-23

---

## 一、快速开始

### 安装

```bash
git clone https://github.com/listvoid/noelle.git ~/noelle
cd ~/noelle && ./install.sh
```

安装脚本自动完成：检查/安装上游 `miyu`（AUR）→ 复制二进制 → 初始化 `~/noelle/.noelle` → 部署启动器 → 装 fish 集成。

### 首次运行

```bash
noelle normal
```

首次进入会自动走**新手引导**，依次设置：人格 → 功能 → 认识你 → 终端集成 → 接模型。

引导完成后 `oobe_done` 变为 `true`，之后再运行 `noelle normal` 就直接进入对话。

---

## 二、命令总览

| 命令 | 说明 |
|---|---|
| `noelle normal` | **普通模式**。首次自动引导，之后进对话 REPL |
| `noelle dev` | **开发模式**。无人格的极简编码形态，适合写代码 |
| `noelle oobe` | 重跑新手引导（改人格、换模型、重新认识你） |
| `noelle ask "问题"` | 单次提问，回答完就退出，不进 REPL |
| `noelle paths` | 显示所有配置、数据、缓存路径 |
| `noelle config` | 打开 TUI 配置界面 |
| `noelle daemon status` | 查看后台服务状态 |
| `noelle daemon restart` | 重启后台服务（改完配置后用） |
| `noelle reload` | 热重载配置，不重启 daemon |
| `noelle session list` | 列出所有会话 |
| `noelle wipe` | 清空所有会话历史与记忆 ⚠️ |

其余上游子命令（`kb`、`memory`、`skills`、`voice`、`web`、`export`、`import` 等）**全部原样透传**：

```bash
noelle kb --help
noelle memory --help
noelle web            # 打开本地 WebUI
```

---

## 三、三种使用方式

### 3.1 普通模式（REPL）

```bash
noelle normal
```

进入后是一个可持续对话的界面，支持：

| 输入 | 作用 |
|---|---|
| 直接打字 | 对话 |
| `/exit` | 退出 |
| `/help` | 查看命令 |
| `/reset` | 清空当前上下文 |
| `/models` | 切换模型 |
| `/config` | 打开配置 |

### 3.2 开发模式

```bash
noelle dev
```

**无人格**的极简编码形态，不带任何角色设定与废话，专注代码。适合：

- 让助手改代码、写脚本
- 排查编译错误
- 批量重构

### 3.3 单次提问

```bash
noelle ask "解释一下 Btrfs 快照"
noelle ask "把这段 bash 改成 fish" 
```

回答完直接退出，不占会话上下文，适合脚本调用。

---

## 四、终端无缝集成

安装脚本会自动装好 fish 集成：`~/.config/fish/conf.d/noelle.fish`

**效果**：在 fish 里直接输入自然语言，回车即交给 AI：

```bash
~ ❯ 帮我看看磁盘占用
……（AI 分析并回答）

~ ❯ ls -la          # 普通命令照常执行
~ ❯ sudo pacman -Syu # 普通命令照常执行
```

判定规则（`--shell-classify`，耗时 < 60ms）：

| 输入 | 判定 | 依据 |
|---|---|---|
| `ls -la` | 命令 | 首词是已知命令 |
| `sudo pacman -Syu` | 命令 | 首词是已知命令 |
| `ls \| grep foo` | 命令 | 含 shell 运算符 |
| `/usr/bin/python3 x.py` | 命令 | 以路径开头 |
| `帮我看看磁盘` | 自然语言 | 含 CJK 字符 |
| `what is KISS` | 自然语言 | 未匹配命令模式 |

---

## 五、人格管理

### 5.1 首次设定

`noelle normal` 首次运行会强制进入引导，让你自己写人格，**不预设任何默认人格**。

### 5.2 手动设置

人格提示词放在：

```
~/noelle/.noelle/data/prompts/<名字>.md
```

然后在 `~/.noelle/config/config.jsonc` 中指向它：

```jsonc
"prompt": {
    "active_persona": "你的名字.md"
}
```

改完执行：

```bash
noelle reload
```

### 5.3 切换人格

```bash
noelle oobe          # 走引导重新选
```

或直接改配置后 `noelle reload`。

### 5.4 完全清空人格

```bash
sed -i 's/"active_persona": "[^"]*"/"active_persona": ""/' \
  ~/noelle/.noelle/config/config.jsonc
noelle daemon restart
```

---

## 六、接入模型

配置在 `~/noelle/.noelle/config/config.jsonc` 的 `llm` 段，或直接走引导：

```bash
noelle oobe
```

常用 provider：

| provider | endpoint | 备注 |
|---|---|---|
| `zhipu` | open.bigmodel.cn | GLM 系列，国内直连 |
| `deepseek` | api.deepseek.com | 国内直连 |
| `nyarch` | llm.nyarchlinux.moe | 上游提供，有限额 |
| `mistral` | api.mistral.ai | 部分地区不可达 |
| `openrouter` | openrouter.ai | 聚合多家 |

切完模型测试：

```bash
noelle ask "只回两个字：在线"
```

---

## 七、与 Miyu 共存

两者**完全隔离**，可同时运行：

| 项目 | miyu | noelle |
|---|---|---|
| 数据目录 | `~/.miyu` | `~/noelle/.noelle` |
| daemon | 独立 PID | 独立 PID |
| runtime | `/run/user/1000/miyu` | `/run/user/1000/miyu-<hash>` |
| shell hook | `miyu.fish` | `noelle.fish` |

两个 hook 都注册回车拦截，按文件名排序加载，**后加载者优先**（`miyu.fish` < `noelle.fish`，所以 noelle 生效）。

临时禁用其中一个：

```bash
mv ~/.config/fish/conf.d/miyu.fish{,.disabled}
```

---

## 八、目录结构

```
~/noelle/
├── install.sh              # 安装
├── uninstall.sh            # 卸载
├── README.md
├── noelle.fish             # fish 集成（源文件）
├── bin/
│   ├── noelle              # 启动器（normal/dev 分发）
│   └── noelle.real         # 上游二进制（gitignore）
├── docs/
│   └── 使用手册.md          # 本文
└── .noelle/                # 独立数据（gitignore）
    ├── config/config.jsonc # 主配置
    ├── data/prompts/       # 人格提示词
    ├── personas/           # 人格记忆库
    ├── home/               # 会话、图片、文档
    ├── state/              # 运行状态
    └── cache/              # 缓存与日志
```

---

## 九、常见问题

### Q0：为什么 logo 还是 MIYU？

因为 **MIYU 字形是编译进上游二进制的常量**，无法通过配置文件修改：

| 位置 | 内容 |
|---|---|
| `0x611020` | MIYU 的 ANSI Shadow 字形（483 字节 / 32 宽 × 6 行） |
| `0x611203` | MIYU 的纯 ASCII 回退字形 |

环境变量 `MIYU_ASCII` 只能在这两套**内置字形**间切换，改不了文字。`MIYU_COLOR` 控制配色。

noelle 的处理方式是**关掉内置 banner，由启动器自绘 NOELLE 字形**：

1. `config.jsonc` 里 `"banner": false`（`install.sh` 自动设置）
2. `assets/banner.txt` 存放 NOELLE 的 ANSI Shadow 字形
3. `bin/noelle` 在 `normal` 模式启动时打印它（仅 TTY）

想换字形：直接改 `assets/banner.txt`，宽高随意，启动器原样打印。

### Q0b：终端标题为什么是 NOEL 而不是 NOELLE？

标题在代码段里由指令直接写入，字符串字面量编进了**立即数**：

```asm
c7 00 4d 69 79 75                     mov dword [rax], 0x7579694D   ; "Miyu"
48 c7 84 24 e0 01 00 00 04 00 00 00   mov qword [rsp+0x1e0], 4
48 c7 84 24 f0 01 00 00 04 00 00 00   mov qword [rsp+0x1f0], 4
```

长度 `4` 硬编码，缓冲区只有 4 字节，**只能换成 4 个 ASCII 字符**。变长需重写指令并重定位，风险大。

因此标题用 `NOEL`，banner 用完整的 `NOELLE` 字形。

补丁由 `tools/patch-title.py` 完成，`install.sh` 会自动调用：

```bash
python3 tools/patch-title.py bin/noelle.real NOEL    # 打补丁
python3 tools/patch-title.py bin/noelle.real --revert # 还原成 Miyu
```

换别的 4 字母名（如 `NELL`）也行，改第二个参数即可。

### Q1：`noelle normal` 没进引导，直接对话了

`oobe_done` 已是 `true`。想重跑：

```bash
noelle oobe
```

或强制重置标记：

```bash
sed -i 's/"oobe_done": true/"oobe_done": false/' \
  ~/noelle/.noelle/config/config.jsonc
```

### Q2：改了人格但回复没变

daemon 有缓存，必须重启：

```bash
noelle daemon restart
```

### Q3：`daemon stop` 把自己的 miyu 也停了

**不要直接用 `~/noelle/bin/noelle.real`**，它不注入 `MIYU_HOME`，会操作默认的 `~/.miyu`。

始终用：

```bash
noelle daemon stop              # 走 PATH（推荐）
~/noelle/bin/noelle daemon stop # 或显式路径
```

### Q4：终端里输入中文没反应

检查 hook 是否加载：

```bash
fish -c "type -q noelle; and echo '✓ 已加载'"
```

没加载就重新 souce：

```bash
source ~/.config/fish/conf.d/noelle.fish
```

### Q5：上游更新了怎么办

```bash
cd ~/noelle && ./install.sh
```

脚本幂等，会重新复制二进制，**保留现有配置与数据**。

### Q6：想彻底重来

```bash
mv ~/noelle/.noelle ~/noelle/.noelle.old
./install.sh
```

### Q7：能不能提交到 Git？

`.gitignore` 已排除 `.noelle/`（含 API Key）与二进制。提交前核对：

```bash
git status
```

不应该看到 `.noelle/`。

---

## 十、卸载

```bash
cd ~/noelle && ./uninstall.sh
```

会停止 daemon、移除 fish hook、删除数据目录与二进制。**不触碰** `~/.miyu` 与上游 `miyu` 包。

彻底删除：

```bash
rm -rf ~/noelle
```
