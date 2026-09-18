@echo off
setlocal
cd /d "%~dp0"
set "PAWPAY_FLUTTER=C:\src\flutter\bin\flutter.bat"
if not exist "pubspec.yaml" (
  echo ERROR: Run this file from the extracted Pawpay project.
  pause
  exit /b 1
)
if not exist "%PAWPAY_FLUTTER%" (
  echo ERROR: Flutter was not found at C:\src\flutter.
  echo See ANDROID_PHONE_GUIDE_zh-TW.html for setup instructions.
  pause
  exit /b 1
)
call "%PAWPAY_FLUTTER%" pub get
if errorlevel 1 goto failed
if "%~1"=="" (
  call "%PAWPAY_FLUTTER%" run
) else (
  call "%PAWPAY_FLUTTER%" run -d "%~1"
)
if errorlevel 1 goto failed
exit /b 0
:failed
echo.
echo Build or connection failed. Keep the error above for troubleshooting.
pause
exit /b 1
