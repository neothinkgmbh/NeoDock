import AppKit
import NeoDockKit

/// Die App-Icons der Tools (wie das Dock sie zeigt): Claude für Claude Code, die Codex-App für Codex.
/// Fehlt eine App, gibt es nil — dann zeigt die Oberfläche das Symbol des Tools.
enum ToolIcons {
    static let claudeAppID = "com.anthropic.claudefordesktop"
    static let bundleIDs: [AgentTool: String] = [.claude: claudeAppID, .codex: "com.openai.codex"]
    private static var cache: [AgentTool: NSImage] = [:]

    static func icon(_ tool: AgentTool) -> NSImage? {
        if let cached = cache[tool] { return cached }
        guard let id = bundleIDs[tool], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[tool] = image
        return image
    }
}
