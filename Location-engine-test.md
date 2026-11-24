# Testing the new location engine on the iPhone

Written 2026-11-23. A 3-day test of the new location engine in shadow mode (2026-11-24 to 2026-11-26), then 1–2 days with it deciding. What the engine does is in [Roadmap.md](Roadmap.md) ("New location logic, in shadow mode").

In shadow mode the current logic still blocks and unblocks. The new engine tracks location and records what it would have done. Nothing about blocking changes for you, but battery use near your places goes up, because the engine really tracks.

## Before day 1 (about 10 minutes)

1. **Install a Debug build from Xcode.** The recorder only exists in Debug builds. TestFlight and Release builds record nothing.
   - In `PlaceLock/`, run `xcodegen generate --spec project-paid.yml`.
   - Open `PlaceLock.xcodeproj`, pick your iPhone and run. The app keeps working after you unplug.
2. **Check permissions.** Settings › Cove › Location: Always, with Precise Location on.
3. **Reset the recorder.** In Cove › Settings › Debug › Location engine:
   - Check that "Decides" says **Current (engine in shadow)**.
   - Tap **Clear location trace**.
4. **Note the battery.** Settings › Battery: Cove's share of the last 24 hours.
5. **Start a note** for times, using the log below.

## Every day

- **Arriving at a place, with Cove closed** (swiped to the home screen, not force-quit):
  - Note when you walk in.
  - Note whether apps unblocked, and when.
- **Leaving:** note when you step outside, and when apps blocked.
- **Now and then after arriving,** open Debug › Location engine. It shows what the engine thinks of each place, like "Gym: inside (accurateFixInside)". If apps are still blocked but the engine says inside, note it: that's the old bug, and the engine would have fixed it.
- **At home in the evening:** apps should never block. Check Home's state in the Debug screen once or twice.
- **While Cove is closed:** look at the status bar. Note it if a blue location pill ever shows. It shouldn't.
- **At the end of the day:** note Cove's battery share (Settings › Battery, last 24 hours).

## Once during the 3 days

- **Force-quit, then arrive:** swipe Cove up in the app switcher, then walk into a place. Note whether apps unblock, and when.
- **Your smallest place:** stay a while and move around inside. This shows whether walking around starts too many GPS bursts.
- **Low Power Mode:** turn it on for part of one day. Note whether arriving and leaving still work, and how late.

## Log

| Date | Place | Arrived | Apps unblocked | Left | Apps blocked | Cove closed or force-quit | Notes |
|---|---|---|---|---|---|---|---|
| 2026-11-24 | | | | | | | |
| | | | | | | | |
| 2026-11-25 | | | | | | | |
| | | | | | | | |
| 2026-11-26 | | | | | | | |
| | | | | | | | |

| Date | Cove battery (last 24 h) | Blue pill seen? | Low Power Mode on? |
|---|---|---|---|
| Before | | | |
| 2026-11-24 | | | |
| 2026-11-25 | | | |
| 2026-11-26 | | | |

## After day 3

1. In Debug › Location engine, tap **Export location trace** and AirDrop it to your Mac. The file holds your real coordinates, so don't post it anywhere public.
2. Send Claude the file's path, this log and the battery numbers.
3. Claude will:
   - Compare the engine's unblock and block times with the current logic's and with your notes.
   - Look for bad indoor fixes, GPS bursts at your smallest place, and battery use.
   - Check whether tracking started from a background wake.
   - Turn the trace into replay tests and tune the thresholds.

## Then: the new engine decides (1–2 days)

1. In Debug › Location engine, switch "Decides" to **New engine**. Blocking and unblocking now follow it.
2. Do the same daily checks. You're aiming for:
   - Unblocking within about 30 seconds of walking in.
   - Blocking within about a minute of leaving.
   - Never blocking at home.
3. If anything goes wrong, switch back to **Current**. It applies at once.
4. Export the trace again at the end. If it holds up, the new engine becomes the default.

## Optional: watch it live

Plug the phone into your Mac and open Console. Pick your iPhone and filter on `subsystem:com.nsimon.PlaceLock`:
- Search **Shadow:** to see each moment the engine would have unblocked or blocked, next to what Cove really did.
- Search **Engine:** to see each place's state change and why.
