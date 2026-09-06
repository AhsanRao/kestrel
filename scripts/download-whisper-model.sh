#!/usr/bin/env bash
# Downloads a whisper.cpp GGML model into ~/.kestrel/models.
#   ./scripts/download-whisper-model.sh [base.en|small|medium|large-v3-turbo]
# base.en  ~148 MB, fastest, English only        (default)
# small    ~488 MB, multilingual — use for Urdu or mixed speech
set -euo pipefail

MODEL="${1:-base.en}"
DEST="$HOME/.kestrel/models"
FILE="ggml-${MODEL}.bin"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${FILE}"

mkdir -p "$DEST"
if [ -f "$DEST/$FILE" ]; then
  echo "already present: $DEST/$FILE"
  exit 0
fi

echo "downloading $FILE …"
curl -fL --progress-bar -o "$DEST/$FILE.part" "$URL"
mv "$DEST/$FILE.part" "$DEST/$FILE"
echo "installed: $DEST/$FILE"
echo
echo "If this is not base.en, point Kestrel at it:"
echo "  Settings ▸ Speech ▸ Whisper model, or edit ~/.kestrel/config.json"
