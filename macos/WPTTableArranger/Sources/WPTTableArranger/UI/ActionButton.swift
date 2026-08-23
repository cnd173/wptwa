import SwiftUI

/// Small pill button matching the tkinter `_btn` helper's flat/hover style in main.py.
struct ActionButton: View {
    let title: String
    let bg: Color
    let fg: Color
    var font: Font = .system(size: 12, weight: .bold)
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundColor(fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(hovering ? bg.opacity(0.85) : bg)
        .cornerRadius(4)
        .onHover { hovering = $0 }
    }
}
