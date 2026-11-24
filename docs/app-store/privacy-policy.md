# Cove privacy policy (source)

> **Published 2026-11-23** at https://nathansimonproj.github.io/cove/privacy/ (repo `nathansimonproj/cove`, GitHub Pages). Written from [data-inventory.md](data-inventory.md) (checked against the code at commit 4a52129).
>
> - The Supabase facts (region, 1-day logs, no backups) were checked 2026-11-23 for the **Free plan**. On Pro, logs are kept 7 days and backups 7 days: update "Backup" and "How long we keep it" if you upgrade.
> - It describes the app as it is today: **backup is on from first launch**, and setup's first step says so (decided 2026-11-23). If that ever changes (opt-in backup, or no `address`), update "Backup" and "What we collect".
> - It's plain language, not legal advice. If you expect users in places with specific privacy laws (the EU, the UK, California), have it checked against those.
> - The same text is in [`docs/privacy/index.html`](../privacy/index.html). After any change, update both, change the effective date, and copy the HTML to the `cove` repo's `privacy/index.html`.

---

# Cove privacy policy

Effective date: November 23, 2026

Cove blocks the apps you choose everywhere except at places you save. This page says what Cove keeps on your iPhone, what it sends off it, and how to delete it.

Cove is made by Nathanael Simon.

## The short version

- Cove works out where you are on your iPhone. Your live location is never sent to us.
- Your saved places and unlock history are backed up to our server under an anonymous account. There's no sign-in, and we never ask for your name, email or phone number.
- The apps you block stay on your iPhone. Cove never sends that list anywhere.
- No ads, no analytics, no tracking, and we don't sell or share your data.
- You can delete everything we have at any time: in Cove, open Settings › Backup › Delete account.

## What stays on your iPhone

- **Your location.** iOS tells Cove when you arrive at or leave one of your places, and Cove checks your location to decide whether apps unblock. This happens on your iPhone. Your live location isn't sent to our server.
- **Your blocked apps.** You pick them in Apple's Screen Time picker. Cove gets only Apple's codes for them, keeps them on your iPhone and hands them to Screen Time. They're never backed up or logged.
- **Your places, settings and visit list.** These are saved on your iPhone. Places and unlock history are also backed up (see below).
- **Notifications.** All of Cove's notifications ("At Gym, apps unblocked.") are made on your iPhone. Nothing goes through a push server.

## Backup: what we collect and why

When you first open Cove, it creates an anonymous account and starts backing up. This is so a reinstall brings back your places and history, and doesn't hand you a fresh day with no 24-hour waits.

We store, linked to that anonymous account:

- **An account ID.** A random ID made when the account is created. It isn't made from your name, email, phone number, Apple ID or any device identifier.
- **Your saved places.** Each place's name (what you typed or picked), its address from Apple Maps if it has one, its exact center and its size. If a change to a place is waiting out its 24 hours, the new center and size too.
- **Your unlock history.** For each time apps unblocked: which place, when they unblocked, when they blocked again, and why (for example, you left).
- **Timing for the rules.** When your first 24-hour setup window ends, when each place starts working, when places were deleted, and when each item was last changed.

Together, your places and unlock history show when you were at each of your saved places. We use this only to back up and restore Cove on your phone. We don't use it for anything else.

Like any internet service, our server also sees your phone's IP address and basic connection details (such as the app and iOS version) when Cove connects. Supabase's request logs record that IP address with your anonymous account ID, and are deleted after 1 day.

## Where it's stored

Backups are stored with Supabase, a database hosting company, in the eastern United States (North Virginia). Supabase stores the data for us. Data is sent over an encrypted (HTTPS) connection, and each account can read and change only its own data.

## Apple services Cove uses

Some features ask Apple for information. These requests don't include your Cove account ID, and Apple handles them under [Apple's privacy policy](https://www.apple.com/legal/privacy/):

- **Place search.** When you search for a place to add, the text you type and the area around you go to Apple Maps, so nearby results come first.
- **The map.** Apple Maps loads the map area you're looking at when you add or edit a place.
- **"Estimated @" on the block screen.** While apps are blocked, Cove sends your current location to Apple Maps (at most once a minute while Cove is open, every 5 minutes in the background) to get a nearby place name to show on the block screen.
- **Crash reports.** If you've chosen to share analytics with app developers in iOS Settings, Apple may send us crash reports. Cove has no crash reporting or analytics of its own.

## What we don't do

- No ads, analytics, tracking or advertising IDs.
- We don't sell your data, share it with data brokers or use it to profile you.
- We don't collect which apps you have or which ones you block.
- We don't ask for your name, email, phone number or contacts.

## How long we keep it

Your backup stays until you delete your account. Our hosting plan doesn't keep separate database backups, so when you delete your account, your data is gone from our server straight away. Only the request logs above can still hold your IP address and account ID, for up to 1 day. Places you delete in the app are kept in the backup, marked as deleted, so a reinstall doesn't bring them back; they're removed for good when you delete your account.

If you delete Cove from your iPhone without deleting your account first, the backup stays on our server. iOS keeps Cove's sign-in on the iPhone, so reinstalling Cove on the same iPhone reconnects to the same account, and you can delete it from there.

## Deleting your data

- **Everything on our server:** in Cove, open Settings › Backup › Delete account. This permanently deletes your account, your backed-up places and your unlock history straight away, and turns backup off. Your places and blocked apps stay on your iPhone, and blocking keeps working. You can turn backup back on later; it starts a new account.
- **Everything on your iPhone:** delete Cove from your iPhone. iOS keeps only Cove's anonymous sign-in, so a reinstall can reconnect to your backup.
- **Location access:** you can turn it off any time in iOS Settings › Privacy & Security › Location Services › Cove. Without it, Cove keeps your apps blocked, because it can't tell that you're at one of your places.

Because the account is anonymous, we can't look it up by your name or email. Delete account in the app is the way to remove it. If that doesn't work for you, email us (below) and we'll help.

## Children

Cove isn't directed at children under 13, and we don't knowingly collect their data. If you think a child has used Cove, contact us and we'll delete the account.

## Changes to this policy

If what Cove collects changes, we'll update this page and its effective date before the new version of the app is released.

## Contact

Questions or requests: nsimon06@uw.edu
