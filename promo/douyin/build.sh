#!/bin/zsh
set -euo pipefail
FILM_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$FILM_DIR/../.." && pwd)"
PYTHON_BIN="${XVICO_VIDEO_PYTHON:-python3}"
mkdir -p "$FILM_DIR/.build/keyframes" "$FILM_DIR/dist"
"$PYTHON_BIN" "$PROJECT_DIR/promo/prepare-app-assets.py"
"$PYTHON_BIN" "$FILM_DIR/prepare.py"
"$PYTHON_BIN" "$FILM_DIR/soundtrack.py"
swiftc -O "$FILM_DIR/render.swift" -o "$FILM_DIR/.build/render"
"$FILM_DIR/.build/render" "$PROJECT_DIR" --verify-motion
"$FILM_DIR/.build/render" "$PROJECT_DIR" --preview
"$FILM_DIR/.build/render" "$PROJECT_DIR"
swiftc -O -parse-as-library "$FILM_DIR/finish.swift" -o "$FILM_DIR/.build/finish"
"$FILM_DIR/.build/finish" "$PROJECT_DIR"
swiftc -O -parse-as-library "$FILM_DIR/validate.swift" -o "$FILM_DIR/.build/validate"
"$FILM_DIR/.build/validate" "$PROJECT_DIR"
"$PYTHON_BIN" "$FILM_DIR/deliver.py"
