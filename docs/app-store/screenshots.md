# App Store screenshots

`PlaceLock/scripts/app-store-screens.sh` builds the free Debug app and screenshots it on the "iPhone 17 Pro Max" Simulator. Every shot is 1320 × 2868, Apple's 6.9" iPhone size; one 6.9" set is enough, and App Store Connect scales it for smaller iPhones.

```sh
PlaceLock/scripts/app-store-screens.sh                  # into PlaceLock/build/app-store-screens
PlaceLock/scripts/app-store-screens.sh ~/Desktop/shots  # or anywhere else
```

It runs in scenario mode, so backup is off and nothing reaches the live Supabase project. It reinstalls Cove on that Simulator, so anything saved there is wiped. The status bar reads 9:41 with full battery and signal.

| File | Screen |
| --- | --- |
| `1-home-locked.png` | Home, locked for 1 h 36 m, 4 apps resting |
| `2-home-unlocked.png` | Home, unlocked at Library for 42 m |
| `3-settings.png` | Settings: blocked apps and places |
| `4-add-place.png` | Add place: map and radius |
| `5-wait-info.png` | The 24-hour wait sheet |
| `6-setup-location.png`, `6-setup-apps.png`, `6-setup-places.png` | First-run setup steps (pick one or two) |

Demo data: places Home (100 m), Library (100 Larkin St, 150 m) and Gym (100 m) in San Francisco, 4 blocked apps, two earlier visits today, setup ended 3 days ago. It's all in the script.

## Before using them

- **Blocked apps show stand-in icons.** The free build lists apps by name with plain symbols (a camera for Instagram). The paid build shows real icons from Apple's picker. Retake Home and Settings from the paid build on the iPhone (side button + volume up), or decide whether other apps' names belong in the screenshots at all: App Review guidelines 2.3.7 (other apps' names in metadata) and 5.2.1 (others' trademarks) may apply.
- **The block screen needs the paid build on the iPhone.** The Simulator can't show Screen Time's real block screen.
- **`3-settings.png` shows the Debug row faintly under the tab bar.** It's only in Debug builds. Crop it, or retake from the paid build.
- **No captions or frames.** Apple accepts plain screenshots; any marketing text on top is still to do.
- Upload: App Store Connect › the version page › Previews and Screenshots › iPhone 6.9" Display, 3–10 shots.
