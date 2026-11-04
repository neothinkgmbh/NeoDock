import Foundation

/// Zerlegt die Textausgabe von `/usr/bin/lsappinfo`. LaunchServices führt je App den Wert
/// `LSWantsAttention`; das Werkzeug ist der Weg, ihn ohne private Schnittstellen zu lesen.
public enum LSAppInfo {
    /// `lsappinfo find …` gibt je Treffer eine Zeile `ASN:0x0-0x2edbed9-"Name":`.
    /// Zurück kommt die Schreibweise, die `lsappinfo info` erwartet: `ASN:0x0-0x2edbed9:`.
    public static func asns(inFindOutput output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            line.prefixMatch(of: /ASN:0x[0-9a-fA-F]+-0x[0-9a-fA-F]+/).map { "\($0.output):" }
        }
    }

    /// `lsappinfo info -only pid <ASN>` gibt eine Zeile `    pid = 1781 …`; zu einer beendeten App nichts.
    public static func pid(inInfoOutput output: String) -> Int32? {
        output.firstMatch(of: /(?m)^\s*pid = (\d+)/).flatMap { Int32($0.1) }
    }
}
