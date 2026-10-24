@echo off
cd /d C:\HAPPY_EXTRACTOR\SYNC
HappyAuto.exe probar
if errorlevel 1 echo PRUEBA FALLIDA. NO INSTALAR AUTOMATIZACION.
pause
