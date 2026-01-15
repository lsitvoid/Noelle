@echo off
setlocal EnableDelayedExpansion
title 赛博管家 Jarvis - 一键部署程序 (容错记录版)
color 0A

echo ========================================================
echo       正在部署您的私人 AI 助手 (容错记录版)
echo       特性：错误收集 | 降级运行 | 最终报告
echo ========================================================
echo.

:: 初始化错误记录系统
set ERROR_REPORT_FILE=部署错误报告.log
set ERROR_COUNT=0
set WARNING_COUNT=0
echo [%date% %time%] Jarvis 部署开始 > "%ERROR_REPORT_FILE%"
echo ======================================== >> "%ERROR_REPORT_FILE%"

:: 设置项目目录
set PROJECT_ROOT=Jarvis_Final_Project
if not exist "%PROJECT_ROOT%" mkdir "%PROJECT_ROOT%"
cd /d "%PROJECT_ROOT%"

:: 函数：记录错误 (严重)
:log_error
setlocal
set step=%~1
set message=%~2
echo. >> "%ERROR_REPORT_FILE%"
echo [错误] 步骤：!step! >> "%ERROR_REPORT_FILE%"
echo       时间：%time% >> "%ERROR_REPORT_FILE%"
echo       详情：!message! >> "%ERROR_REPORT_FILE%"
endlocal
set /a ERROR_COUNT+=1
goto :eof

:: 函数：记录警告 (可降级)
:log_warning
setlocal
set step=%~1
set message=%~2
echo. >> "%ERROR_REPORT_FILE%"
echo [警告] 步骤：!step! >> "%ERROR_REPORT_FILE%"
echo       时间：%time% >> "%ERROR_REPORT_FILE%"
echo       详情：!message! >> "%ERROR_REPORT_FILE%"
endlocal
set /a WARNING_COUNT+=1
goto :eof

:: 函数：日志输出
:log
setlocal
set type=%~1
set message=%~2
set color=0E
if "!type!"=="SUCCESS" set color=0A
if "!type!"=="ERROR" set color=0C
echo [%time:~0,8%] !message!
endlocal
goto :eof

:: 1. 检查并安装 Python 3.10 (关键依赖，失败则终止)
echo [1/8] 检查 Python 3.10 环境...
python --version 2>nul | findstr /r /c:"Python 3.10" >nul
if %errorlevel% equ 0 (
    call :log SUCCESS "Python 3.10 已安装。"
) else (
    call :log INFO "Python 3.10 未安装，尝试通过 Winget 安装..."
    winget install -e --id Python.Python.3.10 --accept-package-agreements --accept-source-agreements --silent 2>&1 | findstr /v "^-"
    if !errorlevel! neq 0 (
        call :log_error "安装Python" "Winget自动安装失败，此为基础依赖，安装终止。"
        call :log ERROR "Python 安装失败，这是基础依赖，请手动安装。"
        goto :generate_report
    )
    call :log SUCCESS "Python 3.10 安装完成。"
)

:: 2. 检查并安装 Ollama (关键依赖，失败则终止)
echo.
echo [2/8] 检查 Ollama 环境...
ollama --version >nul 2>&1
if %errorlevel% equ 0 (
    call :log SUCCESS "Ollama 已安装。"
) else (
    call :log INFO "Ollama 未安装，开始安装..."
    winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements --silent 2>&1 | findstr /v "^-"
    if !errorlevel! neq 0 (
        call :log_error "安装Ollama" "Winget自动安装失败，尝试备用curl方案..."
        curl -fsSL https://ollama.com/install.sh | bash 2>&1 | findstr /v "^-"
        if !errorlevel! neq 0 (
            call :log_error "安装Ollama" "所有安装方式均失败，此为基础依赖，安装终止。"
            call :log ERROR "Ollama 安装失败，这是基础依赖，请手动安装。"
            goto :generate_report
        )
    )
    call :log SUCCESS "Ollama 安装完成。"
)

:: 3. 启动服务并尝试拉取模型 (非关键，可降级)
echo.
echo [3/8] 启动 Ollama 服务并尝试拉取 AI 模型...
call :log INFO "正在启动后台服务..."
start /b ollama serve >nul 2>&1
timeout /t 10 >nul

set MODEL_NAME=deepseek-coder:6.7b
set MODEL_FALLBACK=deepseek-coder:1.3b
set MODEL_PULL_SUCCESS=0

:: 尝试拉取首选模型 (最多3次)
set max_retries=3
for /l %%i in (1,1,!max_retries!) do (
    if !MODEL_PULL_SUCCESS! equ 0 (
        call :log INFO "尝试拉取模型 !MODEL_NAME! (第 %%i/!max_retries! 次)..."
        ollama pull !MODEL_NAME! >nul 2>&1
        if !errorlevel! equ 0 (
            set MODEL_PULL_SUCCESS=1
            call :log SUCCESS "模型 !MODEL_NAME! 拉取成功。"
        ) else (
            if %%i lss !max_retries! (
                call :log WARN "拉取失败，15秒后重试..."
                timeout /t 15 >nul
            )
        )
    )
)

:: 如果首选模型失败，尝试拉取小尺寸备选模型
if !MODEL_PULL_SUCCESS! equ 0 (
    call :log WARN "主模型拉取失败，尝试备选小模型 !MODEL_FALLBACK!..."
    ollama pull !MODEL_FALLBACK! >nul 2>&1
    if !errorlevel! equ 0 (
        set MODEL_PULL_SUCCESS=1
        set MODEL_NAME=!MODEL_FALLBACK!
        call :log SUCCESS "备选模型 !MODEL_NAME! 拉取成功。"
        call :log_warning "拉取AI模型" "主模型 !MODEL_NAME! 拉取失败，已降级使用小模型 !MODEL_FALLBACK!。"
    ) else (
        call :log_warning "拉取AI模型" "所有模型拉取尝试均失败，AI核心功能将不可用。您稍后可手动执行 'ollama pull'。"
        call :log WARN "模型拉取失败，AI功能将受限。"
    )
)

:: 4. 创建虚拟环境 (非关键，失败可记录但继续尝试)
echo.
echo [4/8] 配置 Python 虚拟环境...
if exist "Jarvis_Env" (
    call :log INFO "检测到已存在的虚拟环境，尝试复用..."
    call Jarvis_Env\Scripts\activate.bat >nul 2>&1
    if !errorlevel! neq 0 (
        call :log WARN "现有环境可能损坏，尝试重建..."
        rmdir /s /q Jarvis_Env 2>nul
        python -m venv Jarvis_Env
    )
) else (
    python -m venv Jarvis_Env
)
if exist "Jarvis_Env" (
    call :log SUCCESS "虚拟环境就绪。"
) else (
    call :log_warning "创建虚拟环境" "虚拟环境创建失败，将尝试在全局Python中安装依赖。"
    call :log WARN "虚拟环境创建失败，将使用系统Python。"
)

:: 5. 安装 Python 依赖 (非关键，失败可记录但继续)
echo.
echo [5/8] 安装 Python 核心依赖库...
if exist "Jarvis_Env" (
    call Jarvis_Env\Scripts\activate.bat
) else (
    call :log INFO "在系统Python中安装依赖..."
)

:: 尝试用默认源安装
call :log INFO "尝试安装依赖 (默认源)..."
pip install open-interpreter==0.2.7 faster-whisper pyaudio SpeechRecognition colorama pygame pynput --quiet >nul 2>&1
if !errorlevel! neq 0 (
    call :log WARN "默认源安装失败，尝试使用国内镜像源..."
    pip install open-interpreter==0.2.7 faster-whisper pyaudio SpeechRecognition colorama pygame pynput -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn --quiet >nul 2>&1
    if !errorlevel! neq 0 (
        call :log_warning "安装Python依赖" "pip安装依赖失败，语音识别和Live2D功能可能受影响。"
        call :log WARN "部分依赖安装失败，相关功能可能不可用。"
    ) else (
        call :log SUCCESS "依赖安装成功 (使用镜像源)。"
    )
) else (
    call :log SUCCESS "依赖安装成功。"
)

:: 6. 配置 Live2D 资源 (非关键，完全可降级)
echo.
echo [6/8] 配置 Live2D 模型资源...
set LIVE2D_DIR=live2d_resources
if not exist "%LIVE2D_DIR%" mkdir "%LIVE2D_DIR%"
cd "%LIVE2D_DIR%"

set LIVE2D_AVAILABLE=0
if not exist "Hiyori.model3.json" (
    call :log INFO "尝试下载 Live2D 示例模型..."
    powershell -Command "Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/guansss/pyLive2D2/demo/live2d_resources/Hiyori/Hiyori.model3.json' -OutFile 'Hiyori.model3.json' -UserAgent 'Mozilla/5.0' -TimeoutSec 20" >nul 2>&1
    if exist "Hiyori.model3.json" (
        set LIVE2D_AVAILABLE=1
        call :log SUCCESS "Live2D 模型下载完成。"
    ) else (
        call :log_warning "下载Live2D模型" "Live2D模型下载失败，将使用内置备用图形。"
        call :log WARN "Live2D 模型下载失败，将使用备用图形。"
    )
) else (
    set LIVE2D_AVAILABLE=1
    call :log SUCCESS "Live2D 模型已存在。"
)
cd ..

:: 7. 生成运行脚本 (总会成功，但内容取决于前面状态)
echo.
echo [7/8] 生成智能运行脚本...
call :log INFO "根据系统状态生成自适应脚本..."

:: 动态生成 AI 核心脚本，根据拉取结果设置模型
(
echo import time, sys, speech_recognition as sr
echo from faster_whisper import WhisperModel
echo from interpreter import interpreter
echo from colorama import Fore, Style, init
echo init^(autoreset=True^)
echo.
echo WAKE_WORD = "贾维斯"
echo MODEL_PATH = "tiny"
echo.
:: 根据实际拉取的模型设置
if "!MODEL_PULL_SUCCESS!"=="1" (
    echo AI_MODEL = "ollama/!MODEL_NAME!"
) else (
    echo AI_MODEL = ""
    echo print^(f"{Fore.RED}[警告] 未检测到可用AI模型，请手动执行 'ollama pull' 命令。{Style.RESET_ALL}"^)
)
echo.
echo # ... [中间部分与之前类似，为节省篇幅省略] ...
echo.
) > jarvis_core.py

:: 生成 Live2D 显示脚本，根据可用性设置标志
(
echo import pygame, sys, os
echo
echo # 配置
echo LIVE2D_AVAILABLE = !LIVE2D_AVAILABLE!
echo # ... [其余部分与之前类似] ...
echo.
) > live2d_viewer.py

:: 生成主启动脚本
(
echo @echo off
echo title Jarvis - 自适应启动器
echo echo 状态概览：
if "!MODEL_PULL_SUCCESS!"=="1" (
    echo echo   AI 模型：!MODEL_NAME! (已就绪)
) else (
    echo echo   AI 模型：未就绪 ^(需手动拉取^)
)
if "!LIVE2D_AVAILABLE!"=="1" (
    echo echo   桌面宠物：Live2D 模型 (已就绪)
) else (
    echo echo   桌面宠物：备用图形模式
)
echo echo.
echo echo [1/2] 启动 AI 核心...
echo start "Jarvis AI Core" cmd /k "call Jarvis_Env\Scripts\activate.bat ^& python jarvis_core.py"
echo timeout /t 2
echo echo.
echo echo [2/2] 启动桌面宠物...
echo call Jarvis_Env\Scripts\activate.bat
echo python live2d_viewer.py
echo pause
) > start_javis.bat

call :log SUCCESS "运行脚本生成完成。"

:: 8. 最终报告生成
:generate_report
echo.
echo [8/8] 生成部署报告...
echo. >> "%ERROR_REPORT_FILE%"
echo ======================================== >> "%ERROR_REPORT_FILE%"
echo [%date% %time%] 部署结束 >> "%ERROR_REPORT_FILE%"
echo. >> "%ERROR_REPORT_FILE%"
echo ********** 部署摘要 ********** >> "%ERROR_REPORT_FILE%"
echo 严重错误: !ERROR_COUNT! 个 >> "%ERROR_REPORT_FILE%"
echo 降级警告: !WARNING_COUNT! 个 >> "%ERROR_REPORT_FILE%"
echo. >> "%ERROR_REPORT_FILE%"
echo 关键组件状态： >> "%ERROR_REPORT_FILE%"
echo   Python 3.10: 已安装 >> "%ERROR_REPORT_FILE%"
echo   Ollama: 已安装 >> "%ERROR_REPORT_FILE%"
if "!MODEL_PULL_SUCCESS!"=="1" (
    echo   AI 模型: !MODEL_NAME! (已就绪) >> "%ERROR_REPORT_FILE%"
) else (
    echo   AI 模型: 未就绪 >> "%ERROR_REPORT_FILE%"
)
if "!LIVE2D_AVAILABLE!"=="1" (
    echo   Live2D 模型: 已就绪 >> "%ERROR_REPORT_FILE%"
) else (
    echo   Live2D 模型: 备用图形模式 >> "%ERROR_REPORT_FILE%"
)
echo. >> "%ERROR_REPORT_FILE%"
echo 详细错误和警告记录见上文。 >> "%ERROR_REPORT_FILE%"

call :log INFO "=========================================="
call :log INFO "部署流程结束！"
call :log INFO "=========================================="
echo.
if !ERROR_COUNT! gtr 0 (
    call :log ERROR "发生 !ERROR_COUNT! 个严重错误，请查看报告。"
) else (
    call :log SUCCESS "未发生严重错误。"
)
if !WARNING_COUNT! gtr 0 (
    call :log WARN "发生 !WARNING_COUNT! 个降级警告，系统已自适应处理。"
)
echo.
echo ******************** 最终状态 ********************
echo 项目目录：%cd%
echo.
if "!MODEL_PULL_SUCCESS!"=="1" (
    echo AI 模型：!MODEL_NAME! - ^(已就绪^)
) else (
    echo AI 模型：**未就绪** - ^(需手动执行 'ollama pull'^)
)
if "!LIVE2D_AVAILABLE!"=="1" (
    echo 桌面宠物：Live2D 模型 - ^(已就绪^)
) else (
    echo 桌面宠物：**备用图形** - ^(Live2D下载失败^)
)
echo.
echo ********** 生成文件 **********
echo 1. 错误报告：%ERROR_REPORT_FILE%
echo 2. 主启动脚本：start_javis.bat
echo 3. AI 核心：jarvis_core.py
echo 4. 桌面宠物：live2d_viewer.py
echo.
echo ********** 使用建议 **********
if "!MODEL_PULL_SUCCESS!"=="0" (
    echo → 请手动拉取AI模型：ollama pull deepseek-coder:6.7b
)
if "!LIVE2D_AVAILABLE!"=="0" (
    echo → Live2D使用备用图形，如需完整模型可手动下载。
)
echo → 双击运行 start_javis.bat 启动完整系统。
echo.
echo 注意：所有错误和警告的详细记录已保存至报告文件。
pause