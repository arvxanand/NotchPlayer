#!/bin/bash
# Make macOS ask for Automation and Audio Capture again.
#
# Needed because the app is ad-hoc signed, so its code signature changes on
# every build, and macOS may stop recognising a previously-granted build. The
# symptom is Apple Events failing with -1743 (errAEEventNotPermitted) for an
# app that is listed as allowed in System Settings, or the waveform silently
# never receiving a buffer.
set -euo pipefail
ID="local.spotifynotch"
tccutil reset AppleEvents "$ID" || true
tccutil reset AudioCapture "$ID" || true
echo "reset AppleEvents and AudioCapture for $ID -- next launch will re-ask"
