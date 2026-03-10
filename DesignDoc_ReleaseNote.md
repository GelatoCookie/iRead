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

## SDK API Mapping
- RFID: srfidGetSdkVersion, srfidSetDelegate, srfidGetAvailableReadersList, etc.
- Scanner: sbtSetDelegate, sbtGetVersion, sbtGetAvailableScannersList, etc.

## Notable Design Choices
- Modular SDK integration
- UI updates dispatched to main thread
- Thread-safe device/tag management

## Extensibility
- Easily add new device types or tag formats
- UI can be expanded for more controls or analytics

---

# SimpleRFID Release Note

**Version:** 1.0.0  
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

## Known Issues
- Requires valid provisioning profile for physical device deployment
- SDK version compatibility warnings (RFID SDK built for iOS 14, app links to iOS 12)

---

For further details or customizations, expand sections as needed.
