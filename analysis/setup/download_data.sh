#!/usr/bin/env bash
# Download the MET EEG dataset (OpenNeuro ds008701, version 1.0.4, about 14 GB)
# into data/ds008701. Run from the project folder:  bash analysis/setup/download_data.sh
#
# Preferred route: DataLad (pins the exact version used in the analysis).
#   Install: pip install datalad   (also needs git-annex: brew install git-annex)
# Fallback: the AWS CLI (no account needed), which fetches the latest version.
#   Install: brew install awscli

set -euo pipefail
DEST="data/ds008701"
VERSION="1.0.4"
mkdir -p data

if command -v datalad >/dev/null 2>&1; then
  if [ ! -d "$DEST" ]; then
    datalad clone https://github.com/OpenNeuroDatasets/ds008701.git "$DEST"
  fi
  git -C "$DEST" checkout "$VERSION"
  (cd "$DEST" && datalad get .)
elif command -v aws >/dev/null 2>&1; then
  echo "DataLad not found; using AWS CLI (latest version, not pinned to $VERSION)."
  aws s3 sync --no-sign-request s3://openneuro.org/ds008701 "$DEST"
else
  echo "Install DataLad (preferred) or the AWS CLI, then run this script again." >&2
  exit 1
fi

echo "Done. Dataset is in $DEST"
