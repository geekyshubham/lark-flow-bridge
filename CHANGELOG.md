# Changelog

## 1.1.0

- Add live battery percentages and battery bars for both transmitters.
- Show per-microphone connection, charging and muted status, plus receiver firmware.
- Keep read-only monitoring active when the bridge is stopped or Accessibility is unavailable.
- Add confirmed Off/Low/Medium/High noise controls while the bridge is stopped.
- Clear stale/disconnected telemetry rather than displaying old percentages.
- Add report validation and fixture tests for status parsing and safe setting confirmation.
- Document the Android controls whose USB commands have not been verified.

## 1.0.0

- First public release of the native macOS LARK A2 to Wispr Flow bridge.
- Click the transmitter once to start dictation and again to stop.
- Restore the original noise-cancellation setting and confirm it before sending a shortcut.
- Match the supported receiver and reinitialize after reconnecting.
- Pause on repeated restoration failures and skip shortcuts while modifier keys are held.
- Add a modern microphone/link app icon, universal macOS packaging, checksums, build automation, and setup/troubleshooting guides.
