# VideoPlayer

A Mac video player for live shows. Load the videos and put them in order. Each time you press **Next**, the next video plays. When a video ends, a **loop visual** plays on repeat until you press Next again.

It's built for the screen behind the band. There's a control window on the laptop and a full-screen output on the projector or second display.

## What it does

- **Setlist.** Add videos with the button or by dropping them in from Finder, then drag them into order. Double-click a video to play it right away. Right-click a video for more options.
- **Next.** Plays the video marked NEXT. The next video is already loaded in a second player, so it starts instantly.
- **Loop visual.** When a video ends, the picture fades into the loop video, which repeats with no gap until you press Next. Set one default loop, or give any video its own loop: right-click it and choose *Choose Loop for After This Video…*.
- **Output.** A full-screen window on the screen you pick, with no mouse pointer. The control window has a live preview of exactly what's on the output.
- **Crossfade.** 0–3 seconds between videos and into the loop (0 = hard cut). A second press of Next during a fade is ignored, so a double-tap on a clicker can't skip a song.
- **Blackout, Stop, Back.** Blackout fades the screen to black. Stop fades out and resets NEXT to the first video. Back moves NEXT up one video without playing anything.
- **Remembers your setlist.** It reopens where you left off. Use *Save Setlist As…* and *Open Setlist…* (File menu) to keep one setlist per show. If a video file is moved or renamed, the setlist still finds it.

## Keys (presentation clickers work too)

| Key | Action |
|---|---|
| Space, →, Page Down | Next video |
| ←, Page Up | Move NEXT back one (doesn't play) |
| L | Show the loop visual now |
| B or . | Blackout on / off |
| F | Show / hide the output |
| Esc | Hide the output |

## Install on a Mac

Open **Terminal** and paste this one line:

```
curl -fsSL https://raw.githubusercontent.com/JUSTIC3MAN/VideoPlayer/main/install.sh | bash
```

It downloads the latest VideoPlayer, puts it in Applications and opens it. It works on Intel and Apple Silicon Macs with macOS 13 Ventura or newer, and nothing else needs installing.

**Or download it by hand:** get `VideoPlayer.zip` from the [latest release](https://github.com/JUSTIC3MAN/VideoPlayer/releases/latest), unzip it and drag `VideoPlayer.app` into Applications. The first time you open it, macOS blocks it because it isn't from the App Store. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. This is only needed once. The Terminal line above skips this step.

## Updates

- VideoPlayer checks GitHub a few seconds after it opens. If there's a newer version, it asks whether to update; click **Update and Restart**. You can also choose **VideoPlayer → Check for Updates…** at any time.
- Or run the install line again; it replaces the old version.
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
  VideoPlayerApp.swift                app, menus, keyboard shortcuts
  ControlView.swift                control window (setlist, preview, transport, settings)
  PlaybackEngine.swift             the two video players, the loop, fades, Next logic
  StageView.swift                  the picture (used by the output window and the preview)
  OutputController.swift           full-screen output window and screen choice
  Setlist.swift                    setlist, settings, saving, thumbnails
  Models.swift                     data types
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

`pc-preview/VideoPlayer Preview.html` is a browser copy of the same interface, for checking the layout and flow on Windows. Open it in Chrome or Edge and drop some videos in. It has the same buttons, keys and Next / loop behavior. Open Setlist, Save Setlist, Show in Finder and the screen picker only work in the Mac app.
