# Node Operator Guide (Windows / Linux)

This document is for "Node Operators". Objective: Start the node immediately after downloading and extracting.

- Windows: Double-click `start.bat`
- Linux: Run `./start.sh`

## 1. Prerequisites

You must have:

- NVIDIA GPU drivers installed (properly recognizing your GPU)
- Docker installed and running
  - Windows: Docker Desktop (with Linux containers mode)
  - Linux: Docker Engine + NVIDIA Container Toolkit (to expose GPUs to the containers)

## 2. Directory Structure (After Extraction)

It should at least contain:

- `start.bat`
- `stop.bat`
- `start.sh`
- `stop.sh`

The following will be automatically created during runtime:

- `node-config.txt` (Saves EMAIL, WALLET_ADDRESS, GPU_INDEX, MODELS_DIR, MODEL_ID, and NODE_NAME_GPU0/NODE_NAME_GPU1/... for each GPU)
- `models/` (Default model cache directory. The first launch might take a while to download. Can be customized via MODELS_DIR)

## 3. Administrator Configurations (No effort required from node operators)

Server address, image version, and auto-updates are pre-configured by administrators. Node operators just need to run the script and follow the prompts to input:

- `Email` (The email address you used to register on the web console)
- `WALLET_ADDRESS` (Your bound wallet address)
- Select the GPU/Node to run (if nodes for multiple GPUs are already saved, a selection menu will appear)
- If it's the first time starting this GPU: confirm the `NODE_NAME`

## 3.1 Custom Model Directory (MODELS_DIR)

By default, models are downloaded/cached in the `models/` directory next to the scripts.

You can modify the model directory by setting `MODELS_DIR` in `node-config.txt`:

- Relative Path: Relative to the script directory (Recommended: `MODELS_DIR=models`)
- Absolute Path: e.g., `D:\rabah-models` or `/data/rabah-models`

Resolution Priority:

- Windows: Environment Variables → `node-config.txt` → Default (`models/` in script directory)
- Linux: Environment Variables → `node-config.txt` → Default (`models/` in script directory)

## 3.2 Selecting Models (MODEL_ID)

By default, the script writes `MODEL_ID=flux-2-klein-9b-fp8` to `node-config.txt`, so the node will only fetch tasks for this model.

To switch/add models, edit `MODEL_ID` in `node-config.txt`:

- Single Model: `MODEL_ID=flux-2-klein-9b-fp8`
- Multiple Models: Comma-separated: `MODEL_ID=flux-2-klein-9b-fp8,other-model-id`

Note:

- Nodes will only fetch tasks for the models listed in `MODEL_ID`; if you remove a model from `MODEL_ID`, it will stop fetching tasks for it.
- Model files are not automatically deleted. You must clean your disk manually if needed.

## 4. First Start (Double Click start.bat)

When you double-click `start.bat` for the first time, you will usually be prompted to:

- Enter `Email` (Used for web console registration)
- Enter `Wallet Address` (Must match the one bound on the web console)
- Select or input `GPU_INDEX` (GPU ID)
  - If you only have one GPU, enter `0`
  - For multiple GPUs, choose accordingly: `0/1/2/...`
- If no node name is saved for this GPU yet: you will be prompted to confirm a `NODE_NAME`
  - Press Enter: accept the suggested value (e.g., `rabah-node-gpu1-ABCDE`)
  - Or input: customize or restore a node name you previously used

These settings will be saved to `node-config.txt` and will not be prompted again on subsequent startups (unless you delete the file or set `RESET_CONFIG=1`).

## 4.1 Running with Multiple GPUs (Windows)

It is recommended to start "one node per GPU". Each node should use a different `GPU_INDEX`. The script will automatically generate and persist a unique `NODE_NAME` for each GPU (saved as `NODE_NAME_GPU0/NODE_NAME_GPU1/...` in `node-config.txt`). On future startups, you can simply run the script and select the node from the menu, or continue specifying it via `GPU_INDEX`.

Example: Two GPUs (GPU 0 and GPU 1), open two separate terminal windows (replace the directories below with your extracted directory):

Window 1:

```powershell
cd D:\rabah-node
$env:GPU_INDEX="0"
.\start.bat
```

Window 2:

```powershell
cd D:\rabah-node
$env:GPU_INDEX="1"
.\start.bat
```

If you wish to "restore a previous node name" or customize it, you can manually set the `NODE_NAME` environment variable once during your first launch for a specific GPU (it will be saved for future launches):

```powershell
cd D:\rabah-node
$env:GPU_INDEX="1"
$env:NODE_NAME="rabah-node-gpu1-your-old-suffix"
.\start.bat
```

If you are using `cmd.exe` (instead of PowerShell), use:

```bat
cd /d D:\rabah-node
set GPU_INDEX=1
start.bat
```

Note:

- If both GPUs will use the same account (same Email and Wallet), keep them consistent.
- If you desire to bind each GPU to a separate email independently, you can input them separately in different windows (they will be saved to their respective `node-config.txt`, so it's recommended to run them in different directories).

## 5. How Auto-updates Work

Every time you run `start.bat` / `start.sh`, it will first execute:

- `docker pull ghcr.io/...:latest`

Once successful, it will launch the node container. You do not need to download updates manually.

## 6. Benchmark

After the node boots up, it runs a benchmark to display the node's base score on the web console:

- Warmup 1 time (not scored, to eliminate cold-start lag)
- Run 3 times, calculate the average and report
- This does not count towards "completed tasks" (since it wasn't a real task dispatched from the server)

The benchmark cannot be bypassed. If you force set `RUN_BENCHMARK=0`, your node might fail to receive tasks due to the missing `benchmark_score`.

## 7. Troubleshooting

### 7.1 `Docker not found in PATH`

Docker is not installed or not added to your system PATH.

- Windows: Install Docker Desktop and reopen your terminal or restart your PC.
- Linux: Install Docker Engine and log out/log in or reboot.

### 7.2 `Docker is not running`

The Docker service has not started or is unavailable.

- Windows: Open Docker Desktop and wait for it to be ready.
- Linux: Start the Docker daemon (e.g., `systemctl start docker`).

### 7.3 `docker pull` fails

Common reasons:

- Network unable to access GHCR
- Ensure you can successfully run `docker pull ghcr.io/is-pan/rabah-node:latest` in your terminal.

### 7.4 Error `no CUDA-capable device` / Tasks complete extremely slowly

The GPU is not recognized by the container, or driver/GPU passthrough is incorrectly configured. Ensure:

- NVIDIA drivers are working correctly
- The Docker container is allowed to access the GPU (Windows: Docker Desktop GPU support; Linux: NVIDIA Container Toolkit)
- The machine indeed has an available GPU

### 7.5 Poll failed / Connection refused

Indicates the node briefly failed to connect to the server while polling for tasks (server restart / network jitter). It usually recovers after retrying and does not impact long-term operations.

### 7.6 Writeback error `stale_lease` / Task reclaimed after running too long

If you see `stale_lease` when the node reports a completion/failure, it usually means the task has been reclaimed by the server and put back into the queue (e.g., the execution time significantly exceeded the historical baseline threshold for your GPU + template).

How to handle:

- No manual intervention is needed: The node will automatically resume polling for new tasks.
- The output of the current rejected task is discarded by the server (because the lease expired), which is standard protection functionality.
- If this happens constantly: Ensure your machine has no thermal throttling / VRAM shortage / driver crashes. Then contact administrators to adjust server-side thresholds or sampling strategies.

### 7.7 Node entering "Test Task" mode (Self-Test/bgate)

When a node misbehaves (e.g., failed tasks / disconnections / lease timeouts), the server may mark it as "requiring a test". During this self-test period, the node will only pull "Test Tasks" until it successfully completes one, after which it regains access to normal tasks.

Test tasks are fixed to:

- Workflow: `single-image-edit-flux2-klein.json`
- Model: `flux-2-klein-9b-fp8`

Important Rules:

- Once a node enters self-test mode, it will not fetch any regular tasks until it passes.
- Upon self-test failure, it will retry repeatedly until it succeeds.
- Test tasks are exempt from "normal task timeout reclaiming" (but still bound by the lease/heartbeat mechanisms, so the node must remain online and heartbeat continuously).
- To prevent extreme conditions (e.g., all nodes are testing and nobody serves normal tasks), the server prioritizes the normal task queue if it has items. However, nodes locked into test mode will continue to receive test tasks.

What you will observe:

- The task payload in node logs will include `__system_test: "node_gate"` (indicating a self-test task).
- In the web console task list, you might spot the node processing a test task with cost=0 (system task).

## 8. Stopping the Node

- Windows: Double-click `stop.bat`, which will list running node containers and allow you to select which ones to stop; or you can stop all.
- Linux: Run `./stop.sh`, which will list running node containers and allow you to select which ones to stop; or you can stop all.

For "non-interactive" stops targeting a specific GPU (recommended for multi-node deployments):

Windows PowerShell:

```powershell
$env:GPU_INDEX="1"
$env:NO_PAUSE="1"
.\stop.bat
```

Linux:

```bash
GPU_INDEX=1 NO_PAUSE=1 ./stop.sh
```

Stop ALL (Windows cmd.exe):

```bat
set STOP_ALL=1
stop.bat
```

Stop ALL (Windows PowerShell):

```powershell
$env:STOP_ALL="1"
.\stop.bat
```

Stop ALL (Linux):

```bash
STOP_ALL=1 ./stop.sh
```

## 9. Advanced: Resetting Local Configs

If you wish to re-enter your wallet / GPU settings:

- Method 1: Delete `node-config.txt`
- Method 2: Define the `RESET_CONFIG=1` environment variable before running the script

## 10. Linux Support

The node application runs via Docker, hence Linux machines are fully supported (assuming Docker + NVIDIA GPU capability).

In Linux, use `start.sh` (which shares parity with the Windows `start.bat`), supporting interactive prompts and automatically generating `node-config.txt`.

```bash
cd /path/to/agent
chmod +x start.sh stop.sh
./start.sh
```
To stop the node: See Section 8 (`./stop.sh` or `STOP_ALL=1 ./stop.sh`).

### 10.1 Running Multiple GPUs (Linux)

Similar recommendations apply: "one node per GPU", utilizing different `GPU_INDEX` indexes. The script will automatically generate and save a unique `NODE_NAME` for each card (persisted in `node-config.txt` as `NODE_NAME_GPU0/NODE_NAME_GPU1/...`).

Example: Two GPUs (GPU 0 and GPU 1):

Terminal 1:

```bash
cd /path/to/agent
EMAIL=your@email.com WALLET_ADDRESS=your_wallet_address GPU_INDEX=0 ./start.sh
```

Terminal 2:

```bash
cd /path/to/agent
EMAIL=your@email.com WALLET_ADDRESS=your_wallet_address GPU_INDEX=1 ./start.sh
```

To restore/customize node names: Assign the `NODE_NAME` variable once during the initial launch for a particular card (it will persist):

```bash
cd /path/to/agent
EMAIL=your@email.com WALLET_ADDRESS=your_wallet_address GPU_INDEX=1 NODE_NAME=rabah-node-gpu1-your-old-suffix ./start.sh
```
