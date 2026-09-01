<div align="center">

# SingleSense 🎮

**Make your DualSense yours — straight from your Mac.**

Colours, triggers, rumble, even the controller's touchpad.
No PlayStation required.

</div>

---

## What you can do

### 🌈 The light bar, your way

Pick a solid colour, let it breathe slowly, or run a rainbow at 60 frames per second. There are ready-made palettes (PlayStation blue, cyberpunk cyan, neon magenta, gold) and a hex field too, if you already know the exact shade you want.

Two automatic modes that earn their keep day to day:

- **Battery gauge** — the light shifts green to red as the charge drops, and pulses when it's nearly out
- **Trigger reactive** — the colour follows how hard you squeeze L2 or R2

### 🎵 Sync with your music

Turn on **Music Sync** and the controller follows whatever your Mac is playing — Spotify, Apple Music, a browser tab, a game. The source doesn't matter.

| Style | How it looks |
|---|---|
| **Spectrum** | Red on bass, green on mids, blue on treble |
| **Colour Pulse** | Your chosen colour breathing with the volume |
| **Hue Sweep** | Bass-heavy music runs warm, bright music runs cool |
| **Beat Flash** | Dark between beats, lighting up on each one |

The **five player LEDs** join in as a meter — filling from the left, growing outward from the centre, or flashing on the beat.

And if you want to *feel* the music, switch on **rumble**: bass goes to the heavy motor on the left, treble to the light one on the right. It ships off, because continuous rumble drains the battery noticeably faster.

> The first time, macOS will ask for **Screen Recording** permission. That's how the system lets an app listen to audio — no video is captured or stored.

### 🎯 Adaptive triggers

The best part of the DualSense. Build whatever feel you want:

- **Rigid resistance** — a wall starting wherever you choose
- **Weapon** — slack at first, then resistance, then a crisp break
- **Vibration** — the trigger buzzes, with adjustable frequency and strength
- **Slope** — resistance builds as you press deeper
- **Machine gun** — rapid recoil pulses
- **10-zone curve** — a graph where you draw the resistance point by point

There are presets to get going quickly: Desert Eagle, sniper rifle, shotgun, bow and arrow, ABS brake, mechanical mouse click.

And the **Dyno Test**: hold a trigger and watch the colour and rumble respond to your finger pressure live. Handy for feeling out what each setting does before you save it.

### 🖱️ The touchpad as a Mac trackpad

Yes, you can drive the cursor with the controller's touchpad.

| Gesture | What it does |
|---|---|
| One finger | Move the pointer |
| Tap | Click |
| Two fingers | Scroll |
| Two-finger tap | Right click |
| Press the pad | Click (right click with two fingers down) |
| Press and drag | Select |

It ships off, and needs **Accessibility** permission — that's what macOS requires before an app can move the cursor.

### 📊 Dashboard and sensors

The dashboard shows the whole controller on screen: buttons lighting up, sticks moving, triggers with their pressure as a percentage, real battery level and how it's connected.

There's also a **motion** tab, with the gyroscope in degrees per second and the accelerometer in G, read straight from the controller using its own factory calibration.

### 💾 Profiles

Save whole combinations — lighting, triggers, rumble — and switch between them in one click. Six come built in: PlayStation Classic, FPS, Racing, Rainbow, Battery Saver and Night City.

Everything is reachable from the menu bar icon too, without opening the window.

---

## Getting started

You'll need a Mac running **macOS 13 (Ventura)** or later, with Xcode installed.

```bash
git clone https://github.com/ry-diffusion/SingleSense.git
cd SingleSense
bash scripts/build_app.sh
open SingleSense.app
```

Connect the DualSense over **USB** or **Bluetooth** — both work, and the app figures out which one on its own. It supports the standard DualSense and the **DualSense Edge**, including the back paddles.

### About the permissions

A couple of features ask the system for permission the first time:

| Feature | Permission | Why |
|---|---|---|
| Music Sync | Screen Recording | It's how macOS grants access to system audio |
| Trackpad | Accessibility | Required to move the cursor and click |

One caveat: the app is signed locally (ad-hoc), so macOS may ask again after each rebuild. With an Apple developer account that stops happening.

---

## For anyone digging into the code

It's a plain Swift package:

```bash
swift build     # build
swift test      # run the test suite
```

Talking to the controller is done over raw HID, following the Linux kernel driver (`hid-playstation.c`) and `dualsensectl` as the reference for the packet format. The test suite has **92 tests** checking, byte by byte, what goes out to the controller — offsets, enable bits, checksum, the encoding of every trigger effect, sensor calibration and the trackpad gestures.

```
Sources/SingleSense/
├── Models/      configuration and state types
├── Services/    HID driver, audio and lighting engines, trackpad
└── Views/       the interface
```

---

## Credits

Built on the DualSense community's reverse engineering work — in particular the Linux kernel's [`hid-playstation`](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-playstation.c) driver, [`dualsensectl`](https://github.com/nowrep/dualsensectl) and [`DualSense-Windows`](https://github.com/Ohjurot/DualSense-Windows).

An independent project, not affiliated with Sony Interactive Entertainment. PlayStation and DualSense are trademarks of Sony.
