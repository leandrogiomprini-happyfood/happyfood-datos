@echo off
REM Requiere prueba completa revisada y aprobacion humana posterior.
cd /d C:\HAPPY_EXTRACTOR\SYNC
if not exist AUTO_ESTADO\BASE_CONFIRMADA\movivent.csv exit /b 1
if exist AUTO_ESTADO\REQUIERE_REVISION.txt exit /b 2
set /p CONFIRMA=Para habilitar escrituras automaticas ingresar AUTORIZO_SYNC_AUTOMATICA_CADA_10_MIN: 
if not "%CONFIRMA%"=="AUTORIZO_SYNC_AUTOMATICA_CADA_10_MIN" exit /b 2
> AUTO_ESTADO\AUTORIZACION_AUTOMATICA.txt echo AUTORIZO_SYNC_AUTOMATICA_CADA_10_MIN
echo ESCRITURA AUTOMATICA AUTORIZADA EN ESTA CUENTA DE WINDOWS.
pause
