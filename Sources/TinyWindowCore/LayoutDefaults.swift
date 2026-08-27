import Foundation

/// Starter layouts seeded on first run when the user has no Window Tidy data
/// to import (mirrors the classic Window Tidy default set).
public enum LayoutDefaults {
    public static func starterSet() -> [Layout] {
        func grid(_ name: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Layout {
            Layout(name: name,
                   kind: .grid(.init(columns: 6, rows: 6, cellX: x, cellY: y, cellW: w, cellH: h)),
                   origin: .builtin)
        }
        return [
            grid("Left Half", 0, 0, 3, 6),
            grid("Right Half", 3, 0, 3, 6),
            grid("Full Screen", 0, 0, 6, 6),
            grid("Centre", 1, 1, 4, 4),
            grid("Top Left Quarter", 0, 0, 3, 3),
            grid("Top Right Quarter", 3, 0, 3, 3),
            grid("Bottom Left Quarter", 0, 3, 3, 3),
            grid("Bottom Right Quarter", 3, 3, 3, 3),
        ]
    }
}
