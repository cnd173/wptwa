import SwiftUI

/// Port of the PreviewCanvas class in main.py: a scaled visualisation of slot positions
/// with drag-to-swap and magnet snapping. Pass `onSwap` to enable dragging (nil = read-only,
/// as used inside the slot editor).
struct PreviewCanvasView: View {
    static let width: CGFloat = 260
    static let height: CGFloat = 146

    let slots: [Slot]
    let screenSize: CGSize
    var occupiedSlotIds: Set<Int>? = nil // nil = unknown/don't dim
    var magnetEnabled: Bool = false
    var onSwap: ((Int, Int) -> Void)? = nil

    @State private var dragFrom: Int?
    @State private var dragTo: Int?
    @State private var ghostPoint: CGPoint?

    private var scale: CGSize {
        CGSize(width: Self.width / max(screenSize.width, 1), height: Self.height / max(screenSize.height, 1))
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.bg))
            for (i, slot) in slots.enumerated() {
                draw(slot: slot, index: i, context: &context)
            }
            if let ghostPoint, let dragFrom {
                let color = Palette.slotColors[dragFrom % Palette.slotColors.count]
                let r: CGFloat = 7
                let rect = CGRect(x: ghostPoint.x - r, y: ghostPoint.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(Path(ellipseIn: rect), with: .color(Palette.text), lineWidth: 1)
                context.draw(
                    Text("\(dragFrom + 1)").font(.system(size: 6, weight: .bold)).foregroundColor(Palette.text),
                    at: ghostPoint
                )
            }
        }
        .frame(width: Self.width, height: Self.height)
        .background(Palette.bg)
        .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard onSwap != nil else { return }
                if dragFrom == nil {
                    dragFrom = slotIndex(at: value.startLocation)
                }
                guard dragFrom != nil else { return }
                dragTo = targetIndex(at: value.location)
                ghostPoint = value.location
            }
            .onEnded { value in
                defer { dragFrom = nil; dragTo = nil; ghostPoint = nil }
                guard let onSwap, let from = dragFrom else { return }
                if let target = targetIndex(at: value.location), target != from {
                    onSwap(from, target)
                }
            }
    }

    private func rect(for slot: Slot) -> CGRect {
        CGRect(x: CGFloat(slot.x) * scale.width, y: CGFloat(slot.y) * scale.height,
               width: CGFloat(slot.width) * scale.width, height: CGFloat(slot.height) * scale.height)
    }

    private func slotIndex(at point: CGPoint) -> Int? {
        slots.indices.first { rect(for: slots[$0]).contains(point) }
    }

    private func nearestSlotIndex(at point: CGPoint) -> Int? {
        var best: Int?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in slots.indices {
            let r = rect(for: slots[i])
            let center = CGPoint(x: r.midX, y: r.midY)
            let d = pow(center.x - point.x, 2) + pow(center.y - point.y, 2)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    private func targetIndex(at point: CGPoint) -> Int? {
        if let hit = slotIndex(at: point) { return hit }
        return magnetEnabled ? nearestSlotIndex(at: point) : nil
    }

    private func draw(slot: Slot, index: Int, context: inout GraphicsContext) {
        let r = rect(for: slot)
        let color = Palette.slotColors[index % Palette.slotColors.count]
        let isEmpty = occupiedSlotIds != nil && !occupiedSlotIds!.contains(slot.id)

        var fill = Palette.card
        var outline = color
        var lineWidth: CGFloat = 1
        var textColor = color

        if index == dragFrom {
            fill = Palette.surface; outline = color; lineWidth = 1; textColor = Palette.dim
        } else if index == dragTo {
            fill = Palette.card.opacity(0.9); outline = Palette.text; lineWidth = 2; textColor = Palette.text
        } else if isEmpty {
            fill = Palette.bg; outline = Palette.border; lineWidth = 1; textColor = Palette.dim
        }

        let path = Path(r)
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(outline), lineWidth: lineWidth)

        let label: String
        if index == SlotManager.lobbySlotIdx {
            label = "\(index + 1)\nLOBBY"
        } else if index == SlotManager.historySlotIdx {
            label = "\(index + 1)\nHIST"
        } else {
            label = "\(index + 1)"
        }
        let fontSize = max(7, min(11, r.width / 5))
        context.draw(
            Text(label).font(.system(size: fontSize, weight: .bold)).foregroundColor(textColor),
            at: CGPoint(x: r.midX, y: r.midY)
        )
    }
}
