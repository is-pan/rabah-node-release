@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

title Rabah Network Node

set "CONFIG_FILE=%~dp0node-config.txt"
set "EMAIL=%EMAIL%"
set "WALLET_ADDRESS=%WALLET_ADDRESS%"
set "GPU_INDEX=%GPU_INDEX%"
set "NODE_NAME=%NODE_NAME%"
set "MODELS_DIR=%MODELS_DIR%"
set "MODEL_ID=%MODEL_ID%"
set "RESET_CONFIG=%RESET_CONFIG%"
set "ASK_ON_START=%ASK_ON_START%"
set "DRY_RUN=%DRY_RUN%"
set "NO_PAUSE=%NO_PAUSE%"
set "AUTO_UPDATE=%AUTO_UPDATE%"
set "AGENT_IMAGE=%AGENT_IMAGE%"
set "ALLOW_ENV_FILE=%ALLOW_ENV_FILE%"
set "ALLOW_ADVANCED_CONFIG=%ALLOW_ADVANCED_CONFIG%"
set "ENV_FILE_ARG="
set "ENV_FILE_FOUND=0"
set "SERVER_URL_DISPLAY="
set "NODE_NAME_FROM_ENV=0"
if not "%NODE_NAME%"=="" set "NODE_NAME_FROM_ENV=1"
set "GPU_INDEX_FROM_ENV=0"
if not "%GPU_INDEX%"=="" set "GPU_INDEX_FROM_ENV=1"
set "SELECT_NODE_ON_START="
set "CFG_COUNT=0"
if "%ALLOW_ENV_FILE%"=="" set "ALLOW_ENV_FILE=0"
if "%ALLOW_ADVANCED_CONFIG%"=="" set "ALLOW_ADVANCED_CONFIG=0"
if /i "%ALLOW_ENV_FILE%"=="1" if exist "%~dp0.env" (
  set "ENV_FILE_FOUND=1"
  set "ENV_FILE_ARG=--env-file ""%~dp0.env"""
  for /f "usebackq tokens=1,* delims==" %%A in ("%~dp0.env") do (
    if /i "%%A"=="SERVER_URL" if "!SERVER_URL_DISPLAY!"=="" set "SERVER_URL_DISPLAY=%%B"
    if /i "%%A"=="AUTO_UPDATE" if "!AUTO_UPDATE!"=="" set "AUTO_UPDATE=%%B"
    if /i "%%A"=="AGENT_IMAGE" if "!AGENT_IMAGE!"=="" set "AGENT_IMAGE=%%B"
    if /i "%%A"=="MODELS_DIR" if "!MODELS_DIR!"=="" set "MODELS_DIR=%%B"
  )
)

docker --version >nul 2>nul
if errorlevel 1 (
  echo ERROR: Docker not found in PATH.
  echo Please install Docker Desktop and reopen this window.
  echo.
  pause
  exit /b 1
)

docker info >nul 2>nul
if errorlevel 1 (
  echo ERROR: Docker is not running.
  echo Please start Docker Desktop ^(Linux containers^) and try again.
  echo.
  pause
  exit /b 1
)

if /i "%RESET_CONFIG%"=="1" (
  if exist "%CONFIG_FILE%" del /f /q "%CONFIG_FILE%" >nul 2>nul
  set "NODE_NAME="
)

if exist "%CONFIG_FILE%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
    set "CFG_K=%%A"
    if /i "%%A"=="EMAIL" if "!EMAIL!"=="" set "EMAIL=%%B"
    if /i "%%A"=="WALLET_ADDRESS" if "!WALLET_ADDRESS!"=="" set "WALLET_ADDRESS=%%B"
    if /i "%%A"=="GPU_INDEX" if "!GPU_INDEX!"=="" set "GPU_INDEX=%%B"
    if /i "%%A"=="MODELS_DIR" if "!MODELS_DIR!"=="" set "MODELS_DIR=%%B"
    if /i "%%A"=="MODEL_ID" if "!MODEL_ID!"=="" set "MODEL_ID=%%B"
    if /i "%%A"=="NODE_NAME" if "!LEGACY_NODE_NAME!"=="" set "LEGACY_NODE_NAME=%%B"
    if /i "%%A"=="SELECT_NODE_ON_START" if "!SELECT_NODE_ON_START!"=="" set "SELECT_NODE_ON_START=%%B"
    if /i "!CFG_K:~0,13!"=="NODE_NAME_GPU" (
      set /a CFG_COUNT+=1
      set "CFG_GPU_!CFG_COUNT!=!CFG_K:~13!"
      set "CFG_NODE_!CFG_COUNT!=%%B"
    )
  )
)
set "CFG_K="

if "%SELECT_NODE_ON_START%"=="" set "SELECT_NODE_ON_START=1"
if /i "%SELECT_NODE_ON_START%"=="0" (
  set "SELECT_NODE_ON_START=0"
) else (
  set "SELECT_NODE_ON_START=1"
)

if /i not "%ALLOW_ADVANCED_CONFIG%"=="1" (
  set "AUTO_UPDATE="
  set "AGENT_IMAGE="
)

if "%AUTO_UPDATE%"=="" set "AUTO_UPDATE=1"
if "%AGENT_IMAGE%"=="" set "AGENT_IMAGE=ghcr.io/is-pan/rabah-node:latest"
if "%MODELS_DIR%"=="" set "MODELS_DIR=%~dp0models"
if "%MODEL_ID%"=="" set "MODEL_ID=flux-2-klein-9b-fp8"

set "MODELS_DIR=!MODELS_DIR:"=!"
set "MODELS_DIR_IS_ABS=0"
if "!MODELS_DIR:~1,1!"==":" set "MODELS_DIR_IS_ABS=1"
if "!MODELS_DIR:~0,2!"=="\\" set "MODELS_DIR_IS_ABS=1"
if "!MODELS_DIR:~0,1!"=="/" set "MODELS_DIR_IS_ABS=1"
if "!MODELS_DIR_IS_ABS!"=="0" (
  for %%I in ("%~dp0!MODELS_DIR!") do set "MODELS_DIR=%%~fI"
) else (
  for %%I in ("!MODELS_DIR!") do set "MODELS_DIR=%%~fI"
)

if "%NODE_NAME%"=="" if "%GPU_INDEX_FROM_ENV%"=="0" if "%SELECT_NODE_ON_START%"=="1" if %CFG_COUNT% GTR 0 (
  if %CFG_COUNT% EQU 1 (
    call set "GPU_INDEX=%%CFG_GPU_1%%"
    call set "NODE_NAME=%%CFG_NODE_1%%"
  ) else (
    set "SELECTED_GPU="
    set "SELECTED_NODE="
    set "_AUTO_SEL=0"
    if /i "%NO_PAUSE%"=="1" set "_AUTO_SEL=1"
    if /i "%DRY_RUN%"=="1" set "_AUTO_SEL=1"
    if "!_AUTO_SEL!"=="1" (
      set "SELECTED_GPU=%GPU_INDEX%"
      for /l %%I in (1,1,%CFG_COUNT%) do (
        if "!SELECTED_GPU!"=="%%CFG_GPU_%%I%%" (
          call set "SELECTED_NODE=%%CFG_NODE_%%I%%"
        )
      )
      if "!SELECTED_NODE!"=="" (
        call set "SELECTED_GPU=%%CFG_GPU_1%%"
        call set "SELECTED_NODE=%%CFG_NODE_1%%"
      )
    ) else (
      echo Node selection:
      echo - Found %CFG_COUNT% saved nodes:
      for /l %%I in (1,1,%CFG_COUNT%) do (
        call echo   [%%I] GPU %%CFG_GPU_%%I%% - %%CFG_NODE_%%I%%
      )
      echo   [A] Start all
      echo   [Q] Quit
      echo.
      call :prompt_node_selection
      if /i "!CHOICE!"=="Q" exit /b 0
      if /i "!CHOICE!"=="A" (
        call :start_all_nodes
        call set "SELECTED_GPU=%%CFG_GPU_1%%"
        call set "SELECTED_NODE=%%CFG_NODE_1%%"
      )
    )
    set "GPU_INDEX=!SELECTED_GPU!"
    set "NODE_NAME=!SELECTED_NODE!"
    set "_AUTO_SEL="
    set "SELECTED_GPU="
    set "SELECTED_NODE="
  )
)

if /i "%ASK_ON_START%"=="1" (
  set "ASK_EMAIL=1"
  set "ASK_WALLET=1"
  set "ASK_GPU=1"
) else (
  set "ASK_EMAIL=0"
  set "ASK_WALLET=0"
  set "ASK_GPU=0"
)

if "%EMAIL%"=="" set "ASK_EMAIL=1"
if "%WALLET_ADDRESS%"=="" set "ASK_WALLET=1"
if "%GPU_INDEX%"=="" set "ASK_GPU=1"

if "%ASK_EMAIL%"=="1" (
  echo First time setup:
  echo - Please enter your registered Email address.
  if not "!EMAIL!"=="" (
    echo Current Email: !EMAIL!
  )
  set /p EMAIL=Email: 
  if "!EMAIL!"=="" (
    echo ERROR: Email is required.
    echo.
    pause
    exit /b 1
  )
)

if "%ASK_WALLET%"=="1" (
  echo.
  echo - Please enter your wallet address ^(same as the one bound in the web Settings page^).
  if not "!WALLET_ADDRESS!"=="" (
    echo Current wallet: !WALLET_ADDRESS!
  )
  set /p WALLET_ADDRESS=Wallet Address: 
  if "!WALLET_ADDRESS!"=="" (
    echo ERROR: Wallet Address is required.
    echo.
    pause
    exit /b 1
  )
)

if "%SERVER_URL_DISPLAY%"=="" set "SERVER_URL_DISPLAY=http://38.135.24.37:3000"
if /i not "%DRY_RUN%"=="1" (
  call :verify_wallet_email
  if errorlevel 1 exit /b 1
)

if "%ASK_GPU%"=="1" (
  echo.
  echo GPU selection:
  echo - Enter GPU index ^(default 0^). If you have only one GPU, use 0.
  if not "!GPU_INDEX!"=="" (
    echo Current GPU_INDEX: !GPU_INDEX!
  )
  set /p GPU_INDEX=GPU_INDEX [0]: 
  if "!GPU_INDEX!"=="" set "GPU_INDEX=0"
)

set "NODE_NAME_FROM_CFG=0"
if "!NODE_NAME!"=="" (
  if exist "%CONFIG_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
      if /i "%%A"=="NODE_NAME_GPU!GPU_INDEX!" (
        set "NODE_NAME=%%B"
        set "NODE_NAME_FROM_CFG=1"
      )
    )
  )
  if "!NODE_NAME!"=="" if not "!LEGACY_NODE_NAME!"=="" set "NODE_NAME=!LEGACY_NODE_NAME!"
)

set "_GEN_NAME=0"
if "!NODE_NAME!"=="" set "_GEN_NAME=1"
if /i "!NODE_NAME!"=="rabah-node" set "_GEN_NAME=1"
if "!_GEN_NAME!"=="1" (
  set "CHARS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  set "RAND_SUFFIX="
  for /l %%I in (1,1,5) do (
    set /a "IDX=!RANDOM! %% 36"
    call set "RAND_SUFFIX=%%RAND_SUFFIX%%%%CHARS:~!IDX!,1%%"
  )
  set "CHARS="
  set "IDX="
  set "DEFAULT_NODE_NAME=rabah-node-gpu!GPU_INDEX!-!RAND_SUFFIX!"
  set "RAND_SUFFIX="
  if /i "%DRY_RUN%"=="1" (
    set "NODE_NAME=!DEFAULT_NODE_NAME!"
  ) else (
    if /i "%NO_PAUSE%"=="1" (
      set "NODE_NAME=!DEFAULT_NODE_NAME!"
    ) else (
      if "!NODE_NAME_FROM_CFG!"=="0" (
        echo.
        echo Node naming:
        echo - Suggested node name: !DEFAULT_NODE_NAME!
        echo - Press Enter to accept, or type your own node name to restore/customize.
        set /p NODE_NAME=NODE_NAME [!DEFAULT_NODE_NAME!]: 
        if "!NODE_NAME!"=="" set "NODE_NAME=!DEFAULT_NODE_NAME!"
      ) else (
        set "NODE_NAME=!DEFAULT_NODE_NAME!"
      )
    )
  )
  set "DEFAULT_NODE_NAME="
  set "_GEN_NAME="
)

if /i "%DRY_RUN%"=="1" (
  set "SKIP_SAVE_CONFIG=1"
) else (
  set "SKIP_SAVE_CONFIG=0"
)

if /i "%SKIP_SAVE_CONFIG%"=="0" (
  set "LOCK_DIR=%CONFIG_FILE%.lock"
  call :acquire_lock "!LOCK_DIR!" 5
  if errorlevel 1 (
    echo.
    echo ERROR: Could not acquire config lock: !LOCK_DIR!
    echo Another start may be updating node-config.txt. Try again.
    echo.
    if /i "%NO_PAUSE%"=="1" exit /b 1
    pause
    exit /b 1
  )

  set "TMP_FILE=%CONFIG_FILE%.tmp"
  break > "!TMP_FILE!"

  if exist "%CONFIG_FILE%" (
    for /f "usebackq delims=" %%L in ("%CONFIG_FILE%") do (
      set "KEY="
      set "LINE=%%L"
      for /f "tokens=1,* delims==" %%K in ("%%L") do (
        set "KEY=%%K"
      )
      if /i "!KEY!"=="EMAIL" set "LINE="
      if /i "!KEY!"=="WALLET_ADDRESS" set "LINE="
      if /i "!KEY!"=="MODELS_DIR" set "LINE="
      if /i "!KEY!"=="MODEL_ID" set "LINE="
      if /i "!KEY!"=="GPU_INDEX" set "LINE="
      if /i "!KEY!"=="NODE_NAME" set "LINE="
      if /i "!KEY!"=="NODE_NAME_GPU!GPU_INDEX!" set "LINE="
      if not "!LINE!"=="" >> "!TMP_FILE!" echo(!LINE!
    )
  )

  >> "!TMP_FILE!" echo EMAIL=%EMAIL%
  >> "!TMP_FILE!" echo WALLET_ADDRESS=%WALLET_ADDRESS%
  >> "!TMP_FILE!" echo MODELS_DIR=%MODELS_DIR%
  >> "!TMP_FILE!" echo MODEL_ID=%MODEL_ID%
  >> "!TMP_FILE!" echo GPU_INDEX=%GPU_INDEX%
  >> "!TMP_FILE!" echo NODE_NAME_GPU!GPU_INDEX!=!NODE_NAME!
  move /y "!TMP_FILE!" "%CONFIG_FILE%" >nul

  call :release_lock "!LOCK_DIR!"
  set "LOCK_DIR="
)

if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%"

if "%SERVER_URL_DISPLAY%"=="" set "SERVER_URL_DISPLAY=http://38.135.24.37:3000"

echo.
echo Starting node agent...
echo - SERVER_URL: %SERVER_URL_DISPLAY%
echo - EMAIL: %EMAIL%
echo - WALLET_ADDRESS: %WALLET_ADDRESS%
echo - GPU_INDEX: %GPU_INDEX%
echo - NODE_NAME: %NODE_NAME%
echo - MODEL_ID: %MODEL_ID%
echo.

if /i "%AUTO_UPDATE%"=="1" (
  if /i "%AGENT_IMAGE%"=="rabah-agent:local" (
    where git >nul 2>nul
    if not errorlevel 1 (
      if exist "%~dp0.git" (
        echo Updating agent source via git pull...
        git -C "%~dp0" pull --rebase --autostash
      )
    )
  ) else (
    echo Pulling latest image: %AGENT_IMAGE%
    docker pull "%AGENT_IMAGE%"
  )
)

if /i "%AGENT_IMAGE%"=="rabah-agent:local" (
  docker image inspect rabah-agent:local >nul 2>nul
  if errorlevel 1 (
    echo Building local image: rabah-agent:local
    docker build -t rabah-agent:local "%~dp0"
    if errorlevel 1 (
      echo.
      echo ERROR: Failed to build image rabah-agent:local
      echo.
      pause
      exit /b 1
    )
  )
  if not exist "%~dp0workflows" mkdir "%~dp0workflows"
  set "DOCKER_CMD=docker run --rm --name ""%NODE_NAME%"" --gpus all %ENV_FILE_ARG% -w /workspace -e ""EMAIL=%EMAIL%"" -e ""WALLET_ADDRESS=%WALLET_ADDRESS%"" -e ""GPU_INDEX=%GPU_INDEX%"" -e ""NODE_NAME=%NODE_NAME%"" -e ""MODEL_ID=%MODEL_ID%"" -e ""CUDA_DEVICE_ORDER=PCI_BUS_ID"" -e ""CUDA_VISIBLE_DEVICES=%GPU_INDEX%"" -e ""NVIDIA_VISIBLE_DEVICES=%GPU_INDEX%"" -e ""PYTHONUNBUFFERED=1"" -e ""PYTHONPATH=/workspace:/app"" -e ""COMFYUI_WORKFLOWS_DIR=/workspace/workflows"" -v ""%~dp0.:/workspace"" -v ""%MODELS_DIR%:/app/models"" -v ""%MODELS_DIR%:/app/ComfyUI/models"" rabah-agent:local python -u /workspace/comfy_agent.py"
) else (
  set "DOCKER_CMD=docker run --rm --name ""%NODE_NAME%"" --gpus all %ENV_FILE_ARG% -e ""EMAIL=%EMAIL%"" -e ""WALLET_ADDRESS=%WALLET_ADDRESS%"" -e ""GPU_INDEX=%GPU_INDEX%"" -e ""NODE_NAME=%NODE_NAME%"" -e ""MODEL_ID=%MODEL_ID%"" -e ""CUDA_DEVICE_ORDER=PCI_BUS_ID"" -e ""CUDA_VISIBLE_DEVICES=%GPU_INDEX%"" -e ""NVIDIA_VISIBLE_DEVICES=%GPU_INDEX%"" -e ""PYTHONUNBUFFERED=1"" -v ""%MODELS_DIR%:/app/models"" -v ""%MODELS_DIR%:/app/ComfyUI/models"" %AGENT_IMAGE%"
)

if /i "%DRY_RUN%"=="1" (
  echo DRY_RUN=1
  echo %DOCKER_CMD%
  echo.
  if /i "%NO_PAUSE%"=="1" exit /b 0
  pause
  exit /b 0
)

set "FORCE_RESTART=%FORCE_RESTART%"
if "%FORCE_RESTART%"=="" set "FORCE_RESTART=0"
if /i not "%FORCE_RESTART%"=="1" (
  for /f "usebackq delims=" %%I in (`docker ps -q --filter "name=^%NODE_NAME%$"`) do (
    echo.
    echo ERROR: Node container already running: %NODE_NAME%
    echo Stop it first ^(stop.bat^) or set FORCE_RESTART=1 to restart.
    echo.
    if /i "%NO_PAUSE%"=="1" exit /b 1
    pause
    exit /b 1
  )
)
docker rm "%NODE_NAME%" >nul 2>nul
if /i "%FORCE_RESTART%"=="1" docker rm -f "%NODE_NAME%" >nul 2>nul

%DOCKER_CMD%

set "EXIT_CODE=%errorlevel%"
if not "%EXIT_CODE%"=="0" (
  echo.
  echo Node exited with code %EXIT_CODE%.
  echo If the window closes too fast on double-click, run it from cmd to see logs:
  echo   cd /d "%~dp0"
  echo   start.bat
  echo.
  pause
  exit /b %EXIT_CODE%
)

exit /b 0

:verify_wallet_email
set "VERIFY_SERVER_URL=%SERVER_URL_DISPLAY%"
:verify_wallet_email_loop
echo.
echo Verifying wallet/email with server...
powershell -NoProfile -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$u=($env:VERIFY_SERVER_URL -as [string]); if(-not $u){$u='http://38.135.24.37:3000'};" ^
  "$u=$u.Trim(); $u=$u.TrimEnd('/'); if($u.ToLower().EndsWith('/v1')){$u=$u.Substring(0,$u.Length-3)};" ^
  "$body=@{wallet_address=$env:WALLET_ADDRESS; email=$env:EMAIL} | ConvertTo-Json -Compress;" ^
  "try { Invoke-WebRequest -Uri ($u + '/v1/nodes/verify') -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10 | Out-Null; exit 0 }" ^
  "catch { if($_.ErrorDetails -and $_.ErrorDetails.Message){ Write-Host $_.ErrorDetails.Message } else { Write-Host $_.Exception.Message }; exit 1 }"
if not errorlevel 1 exit /b 0
echo.
echo ERROR: Wallet and email do not match any registered user.
if /i "%NO_PAUSE%"=="1" exit /b 1
echo Please re-enter Email and Wallet Address.
set /p EMAIL=Email: 
if "!EMAIL!"=="" exit /b 1
set /p WALLET_ADDRESS=Wallet Address: 
if "!WALLET_ADDRESS!"=="" exit /b 1
goto verify_wallet_email_loop

:acquire_lock
set "LOCK_PATH=%~1"
set "LOCK_TRIES=%~2"
if "%LOCK_TRIES%"=="" set "LOCK_TRIES=5"
for /l %%I in (1,1,%LOCK_TRIES%) do (
  2>nul mkdir "%LOCK_PATH%" && exit /b 0
  timeout /t 1 /nobreak >nul
)
echo Note: Removing stale config lock: %LOCK_PATH%
rmdir "%LOCK_PATH%" >nul 2>nul
2>nul mkdir "%LOCK_PATH%" && exit /b 0
exit /b 1

:prompt_node_selection
set "CHOICE="
set "SELECTED_GPU="
set "SELECTED_NODE="
set /p CHOICE=Select: 
if "!CHOICE!"=="" goto prompt_node_selection
if /i "!CHOICE!"=="Q" exit /b 0
if /i "!CHOICE!"=="A" exit /b 0
for /l %%I in (1,1,%CFG_COUNT%) do (
  if "!CHOICE!"=="%%I" (
    call set "SELECTED_GPU=%%CFG_GPU_%%I%%"
    call set "SELECTED_NODE=%%CFG_NODE_%%I%%"
  )
)
if "!SELECTED_GPU!"=="" (
  echo.
  echo ERROR: Invalid selection.
  echo.
  goto prompt_node_selection
)
exit /b 0

:start_all_nodes
for /l %%J in (2,1,%CFG_COUNT%) do (
  call set "S_GPU=%%CFG_GPU_%%J%%"
  call set "S_NODE=%%CFG_NODE_%%J%%"
  if not "!S_GPU!"=="" if not "!S_NODE!"=="" (
    start "Rabah Node GPU!S_GPU!" cmd /v:on /k "cd /d ^"%~dp0^" ^&^& set ^"GPU_INDEX=!S_GPU!^" ^&^& set ^"NODE_NAME=!S_NODE!^" ^&^& call ^"%~f0^""
  )
)
set "S_GPU="
set "S_NODE="
exit /b 0

:release_lock
set "LOCK_PATH=%~1"
if not "%LOCK_PATH%"=="" rmdir "%LOCK_PATH%" >nul 2>nul
exit /b 0
