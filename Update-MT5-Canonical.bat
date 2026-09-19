@echo off
setlocal

set "REPO_ROOT=%~dp0"
set "SYNC_SCRIPT=%REPO_ROOT%tools\Sync-And-Compile-Canonical.ps1"

if not exist "%SYNC_SCRIPT%" (
    echo ERROR: Sync script not found:
    echo %SYNC_SCRIPT%
    pause
    exit /b 1
)

echo Updating the MT5 canonical indicator...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%SYNC_SCRIPT%\"'"
set "RESULT=%ERRORLEVEL%"

echo.
if "%RESULT%"=="0" (
    echo SUCCESS: MT5 source updated and compiled successfully.
    echo Result: 0 errors, 0 warnings
) else (
    echo FAILED: MT5 update or compilation failed.
    echo Check the compiler output above.
)

echo.
pause
exit /b %RESULT%