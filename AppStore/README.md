# App Store submission kit

Everything needed to get What The Flight? 1.0 onto the App Store: the text to paste, the
answers to Apple's questionnaires, a privacy policy and support site, and the screenshots.

| File | What it's for |
|---|---|
| [1 Submission Guide.md](1%20Submission%20Guide.md) | Step-by-step, first time through. Start here. |
| [2 Store Listing.md](2%20Store%20Listing.md) | Copy-and-paste text for every field on the store pages |
| [3 Privacy and Review.md](3%20Privacy%20and%20Review.md) | App Privacy, age rating, content rights, notes for the reviewer |
| `Open Asset Studio.command` | Double-click to review captions and save the screenshots |
| `Screenshots/Raw/` | Plain captures from the simulators (the studio's source material) |
| `Screenshots/Final/` | Finished screenshots, ready to drag into App Store Connect |
| `Header Art/` | Optional header and search-result artwork |
| [`../Website/`](../Website/) | The app's website, with the privacy policy and support pages (its own git repository, published on GitHub Pages). `AppStore/Website/` is an outdated copy |

## Checklist

- [ ] Decide on the flight data source (below)
- [ ] Put your support email into `Website/support.html`, `privacy.html` and `press.html`
- [ ] Publish the website (guide step 3)
- [ ] App Information, Pricing, App Privacy, Age Rating (guide step 4)
- [ ] Deploy the CloudKit schema to Production (guide step 5)
- [ ] Archive and upload the build (guide step 6)
- [ ] Try the build through TestFlight (guide step 7)
- [ ] Save the screenshots in the Asset Studio and upload them (guide step 8)
- [ ] Fill in the version page and submit (guide step 8)
- [ ] Release when approved (guide step 10)

Three things only you can fill in: your **support email** (on the website), your **contact
details** for App Review (only Apple sees them), and the **copyright name**, which must match
the legal name on your developer account.

## Decide first: the flight data

Every aircraft in the app comes from Flightradar24's private web feed
(`data-cloud.flightradar24.com/zones/fcgi/feed.js`), fetched with a Safari User-Agent.
Flightradar24 doesn't license that feed to apps, and its terms forbid automated access. That
matters three ways:

1. **App Review guideline 5.2.2** requires permission from any service whose content you show.
   A reviewer who notices can reject the app until you provide it.
2. **Content Rights:** App Store Connect asks you to confirm you have the rights to third-party
   content. Without a licence, you can't honestly tick that box for Flightradar24.
3. **After launch:** Flightradar24 can report the app to Apple, or block the feed. Either way
   the app goes blank for everyone, and reviews follow.

Your options:

- **License it.** Flightradar24 sells an official API (fr24api.flightradar24.com) with a monthly
  subscription. The app reads flights through one protocol (`FlightFeed` in
  `Services/FlightFeed.swift`), so switching sources is contained to that file plus its parser.
- **Use a different licensed source.** Several ADS-B networks offer APIs. Check that each
  one's terms allow use in a public app.
- **Submit as it is.** It may pass review, but you'd be ticking the rights box without the rights
  and accepting that the app can break or be pulled at any time.

I'd sort this out before submitting. Everything else in this folder works whichever source you
choose, except the "About the data" line in the description and the credits on the website.

## The Asset Studio

1. Double-click **Open Asset Studio.command**. A Terminal window opens (leave it open) and the
   studio opens in your browser. If macOS refuses to open it, right-click it → **Open**.
2. Each tab is one row of App Store Connect: iPhone, iPad, Apple Watch, Apple TV, and the
   optional header art. The chips at the top show which slots are ready.
3. Change any caption, pick a different screenshot, switch the look (Paper, Night, Teal),
   reorder with the arrows, or leave a frame out. Edits are remembered in your browser;
   **Reset edits** goes back to the originals.
4. Click **Save all**. Every PNG is written into `Screenshots/Final/` and `Header Art/` at the
   exact pixel size Apple wants, without the alpha channel Apple rejects. **Save PNG** on a card
   saves just that one.
5. Drag the files from those folders into App Store Connect, in their numbered order.

There's also a private online copy at https://claude.ai/artifact/DmXRksJTcw7Meuou2HDCxm. It
works the same way, except that saves download to your computer instead of landing in the repo.

To retake the raw screenshots from the simulators, see `Screenshots/Raw/captures.json` for what
each one shows. They were taken at Central Park, New York, with live traffic, the status bar
set to 9:41, and these launch arguments: `-wtf.hasSeenWelcome YES -wtf.showHelicopters NO
-wtf.iCloudLogbook NO`, plus `-wtf.debugSheet …` / `-wtf.debugScreen …` for each screen.
Frames that show a Planespotters photo are left out by default, because those photos belong
to their photographers.

## Found while capturing the screenshots

Worth checking before you submit:

- **Crash on launch in `LogbookSync.start` → `CKContainer(identifier:)`**, seen once in the
  iPhone simulator (Oct 23, 17:21). Try the TestFlight build with iCloud signed out and with
  iCloud signed in.
- **Apple TV logbook:** the record tiles show Planespotters photos with no photographer credit.
  Planespotters requires the credit, so fix this before the Apple TV submission.
- **Apple TV, Simulator only:** four crashes in `TopographyRenderer` (Metal texture-descriptor
  validation). Probably Simulator-specific, but check it on a real Apple TV.

Cosmetic, seen in the screenshots:

- Search and logbook rows cut aircraft type names short ("Boei…", "Bomb…").
- In the logbook, the floating search field covers the third Records row.
- The Sky View photo card's Share button is cut off at the bottom of the screen.
- The detail sheet's Nearby map is sometimes off-centre.
- On iPad, the radar hero puts Altitude and Speed on one row with Distance alone below it. There's
  also a stray arc beside the settings button, and the Topography sheet cuts off its Motion row.
- On Apple TV, the dock hides the mile labels along the bottom edge, and map labels overlap at a
  20-mile range.
- In Apple Watch Find, the green arm pointer covers the 0° label.
