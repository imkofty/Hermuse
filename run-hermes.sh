#!/bin/bash
# Menjalankan Hermes CLI.
#
# Mode default (disarankan): pakai perintah `hermes` dari instalasi standar.
# scripts/install.sh memasang Hermes lewat installer resmi Nous Research;
# perintahnya tinggal di ~/.local/bin. Script ini meneruskan argumen ke sana.
#
# Mode venv (OPT-IN eksplisit, untuk provisioning non-standar): set
#   HERMES_VENV -> venv hasil provisioning (harus berisi bin/python)
#   HERMES_SRC  -> checkout source hermes-agent (default ~/hermes-agent)
# Tanpa keduanya mode ini MENOLAK jalan dengan pesan jelas — tidak ada lagi
# path placeholder <INSTALL_ID>/<ENV_ID> yang diam-diam rusak.

export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

# Daftar no_proxy minimal. (Catatan dari VM asal: entri IPv6 bracket seperti
# [::1] di no_proxy membuat httpx crash dengan "Invalid port" — pakai daftar
# minimal yang aman ini.)
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

if [ -n "${HERMES_VENV:-}" ]; then
  HERMES_SRC="${HERMES_SRC:-$HOME/hermes-agent}"
  export HERMES_SRC
  if [ ! -x "$HERMES_VENV/bin/python" ]; then
    echo "run-hermes: HERMES_VENV=$HERMES_VENV tidak berisi venv yang valid (bin/python tidak ditemukan)." >&2
    echo "run-hermes: perbaiki HERMES_VENV, atau kosongkan agar memakai perintah 'hermes' standar." >&2
    exit 1
  fi
  if [ ! -d "$HERMES_SRC/hermes_cli" ]; then
    echo "run-hermes: HERMES_SRC=$HERMES_SRC tidak berisi source hermes-agent (folder hermes_cli tidak ditemukan)." >&2
    echo "run-hermes: set HERMES_SRC ke checkout hermes-agent yang benar, atau kosongkan HERMES_VENV." >&2
    exit 1
  fi
  exec "$HERMES_VENV/bin/python" -c "
import os, sys
sys.path.insert(0, os.environ['HERMES_SRC'])
from hermes_cli.main import main
sys.argv = ['hermes'] + sys.argv[1:]
main()
" "$@"
fi

if command -v hermes >/dev/null 2>&1; then
  exec hermes "$@"
fi

# hermes terpasang tapi ~/.local/bin belum masuk PATH shell ini (non-login shell)
if [ -x "$HOME/.local/bin/hermes" ]; then
  exec "$HOME/.local/bin/hermes" "$@"
fi

echo "run-hermes: perintah 'hermes' tidak ditemukan." >&2
echo "run-hermes: jalankan dulu: bash scripts/install.sh" >&2
exit 1
