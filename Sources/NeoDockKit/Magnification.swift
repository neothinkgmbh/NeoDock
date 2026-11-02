import Foundation

/// Dock-Vergrößerung: eine Kosinus-Glocke um den Zeiger. Gerechnet wird auf den
/// Ruhepositionen der Icons, damit die Vergrößerung das Layout nicht zurückkoppelt.
public enum Magnification {
    public static func scales(pointerX: Double?, centers: [Double], maxScale: Double, reach: Double) -> [Double] {
        guard let x = pointerX, maxScale > 1, reach > 0 else { return centers.map { _ in 1 } }
        return centers.map { center in
            let distance = abs(center - x)
            guard distance < reach else { return 1 }
            return 1 + (maxScale - 1) * (cos(distance / reach * .pi) + 1) / 2
        }
    }

    /// Seitliche Verschiebung je Icon, damit vergrößerte Icons ihre Nachbarn wegschieben
    /// statt sie zu überdecken. `extra` ist die zusätzliche Gesamtbreite, die Verschiebung
    /// ist um die Mitte der Reihe zentriert.
    public static func shifts(scales: [Double], base: Double) -> (shifts: [Double], extra: Double) {
        let growth = scales.map { ($0 - 1) * base }
        let extra = growth.reduce(0, +)
        var before = 0.0
        let shifts = growth.map { g -> Double in
            defer { before += g }
            return before + g / 2 - extra / 2
        }
        return (shifts, extra)
    }
}
