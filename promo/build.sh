#!/bin/zsh
# Native, local-only renderer. Does not launch or modify the Xvico application.
set -euo pipefail
PROMO_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$PROMO_DIR/.." && pwd)"
mkdir -p "$PROMO_DIR/.build" "$PROMO_DIR/dist"
python3 "$PROMO_DIR/prepare-app-assets.py"
python3 "$PROMO_DIR/soundtrack.py"
swiftc -O "$PROMO_DIR/render.swift" -o "$PROMO_DIR/.build/render"
"$PROMO_DIR/.build/render" "$PROJECT_DIR" --verify-motion
"$PROMO_DIR/.build/render" "$PROJECT_DIR" --preview
"$PROMO_DIR/.build/render" "$PROJECT_DIR"
swiftc -O -parse-as-library "$PROMO_DIR/finish.swift" -o "$PROMO_DIR/.build/finish"
"$PROMO_DIR/.build/finish" "$PROJECT_DIR"
python3 "$PROMO_DIR/write-captions.py"
swiftc -O -parse-as-library "$PROMO_DIR/validate.swift" -o "$PROMO_DIR/.build/validate"
"$PROMO_DIR/.build/validate" "$PROJECT_DIR"
printf '%s\n' "$PROMO_DIR/dist/Xvico-promo-4x3-zh.mp4"
