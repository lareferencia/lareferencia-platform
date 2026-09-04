#!/usr/bin/env bash
set -euo pipefail

cd /workspace/lareferencia-lrharvester-admin-web
if [ ! -x node_modules/.bin/vite ]; then
  echo 'Installing admin web dependencies...'
  npm ci --no-audit --no-fund
fi
exec npm run dev -- --host 0.0.0.0
