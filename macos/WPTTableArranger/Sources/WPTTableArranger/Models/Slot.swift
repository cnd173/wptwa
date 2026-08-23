import Foundation

struct Slot: Codable, Identifiable, Equatable {
    var id: Int
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

let maxSlots = 7

/// Same 3x2 grid layout as config.py:default_slots — cols=3, rows=2, height = screenHeight / 2.5.
func defaultSlots(screenWidth: Int, screenHeight: Int) -> [Slot] {
    let cols = 3
    let rows = 2
    let sw = screenWidth / cols
    let sh = Int(Double(screenHeight) / 2.5)
    var slots: [Slot] = []
    for r in 0..<rows {
        for c in 0..<cols {
            slots.append(Slot(id: r * cols + c + 1, x: c * sw, y: r * sh, width: sw, height: sh))
        }
    }
    return slots
}
