#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "Connected" asset catalog image resource.
static NSString * const ACImageNameConnected AC_SWIFT_PRIVATE = @"Connected";

/// The "Disconnected" asset catalog image resource.
static NSString * const ACImageNameDisconnected AC_SWIFT_PRIVATE = @"Disconnected";

/// The "barcodeReader" asset catalog image resource.
static NSString * const ACImageNameBarcodeReader AC_SWIFT_PRIVATE = @"barcodeReader";

/// The "rfidReader" asset catalog image resource.
static NSString * const ACImageNameRfidReader AC_SWIFT_PRIVATE = @"rfidReader";

/// The "rfidTag" asset catalog image resource.
static NSString * const ACImageNameRfidTag AC_SWIFT_PRIVATE = @"rfidTag";

#undef AC_SWIFT_PRIVATE
