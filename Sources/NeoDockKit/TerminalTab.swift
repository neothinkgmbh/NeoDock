import Foundation

/// Springt in Terminal.app auf den Tab eines Terminals.
public enum TerminalTab {
    /// AppleScript für `tty`, z. B. `/dev/ttys000`. Der Pfad landet im Skript, deshalb nur dieses Format.
    /// `frontmost` statt `index`: Bei einem Terminal im Hintergrund bleibt `index` wirkungslos (gemessen).
    public static func selectScript(tty: String) -> String? {
        guard tty.wholeMatch(of: /\/dev\/ttys[0-9]+/) != nil else { return nil }
        return """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set miniaturized of w to false
                        set selected of t to true
                        set frontmost of window id (id of w) to true
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
    }
}
