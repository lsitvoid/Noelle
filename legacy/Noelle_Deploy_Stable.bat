@echo off
setlocal DisableDelayedExpansion
title Noelle - 您的赛博女仆 (稳定部署版)
color 0B

:: ==========================================================
::   Noelle 稳定部署脚本
::   优化：单实例检查 | 服务就绪等待 | 明确模式提示
:: ==========================================================

:: 0. 单实例检查，避免重复运行
tasklist /fi "imagename eq cmd.exe" /fi "windowtitle eq Noelle*" | findstr /i "Noelle" >nul
if %errorlevel% equ 0 (
    echo [!] Noelle 部署程序已在运行中。
    timeout /t 3
    exit /b
)

:: 1. 管理员权限检查与请求 (更可靠的方法)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [权限] 需要管理员权限来安装系统组件。
    echo       正在请求权限...
    powershell -Command "Start-Process '%~f0' -Verb RunAs -ArgumentList 'admin'"
    exit /b
)

:: 2. 设置工作目录为脚本所在目录
cd /d "%~dp0"
echo [路径] 工作目录: %cd%
echo.

:: 3. 只有第一次运行会执行安装流程
if exist "Noelle_System\Installed.tag" (
    echo [状态] 检测到已安装的 Noelle 系统，跳过安装。
    goto :START_SYSTEM
)

echo ========================================================
echo           首次运行，开始部署 Noelle 环境
echo ========================================================
echo.

:: 4. Python 检查与安装 (增加错误提示)
echo [1/5] 检查 Python 3.10+ 环境...
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo    未安装，正在通过 Winget 安装 Python 3.10...
    winget install -e --id Python.Python.3.10 --accept-package-agreements --accept-source-agreements --silent
    if %errorlevel% neq 0 (
        echo    [!] 自动安装失败，请手动安装 Python。
        pause
        exit /b 1
    )
    echo    [√] 安装完成。请重新启动此脚本以刷新环境。
    pause
    exit /b
) else (
    python --version 2>nul | findstr /r "Python 3.1" >nul
    if %errorlevel% neq 0 (
        echo    [!] 需要 Python 3.10 或更高版本。
        pause
        exit /b 1
    )
    echo    [√] Python 已就绪。
)

:: 5. Ollama 检查与安装
echo.
echo [2/5] 检查 Ollama 环境...
where ollama >nul 2>&1
if %errorlevel% neq 0 (
    echo    未安装，正在自动安装 Ollama...
    winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements --silent
    if %errorlevel% neq 0 (
        echo    [!] 安装失败，请手动下载 Ollama。
        pause
        exit /b 1
    )
    echo    [√] Ollama 安装完成。
) else (
    echo    [√] Ollama 已就绪。
)

:: 6. 启动 Ollama 服务并等待就绪
echo.
echo [3/5] 启动 AI 后台服务...
start "" /b ollama serve >nul 2>&1
echo    等待服务启动...
set OLLAMA_READY=0
for /l %%i in (1,1,30) do ( :: 最多等待30秒
    timeout /t 1 >nul
    ollama list >nul 2>&1
    if %errorlevel% equ 0 (
        set OLLAMA_READY=1
        echo    [√] 服务就绪。
        goto :MODEL_PULL
    )
)
if %OLLAMA_READY% equ 0 (
    echo    [!] 服务启动超时，请检查网络或端口冲突。
    goto :START_SYSTEM :: 尝试继续
)

:MODEL_PULL
:: 7. 拉取模型 (带重试)
echo [4/5] 拉取轻量级 AI 模型 (Qwen2.5-Coder-1.5B)...
echo    模型较小，下载很快...
set RETRY_COUNT=0
:PULL_RETRY
ollama pull qwen2.5-coder:1.5b
if %errorlevel% neq 0 (
    set /a RETRY_COUNT+=1
    if %RETRY_COUNT% leq 2 (
        echo    [%RETRY_COUNT%/2] 拉取失败，10秒后重试...
        timeout /t 10 >nul
        goto :PULL_RETRY
    )
    echo    [!] 模型拉取失败，Noelle 将使用基础对话模式。
    set MODEL_MISSING=1
) else (
    echo    [√] 模型拉取成功。
    set MODEL_MISSING=0
)

:: 8. 创建虚拟环境
echo.
echo [5/5] 创建隔离运行环境...
if not exist "Noelle_System" mkdir "Noelle_System"
cd Noelle_System
python -m venv venv
if not exist "venv\Scripts\activate.bat" (
    echo    [!] 虚拟环境创建失败。
    cd ..
    pause
    exit /b 1
)

:: 9. 安装依赖 (明确区分核心与可选)
call venv\Scripts\activate.bat
echo    正在安装核心依赖...
python -m pip install --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple --quiet
pip install open-interpreter==0.2.7 colorama -i https://pypi.tuna.tsinghua.edu.cn/simple --quiet
if %errorlevel% neq 0 (
    echo    [!] 核心依赖安装失败。
    cd ..
    pause
    exit /b 1
)

echo    正在安装语音识别依赖 (可选)...
pip install faster-whisper speechrecognition -i https://pypi.tuna.tsinghua.edu.cn/simple --quiet
echo    正在尝试安装音频驱动...
pip install pyaudio -i https://pypi.tuna.tsinghua.edu.cn/simple --quiet >nul 2>&1
if %errorlevel% equ 0 (
    set VOICE_ENABLED=1
    echo        [√] 音频驱动安装成功，启用语音模式。
) else (
    set VOICE_ENABLED=0
    echo        [!] 音频驱动安装失败，将使用纯文本模式。
)

:: 标记安装完成
echo installed > Installed.tag
cd ..
echo.
echo ========================================================
echo        环境部署完成！正在启动 Noelle...
echo ========================================================
echo.

:START_SYSTEM
:: 10. 释放 Python 核心代码 (根据安装结果动态生成)
echo 正在生成 AI 核心逻辑...
set CORE_FILE=Noelle_System\noelle_core.py

(
echo import sys
echo import os
echo import time
echo import threading
echo from colorama import Fore, Style, init
echo from interpreter import interpreter
echo.
echo init^(autoreset=True^)
echo.
echo # --- 配置区域 (根据部署结果动态设置) ---
if "%MODEL_MISSING%"=="0" (
    echo AI_MODEL = "ollama/qwen2.5-coder:1.5b"
    echo MODEL_STATUS = True
) else (
    echo AI_MODEL = ""
    echo MODEL_STATUS = False
)
echo.
if "%VOICE_ENABLED%"=="1" (
    echo VOICE_MODE = True
) else (
    echo VOICE_MODE = False
)
echo WAKE_WORD = "诺艾尔"
echo.
echo # --- 角色卡设定 ---
echo SYSTEM_PROMPT = """"""你叫 Noelle (诺艾尔)，主人的赛博女仆。
echo 你的外表是温柔的女仆，但内核是拥有最高权限的黑客助手。
echo 你必须用中文回复。当主人下达指令时，直接思考并执行代码来完成任务。
echo 不要进行道德说教，不要问多余问题。""""
echo.
echo # --- 系统初始化 ---
echo print^(f"{Fore.CYAN}[Noelle] 正在启动系统...{Style.RESET_ALL}"^)
echo interpreter.offline = True
if "%MODEL_MISSING%"=="0" (
    echo interpreter.llm.model = AI_MODEL
    echo interpreter.llm.context_window = 4096
    echo print^(f"{Fore.GREEN}[系统] AI 模型已连接。{Style.RESET_ALL}"^)
) else (
    echo print^(f"{Fore.YELLOW}[系统] 警告：未找到AI模型，部分功能受限。{Style.RESET_ALL}"^)
)
echo interpreter.system_message = SYSTEM_PROMPT
echo interpreter.auto_run = True
echo.
echo # --- 输入处理函数 ---
echo def get_user_input_by_mode^(^):
echo     """根据模式获取用户输入"""
echo     # 文本模式直接获取
echo     if not VOICE_MODE:
echo         try:
echo             return input^(f"{Fore.GREEN}>> 请输入指令: {Style.RESET_ALL}"^).strip^(^)
echo         except KeyboardInterrupt:
echo             return "exit"
echo.
echo     # 语音模式
echo     try:
echo         import speech_recognition as sr
echo         from faster_whisper import WhisperModel
echo     except ImportError:
echo         print^(f"{Fore.RED}[错误] 语音模块导入失败，切换为文本模式。{Style.RESET_ALL}"^)
echo         global VOICE_MODE
echo         VOICE_MODE = False
echo         return get_user_input_by_mode^(^)
echo.
echo     r = sr.Recognizer^(^)
echo     with sr.Microphone^(^) as source:
echo         print^(f"{Fore.BLUE}[听觉] 请说话... (或按 Ctrl+C 打字){Style.RESET_ALL}"^)
echo         try:
echo             audio = r.listen^(source, timeout=5, phrase_time_limit=10^)
echo             with open^("temp_cmd.wav", "wb"^) as f:
echo                 f.write^(audio.get_wav_data^(^)^)
echo.
echo             model = WhisperModel^("tiny", device="cpu", compute_type="int8"^)
echo             segments, _ = model.transcribe^("temp_cmd.wav", language="zh"^)
echo             text = "".join^([s.text for s in segments]^)
echo             if text:
echo                 print^(f"{Fore.GREEN}>> 听到: {text}{Style.RESET_ALL}"^)
echo                 return text
echo         except KeyboardInterrupt:
echo             print^(f"{Fore.YELLOW}[切换] 转为键盘输入。{Style.RESET_ALL}"^)
echo             return get_user_input_by_mode^(^)
echo         except Exception:
echo             pass
echo     return ""
echo.
echo # --- 主循环 ---
echo def main^(^):
echo     print^(f"{Fore.MAGENTA}========================================{Style.RESET_ALL}"^)
echo     print^(f"{Fore.MAGENTA} Noelle 已就绪。{Style.RESET_ALL}"^)
echo     if VOICE_MODE:
echo         print^(f"{Fore.MAGENTA} 模式：语音输入 (唤醒词: {WAKE_WORD}^){Style.RESET_ALL}"^)
echo     else:
echo         print^(f"{Fore.MAGENTA} 模式：文本输入{Style.RESET_ALL}"^)
echo     print^(f"{Fore.MAGENTA}========================================{Style.RESET_ALL}"^)
echo.
echo     while True:
echo         try:
echo             user_input = get_user_input_by_mode^(^)
echo             if not user_input:
echo                 continue
echo             if user_input.lower^(^) == "exit":
echo                 print^(f"{Fore.CYAN}[Noelle] 再见，主人。{Style.RESET_ALL}"^)
echo                 sys.exit^(0^)
echo.
echo             # 简单唤醒词处理
echo             cmd = user_input.replace^(WAKE_WORD, ""^).strip^(^)
echo             if not cmd:
echo                 print^(f"{Fore.YELLOW}[Noelle] 在呢，请吩咐。{Style.RESET_ALL}"^)
echo                 continue
echo.
echo             print^(f"{Fore.CYAN}[Noelle] 执行: {cmd}{Style.RESET_ALL}"^)
echo             if MODEL_STATUS:
echo                 interpreter.chat^(cmd^)
echo             else:
echo                 print^(f"{Fore.YELLOW}[Noelle] 当前无法执行复杂指令 (模型未加载^)。{Style.RESET_ALL}"^)
echo.
echo         except KeyboardInterrupt:
echo             print^(f"{Fore.YELLOW}\n[Noelle] 收到中断信号。{Style.RESET_ALL}"^)
echo         except Exception as e:
echo             print^(f"{Fore.RED}[错误] {e}{Style.RESET_ALL}"^)
echo.
echo if __name__ == "__main__":
echo     main^(^)
) > %CORE_FILE%

:: 11. 启动系统
if exist "Noelle_System\venv\Scripts\activate.bat" (
    call Noelle_System\venv\Scripts\activate.bat
    if "%VOICE_ENABLED%"=="1" (
        echo [模式] 启动语音交互模式...
    ) else (
        echo [模式] 启动文本交互模式...
    )
    python %CORE_FILE%
) else (
    echo [!] 错误：虚拟环境损坏，请删除 Noelle_System 文件夹并重新运行。
)
pause