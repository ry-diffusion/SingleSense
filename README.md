<div align="center">

<img src="Docs/logo.png" alt="Single Sense" width="168">

# Single Sense 🎮

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

**Music Sync** has its own section in the sidebar and its own switch, because it isn't a lighting effect — it drives three separate parts of the controller, and you choose which ones. It follows whatever your Mac is playing: Spotify, Apple Music, a browser tab, a game. The source doesn't matter.

**The light bar**, if you let it. While that's on, the music takes the bar over from the lighting mode; turn it off and your static colour, rainbow or breathing stays exactly as it was while the music drives only the rest.

| Style | How it looks |
|---|---|
| **Spectrum** | Red on bass, green on mids, blue on treble |
| **Colour Pulse** | Your chosen colour breathing with the volume |
| **Hue Sweep** | Bass-heavy music runs warm, bright music runs cool |
| **Beat Flash** | Dark between beats, lighting up on each one |

**The five player LEDs**, as a meter — filling from the left, growing outward from the centre, or flashing on the beat. Leave it on *Fixed Pattern* and the row keeps the player number you set in Lightbar.

Choose **Kick / Snare** to flash the left pair on a kick and the right pair on a snare, with the row dark between hits. This follows percussion rather than overall loudness, which can stay high throughout a compressed song.

**The rumble motors**, if you want to *feel* the music: bass goes to the heavy motor on the left, treble to the light one on the right. The intensity slider is a ceiling, and the music decides how much of it gets used moment to moment. It ships off, because continuous rumble drains the battery noticeably faster.

Over USB, **Feel it through the voice coils** (on by default) sends the music itself to the actuators in the grips instead of turning it into motor levels: *Bass Kick* plays the actual bass line on both grips, *Full Range* puts the bass on the left and the low mids on the right. Over Bluetooth the motors carry it as before.

> The first time, macOS will ask for **System Audio Recording** permission. Single Sense uses Apple's native Core Audio Process Taps to listen to the system mix directly — no screen or video recording permission is needed.

### 🔊 The controller as a speaker and a subwoofer

In **Speaker & Subwoofer**, switch on the speaker and whatever your Mac is playing moves to the DualSense: its built-in speaker, or headphones plugged into its jack. The sound is moved, not copied — the Mac goes quiet while it's on and comes back the moment you switch it off.

- **Speaker** gets a mono mix of both channels, so nothing panned hard left goes missing
- **Headphones** in the controller's jack get full stereo; plug or unplug them and the sound follows
- Its own volume slider, on top of the Mac's

Switch on **Use the Grips as a Subwoofer** and the voice coils in the grips play the bass of whatever is playing — the actual bass line, through a proper crossover, at the music's own level.

- With the speaker **off**, your Mac keeps playing and the grips add the bass underneath
- With the speaker **on**, it's a 2.1 pair in your hands: the speaker takes everything above the crossover, the grips everything below
- **Crossover** from 60 to 200 Hz, its own **level**, and **Boost deep bass**, which adds the octave above notes too deep for the coils to move
- Music Sync's rumble steps aside while it's on

Both need a **USB cable**: over Bluetooth macOS doesn't see the controller as a sound device. They use the same **System Audio Recording** permission as Music Sync.

### 〰️ Voice-coil haptics

The DualSense's real haptics are two voice-coil actuators in the grips; the "rumble motors" are the firmware imitating old motors on them. Over USB, **Haptics & Vibration** plays waveforms straight into the coils: a crisp click, a heavy thud, a heartbeat, a rapid burst, a wood knock, gravel footsteps alternating between your hands, rain and an explosion. Pick the left grip, the right or both, and set the strength. Without the cable they fall back to CoreHaptics.

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

Everything is reachable from the menu bar item too, which displays the live battery percentage and charging status at a glance without opening the window.

---

## Getting started

You'll need a Mac running **macOS 15 (Sequoia)** or later, with Xcode installed.

```bash
git clone https://github.com/ry-diffusion/SingleSense.git
cd SingleSense
open "Single Sense.xcodeproj"
```

Then hit **Run** (⌘R). Prefer the terminal?

```bash
xcodebuild -project "Single Sense.xcodeproj" -scheme "Single Sense" -configuration Release build
```

Connect the DualSense over **USB** or **Bluetooth** — both work, and the app figures out which one on its own. It supports the standard DualSense and the **DualSense Edge**, including the back paddles.

### About the permissions

A couple of features ask the system for permission the first time:

| Feature | Permission | Why |
|---|---|---|
| Music Sync | System Audio Recording Only | Uses Core Audio Process Taps to read the system mix without screen capture |
| Trackpad | Accessibility | Required to move the cursor and click |

One caveat: the app is signed locally (ad-hoc), so macOS may ask again after each rebuild. With an Apple developer account that stops happening.

---

## For anyone digging into the code

It's a plain Xcode project — one app target and one unit-test target, no dependencies:

```bash
xcodebuild -project "Single Sense.xcodeproj" -scheme "Single Sense" build   # build
xcodebuild -project "Single Sense.xcodeproj" -scheme "Single Sense" test    # run the test suite
```

Signing is set to **Sign to Run Locally** (ad-hoc), so it builds on a clean machine with no developer account. Set your team in *Signing & Capabilities* if you want a stable signature.

Talking to the controller is done over raw HID, following the Linux kernel driver (`hid-playstation.c`) and `dualsensectl` as the reference for the packet format. The test suite has **110 tests** checking, byte by byte, what goes out to the controller — offsets, enable bits, checksum, the encoding of every trigger effect, sensor calibration and the trackpad gestures.

```
Sources/SingleSense/
├── App/         entry point and menu bar
├── Models/      configuration and state types
├── Services/    HID driver, audio and lighting engines, trackpad
└── Views/       the interface
Tests/SingleSenseTests/
Resources/Info.plist
```

---

## Credits

Built on the DualSense community's reverse engineering work — in particular the Linux kernel's [`hid-playstation`](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-playstation.c) driver, [`dualsensectl`](https://github.com/nowrep/dualsensectl) and [`DualSense-Windows`](https://github.com/Ohjurot/DualSense-Windows).

An independent project, not affiliated with Sony Interactive Entertainment. PlayStation and DualSense are trademarks of Sony.
