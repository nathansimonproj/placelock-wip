# Age rating answers

> **DRAFT (2026-11-23).** Answers for App Store Connect › the app › App Information › Age Rating › Edit. Not entered yet. Expected result: **4+**.

Apple changed the questionnaire in 2025 (new 13+, 16+ and 18+ ratings and new sections), added social media questions in 2026 (required since September 2026), and added two more declarations on 2026-11-16 (Shared Location, and Dating and Relationships). All of them are below. If App Store Connect shows a question that isn't here, answer it from what Spots does: a solo focus tool with no content, no other people and no web browsing.

## In-App Controls

| Item | Answer | Why |
| --- | --- | --- |
| Parental Controls | **No** | Spots is for managing your own phone. It asks Screen Time for individual access (`requestAuthorization(for: .individual)`), not a parent's control over a child's device |
| Age Assurance | **No** | Spots doesn't check anyone's age |

## Capabilities

| Item | Answer | Why |
| --- | --- | --- |
| Unrestricted Web Access | **No** | No browser or web view in the app. The About links open Safari, outside the app |
| User-Generated Content | **No** | Place names are typed by the user for themselves and never shown to anyone else |
| Social Media | **No** | No feed, no sharing, no other users |
| Messaging and Chat | **No** | None |
| Shared Location | **No** | Apple: "Sharing of real-world location with another person or group." Spots shares location with no one. Backup keeps saved places on Spots' server under the user's own anonymous account, which nobody else can read (row-level security). The block screen shows the estimate only to the user |
| Advertising | **No** | No ads |

## Mature Themes

| Item | Answer |
| --- | --- |
| Profanity or Crude Humor | **None** |
| Horror/Fear Themes | **None** |
| Alcohol, Tobacco, or Drug Use or References | **None** |
| Dating and Relationships | **No** |

## Medical or Wellness

| Item | Answer | Why |
| --- | --- | --- |
| Medical or Treatment Information | **None** | No medical content |
| Health or Wellness Topics | **No** (your call) | Spots blocks distracting apps by place. It has no health or wellness content: no advice, no mood or sleep tracking, no wording about mental health. This item would make it 9+. If you later add copy about "digital wellbeing" or mental health, revisit it. `TODO(user)`: confirm |

## Sexuality or Nudity

| Item | Answer |
| --- | --- |
| Mature or Suggestive Themes | **None** |
| Sexual Content or Nudity | **None** |
| Graphic Sexual Content and Nudity | **None** |

## Violence

| Item | Answer |
| --- | --- |
| Cartoon or Fantasy Violence | **None** |
| Realistic Violence | **None** |
| Prolonged Graphic or Sadistic Realistic Violence | **None** |
| Guns or Other Weapons | **None** |

## Chance-Based Activities

| Item | Answer |
| --- | --- |
| Gambling | **No** |
| Simulated Gambling | **None** |
| Contests | **None** |
| Loot Boxes | **No** |

## Other settings on the same screen

| Setting | Answer | Why |
| --- | --- | --- |
| Made for Kids | **No** | Not designed for children; it's a self-control tool for the phone's owner |
| Higher age rating than calculated | **No** (your call) | Nothing in the app needs it. Pick a higher one only if you want to keep Spots from younger users |

## Expected result

4+ in every region. Every item that could raise the rating is No or None. Brazil gives Shared Location an A16 rating, which doesn't apply here because Spots answers No.

## Sources and what's unverified

- App Store Connect Help, "Age ratings values and definitions" (https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions), read 2026-11-23. Only part of the page could be read word for word. The item list and which rating each item leads to came from a summary of the rest, so check the item names on screen.
- Apple Developer News, "Upcoming: New age rating content descriptors in App Store Connect" (https://developer.apple.com/news/?id=yxkh08us, 2026-11-02): Shared Location and Dating and Relationships from 2026-11-16, required for every app by 2027-01-12.
- Apple Developer News, "Age rating questionnaire now includes social media questions" (https://developer.apple.com/news?id=tlur8uvi, 2026-07-09): social media is "the ability to redistribute, amplify, or interact with user-generated content through a social feed or similar discovery method". Answers required since September 2026.
- Apple Developer News, "Updated age ratings in App Store Connect" (https://developer.apple.com/news/?id=ks775ehf, 2025): the In-App Controls, Capabilities, Medical or Wellness and violent themes questions.

Not verified: the exact on-screen question wording and answer menus (the help page lists items and definitions, not the form), and whether App Store Connect counts a focus app as a "Health or Wellness Topic". Apple's definition of that item wasn't on the part of the page read word for word.
