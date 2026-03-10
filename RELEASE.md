# SimpleRFID RELEASE

**Version:** rc1.1  
**Date:** 2026-03-09
**Status:** Release candidate

## Summary
- Stabilizes RFID reader lifecycle handling before release.
- Replaces ad hoc tag-table refresh scheduling with a 500 ms timer-driven refresh path.
- Hardens mixed RFID/barcode workflows so tag locationing only targets valid RFID EPCs.

## Included Changes
- Added a shared, lock-safe tag database clear path and routed trigger resets through it.
- Switched reader and scanner UI paths to immutable snapshots to avoid reading mutable SDK-owned arrays on the main thread.
- Replaced unsafe barcode decoding with length-aware `NSData` to UTF-8 decoding plus a safe fallback string.
- Removed hardcoded locationing reader/tag inputs and now require an explicitly selected RFID tag from the UI.
- Reset stale RFID session, selected tag, and visible tag state across disconnect, disappearance, and session termination callbacks.
- Moved reader post-connect setup out of the reader-list lock so callback ordering does not leave the session partially initialized.
- Guarded alert presentation so repeated SDK callbacks do not attempt to stack modal alerts.

## Validation
- Editor diagnostics for `ViewController.m` and release docs are clean.
- Device build remains blocked by provisioning profile configuration.
- Simulator build remains blocked by Zebra's device-only static library `libintegratedsdk.a`.

## Known Issues
- Requires a valid provisioning profile for physical device deployment.
- RFID SDK compatibility warnings remain because the SDK is built for iOS 14 while the app links to iOS 12.
- Simulator execution is not currently supported because the bundled Zebra static library is built only for iOS devices.

## Installation
1. Clone the repository: `git clone https://github.com/GelatoCookie/iRead.git`
2. Open `SimpleRFID.xcodeproj` in Xcode.
3. Configure signing for a physical device target.
4. Build and run on supported hardware.

## Usage
- Launch the app.
- Connect an RFID reader or barcode scanner from the device lists.
- Start RFID inventory or barcode scanning from the UI controls.
- Select an RFID EPC from the tag list before starting tag locationing.

---
See the design document for implementation details behind this release candidate.
