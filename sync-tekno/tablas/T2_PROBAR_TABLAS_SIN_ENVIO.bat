@echo off
REM Hace todo el ciclo (VSS, copia, extractor, comparacion) SIN conectarse a Supabase.
cd /d C:\HAPPY_EXTRACTOR\SYNC
HappyTablas.exe probar
if errorlevel 1 echo PRUEBA FALLIDA. Mandar ejecucion.log de AUTO_TABLAS\EJECUCIONES\(ultima carpeta).
if not errorlevel 1 echo PRUEBA CORRECTA. Mandar RESUMEN_CAMBIOS.txt de AUTO_TABLAS\EJECUCIONES\(ultima carpeta).
pause
