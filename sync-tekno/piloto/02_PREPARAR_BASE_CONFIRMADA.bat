@echo off
cd /d C:\HAPPY_EXTRACTOR\SYNC
HappyAuto.exe preparar
if errorlevel 1 echo DETENIDO. Revisar mensaje de error.
pause
