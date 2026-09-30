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
    let micLabels = [NSTextField(labelWithString: "—"), NSTextField(labelWithString: "—")]
    let micStates = [NSTextField(labelWithString: "Waiting for receiver"), NSTextField(labelWithString: "Waiting for receiver")]
    let batteryBars = [NSProgressIndicator(), NSProgressIndicator()]
    let receiverLabel = NSTextField(labelWithString: "Receiver disconnected")
    let noisePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let controlHint = NSTextField(labelWithString: "Choose a noise setting while the bridge is stopped.")
    var bridgeEnabled = false
    var lastStatusAt: TimeInterval = 0
    var requestedNoise: UInt8?
    var settingDeadline: TimeInterval = 0
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
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 570), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "LARK Flow Bridge"
        window.center()
        let title = NSTextField(labelWithString: "LARK A2 → Wispr Flow")
        title.font = .boldSystemFont(ofSize: 24)
        status.font = .boldSystemFont(ofSize: 15)
        status.maximumNumberOfLines = 2
        details.stringValue = "Click your microphone once to start dictation, and again to stop. Keep Wispr Flow open with Fn + Space as its hands-free shortcut."
        details.font = .systemFont(ofSize: 13)
        startButton.target = self
        startButton.action = #selector(toggle)
        let accessibility = NSButton(title: "Open Accessibility settings", target: self, action: #selector(openAccessibility))
        let monitoring = NSButton(title: "Open Input Monitoring settings", target: self, action: #selector(openMonitoring))
        let row = NSStackView(views: [accessibility, monitoring])
        row.orientation = .horizontal
        row.spacing = 12
        var cards: [NSView] = []
        for i in 0..<2 {
            let heading = NSTextField(labelWithString: "Microphone \(i + 1)")
            heading.font = .boldSystemFont(ofSize: 14)
            micLabels[i].font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
            micStates[i].textColor = .secondaryLabelColor
            batteryBars[i].isIndeterminate = false
            batteryBars[i].minValue = 0; batteryBars[i].maxValue = 100
            batteryBars[i].style = .bar
            let card = NSStackView(views: [heading, micLabels[i], batteryBars[i], micStates[i]])
            card.orientation = .vertical; card.alignment = .leading; card.spacing = 10
            card.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
            card.wantsLayer = true; card.layer?.cornerRadius = 14
            card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            batteryBars[i].widthAnchor.constraint(equalToConstant: 235).isActive = true
            cards.append(card)
        }
        let microphones = NSStackView(views: cards)
        microphones.spacing = 20; microphones.distribution = .fillEqually
        noisePicker.addItems(withTitles: ["Off", "Low", "Medium", "High"])
        noisePicker.target = self; noisePicker.action = #selector(changeNoise)
        noisePicker.isEnabled = false
        let noiseRow = NSStackView(views: [NSTextField(labelWithString: "Noise cancellation"), noisePicker])
        noiseRow.spacing = 16
        controlHint.font = .systemFont(ofSize: 12); controlHint.textColor = .secondaryLabelColor
        receiverLabel.font = .systemFont(ofSize: 12); receiverLabel.textColor = .secondaryLabelColor
        let phoneNote = NSTextField(wrappingLabelWithString: "Gain, sound tuning, LED settings and firmware updates remain available in HollyAudio on your phone. Battery status stays live while the bridge is stopped.")
        phoneNote.font = .systemFont(ofSize: 12); phoneNote.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, details, microphones, receiverLabel, noiseRow, controlHint, status, startButton, row, phoneNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startMonitoring()
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
        if bridgeEnabled {
            bridgeEnabled = false; togglePending = false
            startButton.title = "Start bridge"
            status.stringValue = "Bridge stopped. Microphone status is still live."
            controlHint.stringValue = "Choose a noise setting while the bridge is stopped."
            noisePicker.isEnabled = online && !restorePending && requestedNoise == nil
            return
        }
        guard !restorePending, requestedNoise == nil else {
            status.stringValue = "Wait for the noise setting to finish updating."; return
        }
        let requestAccessibility = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(requestAccessibility) else {
            status.stringValue = "Allow LARK Flow Bridge in Accessibility, then start again."
            return
        }
        bridgeEnabled = true
        controlHint.stringValue = "Stop the bridge to adjust noise cancellation."
        baselineNoise = nil
        startButton.title = "Stop bridge"
        noisePicker.isEnabled = false
        status.stringValue = "Waiting for microphone status…"
    }

    func startMonitoring() {
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
            bridge.lastStatusAt = 0
            bridge.send(command: 0x41)
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
            bridge.requestedNoise = nil
            bridge.clearTelemetry("Receiver disconnected")
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
        status.stringValue = "Waiting for the LARK A2 receiver…"
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.device != nil else { return }
            if self.bridgeEnabled && !AXIsProcessTrusted() {
                self.bridgeEnabled = false; self.togglePending = false
                self.startButton.title = "Start bridge"
                self.status.stringValue = "Bridge stopped: Accessibility permission was removed."
            }
            if self.lastStatusAt > 0 && Date().timeIntervalSince1970 - self.lastStatusAt > 2 {
                self.clearTelemetry("Receiver not responding. Reconnect it.")
                self.online = false; self.baselineNoise = nil
                self.requestedNoise = nil; self.restorePending = false; self.togglePending = false
            }
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
                    guard let self, (self.restorePending && self.baselineNoise == original) || self.requestedNoise == original else { return }
                    self.send(command: 0x06, payload: [original])
                }
            }
            return result
        }
        return original > 0 ? send(command: 0x06, payload: [original]) : kIOReturnSuccess
    }

    func receive(_ bytes: [UInt8]) {
        guard bytes.count >= 6, bytes[0] == 0xbb, bytes[1] == 0xdd, bytes[3] == 0x80 else { return }
        let declared = Int(bytes[4]) * 256 + Int(bytes[5])
        guard bytes.count >= 6 + declared else { return }
        if bytes[2] == 0x41, declared >= 6 {
            let v = Array(bytes.dropFirst(6))
            receiverLabel.stringValue = "USB-C receiver · Firmware \(v[0]).\(v[1]).\(v[2]).\(v[3])\(v[4])\(v[5])"
            return
        }
        guard bytes[2] == 0x10, declared >= 16 else { return }
        lastStatusAt = Date().timeIntervalSince1970
        let p = Array(bytes.dropFirst(6))
        for i in 0..<2 {
            let isOnline = p[i] == 1
            let battery = p[2+i]
            let charging = p[15] & UInt8(4 << i) != 0
            let muted = p[15] & UInt8(1 << i) != 0
            micLabels[i].stringValue = isOnline && battery <= 100 ? "\(battery)%" : "—"
            batteryBars[i].doubleValue = isOnline && battery <= 100 ? Double(battery) : 0
            micStates[i].stringValue = isOnline ? ["Connected", charging ? "Charging" : nil, muted ? "Muted" : nil].compactMap { $0 }.joined(separator: " · ") : "Disconnected"
            micLabels[i].setAccessibilityLabel("Microphone \(i+1) battery")
        }
        if receiverLabel.stringValue.hasPrefix("Receiver") { receiverLabel.stringValue = "USB-C receiver connected"; send(command: 0x41) }
        let connected = p[0] == 1 || p[1] == 1
        let noise = p[6]
        guard noise <= 3 else {
            noisePicker.isEnabled = false
            status.stringValue = "Unsupported noise status. Bridge is paused."
            bridgeEnabled = false; togglePending = false; startButton.title = "Start bridge"
            return
        }
        noisePicker.selectItem(at: Int(noise))
        noisePicker.isEnabled = connected && !bridgeEnabled && !restorePending && requestedNoise == nil
        guard connected else {
            online = false; baselineNoise = nil; restorePending = false; togglePending = false; requestedNoise = nil
            status.stringValue = "Receiver connected. Power on a transmitter."
            return
        }
        let now = Date().timeIntervalSince1970
        if let requested = requestedNoise {
            if noise == requested {
                requestedNoise = nil; baselineNoise = noise
                noisePicker.isEnabled = connected && !bridgeEnabled
                controlHint.stringValue = "Noise cancellation updated."
            } else if now > settingDeadline {
                requestedNoise = nil; baselineNoise = noise
                noisePicker.isEnabled = connected && !bridgeEnabled
                controlHint.stringValue = "Setting was not confirmed. Try again or reconnect the receiver."
            }
            return
        }
        if !bridgeEnabled && !restorePending {
            if !online { status.stringValue = "Bridge stopped. Microphone status is live." }
            online = true; baselineNoise = noise
            return
        }
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
                    bridgeEnabled = false; startButton.title = "Start bridge"; noisePicker.isEnabled = online
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

    func clearTelemetry(_ message: String) {
        receiverLabel.stringValue = message; noisePicker.isEnabled = false
        for i in 0..<2 {
            micLabels[i].stringValue = "—"; micStates[i].stringValue = "Unavailable"
            batteryBars[i].doubleValue = 0
        }
    }

    @objc func changeNoise() {
        guard !bridgeEnabled, !restorePending, online, let current = baselineNoise else { return }
        let target = UInt8(noisePicker.indexOfSelectedItem)
        guard target != current else { return }
        requestedNoise = target; settingDeadline = Date().timeIntervalSince1970 + 2
        noisePicker.isEnabled = false
        controlHint.stringValue = "Updating noise cancellation…"
        if restoreNoise(current: current, original: target) != kIOReturnSuccess {
            requestedNoise = nil; noisePicker.isEnabled = online
            noisePicker.selectItem(at: Int(current))
            controlHint.stringValue = "Unable to send the setting. Reconnect the receiver."
        }
    }

    func sendFlowToggle() -> Bool {
        let previousFlags = CGEventSource.flagsState(.hidSystemState)
        let heldModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        guard bridgeEnabled, previousFlags.intersection(heldModifiers).isEmpty else { return false }
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
