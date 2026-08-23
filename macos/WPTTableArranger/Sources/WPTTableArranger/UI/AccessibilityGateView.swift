import SwiftUI

/// Blocking screen shown until Accessibility permission is granted — the one permission this
/// app needs, since it reads/moves other apps' windows via the Accessibility API.
struct AccessibilityGateView: View {
    let onRecheck: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(t("accessibility_needed_title"))
                .font(.system(size: 14, weight: .bold)).foregroundColor(Palette.text)
            Text(t("accessibility_needed_msg"))
                .font(.system(size: 11)).foregroundColor(Palette.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            HStack(spacing: 8) {
                ActionButton(title: t("open_settings"), bg: Palette.accent, fg: Palette.text,
                             font: .system(size: 10, weight: .bold)) {
                    Accessibility.openAccessibilitySettings()
                }.fixedSize()
                ActionButton(title: t("recheck"), bg: Palette.card, fg: Palette.text,
                             font: .system(size: 10, weight: .bold)) {
                    onRecheck()
                }.fixedSize()
            }
        }
        .padding(24)
        .frame(width: 380, height: 220)
        .background(Palette.bg)
    }
}
