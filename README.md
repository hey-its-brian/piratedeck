# PirateDeck

A Mac app that controls a Bus Pirate 5 without the console. Version 0.2: connection, setup, wiring panel, read-only actions, and a console panel.

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
- **Setup:** select HiZ, I2C, SPI or UART, the mode settings, the power source, the voltage and the pull-ups, then click Apply.
- **Wiring:** shows each used pin, the signal, where to connect it, and its voltage.
- **Actions:** I2C scan and register read, SPI flash identify and byte transfer, Return to HiZ. The actions are enabled only after Apply and only if the voltage on VOUT is correct.
- **Console:** shows each command that the app sends. You can also type commands. Copy Transcript puts all text on the clipboard.
- Sets HiZ mode when you disconnect or quit.

## Safety

- The app sends `W` (power on) only when you click Apply with "Bus Pirate supplies power" selected.
- This version has no write or erase actions.
- A command that you type in the console disables the actions until you click Apply again, because the app no longer knows the setup.

## Hardware tests (optional)

These tests talk to a real Bus Pirate. Quit PirateDeck first. Nothing must be connected to the pins.

```bash
PIRATEDECK_HW=1 swift test --filter testConnectAndReadInfoFromRealDevice
PIRATEDECK_HW_MODES=1 swift test --filter testSPIAndUARTMenusOnRealDevice
PIRATEDECK_HW_APPLY=1 swift test --filter testApplyI2CScanAndReturnToHiZOnRealDevice   # 3.3 V on VOUT for a short time
```

## Layout

- `Sources/PirateDeckCore`: serial port, session, parsers. All logic and all tests.
- `Sources/PirateDeck`: the SwiftUI window.
- `docs/plans`: the build plans.
