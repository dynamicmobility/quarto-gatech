#!/usr/bin/env bash
# Serve main.qmd with live reload; re-render whenever anything in slides/ changes.
set -u

cd "$(dirname "$0")"

PORT=4200

quarto preview main.qmd --port "$PORT" --no-browser &
PREVIEW_PID=$!
trap 'kill $PREVIEW_PID 2>/dev/null; pkill -P $$ fswatch 2>/dev/null' EXIT INT TERM

# Included files aren't watched by quarto preview, so touch main.qmd to trigger a re-render.
# -o batches a burst of events into one line; -l 0.5 waits 0.5s to coalesce saves.
fswatch -o -l 0.5 slides | while read -r _; do
  touch main.qmd
done
