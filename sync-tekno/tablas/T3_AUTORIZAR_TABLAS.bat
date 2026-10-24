@echo off
REM Ejecutar solo despues de que T2 salio bien y se aplico 002_tekno_registros.sql en Supabase.
cd /d C:\HAPPY_EXTRACTOR\SYNC
if exist AUTO_TABLAS\REQUIERE_REVISION.txt (
 echo DETENIDO: existe AUTO_TABLAS\REQUIERE_REVISION.txt
 pause
 exit /b 2
)
set /p CONFIRMA=Para habilitar el envio de tablas escribir AUTORIZO_SYNC_TABLAS_TEKNO: 
if not "%CONFIRMA%"=="AUTORIZO_SYNC_TABLAS_TEKNO" exit /b 2
if not exist AUTO_TABLAS mkdir AUTO_TABLAS
> AUTO_TABLAS\AUTORIZACION_AUTOMATICA.txt echo AUTORIZO_SYNC_TABLAS_TEKNO
echo ENVIO DE TABLAS AUTORIZADO.
pause
