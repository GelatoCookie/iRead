# SimpleRFID

SimpleRFID is an iOS application for Zebra RFID readers and barcode scanners. It provides device discovery, connection management, RFID inventory, barcode capture, and RFID tag locationing through Zebra's iOS SDKs.

This repository is currently at release candidate `rc1.1`.

## Overview

- iOS app built around a single main controller: `ViewController`
- Integrates Zebra RFID SDK and Zebra scanner SDK
- Supports reader and scanner discovery, connection, and session management
- Displays device lists and live tag data in table views
- Supports RFID tag inventory and RFID tag locationing from the UI

## Current Highlights

- Tag list refresh uses a repeating 500 ms timer instead of per-read UI scheduling
- Reader and scanner tables render from immutable snapshots instead of mutable SDK-owned arrays
- RFID locationing requires an explicitly selected RFID EPC from the tag list
- RFID disconnect, disappearance, and termination flows clear stale reader and tag state
- Alert presentation is guarded to avoid repeated modal stacking from SDK callbacks

## Project Structure

- `SimpleRFID/ViewController.m`: main application logic, SDK delegates, UI event handling
- `SimpleRFID/ViewController.h`: controller interface and protocol declarations
- `SimpleRFID/AppDelegate.m`: application lifecycle integration
- `DesignDoc_ReleaseNote.md`: design notes plus high-level release notes
- `RELEASE.md`: release-candidate summary for `rc1.1`
- `symbolrfid-sdk/include/`: Zebra RFID and scanner SDK headers

## Architecture

### UI Layer

- `UITableView` is used for RFID readers, barcode scanners, and tag data
- Labels and buttons expose connection, inventory, and locationing actions
- UI refreshes are dispatched to the main thread

### SDK Layer

- RFID SDK: `RfidSdkApi`, `RfidSdkFactory`
- Scanner SDK: `ISbtSdkApi`, `SbtSdkFactory`
- Delegates: `srfidISdkApiDelegate`, `ISbtSdkApiDelegate`

### Data Flow

- Reader and scanner device lists are maintained as mutable internal arrays with locks
- UI reads immutable snapshots of those device lists on the main thread
- RFID and barcode callbacks write into the shared tag database
- An RFID-only EPC set is maintained so locationing cannot target barcode values

## Requirements

- macOS with Xcode
- Zebra SDK content already included in this repository
- A valid Apple signing/provisioning setup for physical device deployment
- Supported Zebra RFID reader and/or Zebra barcode scanner hardware

## Build And Run

1. Open `SimpleRFID.xcodeproj` in Xcode.
2. Configure signing for a physical device target.
3. Select the `SimpleRFID` scheme.
4. Build and run on supported hardware.

Workspace task available in VS Code:

- `Build iOS app`: runs `xcodebuild -project SimpleRFID.xcodeproj -scheme SimpleRFID -configuration Release`

## Usage

1. Launch the app.
2. Connect an RFID reader or barcode scanner from the device lists.
3. Start RFID inventory or barcode scanning from the UI controls.
4. Watch tag data update in the tag table.
5. Select an RFID EPC from the tag list before starting tag locationing.

## Known Limitations

- Physical device builds require a valid provisioning profile.
- Simulator builds are blocked by Zebra's device-only static library `libintegratedsdk.a`.
- The RFID SDK currently reports compatibility warnings because the SDK is built for iOS 14 while the app links to iOS 12.

## Release Status

- Current release candidate: `rc1.1`
- Release summary: see `RELEASE.md`
- Design details: see `DesignDoc_ReleaseNote.md`

## Notes For Maintainers

- Xcode user state files under `xcuserdata` are transient and should not be part of a release commit.
- The current release candidate was validated with editor diagnostics, but full device/simulator execution remains constrained by signing and SDK packaging.