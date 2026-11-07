@echo off
setlocal enabledelayedexpansion
title Servis AI Asistent - Antigravity CLI Portable
cd /d "%~dp0"

echo ==================================================================
echo         ANTIGRAVITY CLI PORTABLE - SERVISNI ASISTENT             
echo           Google AI Pro Tehnologija za Servisnu Dijagnostiku     
echo ==================================================================
echo.

set "USB_ROOT=%~dp0"
if "%USB_ROOT:~-1%"=="\" set "USB_ROOT=%USB_ROOT:~0,-1%"

:: 1. Odabir profila (Podrazumevano Primarni nalog, parametar -Fallback za rezervni nalog)
set "PROFILE_DIR=%USB_ROOT%\data\accounts\primary"
if /i "%~1"=="-Fallback" set "PROFILE_DIR=%USB_ROOT%\data\accounts\fallback"
if /i "%~1"=="--fallback" set "PROFILE_DIR=%USB_ROOT%\data\accounts\fallback"

if not exist "%PROFILE_DIR%\.gemini" (
    echo [!] Primarni profil nije pronadjen, koristim data folder...
    set "PROFILE_DIR=%USB_ROOT%\data"
)

echo [*] Aktiviran profil na USB-u: %PROFILE_DIR%

:: 2. Postavljanje prenosivih promenljivih okruzenja
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

:: 3. Pametni most akreditiva ka profilu klijenta na disku C:
:: Garantuje da agy.exe pronalazi tokene cak i kada Win32 API ociatva pravi C:\Users profil
set "TARGET_CLI_DIR=%SystemDrive%\Users\%USERNAME%\.gemini\antigravity-cli"
set "BRIDGED=0"

if exist "%SystemDrive%\Users\%USERNAME%" (
    if not exist "%TARGET_CLI_DIR%\jetski-standalone-oauth-token" (
        if not exist "%TARGET_CLI_DIR%" mkdir "%TARGET_CLI_DIR%" >nul 2>&1
        copy /y "%PROFILE_DIR%\.gemini\antigravity-cli\*" "%TARGET_CLI_DIR%\" >nul 2>&1
        set "BRIDGED=1"
        echo [*] Aktiviran privremeni most akreditiva za korisnika %USERNAME%.
    )
)

:: 4. Pokretanje PowerShell orkestratora (sa fallback-om na direktni agy.exe)
if exist "%USB_ROOT%\Start-ServisAI.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USB_ROOT%\Start-ServisAI.ps1" %*
) else (
    echo [!] Start-ServisAI.ps1 nije pronadjen, pokrecem direktni CLI...
    "%USB_ROOT%\bin\agy.exe" %*
)

:: 5. Ciscenje mosta akreditiva pri izlazu (Zero-trace)
if "%BRIDGED%"=="1" (
    if exist "%TARGET_CLI_DIR%" (
        copy /y "%TARGET_CLI_DIR%\*" "%PROFILE_DIR%\.gemini\antigravity-cli\" >nul 2>&1
        del /q "%TARGET_CLI_DIR%\*token*" >nul 2>&1
        echo [OK] Privremeni akreditivi bezbedno uklonjeni sa ovog racunara.
    )
)

echo.
echo ==================================================================
echo [OK] Sesija je zavrsena.
pause
