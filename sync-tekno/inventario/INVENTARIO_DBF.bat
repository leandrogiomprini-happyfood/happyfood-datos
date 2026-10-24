@echo off
REM Happy Food - genera tablas.csv y campos.csv en C:\HAPPY_EXTRACTOR\INVENTARIO_DBF (solo lectura de encabezados)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0inventario_dbf.ps1"
pause
