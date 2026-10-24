@echo off
REM Solo ejecutar DESPUES de confirmar prueba real, con cuenta del mismo usuario que guarda DPAPI.
setlocal
cd /d C:\HAPPY_EXTRACTOR\SYNC
if not exist AUTO_ESTADO\AUTORIZACION_AUTOMATICA.txt (
 echo FALTA AUTORIZACION AUTOMATICA
 pause
 exit /b 1
)
if exist AUTO_ESTADO\REQUIERE_REVISION.txt (
 echo DETENIDO: existe bloqueo por revision
 pause
 exit /b 1
)
set /p CONFIRMA=Crear la tarea automatica 24x7 cada 10 minutos? Escribir PROGRAMAR_10_MIN: 
if not "%CONFIRMA%"=="PROGRAMAR_10_MIN" exit /b 2
echo ATENCION: utilizar la MISMA cuenta Windows que tiene la credencial DPAPI.
echo Se solicitara la contrasena Windows de esa cuenta EN TU SERVIDOR (no enviarla al chat).
schtasks /create /f /tn "HappyFood_Tekno_Supabase_10min" /sc minute /mo 10 /tr "C:\HAPPY_EXTRACTOR\SYNC\HappyAuto.exe sincronizar" /ru "%USERDOMAIN%\%USERNAME%" /rp *
if errorlevel 1 echo ERROR: tarea no creada. Verificar permisos de usuario.
if not errorlevel 1 echo TAREA CREADA. Verificar ultimo resultado en Programador de tareas.
pause
