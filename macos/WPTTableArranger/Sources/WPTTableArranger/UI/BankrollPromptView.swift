import SwiftUI
import AppKit

/// Port of BankrollPromptDialog in main.py — shown automatically when a session ends.
struct BankrollPromptView: View {
    let elapsed: TimeInterval
    let onResult: (Double?, Double?, String) -> Void

    @State private var buyIn = ""
    @State private var cashOut = ""
    @State private var note = ""
    @State private var hostWindow: NSWindow?

    private var hmsText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 10) {
                Text(t("played_for", ["hms": hmsText])).font(.system(size: 9)).foregroundColor(Palette.dim)
                field(t("col_buyin"), $buyIn)
                field(t("col_cashout"), $cashOut)
                Text(t("note_optional")).font(.system(size: 8)).foregroundColor(Palette.dim)
                TextField("", text: $note).textFieldStyle(.roundedBorder)
            }
            .padding(16)
            Spacer(minLength: 0)
            HStack {
                ActionButton(title: t("skip"), bg: Palette.card, fg: Palette.text,
                             font: .system(size: 9, weight: .bold)) { skip() }.fixedSize()
                Spacer()
                ActionButton(title: t("save"), bg: Palette.green, fg: Palette.text,
                             font: .system(size: 9, weight: .bold)) { save() }.fixedSize()
            }
            .padding(16)
            .background(Palette.surface)
        }
        .background(Palette.bg)
        .background(WindowAccessor { hostWindow = $0 })
    }

    private var header: some View {
        HStack {
            Text(t("session_ended_title")).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.text)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Palette.surface)
    }

    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading).font(.system(size: 9)).foregroundColor(Palette.text)
            TextField("", text: binding).textFieldStyle(.roundedBorder)
        }
    }

    private func skip() {
        onResult(nil, nil, "")
        hostWindow?.close()
    }

    private func save() {
        onResult(Double(buyIn), Double(cashOut), note.trimmingCharacters(in: .whitespacesAndNewlines))
        hostWindow?.close()
    }
}
