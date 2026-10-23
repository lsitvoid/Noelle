#!/usr/bin/env python3
"""
noelle — cross-platform terminal AI assistant
=============================================

A Windows-native reimplementation of the noelle (miyu) terminal experience.
No daemon, no Unix signals, no PTY tricks — just Python 3.9+ stdlib running
on Windows Terminal / PowerShell, and equally on Linux / macOS.

    noelle              first run -> setup wizard, then REPL
    noelle normal       REPL (setup wizard on first run)
    noelle chat         same as normal
    noelle ask "..."    one-shot question
    noelle config       interactive config editor
    noelle persona      view / set / clear persona
    noelle models       list configured providers
    noelle paths        show config & data locations
    noelle reset        wipe history (keeps config)

Data lives in:
    Windows : %APPDATA%\\noelle
    Linux   : ~/.config/noelle  +  ~/.local/share/noelle
    macOS   : ~/Library/Application Support/noelle
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    import readline  # noqa: F401  (line editing on Unix)
except ImportError:
    readline = None


# --------------------------------------------------------------------------
# 平台适配
# --------------------------------------------------------------------------
IS_WIN = os.name == "nt"

if IS_WIN:
    try:
        import ctypes
        _k = ctypes.windll.kernel32
        _k.SetConsoleMode(_k.GetStdHandle(-11), 7)  # 启用 VT 转义
        ENABLE_VT = True
    except Exception:
        ENABLE_VT = False
else:
    ENABLE_VT = True


class C:
    """ANSI 颜色，不可用时自动降级为空串"""

    def __init__(self, on: bool):
        def w(code: str) -> str:
            return code if on else ""

        self.reset = w("\033[0m")
        self.bold = w("\033[1m")
        self.dim = w("\033[2m")
        self.cyan = w("\033[36m")
        self.green = w("\033[32m")
        self.yellow = w("\033[33m")
        self.red = w("\033[31m")
        self.grey = w("\033[90m")


COLOR = C(ENABLE_VT and sys.stdout.isatty())


# --------------------------------------------------------------------------
# 路径
# --------------------------------------------------------------------------
APP = "noelle"


def _win_base() -> Path:
    return Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")


def config_dir() -> Path:
    if IS_WIN:
        return _win_base() / APP
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / APP


def data_dir() -> Path:
    if IS_WIN or sys.platform == "darwin":
        return config_dir()
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / APP


def config_file() -> Path:
    return config_dir() / "config.json"


def history_file() -> Path:
    return data_dir() / "history.jsonl"


def persona_file() -> Path:
    return config_dir() / "persona.md"


# --------------------------------------------------------------------------
# 配置
# --------------------------------------------------------------------------
DEFAULT_CONFIG = {
    "provider": "",
    "providers": {
        "zhipu": {
            "base_url": "https://open.bigmodel.cn/api/paas/v4",
            "model": "glm-4-flash",
            "api_key": "",
        },
        "deepseek": {
            "base_url": "https://api.deepseek.com/v1",
            "model": "deepseek-chat",
            "api_key": "",
        },
        "openai": {
            "base_url": "https://api.openai.com/v1",
            "model": "gpt-4o-mini",
            "api_key": "",
        },
        "ollama": {
            "base_url": "http://localhost:11434/v1",
            "model": "qwen2.5:7b",
            "api_key": "ollama",
        },
        "custom": {"base_url": "", "model": "", "api_key": ""},
    },
    "temperature": 0.7,
    "max_tokens": 2048,
    "system_prompt": "You are Noelle, a concise and capable terminal assistant.",
    "history_turns": 10,
    "stream": True,
}


def deep_merge(base: dict, over: dict) -> dict:
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config() -> dict:
    f = config_file()
    if not f.is_file():
        return json.loads(json.dumps(DEFAULT_CONFIG))
    try:
        user = json.loads(f.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"{COLOR.red}config 解析失败: {e}{COLOR.reset}", file=sys.stderr)
        return json.loads(json.dumps(DEFAULT_CONFIG))
    return deep_merge(DEFAULT_CONFIG, user)


def save_config(cfg: dict) -> None:
    config_dir().mkdir(parents=True, exist_ok=True)
    config_file().write_text(
        json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # Windows 上尽量收紧权限（含 API Key）
    if IS_WIN:
        try:
            os.chmod(config_file(), 0o600)
        except OSError:
            pass


def active_provider(cfg: dict):
    name = cfg.get("provider") or ""
    if not name:
        return None, None
    prov = cfg["providers"].get(name)
    if not prov or not prov.get("base_url"):
        return None, None
    return name, prov


# --------------------------------------------------------------------------
# LLM 调用（OpenAI 兼容协议，覆盖 zhipu / deepseek / openai / ollama / 自建）
# --------------------------------------------------------------------------
class LLMError(RuntimeError):
    pass


def _post_stream(url: str, headers: dict, payload: dict):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line or not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue
            choices = obj.get("choices") or []
            if not choices:
                continue
            delta = choices[0].get("delta") or {}
            piece = delta.get("content")
            if piece:
                yield piece


def _post_once(url: str, headers: dict, payload: dict) -> str:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        obj = json.loads(resp.read().decode("utf-8", "replace"))
    choices = obj.get("choices") or []
    if not choices:
        raise LLMError(f"响应无 choices: {obj}")
    return choices[0].get("message", {}).get("content", "")


def chat(cfg: dict, messages: list, stream: bool = True):
    """返回字符串（非流式）或生成器（流式）"""
    name, prov = active_provider(cfg)
    if not prov:
        raise LLMError("尚未配置可用的模型，请先运行: noelle config")

    url = prov["base_url"].rstrip("/") + "/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {prov.get('api_key', '')}",
    }
    payload = {
        "model": prov["model"],
        "messages": messages,
        "temperature": cfg.get("temperature", 0.7),
        "max_tokens": cfg.get("max_tokens", 2048),
        "stream": bool(stream),
    }

    try:
        if stream:
            return _post_stream(url, headers, payload)
        return _post_once(url, headers, payload)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:400]
        raise LLMError(f"HTTP {e.code} — {body}") from None
    except urllib.error.URLError as e:
        raise LLMError(f"网络不可达: {e.reason}") from None


# --------------------------------------------------------------------------
# 会话
# --------------------------------------------------------------------------
def build_messages(cfg: dict, history: list, user_text: str) -> list:
    msgs = [{"role": "system", "content": cfg.get("system_prompt", "")}]

    pf = persona_file()
    if pf.is_file():
        persona = pf.read_text(encoding="utf-8").strip()
        if persona:
            msgs.append({"role": "system", "content": persona})

    keep = int(cfg.get("history_turns", 10)) * 2
    msgs.extend(history[-keep:] if keep > 0 else [])
    msgs.append({"role": "user", "content": user_text})
    return msgs


def append_history(history: list, role: str, content: str) -> None:
    history.append({"role": role, "content": content})
    try:
        data_dir().mkdir(parents=True, exist_ok=True)
        with history_file().open("a", encoding="utf-8") as f:
            f.write(json.dumps(
                {"t": time.time(), "role": role, "content": content},
                ensure_ascii=False) + "\n")
    except OSError:
        pass


def run_turn(cfg: dict, history: list, text: str) -> str:
    msgs = build_messages(cfg, history, text)
    want_stream = bool(cfg.get("stream", True))

    if not want_stream:
        reply = chat(cfg, msgs, stream=False)
        print(reply)
        return reply

    buf = []
    printed = False
    gen = chat(cfg, msgs, stream=True)
    try:
        for piece in gen:
            if not printed:
                print()
                printed = True
            sys.stdout.write(piece)
            sys.stdout.flush()
            buf.append(piece)
    finally:
        if printed:
            print()
    return "".join(buf)


# --------------------------------------------------------------------------
# 界面
# --------------------------------------------------------------------------
def print_banner() -> None:
    f = Path(__file__).parent / "assets" / "banner.txt"
    if f.is_file():
        print(COLOR.cyan + COLOR.bold)
        print(f.read_text(encoding="utf-8").rstrip("\n"))
        print(COLOR.reset)


def setup_wizard(cfg: dict) -> None:
    print(COLOR.bold + "noelle 首次设置" + COLOR.reset)
    print("─" * 52)
    print("可用 provider:")
    names = [k for k, v in cfg["providers"].items() if k != "custom"]
    for i, n in enumerate(names, 1):
        p = cfg["providers"][n]
        print(f"  {i}) {n:10s} {p['base_url']}  ({p['model']})")
    print(f"  {len(names)+1}) custom     自行填写 base_url / model")
    print()

    pick = ask("选择 provider 编号", "1")
    try:
        idx = int(pick) - 1
    except ValueError:
        idx = 0

    if 0 <= idx < len(names):
        name = names[idx]
    else:
        name = "custom"
        cfg["providers"]["custom"]["base_url"] = ask("base_url", "")
        cfg["providers"]["custom"]["model"] = ask("model", "")

    if name != "ollama":
        key = ask("API Key", "")
        cfg["providers"][name]["api_key"] = key

    cfg["provider"] = name

    print()
    persona = ask("人格提示词（可留空，之后用 noelle persona 设置）", "")
    if persona.strip():
        persona_file().parent.mkdir(parents=True, exist_ok=True)
        persona_file().write_text(persona.strip() + "\n", encoding="utf-8")

    save_config(cfg)
    print()
    print(f"{COLOR.green}✓ 配置已保存: {config_file()}{COLOR.reset}")
    print(f"{COLOR.dim}  修改配置: noelle config{COLOR.reset}")
    print()


def ask(prompt: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    try:
        val = input(f"{COLOR.cyan}{prompt}{suffix} › {COLOR.reset}").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return default
    return val or default


def repl(cfg: dict) -> None:
    history: list = []
    name, prov = active_provider(cfg)
    label = f"{name}/{prov['model']}" if prov else "未配置模型"

    print_banner()
    print(f"{COLOR.dim}{label} · /exit 退出 · /reset 清空上下文 · /config 配置{COLOR.reset}")
    print()

    while True:
        try:
            line = input(f"{COLOR.green}你 › {COLOR.reset}").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not line:
            continue
        if line in ("/exit", "/quit", "exit", "quit"):
            break
        if line == "/reset":
            history.clear()
            print(f"{COLOR.dim}上下文已清空{COLOR.reset}\n")
            continue
        if line == "/config":
            print(f"{COLOR.dim}{config_file()}{COLOR.reset}\n")
            continue
        if line in ("/help", "/?"):
            print("/exit  /reset  /config  /help\n")
            continue

        try:
            reply = run_turn(cfg, history, line)
        except LLMError as e:
            print(f"{COLOR.red}[错误] {e}{COLOR.reset}\n", file=sys.stderr)
            continue

        append_history(history, "user", line)
        append_history(history, "assistant", reply)
        print()


def cmd_config(cfg: dict) -> None:
    name, prov = active_provider(cfg)
    print(COLOR.bold + "noelle 配置" + COLOR.reset)
    print("─" * 52)
    print(f"  当前 provider : {name or '未设置'}")
    if prov:
        print(f"  base_url      : {prov['base_url']}")
        print(f"  model         : {prov['model']}")
        k = prov.get("api_key", "")
        print(f"  api_key       : {'*' * 8 + k[-4:] if len(k) > 4 else '(空)'}")
    print(f"  temperature   : {cfg.get('temperature')}")
    print(f"  max_tokens    : {cfg.get('max_tokens')}")
    print(f"  stream        : {cfg.get('stream')}")
    print(f"  history_turns : {cfg.get('history_turns')}")
    print(f"  配置文件      : {config_file()}")
    print()
    print(f"{COLOR.dim}直接编辑上面的 JSON 文件即可，或用 noelle setup 重跑向导{COLOR.reset}")


def cmd_persona(cfg: dict, args: list) -> None:
    pf = persona_file()
    if not args:
        if pf.is_file():
            print(pf.read_text(encoding="utf-8"))
        else:
            print(f"{COLOR.dim}(未设置人格，用 noelle persona \"你是...\" 设置){COLOR.reset}")
        return
    text = " ".join(args)
    if text in ("clear", "reset", "-d"):
        if pf.is_file():
            pf.unlink()
        print(f"{COLOR.green}✓ 人格已清除{COLOR.reset}")
        return
    config_dir().mkdir(parents=True, exist_ok=True)
    pf.write_text(text + "\n", encoding="utf-8")
    print(f"{COLOR.green}✓ 人格已保存{COLOR.reset}")


def cmd_models(cfg: dict) -> None:
    cur = cfg.get("provider")
    for name, p in cfg["providers"].items():
        if not p.get("base_url"):
            continue
        mark = "→" if name == cur else " "
        has_key = "✓" if p.get("api_key") or name == "ollama" else "✗"
        print(f" {mark} {name:10s} {p['model']:24s} key:{has_key}  {p['base_url']}")


def cmd_paths() -> None:
    print(f"配置文件 : {config_file()}")
    print(f"数据目录 : {data_dir()}")
    print(f"历史记录 : {history_file()}")
    print(f"人格文件 : {persona_file()}")


def main() -> int:
    argv = sys.argv[1:]
    cfg = load_config()

    if not argv:
        if not cfg.get("provider"):
            setup_wizard(cfg)
            cfg = load_config()
        repl(cfg)
        return 0

    cmd, rest = argv[0], argv[1:]

    if cmd in ("normal", "chat"):
        if not cfg.get("provider"):
            setup_wizard(cfg)
            cfg = load_config()
        repl(cfg)
        return 0

    if cmd in ("setup", "oobe"):
        setup_wizard(cfg)
        return 0

    if cmd == "ask":
        text = " ".join(rest)
        if not text:
            text = sys.stdin.read().strip()
        if not text:
            print("用法: noelle ask \"问题\"", file=sys.stderr)
            return 2
        if not cfg.get("provider"):
            print(f"{COLOR.red}尚未配置模型，运行: noelle setup{COLOR.reset}", file=sys.stderr)
            return 2
        try:
            run_turn(cfg, [], text)
        except LLMError as e:
            print(f"{COLOR.red}[错误] {e}{COLOR.reset}", file=sys.stderr)
            return 1
        return 0

    if cmd == "config":
        cmd_config(cfg)
        return 0

    if cmd == "persona":
        cmd_persona(cfg, rest)
        return 0

    if cmd == "models":
        cmd_models(cfg)
        return 0

    if cmd == "paths":
        cmd_paths()
        return 0

    if cmd == "reset":
        h = history_file()
        if h.is_file():
            h.unlink()
            print(f"{COLOR.green}✓ 历史已清空{COLOR.reset}")
        else:
            print("(无历史记录)")
        return 0

    if cmd in ("-h", "--help", "help"):
        print(__doc__)
        return 0

    if cmd in ("-v", "--version", "version"):
        print("noelle-win 0.1.0 (python)")
        return 0

    # 未知子命令 → 当作提问
    if not cfg.get("provider"):
        print(f"{COLOR.red}尚未配置模型，运行: noelle setup{COLOR.reset}", file=sys.stderr)
        return 2
    try:
        run_turn(cfg, [], " ".join(argv))
    except LLMError as e:
        print(f"{COLOR.red}[错误] {e}{COLOR.reset}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        sys.exit(130)
