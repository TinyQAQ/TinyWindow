import CoreGraphics
import TinyWindowCore

func runGridMathChecks() {
    print("— GridMath")

    // Boundaries are monotone and cover [0, length] exactly; cell sizes differ ≤ 1 pt.
    for length: CGFloat in [5120, 5119, 1001, 100] {
        for count in [6, 5, 3] {
            let bounds = (0...count).map { GridMath.boundary($0, count: count, length: length) }
            expect(bounds.first == 0, "first boundary 0 for \(length)/\(count)")
            expect(bounds.last == length.rounded(), "last boundary covers length for \(length)/\(count)")
            for i in 1...count {
                expect(bounds[i] > bounds[i - 1], "monotone at \(i) for \(length)/\(count)")
            }
            let sizes = (1...count).map { bounds[$0] - bounds[$0 - 1] }
            expect((sizes.max()! - sizes.min()!) <= 1, "cell sizes within 1 pt for \(length)/\(count)")
        }
    }

    // Adjacent cell ranges share the exact same edge (no 1-px gap or overlap).
    let container = CGRect(x: 0, y: 0, width: 1001, height: 997)
    let left = GridMath.rect(
        for: .init(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 3, cellH: 6), in: container)
    let right = GridMath.rect(
        for: .init(columns: 6, rows: 6, cellX: 3, cellY: 0, cellW: 3, cellH: 6), in: container)
    expect(left.maxX == right.minX, "left half and right half share one edge")
    expect(left.minX == container.minX, "left half starts at container edge")
    expect(right.maxX == container.maxX, "right half ends at container edge")

    // Full span equals the container.
    let odd = CGRect(x: 13, y: 27, width: 2560, height: 1415)
    let full = GridMath.rect(
        for: .init(columns: 6, rows: 6, cellX: 0, cellY: 0, cellW: 6, cellH: 6), in: odd)
    expect(full == odd, "full span equals container")

    // Row 0 is at the top (minY side of a Quartz container).
    let square = CGRect(x: 0, y: 0, width: 600, height: 600)
    let topLeft = GridMath.rect(
        for: .init(columns: 2, rows: 2, cellX: 0, cellY: 0, cellW: 1, cellH: 1), in: square)
    expect(topLeft == CGRect(x: 0, y: 0, width: 300, height: 300), "row 0 is at top")

    // Out-of-range specs are clamped, never crash or go empty.
    let clamped = GridMath.rect(
        for: .init(columns: 4, rows: 4, cellX: 9, cellY: -2, cellW: 99, cellH: 0), in: square)
    expect(square.contains(clamped), "clamped inside container")
    expect(!clamped.isEmpty, "clamped rect not empty")
}
