# ============================================================
# noelle-win 安装脚本 (PowerShell)
#
# 用法（在解压后的目录里，右键“使用 PowerShell 运行”，或）：
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Info($m) { Write-Host "[noelle] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[警告] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[错误] $m" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------
# 1. 检查 Python
# ------------------------------------------------------------
$py = $null
foreach ($c in @("python", "py")) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break }
}
if (-not $py) {
    Die "未找到 Python。请先执行: winget install Python.Python.3.12"
}

$ver = & $py -c "import sys;print('%d.%d'%sys.version_info[:2])"
Info "Python $ver ($py)"

if ([version]$ver -lt [version]"3.9") {
    Die "需要 Python 3.9 或更高，当前 $ver"
}

# ------------------------------------------------------------
# 2. 部署到 %LOCALAPPDATA%\noelle
# ------------------------------------------------------------
$Dest = Join-Path $env:LOCALAPPDATA "noelle"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

Copy-Item (Join-Path $Root "noelle.py") $Dest -Force
if (Test-Path (Join-Path $Root "assets")) {
    Copy-Item (Join-Path $Root "assets") $Dest -Recurse -Force
}
Info "核心文件 -> $Dest"

# ------------------------------------------------------------
# 3. 生成启动器（不加 .cmd 后缀，PowerShell 里可直接 noelle）
# ------------------------------------------------------------
$Launcher = Join-Path $Dest "noelle.cmd"
@"
@echo off
$py "$Dest\noelle.py" %*
"@ | Set-Content -Path $Launcher -Encoding ASCII
Info "启动器 -> $Launcher"

# ------------------------------------------------------------
# 4. 加入用户 PATH
# ------------------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$Dest*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$Dest", "User")
    Info "已加入用户 PATH（重开终端生效）"
    Warn "当前窗口请手动执行: `$env:Path += `";$Dest`""
} else {
    Info "PATH 已存在，跳过"
}

# ------------------------------------------------------------
# 5. 完成
# ------------------------------------------------------------
Write-Host ""
Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host " 安装完成" -ForegroundColor Green
Write-Host ""
Write-Host "   首次设置：  noelle            # 自动进入配置向导"
Write-Host "   普通模式：  noelle normal"
Write-Host "   单次提问：  noelle ask `"问题`""
Write-Host "   配置查看：  noelle config"
Write-Host "   人格管理：  noelle persona `"你是...`""
Write-Host "   路径信息：  noelle paths"
Write-Host ""
Write-Host " 配置目录：$env:APPDATA\noelle"
Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray
