# Privacy, ratings and review answers

The questionnaires App Store Connect walks you through, with the answer to click and why. Plus
the notes for the App Review team, ready to paste.

---

## App Privacy

Left sidebar → **App Privacy** → **Get Started**. Apple turns these answers into the "privacy
nutrition label" on the product page.

**Do you or your third-party partners collect data from this app?** → **Yes, we collect data from this app**

Select one data type:

| Data type | Tick? |
|---|---|
| Location → **Precise Location** | ✅ Yes |
| Everything else (Contact Info, Health, Financial, Identifiers, Usage Data, Diagnostics, Photos or Videos, …) | No |

For **Precise Location**, answer:

| Question | Answer |
|---|---|
| How is it used? | **App Functionality** only |
| Is it linked to the user's identity? | **No** |
| Is it used for tracking? | **No** |

The label will read **Data Not Linked to You: Location**.

**Why location counts:** to fetch traffic, the app sends Flightradar24 a box drawn around your
exact position, and its centre is your location to full precision. Apple counts data as
"collected" if a third party can keep it longer than it takes to answer the request. You can't
promise Flightradar24 doesn't log requests, so declaring it is the honest choice. It costs
little: "Not linked to you" is the mildest label there is.

**Why nothing else counts:**
- **Logbook, Sky View photos and pins** stay on the device or go to the user's *private* iCloud
  database and key-value store. You can't read those, so they aren't collected.
- **Aircraft photos:** the app sends Planespotters.net the aircraft's registration, nothing
  about the user.
- **Place names** come from Apple's own geocoder, and maps come from Apple Maps.
- **Apple TV link:** stays on the local network.
- There are no analytics, ads, crash-reporting SDKs or accounts.

**Optional tidy-up:** `WhatTheFlight/WhatTheFlight/PrivacyInfo.xcprivacy` currently lists no
collected data. Apple doesn't reject a mismatch, but it's cleaner if the privacy manifest also
lists `NSPrivacyCollectedDataTypePreciseLocation` (not linked, not tracking, purpose App
Functionality). That's a five-line change; ask for it if you want it.

---

## Content rights

App Information → **Content Rights** → "Does your app contain, show, or access third-party
content?" → **Yes**. You're then asked to confirm you have the rights to it.

| Source | What the app uses | Rights |
|---|---|---|
| OurAirports | Airport names and positions (bundled) | Public domain. ✅ |
| OpenFlights | Airline names and callsigns (bundled) | ODbL: attribution required, shown in Settings → About. ✅ |
| Planespotters.net | Aircraft photos | Their public API is meant for this, with the photographer credited and linked, which the app does. ✅ |
| **Flightradar24** | **Every aircraft position** | ⚠️ **No licence.** The app reads Flightradar24's private web feed (`data-cloud.flightradar24.com/zones/fcgi/feed.js`) with a browser User-Agent. Their terms prohibit automated access without permission; the licensed route is their paid API at fr24api.flightradar24.com. |

This is the one real risk to the submission. App Review Guideline 5.2.2 says an app that shows
content from a third-party service must be "specifically permitted to do so under the service's
terms of use", and a reviewer can ask you to prove it. Even if review doesn't catch it,
Flightradar24 can file a complaint with Apple later or block the feed, and the app goes blank
for everyone. See the README for your options.

---

## Age Rating

App Information → **Age Rating** → **Set Up Age Rating**. Answer **None** or **No** to every
question. Apple has reworded these over time; if you see one not listed here, the answer is
still None/No.

| Section | Questions | Answer |
|---|---|---|
| In-app controls | Parental controls, age assurance | No |
| Capabilities | Unrestricted web access, user-generated content, messaging and chat, advertising | No (links open in Safari, not inside the app) |
| Mature themes | Profanity or crude humor, horror/fear, alcohol/tobacco/drugs | None |
| Medical or wellness | Medical information, health or wellness topics | None / No |
| Sexuality or nudity | All | None |
| Violence | Cartoon, realistic, graphic violence, guns or other weapons | None (military aircraft are shown as traffic, not weapons) |
| Chance-based | Simulated gambling, gambling, contests, loot boxes | None / No |

Result: **4+**.

---

## Export compliance (encryption)

Already handled. The project sets `ITSAppUsesNonExemptEncryption = NO` (the app only uses
Apple's standard HTTPS), so App Store Connect won't ask about encryption when you upload. If it
ever does ask: "Does your app use encryption?" → **Yes**, then **"None of the algorithms
mentioned above"** (standard HTTPS only).

---

## Notes for App Review

Paste into **App Review Information → Notes** on the version page. 2,533 / 4,000 characters.

```text
Thanks for reviewing What The Flight?

There are no accounts, sign-in or in-app purchases. Everything works as soon as location access is allowed.

WHAT IT DOES
A live radar of the aircraft flying around you. The nearest aircraft sits in the center; every other aircraft sits on the edge of the screen in its compass direction, with its distance in miles.

HOW TO TRY IT
1. Allow location ("While Using the App"). Aircraft appear within about 20 seconds.
2. Swipe left for the next aircraft out, right to come back to the nearest. Tap the center for details: photo, airline, route and map.
3. Tap the aircraft-count badge in the bottom-left corner to search for any flight worldwide and to open the Logbook. The gear in the bottom-right corner opens Settings.
4. Lift the phone toward the sky to open Sky View, which labels aircraft in the camera image. It works best outdoors with a clear view of the sky. "Find in the Sky" on a flight's details also opens it.
5. Indoors, or nothing flying nearby? Settings > Behavior > Demo traffic shows simulated aircraft. They are marked DEMO and are never logged.

PERMISSIONS
- Location (While Using the App): to ask for the aircraft around you. The app never asks for Always access.
- Background location: only while Sky Watch is on (Settings > Alerts > Start Sky Watch). The user starts it, it shows a Live Activity and the blue location indicator, and it stops on its own after two hours. It lets overhead alerts arrive as notifications while the phone is locked.
- Background remote notifications: iCloud (CloudKit) uses silent pushes to sync the logbook between the user's devices.
- Camera: Sky View, and aiming the iPhone at an Apple TV to measure which way the TV faces.
- Photo Library (add only): saving Sky View photos to the camera roll.
- Local Network: linking the iPhone to an Apple TV on the same network (Settings > Apple TV).
- Notifications: alerts for aircraft about to pass overhead and for notable aircraft.
- Motion (Apple Watch only): Point & Find uses the Watch's motion sensors to tell where the user's arm points.

ALSO INCLUDED
An Apple Watch app that runs on its own with the Watch's GPS, Home Screen and Lock Screen widgets, a Live Activity, and Siri shortcuts such as "What's that plane in What The Flight?".

DATA SOURCES
Flight positions: Flightradar24. Aircraft photos: Planespotters.net, with the photographer credited and linked on every photo. Airline names: OpenFlights (ODbL). Airports: OurAirports (public domain). All are credited in Settings > About.
```

---

## Things App Review might ask, and what to say

| If they say… | Reply / fix |
|---|---|
| **5.2.2:** "Provide documentation that you're authorized to use Flightradar24 data." | You can only answer this with a licence or written permission. See the README. |
| **2.5.4:** "Why does the app use background location?" | Point them at the PERMISSIONS paragraph: user-started, visible, two-hour limit, for alerts while locked. |
| **2.1:** "We couldn't see any aircraft." | Reply with the demo traffic steps, or attach a screen recording from a real device. |
| **5.1.1:** "Purpose string isn't specific enough." | Rewrite the string they quote in Xcode (target → Info), bump the build number, upload again. |
| **Name:** "The name implies profanity." | Unlikely, but if so, answer the questionnaire's crude-humor question as "Infrequent/Mild", or reply that it's a pun on "flight". |

Reply in **App Review → Resolution Center** (it's linked from the email). A reply without a new
build often clears explanation-only questions within a day.
