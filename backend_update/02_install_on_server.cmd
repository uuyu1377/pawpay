@echo off
chcp 65001 >nul
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0install_on_server.py" %*
) else (
  python "%~dp0install_on_server.py" %*
)
pause
