@echo off
title Servis AI Asistent
cd /d "%~dp0"

:: 1. Provera administratorskih privilegija
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Zahtevam administratorska prava za servisnu dijagnostiku (UAC)...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File """"%~dp0Start-ServisAI.ps1""""' -Verb RunAs"
    exit /b
)

:: 2. Pokretanje glavnog PowerShell orkestratora sa -NoExit osiguracem
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Start-ServisAI.ps1"
