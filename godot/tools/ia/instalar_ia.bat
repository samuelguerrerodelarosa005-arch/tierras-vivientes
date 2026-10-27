@echo off
rem Instala la IA local de Tierras Vivas (unos 3,5 GB). Se puede repetir: sigue donde se quedo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ia\instalar_ia.ps1"
pause
