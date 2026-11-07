@echo off
setlocal
title Prijava Servisnog Naloga na ovaj Racunar
cd /d "%~dp0"

set "USB_ROOT=%~dp0"
if "%USB_ROOT:~-1%"=="\" set "USB_ROOT=%USB_ROOT:~0,-1%"

set "TARGET_CLI_DIR=%SystemDrive%\Users\%USERNAME%\.gemini\antigravity-cli"
if not exist "%TARGET_CLI_DIR%" mkdir "%TARGET_CLI_DIR%" >nul 2>&1

copy /y "%USB_ROOT%\data\accounts\primary\.gemini\antigravity-cli\*" "%TARGET_CLI_DIR%\" >nul 2>&1

echo.
echo ==================================================================
echo [OK] PRIMARNI SERVISNI NALOG SA USB-A JE AKTIVIRAN!
echo ==================================================================
echo.
echo Akreditivi su postavljeni u profil korisnika: %USERNAME%
echo Sada mozes pokretati bilo koju skriptu ili cak direktno bin\agy.exe
echo i bices automatski ulogovan bez ikakvog pitanja!
echo.
echo Kada zavrsis servisiranje masine, pokreni:
echo   Ukloni-Nalog-Sa-Racunara.bat
echo ==================================================================
echo.
pause
