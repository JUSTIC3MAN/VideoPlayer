# VideoPlayer

A Mac video player for live shows. Load the videos and put them in order. Each time you press **Next** (or **A** on an Xbox controller), the next video plays. When a video ends, a **loop visual** plays on repeat until you press Next again. Each part of the show can have its own loop.

It's built for the screen behind the band. There's a control window on the laptop and a full-screen output on the projector or second display.

## What it does

- **Setlist.** Add videos with the button or by dropping them in from Finder, then drag them into order. Double-click a video to play it right away. Right-click a video for more options.
- **Next.** Plays the video marked NEXT. The next video is already loaded in a second player, so it starts instantly.
- **Previous.** Plays the video before the one playing now (or before the one whose loop is up). On the first video it starts it again.
- **Pause.** Freezes the video or loop on screen, and its sound. Press again to carry on.
- **Seek bar.** Click or drag the time bar under the preview to jump to any point in the playing video.
- **Loops for each part of the show.** Any video in the setlist can be a loop: select it and click **Use as Loop** (or right-click it). A loop plays after every video below it, up to the next loop, with no gap until you press Next. So with a loop above videos 1–4 and another above videos 5–7, the first loop plays between videos 1–4 and the second between videos 5–7. See [Loops](#loops-a-different-loop-for-each-part-of-the-show) below.
- **Xbox controller.** A = Next, B = Previous, Y = Pause. See [Xbox controller](#xbox-controller) below.
- **Output.** A full-screen window on the screen you pick, with no mouse pointer. The control window has a live preview of exactly what's on the output.
- **Crossfade.** 0–3 seconds between videos and into the loop (0 = hard cut). A second press of Next during a fade is ignored, so a double-tap on a clicker can't skip a song.
- **Blackout, Stop, Back One.** Blackout fades the screen to black. Stop fades out and resets NEXT to the first video. Back One moves NEXT up one video without playing anything.
- **Remembers your setlist.** It reopens where you left off. Use *Save Setlist As…* and *Open Setlist…* (File menu) to keep one setlist per show. If a video file is moved or renamed, the setlist still finds it. Setlists from older versions open too: their Loop 1 becomes a loop at the top of the setlist, and Loops 2 and 3 go at the end, ready to drag into place.

## Loops: a different loop for each part of the show

A loop row in the setlist plays after every video below it, up to the next loop row. Loop rows have an orange ∞ and show which videos they cover, and each video shows the loop that follows it.

Example: the first 4 videos with one artist's logo loop, then the next 3 with another's:

```
∞  Loop 1: artist A logo     plays after videos 1–4
1  song A1
2  song A2
3  song A3
4  song A4
∞  Loop 2: artist B logo     plays after videos 5–7
5  song B1
6  song B2
7  song B3
```

- **Make a loop:** select any video in the setlist and click **Use as Loop** (above the setlist), or right-click it and choose *Use as Loop*. *Use as Video* turns it back.
- **Add a loop from a file:** select the first video of a part and click **Add Loop…** (in the Loops box). The loop goes above that video. With nothing selected it goes at the top (first loop) or at the end.
- **Choose how many videos a loop covers:** drag the loop row up or down. It covers everything below it until the next loop row.
- **Show a loop now:** double-click its row (or right-click → *Show This Loop Now*). It stays up until the next video plays.
- **One video with its own loop:** right-click the video → *Choose Loop for After This Video…*. *Use the Loop Above It* undoes that.
- Next, Previous and Back One skip loop rows, so loops are never played as songs. Videos with no loop row above them go to black when they end; the Loops box warns about this.
- The Loops box (right side) lists every loop and the videos it covers. Click one to find it in the setlist.

## Xbox controller

| Button | Action |
|---|---|
| A | Next video |
| B | Previous video |
| Y | Pause / resume |

**Pair it once:** press the Xbox button to turn the controller on, then hold the pair button on its top edge until the Xbox button flashes fast. On the Mac, open **System Settings → Bluetooth** and click **Connect** next to the controller. After that it connects by itself whenever it's turned on.

The control window shows the controller's name under the transport buttons when it's connected. Supported: Xbox Wireless Controller (model 1708 with Bluetooth, and Series X|S), Xbox Elite Series 2 and Xbox Adaptive Controller. PlayStation controllers work too, with the buttons in the same places (✕ Next, ○ Previous, △ Pause). The buttons also work while another app (Ableton, say) is in front; on some older macOS versions they only work while VideoPlayer is the front app. A second press of A or B during a fade is ignored, just like Next.

## Keys (presentation clickers work too)

| Key | Action |
|---|---|
| Space, →, Page Down | Next video |
| ←, Page Up | Move NEXT back one (doesn't play) |
| P | Pause / resume |
| L | Show the loop visual now |
| B or . | Blackout on / off |
| F | Show / hide the output |
| Esc | Hide the output |

## Install on a Mac

Works on Intel and Apple Silicon Macs with macOS 13 Ventura or newer.

**Easiest:** open **Terminal**, paste this one line and press Return:

```
curl -fsSL https://raw.githubusercontent.com/JUSTIC3MAN/VideoPlayer/main/install.sh | bash
```

It downloads the latest VideoPlayer, puts it in Applications and opens it, with no security warnings. If it asks for a password, type the Mac's login password (nothing shows while you type) and press Return.

**Or download the zip:**

1. Download [VideoPlayer.zip](https://github.com/JUSTIC3MAN/VideoPlayer/releases/latest/download/VideoPlayer.zip) (always the newest version) and double-click it in Downloads if Safari didn't unzip it.
2. Drag `VideoPlayer.app` into **Applications**.
3. Open it the first time. macOS blocks apps that don't come from the App Store until you allow them once:
   - **macOS 14 Sonoma or older:** right-click VideoPlayer → **Open** → **Open**.
   - **macOS 15 Sequoia or newer:** double-click it and click **Done** on the warning. Then go to **System Settings → Privacy & Security**, click **Open Anyway** and confirm.

## Updates

- VideoPlayer checks GitHub a few seconds after it opens. If there's a newer version, it asks whether to update; click **Update and Restart**. You can also choose **VideoPlayer → Check for Updates…** at any time.
- Or download the zip again and drag the new `VideoPlayer.app` into Applications (choose **Replace**), or run the Terminal line again.
- Your setlist and settings are kept either way.

Each time the code on GitHub changes, GitHub builds a new version on one of its Macs and publishes it as the latest release (see the Actions tab), so updates show up by themselves.

## Show setup tips

- **Use one display as the output.** Plug in the projector, choose it under *Output → Screen*, and press **F**. On a single-screen Mac, the output covers the whole screen; press Esc to get back to the controls.
- **Use H.264 or HEVC MP4 / MOV files at the screen's resolution** (for example 1920×1080). These decode on the Mac's video hardware. ProRes also plays smoothly but makes very large files.
- **Make the loop seamless.** Its last frame should flow into its first, because the player repeats it with no gap. Loops play muted.
- **Keep the videos on the Mac's internal drive or a fast SSD,** not a slow USB stick or a network drive.
- Turn *Play the videos' own sound* off if the band is playing live over the video.

## How it stays smooth

- Video is played with AVFoundation, so decoding runs on the Mac's video hardware, not the CPU.
- Two players take turns. While one is on screen, the next video is already loaded with its first frame decoded, so Next starts instantly.
- The loop runs on its own player with `AVPlayerLooper`, which repeats with no gap.
- Fades are done by Core Animation on the graphics card.
- The time display is kept separate so the rest of the window doesn't redraw while a video plays.
- While the app is open, the display won't go to sleep and macOS won't slow the app down in the background.

## Code

```
Package.swift                      Swift package (macOS 13+)
build.sh                           builds VideoPlayer.app
install.sh                         one-line install / update
.github/workflows/release.yml      GitHub builds the app and publishes each release
Sources/VideoPlayer/
  Updater.swift                    Check for Updates
  VideoPlayerApp.swift             app, menus, keyboard shortcuts
  Gamepad.swift                    Xbox controller buttons (A Next, B Previous, Y Pause)
  ControlView.swift                control window (setlist, loops, preview, transport, settings)
  PlaybackEngine.swift             the two video players, the loop, fades, Next / Previous / Pause
  StageView.swift                  the picture (used by the output window and the preview)
  OutputController.swift           full-screen output window and screen choice
  Setlist.swift                    setlist (videos and loop rows), settings, saving, thumbnails
  Models.swift                     data types, loop parts
```

## Build it yourself (optional)

You only need this if you're changing the code:

```
xcode-select --install        # Apple's free build tools, once
git clone https://github.com/JUSTIC3MAN/VideoPlayer.git
cd VideoPlayer
./build.sh                    # makes build/VideoPlayer.app   (./build.sh install also copies it to Applications)
```

## PC preview

`pc-preview/VideoPlayer Preview.html` is a browser copy of the same interface, for checking the layout and flow on Windows. Open it in Chrome or Edge and drop some videos in. It has the same buttons, keys, loops and Next / Previous / Pause behavior, and an Xbox controller works in it too: plug it in or pair it with the PC, then press any button so the browser sees it. Open Setlist, Save Setlist, Show in Finder and the screen picker only work in the Mac app.
