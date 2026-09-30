# LARK Flow Bridge 1.1.0

Use the physical **Hollyland LARK A2 microphone button** to start and stop **Wispr Flow dictation on macOS**.

This release adds live battery percentages, charging/mute/connection status for both microphones, receiver firmware display, and Off/Low/Medium/High noise controls. Battery monitoring stays active when the bridge is stopped. Stop the bridge before changing noise settings. Gain, tuning, LED, power settings and firmware updates continue to use HollyAudio on your phone.

The community release includes the complete Swift source, a native macOS app with a microphone/link icon, a universal Apple Silicon + Intel binary, build scripts, setup instructions, and troubleshooting guidance.

## Download

- `LARK-Flow-Bridge-macOS-universal.zip`: extracted `.app`, targeting macOS 13+.
- `SHA256SUMS.txt`: checksum for the ZIP.

## Setup

1. Connect the supported LARK A2 USB-C receiver and power on the transmitter.
2. Open Wispr Flow, choose **Wireless (USB)**, and keep **Fn + Space** as its hands-free shortcut.
3. Open the bridge, grant Accessibility access, and click **Start bridge**.
4. Focus a text field. Click the microphone button once to start, speak, then click again to stop.

## Compatibility and distribution

Physically verified on Apple Silicon/macOS 26.3 with RX firmware 3.0.2.008 and Wispr Flow 1.6.999. Intel is compiled but not tested on physical hardware. This version supports receiver VID `0x3547` / PID `0x0411`; other LARK models and camera receivers are outside its tested scope.

The binary is **ad hoc signed and not Apple-notarized**. Review the source and README's macOS first-launch guidance before installing. Other apps' noise-setting changes can also trigger the bridge, so stop it before adjusting those settings.

The bridge runs locally and does not capture audio, typed text, or transcripts, or make network requests. Wispr Flow handles transcription separately. This is an independent community utility under the MIT license.
