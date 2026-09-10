@echo off
setlocal EnableDelayedExpansion
title Pokretanje Servis AI Asistenta...

:: 1. Provera administratorskih privilegija
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Skripta zahteva administratorska prava za servisnu dijagnostiku.
    echo [*] Pokrecem zahtev za pisenje privilegija (UAC)...
    powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/k \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: 2. Postavljanje radnog direktorijuma na lokaciju ove skripte
cd /d "%~dp0"

:: 3. Pozivanje glavnog PowerShell orkestratora
echo [*] Pokrecem Servis AI Asistenta...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ServisAI.ps1"

:: 4. Ciscenje i zavrsetak
echo.
echo [*] Servisna sesija je zavrsena. Pritisnite bilo koji taster za zatvaranje prozora.
pause >nul
exit /b
