import Foundation

private let ansiPattern: NSRegularExpression = {
    // CSI sequences (ESC [ params final-byte) and two-byte sequences (ESC 7, ESC 8, ...).
    try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}[78=>cM]")
}()

private let modePromptPattern: NSRegularExpression = {
    try! NSRegularExpression(pattern: "^([A-Za-z0-9-]+)>\\s*$")
}()

/// Removes ANSI / VT100 escape codes from device output.
public func stripANSI(_ text: String) -> String {
    let range = NSRange(text.startIndex..., in: text)
    let noCodes = ansiPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    // The firmware sends ETX (0x03) after each prompt and BEL (0x07) on errors.
    // Remove all control characters except tab, line feed and carriage return.
    let kept = noCodes.unicodeScalars.filter { scalar in
        scalar == "\t" || scalar == "\n" || scalar == "\r" || !(scalar.value < 0x20 || scalar.value == 0x7F)
    }
    return String(String.UnicodeScalarView(kept))
}

private func lastNonEmptyLine(_ text: String) -> String? {
    stripANSI(text)
        .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
        .map(String.init)
        .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
}

/// Returns the mode name (for example "HiZ") if the text ends with a mode prompt.
/// Menu prompts such as "Mode > " have a space before ">" and return nil.
public func modePrompt(in text: String) -> String? {
    guard let line = lastNonEmptyLine(text) else { return nil }
    let range = NSRange(line.startIndex..., in: line)
    guard let match = modePromptPattern.firstMatch(in: line, range: range),
          let nameRange = Range(match.range(at: 1), in: line) else { return nil }
    return String(line[nameRange])
}

/// True if the device asks the VT100 color mode question.
public func isVT100Question(_ text: String) -> Bool {
    guard let line = lastNonEmptyLine(text) else { return false }
    return line.range(of: "VT100", options: .caseInsensitive) != nil
}
