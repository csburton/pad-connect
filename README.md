# PadConnect

An English replacement for the "Sports Show" (运动秀 / FitShow) app that controls a Chaoke X386P walking pad over Bluetooth. It runs on iPhone, Apple Watch and Mac, and saves each walk to Apple Health as an indoor walking workout, with heart rate when you wear an Apple Watch.

**Status:** first draft. The code was written without access to Xcode or the pad, so expect a round of small fixes the first time it is built and tried.

## What it does

- Finds the pad (it advertises as `FS-xxxxxx`) and reconnects to it automatically next time.
- Start, stop, speed up/down (0.1, 0.5 or 1 km/h steps) and one-tap speed presets.
- Live time, distance, active calories and steps.
- iPhone: saves the walk to Apple Health with per-minute distance and energy samples, plus steps and heart rate when the pad reports them.
- Mac: the same controls in a window, plus a menu bar item. Keyboard shortcuts: ↑/↓ change speed, space starts and stops.
- A walk starts when the belt starts moving. Tap **Finish walk** to save it, or it finishes on its own 5 minutes after the belt stops.

## Building it

You need a Mac with Xcode 15 or later.

```sh
brew install xcodegen
cd pad-connect
xcodegen          # creates PadConnect.xcodeproj from project.yml
open PadConnect.xcodeproj
```

1. In Xcode, select the **PadConnect** target, open **Signing & Capabilities** and pick your team (your Apple ID works as a free "Personal Team").
2. If Xcode says the bundle identifier is taken, change `com.csburton.padconnect` to something unique.
3. Plug in your iPhone, select it as the run destination and press Run. The first time, approve the developer profile on the phone under Settings → General → VPN & Device Management.
4. For the Mac, pick the **PadConnectMac** scheme and run it on "My Mac".

With a free Apple ID, apps installed on the phone stop launching after 7 days and need re-running from Xcode. A paid Apple Developer account removes that limit and allows TestFlight.

Run the protocol unit tests with `swift test` inside `PadKit/`.

### Trying it without the pad

The iOS Simulator has no Bluetooth, so in the Simulator the connect screen lists a **Simulated pad**. It behaves like the real one: it speeds up and slows down at about 0.5 km/h per second (including the wind-down after Stop) and makes up steps and heart rate. Finished walks save to the Simulator's Health app. On a real iPhone or Mac it never appears, and the Mac app uses the MacBook's own Bluetooth.

## Apple Watch

If you have an Apple Watch, PadConnect works like gym equipment paired to your Watch:

1. When the belt starts, the iPhone opens PadConnect on the Watch, which starts an indoor walk workout.
2. The Watch records heart rate and calories. The iPhone sends it the pad's speed and distance every second, so distance comes from the belt rather than your wrist.
3. The Watch shows time, speed, heart rate, distance and calories. Swipe up for − / +, start/stop belt and Finish.
4. Finish on either device and one workout is saved to Health from the Watch, with heart rate and the pad's distance. The iPhone shows your heart rate while you walk.

Without a Watch (or if the Watch app isn't installed) the iPhone saves the walk itself, as before.

The Watch app is installed together with the iPhone app. In Xcode, run the **PadConnect** scheme on your iPhone; if it doesn't appear on the Watch, open the Watch app on the iPhone and install PadConnect from the "Available apps" list. It uses the same signing team as the iPhone app.

## Lock Screen and Dynamic Island

While a walk is going, the iPhone shows it as a Live Activity: walking time, speed and distance on the Lock Screen, and in the Dynamic Island on iPhones that have one (time in the compact view; speed, heart rate and distance when you long-press it). Heart rate appears when an Apple Watch is recording the walk. The clock pauses when the belt stops, and when you finish, a summary stays on the Lock Screen for five minutes. Live Activities can be turned off per app in Settings › PadConnect.

## How it talks to the pad

The pad's Bluetooth module (FitShow) exposes two protocols. PadConnect uses the first and falls back to the second:

1. **FTMS** (Bluetooth Fitness Machine Service, `0x1826`), the industry standard. Live data comes from Treadmill Data (`0x2ACD`). Commands go to the Control Point (`0x2AD9`): request control, start, stop, pause and set target speed.
2. **FitShow** (`0xFFF0`, notify `0xFFF1`, write `0xFFF2`), the vendor protocol the Sports Show app uses. Packets are `02 <payload> <xor of payload> 03`. The app polls status with `51` and sends control commands with `53 xx`, for example `53 02 <speed×10> <incline>` to set the speed.

If speed changes don't work over FTMS, turn on **Use FitShow protocol** in Settings and reconnect.

The FitShow field layout comes from the reverse engineering in [qdomyos-zwift](https://github.com/cagnulein/qdomyos-zwift)'s `fitshowtreadmill` driver. No code was copied from it.

## Layout

```
PadKit/                     Swift package with all the logic, unit-tested
  FTMS.swift                FTMS parsing and commands
  FitShow.swift             FitShow framing, commands and status parsing
  WorkoutTracker.swift      Turns readings into distance, calories, steps
  WatchMessage.swift        What the iPhone and Watch send each other
  TreadmillController.swift CoreBluetooth: scan, connect, choose protocol, control
App/Shared/                 SwiftUI app shared by iPhone and Mac
App/iOS/HealthWriter.swift  Apple Health saving (no Watch)
App/iOS/WatchWorkoutLink.swift  Starts and mirrors the Watch workout
App/iOS/WalkActivityController.swift  Starts, updates and ends the Live Activity
App/LiveActivity/           Live Activity data, shared by the app and widget
App/Widgets/                Widget extension: Lock Screen and Dynamic Island views
App/watchOS/                Watch app: workout, heart rate, controls
App/macOS/                  Menu bar controls
project.yml                 XcodeGen project definition
```
