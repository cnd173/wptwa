import SwiftUI
import AppKit

/// Port of App/_build_ui in main.py: branding column, preview canvas, and controls.
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var localizer = Localizer.shared
    private let screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            brandingColumn
            previewColumn
            controlsColumn
        }
        .padding(10)
        .background(Palette.bg)
        .frame(width: 620)
        .alert(item: $model.activeAlert) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Branding

    private var brandingColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("POKER").font(.system(size: 16, weight: .bold)).foregroundColor(Palette.accent)
            Text(t("brand_sub")).font(.system(size: 11, weight: .bold)).foregroundColor(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            Text(t("slots_configured", ["n": model.slots.count]))
                .font(.system(size: 7)).foregroundColor(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                languageButton(code: "vi", label: "VI")
                languageButton(code: "en", label: "EN")
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(width: 108, alignment: .leading)
    }

    private func languageButton(code: String, label: String) -> some View {
        Button(label) { Localizer.shared.setLanguage(code) }
            .buttonStyle(.plain)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundColor(Palette.text)
            .background(localizer.current == code ? Palette.accent : Palette.card)
            .cornerRadius(3)
    }

    // MARK: - Preview

    private var previewColumn: some View {
        VStack(spacing: 2) {
            PreviewCanvasView(
                slots: model.slots, screenSize: screenSize,
                occupiedSlotIds: model.arranging ? model.occupiedSlotIds : nil,
                magnetEnabled: model.magnetEnabled,
                onSwap: { a, b in model.swapSlots(a, b) }
            )
            Text(t("drag_to_swap")).font(.system(size: 7)).foregroundColor(Palette.dim)
            Toggle(isOn: $model.magnetEnabled) {
                Text(t("magnet")).font(.system(size: 8)).foregroundColor(Palette.dim)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 2)
        }
    }

    // MARK: - Controls

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(model.dotColor).frame(width: 10, height: 10)
                Text(model.statusText).font(.system(size: 9)).foregroundColor(Palette.dim)
            }

            HStack(spacing: 6) {
                Text(t("session_label")).font(.system(size: 7, weight: .bold)).foregroundColor(Palette.dim)
                Text(model.sessionElapsedText).font(.system(size: 9, weight: .bold)).foregroundColor(Palette.text)
                Spacer()
                Button(model.sessionState == .running ? "‖" : "▶") { model.timerToggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Palette.card)
                    .cornerRadius(3)
                    .help(model.sessionState == .running ? t("pause_session") : t("start_session"))
                Button("■") { model.timerStop() }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(model.sessionState == .stopped ? Palette.dim : Palette.text)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Palette.card)
                    .cornerRadius(3)
                    .disabled(model.sessionState == .stopped)
                    .help(t("stop_session"))
            }

            ActionButton(
                title: model.arranging ? t("stop_arranging") : t("start_arranging"),
                bg: model.arranging ? Palette.red : Palette.green, fg: Palette.text,
                font: .system(size: 10, weight: .bold)
            ) { model.toggleArranging() }

            HStack(spacing: 2) {
                ActionButton(title: t("btn_slots"), bg: Palette.card, fg: Palette.text,
                             font: .system(size: 8, weight: .bold)) { openSlotEditor() }
                ActionButton(title: t("btn_reset"), bg: Palette.card, fg: Palette.text,
                             font: .system(size: 8, weight: .bold)) { model.rearrange() }
                ActionButton(title: t("btn_bankroll"), bg: Palette.card, fg: Palette.text,
                             font: .system(size: 8, weight: .bold)) { openBankroll() }
            }

            ActionButton(title: t("btn_log_entry"), bg: Palette.accent, fg: Palette.text,
                         font: .system(size: 9, weight: .bold)) { openBankrollEntry() }

            Toggle(isOn: Binding(get: { model.autostartEnabled }, set: { model.setAutostart($0) })) {
                Text(t("start_with_windows")).font(.system(size: 8)).foregroundColor(Palette.dim)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 4)

            presetSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(Palette.border).frame(height: 1).padding(.vertical, 4)
            Text(t("presets_label")).font(.system(size: 7, weight: .bold)).foregroundColor(Palette.dim)

            HStack(spacing: 3) {
                Picker("", selection: Binding(get: { model.selectedPreset ?? "" }, set: { model.selectedPreset = $0 })) {
                    if model.presets.isEmpty {
                        Text(t("no_presets")).tag("")
                    } else {
                        ForEach(model.presets.keys.sorted(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                ActionButton(title: t("load_btn"), bg: Palette.accent, fg: Palette.text,
                             font: .system(size: 8, weight: .bold)) { model.loadSelectedPreset() }
                    .fixedSize()
                ActionButton(title: "✕", bg: Palette.card, fg: Palette.text,
                             font: .system(size: 8, weight: .bold)) { model.deleteSelectedPreset() }
                    .fixedSize()
            }

            ActionButton(title: t("save_as_preset"), bg: Palette.card, fg: Palette.text,
                         font: .system(size: 8, weight: .bold)) { promptSavePreset() }
        }
    }

    // MARK: - Actions

    private func promptSavePreset() {
        let alert = NSAlert()
        alert.messageText = t("save_preset_title")
        alert.informativeText = t("save_preset_prompt")
        alert.addButton(withTitle: t("save"))
        alert.addButton(withTitle: t("cancel"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = input
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            model.savePreset(name: input.stringValue)
        }
    }

    private func openSlotEditor() {
        let controller = PanelWindowController(
            title: t("edit_slots_title"), width: 460, height: 380,
            content: SlotEditorView(initialSlots: model.slots, screenSize: screenSize) { newSlots in
                model.updateSlots(newSlots)
            }
        )
        model.slotEditorWindow = controller
        controller.show()
    }

    private func openBankroll() {
        model.bankrollWindow?.window?.close()
        let controller = PanelWindowController(title: t("bankroll_title"), width: 420, height: 380, content: BankrollView())
        model.bankrollWindow = controller
        controller.show()
    }

    private func openBankrollEntry() {
        let controller = PanelWindowController(
            title: t("add_entry_title"), width: 260, height: 260,
            content: BankrollEntryView { date, buyIn, cashOut, note in
                let dt = Calendar.current.startOfDay(for: date)
                model.logSession(start: dt, end: dt, seconds: 0, buyIn: buyIn, cashOut: cashOut, note: note)
                model.bankrollEntryWindow?.window?.close()
                if model.bankrollWindow?.window?.isVisible == true {
                    openBankroll() // refresh if it's currently open
                }
            }
        )
        model.bankrollEntryWindow = controller
        controller.show()
    }
}
