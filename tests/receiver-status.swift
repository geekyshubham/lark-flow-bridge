// Exercises real report parsing without a receiver, audio capture or keyboard events.
let bridge = Bridge()
bridge.noisePicker.addItems(withTitles: ["Off", "Low", "Medium", "High"])
func report(_ payload: [UInt8], command: UInt8 = 0x10) -> [UInt8] {
    [0xbb, 0xdd, command, 0x80, 0, UInt8(payload.count)] + payload
}
var payload: [UInt8] = [1, 1, 90, 93, 0, 0, 3, 5, 0, 0, 0, 0, 0, 0, 0, 6]
bridge.receive(report(payload))
assert(bridge.micLabels[0].stringValue == "90%")
assert(bridge.micLabels[1].stringValue == "93%")
assert(bridge.micStates[0].stringValue == "Connected · Charging")
assert(bridge.micStates[1].stringValue == "Connected · Muted")
assert(bridge.baselineNoise == 3 && bridge.clickCount == 0)
payload[6] = 0
bridge.receive(report(payload))
assert(bridge.baselineNoise == 0 && !bridge.restorePending && bridge.clickCount == 0)
bridge.requestedNoise = 2; bridge.settingDeadline = Date().timeIntervalSince1970 + 2
payload[6] = 2; bridge.receive(report(payload))
assert(bridge.requestedNoise == nil && bridge.baselineNoise == 2 && bridge.clickCount == 0)
payload[0] = 0; payload[3] = 255
bridge.receive(report(payload))
assert(bridge.micLabels.allSatisfy { $0.stringValue == "—" })
assert(bridge.micStates[0].stringValue == "Disconnected")
bridge.receive(report([3, 0, 2, 0, 0, 8], command: 0x41))
assert(bridge.receiverLabel.stringValue.contains("3.0.2.008"))
let prior = bridge.receiverLabel.stringValue
bridge.receive([0xbb, 0xdd, 0x10, 0x80, 0, 16, 1])
bridge.receive([0xbb])
assert(bridge.receiverLabel.stringValue == prior)
bridge.clearTelemetry("Receiver disconnected")
assert(!bridge.noisePicker.isEnabled && bridge.batteryBars[0].doubleValue == 0)
print("Receiver status fixtures passed: batteries, charging, mute, offline/invalid data, firmware, safe setting confirmation, malformed reports.")
