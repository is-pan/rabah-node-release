#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CONFIG_FILE="${SCRIPT_DIR}/node-config.txt"

NODE_NAME="${NODE_NAME:-}"
GPU_INDEX="${GPU_INDEX:-}"
EMAIL="${EMAIL:-}"
WALLET_ADDRESS="${WALLET_ADDRESS:-}"
MODELS_DIR="${MODELS_DIR:-}"
MODEL_ID="${MODEL_ID:-}"
AGENT_IMAGE="${AGENT_IMAGE:-}"
AUTO_UPDATE="${AUTO_UPDATE:-}"
RESET_CONFIG="${RESET_CONFIG:-}"
ASK_ON_START="${ASK_ON_START:-}"
DRY_RUN="${DRY_RUN:-}"
NO_PAUSE="${NO_PAUSE:-}"
ALLOW_ENV_FILE="${ALLOW_ENV_FILE:-0}"
ALLOW_ADVANCED_CONFIG="${ALLOW_ADVANCED_CONFIG:-0}"

GPU_INDEX_FROM_ENV="0"
if [[ -n "${GPU_INDEX}" ]]; then
  GPU_INDEX_FROM_ENV="1"
fi

NODE_NAME_FROM_ENV="0"
if [[ -n "${NODE_NAME}" ]]; then
  NODE_NAME_FROM_ENV="1"
fi

ENV_FILE_FOUND="0"
SERVER_URL_DISPLAY=""
if [[ "${ALLOW_ENV_FILE}" == "1" && -f "${SCRIPT_DIR}/.env" ]]; then
  ENV_FILE_FOUND="1"
  while IFS='=' read -r k v; do
    [[ -z "${k}" ]] && continue
    case "${k}" in
      SERVER_URL) [[ -z "${SERVER_URL_DISPLAY}" ]] && SERVER_URL_DISPLAY="${v}" ;;
      AUTO_UPDATE) [[ -z "${AUTO_UPDATE}" ]] && AUTO_UPDATE="${v}" ;;
      AGENT_IMAGE) [[ -z "${AGENT_IMAGE}" ]] && AGENT_IMAGE="${v}" ;;
      MODELS_DIR) [[ -z "${MODELS_DIR}" ]] && MODELS_DIR="${v}" ;;
      MODEL_ID) [[ -z "${MODEL_ID}" ]] && MODEL_ID="${v}" ;;
    esac
  done < "${SCRIPT_DIR}/.env"
fi

if [[ "${RESET_CONFIG}" == "1" ]]; then
  rm -f "${CONFIG_FILE}" >/dev/null 2>&1 || true
  NODE_NAME=""
fi

SELECT_NODE_ON_START=""
CFG_GPU_LIST=()
CFG_NODE_LIST=()

if [[ -f "${CONFIG_FILE}" ]]; then
  while IFS='=' read -r k v; do
    [[ -z "${k}" ]] && continue
    case "${k}" in
      EMAIL) [[ -z "${EMAIL}" ]] && EMAIL="${v}" ;;
      WALLET_ADDRESS) [[ -z "${WALLET_ADDRESS}" ]] && WALLET_ADDRESS="${v}" ;;
      GPU_INDEX) [[ -z "${GPU_INDEX}" ]] && GPU_INDEX="${v}" ;;
      MODELS_DIR) [[ -z "${MODELS_DIR}" ]] && MODELS_DIR="${v}" ;;
      MODEL_ID) [[ -z "${MODEL_ID}" ]] && MODEL_ID="${v}" ;;
      NODE_NAME) [[ -z "${LEGACY_NODE_NAME:-}" ]] && LEGACY_NODE_NAME="${v}" ;;
      SELECT_NODE_ON_START) [[ -z "${SELECT_NODE_ON_START}" ]] && SELECT_NODE_ON_START="${v}" ;;
      NODE_NAME_GPU*) CFG_GPU_LIST+=("${k#NODE_NAME_GPU}"); CFG_NODE_LIST+=("${v}") ;;
    esac
  done < "${CONFIG_FILE}"
fi

if [[ -z "${SELECT_NODE_ON_START}" ]]; then
  SELECT_NODE_ON_START="1"
fi
case "${SELECT_NODE_ON_START,,}" in
  0|false|no|off) SELECT_NODE_ON_START="0" ;;
  *) SELECT_NODE_ON_START="1" ;;
esac

if [[ "${ALLOW_ADVANCED_CONFIG}" != "1" ]]; then
  AUTO_UPDATE=""
  AGENT_IMAGE=""
fi

if [[ -z "${AUTO_UPDATE}" ]]; then
  AUTO_UPDATE="1"
fi
if [[ -z "${AGENT_IMAGE}" ]]; then
  AGENT_IMAGE="ghcr.io/is-pan/rabah-node:latest"
fi
if [[ -z "${MODELS_DIR}" ]]; then
  MODELS_DIR="${SCRIPT_DIR}/models"
fi
if [[ "${MODELS_DIR}" != /* ]]; then
  MODELS_DIR="${SCRIPT_DIR}/${MODELS_DIR}"
fi
if [[ -z "${MODEL_ID}" ]]; then
  MODEL_ID="flux-2-klein-9b-fp8"
fi

docker --version >/dev/null 2>&1 || {
  echo "ERROR: Docker not found in PATH." >&2
  exit 1
}

docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker is not running." >&2
  exit 1
}

launch_node_instance() {
  local gpu="$1"
  local node="$2"
  [[ -z "${gpu}" || -z "${node}" ]] && return 0
  echo "Opening new terminal for Node ${node} (GPU ${gpu})..."
  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -c "cd \"${SCRIPT_DIR}\" && GPU_INDEX=\"${gpu}\" NODE_NAME=\"${node}\" bash \"${SCRIPT_DIR}/start.sh\"; exec bash"
  elif command -v konsole >/dev/null 2>&1; then
    konsole -e bash -c "cd \"${SCRIPT_DIR}\" && GPU_INDEX=\"${gpu}\" NODE_NAME=\"${node}\" bash \"${SCRIPT_DIR}/start.sh\"; exec bash" &
  elif command -v xterm >/dev/null 2>&1; then
    xterm -e bash -c "cd \"${SCRIPT_DIR}\" && GPU_INDEX=\"${gpu}\" NODE_NAME=\"${node}\" bash \"${SCRIPT_DIR}/start.sh\"; exec bash" &
  elif command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -c "cd \"${SCRIPT_DIR}\" && GPU_INDEX=\"${gpu}\" NODE_NAME=\"${node}\" bash \"${SCRIPT_DIR}/start.sh\"; exec bash" &
  else
    echo "Warning: No supported GUI terminal found (gnome-terminal, konsole, xterm). Defaulting to background execution."
    GPU_INDEX="${gpu}" NODE_NAME="${node}" NO_PAUSE=1 nohup "${SCRIPT_DIR}/start.sh" > "${SCRIPT_DIR}/${node}.log" 2>&1 &
  fi
}

parse_selection_indexes() {
  local choice="$1"
  local max="$2"
  local normalized
  normalized="$(printf '%s' "${choice}" | tr -c '0-9' ',')"
  while [[ "${normalized}" == ,* ]]; do
    normalized="${normalized#,}"
  done
  while [[ "${normalized}" == *, ]]; do
    normalized="${normalized%,}"
  done
  while [[ "${normalized}" == *",,"* ]]; do
    normalized="${normalized//,,/,}"
  done
  IFS=',' read -r -a CHOICE_PARTS <<< "${normalized}"
  SELECTED_INDEXES=()
  local seen=","
  local token
  for part in "${CHOICE_PARTS[@]}"; do
    token="${part//[[:space:]]/}"
    [[ -z "${token}" ]] && continue
    if ! [[ "${token}" =~ ^[0-9]+$ ]] || [[ "${token}" -lt 1 ]] || [[ "${token}" -gt "${max}" ]]; then
      return 1
    fi
    if [[ "${seen}" == *",${token},"* ]]; then
      continue
    fi
    SELECTED_INDEXES+=("${token}")
    seen="${seen}${token},"
  done
  [[ "${#SELECTED_INDEXES[@]}" -gt 0 ]]
}

if [[ "${NODE_NAME_FROM_ENV}" == "0" && "${GPU_INDEX_FROM_ENV}" == "0" && "${SELECT_NODE_ON_START}" == "1" && "${#CFG_GPU_LIST[@]}" -gt 0 ]]; then
  if [[ "${#CFG_GPU_LIST[@]}" -eq 1 ]]; then
    GPU_INDEX="${CFG_GPU_LIST[0]}"
    NODE_NAME="${CFG_NODE_LIST[0]}"
  else
    if [[ "${NO_PAUSE}" == "1" || "${DRY_RUN}" == "1" ]]; then
      sel="0"
      if [[ -n "${GPU_INDEX}" ]]; then
        for i in "${!CFG_GPU_LIST[@]}"; do
          if [[ "${CFG_GPU_LIST[$i]}" == "${GPU_INDEX}" ]]; then
            sel="${i}"
            break
          fi
        done
      fi
      GPU_INDEX="${CFG_GPU_LIST[$sel]}"
      NODE_NAME="${CFG_NODE_LIST[$sel]}"
    else
      echo
      echo "Node selection:"
      echo "- Found ${#CFG_GPU_LIST[@]} saved nodes in node-config.txt"
      for i in "${!CFG_GPU_LIST[@]}"; do
        idx="$((i + 1))"
      echo "  [${idx}] GPU ${CFG_GPU_LIST[$i]} - ${CFG_NODE_LIST[$i]}"
      done
      echo "  [A] Start all (background)"
      echo "  [Q] Quit"
      echo "  [2,3] Start multiple by index"
      echo
      read -r -p "Select [1]: " CHOICE
      CHOICE="${CHOICE:-1}"
      if [[ "${CHOICE,,}" == "q" ]]; then
        exit 0
      elif [[ "${CHOICE,,}" == "a" ]]; then
        for i in "${!CFG_GPU_LIST[@]}"; do
          if [[ $i -eq 0 ]]; then continue; fi
          S_GPU="${CFG_GPU_LIST[$i]}"
          S_NODE="${CFG_NODE_LIST[$i]}"
          launch_node_instance "${S_GPU}" "${S_NODE}"
        done
        GPU_INDEX="${CFG_GPU_LIST[0]}"
        NODE_NAME="${CFG_NODE_LIST[0]}"
      else
        if ! parse_selection_indexes "${CHOICE}" "${#CFG_GPU_LIST[@]}"; then
          echo
          echo "ERROR: Invalid selection." >&2
          exit 1
        fi
        sel="$((SELECTED_INDEXES[0] - 1))"
        GPU_INDEX="${CFG_GPU_LIST[$sel]}"
        NODE_NAME="${CFG_NODE_LIST[$sel]}"
        if [[ "${#SELECTED_INDEXES[@]}" -gt 1 ]]; then
          for ((k=1; k<${#SELECTED_INDEXES[@]}; k++)); do
            idx="$((SELECTED_INDEXES[$k] - 1))"
            S_GPU="${CFG_GPU_LIST[$idx]}"
            S_NODE="${CFG_NODE_LIST[$idx]}"
            launch_node_instance "${S_GPU}" "${S_NODE}"
          done
        fi
      fi
    fi
  fi
fi

ASK_EMAIL="0"
ASK_WALLET="0"
ASK_GPU="0"
if [[ "${ASK_ON_START}" == "1" ]]; then
  ASK_EMAIL="1"
  ASK_WALLET="1"
  ASK_GPU="1"
fi
if [[ -z "${EMAIL}" ]]; then
  ASK_EMAIL="1"
fi
if [[ -z "${WALLET_ADDRESS}" ]]; then
  ASK_WALLET="1"
fi
if [[ -z "${GPU_INDEX}" ]]; then
  ASK_GPU="1"
fi

if [[ "${ASK_EMAIL}" == "1" ]]; then
  echo "First time setup:"
  echo "- Please enter your registered Email address."
  if [[ -n "${EMAIL}" ]]; then
    echo "Current Email: ${EMAIL}"
  fi
  read -r -p "Email: " EMAIL_INPUT
  EMAIL="${EMAIL_INPUT:-${EMAIL}}"
  if [[ -z "${EMAIL}" ]]; then
    echo "ERROR: Email is required." >&2
    exit 1
  fi
fi

if [[ "${ASK_WALLET}" == "1" ]]; then
  echo
  echo "- Please enter your wallet address (same as the one bound in the web Settings page)."
  if [[ -n "${WALLET_ADDRESS}" ]]; then
    echo "Current wallet: ${WALLET_ADDRESS}"
  fi
  read -r -p "Wallet Address: " WALLET_ADDRESS
  if [[ -z "${WALLET_ADDRESS}" ]]; then
    echo "ERROR: Wallet Address is required." >&2
    exit 1
  fi
fi

if [[ -z "${SERVER_URL_DISPLAY}" ]]; then
  SERVER_URL_DISPLAY="http://38.135.24.37:3000"
fi

normalize_server_base_url() {
  local u="${1:-}"
  u="${u%%$'\r'}"
  u="${u%/}"
  local lower="${u,,}"
  if [[ "${lower}" == */v1 ]]; then
    u="${u%/v1}"
  fi
  echo "${u}"
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

verify_wallet_email_once() {
  local base
  base="$(normalize_server_base_url "${SERVER_URL_DISPLAY}")"
  local url="${base}/v1/nodes/verify"
  local payload
  payload="$(printf '{"wallet_address":"%s","email":"%s"}' "$(json_escape "${WALLET_ADDRESS}")" "$(json_escape "${EMAIL}")")"

  if command -v curl >/dev/null 2>&1; then
    local resp body code
    resp="$(curl -sS -m 10 -H 'content-type: application/json' -d "${payload}" -w $'\n%{http_code}' "${url}" 2>/dev/null || true)"
    body="${resp%$'\n'*}"
    code="${resp##*$'\n'}"
    if [[ "${code}" == "200" ]]; then
      return 0
    fi
    echo "Verification failed (${code}): ${body}" >&2
    return 1
  fi

  if command -v wget >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp 2>/dev/null || echo '')"
    if [[ -z "${tmp}" ]]; then
      echo "ERROR: Could not create temp file for verification." >&2
      return 1
    fi
    if wget -qO "${tmp}" --content-on-error --timeout=10 --method=POST --header='Content-Type: application/json' --body-data="${payload}" "${url}" >/dev/null 2>&1; then
      rm -f "${tmp}" >/dev/null 2>&1 || true
      return 0
    fi
    echo "Verification failed: $(cat "${tmp}" 2>/dev/null || true)" >&2
    rm -f "${tmp}" >/dev/null 2>&1 || true
    return 1
  fi

  echo "ERROR: Need curl or wget to verify wallet/email before startup." >&2
  return 1
}

if [[ "${DRY_RUN}" != "1" ]]; then
  echo
  echo "Verifying wallet/email with server..."
  while true; do
    if verify_wallet_email_once; then
      break
    fi
    if [[ "${NO_PAUSE}" == "1" ]]; then
      exit 1
    fi
    echo
    echo "Please re-enter Email and Wallet Address."
    read -r -p "Email: " EMAIL_RETRY
    EMAIL="${EMAIL_RETRY:-${EMAIL}}"
    read -r -p "Wallet Address: " WALLET_RETRY
    WALLET_ADDRESS="${WALLET_RETRY:-${WALLET_ADDRESS}}"
    if [[ -z "${EMAIL}" || -z "${WALLET_ADDRESS}" ]]; then
      echo "ERROR: Email and Wallet Address are required." >&2
      exit 1
    fi
  done
fi

if [[ "${ASK_GPU}" == "1" ]]; then
  echo
  echo "GPU selection:"
  echo "- Enter GPU index (default 0). If you have only one GPU, use 0."
  if [[ -n "${GPU_INDEX}" ]]; then
    echo "Current GPU_INDEX: ${GPU_INDEX}"
  fi
  read -r -p "GPU_INDEX [0]: " GPU_INDEX_INPUT
  GPU_INDEX="${GPU_INDEX_INPUT:-0}"
fi

if [[ -z "${GPU_INDEX}" ]]; then
  GPU_INDEX="0"
fi

if [[ -z "${NODE_NAME}" || "${NODE_NAME}" == "rabah-node" ]]; then
  FOUND_NODE_NAME_FROM_CFG="0"
  if [[ -z "${NODE_NAME}" ]]; then
    if [[ -f "${CONFIG_FILE}" ]]; then
      while IFS='=' read -r k v; do
        [[ -z "${k}" ]] && continue
        if [[ "${k}" == "NODE_NAME_GPU${GPU_INDEX}" ]]; then
          NODE_NAME="${v}"
          FOUND_NODE_NAME_FROM_CFG="1"
          break
        fi
      done < "${CONFIG_FILE}"
    fi
    if [[ -z "${NODE_NAME}" && -n "${LEGACY_NODE_NAME:-}" ]]; then
      NODE_NAME="${LEGACY_NODE_NAME}"
    fi
  fi

  if [[ -z "${NODE_NAME}" || "${NODE_NAME}" == "rabah-node" ]]; then
    RAND_SUFFIX="$(tr -dc '0-9A-Z' </dev/urandom 2>/dev/null | head -c 5 || true)"
    if [[ -z "${RAND_SUFFIX}" ]]; then
      RAND_SUFFIX="$(printf '%05d' "$((RANDOM % 100000))")"
    fi
    DEFAULT_NODE_NAME="rabah-node-gpu${GPU_INDEX}-${RAND_SUFFIX}"
    RAND_SUFFIX=""
    if [[ "${DRY_RUN}" != "1" && "${NO_PAUSE}" != "1" && "${NODE_NAME_FROM_ENV}" != "1" && "${FOUND_NODE_NAME_FROM_CFG}" == "0" ]]; then
      echo
      echo "Node naming:"
      echo "- Suggested node name: ${DEFAULT_NODE_NAME}"
      echo "- Press Enter to accept, or type your own node name to restore/customize."
      NODE_NAME_INPUT=""
      read -r -p "NODE_NAME [${DEFAULT_NODE_NAME}]: " NODE_NAME_INPUT
      NODE_NAME="${NODE_NAME_INPUT:-${DEFAULT_NODE_NAME}}"
    else
      NODE_NAME="${DEFAULT_NODE_NAME}"
    fi
    DEFAULT_NODE_NAME=""
  fi
fi

if [[ -z "${WALLET_ADDRESS}" ]]; then
  echo "ERROR: WALLET_ADDRESS is required." >&2
  echo "Usage: WALLET_ADDRESS=0x... ./start.sh" >&2
  exit 1
fi

if [[ "${DRY_RUN}" != "1" ]]; then
  LOCK_DIR="${CONFIG_FILE}.lock"
  LOCK_ACQUIRED="0"
  for i in $(seq 1 5); do
    if mkdir "${LOCK_DIR}" >/dev/null 2>&1; then
      LOCK_ACQUIRED="1"
      break
    fi
    sleep 1
  done
  if [[ "${LOCK_ACQUIRED}" != "1" ]]; then
    echo "Note: Removing stale config lock: ${LOCK_DIR}"
    rmdir "${LOCK_DIR}" >/dev/null 2>&1 || true
    if mkdir "${LOCK_DIR}" >/dev/null 2>&1; then
      LOCK_ACQUIRED="1"
    fi
  fi
  if [[ "${LOCK_ACQUIRED}" != "1" ]]; then
    echo "ERROR: Could not acquire config lock: ${LOCK_DIR}" >&2
    echo "Another start may be updating node-config.txt. Try again." >&2
    exit 1
  fi
  trap 'rmdir "${LOCK_DIR}" >/dev/null 2>&1 || true' EXIT

  TMP_FILE="${CONFIG_FILE}.tmp"
  : > "${TMP_FILE}"

  if [[ -f "${CONFIG_FILE}" ]]; then
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      k="${line%%=*}"
      if [[ "${k}" == "EMAIL" || "${k}" == "WALLET_ADDRESS" || "${k}" == "MODELS_DIR" || "${k}" == "MODEL_ID" || "${k}" == "GPU_INDEX" || "${k}" == "NODE_NAME" || "${k}" == "NODE_NAME_GPU${GPU_INDEX}" ]]; then
        continue
      fi
      printf '%s\n' "${line}" >> "${TMP_FILE}"
    done < "${CONFIG_FILE}"
  fi

  printf '%s\n' "EMAIL=${EMAIL}" >> "${TMP_FILE}"
  printf '%s\n' "WALLET_ADDRESS=${WALLET_ADDRESS}" >> "${TMP_FILE}"
  printf '%s\n' "MODELS_DIR=${MODELS_DIR}" >> "${TMP_FILE}"
  printf '%s\n' "MODEL_ID=${MODEL_ID}" >> "${TMP_FILE}"
  printf '%s\n' "GPU_INDEX=${GPU_INDEX}" >> "${TMP_FILE}"
  printf '%s\n' "NODE_NAME_GPU${GPU_INDEX}=${NODE_NAME}" >> "${TMP_FILE}"

  mv -f "${TMP_FILE}" "${CONFIG_FILE}"
  rmdir "${LOCK_DIR}" >/dev/null 2>&1 || true
  trap - EXIT
fi

mkdir -p "${MODELS_DIR}"
if [[ "${AGENT_IMAGE,,}" == "rabah-agent:local" ]]; then
  mkdir -p workflows
fi

echo
echo "Starting node agent..."
if [[ -z "${SERVER_URL_DISPLAY}" ]]; then
  SERVER_URL_DISPLAY="http://38.135.24.37:3000"
fi
echo "- SERVER_URL: ${SERVER_URL_DISPLAY}"
echo "- EMAIL: ${EMAIL}"
echo "- WALLET_ADDRESS: ${WALLET_ADDRESS}"
echo "- GPU_INDEX: ${GPU_INDEX}"
echo "- NODE_NAME: ${NODE_NAME}"
echo "- MODEL_ID: ${MODEL_ID}"
echo

AGENT_IMAGE_LC="${AGENT_IMAGE,,}"
if [[ "${AUTO_UPDATE}" == "1" ]]; then
  if [[ "${AGENT_IMAGE_LC}" == "rabah-agent:local" ]]; then
    if command -v git >/dev/null 2>&1; then
      if [[ -d "${SCRIPT_DIR}/.git" ]]; then
        echo "Updating agent source via git pull..."
        git -C "${SCRIPT_DIR}" pull --rebase --autostash || true
      fi
    fi
  else
    echo "Pulling latest image: ${AGENT_IMAGE}"
    docker pull "${AGENT_IMAGE}"
  fi
fi

FORCE_RESTART="${FORCE_RESTART:-0}"
if [[ "${FORCE_RESTART}" != "1" ]]; then
  RUNNING_ID="$(docker ps -q --filter "name=^${NODE_NAME}$" 2>/dev/null || true)"
  if [[ -n "${RUNNING_ID}" ]]; then
    echo
    echo "ERROR: Node container already running: ${NODE_NAME}" >&2
    echo "Stop it first (./stop.sh) or set FORCE_RESTART=1 to restart." >&2
    exit 1
  fi
fi
docker rm "${NODE_NAME}" >/dev/null 2>&1 || true
if [[ "${FORCE_RESTART}" == "1" ]]; then
  docker rm -f "${NODE_NAME}" >/dev/null 2>&1 || true
fi

ENV_FILE_ARG=()
if [[ "${ALLOW_ENV_FILE}" == "1" && -f "${SCRIPT_DIR}/.env" ]]; then
  ENV_FILE_ARG=(--env-file "${SCRIPT_DIR}/.env")
fi

DOCKER_CMD=()
if [[ "${AGENT_IMAGE_LC}" == "rabah-agent:local" ]]; then
  if ! docker image inspect rabah-agent:local >/dev/null 2>&1; then
    echo "Building local image: rabah-agent:local"
    if ! docker build -t rabah-agent:local "${SCRIPT_DIR}"; then
      echo
      echo "ERROR: Failed to build image rabah-agent:local" >&2
      exit 1
    fi
  fi
  DOCKER_CMD=(docker run --rm --name "${NODE_NAME}" --gpus all "${ENV_FILE_ARG[@]}" -w /workspace \
    -e "EMAIL=${EMAIL}" -e "WALLET_ADDRESS=${WALLET_ADDRESS}" -e "GPU_INDEX=${GPU_INDEX}" -e "NODE_NAME=${NODE_NAME}" -e "MODEL_ID=${MODEL_ID}" \
    -e "CUDA_DEVICE_ORDER=PCI_BUS_ID" -e "CUDA_VISIBLE_DEVICES=${GPU_INDEX}" -e "NVIDIA_VISIBLE_DEVICES=${GPU_INDEX}" \
    -e "PYTHONUNBUFFERED=1" -e "PYTHONPATH=/workspace:/app" \
    -e "COMFYUI_WORKFLOWS_DIR=/workspace/workflows" \
    -v "${SCRIPT_DIR}:/workspace" \
    -v "${MODELS_DIR}:/app/models" \
    -v "${MODELS_DIR}:/app/ComfyUI/models" \
    rabah-agent:local python -u /workspace/comfy_agent.py)
else
  DOCKER_CMD=(docker run --rm --name "${NODE_NAME}" --gpus all "${ENV_FILE_ARG[@]}" \
    -e "EMAIL=${EMAIL}" -e "WALLET_ADDRESS=${WALLET_ADDRESS}" -e "GPU_INDEX=${GPU_INDEX}" -e "NODE_NAME=${NODE_NAME}" -e "MODEL_ID=${MODEL_ID}" \
    -e "CUDA_DEVICE_ORDER=PCI_BUS_ID" -e "CUDA_VISIBLE_DEVICES=${GPU_INDEX}" -e "NVIDIA_VISIBLE_DEVICES=${GPU_INDEX}" \
    -e "PYTHONUNBUFFERED=1" \
    -v "${MODELS_DIR}:/app/models" \
    -v "${MODELS_DIR}:/app/ComfyUI/models" \
    "${AGENT_IMAGE}")
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "DRY_RUN=1"
  printf '%q ' "${DOCKER_CMD[@]}"
  echo
  exit 0
fi

set +e
"${DOCKER_CMD[@]}"
EXIT_CODE="$?"
set -e

if [[ "${EXIT_CODE}" != "0" ]]; then
  echo
  echo "Node exited with code ${EXIT_CODE}."
  echo "If the window closes too fast, run it from terminal to see logs:"
  echo "  cd \"${SCRIPT_DIR}\""
  echo "  ./start.sh"
  echo
  exit "${EXIT_CODE}"
fi
