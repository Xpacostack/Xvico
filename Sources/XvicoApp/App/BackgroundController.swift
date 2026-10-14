import SwiftUI
import AppKit

final class XvicoApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { BackgroundController.shared.showWindow() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        BackgroundController.shared.stopControl()
    }
}

@MainActor
final class BackgroundController: NSObject {
    static let shared = BackgroundController()
    private var item: NSStatusItem?
    private weak var model: AppModel?
    func configure(_ model: AppModel) {
        self.model = model
        let policy: NSApplication.ActivationPolicy = model.settings.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        if model.settings.showMenuBarIcon || !model.settings.showDockIcon {
            if item == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "appletvremote.gen3", accessibilityDescription: "Xvico")
                item.button?.toolTip = "Xvico"
                let menu = NSMenu()
                for (title, action) in [("显示 Xvico", #selector(showWindow)), ("开始 / 停止控制", #selector(toggleControl)), ("退出 Xvico", #selector(quit))] {
                    let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    entry.target = self; menu.addItem(entry)
                }
                item.menu = menu; self.item = item
            }
        } else if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
        let locale = model.interfaceLocale
        let titles = ["显示 Xvico", "开始 / 停止控制", "退出 Xvico"]
        for (index, entry) in (item?.menu?.items ?? []).enumerated() where titles.indices.contains(index) {
            entry.title = XvicoLocalization.string(titles[index], locale: locale)
        }
    }
    @objc func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title == "Xvico" && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleControl() { guard let model else { return }; model.running ? model.stopControl() : model.startControl() }
    func stopControl() { model?.stopControl() }
    @objc private func quit() { model?.stopControl(); NSApp.terminate(nil) }
}

struct WindowLifecycleView: NSViewRepresentable {
    @EnvironmentObject private var model: AppModel
    func makeNSView(context: Context) -> WindowLifecycleNSView { let view = WindowLifecycleNSView(); view.model = model; return view }
    func updateNSView(_ view: WindowLifecycleNSView, context: Context) { view.model = model }
}

final class WindowLifecycleNSView: NSView {
    weak var model: AppModel?
    private var policy: WindowClosePolicy?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, policy == nil, let model {
            let policy = WindowClosePolicy(model: model, original: window.delegate)
            self.policy = policy; window.delegate = policy
        }
    }
}

final class WindowClosePolicy: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private weak var original: NSWindowDelegate?
    init(model: AppModel, original: NSWindowDelegate?) { self.model = model; self.original = original }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model?.settings.keepRunningWhenClosed == true { sender.orderOut(nil); return false }
        model?.stopControl()
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || original?.responds(to: selector) == true }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}
