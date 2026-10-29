#!/bin/zsh
# Renders the round 3 icons into the app's asset catalog (iPhone and iPad alternates):
#   AppIcon-<Name>.appiconset        Automatic: light, dark and tinted
#   AppIcon-<Name>Light.appiconset   always the light art (+ tinted)
#   AppIcon-<Name>Dark.appiconset    always the dark art (+ tinted)
#   IconPreview-<Name>.imageset      240 px picker preview, light and dark appearances
# Needs Google Chrome and Python with Pillow. Run from anywhere: ./render.sh
set -e
here=${0:A:h}
catalog="$here/../../WhatTheFlight/WhatTheFlight/Assets.xcassets"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# id:AssetName
icons=(interrobang:Interrobang cloud:CloudMark wideeyed:WideEyed paper:LoopTheLoop doubletake:DoubleTake
       tailfin:TailFin board:DepartureBoard birdplane:BirdOrPlane trend:TrendContrail hours:SkyByTheHour
       rose:HeadingRose tally:Tally badge:BadgeRing collection:Collection)

for entry in $icons; do
  id=${entry%%:*}
  for mode in light dark tinted; do
    "$chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1024,1024 \
      --user-data-dir="$work/profile-$id-$mode" --screenshot="$work/$id-$mode.png" \
      "file://$here/icon-render.html#$id,$mode,1024" >/dev/null 2>&1 &
  done
  wait
done

python3 - "$work" "$catalog" $icons <<'PY'
import json, os, sys
from PIL import Image
work, catalog, entries = sys.argv[1], sys.argv[2], sys.argv[3:]

def icon_set(name, files):
    folder = os.path.join(catalog, f"AppIcon-{name}.appiconset")
    os.makedirs(folder, exist_ok=True)
    images = []
    for appearance, image in files:
        filename = f"{appearance}.png"
        image.save(os.path.join(folder, filename), optimize=True)
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance != "any":
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(folder, "Contents.json"), "w"), indent=2)

def preview(name, light, dark):
    folder = os.path.join(catalog, f"IconPreview-{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    light.resize((240, 240), Image.LANCZOS).save(os.path.join(folder, "any.png"), optimize=True)
    dark.resize((240, 240), Image.LANCZOS).save(os.path.join(folder, "dark.png"), optimize=True)
    json.dump({"images": [{"filename": "any.png", "idiom": "universal"},
                          {"filename": "dark.png", "idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}]}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(folder, "Contents.json"), "w"), indent=2)

for entry in entries:
    icon, name = entry.split(":")
    # App icons must be opaque: no alpha channel.
    art = {m: Image.open(os.path.join(work, f"{icon}-{m}.png")).convert("RGB") for m in ("light", "dark", "tinted")}
    assert all(im.size == (1024, 1024) for im in art.values()), icon
    icon_set(name, [("any", art["light"]), ("dark", art["dark"]), ("tinted", art["tinted"])])
    icon_set(f"{name}Light", [("any", art["light"]), ("tinted", art["tinted"])])
    icon_set(f"{name}Dark", [("any", art["dark"]), ("tinted", art["tinted"])])
    preview(name, art["light"], art["dark"])
    print("rendered", name)
PY
