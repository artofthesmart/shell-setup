#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0 <gpu|cpu|both> <model_name>"
  echo "Example: $0 both llama3"
  exit 1
fi

TARGET_INPUT=$1
MODEL=$2

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

  echo "========================================"
  echo "🚀 Pulling $MODEL on $CONTAINER..."
  docker exec -it "$CONTAINER" ollama pull "$MODEL"

  if [ $? -eq 0 ]; then
    # Determine new name (handle tags like llama3:8b)
    if [[ "$MODEL" == *":"* ]]; then
      BASE="${MODEL%%:*}"
      TAG="${MODEL#*:}"
      NEW_MODEL="${BASE}${SUFFIX}:${TAG}"
    else
      NEW_MODEL="${MODEL}${SUFFIX}"
    fi

    echo "🏷️ Tagging as $NEW_MODEL..."
    docker exec -it "$CONTAINER" ollama cp "$MODEL" "$NEW_MODEL"

    echo "🧹 Cleaning up base model name..."
    docker exec -it "$CONTAINER" ollama rm "$MODEL"

    echo "✅ Done! Model is available in OpenWebUI as $NEW_MODEL."
  else
    echo "❌ Failed to pull $MODEL on $CONTAINER."
  fi
done
