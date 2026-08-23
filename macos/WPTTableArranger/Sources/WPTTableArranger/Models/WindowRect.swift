import Foundation

struct WindowRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

extension Slot {
    var rect: WindowRect { WindowRect(x: x, y: y, width: width, height: height) }
}
