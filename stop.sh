#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CONFIG_FILE="${SCRIPT_DIR}/node-config.txt"

NODE_NAME="${NODE_NAME:-}"
GPU_INDEX="${GPU_INDEX:-}"
STOP_ALL="${STOP_ALL:-0}"
NO_PAUSE="${NO_PAUSE:-}"
LEGACY_NODE_NAME="${LEGACY_NODE_NAME:-}"
NODE_NAME_FROM_ENV="0"
GPU_INDEX_FROM_ENV="0"
if [[ -n "${NODE_NAME}" ]]; then
  NODE_NAME_FROM_ENV="1"
fi
if [[ -n "${GPU_INDEX}" ]]; then
  GPU_INDEX_FROM_ENV="1"
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  while IFS='=' read -r k v; do
    [[ -z "${k}" ]] && continue
    case "${k}" in
      GPU_INDEX) [[ -z "${GPU_INDEX}" ]] && GPU_INDEX="${v}" ;;
      NODE_NAME) [[ -z "${LEGACY_NODE_NAME}" ]] && LEGACY_NODE_NAME="${v}" ;;
    esac
  done < "${CONFIG_FILE}"
fi

if [[ -z "${NODE_NAME}" ]]; then
  if [[ -f "${CONFIG_FILE}" && -n "${GPU_INDEX}" ]]; then
    while IFS='=' read -r k v; do
      [[ -z "${k}" ]] && continue
      if [[ "${k}" == "NODE_NAME_GPU${GPU_INDEX}" ]]; then
        NODE_NAME="${v}"
        break
      fi
    done < "${CONFIG_FILE}"
  fi
  if [[ -z "${NODE_NAME}" && -n "${LEGACY_NODE_NAME}" ]]; then
    NODE_NAME="${LEGACY_NODE_NAME}"
  fi
fi

if [[ -z "${NODE_NAME}" ]]; then
  if [[ -z "${GPU_INDEX}" ]]; then
    GPU_INDEX="0"
  fi
  NODE_NAME="rabah-node-gpu${GPU_INDEX}"
fi

docker --version >/dev/null 2>&1 || {
  echo "ERROR: Docker not found in PATH." >&2
  exit 1
}

docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker is not running." >&2
  exit 1
}

stop_one() {
  local target="$1"
  [[ -z "${target}" ]] && return 0
  echo "- stopping ${target}"
  docker rm -f "${target}" >/dev/null 2>&1 || true
}

stop_all_running() {
  echo "Stopping all running node containers with name prefix: rabah-node"
  for name in "${CONTAINERS[@]}"; do
    stop_one "${name}"
  done
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
  SELECTED_NAMES=()
  local seen=","
  local token selected_index
  for part in "${CHOICE_PARTS[@]}"; do
    token="${part//[[:space:]]/}"
    [[ -z "${token}" ]] && continue
    if ! [[ "${token}" =~ ^[0-9]+$ ]]; then
      return 1
    fi
    selected_index="$((token - 1))"
    if (( selected_index < 0 || selected_index >= max )); then
      return 1
    fi
    if [[ "${seen}" == *",${token},"* ]]; then
      continue
    fi
    seen="${seen}${token},"
    SELECTED_NAMES+=("${CONTAINERS[$selected_index]}")
  done
  [[ "${#SELECTED_NAMES[@]}" -gt 0 ]]
}

mapfile -t CONTAINERS < <(docker ps --format "{{.Names}}" | grep -i -E '^rabah-node' || true)
COUNT="${#CONTAINERS[@]}"

if [[ "${STOP_ALL}" == "1" ]]; then
  if [[ "${COUNT}" == "0" ]]; then
    echo "No running node containers found by name prefix: rabah-node"
    exit 0
  fi
  stop_all_running
  echo "Done."
  exit 0
fi

if [[ "${STOP_ALL}" != "1" && ( "${NODE_NAME_FROM_ENV}" == "1" || "${GPU_INDEX_FROM_ENV}" == "1" ) && -n "${NODE_NAME}" && "${COUNT}" != "0" ]]; then
  for name in "${CONTAINERS[@]}"; do
    if [[ "${name}" == "${NODE_NAME}" ]]; then
      echo "Stopping node container: ${NODE_NAME}"
      stop_one "${NODE_NAME}"
      echo "Done."
      exit 0
    fi
  done
fi

if [[ "${NO_PAUSE}" == "1" && "${STOP_ALL}" != "1" && -n "${NODE_NAME}" ]]; then
  echo "Stopping node container: ${NODE_NAME}"
  stop_one "${NODE_NAME}"
  echo "Done."
  exit 0
fi

if [[ "${COUNT}" == "0" ]]; then
  echo "No running node containers found by name prefix: rabah-node"
  echo "Attempting to stop configured node: ${NODE_NAME}"
  stop_one "${NODE_NAME}"
  echo "Done."
  exit 0
fi

if [[ "${COUNT}" == "1" ]]; then
  echo "Stopping node container: ${CONTAINERS[0]}"
  stop_one "${CONTAINERS[0]}"
  echo "Done."
  exit 0
fi

echo "Found ${COUNT} node containers:"
for i in "${!CONTAINERS[@]}"; do
  idx="$((i + 1))"
  echo "  [${idx}] ${CONTAINERS[$i]}"
done
echo "  [A] Stop all"
echo "  [Q] Quit"
echo "  [2,3] Stop multiple by index"
read -r -p "Select [1]: " CHOICE

if [[ -z "${CHOICE}" ]]; then
  CHOICE="1"
fi

if [[ "${CHOICE,,}" == "q" ]]; then
  exit 0
fi

if [[ "${CHOICE,,}" == "a" ]]; then
  stop_all_running
  echo "Done."
  exit 0
fi

if ! parse_selection_indexes "${CHOICE}" "${COUNT}"; then
  echo "ERROR: Invalid selection." >&2
  exit 1
fi

for name in "${SELECTED_NAMES[@]}"; do
  echo "Stopping node container: ${name}"
  stop_one "${name}"
done
echo "Done."
exit 0
