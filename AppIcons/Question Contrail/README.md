# App icon: Question Contrail (Teal & Coral)

The plane's contrail curls into a question mark; the plane is the dot. Deep teal from the night
radar, a white contrail and a coral (signal red) plane. Chosen October 2026.

- `light-1024x1024.png`, `dark-1024x1024.png`, `tinted-1024x1024.png` — iOS / iPadOS appearances
- `mac-1024x1024.png` — macOS (rounded square with margin, macOS doesn't mask)
- `topshelf-*.png` — Apple TV Top Shelf banners
- `icon-render.html` — the source. Every asset is drawn here as SVG; open it with a hash to render one:
  `icon-render.html#light,1024,1024`, `#dark,…`, `#tinted,…`, `#mac,…`, `#tv-back,400,240`,
  `#tv-middle,…`, `#tv-front,…`, `#topshelf,1920,720`. Render at exact size with headless Chrome:

  ```
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
    --force-device-scale-factor=1 --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot=out.png "file://$PWD/icon-render.html#light,1024,1024"
  ```

Installed in `WhatTheFlight/Assets.xcassets/AppIcon.appiconset` (plus the small iPhone/iPad sizes and
Mac sizes resized from these), `App Icon & Top Shelf Image.brandassets` (tvOS layered icon: back =
gradient and contours, middle = contrail, front = plane) and `WhatTheFlightWatch/Assets.xcassets`.
The previous icon is in `../Legacy - Question Plane`.
