import Foundation

/// Zufallspasswörter aus SystemRandomNumberGenerator (kryptografisch sicher auf Apple-Plattformen),
/// ohne leicht verwechselbare Zeichen, mit mindestens einem Zeichen jeder Klasse.
public enum PasswordGenerator {
    public static let minimumLength = 8
    static let lower = Array("abcdefghijkmnopqrstuvwxyz")
    static let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("23456789")
    public static let symbols = Array("-_!?#+*")

    public static func generate(length: Int) -> String {
        var rng = SystemRandomNumberGenerator()
        let count = max(length, minimumLength)
        let classes = [lower, upper, digits, symbols]
        let all = classes.flatMap { $0 }
        var chars = classes.map { $0.randomElement(using: &rng)! }
        chars += (chars.count..<count).map { _ in all.randomElement(using: &rng)! }
        chars.shuffle(using: &rng)
        return String(chars)
    }
}
