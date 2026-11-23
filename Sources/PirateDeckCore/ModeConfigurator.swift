import Foundation

public enum ConfigError: Error, Equatable {
    case modeNotReached(got: String?)
}

/// Sends `m <mode>` and answers the setup menus by their titles.
public enum ModeConfigurator {
    /// Returns the titles of menus that the app did not know. For these menus
    /// it sends Return (the default). It never sends a guessed value.
    public static func enter(_ mode: BusMode, settings: ModeSettings,
                             session: BusPirateSession) async throws -> [String] {
        let answers = settings.menuAnswers(for: mode)
        var unknown: [String] = []
        var reply = try await session.sendInteractive(mode.command)
        for _ in 0..<12 {
            if await session.isAtModePrompt {
                let current = await session.currentMode
                if current?.lowercased() == mode.rawValue.lowercased() { return unknown }
                throw ConfigError.modeNotReached(got: current)
            }
            if reply.contains("Use previous settings?") {
                reply = try await session.sendInteractive("n")
                continue
            }
            if let title = answers.keys.sorted(by: { $0.count > $1.count }).first(where: { reply.contains($0) }),
               let answer = answers[title] {
                reply = try await session.sendInteractive(answer)
            } else {
                unknown.append(menuTitle(in: reply))
                reply = try await session.sendInteractive("")
            }
        }
        throw ConfigError.modeNotReached(got: await session.currentMode)
    }

    /// The first line of a menu that is not the "Mode: X" line.
    static func menuTitle(in reply: String) -> String {
        collapseCarriageReturns(reply)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("Mode:") }) ?? "(no title)"
    }
}
