import AppKit
import ClipStackCore
import SwiftUI

/// The one real window ClipStack has.
///
/// Presenting it from an `.accessory` app takes two steps that are easy to miss:
/// `AppMenu.installIfNeeded()` so ⌘V works in the key field, and a temporary switch to
/// `.regular` so the window can become key and own the menu bar. A Dock icon appears
/// while it is open, which is a fair trade for a window most people see once.
@MainActor
final class ActivationWindowController: NSObject, NSWindowDelegate {
    private let license: LicenseManager
    private let onOpenCheckout: () -> Void
    private var window: NSWindow?

    init(license: LicenseManager, onOpenCheckout: @escaping () -> Void) {
        self.license = license
        self.onOpenCheckout = onOpenCheckout
    }

    func show() {
        AppMenu.installIfNeeded()
        NSApp.setActivationPolicy(.regular)

        let window = window ?? makeWindow()
        self.window = window

        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipStack Licence"
        // The controller outlives the window; without this, closing it would be fatal.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: ActivationView(
                license: license,
                onBuy: { [weak self] in self?.onOpenCheckout() },
                onDone: { [weak self] in self?.window?.close() }
            )
        )
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only app. The main menu is left installed — it is inert
        // while accessory, and rebuilding it on every open would be pointless work.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct ActivationView: View {
    @Bindable var license: LicenseManager
    let onBuy: () -> Void
    let onDone: () -> Void

    @State private var key = ""
    @State private var message: String?
    @State private var didActivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if didActivate {
                success
            } else {
                form
            }
        }
        .padding(28)
        .frame(width: 460, alignment: .leading)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activate ClipStack")
                .font(.system(size: 20, weight: .semibold))

            Text("Paste the licence key from your purchase email. It works on up to three Macs you own.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .disabled(license.isActivating)
                .onSubmit { activate() }

            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Buy a licence — $12", action: onBuy)
                    .buttonStyle(.link)
                Spacer()
                if license.isActivating {
                    ProgressView().controlSize(.small)
                }
                Button("Activate", action: activate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || license.isActivating)
            }
        }
    }

    private var success: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("ClipStack is activated", systemImage: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
            Text("Thank you. New copies are being saved again, and this licence covers every future version.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func activate() {
        message = nil
        Task {
            switch await license.activate(key) {
            case .success:
                didActivate = true
            case .failure(let error):
                message = error.message
            }
        }
    }
}
