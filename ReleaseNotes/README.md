# Release notes

- `unreleased/`: one small file per tester-visible change since the last TestFlight build. Claude sessions write these as they work (the rule and format are in `CLAUDE.md`, "Release notes"). You can add or edit one by hand too.
- `testflight/`: the plain-text "What to Test" for each build, as pasted into TestFlight.
- `../CHANGELOG.md`: the full history, one section per build.

When a build goes out, run `/release-notes` (or `/release-notes 12` to name the build) in Claude Code. It merges the notes into `CHANGELOG.md`, writes the TestFlight text and copies it to the clipboard, then deletes the notes it used. `/release-notes preview` shows the draft without changing anything.
