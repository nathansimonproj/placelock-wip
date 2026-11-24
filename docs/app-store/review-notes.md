# App Review notes

> **DRAFT (2026-11-23).** For App Store Connect › the 1.0 version › App Review Information. Not entered yet. Fill in each `TODO(user)`, record the screen recording on the iPhone (script below), and check every step against a paid build on the iPhone before pasting: none of it has been tried there yet.

## App Review Information fields

| Field | Draft |
| --- | --- |
| Sign-in required | **No.** Cove has no login. Backup uses an anonymous account it makes on its own |
| Contact first and last name | Nathanael Simon |
| Contact phone | `TODO(user)` |
| Contact email | nsimon06@uw.edu |
| Notes | The text below |
| Attachment | The screen recording (script below). `TODO(user)`: record it, or upload it somewhere and put its link at the end of the notes |

## Notes (paste this)

The notes field takes up to 4,000 characters. This text is 3,413 (checked 2026-11-23 with the command at the end).

```text
Cove keeps the apps a person chooses blocked everywhere except places they save, like the gym or home. Apps unblock on their own on arriving at a saved place and block again on leaving. There is no unlock button. Cove is for managing your own phone: it asks Screen Time for individual access, not parental controls.

NO LOGIN
No account or demo login is needed. Backup makes an anonymous account on its own. In Cove, Settings > Backup > Delete account removes it and everything stored with it.

WHY ALWAYS LOCATION
Cove has to notice arriving at and leaving a saved place while it is closed, which is the whole product: apps unblock while you're at the place and block again when you go. It uses iOS region monitoring (CLMonitor) for the saved places, significant-change updates, and short one-off location fixes for lock checks and for the block screen's "Estimated @" line. It never runs continuous GPS in the background. Precise Location is needed because places can be as small as 50 m. Losing Always or Precise Location blocks apps again as soon as Cove runs, and Home explains how to fix it.

HOW TO TRY IT (needs a real iPhone; about 3 minutes)
The first 24 hours after setup are a setup window: every change applies right away, so a place added where you are works at once. After that, adding or enlarging a place and removing a blocked app wait 24 hours. Please don't tap Finish on the Setup row in the Settings tab, which ends the window early.

1. Open Cove and follow setup. Allow location, then choose Always (Settings > Cove > Location if iOS only offers While Using). Keep Precise Location on.
2. Allow Screen Time access and confirm with Face ID or the passcode.
3. Choose apps to block, for example two apps you can open easily.
4. Add a place: tap Add a place. The map starts where you are. Type a name (for example Desk) and tap Save. The default area is 150 m across.
5. Allow notifications (optional).
6. Home now says Unlocked, "at Desk for 0m". The chosen app opens normally. iOS may take a few seconds to report that you're inside.
7. To see blocking without walking away: in the Settings tab, swipe left on Desk and delete it. Removing a place only makes things stricter, so it applies at once. Home says Locked.
8. Open the blocked app. The Screen Time block screen says "<app> is locked", then roughly where you are ("Estimated @ ..."), then "Add a place in Cove to open it there.", with a Back to focus button.
9. Walking out of a saved place also blocks again. iOS reports leaving after a few minutes and 100-200 m.

THE BLOCK SCREEN NEEDS A REAL DEVICE
Screen Time's block screen (a ShieldConfiguration extension) only appears on a real iPhone, not in the Simulator. The attached screen recording shows the whole flow on a device.

THE 24-HOUR WAIT
In Cove's Settings tab, the ⓘ button ("How the 24-hour wait works") explains it. After setup, a new place shows "Starts in 24 h" until it starts working. Changes that only make things stricter (deleting a place, shrinking one, blocking another app) always apply at once. The wait is the point of the app: it stops someone from adding a place on a whim to unblock their apps.

BACKUP
Places and unlock history are backed up to our Supabase project, under the anonymous account, so a reinstall restores them and can't skip the 24-hour waits. Blocking never waits on the network. The blocked-app list and anything from Screen Time stay on the phone.

Screen recording: TODO(user)
```

## Screen recording script

Record on the iPhone with the paid build, from a fresh install, using Control Center › Screen Recording. Aim for 60–90 seconds. Keep it at a desk; deleting the place stands in for walking away. App Review needs to see the block screen, which the Simulator can't show.

Before recording: delete Cove, install the build from TestFlight, turn on Do Not Disturb (so no other notifications show), and pick two apps to block that have nothing personal on screen. Don't film other people's names or messages.

| # | Do | Shows |
| --- | --- | --- |
| 1 | Open Cove | Setup's first step, "Apps unblock where you choose" |
| 2 | Allow location, then Always (in the iOS prompt, or Settings › Cove › Location) | iOS's location prompt with Cove's purpose text, then "Location is set to Always" |
| 3 | Allow Screen Time access, confirm with Face ID or the passcode | "Screen Time access is on" |
| 4 | Choose apps: pick the two apps | "Blocking 2 apps" (pick two: with one, setup says "Blocking 1 apps"; see Roadmap Known issues) |
| 5 | Add a place: keep the map where you are, name it Desk, Save | The place in the list. "Places you add in your first 24 hours work right away." |
| 6 | Turn on notifications | iOS's notification prompt |
| 7 | Wait on Home until it says Unlocked | "Unlocked", "at Desk for 0m", "Apps block again when you leave." The "At Desk, apps unblocked." notification if it arrives |
| 8 | Open one of the blocked apps, then go back to Cove | The app opens normally |
| 9 | Settings tab: swipe left on Desk, Delete | The place goes away |
| 10 | Home | "Locked" |
| 11 | Open the same app again | The block screen: "<app> is locked", the "Estimated @" line, "Add a place in Cove to open it there.", Back to focus. Tap Back to focus |
| 12 | Settings tab: tap "How the 24-hour wait works" | The sheet that explains the wait |
| 13 | Settings › Backup | The Backup screen, with Delete account |

Then stop the recording. If step 7 takes long, trim the wait out. Attach the video in App Review Information, or upload it and replace `Screen recording: TODO(user)` in the notes with its link.

## Things to check on the iPhone before submitting

Each of these is what the notes and recording promise; none has been seen on a device yet:

- Adding a place where you already are unlocks within seconds (the Simulator scenarios only cover walking in and out).
- The block screen's exact text, including "Estimated @" right after a fresh install.
- Setup's apps step says "Blocking 2 apps" with two apps picked. With one it says "Blocking 1 apps" (`BlockList.summary` doesn't handle one), which is a bug to fix before the recording or the screenshots.
- Home's "at Desk for 0m" and the notification text.
- Deleting the active place locks at once and the block screen comes back.
- The Screen Time prompt asks for Face ID or the passcode.

## Checking the length

```sh
python3 -c "import re;t=open('docs/app-store/review-notes.md').read();n=re.search(r'\`\`\`text\n(.*?)\n\`\`\`',t,re.S).group(1);print(len(n),'/ 4000')"
```

## Sources and what's unverified

- What the app says comes from the code on 2026-11-23: setup (`Views/OnboardingView.swift`), Home (`Views/HomeView.swift`), Add place's 150 m default and Save (`Views/AddPlaceView.swift`), deleting a place (`RulesView` › `.onDelete`, then `AppModel.deletePlaces`), the lock and unlock notifications (`App/AppModel.swift`), the block screen (`Extensions/Shield/ShieldConfigurationExtension.swift`, `Shared/Brand.swift`).
- The 4,000-character limit on the notes field is from memory of App Store Connect, not checked against Apple's docs tonight.
- The backup paragraph describes backup as it works today, on from first launch (kept on, 2026-11-23). Setup's first step tells people this before they save a place.
