// The studio's starting plan: which capture goes in each slot, in upload order, with its caption.
// Edits made in the studio are kept in the browser; "Reset edits" comes back to this.
// Frames with `include: false` are left out of the export: alternates, and every frame that shows
// a Planespotters photo (those belong to their photographers, so keep them out of marketing).
window.STUDIO = {
  version: "1",
  base: "../Screenshots/Raw/",
  raw: {},
  plan: {
    iphone: [
      { src: "01-radar-light.png", eyebrow: "Live radar", headline: "Every plane around you, live", look: "paper" },
      { src: "04-route-map.png", eyebrow: "The full story", headline: "Where it's from, where it's going", look: "paper" },
      { src: "09-spot-card.png", eyebrow: "Sky View", headline: "Snap a plane, keep the boarding pass", look: "paper" },
      { src: "02-radar-dark.png", eyebrow: "Heads up", headline: "Know what's about to fly over you", look: "night" },
      { src: "05-logbook.png", eyebrow: "Logbook", headline: "Every plane you see, logged", look: "paper" },
      { src: "06-badge.png", eyebrow: "Badges", headline: "Spot more, unlock more", look: "paper" },
      { src: "07-search.png", eyebrow: "Find any aircraft", headline: "Search any flight on Earth and pin it", look: "paper" },
      { src: "08-topography.png", eyebrow: "Make it yours", headline: "Topographic backdrops that drift like the tide", look: "paper" },
      { src: "10-app-icons.png", eyebrow: "Ten icons", headline: "Pick the one that suits you", look: "paper" },
      { src: "03-detail.png", eyebrow: "The full story", headline: "Tap the center for every detail", look: "paper", include: false },
      { src: "03-detail-b.png", eyebrow: "The full story", headline: "A photo of that exact plane", look: "paper", include: false },
    ],
    ipad: [
      { src: "01-radar-light.png", eyebrow: "Live radar", headline: "Every plane around you, live", look: "paper" },
      { src: "03-detail-route.png", eyebrow: "The full story", headline: "Where it's from, where it's going", look: "paper" },
      { src: "02-radar-dark.png", eyebrow: "Notable traffic", headline: "Catch the rare ones, like this 747", look: "night" },
      { src: "04-logbook.png", eyebrow: "Logbook", headline: "Every plane you see, logged", look: "paper" },
      { src: "05-search.png", eyebrow: "Find any aircraft", headline: "Search any flight on Earth", look: "paper" },
      { src: "06-topography.png", eyebrow: "Make it yours", headline: "Topographic backdrops that drift like the tide", look: "paper" },
      { src: "07-detail-photo.png", eyebrow: "The full story", headline: "A photo of that exact plane", look: "night", include: false },
    ],
    watch: [
      { src: "01-radar.png" },
      { src: "03-identify.png" },
      { src: "04-find.png" },
      { src: "02-detail.png" },
      { src: "05-nearby.png" },
    ],
    tv: [
      { src: "01-radar.png" },
      { src: "02-split.png" },
      { src: "03-map.png" },
      { src: "05-dock.png" },
      { src: "04-detail.png", include: false },
      { src: "06-logbook.png", include: false },
    ],
    header: { eyebrow: "What The Flight?", headline: "What's that\nplane?", sub: "", look: "teal", mark: false },
  },
};
