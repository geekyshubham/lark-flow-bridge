# How LARK Flow Bridge connects the LARK A2 button to Wispr Flow

The app is a native Swift/AppKit utility. It handles the recording control signal; Wispr Flow receives microphone audio directly from the USB receiver.

## Device matching

`IOHIDManager` opens only devices matching Hollyland USB vendor `13639` (`0x3547`) and product `1041` (`0x0411`). This is the tested LARK A2 USB-C mobile receiver identity. It does not subscribe to normal keyboard input or other USB device models.

## Receiver control reports

The app uses the control packet format visible in Hollyland's [LARK A2 Web Control implementation](https://res.hollyland.com/6118/index.html). The device exposes vendor reports on HID report ID `0x55`.

| Command | Purpose |
| --- | --- |
| `0x10` | Read receiver/transmitter status, including the noise state. |
| `0x19`, payload `[2]` | Toggle noise cancellation on/off. |
| `0x06`, payload `[level]` | Set noise-cancellation strength when needed. |

Requests use the `AA DD` header and receiver destination byte `0x40`. Responses use `BB DD`. Native HID reports can contain the report-ID byte; the receiver callback removes that prefix before parsing.

The on/off switch and strength are separate commands. Sending strength zero is not a reliable substitute for turning noise cancellation off. The app uses the switch command for on/off restoration and the strength command to restore a nonzero level.

## Click detection and restoration

1. On connection, wait for a powered-on transmitter and remember the receiver's noise state.
2. Read status every 200 ms.
3. Treat a change from the remembered noise setting as a button event.
4. Restore the original on/off state and, when applicable, its strength.
5. Confirm restoration through a later status response.
6. Send the dictation toggle once.

This is an inference from microphone status, not a firmware button remapping. Noise changes made by the receiver button or another app can also trigger it.

## Wispr Flow shortcut

The bridge checks that Wispr Flow is running, then emits macOS `CGEvent` keyboard events for **Fn + Space**. Accessibility permission is required for these events. Flow handles the recording, stopping, transcription, and insertion into the focused text field.

The bridge checks only the current modifier-key flags before emitting its shortcut. It does not capture typed text. If a modifier is already held, it skips the shortcut to avoid turning it into another combination.

## Safeguards and boundaries

- Wait briefly after connection before interpreting status changes as clicks.
- Use a short debounce interval after restoration.
- Confirm the noise setting before sending the recording shortcut.
- Retry failed restoration a limited number of times, then pause rather than repeatedly firing shortcuts.
- Reinitialize the baseline after disconnect/reconnect.
- Stop polling when stopped, quit, or Accessibility permission is removed.
- Do not launch Wispr Flow automatically or inspect its transcript/history data.

The app does not know whether Flow is currently recording. Its counter reports shortcut sends, not recording confirmations. If Flow is busy, blocked by secure keyboard input, or uses a different shortcut, a send may not start dictation.

## Privacy and runtime dependencies

The source contains no network requests, audio recording, speech recognition, analytics, accounts, or API keys. Its status and click count live in memory. It uses macOS AppKit, ApplicationServices, and IOKit, with no third-party runtime libraries.

Wispr Flow is a separate app with its own audio handling, account settings, and data policies. This bridge does not change those settings.

## Verified setup

Verified on macOS 26.3 / Apple Silicon, a LARK A2 USB-C receiver with firmware 3.0.2.008, and Wispr Flow 1.6.999. Receiver status and noise restoration were tested, real Flow start/stop sessions were verified, and the physical button was confirmed working by the user. CI validates compilation and packaging, not physical hardware or transcription.

## Live microphone dashboard (1.1)

Read-only monitoring starts when the app opens and continues after Stop bridge. A status reply must have a valid response header, RX destination and declared payload length of at least 16 bytes. Payload bytes 0/1 indicate transmitter presence, 2/3 report battery percentages, 6 reports noise strength, and byte 15 contains mute bits 0/1 and charging bits 2/3, matching Hollyland's desktop controller parser. Offline/invalid percentages show —. Telemetry becomes unavailable after two seconds without a status reply. Command 0x41 reads RX firmware.

Noise controls are disabled while the dictation bridge runs. A user setting is handled as a separate pending operation, confirmed by status before accepting the new baseline, with a two-second timeout. It never requests a Flow toggle. Other Android controls are not sent without verified protocol support.
