# TrackMyDrive

An iPhone app for logging supervised driving hours — built with SwiftUI for iOS 17+.

## Features

**Logging**
- One-tap **live drive timer** that survives the app closing, crashing or the phone restarting
- **GPS distance, speed and route map** (keeps working with the screen locked)
- **Automatic night hours** from real sunset/sunrise times at the drive's location, or a fixed clock window (with optional "30 min after sunset" rules)
- Log past drives by hand with quick length buttons, overlap/duplicate warnings and validation
- Supervisor and vehicle per drive (saved names, defaults), weather, road types, skills practiced and notes
- Search and filter the log (night, day, tracked, manual, bad weather), grouped by month
- **Recently Deleted** — deleted drives can be restored for 30 days

**Progress**
- Total and night goal rings, with presets for common US state requirements (always editable)
- Stats: weekly day/night chart, streaks, bad-weather hours, longest drive, road/weather breakdowns, skills checklist, hours per supervisor
- Projected completion date based on your recent pace
- Optional daily practice reminder

**Backups (so a lost or broken phone can't erase your hours)**
1. **Back Up to Notes** — one tap opens the share sheet with a readable text log *and* the PDF. Save it to Notes and it syncs to iCloud. The note ends with a restore block: paste the note into *Settings ▸ Restore From Backup* on any phone to get every drive back.
2. **PDF driving log** — DMV-style table with running totals and signature lines.
3. **Automatic on-device copies** — every change is written atomically with the previous version kept; a daily JSON backup, the PDF and a text copy are kept in *Files ▸ On My iPhone ▸ TrackMyDrive* (also included in iCloud/iTunes device backups). If the log file is ever damaged the app recovers from these automatically.
4. **Shortcuts automation** — the *Get Driving Log Backup* action + Notes' *Create Note* action backs up to Notes on a schedule with no taps.
5. CSV (spreadsheet) and full JSON exports.

The home screen nags you when drives haven't been backed up off the phone.

**Siri & Shortcuts:** "Start a drive in TrackMyDrive", "Stop my drive in TrackMyDrive", "How many hours do I have in TrackMyDrive".

## Running it

1. Open `TrackMyDrive.xcodeproj` in **Xcode 16 or newer**.
2. Select the **TrackMyDrive** target ▸ *Signing & Capabilities* and choose your Team (a free Apple ID works for your own phone). If Xcode complains about the bundle ID, change `com.trackmydrive.app` to something unique.
3. Pick your iPhone (or a simulator) and press **Run**.

In the simulator you can test GPS with *Features ▸ Location ▸ Freeway Drive*.

## Project layout

```
TrackMyDrive/
  App/          App entry point and tab root
  Models/       Drive, settings, live-drive state, stats
  Store/        DriveStore — persistence, live drive, backups, restore
  Services/     Night/sun calculation, location, PDF/text/CSV export, notifications
  Intents/      App Intents for Siri & Shortcuts
  Views/        Home, live drive, log, editor, stats, settings, backup, onboarding
```

> Safety: never use your phone while driving. Start the drive before pulling out and let the supervisor handle the app.
