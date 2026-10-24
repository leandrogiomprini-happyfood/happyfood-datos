@echo off
setlocal
cd /d C:\HAPPY_EXTRACTOR\SYNC
set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if exist "%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" (
 echo ERROR: no se encontro compilador .NET 4.x
 pause
 exit /b 1
)
"%CSC%" /nologo /codepage:65001 /target:exe /out:HappyTablas.exe /r:System.Web.Extensions.dll /r:System.Core.dll /r:System.Security.dll HappyTablas.cs
if errorlevel 1 (
 echo ERROR DE COMPILACION. No se instalo nada.
 pause
 exit /b 1
)
echo COMPILACION CORRECTA: HappyTablas.exe
pause
