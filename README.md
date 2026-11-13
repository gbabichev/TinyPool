# Tiny Pool

**Pull back. Let go. Pot the lot.**

A quick, friendly top-down pool game for iPhone, iPad and Mac. No ads, no purchases, no accounts, and it works fully offline.

### 👉 [gbabichev.github.io/TinyPool](https://gbabichev.github.io/TinyPool/)

Screenshots, how it works, support and the privacy policy are all on the website.

## The games

- **Pot Points**: any ball goes, every ball is a point, and the black 8 is worth three.
- **Classic 8-Ball**: solids or stripes, then the black 8, with fouls and ball in hand.
- **9-Ball**: hit the lowest ball first, and pot the 9 to win.
- **Timed**: sixty seconds, pot as many as you can.

Play **Practice** on your own, take on the **computer** (Beginner, Intermediate or Expert), or share one screen in **Versus** with up to four players.

## Requirements

iOS 18, iPadOS 18 or macOS 15 or later.

## Building

Open `Tiny Pool.xcodeproj` in Xcode and run the **Tiny Pool** scheme, or from the command line:

```bash
xcodebuild -project "Tiny Pool.xcodeproj" -scheme "Tiny Pool" -destination 'platform=macOS' build
```

`Tools/Bench/run.sh` times the aim hint and the physics step, in an optimised and an unoptimised build.

## Support and privacy

Questions, bugs and ideas: [open an issue](https://github.com/gbabichev/TinyPool/issues). Tiny Pool collects no data; see the [privacy policy](https://gbabichev.github.io/TinyPool/PrivacyPolicy.html).

© 2026 George Babichev
