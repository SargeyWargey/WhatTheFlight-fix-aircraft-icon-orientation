#!/bin/zsh
# Double-click to open the Asset Studio in your browser. Saves go straight into this folder.
cd "$(dirname "$0")"
exec /usr/bin/python3 "Asset Studio/serve.py"
