@echo off
setlocal
title Uklanjanje Servisnog Naloga sa ovog Racunara
cd /d "%~dp0"

set "USB_ROOT=%~dp0"
if "%USB_ROOT:~-1%"=="\" set "USB_ROOT=%USB_ROOT:~0,-1%"

set "TARGET_CLI_DIR=%SystemDrive%\Users\%USERNAME%\.gemini\antigravity-cli"
if exist "%TARGET_CLI_DIR%" (
    copy /y "%TARGET_CLI_DIR%\*" "%USB_ROOT%\data\accounts\primary\.gemini\antigravity-cli\" >nul 2>&1
    del /q "%TARGET_CLI_DIR%\*token*" >nul 2>&1
)

echo.
echo ==================================================================
echo [OK] Servisni nalog i tokeni su bezbedno uklonjeni sa ovog PC-ja!
echo Na klijentskom racunaru nije ostao nijedan sacuvan nalog.
echo ==================================================================
echo.
pause
