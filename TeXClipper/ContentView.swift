import SwiftUI
import Carbon

struct ContentView: View {
    @State private var recordingShortcut: ShortcutType? = nil
    @State private var renderShortcut: ShortcutConfig
    @State private var renderInlineShortcut: ShortcutConfig
    @State private var revertShortcut: ShortcutConfig
    @State private var launchAtLogin: Bool

    let shortcutManager: ShortcutManager

    enum ShortcutType {
        case render, renderInline, revert
    }

    init(shortcutManager: ShortcutManager? = nil) {
        let manager = shortcutManager ?? ShortcutManager.shared ?? ShortcutManager()
        self.shortcutManager = manager
        self._renderShortcut = State(initialValue: manager.getRenderShortcut())
        self._renderInlineShortcut = State(initialValue: manager.getRenderInlineShortcut())
        self._revertShortcut = State(initialValue: manager.getRevertShortcut())
        self._launchAtLogin = State(initialValue: LoginItemManager.shared.isEnabled)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("TeXClipper Settings")
                .font(.title)
                .padding(.top)

            GroupBox(label: Text("Shortcuts")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Render LaTeX (display mode):")
                        Spacer()
                        ShortcutButton(
                            shortcut: renderShortcut,
                            isRecording: recordingShortcut == .render,
                            onTap: { recordingShortcut = .render },
                            onReset: {
                                renderShortcut = ShortcutManager.defaultRenderShortcut
                                shortcutManager.setRenderShortcut(renderShortcut)
                            }
                        )
                    }

                    HStack {
                        Text("Render LaTeX (inline mode):")
                        Spacer()
                        ShortcutButton(
                            shortcut: renderInlineShortcut,
                            isRecording: recordingShortcut == .renderInline,
                            onTap: { recordingShortcut = .renderInline },
                            onReset: {
                                renderInlineShortcut = ShortcutManager.defaultRenderInlineShortcut
                                shortcutManager.setRenderInlineShortcut(renderInlineShortcut)
                            }
                        )
                    }

                    HStack {
                        Text("Revert to LaTeX:")
                        Spacer()
                        ShortcutButton(
                            shortcut: revertShortcut,
                            isRecording: recordingShortcut == .revert,
                            onTap: { recordingShortcut = .revert },
                            onReset: {
                                revertShortcut = ShortcutManager.defaultRevertShortcut
                                shortcutManager.setRevertShortcut(revertShortcut)
                            }
                        )
                    }

                    if recordingShortcut != nil {
                        Text("Press a key combination...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .background(ShortcutRecorderView(
                recordingShortcut: $recordingShortcut,
                onShortcutRecorded: { keyCode, modifiers in
                    let config = ShortcutConfig(keyCode: keyCode, modifiers: modifiers)
                    switch recordingShortcut {
                    case .render:
                        renderShortcut = config
                        shortcutManager.setRenderShortcut(config)
                    case .renderInline:
                        renderInlineShortcut = config
                        shortcutManager.setRenderInlineShortcut(config)
                    case .revert:
                        revertShortcut = config
                        shortcutManager.setRevertShortcut(config)
                    case .none:
                        break
                    }
                    recordingShortcut = nil
                }
            ))

            GroupBox(label: Text("General")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            do {
                                try LoginItemManager.shared.setEnabled(newValue)
                            } catch {
                                print("Failed to set launch at login: \(error)")
                                // Revert the toggle on error
                                launchAtLogin = !newValue
                            }
                        }
                }
                .padding()
            }

            Spacer()

            VStack(spacing: 4) {
                Text("The app runs in the menu bar. Use shortcuts to convert LaTeX selections.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Divider()
                    .padding(.vertical, 4)

                Text("Version \(AppVersion.version)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Licensed under Apache License 2.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Includes MathJax © 2009-2023 The MathJax Consortium (Apache 2.0)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 500, height: 420)
    }
}

struct ShortcutButton: View {
    let shortcut: ShortcutConfig
    let isRecording: Bool
    let onTap: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                Text(isRecording ? "Recording..." : shortcut.displayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset to default")
        }
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var recordingShortcut: ContentView.ShortcutType?
    let onShortcutRecorded: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = onShortcutRecorded
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let recorderView = nsView as? ShortcutRecorderNSView {
            recorderView.isRecording = recordingShortcut != nil
        }
    }
}

class ShortcutRecorderNSView: NSView {
    var isRecording = false
    var onShortcutRecorded: ((UInt32, UInt32) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupMonitor()
    }

    private func setupMonitor() {
        if monitor != nil {
            NSEvent.removeMonitor(monitor!)
            monitor = nil
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else {
                return event
            }

            let modifiers = self.convertModifiers(event.modifierFlags)
            if modifiers != 0 && event.keyCode != 0 {
                self.onShortcutRecorded?(UInt32(event.keyCode), modifiers)
                return nil
            }

            return event
        }
    }

    private func convertModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

#Preview {
    ContentView()
}
