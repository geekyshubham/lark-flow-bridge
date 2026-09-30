# Troubleshooting LARK A2 button control for Wispr Flow on Mac

## Accessibility is enabled but the app still asks for access

An ad hoc signed rebuild can change the code identity that macOS approved. The switch may show enabled while the new build remains denied.

1. Quit LARK Flow Bridge.
2. In System Settings → Privacy & Security → Accessibility, turn the bridge off and back on.
3. Reopen it and click Start bridge.

If that fails, reset **only this project's** Accessibility grant, then grant it again:

```sh
tccutil reset Accessibility io.github.geekyshubham.lark-flow-bridge
```

The initial locally built prototype used `local.checkred.lark-flow-bridge`; that is a different bundle identifier from public releases. Do not reset unrelated apps or the entire Accessibility service.

If needed, remove the stale bridge entry from the Accessibility list, add the current `.app` with the `+` button, and enable it. macOS can require Touch ID or your Mac password; enter credentials only in its system prompt.

## USB access denied or the receiver is not found

- Connect the LARK A2 USB-C receiver's device connector directly to the Mac. Its charging socket is for pass-through charging.
- Power on the transmitter and check that it is paired with the receiver.
- Close Hollyland Web Control and other microphone configuration tools.
- If macOS denies HID access, enable the bridge in Privacy & Security → Input Monitoring, then quit and reopen it.
- This version matches vendor `0x3547` / product `0x0411`; other receivers and models need separate support.

You can check whether macOS sees the matching device without recording audio:

```sh
hidutil list --matching '{"VendorID":13639,"ProductID":1041}'
```

## Button only changes blue and green lights

Blue/green changes are the microphone's original noise-cancellation behavior. Open the bridge, click Start bridge, and wait for Ready. The bridge detects those changes, restores the original setting, and sends Flow's toggle. It does not permanently change transmitter firmware.

## Noise restoration failed

Stop and restart the bridge after checking that the receiver is connected and other control apps are closed. If it repeatedly pauses, report the receiver firmware and the exact status message. Do not force unknown control commands or install another model's firmware.

## Shortcut counter increases but Flow does not record

- Confirm Wispr Flow is running and its hands-free shortcut is **Fn + Space**.
- Confirm Flow has its own required microphone and Accessibility permissions.
- Select **Wireless (USB)** in Flow's microphone settings.
- Release held modifier keys and focus a normal, editable text field.
- Test Fn + Space manually. If that also fails, resolve the Flow shortcut problem first.
- Password fields and apps using Secure Keyboard Entry can block shortcuts. See [Flow's secure-input guidance](https://docs.wisprflow.ai/articles/8841649969-Fix-Flow-shortcuts-blocked-by-macOS-Secure-Keyboard-Entry-/-Secure-Event-Input).

The bridge counts shortcut sends, not successful recordings. Check Flow's recording indicator.

## First click works, second click seems ignored

Allow Flow to start before clicking again. Clicks during noise restoration or its short debounce interval may be ignored. If Flow is processing a previous transcript, wait until processing finishes.

## Bridge stops when its window closes

That is intentional: closing the window quits the app. Minimize the window to keep the bridge running. After restarting the Mac, reopen the app and click Start bridge.

## HollyAudio says firmware is latest, but desktop AI mode does not connect

On the verified receiver, firmware 3.0.2.008 responded to basic status commands but not to the desktop AI-template request. A latest-version message is not proof of support for that command. This bridge uses the existing noise-button signal instead. Compatibility with other firmware or hardware variants is not established by that single test.
