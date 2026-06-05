#!/usr/bin/env bash
# Generate one-page Tanium deployment checklist (DOCX + PDF).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

SRC="TANIUM-DEPLOYMENT-CHECKLIST.md"
DOCX="TANIUM-DEPLOYMENT-CHECKLIST.docx"
PDF="TANIUM-DEPLOYMENT-CHECKLIST.pdf"

pandoc "${SRC}" \
  --from gfm \
  --to docx \
  -o "${DOCX}"

if command -v soffice >/dev/null 2>&1; then
  soffice --headless --convert-to pdf "${DOCX}" --outdir .
  echo "Wrote ${PDF}"
else
  echo "LibreOffice (soffice) not found — ${DOCX} only." >&2
fi

echo "Done: ${DOCX}"
