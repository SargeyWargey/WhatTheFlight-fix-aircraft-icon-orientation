# Store listing: copy and paste

Every text field App Store Connect asks for, in the order the pages show them. Copy the text
inside each box exactly. The numbers after each heading are characters used / allowed, already
checked.

Text in `[square brackets]` is yours to fill in. Nothing else needs changing.

---

## Page: App Information (left sidebar → General → App Information)

These are set once for the app, not per version.

### Name · 16 / 30

```text
What The Flight?
```

The name must be unique on the App Store. If App Store Connect says it's taken, try
`What The Flight? Radar`.

### Subtitle · 29 / 30

Shown under the name everywhere, including search results. Search counts these words, so they
aren't repeated in Keywords.

```text
Live radar of planes overhead
```

Alternatives if you'd rather: `What's that plane overhead?` (27) or `Every aircraft above you, live` (30).

### Category

- **Primary:** Travel
- **Secondary:** Utilities

Flight trackers live in Travel, where people browse for them.

### Content Rights

"Does your app contain, show, or access third-party content?" → **Yes**.
Read the content rights section in [3 Privacy and Review.md](3%20Privacy%20and%20Review.md#content-rights)
before you tick "I have the necessary rights". The Flightradar24 feed is the one to think about.

### Age Rating

Click **Set Up Age Rating** and answer **None / No** to everything. The full answer list is in
[3 Privacy and Review.md](3%20Privacy%20and%20Review.md#age-rating). Result: **4+**.

---

## Page: App Privacy (left sidebar → General → App Privacy)

### Privacy Policy URL

```text
https://sargeywargey.github.io/whattheflight/privacy.html
```

That address works once the website is published (guide step 3). The data questions are in
[3 Privacy and Review.md](3%20Privacy%20and%20Review.md#app-privacy).

---

## Page: Pricing and Availability

- **Price:** Free (USD 0.00 tier)
- **Availability:** All countries or regions. The app is in English and shows distances in miles;
  you can limit it to the US, Canada and the UK if you'd rather start small.
- **iPhone and iPad Apps on Apple silicon Macs** and **Apple Vision Pro**: untick both for 1.0.
  Neither has been tested, and Sky View, the compass and GPS behave differently there.

---

## Page: iOS App Version 1.0 (the page in your screenshot)

### Header and Search Results (optional)

The new custom header and search-result artwork is optional. Skip it for the first submission
or use the art from the Asset Studio (**Header & Search** tab, saved to `Header Art/`): either the 5244 × 2950 **Universal** PNG
(one file for both places) or the 3840 × 1646 header plus the 3840 × 2560 search image.

### App Previews and Screenshots

Upload from `Screenshots/Final/`:

| App Store Connect slot | Folder | Size |
|---|---|---|
| iPhone (6.3" display, required) | `Screenshots/Final/iPhone 6.3/` | 1206 × 2622 |
| iPad (13" display, required) | `Screenshots/Final/iPad 13/` | 2064 × 2752 or 2752 × 2064 |
| Apple Watch (appears after a build with the Watch app is attached) | `Screenshots/Final/Apple Watch Ultra/` | 422 × 514 |

App Store Connect scales these down for every smaller device, so one set per row is enough.
Drag them in the order they're numbered: the first three show in search results.

### Promotional Text · 166 / 170

Shown above the description. You can change it any time without submitting a new version.

```text
See every aircraft flying over you right now: the flight, the airline, where it's going and how close it will pass. Raise your iPhone to label the planes you can see.
```

### Description · 3,100 / 4,000

Plain text: App Store Connect shows line breaks but not bold or links. If you're not shipping the
Apple TV app at the same time, delete the APPLE TV paragraph.

```text
Hear a jet overhead and wonder where it's going? What The Flight? shows you every aircraft in the sky around you, live, on a radar that turns as you turn.

THE RADAR
• The nearest aircraft takes the center: flight number, airline, aircraft type, where it's from and where it's going, altitude, speed and distance.
• Every other aircraft sits on the edge of the screen in its real compass direction, nose pointing the way it's flying, with how many miles away it is.
• Turn around and the icons slide around the edge, so whatever is at the top is in front of you.
• Swipe for the next one out, tap any icon to bring it in, hold to pin it.
• Pick your radius, from 2 to 100 miles.

THE FULL STORY
Tap the center for a photo of that exact aircraft, its route on a map, how far along the flight it is and when it will pass closest to you. If you've seen that same plane before, the app remembers.

SKY VIEW
Raise your iPhone to the sky and the camera labels the aircraft you can actually see, right where they are. Line one up to lock on, zoom in and take a photo. It's filed in your logbook as a boarding-pass card you can share.

YOUR LOGBOOK
Every aircraft that comes inside your radius is logged: totals, records like closest and fastest, today's highlights and badges to earn, from First Contact to Queen of the Skies. Your logbook and photos sync across iPhone, iPad and Apple TV with iCloud.

ALERTS FOR THE GOOD STUFF
Get a heads-up when an aircraft is about to pass right over you, or when something unusual is around: emergency squawks, military and government flights, air ambulances and rare aircraft. Sky Watch keeps an eye on the sky in the background for up to two hours, with a Live Activity on your Lock Screen and in the Dynamic Island.

FIND ANY AIRCRAFT
Search by flight number, callsign or tail number anywhere in the world. Pin up to five aircraft and they stay on the edge of your radar wherever they are, across your iPhone, iPad, Apple Watch and Apple TV.

APPLE WATCH
A radar on your wrist, with its own GPS. Point your arm at a plane to find out what it is, or let haptics guide you to the one you're looking for. Complications show what's nearest at a glance.

APPLE TV
Put the sky on the big screen: a radar, a map, or both side by side, with spoken alerts when something flies over. Send your spot and the way your TV faces from your iPhone in one tap.

MAKE IT YOURS
Topographic backgrounds that drift like the tide, light and dark looks, ten app icons, Home Screen and Lock Screen widgets, and Siri: just ask "What's that plane in What The Flight?"

NO ACCOUNT, NO ADS
There's nothing to sign up for and no tracking. Your logbook stays on your devices and in your own iCloud.

ABOUT THE DATA
Flight data comes from Flightradar24, aircraft photos from Planespotters.net (credited to each photographer), airline data from OpenFlights and airport data from OurAirports. Coverage depends on each aircraft's transponder and the receivers near you, so some flights, including many military and private aircraft, may not appear. What The Flight? is for curiosity, not navigation.
```

### Keywords · 99 / 100

Commas, no spaces. The App Store already searches the name and subtitle, so "what", "flight",
"live", "radar", "planes" and "overhead" are left out here. Don't add other apps' names; Apple
rejects that.

```text
tracker,aircraft,airplane,spotting,ADS-B,airport,airline,jet,aviation,tail number,avgeek,helicopter
```

### Support URL

Required. It must open a page with a way to contact you.

```text
https://sargeywargey.github.io/whattheflight/support.html
```

### Marketing URL (optional)

```text
https://sargeywargey.github.io/whattheflight/
```

### Version

```text
1.0
```

This must match `MARKETING_VERSION` in Xcode, which is already 1.0.

### Copyright · 17 / 200

The year, then the name of whoever owns the app: your legal name if you enrolled as an
individual, or the company name if you enrolled as an organization. No © symbol.

```text
2026 Josh Sargent
```

### Routing App Coverage File

Leave empty. It's only for apps that give turn-by-turn directions.

### App Clip / iMessage App

Leave both collapsed. The app has neither.

### Build

Click **Add Build** after you've uploaded one from Xcode (guide step 5) and it has finished
processing (usually 10–30 minutes after upload; you get an email).

### Game Center

Leave unticked.

### App Review Information

- **Sign-in required:** untick it. The app has no accounts.
- **Contact Information:** your name, a phone number and an email you check. Only Apple sees these.
- **Notes:** paste the review notes from [3 Privacy and Review.md](3%20Privacy%20and%20Review.md#notes-for-app-review).
- **Attachment:** optional. A 30-second screen recording of Sky View on a real iPhone outdoors helps
  if the reviewer tests indoors. Record it with Control Center → Screen Recording.

### App Store Version Release

Choose **Manually release this version** for your first app. When it's approved you get an email
and press **Release This Version** yourself, so the launch happens when you're ready.

---

## Later: tvOS App Version 1.0

When you add the Apple TV app (guide step 9), its version page asks for the same fields. Use the
same Promotional Text, Keywords, Support URL, Copyright and Review Notes. For the description, use
the iOS one with the APPLE WATCH and SKY VIEW paragraphs removed. Screenshots are in
`Screenshots/Final/Apple TV/` (3840 × 2160).
