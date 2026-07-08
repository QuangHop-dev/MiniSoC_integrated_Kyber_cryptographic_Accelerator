#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CGRA="$ROOT/external/CGRA_Reference"
MODE="${1:-512}"
if [[ ! -d "$CGRA" ]]; then
  echo "[ERROR] Missing $CGRA. Run ./scripts/fetch_deps.sh first." >&2
  exit 2
fi
cd "$CGRA"
mkdir -p vectors logs
# Prefer the CGRA_Reference generator, because it owns the matching C-reference policy.
if [[ -x tools/gen_c_reference_vectors.sh ]]; then
  bash tools/gen_c_reference_vectors.sh "$MODE"
elif [[ -f tools/gen_c_reference_vectors.sh ]]; then
  bash tools/gen_c_reference_vectors.sh "$MODE"
else
  echo "[ERROR] Missing CGRA_Reference/tools/gen_c_reference_vectors.sh" >&2
  exit 2
fi
mkdir -p "$ROOT/sim/vectors" "$ROOT/logs"
cp -f vectors/c_ref_${MODE}_*.mem "$ROOT/sim/vectors/"
if [[ -f logs/gen_c_reference_vectors.log ]]; then
  cp -f logs/gen_c_reference_vectors.log "$ROOT/logs/gen_c_reference_vectors.log"
fi
echo "[DONE] Copied C-reference vectors to $ROOT/sim/vectors"
ls -lh "$ROOT/sim/vectors"/c_ref_${MODE}_*.mem
