@echo off
setlocal enabledelayedexpansion
title Antigravity CLI - AGY Serviser Portable
cd /d "%~dp0"

set "USB_ROOT=%~dp0"
if "%USB_ROOT:~-1%"=="\" set "USB_ROOT=%USB_ROOT:~0,-1%"

set "PROFILE_DIR=%USB_ROOT%\data\accounts\primary"
if /i "%~1"=="-Fallback" set "PROFILE_DIR=%USB_ROOT%\data\accounts\fallback"
if /i "%~1"=="--fallback" set "PROFILE_DIR=%USB_ROOT%\data\accounts\fallback"

set "USERPROFILE=%PROFILE_DIR%"
set "HOME=%PROFILE_DIR%"
set "HOMEDRIVE=%~d0"
set "HOMEPATH=\data\accounts\primary"
set "APPDATA=%PROFILE_DIR%\AppData\Roaming"
set "LOCALAPPDATA=%PROFILE_DIR%\AppData\Local"
set "SSH_CLIENT=127.0.0.1 12345 22"
set "SSH_CONNECTION=127.0.0.1 12345 127.0.0.1 22"
set "SSH_TTY=/dev/pts/0"
set "TERM=xterm-256color"
set "PAGER=cat"

set "TARGET_CLI_DIR=%SystemDrive%\Users\%USERNAME%\.gemini\antigravity-cli"
set "BRIDGED=0"
if exist "%SystemDrive%\Users\%USERNAME%" (
    if not exist "%TARGET_CLI_DIR%\jetski-standalone-oauth-token" (
        if not exist "%TARGET_CLI_DIR%" mkdir "%TARGET_CLI_DIR%" >nul 2>&1
        copy /y "%PROFILE_DIR%\.gemini\antigravity-cli\*" "%TARGET_CLI_DIR%\" >nul 2>&1
        set "BRIDGED=1"
        echo [*] Privremeni most akreditiva postavljen.
    )
)

echo [*] Pokrecem Antigravity CLI (Servisni profil sa USB-a)...
echo [*] Za izlaz unesite /exit ili pritisnite Ctrl+C
echo.

"%USB_ROOT%\bin\agy.exe" %*

if "%BRIDGED%"=="1" (
    if exist "%TARGET_CLI_DIR%" (
        copy /y "%TARGET_CLI_DIR%\*" "%PROFILE_DIR%\.gemini\antigravity-cli\" >nul 2>&1
        del /q "%TARGET_CLI_DIR%\*token*" >nul 2>&1
        echo [OK] Privremeni most akreditiva bezbedno uklonjen.
    )
)

echo.
pause
