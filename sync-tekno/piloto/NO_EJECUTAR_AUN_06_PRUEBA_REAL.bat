@echo off
cd /d C:\HAPPY_EXTRACTOR\SYNC
HappyAuto.exe sincronizar
if errorlevel 1 echo DETENIDO: NO reintentar sin revisar estado y Supabase.
pause
