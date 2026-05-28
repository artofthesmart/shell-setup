#!/bin/bash

# Get the absolute path of the script, resolving symlinks
REAL_SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(dirname "$REAL_SCRIPT_PATH")

# Load environment variables if .env exists in the script's directory
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

if [ "$1" == "rm" ] || [ "$1" == "remove" ]; then
  TARGET_INPUT=$2
  MODEL=$3
  if [ -z "$TARGET_INPUT" ] || [ -z "$MODEL" ]; then
    echo "Usage: $0 rm <gpu|cpu|both> <model_name>"
    exit 1
  fi

  read -p "⚠️ Are you sure you want to remove model '$MODEL' from '$TARGET_INPUT'? (y/N) " confirm
  if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "Aborted."
    exit 0
  fi

  if [ "$TARGET_INPUT" == "both" ]; then
    TARGETS=("gpu" "cpu")
  else
    TARGETS=("$TARGET_INPUT")
  fi

  for TARGET in "${TARGETS[@]}"; do
    echo "🗑️ Removing $MODEL from ollama-$TARGET..."
    docker exec -it "ollama-$TARGET" ollama rm "$MODEL"
  done
  exit 0
fi

if [ "$1" == "list" ]; then
  echo "========== GPU Models =========="
  docker exec -it ollama-gpu ollama list
  echo "========== CPU Models =========="
  docker exec -it ollama-cpu ollama list
  exit 0
fi

if [ "$1" == "refresh" ]; then
  TARGET_INPUT=$2
  # Shift out 'refresh' so that the rest of the script processes it as a normal pull
  shift
  
  # Parse the model name to remove it
  TEMP_MODEL=""
  for arg in "$@"; do
    case $arg in
      --name=*) TEMP_MODEL="${arg#*=}" ;;
      --model=*) [ -z "$TEMP_MODEL" ] && TEMP_MODEL="${arg#*=}" ;;
      *) [ -z "$TEMP_MODEL" ] && [ "$arg" != "$TARGET_INPUT" ] && TEMP_MODEL="$arg" ;;
    esac
  done

  if [ -z "$TARGET_INPUT" ] || [ -z "$TEMP_MODEL" ]; then
    echo "Usage: $0 refresh <gpu|cpu|both> <model_name>"
    exit 1
  fi

  if [ "$TARGET_INPUT" == "both" ]; then
    TARGETS=("gpu" "cpu")
  else
    TARGETS=("$TARGET_INPUT")
  fi

  for TARGET in "${TARGETS[@]}"; do
    echo "♻️ Refreshing: Removing $TEMP_MODEL from ollama-$TARGET before pulling..."
    docker exec -it "ollama-$TARGET" ollama rm "$TEMP_MODEL" >/dev/null 2>&1 || true
    # Also attempt to remove the suffix tagged version if applicable
    docker exec -it "ollama-$TARGET" ollama rm "${TEMP_MODEL}-${TARGET}" >/dev/null 2>&1 || true
  done
  # Now let it fall through to the pull logic
fi

if [ $# -lt 2 ]; then
  echo "Usage: $0 <gpu|cpu|both|list|rm|refresh> [--name=model_name] [--model=source_model]"
  echo "Example: $0 both llama3"
  echo "Example: $0 gpu --name=qwen3-coder-next:80b --model=hf.co/unsloth/Qwen3-Coder-Next-GGUF:UD-Q4_K_M"
  echo "Example: $0 rm gpu llama3-gpu"
  echo "Example: $0 refresh both llama3"
  echo "Example: $0 list"
  exit 1
fi

TARGET_INPUT=$1
shift

MODEL_NAME=""
MODEL=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --name=*) MODEL_NAME="${1#*=}" ;;
    --model=*) MODEL="${1#*=}" ;;
    *) 
      # Fallback for old positional arguments
      if [ -z "$MODEL" ]; then
        MODEL="$1"
        MODEL_NAME="$1"
      fi
      ;;
  esac
  shift
done

# If --model is provided but not --name, default name to model
if [ -n "$MODEL" ] && [ -z "$MODEL_NAME" ]; then
  if [[ "$MODEL" == hf.co/* ]]; then
    MODEL_NAME=$(basename "$MODEL")
  else
    MODEL_NAME="$MODEL"
  fi
fi

# If only --name is provided, use it as the model to pull
if [ -n "$MODEL_NAME" ] && [ -z "$MODEL" ]; then
  MODEL="$MODEL_NAME"
fi

# Sanitize MODEL_NAME to be lowercase and replace invalid chars like parenthesis
if [ -n "$MODEL_NAME" ]; then
  MODEL_NAME=$(echo "$MODEL_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/(/-/g' | sed 's/)//g' | tr -cd 'a-z0-9_.:-')
fi

if [ -z "$MODEL_NAME" ]; then
  echo "Error: Model name became empty after sanitization."
  exit 1
fi

if [ -z "$MODEL" ]; then
  echo "Error: No model specified."
  exit 1
fi

if [ "$TARGET_INPUT" != "gpu" ] && [ "$TARGET_INPUT" != "cpu" ] && [ "$TARGET_INPUT" != "both" ]; then
  echo "Error: Target must be 'gpu', 'cpu', or 'both'."
  exit 1
fi

if [ "$TARGET_INPUT" == "both" ]; then
  TARGETS=("gpu" "cpu")
else
  TARGETS=("$TARGET_INPUT")
fi

for TARGET in "${TARGETS[@]}"; do
  CONTAINER="ollama-${TARGET}"
  SUFFIX="-${TARGET}"

  if [[ "$MODEL_NAME" == *":"* ]]; then
    BASE="${MODEL_NAME%%:*}"
    TAG="${MODEL_NAME#*:}"
    NEW_MODEL="${BASE}${SUFFIX}:${TAG}"
  else
    NEW_MODEL="${MODEL_NAME}${SUFFIX}"
  fi

  echo "========================================"
  # Deep check if it already exists (to handle the 1.5b vs 15b pollution bug)
  EXISTING_SIZE=$(docker exec "$CONTAINER" ollama list 2>/dev/null | grep -E "^${NEW_MODEL}\s" | awk '{print $3$4}')
  if [ -n "$EXISTING_SIZE" ]; then
    echo "🔍 Deep check: Found existing '$NEW_MODEL' with size $EXISTING_SIZE."
    echo "♻️ Ensuring clean state: removing existing model to guarantee fresh correct download..."
    docker exec "$CONTAINER" ollama rm "$NEW_MODEL" >/dev/null 2>&1 || true
  fi

  echo "🚀 Pulling $MODEL on $CONTAINER..."
  
  PULL_LOG=$(mktemp)
  if [ -n "$HF_TOKEN" ]; then
    script -q -c "docker exec -e HF_TOKEN=\"$HF_TOKEN\" -it \"$CONTAINER\" ollama pull \"$MODEL\"" /dev/null 2>&1 | tee "$PULL_LOG"
  else
    script -q -c "docker exec -it \"$CONTAINER\" ollama pull \"$MODEL\"" /dev/null 2>&1 | tee "$PULL_LOG"
  fi
  PULL_STATUS=${PIPESTATUS[0]}

  WORKAROUND_SUCCESS=0

  if [ $PULL_STATUS -ne 0 ]; then
    if grep -q "sharded GGUF" "$PULL_LOG"; then
      echo "⚠️ Sharded GGUF detected! Ollama does not natively support downloading sharded GGUFs yet."
      echo "🛠️ Engaging automatic workaround (download & merge)..."
      
      REPO=$(echo "$MODEL" | sed 's|hf.co/||' | cut -d':' -f1)
      HF_TAG=$(echo "$MODEL" | cut -d':' -f2)
      
      TEMP_DIR="/models/temp_${HF_TAG}"
      MERGED_FILE="/models/${HF_TAG}_merged.gguf"
      
      # Bypass broken docker credential helpers by using an empty config dir
      DOCKER_CFG="/tmp/empty_docker_config"
      mkdir -p "$DOCKER_CFG"
      
      echo "📥 [1/3] Downloading shards for $REPO ($HF_TAG)..."
      docker --config "$DOCKER_CFG" run -t --rm -v /var/lib/ai-models/llama:/models -e HF_TOKEN="$HF_TOKEN" -e HF_HUB_DISABLE_PROGRESS_BARS=0 python:3.11-slim bash -c "pip install -q huggingface_hub && hf download $REPO --include '*${HF_TAG}-*.gguf' --local-dir $TEMP_DIR"
      
      echo "🧩 [2/3] Merging shards into a single GGUF..."
      # Use find to locate the first shard regardless of folder structure or number of leading zeros
      docker --config "$DOCKER_CFG" run --rm --entrypoint /bin/bash -v /var/lib/ai-models/llama:/models ghcr.io/ggml-org/llama.cpp:full -c "rm -f $MERGED_FILE && FIRST_SHARD=\$(find $TEMP_DIR -type f -name '*1-of-*.gguf' | sort | head -n 1) && /app/llama-gguf-split --merge \"\$FIRST_SHARD\" $MERGED_FILE"
      
      echo "🏗️ [3/3] Creating model in Ollama directly as $NEW_MODEL..."
      # Create Modelfile inside the ollama container's /tmp dir directly
      docker exec "$CONTAINER" sh -c "echo 'FROM $MERGED_FILE' > /tmp/Modelfile"
      
      docker exec -it "$CONTAINER" ollama create "$NEW_MODEL" -f /tmp/Modelfile
      CREATE_STATUS=$?
      
      echo "🧹 Cleaning up temporary files..."
      # Clean up the root-owned files using a quick alpine container
      docker --config "$DOCKER_CFG" run --rm -v /var/lib/ai-models/llama:/models alpine rm -rf "$TEMP_DIR" "$MERGED_FILE"
      
      if [ $CREATE_STATUS -eq 0 ]; then
        WORKAROUND_SUCCESS=1
      else
        echo "❌ Failed to create $NEW_MODEL on $CONTAINER."
      fi
    else
      echo "❌ Failed to pull $MODEL on $CONTAINER."
    fi
  fi
  rm -f "$PULL_LOG"

  if [ $PULL_STATUS -eq 0 ]; then
    echo "🏷️ Tagging as $NEW_MODEL..."
    docker exec -it "$CONTAINER" ollama cp "$MODEL" "$NEW_MODEL"

    echo "🧹 Cleaning up base model name..."
    if [ "$MODEL" != "$NEW_MODEL" ]; then
        docker exec -it "$CONTAINER" ollama rm "$MODEL"
    fi

    echo "✅ Done! Model is available in OpenWebUI as $NEW_MODEL."
  elif [ $WORKAROUND_SUCCESS -eq 1 ]; then
    echo "✅ Done! Model was merged and directly created as $NEW_MODEL."
  fi
done
