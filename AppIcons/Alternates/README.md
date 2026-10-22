# Alternate app icons

Source for the icons you can pick in Settings → Display → App Icon on iPhone and iPad (see `Services/AppIconChoice.swift`).

The Apple TV doesn't offer them: App Store Connect rejected tvOS alternate icons built as image stacks
("missing the Alternate Icon asset", and "background layer image does not match the canvas dimensions").

`alt-render.html#<icon>,<mode>,<w>,<h>[,<layer>]` draws one:

- `icon`: `edge`, `scope`, `overhead`, `compass`, `family` (Perimeter), `skyview`, or the contrail colourway `signal`
- `mode`: `light`, `dark`, `tinted`
- `layer` (Apple TV, 5:3): `back` (blurred fill), `front` (the art), `flat` (both, for the picker preview)

Render with headless Chrome exactly as in `../Question Contrail/README.md`. The Teal / Night contrail
alternates and the Signal Red TV icon come from `../Question Contrail/icon-render.html`
(`#tv-back,400,240,dark` etc.); Classic is the previous icon from `../Legacy - Question Plane`.
