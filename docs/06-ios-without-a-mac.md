# 06 — Shipping iOS Without a Mac

You have no Apple hardware. This is a solved problem for *building*, and an
unsolved problem for *testing*. Be clear on which is which.

> Policies, prices, and tool capabilities in this document change often. Verify
> each against the official source before you rely on it.

## The short version

| Need | Do you need a Mac? |
|---|---|
| Write the code | No — Linux is fine |
| Compile the iOS app | **No** — cloud CI runs macOS for you |
| Sign the app | No — CI handles certificates |
| Upload to App Store Connect | No — CI does it with an API key |
| Manage the store listing, TestFlight, review | No — all web-based |
| Use the iOS Simulator | Yes (or a cloud Mac) — but the simulator is nearly useless for an alarm app |
| **Test an alarm on real hardware** | **No Mac needed — but you MUST have a physical iPhone** |

## Step 1 — Buy a used iPhone. Non-negotiable.

You cannot ship an alarm clock you have never heard ring. The simulator does not
model the silent switch, Do Not Disturb, Focus modes, Low Power Mode,
lock-screen alert presentation, or real audio routing — which is precisely the
list of things that break alarm apps.

- Buy a **used iPhone that supports your minimum iOS version** (doc 09 sets iOS 26).
  A second-hand iPhone 12 or 13 is typically €150–250 and is plenty.
- You do **not** need a Mac to install builds on it: TestFlight installs over the
  air from the App Store.
- Budget this as a mandatory tool cost, alongside the €90/yr developer fee.

Also acquire, or borrow: one cheap **Xiaomi or Samsung** Android device, for the
OEM battery-killer testing in doc 04.

## Step 2 — Apple Developer Program enrollment

- **Cost:** ~$99 USD / year (local equivalent).
- Enroll at `developer.apple.com/programs`, signing in with an Apple Account that
  has **two-factor authentication** enabled.
- You can enroll as an **Individual** (fastest — your legal name becomes the
  seller name shown on the store) or as an **Organization** (requires a registered
  legal entity and a **D-U-N-S number**, which is free but takes days to weeks to obtain).
- **Recommendation:** if you want a company name on the listing, start the D-U-N-S
  request *today*, because it is the longest-lead item in this entire project.
  Otherwise enroll as an Individual and move on — you can migrate later, with effort.
- Enrollment itself can be done from a browser on Linux. Apple may require identity
  verification; recent enrollments sometimes ask you to verify through the Apple
  Developer app on an iOS device — another reason to buy the iPhone first.

## Step 3 — Pick your cloud build service

You need a macOS build machine. Options:

| Service | Fit |
|---|---|
| **Codemagic** | **Recommended.** Purpose-built for Flutter, generous free tier, handles code signing and App Store Connect upload with minimal YAML. |
| GitHub Actions (`macos-latest`) | Free-ish for public repos, cheap for private. More YAML, you manage signing yourself with `fastlane match`. |
| Bitrise | Powerful, steeper learning curve. |
| Expo EAS | Excellent, but React Native oriented — not your stack. |
| Rented cloud Mac (MacStadium, MacinCloud, Scaleway M1) | The escape hatch when you need a real Xcode GUI to debug a signing problem. Rent by the hour, don't subscribe. |

Start with Codemagic. Keep a rented-cloud-Mac provider in mind as the fallback for
the one afternoon you inevitably need Xcode itself.

## Step 4 — Code signing without a Mac

This is the part people fear. It is mechanical.

1. In **App Store Connect → Users and Access → Integrations**, create an
   **App Store Connect API Key** (Issuer ID, Key ID, and a `.p8` file). This
   replaces password-based auth and works from any OS.
2. Generate a certificate signing request and distribution certificate. On Linux
   you can do this with `openssl`, or let **Codemagic's automatic code signing**
   create and manage the certificate and provisioning profile for you using that
   API key. **Use the automatic path.** Manual signing is where days disappear.
3. Register your App ID / bundle identifier (e.g. `com.yourname.duet`) in the
   Developer portal — or let the CI create it.
4. Add capabilities the app needs: **Push Notifications**, **Sign in with Apple**,
   **In-App Purchase**, and whatever AlarmKit requires.

Everything above is doable in a browser plus a CI config file.

## Step 5 — The build/test loop you will actually live in

```
edit code on Linux
      │
      ├─▶ flutter run  ──▶ Android device on your desk     (fast, seconds)
      │
      └─▶ git push ──▶ Codemagic ──▶ macOS build ──▶ TestFlight
                                                       │
                                        install on your iPhone (minutes)
```

Your iteration speed on Android is normal. Your iOS loop is **10–25 minutes per
build**, so batch iOS work: develop features on Android, then do focused iOS
verification passes.

Practical consequences for how you write the code:
- Keep platform-specific code behind the narrow engine interface in doc 02, so
  95% of your work is testable on Android and Linux.
- Write the Swift side carefully the first time; you cannot casually poke at it.
- Add generous logging in the iOS engine and ship logs to Sentry — printf
  debugging via crash reports is your reality without Xcode's debugger.
- Budget one rented cloud-Mac session for the first successful iOS build. Getting
  build #1 green is the hardest one.

## Step 6 — TestFlight

- Upload a build from CI; it appears in App Store Connect.
- **Internal testing:** up to 100 users on your team, no review, available in minutes.
- **External testing:** up to 10,000 users, requires a lightweight Beta App Review
  (usually a day or so).
- Builds expire after 90 days.
- This is how you get the app onto your own iPhone and onto friends' phones. You
  will never need Xcode to install a build.

## Honest assessment of the difficulty

Building and shipping iOS from Linux: **a solved, well-trodden problem.** Expect
one frustrating week for the initial pipeline, then it is routine.

Debugging iOS-specific alarm behavior without Xcode: **genuinely harder.** No
breakpoints, no Instruments, no device console. Your countermeasures are heavy
logging, a real device, and keeping the native surface tiny.

If you find yourself losing more than a few days to iOS debugging, rent a cloud
Mac for a day rather than suffering. It is roughly the price of a meal.

## Cost summary (year one)

| Item | Cost |
|---|---|
| Apple Developer Program | ~$99 / yr |
| Google Play Developer | $25 one-time |
| Used iPhone (iOS 26-capable) | ~$180–280 |
| Cheap Xiaomi/Samsung test device | ~$100–150 |
| Codemagic | Free tier, likely sufficient |
| Supabase | Free tier, then ~$25/mo |
| RevenueCat | Free at your scale |
| Domain + privacy policy hosting | ~$15 / yr |
| Occasional rented cloud Mac | ~$5–30 as needed |
| **Total to get to launch** | **≈ $450–600** |
