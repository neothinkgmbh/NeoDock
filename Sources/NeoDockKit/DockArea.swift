import CoreGraphics

/// Die Fläche, die eine Leiste am unteren Bildschirmrand belegt, wie das System sie als Dock-Fläche
/// führt: Ursprung oben links. Seitlich gibt es das nicht: AppKit zieht auch dann unten ab (gemessen).
public enum DockArea {
    public static func reserved(screen: CGRect, length: CGFloat, depth: CGFloat) -> CGRect {
        CGRect(x: screen.midX - length / 2, y: screen.maxY - depth, width: length, height: depth)
    }

    /// Belegt nichts. So sieht auch die Fläche eines ausgeblendeten macOS-Docks aus.
    public static func free(screen: CGRect) -> CGRect {
        reserved(screen: screen, length: screen.width, depth: 0)
    }

    /// Fenster `frame` (Ursprung oben links) so gekürzt, dass es über `area` endet. Das System reserviert
    /// die ganze Kante, die Länge der Leiste zählt nicht. nil: Es ragt nicht hinein, oder es bliebe
    /// niedriger als `minimum`.
    public static func fitted(_ frame: CGRect, above area: CGRect, minimum: CGFloat) -> CGRect? {
        guard frame.maxY > area.minY else { return nil }
        let height = area.minY - frame.minY
        return height >= minimum ? CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height) : nil
    }
}
