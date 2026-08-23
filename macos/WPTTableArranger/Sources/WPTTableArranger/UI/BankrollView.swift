import SwiftUI

/// Port of BankrollWindow in main.py: summary stats + session log table.
struct BankrollView: View {
    @State private var rows: [SessionLogEntry] = Store.readSessionLogRows()

    private var profits: [Double] { rows.compactMap { $0.profit } }
    private var totalProfit: Double { profits.reduce(0, +) }
    private var winRate: Double {
        guard !profits.isEmpty else { return 0 }
        return Double(profits.filter { $0 > 0 }.count) / Double(profits.count) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .background(Palette.bg)
    }

    private var header: some View {
        HStack {
            Text(t("bankroll_title")).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.text)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Palette.surface)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                Text(String(format: "%+.2f", totalProfit))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(totalProfit >= 0 ? Palette.green : Palette.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t("sessions_tracked", ["n": profits.count])).font(.system(size: 8)).foregroundColor(Palette.dim)
                    Text(t("win_rate", ["v": String(format: "%.0f", winRate)])).font(.system(size: 8)).foregroundColor(Palette.dim)
                }
            }

            if rows.isEmpty {
                Text(t("no_sessions")).font(.system(size: 9)).foregroundColor(Palette.dim)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        row(t("col_date"), t("col_time"), t("col_buyin"), t("col_cashout"), t("col_profit"), t("col_note"),
                            font: .system(size: 8, weight: .bold), color: Palette.dim)
                        .padding(.bottom, 4)

                        ForEach(Array(rows.reversed().enumerated()), id: \.offset) { _, entry in
                            row(entry.date, entry.durationHMS,
                                entry.buyIn.map { String(format: "%.2f", $0) } ?? "—",
                                entry.cashOut.map { String(format: "%.2f", $0) } ?? "—",
                                entry.profit.map { String(format: "%+.2f", $0) } ?? "—",
                                entry.note, font: .system(size: 8), color: Palette.text)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func row(_ date: String, _ time: String, _ buyIn: String, _ cashOut: String,
                      _ profit: String, _ note: String, font: Font, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(date).frame(width: 78, alignment: .leading)
            Text(time).frame(width: 58, alignment: .leading)
            Text(buyIn).frame(width: 56, alignment: .trailing)
            Text(cashOut).frame(width: 62, alignment: .trailing)
            Text(profit).frame(width: 62, alignment: .trailing)
            Text(note).frame(minWidth: 80, alignment: .leading)
        }
        .font(font)
        .foregroundColor(color)
    }
}
