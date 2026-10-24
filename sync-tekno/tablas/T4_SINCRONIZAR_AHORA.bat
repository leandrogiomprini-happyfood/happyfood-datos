@echo off
REM Corre una sincronizacion completa a mano. La primera vez hace la carga inicial de cada tabla.
cd /d C:\HAPPY_EXTRACTOR\SYNC
HappyTablas.exe sincronizar
if errorlevel 1 echo FALLO. Mandar ejecucion.log de AUTO_TABLAS\EJECUCIONES\(ultima carpeta).
if not errorlevel 1 echo SINCRONIZACION CORRECTA.
pause
