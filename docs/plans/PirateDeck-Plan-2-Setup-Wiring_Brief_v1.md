# PirateDeck Plan 2: Setup, Wiring and Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (Brian selected native execution). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brian can select a mode, set power and pull-ups, see the wiring with voltages, and do the common I2C, SPI and UART jobs with no typed commands.

**Architecture:** New pure parsers in `PirateDeckCore` turn the `i` reply into a `DeviceStatus` value (mode, settings, power, pull-ups, pin table). A `ModeConfigurator` drives the `m <mode>` menus by menu title. `AppModel` keeps one `DeviceStatus` and refreshes it with `i` after each action. The SwiftUI window gets Setup, Wiring and Actions areas above the console.

**Tech Stack:** Same as Plan 1. No new packages.

**Spec:** Obsidian vault, `01 Projects/App Dev/PirateDeck/PirateDeck_Brief_v1.md`.
**Real output:** `Tests/PirateDeckCoreTests/Captures/e9cb31e-power-on.txt` (captured 2026-11-23, carriage returns kept). All parser tests use text copied from this file.

## Global Constraints

- All Plan 1 constraints stay in force.
- Modes in this plan: HiZ, I2C, SPI, UART.
- The app sends `W` only after Brian clicks Apply with "Bus Pirate supplies power" selected. With "Target has its own supply" selected, the app never sends `W`.
- Voltage range 0.8 to 5.0 V. Current limit 0 to 500 mA, default 300 mA.
- Erase and write actions are NOT in this plan. Read-only actions only (scan, identify, read, dump to terminal, monitor). Write and erase come in Plan 3 with their confirmations.
- A parser failure shows the raw reply. It does not stop the app.
- The console shows each command that the app sends.
- No em dashes. Simple English in user-visible text.

## Facts from the capture (firmware e9cb31e)

- `m <mode>` asks questions. First time: one menu for each setting, each ends with `x to exit (<default>) > `. Later: `Use previous settings?` then `y/n, x to exit (Y) > `. Return accepts the default.
- I2C menus in order: `I2C speed` (kHz number), `Clock stretching` (1 OFF, 2 on).
- SPI menus in order: `SPI speed` (kHz), `Data bits` (4 to 8), `Clock polarity` (1 Idle LOW, 2 Idle HIGH), `Clock phase` (1 LEADING, 2 TRAILING), `Chip select` (1 Active HIGH, 2 Active LOW).
- UART settings shown by `i`: speed, data bits, parity, stop bits, hardware flow control, signal inversion. The UART menus themselves were not captured.
- `i` in a mode prints: `Active mode: I2C`, indented setting lines (` I2C speed: 400 kHz`), `Pull-up resistors: ON|OFF`, `Power supply: OFF` or `Power supply: ON (3.3V/3.29V)`, `Current limit: OK (3.1mA/300.0mA)`, then the pin table.
- Pin table: three tab-separated rows.
  `1.Vout 2.IO0 ... 9.IO7 10.GND` / `OFF|003.9mA SDA SCL - ... GND` / `3.3V 0.0V ... GND`.
- Pin labels: I2C `IO0 SDA`, `IO1 SCL`. SPI `IO4 MISO`, `IO5 CS`, `IO6 CLK`, `IO7 MOSI`. UART `IO4 TX->`, `IO5 RX<-`.
- `W 3.3` reply has `Power supply:  Enabled` and `Vreg output: 3.3V, Vref/Vout pin: 3.3V, Current: 4.0mA`. `w` reply: `Power supply: Disabled`.
- `P` reply: `Pull-up resistors: Enabled (10K ohms @ 3.3V)`. With no voltage it adds `Warning: no/low voltage detected.`
- `scan` with no power: lines that start with `Error:` and `Aborting I2C scan`. With power and no devices: `Found 0 addresses, 0 W/R pairs.` The format of a found address is NOT known.
- Commands are case-sensitive: `w 3.3` turns the supply OFF.
- The echo uses lone carriage returns to redraw the line with hints (`HiZ> m HiZ` and so on).

## Review Focus

1. Apply with "Bus Pirate supplies power" but VOUT does not reach the set voltage (short circuit, fuse trip): the app shows a warning, and the actions stay disabled.
2. The mode menus have a title that the app does not know (firmware change, UART menus not captured): the configurator sends Return for the default and continues. It never sends a guessed number.
3. The `i` reply has a pin table with a different number of columns or missing rows: `DeviceStatus.parse` returns a status with an empty pin list, and the UI shows the raw table text.
4. Brian types a number outside the range (voltage 12, speed 0, text): Apply is disabled and the field shows the valid range.
5. The device is unplugged during Apply or during an action: same behavior as Plan 1 (disconnected state, no crash), and no half-applied state stays on screen.

Tests: 1 and 5 in Task 4, 2 in Task 2, 3 in Task 1, 4 in Task 3.

## File Structure

```
Sources/PirateDeckCore/
  TextCleaning.swift      (modify) collapseCarriageReturns
  Transcript.swift        (modify) plainText uses collapseCarriageReturns
  DeviceStatus.swift      (new) parser for the in-mode `i` reply and pin table
  ModeSettings.swift      (new) settings model, validation, menu answers
  ModeConfigurator.swift  (new) drives `m <mode>` menus
  PowerControl.swift      (new) W / w / P / p commands and reply checks
  Actions.swift           (new) command builders for read-only actions
Sources/PirateDeck/
  AppModel.swift          (modify) status, apply, actions
  SetupView.swift, WiringView.swift, ActionsView.swift (new)
  ContentView.swift       (modify) layout
Tests/PirateDeckCoreTests/
  CaptureFixtures.swift   (new) strings copied from the capture file
  DeviceStatusTests.swift, ModeSettingsTests.swift, ModeConfiguratorTests.swift,
  PowerControlTests.swift, ActionsTests.swift (new)
```

Test command: `swift test`. Pass: `0 failures`.

---

### Task 1: Clean echo display, DeviceStatus parser

**Files:** modify `TextCleaning.swift`, `Transcript.swift`; create `DeviceStatus.swift`, `CaptureFixtures.swift`; tests `TextCleaningTests.swift` (add), `DeviceStatusTests.swift`.

**Interfaces (produces):**
- `public func collapseCarriageReturns(_ text: String) -> String`: in each line, a lone `\r` (not before `\n`) means "back to the line start". Keep only the text after the last lone `\r`. Line ends become `\n`.
- `Transcript.plainText()` returns `collapseCarriageReturns(stripANSI(raw))`. Add `public func rawText() -> String` (ANSI-stripped, carriage returns kept) for fixtures.
- `public struct PinState: Equatable, Sendable { public let number: Int; public let name: String; public let label: String; public let voltage: Double? }` (`voltage` nil for GND; `label` is `-` for an unused pin).
- `public struct DeviceStatus: Equatable, Sendable { public let mode: String; public let settings: [(key: String, value: String)]`-equivalent as `[Setting]` with `public struct Setting: Equatable, Sendable { key, value }`; `public let pullupsOn: Bool?; public let powerOn: Bool?; public let setVoltage: Double?; public let measuredVoltage: Double?; public let currentMilliamps: Double?; public let pins: [PinState]; public let rawPinTable: String }`
- `public static func DeviceStatus.parse(_ reply: String) -> DeviceStatus?` nil if there is no `Active mode:` line.
- `public static func DeviceStatus.parsePinTable(_ text: String) -> (pins: [PinState], raw: String)` also used for the `v` reply.

- [ ] **Step 1: Write `CaptureFixtures.swift`** with `iReplyI2CPowered`, `iReplyUARTOff`, `vReplyI2CPowered`, `vReplyI2COff`, copied from the capture file (the text between the echo line and the next prompt).
- [ ] **Step 2: Write the failing tests**

```swift
func testCollapseKeepsTextAfterLastLoneCR() {
    XCTAssertEqual(collapseCarriageReturns("\rHiZ> m HiZ\r\rHiZ> m i2c\r\n\r\nMode: I2C\r\n"), "HiZ> m i2c\n\nMode: I2C\n")
}
func testParsesPoweredI2CStatus() throws {
    let s = try XCTUnwrap(DeviceStatus.parse(CaptureFixtures.iReplyI2CPowered))
    XCTAssertEqual(s.mode, "I2C")
    XCTAssertEqual(s.settings, [Setting(key: "I2C speed", value: "400 kHz"), Setting(key: "Clock stretching", value: "OFF")])
    XCTAssertEqual(s.pullupsOn, true); XCTAssertEqual(s.powerOn, true)
    XCTAssertEqual(s.setVoltage, 3.3); XCTAssertEqual(s.measuredVoltage, 3.29)
    XCTAssertEqual(s.currentMilliamps, 3.1)
    XCTAssertEqual(s.pins.count, 10)
    XCTAssertEqual(s.pins[0], PinState(number: 1, name: "Vout", label: "003.1mA", voltage: 3.3))
    XCTAssertEqual(s.pins[1], PinState(number: 2, name: "IO0", label: "SDA", voltage: 3.3))
    XCTAssertEqual(s.pins[2].label, "SCL")
    XCTAssertEqual(s.pins[9], PinState(number: 10, name: "GND", label: "GND", voltage: nil))
}
func testParsesUARTStatusWithPowerOff() throws {
    let s = try XCTUnwrap(DeviceStatus.parse(CaptureFixtures.iReplyUARTOff))
    XCTAssertEqual(s.mode, "UART"); XCTAssertEqual(s.powerOn, false); XCTAssertEqual(s.pullupsOn, false)
    XCTAssertNil(s.setVoltage); XCTAssertEqual(s.settings.count, 6)
    XCTAssertEqual(s.pins[5].label, "TX->"); XCTAssertEqual(s.pins[6].label, "RX<-")
    XCTAssertEqual(s.pins[0].label, "OFF"); XCTAssertEqual(s.pins[0].voltage, 0.0)
}
func testHiZStatusHasNoSettings() throws {
    let s = try XCTUnwrap(DeviceStatus.parse(Fixtures.infoReply))
    XCTAssertEqual(s.mode, "HiZ"); XCTAssertTrue(s.settings.isEmpty); XCTAssertTrue(s.pins.isEmpty)
    XCTAssertNil(s.powerOn)
}
func testBadPinTableGivesEmptyPinsAndKeepsRawText() {
    let bad = "Active mode: I2C\r\n\r\n1.Vout\t2.IO0\r\nOFF\tSDA\tSCL\r\n"
    let s = DeviceStatus.parse(bad)
    XCTAssertEqual(s?.pins, []); XCTAssertTrue(s?.rawPinTable.contains("1.Vout") ?? false)
}
func testParsesVReply() {
    XCTAssertEqual(DeviceStatus.parsePinTable(CaptureFixtures.vReplyI2COff).pins[1].voltage, 0.0)
    XCTAssertEqual(DeviceStatus.parsePinTable(CaptureFixtures.vReplyI2CPowered).pins[1].voltage, 3.3)
}
func testNotAStatusReply() { XCTAssertNil(DeviceStatus.parse("Invalid command: x.")) }
```

- [ ] **Step 3: Run `swift test`.** Expected: compile failure.
- [ ] **Step 4: Implement.** Update the Plan 1 transcript test to the new `plainText` output if it changes.
- [ ] **Step 5: Run `swift test`.** Expected: 0 failures.
- [ ] **Step 6: Commit:** `feat: device status parser, clean echo display`

### Task 2: Mode settings and configurator

**Files:** create `ModeSettings.swift`, `ModeConfigurator.swift`; tests `ModeSettingsTests.swift`, `ModeConfiguratorTests.swift`.

**Interfaces:**
- Consumes: `BusPirateSession.sendInteractive`, `modePrompt(in:)`.
- Produces:
  - `public enum BusMode: String, CaseIterable, Sendable { case hiz = "HiZ", i2c = "I2C", spi = "SPI", uart = "UART" }` with `var command: String` (`"m hiz"`, `"m i2c"`, ...).
  - `public struct ModeSettings: Equatable, Sendable` with
    `i2cSpeedKHz = 400` (1...1000), `i2cClockStretching = false`,
    `spiSpeedKHz = 100` (1...62500), `spiDataBits = 8` (4...8), `spiClockIdleHigh = false`, `spiTrailingEdge = false`, `spiCSActiveLow = true`,
    `uartBaud = 115200` (1...7372800... use 300...3000000), `uartDataBits = 8` (5...8), `uartParity: Parity = .none` (`none, even, odd` = menu 1, 2, 3), `uartStopBits = 1` (1...2).
  - `public func validationErrors(for mode: BusMode) -> [String]` one sentence for each bad value, for example `"I2C speed must be 1 to 1000 kHz."`
  - `public func menuAnswers(for mode: BusMode) -> [String: String]` keyed by menu title: I2C `["I2C speed": "400", "Clock stretching": "1"]`; SPI `["SPI speed": "100", "Data bits": "8", "Clock polarity": "1", "Clock phase": "1", "Chip select": "2"]`; UART `["UART speed": "115200", "Data bits": "8", "Parity": "1", "Stop bits": "1"]`.
  - `public enum ModeConfigurator { public static func enter(_ mode: BusMode, settings: ModeSettings, session: BusPirateSession) async throws -> [String] }` returns the titles of menus that it did not know. Throws `ConfigError.modeNotReached(got: String?)`.

Algorithm:
```
reply = sendInteractive(mode.command)
repeat at most 12 times:
    if session.currentMode matches the mode (case-insensitive) and the reply ended at a mode prompt -> return unknown
    if reply contains "Use previous settings?" -> reply = sendInteractive("n"); continue
    title = the first non-empty line of the last menu block (the block before "x to exit")
    if answers[title] exists -> reply = sendInteractive(answer)
    else -> unknown.append(title); reply = sendInteractive("")      // Return = default
throw modeNotReached
```
The UART menu titles are an assumption from the `i` setting names. If they are wrong, the configurator uses the defaults and reports the titles.

- [ ] **Step 1: Write the failing tests** with `FakeTransport.autoReplies` built from the capture text:
  - `testEntersI2CAndAnswersMenusByTitle`: replies for `m i2c\r` (speed menu), `400\r` (clock stretching menu), `1\r` (`I2C> `). Assert `written` contains `400\r` then `1\r`, result `[]`, `currentMode == "I2C"`.
  - `testAnswersNoToUsePreviousSettings`: `m i2c\r` gives the `Use previous settings?` text. Assert `n\r` is written before `400\r`.
  - `testUnknownMenuTitleGetsReturnNotANumber`: a menu titled `Bit banding` appears. Assert `\r` is written for it, result `["Bit banding"]`, and no digit was written for it.
  - `testHiZNeedsNoAnswers`: `m hiz\r` gives `Mode: HiZ\r\nHiZ> `. Result `[]`.
  - `testThrowsWhenModeIsNotReached`: every reply is a menu. Expect `ConfigError.modeNotReached`.
  - `testValidation`: `i2cSpeedKHz = 0` gives 1 error; `spiDataBits = 9` gives 1 error; defaults give 0 errors for all modes.
  - `testMenuAnswersUseSettings`: `spiClockIdleHigh = true` gives `"Clock polarity": "2"`; `uartParity = .odd` gives `"Parity": "3"`.
- [ ] **Step 2: Run `swift test`.** Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: 0 failures.
- [ ] **Step 5: Commit:** `feat: mode settings and menu configurator`

### Task 3: Power control and action commands

**Files:** create `PowerControl.swift`, `Actions.swift`; tests `PowerControlTests.swift`, `ActionsTests.swift`.

**Interfaces (produces):**
- `public struct PowerRequest: Equatable, Sendable { public var volts: Double; public var milliamps: Int }`, `public func validationErrors() -> [String]` (`"Voltage must be 0.8 to 5.0 V."`, `"Current limit must be 0 to 500 mA."`), `public var command: String` = `"W 3.3 300"` format (`%.1f`... use up to 2 decimals without trailing zeros, uppercase `W` always).
- `public enum PowerControl { static let off = "w"; static let pullupsOn = "P"; static let pullupsOff = "p" }`
- `public static func PowerControl.supplyEnabled(in reply: String) -> Bool` true if a line matches `Power supply:\s+Enabled`.
- `public static func PowerControl.voltageIsGood(set: Double, measured: Double?) -> Bool` true if measured is within 10 percent of set (the firmware undervoltage limit is 10 percent).
- `public enum Actions`:
  - `static let i2cScan = "scan"`
  - `static func i2cRead(address7: UInt8, register: UInt8, count: Int) -> String` gives `"[0xa0 0x00 [0xa1 r:8]"` for address 0x50, register 0, count 8 (write address = address << 1, read address = write address + 1; count 1...255).
  - `static let spiFlashProbe = "flash probe"`
  - `static func spiTransfer(bytes: [UInt8], readCount: Int) -> String` gives `"[0x9f r:3]"` for `[0x9f]`, 3.
  - `static func rawBytes(from text: String) -> [UInt8]?` parses `"9f 00 0x1A"` (hex, with or without `0x`, space or comma separated); nil if any token is bad.
  - `static func scanSummary(_ reply: String) -> String?` returns `"Found 0 addresses, 0 W/R pairs."` line if present; for a reply with `Error:` lines returns the error lines and hints joined by newline.

- [ ] **Step 1: Write the failing tests**: exact strings above; `PowerRequest(volts: 12, milliamps: 300).validationErrors().count == 1`; `PowerRequest(volts: 3.3, milliamps: 300).command == "W 3.3 300"`; `PowerRequest(volts: 5, milliamps: 0).command == "W 5 0"`; `supplyEnabled` true for the captured `W 3.3` reply and false for `Power supply: Disabled`; `voltageIsGood(set: 3.3, measured: 3.29)` true, `(3.3, 0.4)` false, `(3.3, nil)` false; `rawBytes(from: "9f zz") == nil`; `i2cRead(address7: 0x50, register: 0, count: 0)` clamps count to 1; `scanSummary` for both captured scan replies.
- [ ] **Step 2: Run `swift test`.** Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: 0 failures.
- [ ] **Step 5: Commit:** `feat: power control and read-only action commands`

### Task 4: AppModel apply flow

**Files:** modify `Sources/PirateDeck/AppModel.swift`; move the flow into a new testable core type `Sources/PirateDeckCore/DeviceController.swift`; test `DeviceControllerTests.swift`.

**Interfaces:**
- Consumes: everything from Tasks 1 to 3.
- Produces: `public actor DeviceController` with
  - `public init(session: BusPirateSession)`
  - `public enum PowerSource: Sendable { case busPirate(PowerRequest), target }`
  - `public struct ApplyRequest: Sendable { mode: BusMode; settings: ModeSettings; power: PowerSource; pullups: Bool }`
  - `public struct ApplyResult: Equatable, Sendable { status: DeviceStatus?; warnings: [String]; actionsEnabled: Bool }`
  - `public func apply(_ request: ApplyRequest) async throws -> ApplyResult`
  - `public func refresh() async throws -> DeviceStatus?` (sends `i`)
  - `public func run(_ command: String, timeout: Duration = .seconds(10)) async throws -> String` (for actions)

`apply` order: (1) `w` and `p` (safe state), (2) `ModeConfigurator.enter`, (3) if mode is HiZ: stop, (4) if `.busPirate`: send the `W` command and check `supplyEnabled`; if `.target`: send nothing, (5) `P` if pull-ups requested, (6) `refresh()`.
Warnings (exact text):
- Unknown menus: `"The app did not know these settings and used the defaults: <titles>."`
- Supply not enabled or `voltageIsGood` false: `"VOUT is <measured> V but the set value is <set> V. Check for a short circuit. The actions are disabled."` and `actionsEnabled = false`.
- `.target` and Vout voltage below 0.8 V: `"No voltage on VOUT/VREF. Connect the target supply to the VOUT pin. The actions are disabled."` and `actionsEnabled = false`.
- Pull-ups requested and the `P` reply contains `Warning:`: `"Pull-ups are on, but no voltage is present."`

- [ ] **Step 1: Write the failing tests** (FakeTransport, replies from the capture):
  - `testApplyI2CWithPowerSendsCommandsInOrder`: written order is `w`, `p`, `m i2c`, answers, `W 3.3 300`, `P`, `i`. Result: `actionsEnabled == true`, no warnings, `status?.mode == "I2C"`.
  - `testTargetPowerNeverSendsW`: no written line starts with `W`.
  - `testLowVoltageDisablesActions`: the `i` reply shows `Power supply: ON (3.3V/0.41V)` and Vout `0.4V`. Result has the VOUT warning and `actionsEnabled == false`.
  - `testTargetPowerWithNoVoltageDisablesActions`.
  - `testHiZStopsAfterModeChange`: nothing is written after `m hiz`.
  - `testDisconnectDuringApplyThrowsDisconnected`: `f.disconnect()` after `m i2c`; expect `SessionError.disconnected`.
- [ ] **Step 2: Run `swift test`.** Expected: compile failure.
- [ ] **Step 3: Implement `DeviceController`. Update `AppModel`:** add `var status: DeviceStatus?`, `var warnings: [String]`, `var actionsEnabled: Bool`, `var actionResult: String`, `func apply(_:) async`, `func refresh() async`, `func runAction(_ command: String) async`. On any thrown `SessionError.disconnected`, call the Plan 1 lost-device path and clear `status`, `warnings`, `actionResult`.
- [ ] **Step 4: Run `swift test`.** Expected: 0 failures.
- [ ] **Step 5: Commit:** `feat: apply flow with safety checks`

### Task 5: Setup, Wiring and Actions views

**Files:** create `SetupView.swift`, `WiringView.swift`, `ActionsView.swift`; modify `ContentView.swift`.

Fixed UI text and behavior:
- **Setup:** `Picker("Mode")` with HiZ, I2C, SPI, UART. Settings for the selected mode only (I2C: Speed kHz, Clock stretching. SPI: Speed kHz, Data bits, Clock idle state, Clock edge, Chip select. UART: Baud menu with 9600, 19200, 38400, 57600, 115200 and Other, Data bits, Parity, Stop bits). Power: radio `Bus Pirate supplies power` (Voltage menu 1.8, 2.5, 3.3, 5.0 and Other; Current limit mA) or `Target has its own supply`. Toggle `Pull-up resistors`; when the mode is I2C it is ON by default and shows the hint `I2C needs pull-ups.` Button `Apply` (disabled while busy or when any validation error exists; the first error shows in red under the field).
- **Wiring:** one row for each pin whose label is not `-`, plus GND: pin name, signal, `connect to target <signal>`, voltage with one decimal. UART rows show `TX-> : connect to target RX` and `RX<- : connect to target TX`. Button `Refresh`. If `pins` is empty and `rawPinTable` is not, show the raw text in monospace.
- **Actions** (disabled unless `actionsEnabled`):
  - I2C: `Scan bus`; `Read register` with fields Address (hex, 7-bit), Register (hex), Count.
  - SPI: `Identify flash chip`; `Send bytes` with fields Bytes (hex) and Read count.
  - UART: `Open monitor` runs `bridge`... NOT in this plan (the exit needs the device button). UART shows the text `Use the console to send data. Type { to open the port and show incoming data.`
  - All modes: `Return to HiZ` (always enabled when connected).
  - Result area: monospace text of the cleaned reply. For scan, the `scanSummary` line shows above it in bold.
- Layout: status bar, warnings (yellow), Setup and Wiring side by side, Actions, console. Window minimum 860 x 640.

- [ ] **Step 1: Implement the three views and the layout.**
- [ ] **Step 2: Run `swift build` and `swift test`.** Expected: `Build complete!`, 0 failures.
- [ ] **Step 3: Run `bash scripts/make-app.sh`.** Expected: `Built PirateDeck.app`.
- [ ] **Step 4: Update `README.md`** (what the app does now).
- [ ] **Step 5: Commit:** `feat: setup, wiring and actions views`

### Task 6: Hardware check (Claude runs the safe part, Brian does the rest)

- [ ] **Step 1 (Claude):** with nothing connected, run an opt-in hardware test that calls `DeviceController.apply` for I2C at 3.3 V with pull-ups, asserts `actionsEnabled`, runs `scan`, then applies HiZ and asserts that the supply is off.
- [ ] **Step 2 (Brian):** open the app, select I2C, 3.3 V, pull-ups, Apply. The wiring panel must show SDA on IO0 and SCL on IO1 at 3.3 V.
- [ ] **Step 3 (Brian):** connect a known I2C device (for example an SSD1306 display or a 24xx EEPROM), click Scan bus, and paste the result. Claude adds the parser for found addresses from this text.
