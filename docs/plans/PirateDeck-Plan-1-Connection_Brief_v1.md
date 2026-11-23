# PirateDeck Plan 1: Connection and Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Mac app that finds the Bus Pirate 5, connects to its terminal port, shows the device status, and has a console panel with a Copy Transcript button.

**Architecture:** A Swift package with a library target (`PirateDeckCore`) that holds all serial, session and parse logic, and a thin SwiftUI executable target (`PirateDeck`). The core talks to a `ByteTransport` protocol, so all tests use a fake transport and no hardware. A script puts the built binary into a `.app` bundle.

**Tech Stack:** Swift (tools version 5.9, Swift 5 language mode), SwiftUI, XCTest, POSIX `termios`. No third-party packages.

**Spec:** Obsidian vault, `01 Projects/App Dev/PirateDeck/PirateDeck_Brief_v1.md`. This plan covers build order step 1 only. Plan 2 (setup area, wiring, parsers for `v` and `scan`, actions) is written after Brian sends real transcripts from this app.

## Global Constraints

- macOS 14 minimum. Dev machine has Swift 6.4.2, Xcode 27.2, macOS 27.0.1.
- No third-party packages. No app sandbox.
- Serial settings: 115200 baud, 8N1, raw mode.
- Target device: Bus Pirate 5 REV10, firmware main branch commit `e9cb31e` (Nov 20 2026).
- The app answers `n` to the VT100 question and removes ANSI escape codes from all input.
- The app sets HiZ mode on disconnect and on quit.
- The app never sends `W`, erase or write commands by itself in this plan. It sends only: carriage return, `n`, `x`, `i`, `m hiz`, and lines that the user types.
- A parser failure must not stop the app. Show the raw text.
- No em dashes in any text. Use simple English in user-visible text.
- Change from the spec: a Swift package replaces the Xcode project (Xcode opens `Package.swift` directly, and `swift test` runs from the command line).

## Review Focus

1. USB cable removed while connected: the app goes to the disconnected state with a message and does not crash or hang.
2. Other serial devices are connected (Brian has ESP32 boards; `/dev/cu.usbmodem1301` is present now): the app must not open them. Opening an ESP32 port can reset the board.
3. The device is not at a mode prompt at connect (inside a menu, or the VT100 question shows): `start()` gets to a mode prompt or fails with a clear timeout.
4. The device is in VT100 mode with the toolbar: cursor-move and scroll-region codes are removed and prompt detection still works.
5. A reply does not end before the timeout (long help text, a paged dump that waits for a key): `send` throws a timeout that carries the partial text, and the console shows that text.

Tests for each line are in the task that owns the code (1: Task 5, 2: Task 4, 3 and 5: Task 3, 4: Task 1).

## File Structure

```
piratedeck/
  Package.swift
  Sources/PirateDeckCore/
    TextCleaning.swift       ANSI removal, prompt detection
    Transcript.swift         log of sent and received text
    ByteTransport.swift      transport protocol
    POSIXSerialPort.swift    termios implementation of ByteTransport
    BusPirateSession.swift   actor: start, send, shutdown
    DeviceInfo.swift         parser for the `i` reply
    PortFinder.swift         selects the terminal port
  Sources/PirateDeck/
    PirateDeckApp.swift      app entry
    AppModel.swift           connection state for the UI
    ContentView.swift        status bar and console panel
  Tests/PirateDeckCoreTests/
    FakeTransport.swift
    Fixtures.swift           real `i` reply text
    TextCleaningTests.swift, TranscriptTests.swift, SessionTests.swift,
    DeviceInfoTests.swift, PortFinderTests.swift
  scripts/make-app.sh
  README.md, .gitignore
```

All commands run from the repo root. Test command: `swift test`. Expected result for a pass: `Executed N tests, with 0 failures`.

---

### Task 1: Package, text cleaning and transcript

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `*.app`, `.DS_Store`), `Sources/PirateDeckCore/TextCleaning.swift`, `Sources/PirateDeckCore/Transcript.swift`, `Sources/PirateDeck/PirateDeckApp.swift` (empty `WindowGroup` with `Text("PirateDeck")` so the package builds)
- Test: `Tests/PirateDeckCoreTests/TextCleaningTests.swift`, `Tests/PirateDeckCoreTests/TranscriptTests.swift`

**Interfaces:**
- Produces:
  - `public func stripANSI(_ text: String) -> String`
  - `public func modePrompt(in text: String) -> String?` returns the mode name (for example `"HiZ"`, `"I2C"`, `"1WIRE"`) if the last non-empty line of the ANSI-stripped text matches `^([A-Za-z0-9-]+)>\s*$`. Returns nil for menu prompts such as `Mode >` or `(1) >` (they have a space before `>`).
  - `public func isVT100Question(_ text: String) -> Bool` true if the last non-empty line contains `VT100` (case-insensitive).
  - `public final class Transcript: @unchecked Sendable` with `public enum Direction { case sent, received }`, `public func append(_ direction: Direction, _ text: String)`, `public func plainText() -> String`, `public var onChange: (@Sendable () -> Void)?`. `plainText()` writes sent text as `>> <text>` on its own line and received text unchanged (ANSI-stripped). Thread-safe with a lock.

- [ ] **Step 1: Write `Package.swift`**: `swift-tools-version:5.9`, `platforms: [.macOS(.v14)]`, targets `PirateDeckCore` (library), `PirateDeck` (executableTarget, depends on core), `PirateDeckCoreTests`.

- [ ] **Step 2: Write the failing tests**

```swift
final class TextCleaningTests: XCTestCase {
    func testStripsColorCodes() {
        XCTAssertEqual(stripANSI("\u{1B}[0;32mHiZ>\u{1B}[0m "), "HiZ> ")
    }
    func testStripsCursorAndScrollRegionCodes() {
        XCTAssertEqual(stripANSI("\u{1B}[1;24r\u{1B}[24;1H\u{1B}[?25lI2C>\u{1B}7\u{1B}8"), "I2C>")
    }
    func testModePromptFound() {
        XCTAssertEqual(modePrompt(in: "some reply\r\nHiZ> "), "HiZ")
        XCTAssertEqual(modePrompt(in: "\u{1B}[32m1WIRE>\u{1B}[0m"), "1WIRE")
    }
    func testMenuPromptIsNotModePrompt() {
        XCTAssertNil(modePrompt(in: "x. Exit\r\nMode > "))
        XCTAssertNil(modePrompt(in: "Bits (1) > "))
        XCTAssertNil(modePrompt(in: "reply in progress"))
    }
    func testVT100Question() {
        XCTAssertTrue(isVT100Question("VT100 compatible color mode? (Y/n)> "))
        XCTAssertFalse(isVT100Question("HiZ> "))
    }
}
final class TranscriptTests: XCTestCase {
    func testPlainTextFormat() {
        let t = Transcript()
        t.append(.sent, "i")
        t.append(.received, "\u{1B}[32mBus Pirate 5 REV10\u{1B}[0m\r\nHiZ> ")
        XCTAssertEqual(t.plainText(), ">> i\nBus Pirate 5 REV10\r\nHiZ> ")
    }
    func testOnChangeFires() {
        let t = Transcript(); let e = expectation(description: "change")
        t.onChange = { e.fulfill() }
        t.append(.sent, "v"); wait(for: [e], timeout: 1)
    }
}
```

- [ ] **Step 3: Run `swift test`.** Expected: compile failure (functions not defined).
- [ ] **Step 4: Implement the functions and `Transcript`.** `stripANSI` removes CSI sequences (`ESC [` parameters and one final byte in `@` to `~`), and two-byte sequences (`ESC` plus one of `7 8 = > c M`).
- [ ] **Step 5: Run `swift test`.** Expected: 0 failures.
- [ ] **Step 6: Commit** (`git init` first): `feat: package, text cleaning, transcript`

### Task 2: Transport protocol and fake transport

**Files:**
- Create: `Sources/PirateDeckCore/ByteTransport.swift`, `Tests/PirateDeckCoreTests/FakeTransport.swift`

**Interfaces:**
- Produces:
  - `public protocol ByteTransport: AnyObject, Sendable { func write(_ data: Data) throws; var incoming: AsyncStream<Data> { get }; func close() }`. The `incoming` stream finishes when the device disconnects or `close()` is called.
  - `public enum TransportError: Error, Equatable { case openFailed(String), writeFailed, closed }`
  - Test helper `final class FakeTransport: ByteTransport` with `var written: [String]` (each write as UTF-8), `func feed(_ text: String)`, `func disconnect()` (finishes the stream; later `write` throws `.closed`), and `var autoReplies: [String: String]` (when a write equals a key, the value is fed automatically).

- [ ] **Step 1: Write both files.** No separate test: Task 3 exercises them.
- [ ] **Step 2: Run `swift build`.** Expected: `Build complete!`
- [ ] **Step 3: Commit:** `feat: byte transport protocol and fake`

### Task 3: BusPirateSession

**Files:**
- Create: `Sources/PirateDeckCore/BusPirateSession.swift`
- Test: `Tests/PirateDeckCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: `ByteTransport`, `Transcript`, `stripANSI`, `modePrompt(in:)`, `isVT100Question(_:)`
- Produces:
  - `public enum SessionError: Error, Equatable { case timeout(partial: String), disconnected }`
  - `public actor BusPirateSession`
    - `public init(transport: ByteTransport, transcript: Transcript)`
    - `public func start(timeout: Duration = .seconds(3)) async throws` gets the device to a mode prompt.
    - `public func send(_ line: String, timeout: Duration = .seconds(3)) async throws -> String` writes `line + "\r"`, reads until a mode prompt, returns the ANSI-stripped reply without the echoed command line and without the prompt line, trimmed.
    - `public private(set) var currentMode: String?` from the last mode prompt.
    - `public func shutdown() async` sends `m hiz` if `currentMode` is not `"HiZ"` (errors ignored), then closes the transport.
- Every write and every received chunk goes to the transcript.

`start()` algorithm (the tests do not fully determine it):

```
repeat at most 4 times:
    write "\r"; read until 500 ms pass with no new bytes (or timeout)
    if text ends with a mode prompt  -> done
    if isVT100Question(text)         -> write "n\r"; continue
    if text is not empty             -> write "x\r"; continue   (leave a menu)
throw SessionError.timeout(partial: text)
```

- [ ] **Step 1: Write the failing tests**

```swift
final class SessionTests: XCTestCase {
    func makeSession() -> (BusPirateSession, FakeTransport, Transcript) {
        let f = FakeTransport(); let t = Transcript()
        return (BusPirateSession(transport: f, transcript: t), f, t)
    }
    func testStartAtPrompt() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "\r\nHiZ> "]
        try await s.start()
        let mode = await s.currentMode
        XCTAssertEqual(mode, "HiZ")
    }
    func testStartAnswersVT100QuestionWithN() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "VT100 compatible color mode? (Y/n)> ", "n\r": "n\r\nHiZ> "]
        try await s.start()
        XCTAssertTrue(f.written.contains("n\r"))
    }
    func testStartLeavesMenuWithX() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "x. Exit\r\nMode > ", "x\r": "x\r\nHiZ> "]
        try await s.start()
        XCTAssertTrue(f.written.contains("x\r"))
    }
    func testStartTimesOutOnSilentPort() async {
        let (s, _, _) = makeSession()
        do { try await s.start(timeout: .milliseconds(300)); XCTFail() }
        catch { XCTAssertEqual(error as? SessionError, .timeout(partial: "")) }
    }
    func testSendReturnsReplyWithoutEchoAndPrompt() async throws {
        let (s, f, t) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "i\r": "i\r\n\r\nBus Pirate 5 REV10\r\nActive mode: HiZ\r\n\r\nHiZ> "]
        try await s.start()
        let reply = try await s.send("i")
        XCTAssertEqual(reply, "Bus Pirate 5 REV10\r\nActive mode: HiZ")
        XCTAssertTrue(t.plainText().contains(">> i"))
    }
    func testSendTracksModeChange() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "m i2c\r": "m i2c\r\nMode: I2C\r\nI2C> "]
        try await s.start(); _ = try await s.send("m i2c")
        let mode = await s.currentMode
        XCTAssertEqual(mode, "I2C")
    }
    func testSendTimeoutCarriesPartialText() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "?\r": "?\r\nGeneral commands\r\n--more--"]
        try await s.start()
        do { _ = try await s.send("?", timeout: .milliseconds(300)); XCTFail() }
        catch { XCTAssertEqual(error as? SessionError, .timeout(partial: "General commands\r\n--more--")) }
    }
    func testSendThrowsDisconnectedWhenStreamEnds() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> "]
        try await s.start(); f.disconnect()
        do { _ = try await s.send("i"); XCTFail() }
        catch { XCTAssertEqual(error as? SessionError, .disconnected) }
    }
    func testShutdownSendsHiZOnlyWhenNotInHiZ() async throws {
        let (s, f, _) = makeSession()
        f.autoReplies = ["\r": "HiZ> ", "m i2c\r": "I2C> ", "m hiz\r": "HiZ> "]
        try await s.start(); await s.shutdown()
        XCTAssertFalse(f.written.contains("m hiz\r"))
        let (s2, f2, _) = makeSession()
        f2.autoReplies = f.autoReplies
        try await s2.start(); _ = try await s2.send("m i2c"); await s2.shutdown()
        XCTAssertTrue(f2.written.contains("m hiz\r"))
    }
}
```

- [ ] **Step 2: Run `swift test --filter SessionTests`.** Expected: compile failure.
- [ ] **Step 3: Implement `BusPirateSession`.** One long-lived task reads `transport.incoming` into an actor buffer; `send` and `start` wait on the buffer with a deadline.
- [ ] **Step 4: Run `swift test`.** Expected: 0 failures.
- [ ] **Step 5: Commit:** `feat: Bus Pirate session actor`

### Task 4: DeviceInfo and PortFinder

**Files:**
- Create: `Sources/PirateDeckCore/DeviceInfo.swift`, `Sources/PirateDeckCore/PortFinder.swift`, `Tests/PirateDeckCoreTests/Fixtures.swift`
- Test: `Tests/PirateDeckCoreTests/DeviceInfoTests.swift`, `Tests/PirateDeckCoreTests/PortFinderTests.swift`

**Interfaces:**
- Produces:
  - `public struct DeviceInfo: Equatable, Sendable { public let hardware: String; public let firmware: String; public let commit: String?; public let buildDate: String?; public let modes: [String]; public let raw: String }`
  - `public static func DeviceInfo.parse(_ reply: String) -> DeviceInfo?` returns nil if no line starts with `Bus Pirate`.
  - `public static let DeviceInfo.testedCommit = "e9cb31e"`
  - `public enum PortFinder { public static func terminalPort(from names: [String]) -> PortChoice }`
  - `public enum PortChoice: Equatable { case found(String), none, ambiguous([String]) }`
  - `public static func PortFinder.listDevNames() -> [String]` (contents of `/dev`)

Port rule (from the real device: `/dev/cu.usbmodem5buspirate1` is the terminal, `/dev/cu.usbmodem5buspirate3` is the binary port): keep names that start with `cu.usbmodem` and contain `buspirate` (case-insensitive). Group by the name without its last character. One group: `.found("/dev/" + lowest name)`. More than one group: `.ambiguous` with the lowest name of each group. No match: `.none`. The app never opens a port that does not contain `buspirate`.

- [ ] **Step 1: Write `Fixtures.swift`** with `static let infoReply` set to this exact text:

```
Bus Pirate 5 REV10
https://BusPirate.com/
Firmware main branch @ e9cb31e (Nov 20 2026 08:39:34)
RP2040 with 264KB RAM, 128Mbit FLASH
S/N: 0000000000000000
Storage: 0.10GB Micron (FAT16 File System)
Terminal: 80x25

Configuration file: Not Detected
Active binmode: SUMP logic analyzer
Available modes: HiZ 1WIRE UART HDUART I2C SPI 2WIRE 3WIRE DIO LED INFRARED JTAG PS2 USB
Active mode: HiZ

Display format: Auto
```

and `static let oldInfoReply` with the factory text (`Bus Pirate 5 REV10` / `Firmware v0.1.0 (commit unknown)` / `Available modes: HiZ 1-WIRE UART I2C SPI LED`).

- [ ] **Step 2: Write the failing tests**

```swift
final class DeviceInfoTests: XCTestCase {
    func testParsesCurrentFirmware() {
        let d = DeviceInfo.parse(Fixtures.infoReply)!
        XCTAssertEqual(d.hardware, "Bus Pirate 5 REV10")
        XCTAssertEqual(d.firmware, "main branch @ e9cb31e (Nov 20 2026 08:39:34)")
        XCTAssertEqual(d.commit, "e9cb31e")
        XCTAssertEqual(d.buildDate, "Nov 20 2026 08:39:34")
        XCTAssertEqual(d.modes.count, 14)
        XCTAssertEqual(d.modes.first, "HiZ"); XCTAssertEqual(d.modes.last, "USB")
    }
    func testParsesFactoryFirmwareWithoutCommit() {
        let d = DeviceInfo.parse(Fixtures.oldInfoReply)!
        XCTAssertEqual(d.firmware, "v0.1.0 (commit unknown)")
        XCTAssertNil(d.commit); XCTAssertNil(d.buildDate)
        XCTAssertEqual(d.modes, ["HiZ", "1-WIRE", "UART", "I2C", "SPI", "LED"])
    }
    func testRejectsOtherText() {
        XCTAssertNil(DeviceInfo.parse("ets Jul 29 2019 12:21:46\r\nrst:0x1"))
        XCTAssertNil(DeviceInfo.parse(""))
    }
    func testHandlesCRLFAndLeadingBlankLines() {
        XCTAssertNotNil(DeviceInfo.parse("\r\n" + Fixtures.infoReply.replacingOccurrences(of: "\n", with: "\r\n")))
    }
}
final class PortFinderTests: XCTestCase {
    func testFindsTerminalPortAndIgnoresOtherDevices() {
        let names = ["cu.usbmodem1301", "cu.usbmodem5buspirate3", "cu.usbmodem5buspirate1", "tty.usbmodem5buspirate1", "cu.Bluetooth-Incoming-Port"]
        XCTAssertEqual(PortFinder.terminalPort(from: names), .found("/dev/cu.usbmodem5buspirate1"))
    }
    func testNoBusPirate() {
        XCTAssertEqual(PortFinder.terminalPort(from: ["cu.usbmodem1301"]), PortChoice.none)
    }
    func testTwoBusPiratesAreAmbiguous() {
        let names = ["cu.usbmodem5buspirate1", "cu.usbmodem5buspirate3", "cu.usbmodem7buspirate1", "cu.usbmodem7buspirate3"]
        XCTAssertEqual(PortFinder.terminalPort(from: names), .ambiguous(["/dev/cu.usbmodem5buspirate1", "/dev/cu.usbmodem7buspirate1"]))
    }
}
```

- [ ] **Step 3: Run `swift test`.** Expected: compile failure.
- [ ] **Step 4: Implement both files.** `commit` comes from `@ <hex>`; `buildDate` from the text in the parentheses after it.
- [ ] **Step 5: Run `swift test`.** Expected: 0 failures.
- [ ] **Step 6: Commit:** `feat: device info parser and port finder`

### Task 5: POSIX serial port

**Files:**
- Create: `Sources/PirateDeckCore/POSIXSerialPort.swift`

**Interfaces:**
- Consumes: `ByteTransport`, `TransportError`
- Produces: `public final class POSIXSerialPort: ByteTransport` with `public init(path: String, baud: speed_t = 115200) throws`. Opens with `O_RDWR | O_NOCTTY | O_NONBLOCK`, then clears `O_NONBLOCK`, calls `cfmakeraw`, sets 8N1, `CLOCAL | CREAD`, `VMIN = 1`, `VTIME = 0`, and takes an exclusive lock with `ioctl(fd, TIOCEXCL)`. A background thread calls `read`; a result of 0 or an error finishes `incoming` (this is the unplug case). `close()` is safe to call two times.

- [ ] **Step 1: Write the failing test** in `Tests/PirateDeckCoreTests/SerialPortTests.swift`

```swift
final class SerialPortTests: XCTestCase {
    func testOpenFailsForMissingPath() {
        XCTAssertThrowsError(try POSIXSerialPort(path: "/dev/cu.does-not-exist")) {
            guard case TransportError.openFailed = $0 else { return XCTFail() }
        }
    }
    func testRoundTripAndDisconnectOnPseudoTerminal() async throws {
        var master: Int32 = 0, slave: Int32 = 0
        var name = [CChar](repeating: 0, count: 128)
        XCTAssertEqual(openpty(&master, &slave, &name, nil, nil), 0)
        Darwin.close(slave)
        let port = try POSIXSerialPort(path: String(cString: name))
        XCTAssertEqual(Darwin.write(master, "HiZ> ", 5), 5)
        var it = port.incoming.makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first.map { String(decoding: $0, as: UTF8.self) }, "HiZ> ")
        try port.write(Data("i\r".utf8))
        var buf = [UInt8](repeating: 0, count: 8)
        XCTAssertEqual(Darwin.read(master, &buf, 8), 2)
        Darwin.close(master)                      // same as unplug
        let end = await it.next()
        XCTAssertNil(end)
        XCTAssertThrowsError(try port.write(Data("x".utf8)))
    }
}
```

- [ ] **Step 2: Run `swift test --filter SerialPortTests`.** Expected: compile failure.
- [ ] **Step 3: Implement `POSIXSerialPort`.**
- [ ] **Step 4: Run `swift test`.** Expected: 0 failures. If the baud-rate call fails on a pseudo-terminal, ignore `cfsetspeed` errors only when `isatty` is true and the path starts with `/dev/ttys`.
- [ ] **Step 5: Commit:** `feat: POSIX serial transport`

### Task 6: App UI and bundle script

**Files:**
- Create: `Sources/PirateDeck/AppModel.swift`, `Sources/PirateDeck/ContentView.swift`, `scripts/make-app.sh`, `README.md`
- Modify: `Sources/PirateDeck/PirateDeckApp.swift`

**Interfaces:**
- Consumes: all of `PirateDeckCore`
- Produces:
  - `@MainActor @Observable final class AppModel` with
    - `enum ConnectionState: Equatable { case disconnected(message: String?), searching, connected(port: String, info: DeviceInfo), chooseDevice([String]) }`
    - `var state: ConnectionState`, `var consoleText: String`, `var isBusy: Bool`
    - `func connect(path: String? = nil) async`, `func disconnect() async`, `func sendLine(_ line: String) async`, `func copyTranscript()` (puts `transcript.plainText()` on `NSPasteboard.general`)
  - `connect` flow: `PortFinder` then `POSIXSerialPort` then `session.start()` then `session.send("i")` then `DeviceInfo.parse`. If parse returns nil, stay connected and show the raw reply in the console with the status text "Connected. Device information was not read."
  - `sendLine` on `SessionError.timeout(partial:)`: keep the connection, the partial text is already in the console. On `.disconnected` or `TransportError`: state becomes `.disconnected(message: "The Bus Pirate was disconnected.")`.

UI text and layout (fixed by the spec):
- Status bar: a colored dot, and one of `Not connected` / `Searching...` / `<hardware>, firmware <commit> (<build date>) on <port>`. Buttons: `Connect` or `Disconnect`.
- If `info.commit != DeviceInfo.testedCommit`: a yellow notice, "This firmware is different from the tested build (e9cb31e). Some functions can fail."
- `.none` from PortFinder: message "No Bus Pirate found. Connect the USB cable, then click Connect."
- `.chooseDevice`: a list of the ports with a Connect button for each.
- Middle area: placeholder text "Setup and wiring come in the next version."
- Console: a `DisclosureGroup("Console")`, closed by default. Monospaced, read-only, scrolls to the end on new text. Below it: a text field (Return sends the line, disabled while `isBusy`), and buttons `Copy Transcript` and `Clear`.
- App quit (`NSApplication.willTerminateNotification`) and window close call `disconnect()`, which calls `session.shutdown()`.
- Window minimum size 720 x 480.

`scripts/make-app.sh`: runs `swift build -c release`, creates `PirateDeck.app/Contents/{MacOS,Info.plist}`, copies `.build/release/PirateDeck`, writes `Info.plist` with `CFBundleIdentifier` `com.mothmantech.PirateDeck`, `CFBundleName` `PirateDeck`, `CFBundleExecutable` `PirateDeck`, `CFBundlePackageType` `APPL`, `LSMinimumSystemVersion` `14.0`, `NSHighResolutionCapable` true, then runs `codesign --force --sign - PirateDeck.app`.

- [ ] **Step 1: Implement `AppModel`, `ContentView`, update `PirateDeckApp`.**
- [ ] **Step 2: Run `swift build` and `swift test`.** Expected: `Build complete!` and 0 failures.
- [ ] **Step 3: Write `scripts/make-app.sh` and `README.md`** (what the app is, build and run steps, the transcript command list below).
- [ ] **Step 4: Run `bash scripts/make-app.sh && test -x PirateDeck.app/Contents/MacOS/PirateDeck && echo OK`.** Expected: `OK`.
- [ ] **Step 5: Commit:** `feat: app window with status bar and console`

### Task 7: Hardware check by Brian (manual)

This task has no code. Claude cannot do it.

- [ ] **Step 1:** Close all other terminal sessions on the Bus Pirate (`screen`). The port can have only one user.
- [ ] **Step 2:** Open `PirateDeck.app`. Click Connect. Expected: the status bar shows `Bus Pirate 5 REV10, firmware e9cb31e (Nov 20 2026 08:39:34) on /dev/cu.usbmodem5buspirate1`.
- [ ] **Step 3:** Open the console. Send these lines, one at a time, with nothing connected to the Bus Pirate pins: `i`, `v`, `m`, then `x`, `m i2c`, then Enter for each default, `i`, `v`, `W 3.3`, `v`, `P`, `v`, `scan`, `w`, `p`, `m spi`, defaults, `v`, `m uart`, defaults, `v`, `m hiz`, `W -h`, `m -h`.
- [ ] **Step 4:** Click Copy Transcript and paste the text to Claude.
- [ ] **Step 5:** Remove the USB cable while connected. Expected: status shows "The Bus Pirate was disconnected." and the app does not crash.
- [ ] **Step 6:** Connect the cable, click Connect, send `m i2c`, quit the app, open `screen` on the port, press Enter. Expected: the prompt is `HiZ>`.
