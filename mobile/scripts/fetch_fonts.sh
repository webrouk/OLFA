#!/usr/bin/env bash
# Downloads Tajawal + Montserrat (SIL Open Font License) into assets/fonts.
# Run once from mobile/:  bash scripts/fetch_fonts.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/fonts
BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"
for w in Regular Medium Bold ExtraBold; do
  curl -fsSL "$BASE/tajawal/Tajawal-$w.ttf" -o "assets/fonts/Tajawal-$w.ttf"
done
# Montserrat ships as a variable font upstream; static instances come from the
# official Montserrat repository.
MBASE="https://raw.githubusercontent.com/JulietaUla/Montserrat/master/fonts/ttf"
for w in Regular Medium SemiBold Bold; do
  curl -fsSL "$MBASE/Montserrat-$w.ttf" -o "assets/fonts/Montserrat-$w.ttf"
done
echo "Fonts ready in assets/fonts"
