#!/bin/zsh
# Merges the strings the compiler extracted into each target's Localizable.xcstrings.
# Xcode does this itself when you build in the IDE; command-line builds don't, so run this
# after one: Scripts/sync_strings.sh <DerivedData path> [more DerivedData paths…]
# (each path from `xcodebuild … -derivedDataPath`, e.g. one iOS, one tvOS and one watchOS build).
set -e
cd "$(dirname "$0")/.."
[ $# -eq 0 ] && { echo "usage: $0 <derived-data> [...]"; exit 1; }
typeset -A catalogs
catalogs=(
  WhatTheFlight.build WhatTheFlight/Localizable.xcstrings
  WhatTheFlightWidgets.build WhatTheFlightWidgets/Localizable.xcstrings
  WhatTheFlightTopShelf.build WhatTheFlightTopShelf/Localizable.xcstrings
  WhatTheFlightWatch.build WhatTheFlightWatch/Localizable.xcstrings
  WhatTheFlightWatchWidgets.build WhatTheFlightWatchWidgets/Localizable.xcstrings
)
for target catalog in ${(kv)catalogs}; do
  files=()
  for dd in "$@"; do
    files+=($(find "$dd" -path "*/$target/Objects-normal/*" -name '*.stringsdata' 2>/dev/null))
  done
  if (( ${#files} )); then
    xcrun xcstringstool sync "$catalog" --skip-marking-strings-stale --stringsdata "${files[@]}"
    echo "$catalog: $(python3 -c "import json;print(len(json.load(open('$catalog'))['strings']))") keys"
  fi
done
