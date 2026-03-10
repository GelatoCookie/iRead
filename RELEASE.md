# SimpleRFID RELEASE

**Version:** 1.0.0  
**Date:** 2026-03-09

## Features
- Initial release of SimpleRFID iOS app
- Zebra RFID and barcode scanner integration
- Device discovery, connection, and tag reading
- Bluetooth communication for device management
- User interface for device and tag lists, operation controls

## Improvements
- UI enhancements for device status and tag count
- Thread safety for device/tag operations

## Known Issues
- Requires valid provisioning profile for physical device deployment
- SDK version compatibility warnings (RFID SDK built for iOS 14, app links to iOS 12)

## Installation
1. Clone the repository: `git clone https://github.com/GelatoCookie/iRead.git`
2. Open `SimpleRFID.xcodeproj` in Xcode.
3. Set up provisioning profile for your device.
4. Build and run on a physical device or simulator.

## Usage
- Launch the app.
- Select a reader or scanner from the list.
- Start/stop reading/scanning as needed.
- View tag data and device status in the UI.

---
For support or further information, see the design doc or contact the maintainer.
