@echo off
REM Tarea cada 1 hora, a los :05. Usar la MISMA cuenta Windows que la tarea de ventas (credencial DPAPI).
setlocal
cd /d C:\HAPPY_EXTRACTOR\SYNC
if not exist AUTO_TABLAS\AUTORIZACION_AUTOMATICA.txt (
 echo FALTA AUTORIZACION: ejecutar T3 primero.
 pause
 exit /b 1
)
if exist AUTO_TABLAS\REQUIERE_REVISION.txt (
 echo DETENIDO: existe AUTO_TABLAS\REQUIERE_REVISION.txt
 pause
 exit /b 1
)
set /p CONFIRMA=Crear la tarea automatica cada 1 hora? Escribir PROGRAMAR_TABLAS: 
if not "%CONFIRMA%"=="PROGRAMAR_TABLAS" exit /b 2
echo Se pedira la contrasena de Windows de esta cuenta EN EL SERVIDOR (no enviarla al chat).
schtasks /create /f /tn "HappyFood_Tekno_Tablas_1h" /sc hourly /mo 1 /st 00:05 /tr "C:\HAPPY_EXTRACTOR\SYNC\HappyTablas.exe sincronizar" /ru "%USERDOMAIN%\%USERNAME%" /rp *
if errorlevel 1 echo ERROR: tarea no creada.
if not errorlevel 1 echo TAREA CREADA: HappyFood_Tekno_Tablas_1h
pause
