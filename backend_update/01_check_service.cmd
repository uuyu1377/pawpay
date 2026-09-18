@echo off
chcp 65001 >nul
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0check_income_service.py" http://120.126.16.227:5000
) else (
  python "%~dp0check_income_service.py" http://120.126.16.227:5000
)
pause
