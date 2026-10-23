@echo off
REM ============================================================
REM noelle — Windows 启动器
REM 优先用 python，其次 py -3
REM ============================================================
setlocal

where python >nul 2>nul
if %errorlevel%==0 (
    python "%~dp0noelle.py" %*
    exit /b %errorlevel%
)

where py >nul 2>nul
if %errorlevel%==0 (
    py -3 "%~dp0noelle.py" %*
    exit /b %errorlevel%
)

echo [错误] 未找到 Python。请先安装 Python 3.9+：
echo         winget install Python.Python.3.12
exit /b 127
