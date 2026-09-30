import AppKit
import ApplicationServices
import IOKit.hid

// USB device-specific bridge. It does not capture audio, typing, or any other device.
// Firmware 3.0.2.008 exposes transmitter clicks as noise-cancellation state changes.
// The bridge preserves the initial noise setting and sends Flow's existing Fn+Space toggle.
final class Bridge: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let status = NSTextField(labelWithString: "Bridge is stopped.")
    let details = NSTextField(wrappingLabelWithString: "")
    let startButton = NSButton(title: "Start bridge", target: nil, action: nil)
    var manager: IOHIDManager?
    var device: IOHIDDevice?
    var timer: Timer?
    var baselineNoise: UInt8?
    var online = false
    var suppressUntil: TimeInterval = 0
    var restorePending = false
    var togglePending = false
    var restoreAttempts = 0
    var lastPollError = false
    var clickCount = 0
    let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit LARK Flow Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 380), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "LARK Flow Bridge"
        window.center()
        let title = NSTextField(labelWithString: "LARK A2 → Wispr Flow")
        title.font = .boldSystemFont(ofSize: 24)
        status.font = .boldSystemFont(ofSize: 15)
        status.maximumNumberOfLines = 2
        details.stringValue = "Click the transmitter once to start Flow, and again to stop.\n\nThis local workaround detects the microphone's noise button, then restores its original noise setting. Keep Hollyland Web Control closed while using it.\n\nWispr Flow must be running with Fn + Space as its hands-free shortcut. No audio or transcripts are read by this app."
        details.font = .systemFont(ofSize: 13)
        startButton.target = self
        startButton.action = #selector(toggle)
        let accessibility = NSButton(title: "Open Accessibility settings", target: self, action: #selector(openAccessibility))
        let monitoring = NSButton(title: "Open Input Monitoring settings", target: self, action: #selector(openMonitoring))
        let row = NSStackView(views: [accessibility, monitoring])
        row.orientation = .horizontal
        row.spacing = 12
        let stack = NSStackView(views: [title, details, status, startButton, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func openMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc func toggle() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if manager != nil { stop(); return }
        let requestAccessibility = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(requestAccessibility) else {
            status.stringValue = "Allow LARK Flow Bridge in Accessibility, then start again."
            return
        }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: 13639, kIOHIDProductIDKey: 1041] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { context, _, _, device in
            guard let context else { return }
            let bridge = Unmanaged<Bridge>.fromOpaque(context).takeUnretainedValue()
            bridge.device = device
            bridge.baselineNoise = nil
            bridge.online = false
            bridge.restorePending = false
            bridge.togglePending = false
            bridge.suppressUntil = Date().timeIntervalSince1970 + 1
            bridge.status.stringValue = "Receiver connected. Waiting for a powered-on transmitter…"
            IOHIDDeviceRegisterInputReportCallback(device, bridge.reportBuffer, 256, { context, _, _, _, reportID, data, count in
                guard let context, reportID == 0x55, count > 0 else { return }
                let bridge = Unmanaged<Bridge>.fromOpaque(context).takeUnretainedValue()
                var bytes = Array(UnsafeBufferPointer(start: data, count: count))
                if bytes.first == 0x55 { bytes.removeFirst() }
                bridge.receive(bytes)
            }, context)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { context, _, _, _ in
            guard let context else { return }
            let bridge = Unmanaged<Bridge>.fromOpaque(context).takeUnretainedValue()
            bridge.device = nil
            bridge.baselineNoise = nil
            bridge.online = false
            bridge.restorePending = false
            bridge.togglePending = false
            bridge.status.stringValue = "Waiting for the LARK A2 receiver…"
        }, context)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(m, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            status.stringValue = "USB access denied (\(result)). Allow Input Monitoring and reopen this app."
            return
        }
        manager = m
        startButton.title = "Stop bridge"
        status.stringValue = "Waiting for the LARK A2 receiver…"
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.device != nil else { return }
            if !AXIsProcessTrusted() { self.stop(); self.status.stringValue = "Stopped: Accessibility permission was removed."; return }
            let result = self.send(command: 0x10)
            if result != kIOReturnSuccess && !self.lastPollError {
                self.lastPollError = true
                self.status.stringValue = "Receiver read failed. Reconnect it to the Mac."
            } else if result == kIOReturnSuccess { self.lastPollError = false }
        }
    }

    @discardableResult func send(command: UInt8, payload: [UInt8] = []) -> IOReturn {
        guard let device else { return kIOReturnNoDevice }
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0x55; report[1] = 0xaa; report[2] = 0xdd
        report[3] = command; report[4] = 0x40
        report[6] = UInt8(payload.count)
        for (i, value) in payload.enumerated() { report[7+i] = value }
        return report.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x55, $0.baseAddress!, report.count) }
    }

    // Hollyland separates the on/off switch (0x19) from the strength (0x06).
    // Setting strength to zero does not turn noise cancellation off.
    @discardableResult func restoreNoise(current: UInt8, original: UInt8) -> IOReturn {
        if (current > 0) != (original > 0) {
            let result = send(command: 0x19, payload: [2])
            if result == kIOReturnSuccess && original > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self, self.restorePending, self.baselineNoise == original else { return }
                    self.send(command: 0x06, payload: [original])
                }
            }
            return result
        }
        return original > 0 ? send(command: 0x06, payload: [original]) : kIOReturnSuccess
    }

    func receive(_ bytes: [UInt8]) {
        guard bytes.count >= 22, bytes[0] == 0xbb, bytes[1] == 0xdd, bytes[2] == 0x10 else { return }
        let p = Array(bytes.dropFirst(6))
        let connected = p[0] == 1 || p[1] == 1
        let noise = p[6]
        guard connected else {
            online = false; baselineNoise = nil; restorePending = false; togglePending = false
            status.stringValue = "Receiver connected. Power on a transmitter."
            return
        }
        let now = Date().timeIntervalSince1970
        if !online || baselineNoise == nil {
            online = true; baselineNoise = noise; restorePending = false; togglePending = false
            suppressUntil = now + 1
            status.stringValue = "Ready. Click the transmitter to start or stop Flow."
            return
        }
        guard let baseline = baselineNoise else { return }
        if restorePending {
            if noise == baseline {
                restorePending = false; suppressUntil = now + 0.35
                if togglePending {
                    togglePending = false
                    if sendFlowToggle() {
                        clickCount += 1
                        status.stringValue = "Flow start/stop shortcut sent · click \(clickCount)"
                    } else {
                        status.stringValue = "Shortcut not sent. Release held keyboard modifiers and check Accessibility."
                    }
                }
            }
            else if now > suppressUntil {
                if restoreAttempts < 3 {
                    restoreAttempts += 1; restoreNoise(current: noise, original: baseline); suppressUntil = now + 0.5
                } else {
                    baselineNoise = noise; restorePending = false; togglePending = false
                    status.stringValue = "Noise restoration failed. Bridge paused; stop and restart."
                    timer?.invalidate(); timer = nil
                }
            }
            return
        }
        guard now > suppressUntil, noise != baseline else { return }
        // Avoid stale transitions while reconnecting, and never launch Flow implicitly.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.electron.wispr-flow").contains(where: { !$0.isTerminated }) else {
            baselineNoise = noise
            status.stringValue = "Open Wispr Flow first, then click the transmitter."
            return
        }
        restorePending = true; togglePending = true; restoreAttempts = 1; suppressUntil = now + 0.6
        let restoreResult = restoreNoise(current: noise, original: baseline)
        guard restoreResult == kIOReturnSuccess else {
            baselineNoise = noise; restorePending = false; togglePending = false
            status.stringValue = "Noise restoration command failed; no shortcut sent."
            return
        }
        status.stringValue = "Button detected. Waiting for the noise setting to be restored…"
    }

    func sendFlowToggle() -> Bool {
        let previousFlags = CGEventSource.flagsState(.hidSystemState)
        let heldModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        guard previousFlags.intersection(heldModifiers).isEmpty else { return false }
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .hidSystemState),
              let fnDown = CGEvent(keyboardEventSource: source, virtualKey: 63, keyDown: true),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false),
              let fnUp = CGEvent(keyboardEventSource: source, virtualKey: 63, keyDown: false) else { return false }
        let shortcutFlags = previousFlags.union(.maskSecondaryFn)
        fnDown.type = .flagsChanged; fnDown.flags = shortcutFlags
        down.flags = shortcutFlags; up.flags = shortcutFlags
        fnUp.type = .flagsChanged; fnUp.flags = previousFlags
        fnDown.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        fnUp.post(tap: .cghidEventTap)
        return true
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let manager {
            IOHIDManagerClose(manager, 0)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        manager = nil; device = nil; online = false; baselineNoise = nil; restorePending = false; togglePending = false
        startButton.title = "Start bridge"; status.stringValue = "Bridge is stopped."
    }
    func applicationWillTerminate(_ notification: Notification) { stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = Bridge()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
