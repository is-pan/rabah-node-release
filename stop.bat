@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

title Rabah Network Node - Stop

set "CONFIG_FILE=%~dp0node-config.txt"
set "NODE_NAME=%NODE_NAME%"
set "GPU_INDEX=%GPU_INDEX%"
set "STOP_ALL=%STOP_ALL%"
set "NO_PAUSE=%NO_PAUSE%"
set "LEGACY_NODE_NAME="
set "NODE_NAME_FROM_ENV=0"
set "GPU_INDEX_FROM_ENV=0"
if not "%NODE_NAME%"=="" set "NODE_NAME_FROM_ENV=1"
if not "%GPU_INDEX%"=="" set "GPU_INDEX_FROM_ENV=1"

if "%STOP_ALL%"=="" set "STOP_ALL=0"

if exist "%CONFIG_FILE%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
    if /i "%%A"=="NODE_NAME" if "!LEGACY_NODE_NAME!"=="" set "LEGACY_NODE_NAME=%%B"
    if /i "%%A"=="GPU_INDEX" if "!GPU_INDEX!"=="" set "GPU_INDEX=%%B"
  )
)

if "%NODE_NAME%"=="" (
  if exist "%CONFIG_FILE%" if not "%GPU_INDEX%"=="" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
      if /i "%%A"=="NODE_NAME_GPU%GPU_INDEX%" set "NODE_NAME=%%B"
    )
  )
  if "!NODE_NAME!"=="" if not "!LEGACY_NODE_NAME!"=="" set "NODE_NAME=!LEGACY_NODE_NAME!"
)

if "%NODE_NAME%"=="" (
  if "%GPU_INDEX%"=="" (
    set "GPU_INDEX=0"
  )
  set "NODE_NAME=rabah-node-gpu%GPU_INDEX%"
)

docker --version >nul 2>nul
if errorlevel 1 (
  echo ERROR: Docker not found in PATH.
  echo.
  if /i "%NO_PAUSE%"=="1" exit /b 1
  pause
  exit /b 1
)

docker info >nul 2>nul
if errorlevel 1 (
  echo ERROR: Docker is not running.
  echo.
  if /i "%NO_PAUSE%"=="1" exit /b 1
  pause
  exit /b 1
)

set "COUNT=0"
for /f "usebackq delims=" %%C in (`docker ps --format "{{.Names}}" ^| findstr /i /r "^rabah-node"`) do (
  set /a COUNT+=1
  set "C_NAME_!COUNT!=%%C"
)

if /i "%STOP_ALL%"=="1" goto stop_all

if "%COUNT%"=="0" (
  echo No running node containers found by name prefix: rabah-node
  echo Attempting to stop configured node: !NODE_NAME!
  call :stop_one "!NODE_NAME!"
  goto done
)

set "AUTO_STOP=0"
if "!NODE_NAME_FROM_ENV!"=="1" set "AUTO_STOP=1"
if "!GPU_INDEX_FROM_ENV!"=="1" set "AUTO_STOP=1"
if /i "%NO_PAUSE%"=="1" set "AUTO_STOP=1"

if "!AUTO_STOP!"=="1" (
  echo Stopping node container: !NODE_NAME!
  call :stop_one "!NODE_NAME!"
  goto done
)

if "%COUNT%"=="1" (
  echo Stopping node container: !C_NAME_1!
  call :stop_one "!C_NAME_1!"
  goto done
)

:stop_select_menu
echo Node selection:
echo - Found %COUNT% nodes containers:
for /l %%I in (1,1,%COUNT%) do (
  echo   [%%I] !C_NAME_%%I!
)
echo   [A] Stop all
echo   [Q] Quit
set "CHOICE="
echo.
set /p CHOICE=Select: 

if "!CHOICE!"=="" goto stop_select_menu
if /i "!CHOICE!"=="Q" goto done
if /i "!CHOICE!"=="A" goto stop_all

set "SELECTED="
for /l %%I in (1,1,%COUNT%) do (
  if "!CHOICE!"=="%%I" set "SELECTED=!C_NAME_%%I!"
)

if "!SELECTED!"=="" (
  echo.
  echo ERROR: Invalid selection.
  echo.
  goto stop_select_menu
)

echo Stopping node container: !SELECTED!
call :stop_one "!SELECTED!"
goto done

:stop_all
echo Stopping all running node containers with name prefix: rabah-node
for /l %%I in (1,1,%COUNT%) do (
  call :stop_one "!C_NAME_%%I!"
)
goto done

:stop_one
set "TARGET=%~1"
if "!TARGET!"=="" exit /b 0
echo - stopping !TARGET!
docker rm -f "!TARGET!" >nul 2>nul
exit /b 0

:done
echo Done.
echo.
if /i "%NO_PAUSE%"=="1" exit /b 0
pause
exit /b 0
