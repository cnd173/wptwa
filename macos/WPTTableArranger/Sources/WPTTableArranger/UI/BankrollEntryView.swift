import SwiftUI
import AppKit

/// Port of BankrollEntryDialog in main.py — manual bankroll entry, not tied to a live timer.
struct BankrollEntryView: View {
    let onSave: (Date, Double?, Double?, String) -> Void

    @State private var dateText: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }()
    @State private var buyIn = ""
    @State private var cashOut = ""
    @State private var note = ""
    @State private var hostWindow: NSWindow?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 10) {
                field(t("col_date"), $dateText)
                field(t("col_buyin"), $buyIn)
                field(t("col_cashout"), $cashOut)
                Text(t("note_optional")).font(.system(size: 8)).foregroundColor(Palette.dim)
                TextField("", text: $note).textFieldStyle(.roundedBorder)
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 8)).foregroundColor(Palette.red)
                }
            }
            .padding(16)
            Spacer(minLength: 0)
            HStack {
                ActionButton(title: t("cancel"), bg: Palette.card, fg: Palette.text,
                             font: .system(size: 9, weight: .bold)) { hostWindow?.close() }.fixedSize()
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
            Text(t("add_entry_title")).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.text)
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

    private func save() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateText.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = t("invalid_date_msg")
            return
        }
        onSave(date, Double(buyIn), Double(cashOut), note.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
