# Submitting What The Flight? to the App Store

A first-time walkthrough, in the order that avoids getting stuck. Each step says where to click.
The text to paste is in [2 Store Listing.md](2%20Store%20Listing.md) and the questionnaire
answers are in [3 Privacy and Review.md](3%20Privacy%20and%20Review.md).

Rough time: an evening for steps 1–8, then 1–2 days waiting on Apple.

**How it fits together:** App Store Connect (appstoreconnect.apple.com) holds the store page.
Xcode builds the app and uploads it. Once it's uploaded, you attach that build to the store
page and press submit. A person at Apple installs it, tries it and approves it or sends
questions. Then you press release.

---

## Step 1 · Check your account is ready

1. Go to **appstoreconnect.apple.com → Business** (older accounts: **Agreements, Tax, and
   Banking**).
2. Make sure the **Free Apps** agreement shows **Active**. If any banner asks you to accept an
   updated agreement, accept it. An unaccepted agreement is the most common reason the
   **Add for Review** button refuses to work.
3. Tax and banking forms are only needed for paid apps or in-app purchases. You can skip them.

## Step 2 · Check the app record

You've already created the app (you're on its version page). Confirm on **App Information**:

- **Bundle ID** is `SargeyWargey.WhatTheFlight`. It must match Xcode exactly, and it can't be
  changed once a build is uploaded.
- **SKU** can be anything (for example `whattheflight`). Only you see it.

## Step 3 · Publish the privacy policy and support page

Apple requires a public **Privacy Policy URL** and **Support URL** before you can submit. Both
are part of the app's website, in the [`Website/`](../Website/) folder at the top of the
repository. That folder is its own git repository, already published by GitHub Pages at
https://sargeywargey.github.io/whattheflight/. Its README has the details. (`AppStore/Website/`
is an older copy from before the site moved there; don't upload it.)

1. Replace `[your support email]` in `Website/support.html`, `Website/privacy.html` and
   `Website/press.html` with an address you're happy to publish. A free alias works, or an
   iCloud+ Hide My Email address. Don't use a work address.
2. From the `Website` folder, run `./publish.sh "Support email"`. It commits and pushes, and the
   site updates a minute or so later.
3. Open these and check they load:
   - `https://sargeywargey.github.io/whattheflight/`
   - `https://sargeywargey.github.io/whattheflight/support.html`
   - `https://sargeywargey.github.io/whattheflight/privacy.html`

The rest of the website's launch checklist (the App Store badge, letting search engines in) is
under "Before publishing" in `Website/README.md`.

## Step 4 · Fill in the app-wide pages

These are in the left sidebar under **General**. They're set once, not per version.

1. **App Information:** Subtitle, Category, Content Rights, Age Rating. Copy from
   [2 Store Listing.md](2%20Store%20Listing.md) and
   [3 Privacy and Review.md](3%20Privacy%20and%20Review.md). Click **Save** (top right) on each page.
2. **Pricing and Availability:** Free, all countries, untick Mac and Vision Pro.
3. **App Privacy:** paste the Privacy Policy URL, then **Get Started** on the data questions and
   answer as in [3 Privacy and Review.md](3%20Privacy%20and%20Review.md#app-privacy). Finish with
   **Publish** on that page. App Privacy has its own Publish button, separate from the version.

## Step 5 · Get iCloud ready for the real world

The logbook syncs through CloudKit. While you've been developing, CloudKit has been using its
**Development** database. App Store and TestFlight builds use **Production**, which starts empty
and doesn't know about your record types until you copy them over. If you skip this, sync
silently fails for everyone.

1. Go to **icloud.developer.apple.com** → **CloudKit Console** → **iCloud.SargeyWargey.WhatTheFlight**.
2. Click **Deploy Schema Changes…** (or **Schema → Deploy to Production**) and confirm.
   You should see the `Sighting` and `SpotPhoto` record types in the list being deployed.
3. Do this again whenever a future version adds a new record type or field.

## Step 6 · Archive and upload the build from Xcode

1. Open `WhatTheFlight/WhatTheFlight.xcodeproj` in Xcode.
2. **Build number:** select the project → target **WhatTheFlight** → **General** → **Build**
   (it's `7` today). Every upload needs a build number higher than the last one you uploaded, so if
   you ever re-upload, bump it (8, 9, …) in every target that shows it: the app, the widgets, the
   Top Shelf extension, the Watch app and Watch widgets. Version stays `1.0`.
3. In the toolbar, set the scheme to **WhatTheFlight** and the destination to
   **Any iOS Device (arm64)**.
4. **Product → Archive.** It takes a few minutes. The Organizer window opens when it's done.
5. In the Organizer, select the new archive and click **Distribute App → App Store Connect →
   Distribute**. Leave the options at their defaults (automatic signing, upload symbols).
   Xcode creates the distribution certificate and profiles for you the first time.
6. When it says **Upload Successful**, you're done in Xcode. Apple processes the build for 10–30
   minutes and emails you when it's ready.

**If the upload fails,** the error message names the problem. The usual ones:
- *Missing purpose string* (ITMS-90683): a permission description is missing in Info.plist. Paste me the message.
- *Invalid bundle / missing icon:* paste me the message.
- *No accounts / signing errors:* Xcode → Settings → Accounts, sign in with your developer
  Apple ID and pick the team in the target's **Signing & Capabilities**.

## Step 7 · Test the real build on your own iPhone (TestFlight)

Worth doing once for a first release. It's the exact build reviewers will get.

1. App Store Connect → your app → **TestFlight** tab. The build appears under **iOS builds**.
2. Under **Internal Testing**, click **+**, create a group (for example "Me"), add yourself, and
   add the build to it. Internal testing needs no review.
3. Install the **TestFlight** app on your iPhone, open the invite and tap **Install**.
4. Check: live traffic loads, Sky View outdoors, a logbook entry appears on another device via
   iCloud, widgets, the Watch app (it installs from the Watch app on your iPhone), Siri.

## Step 8 · Screenshots, text and submit

1. The screenshots are already saved in `Screenshots/Final/`. If you change a caption in the
   Asset Studio (see the README), click **Save all** again.
2. On the **iOS App Version 1.0** page, under **App Previews and Screenshots**, drag in:
   - iPhone: everything in `Screenshots/Final/iPhone 6.3/`
   - iPad: everything in `Screenshots/Final/iPad 13/`
   - Apple Watch: shown once the build is attached. Use `Screenshots/Final/Apple Watch Ultra/`.
3. Fill in Promotional Text, Description, Keywords, Support URL, Marketing URL, Copyright from
   [2 Store Listing.md](2%20Store%20Listing.md).
4. **Build:** click **Add Build** (the blue button) and pick the build from step 6.
5. **App Review Information:** untick **Sign-in required**, fill in your contact details, paste the
   notes.
6. **App Store Version Release:** **Manually release this version**.
7. Click **Save** (top right). Fix anything it flags in red.
8. Click **Add for Review**, then **Submit to App Review** on the page that opens.

## Step 9 · Wait for review

The status at the top of the version page moves through:

| Status | Meaning |
|---|---|
| Waiting for Review | In the queue. Usually under a day. |
| In Review | Someone is testing it right now. Keep your phone handy in case they call. |
| Pending Developer Release | Approved. It's waiting for you (because you chose manual release). |
| Rejected | You'll get an email. Open **App Review → Resolution Center** to read why. |

**If it's rejected:** don't panic. It's normal for a first app, and most rejections are a
question or a small fix. Read the message; [3 Privacy and Review.md](3%20Privacy%20and%20Review.md#things-app-review-might-ask-and-what-to-say)
has replies for the likely ones. Either reply in the Resolution Center (for explanations) or fix
it, upload a new build with a higher build number, attach it to the version and click
**Resubmit**.

## Step 10 · Release

When the status is **Pending Developer Release**, click **Release This Version**. The app
appears on the App Store within a few hours (search can take up to a day to find it). Your
product page link is on the **App Information** page under **View on App Store**.

---

## Later · Adding the Apple TV app

The Apple TV app shares the bundle ID, so it lives on the same app record and people get both
with one download ("universal purchase").

1. In App Store Connect, open the app and click **+ Add Platform** (next to **iOS App** in the
   sidebar) → **tvOS**.
2. In Xcode, set the destination to **Any tvOS Device (arm64)**, **Product → Archive**, and
   distribute the same way as step 6. The Top Shelf extension comes along automatically.
3. Fill in the **tvOS App Version 1.0** page (see the end of
   [2 Store Listing.md](2%20Store%20Listing.md)) with screenshots from `Screenshots/Final/Apple TV/`.
4. Add for Review → Submit. TV and iPhone versions are reviewed separately.

## Later · Shipping an update

1. In App Store Connect, click **+** next to **iOS App** → enter `1.1`.
2. In Xcode, set **Version** to `1.1` and bump the **Build** number in every target.
3. Archive, upload, attach the build, fill in **What's New in This Version**, submit.
4. Promotional text can be changed any time without an update. So can approved header art.
