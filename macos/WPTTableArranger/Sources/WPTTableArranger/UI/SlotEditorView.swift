import SwiftUI
import AppKit

/// Port of SlotEditorWindow in main.py: per-slot X/Y/W/H rows with add/remove/grid buttons
/// and a live preview.
struct SlotEditorView: View {
    let screenSize: CGSize
    let onSave: ([Slot]) -> Void

    @State private var slots: [Slot]
    @State private var hostWindow: NSWindow?
    @State private var alert: AlertInfo?

    init(initialSlots: [Slot], screenSize: CGSize, onSave: @escaping ([Slot]) -> Void) {
        self._slots = State(initialValue: initialSlots)
        self.screenSize = screenSize
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 14) {
                rowsList
                previewSection
            }
            .padding(14)
            Spacer(minLength: 0)
            footer
        }
        .background(Palette.bg)
        .background(WindowAccessor { hostWindow = $0 })
        .alert(item: $alert) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
    }

    private var header: some View {
        HStack {
            Text(t("edit_slots_title")).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.text)
            Spacer()
            Text(t("max_n", ["n": maxSlots])).font(.system(size: 9)).foregroundColor(Palette.dim)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Palette.surface)
    }

    private var rowsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Color.clear.frame(width: 14, height: 1)
                ForEach(["X", "Y", "W", "H"], id: \.self) { label in
                    Text(label).font(.system(size: 8)).foregroundColor(Palette.dim).frame(width: 52, alignment: .center)
                }
            }
            ForEach(slots.indices, id: \.self) { i in
                HStack(spacing: 3) {
                    Circle().fill(Palette.slotColors[i % Palette.slotColors.count]).frame(width: 10, height: 10)
                    intField(Binding(get: { slots[i].x }, set: { slots[i].x = $0 }))
                    intField(Binding(get: { slots[i].y }, set: { slots[i].y = $0 }))
                    intField(Binding(get: { slots[i].width }, set: { slots[i].width = $0 }))
                    intField(Binding(get: { slots[i].height }, set: { slots[i].height = $0 }))
                }
            }
        }
    }

    private func intField(_ value: Binding<Int>) -> some View {
        TextField("", value: value, formatter: NumberFormatter())
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 9))
            .foregroundColor(Palette.text)
            .padding(4)
            .frame(width: 52)
            .background(Palette.card)
            .cornerRadius(3)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("preview_label")).font(.system(size: 8)).foregroundColor(Palette.dim)
            PreviewCanvasView(slots: slots, screenSize: screenSize)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            ActionButton(title: t("add_slot"), bg: Palette.card, fg: Palette.text,
                         font: .system(size: 9, weight: .bold)) { addSlot() }.fixedSize()
            ActionButton(title: t("remove_slot"), bg: Palette.card, fg: Palette.text,
                         font: .system(size: 9, weight: .bold)) { removeLast() }.fixedSize()
            ActionButton(title: t("grid_3x2"), bg: Palette.card, fg: Palette.text,
                         font: .system(size: 9, weight: .bold)) { resetGrid() }.fixedSize()
            Spacer()
            ActionButton(title: t("save"), bg: Palette.green, fg: Palette.text,
                         font: .system(size: 9, weight: .bold)) { save() }.fixedSize()
        }
        .padding(14)
        .background(Palette.surface)
    }

    private func renumber() {
        for i in slots.indices { slots[i].id = i + 1 }
    }

    private func addSlot() {
        guard slots.count < maxSlots else {
            alert = AlertInfo(title: t("max_reached_title"), message: t("max_reached_msg", ["n": maxSlots]))
            return
        }
        slots.append(Slot(id: slots.count + 1, x: 0, y: 0,
                           width: Int(screenSize.width) / 3, height: Int(screenSize.height) / 2))
    }

    private func removeLast() {
        guard slots.count > 1 else { return }
        slots.removeLast()
    }

    private func resetGrid() {
        slots = defaultSlots(screenWidth: Int(screenSize.width), screenHeight: Int(screenSize.height))
    }

    private func save() {
        renumber()
        Store.saveConfig(slots)
        onSave(slots)
        hostWindow?.close()
    }
}
