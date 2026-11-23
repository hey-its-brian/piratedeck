# PirateDeck

A Mac app that controls a Bus Pirate 5 without the console. This is version 0.1: connection, status bar, and a console panel.

Tested with: Bus Pirate 5 REV10, firmware main branch commit `e9cb31e` (Nov 20 2026).

## Build and run

```bash
swift test                 # run the tests (no hardware necessary)
bash scripts/make-app.sh   # make PirateDeck.app in this folder
open PirateDeck.app
```

Close all other terminal programs on the Bus Pirate port (for example `screen`) before you connect. The port can have only one user.

## What it does

- Finds the Bus Pirate terminal port (`/dev/cu.usbmodem*buspirate*`). It does not open other serial devices.
- Answers the VT100 question with `n` and reads the `i` reply.
- Shows a console panel. Type a command and press Return. Copy Transcript puts all sent and received text on the clipboard.
- Sets HiZ mode when you disconnect or quit.

## Transcript for the next version

With nothing connected to the Bus Pirate pins, send these lines one at a time, then click Copy Transcript:

`i`, `v`, `m`, `x`, `m i2c` (press Return for each default), `i`, `v`, `W 3.3`, `v`, `P`, `v`, `scan`, `w`, `p`, `m spi` (defaults), `v`, `m uart` (defaults), `v`, `m hiz`, `W -h`, `m -h`

## Layout

- `Sources/PirateDeckCore`: serial port, session, parsers. All logic and all tests.
- `Sources/PirateDeck`: the SwiftUI window.
- `docs/plans`: the build plans.
