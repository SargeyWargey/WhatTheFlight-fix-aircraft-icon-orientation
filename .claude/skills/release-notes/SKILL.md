---
name: release-notes
description: Fold the notes in ReleaseNotes/unreleased/ into CHANGELOG.md for a TestFlight build and write the "What to Test" text. Use when the user asks to cut, prepare, draft or preview release notes, the changelog or What to Test for a build.
argument-hint: "[build number | preview]"
---

# Release notes for a TestFlight build

Argument: `$ARGUMENTS` (a build number, `preview`, or nothing).

Every session writes one note per tester-visible change into `ReleaseNotes/unreleased/` (format in CLAUDE.md, "Release notes"). This folds them into `CHANGELOG.md` and produces the text for TestFlight's "What to Test" box.

## 1. Work out the version

- **Marketing version**: `MARKETING_VERSION` in `WhatTheFlight/WhatTheFlight.xcodeproj/project.pbxproj` (all targets share it).
- **Build**: the argument if it's a number. Otherwise the build in the newest `## ` heading of `CHANGELOG.md`, plus one. Don't take it from `CURRENT_PROJECT_VERSION`: Xcode's upload assigns build numbers, so the project lags (it said 9 when build 10 shipped). Mention it only if it's higher than the changelog's last build.
- `preview`: do steps 2–4 and print the result, but write nothing and delete nothing.

## 2. Read the notes

Read every `ReleaseNotes/unreleased/*.md`. If there are none, say so and stop. Remember exactly which files you read: other sessions may add notes while you work, and those stay for the next build.

## 3. Merge them

Several sessions can note the same feature, and a later note can refine or undo an earlier one. Combine overlapping notes into one entry, drop anything a later note reverses, and when a note looks stale (it names a setting or screen you can't find), check the code before keeping it. Group by `kind`: New, Improved, Fixed. Order each group by how much a tester will notice it.

## 4. Write

**CHANGELOG.md**: insert a section above the previous build's (newest first), with the date as `YYYY-MM-DD`:

```markdown
## 1.0 (11) — 2026-11-02

### New
- **Sky View zoom** — pinch, or tap the 0.5× / 1× / 2× / 5× chips. *(iPhone, iPad)*

### Improved
- …

### Fixed
- …
```

Leave out empty groups and the platform tag when an entry applies everywhere.

**TestFlight text**: plain text (TestFlight shows Markdown symbols literally), at most 4,000 characters. Start with one line naming the two or three biggest changes, then `New`, `Improved` and `Fixed` sections with `•` bullets, then `Please try:` built from the notes' `Try:` lines. Save it as `ReleaseNotes/testflight/<version>-<build>.txt` and copy it to the clipboard with `pbcopy`.

## 5. Clean up and report

Delete the note files you read in step 2 (`git rm` for tracked ones, `rm` for the rest), and only those. Don't commit unless the user asks. Report the version and build, how many notes went in, the changelog section, and say the TestFlight text is on the clipboard.
