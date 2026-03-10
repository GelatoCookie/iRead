# SimpleRFID Design Document

## Project Overview
SimpleRFID is an iOS application designed to interface with Zebra Technologies RFID readers and barcode scanners. It provides device discovery, connection, and tag reading functionality, leveraging Zebra's proprietary SDKs.

## Architecture
- **UI Layer:**
  - Main controller: ViewController
  - Uses UITableView for device/tag lists
  - Buttons and switches for user actions
- **SDK Integration:**
  - RFID SDK: RfidSdkApi, RfidSdkFactory
  - Scanner SDK: ISbtSdkApi, SbtSdkFactory
  - Delegates: srfidISdkApiDelegate, ISbtSdkApiDelegate
- **Bluetooth Layer:**
  - CoreBluetooth for device communication
  - CBCentralManagerDelegate, CBPeripheralDelegate
- **Data Management:**
  - Device/tag lists: NSMutableArray, NSMutableDictionary
  - Thread safety: NSLock
  - Tag list UI refresh: repeating `NSTimer` on the main run loop every 500 ms
  - Tag list rendering: uses `m_tagKeysSnapshot` as the current UI snapshot

## Key Files
- SimpleRFID/ViewController.h: UI and delegate definitions
- SimpleRFID/ViewController.m: Main logic, device initialization, UI setup, event handling
- SimpleRFID/AppDelegate.m: App lifecycle management
- symbolrfid-sdk/include/RfidSdkApi.h: RFID SDK interface
- symbolrfid-sdk/include/ISbtSdkApi.h: Scanner SDK interface

## UI Flow
- Device lists displayed in table views
- User selects device to connect
- Start/stop reading/scanning via buttons
- Tag data shown in tag list
- Status and counts updated in labels
- Tag table refreshes on a 500 ms timer instead of per-read UI scheduling
- Immediate tag refresh is still used for explicit UI actions such as clear/start and operation summaries
- Tag locationing uses the currently connected reader and an RFID EPC selected from the tag list UI

## SDK API Mapping
- RFID: srfidGetSdkVersion, srfidSetDelegate, srfidGetAvailableReadersList, etc.
- Scanner: sbtSetDelegate, sbtGetVersion, sbtGetAvailableScannersList, etc.

## Notable Design Choices
- Modular SDK integration
- UI updates dispatched to main thread
- Thread-safe device/tag management
- Timer-based tag list refresh reduces UI churn during high-frequency RFID reads
- Reader and scanner table views consume immutable snapshots instead of mutable SDK-owned arrays

## Extensibility
- Easily add new device types or tag formats
- UI can be expanded for more controls or analytics

## Current Implementation Notes
- `ViewController` owns both SDK delegates and most UI/data orchestration
- RFID/barcode callbacks write into `m_tagDB`, while the timer periodically snapshots and reloads the tag table
- RFID callbacks also maintain an RFID-only EPC set so locationing cannot target barcode values that share the visible tag list
- Reader and scanner SDK callbacks mutate mutable device lists, and the UI reads snapshot copies on the main thread
- `clearTagDatabase` is the shared path for tag reset so clears use the same lock as writes
- Barcode payload decoding uses length-aware UTF-8 decoding from `NSData`, with a fallback string form for non-UTF8 payloads
- Starting tag locationing now requires an explicit RFID tag selection from the tag table and uses the current reader ID instead of hardcoded inputs
- RFID disconnect, disappearance, and session termination paths now reset the active reader ID, visible tag state, and related UI controls together
- RFID session establishment now finishes reader setup outside the reader-list lock so connection ordering does not leave the session partially initialized
- Shared alert helpers now present only when the controller is visible and no other alert is already on screen

---

# SimpleRFID Release Note

**Version:** rc1.1  
**Date:** 2026-03-09

## Features
- Initial release of SimpleRFID iOS app
- Supports Zebra RFID and barcode scanner integration
- Device discovery, connection, and tag reading
- Bluetooth communication for device management
- User interface for device and tag lists, operation controls

## Improvements
- UI enhancements for device status and tag count
- Thread safety for device/tag operations
- Timer-based tag list refresh every 500 ms to decouple UI updates from read callbacks
- Reader and scanner tables now render from immutable snapshots instead of mutable SDK-owned arrays
- RFID locationing now requires a selected RFID EPC and uses the active reader instead of hardcoded IDs
- Disconnect, disappearance, and reconnect flows now reset stale RFID session and tag state consistently
- Alert presentation is guarded so repeated SDK callbacks do not stack modal alerts

## Known Issues
- Requires valid provisioning profile for physical device deployment
- SDK version compatibility warnings (RFID SDK built for iOS 14, app links to iOS 12)
- Simulator build is blocked by a device-only Zebra static library (`libintegratedsdk.a`)

---

For further details or customizations, expand sections as needed.
