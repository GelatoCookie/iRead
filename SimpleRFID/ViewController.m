//
//  ViewController.m
//  SimpleRFID
//
//  Created by RFID ECRT Chuck on 6/23/16.
//  Copyright © 2016 Zebra Technologies. All rights reserved.
//

#import "ViewController.h"
#import "RfidSdkFactory.h" // rfid
#import "SbtSdkFactory.h" //scanner
#import "RfidOperEndSummaryEvent.h"
#import <CoreData/CoreData.h>

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CBManager.h>

@interface ViewController ()
{
    id <srfidISdkApi> rfidSdk;
    id <ISbtSdkApi> scannerSdk;
    // Array of detected RFID readers
    NSMutableArray *m_readerList;
    NSLock *m_readerListGuard;
    // Array of detected scanners
    NSMutableArray *m_scannerList;
    NSLock *m_scannerListGuard;
    // RFID and Scanner Data
    NSLock *m_tagDBGuard;
    NSMutableDictionary *m_tagDB;
    NSArray<NSString *> *m_tagKeysSnapshot;
    BOOL m_tagRefreshScheduled;
    int iTotal;
    bool b_isReading;
    bool b_isConnected;
    int iConnectedRfidId;
    
    srfidStopTriggerConfig *m_stopTriggerConfig;
    srfidStartTriggerConfig *m_startTriggerConfig;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    /////////////////////////
    //RFID and Scanner Init
    rfidSdk = nil;
    scannerSdk = nil;
    m_readerList = [[NSMutableArray alloc] init];
    m_readerListGuard = [[NSLock alloc] init];
    m_scannerList = [[NSMutableArray alloc] init];
    m_scannerListGuard = [[NSLock alloc] init];
    m_tagDBGuard = [[NSLock alloc] init];
    m_tagDB = [[NSMutableDictionary alloc]init];
    m_tagKeysSnapshot = @[];
    m_tagRefreshScheduled = NO;
    
    m_stopTriggerConfig = [[srfidStopTriggerConfig alloc]init];
    m_startTriggerConfig = [[srfidStartTriggerConfig alloc]init];
    
    iTotal = 0;
    b_isReading = false;
    iConnectedRfidId = 0;
    //////////////////////////////////////
    //UI Init
    self.lbUnique.text = @"0";
    self.lbStatus.text = @"Click Reader to Connect";
    self.btStart.enabled = false;
    [self.btStart setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    self.btStop.enabled = false;
    [self.btStop setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    self.btAutoScan.enabled = false;
    [self.btAutoScan setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    self.btStopScan.enabled = false;
    [self.btStopScan setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    self.swtichCountRSSI.enabled = false;
    //////////////////////////////////////
    //UI table views SetDelegate and Data Source
    [self.tbViewReaderList setDelegate:self];
    [self.tbViewReaderList setDataSource:self];
    [self.tbViewReaderList setDelegate:self];
    [self.tbViewTagList setDataSource:self];
    [self.tbViewScannerList setDelegate:self];
    [self.tbViewScannerList setDataSource:self];
    /////////////////////////
    //Start RFID and Scanner Engine
    [self startupRfid];
    [self startupScanner];
}

- (void)reloadReaderListOnMainThread
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tbViewReaderList reloadData];
    });
}

- (void)reloadScannerListOnMainThread
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tbViewScannerList reloadData];
    });
}

- (void)clearTagDatabase
{
    if (YES == [m_tagDBGuard lockBeforeDate:[NSDate distantFuture]]) {
        [m_tagDB removeAllObjects];
        m_tagKeysSnapshot = @[];
        [m_tagDBGuard unlock];
    }
}

- (void)scheduleTagListRefresh
{
    @synchronized (self) {
        if (m_tagRefreshScheduled) {
            return;
        }
        m_tagRefreshScheduled = YES;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSString *> *tagKeys = @[];
        NSUInteger tagCount = 0;

        if ([self->m_tagDBGuard lockBeforeDate:[NSDate distantFuture]]) {
            tagKeys = [[self->m_tagDB allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
            self->m_tagKeysSnapshot = tagKeys;
            tagCount = self->m_tagDB.count;
            [self->m_tagDBGuard unlock];
        }

        self.lbUnique.text = [NSString stringWithFormat:@"%lu", (unsigned long)tagCount];
        [self.tbViewTagList reloadData];

        @synchronized (self) {
            self->m_tagRefreshScheduled = NO;
        }
    });
}

- (void)recordRfidTag:(srfidTagData *)tagData
{
    NSString *tagID = [tagData getTagId];
    NSString *tagRSSI = [NSString stringWithFormat:@"%d", tagData.getPeakRSSI];

    if (YES == [m_tagDBGuard lockBeforeDate:[NSDate distantFuture]]) {
        [m_tagDB setObject:tagRSSI forKey:tagID];
        [m_tagDBGuard unlock];
    }
}

- (void)recordBarcodeValue:(NSString *)barcodeValue
{
    if (barcodeValue == nil) {
        return;
    }

    if (YES == [m_tagDBGuard lockBeforeDate:[NSDate distantFuture]]) {
        NSString *existingValue = [m_tagDB objectForKey:barcodeValue];
        int count = existingValue != nil ? [existingValue intValue] + 1 : 1;
        [m_tagDB setObject:[NSString stringWithFormat:@"%d", count] forKey:barcodeValue];
        [m_tagDBGuard unlock];
    }

    [self scheduleTagListRefresh];
}

- (void) startupRfid
{
    //1. Init RFID SDK
    rfidSdk = [srfidSdkFactory createRfidSdkApiInstance];
    NSLog(@"iRead: srfidGetSdkVersion, RFID SDK Version = %@", [rfidSdk srfidGetSdkVersion]);
    //2. Register SDk Notifications to this Object - UIViewController.m
    b_isConnected = false;
    b_isReading = false;
    [rfidSdk srfidSetDelegate:self];
    //3. Subscribe SDK Events
    [rfidSdk srfidSetOperationalMode:SRFID_OPMODE_MFI];
    [rfidSdk srfidSubsribeForEvents:SRFID_EVENT_READER_APPEARANCE |SRFID_EVENT_READER_DISAPPEARANCE |SRFID_EVENT_SESSION_ESTABLISHMENT | SRFID_EVENT_SESSION_TERMINATION];
    [rfidSdk srfidSubsribeForEvents:SRFID_EVENT_MASK_READ | SRFID_EVENT_MASK_STATUS];
    [rfidSdk srfidSubsribeForEvents:SRFID_EVENT_MASK_PROXIMITY];
    [rfidSdk srfidSubsribeForEvents:SRFID_EVENT_MASK_TRIGGER];
    [rfidSdk srfidSubsribeForEvents:SRFID_EVENT_MASK_BATTERY];;
    [rfidSdk srfidSubsribeForEvents:SRFID_EVENT_MASK_STATUS_OPERENDSUMMARY]; //import RfidOperEndSummaryEven
    
    
    [rfidSdk srfidEnableAvailableReadersDetection:YES];
    //Chuck
    //[rfidSdk srfidEnableAutomaticSessionReestablishment:YES]; //auto reconnect
    [rfidSdk srfidEnableAutomaticSessionReestablishment:FALSE]; //auto reconnect -- USB no auto-reconnect
    
    
    //Chuck: Disable the messqge for Bluetooth turn on
//    NSDictionary *options = @{CBCentralManagerOptionShowPowerAlertKey: @NO};
//    _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:options];
//    _data = [[NSMutableData alloc] init];
//        
//    [_centralManager scanForPeripheralsWithServices:nil options:options];
    
}

- (void) startupScanner
{
    //1. Init Scanner SDK
    scannerSdk = [SbtSdkFactory createSbtSdkApiInstance];
    NSLog(@"iRead: sbtGetVersion, Scanner SDK Version = %@", [scannerSdk sbtGetVersion]);
    //Register Scanner SDK Notification to this object: UIViewContoller.m
    [scannerSdk sbtSetDelegate:self];
    //2. Subscribe Scanner SDK Events
    //[scannerSdk sbtSetOperationalMode:SBT_OPMODE_ALL];
    //Chuck 05/04/2022
    [scannerSdk sbtSetOperationalMode:SBT_OPMODE_MFI];
    //3. Subscribe SDK Events
    [scannerSdk sbtSubsribeForEvents:SBT_EVENT_SCANNER_APPEARANCE | SBT_EVENT_SCANNER_DISAPPEARANCE | SBT_EVENT_SESSION_ESTABLISHMENT | SBT_EVENT_SESSION_TERMINATION | SBT_EVENT_BARCODE];
    [scannerSdk sbtEnableAvailableScannersDetection:YES];
}

-(void) connectToRfidSdk: (int) readerId
{
    //Chuck: testing
    if (b_isReading){
        NSString *status = [[NSString alloc] init];
        [rfidSdk srfidStopInventory:readerId aStatusMessage:&status];
    }
    
    
    //Use RFID SDK API: srfidEstablishCommunicationSession to connect
    NSLog(@"iRead: srfidEstablishCommunicationSession Connecting... RFID Reader ID=%d", readerId);
    SRFID_RESULT result = [rfidSdk srfidEstablishCommunicationSession:readerId];
    if(result == SRFID_RESULT_SUCCESS) {
        self.lbStatus.text = @"Connected OK";
        self.btStart.enabled = true;
        self.btStop.enabled = true;
        self.swtichCountRSSI.enabled = true;
    }else{
        self.lbStatus.text = @"ERROR: Connect RFID";
        self.btStart.enabled = false;
        self.btStop.enabled = false;
        self.swtichCountRSSI.enabled = false;
        NSLog(@"iRead: Connect ERROR = %d", result);
    }
}

-(void) disconnectFromRfidSdk: (int) readerId
{
    //Chuck: testing
    if (b_isReading){
        NSString *status = [[NSString alloc] init];
        [rfidSdk srfidStopInventory:readerId aStatusMessage:&status];
    }
    //Use RFID SDK API: srfidTerminateCommunicationSession to Disconnect
    NSLog(@"iRead: srfidTerminateCommunicationSession Disconnecting... RFID Reader ID=%d", readerId);
    
    SRFID_RESULT result = [rfidSdk srfidTerminateCommunicationSession:readerId];
    if(result == SRFID_RESULT_SUCCESS) {
        self.lbStatus.text = @"Disconnected OK";
        self.btStart.enabled = false;
        self.btStop.enabled = false;
    } else{
        self.lbStatus.text = @"ERROR: Disconnect RFID";
        NSLog(@"iRead: Disconnect ERROR = %d", result);
    }
}

-(void) connectToScannerSdk: (int) scannerId
{
    NSLog(@"iRead: sbtEstablishCommunicationSession Barcode Scanner Connecting... ID=%d", scannerId);
    SBT_RESULT result = [scannerSdk sbtEstablishCommunicationSession:scannerId];
    if(result == SBT_RESULT_SUCCESS) {
        self.lbStatus.text = @"Barcode Scanner Connected";
        self.btAutoScan.enabled = true;
        self.btStopScan.enabled = false;
    }
    else {
        NSLog(@"iRead: Connect Scanner ERROR = %d", result);
        self.lbStatus.text = @"ERROR: Connect Barcode Scanner";
        self.btAutoScan.enabled = false;
        self.btStopScan.enabled = false;
    }
}

-(void) disconnectFromScannerSdk: (int) scannerId
{
    NSLog(@"iRead: sbtTerminateCommunicationSession Disconnecting... Scanner ID=%d", scannerId);
    
    NSLog(@"iRead: turn on RED LED for disconnect");
    [scannerSdk sbtLedControl:true aLedCode:3 forScanner:(int)scannerId];
    
    
    SBT_RESULT result = [scannerSdk sbtTerminateCommunicationSession:scannerId];
    if(result == SBT_RESULT_SUCCESS) {
        self.lbStatus.text = @"Barcode Scanner Disconnected";
        self.btAutoScan.enabled = false;
        self.btStopScan.enabled = false;
    }
    else {
        NSLog(@"iRead: Disconnect Scanner ERROR = %d", result);
        self.lbStatus.text = @"ERROR: Disconnect Barcode Scanner";
    }
}

-(void) inventory: (int) readerId
{
    NSLog(@"iRead: ##### srfidStartInventory API Command, RFID Reader ID=%d", readerId);
    
    if(rfidSdk!=nil) {
        
        //[self setAFTriggerStop:iConnectedRfidId ];
        //[self setAFTriggerStart:iConnectedRfidId ];
        
        NSString *staus_msg = [[NSString alloc]init];
        [rfidSdk srfidStartInventory:readerId aMemoryBank:SRFID_MEMORYBANK_NONE aReportConfig:nil aAccessConfig:nil aStatusMessage:&staus_msg];
    }
}

-(void) stopInventory: (int) readerId
{
    NSLog(@"iRead: ##### srfidStopInventory API Inventory, RFID Reader ID=%d", readerId);
    if(rfidSdk!=nil) {
        NSString *staus_msg = [[NSString alloc]init];
        [rfidSdk srfidStopInventory:readerId aStatusMessage:&staus_msg];
        //Just good pratice, button control already make sure it was stopped
//        for(int i=0; i<3; i++){
//            if(b_isReading){
//                [NSThread sleepForTimeInterval:1.000];
//            }else
//                break;
//        }
        //Make sure not reading before set configration
        //[self setAFTriggerStop:iConnectedRfidId ];
        //[self setAFTriggerStart:iConnectedRfidId ];
    }
}

///RFD40 KEEP ALIVE, TURN OFF MODE
#define OFF_MODE_TIMEOUT      1633    // The Attribute Number for Off Mode Timeout

-(SRFID_RESULT)setReaderAttribute:(int)readerID attributeInformation:(srfidAttribute*)attributeInfo aStatusMessage:(NSString**)statusMessage {
    
    SRFID_RESULT srfid_result = SRFID_RESULT_FAILURE;
    srfid_result = [rfidSdk srfidSetAttribute:readerID aAttrInfo:attributeInfo aStatusMessage:statusMessage];
    return srfid_result;
    
}

-(SRFID_RESULT)getReaderAttribute:(int)readerID
                     attributeNum:(int)attrNum
                        aAttrInfo:(srfidAttribute**)attrInfo
                   aStatusMessage:(NSString**)statusMessage {
    
    SRFID_RESULT srfid_result = SRFID_RESULT_FAILURE;
    srfid_result = [rfidSdk srfidGetAttribute:readerID
                                          aAttrNum:attrNum
                                         aAttrInfo:attrInfo
                                    aStatusMessage:statusMessage];
    return srfid_result;
    
}

-(void)changeOffModeTimeout: (int) readerId
{
    NSString *status = [[NSString alloc] init];
    srfidAttribute *attributeDet =[[srfidAttribute alloc]init];

    [self getReaderAttribute:readerId attributeNum:OFF_MODE_TIMEOUT aAttrInfo:&attributeDet aStatusMessage:&status];
    
    NSLog(@"Current Off-Mode Timeout = %@, Override to 1800*4 second = 2 hours", [attributeDet getAttrVal] );
    [attributeDet setAttrVal:@"7200"];
    
    //Chuck: Testing
//    NSLog(@"Current Off-Mode Timeout = %@, Test alive timeout as 60 seconds", [attributeDet getAttrVal] );
//    [attributeDet setAttrVal:@"60"];
    
    [self setReaderAttribute:readerId attributeInformation:attributeDet aStatusMessage:&status];
    
    [self getReaderAttribute:readerId attributeNum:OFF_MODE_TIMEOUT aAttrInfo:&attributeDet aStatusMessage:&status];
    NSLog(@"Verify Off-Mode Timeout = %@", [attributeDet getAttrVal] );
}


-(void) startLocation: (int) readerId
{
    NSLog(@"iRead: @@@@@ srfidStartTagLocationing API Command, RFID Reader ID=%d", readerId);
    if(rfidSdk!=nil) {
        //[self setAFTriggerStop:iConnectedRfidId ];
        //[self setAFTriggerStart:iConnectedRfidId ];
        
        NSString *staus_msg = [[NSString alloc]init];
        [rfidSdk srfidStartTagLocationing:1 aTagEpcId:@"E280689400004015B09838CE" aStatusMessage:&staus_msg];
    }
}

-(void) stopLocation: (int) readerId
{
    NSLog(@"iRead: @@@@@ srfidStopTagLocationing API Inventory, RFID Reader ID=%d", readerId);
    if(rfidSdk!=nil) {
        NSString *staus_msg = [[NSString alloc]init];
        [rfidSdk srfidStopTagLocationing:readerId aStatusMessage:&staus_msg];
        //[self setAFTriggerStart:readerId];
        //[self setAFTriggerStop:readerId];
    }
}

-(void)setAFTriggerStart: (int) readerId
{
    SRFID_RESULT srfid_result = SRFID_RESULT_FAILURE;
    NSString *staus_msg = [[NSString alloc]init];
    
    srfidStartTriggerConfig *config = [[srfidStartTriggerConfig alloc]init];
    srfid_result = [rfidSdk srfidGetStartTriggerConfiguration:readerId aStartTriggeConfig:&config aStatusMessage:&staus_msg];
    [config setStartOnHandheldTrigger:YES];
    [config setRepeatMonitoring:YES];
    [config setStartDelay:0];

    if(srfid_result == SRFID_RESULT_SUCCESS){
        srfid_result = [rfidSdk srfidSetStartTriggerConfiguration:readerId aStartTriggeConfig:config aStatusMessage:&staus_msg];
    }
}



-(void)setAFTriggerStop: (int) readerId
{
    //dispatch_async(dispatch_get_main_queue(), ^{
    SRFID_RESULT srfid_result = SRFID_RESULT_FAILURE;
    NSString *staus_msg = [[NSString alloc]init];
    int iLoopMax = 5;
    
    srfidStopTriggerConfig *config = [[srfidStopTriggerConfig alloc]init];
    for(int i=0; i<iLoopMax; i++){
        srfid_result = SRFID_RESULT_FAILURE;
        NSLog(@"0. Attempt to get config Loop Count=%d", i);
        srfid_result = [rfidSdk srfidGetStopTriggerConfiguration:readerId aStopTriggeConfig:&config aStatusMessage:&staus_msg];
        if ((srfid_result != SRFID_RESULT_RESPONSE_TIMEOUT) && (srfid_result != SRFID_RESULT_FAILURE)) {
            break;
        }
        
    }
    if(srfid_result == SRFID_RESULT_SUCCESS){
        NSLog(@"0. Get Config OK");
    }
    else{
        NSLog(@"!!!!!!!!!! FAILED Get Config!!!!!!!!!!!!!!!");
    }
    [config setStopOnHandheldTrigger:YES];
    [config setStopOnTagCount:NO];
    [config setStopOnTimeout:YES];
    [config setStopOnInventoryCount:NO];
    [config setStopTagCount:0];
    [config setStopInventoryCount:0];
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //Do we need the following addtional code? Testing code:
    int iTimeout=[config getStopTimeout];
    NSLog(@"1. getStopTimeout=%d", [config getStopTimeout]);
    NSLog(@"2. getStopOnTimeout=%d", [config getStopOnTimeout]);
    //Toggle it so the configuraiton can be saved.
    if(iTimeout==500000)
        [config setStopTimout:10000000];
    else if(iTimeout == 0)
        [config setStopTimout:990000];
    else
        [config setStopTimout:500000];
    ///////////////////////////////////////////////////////////////////////////////////////////////
    for(int i=0; i<iLoopMax; i++){
        srfid_result = SRFID_RESULT_FAILURE;
        NSLog(@"3. Attempt to set config Loop Count=%d", i);
        srfid_result = [self->rfidSdk srfidSetStopTriggerConfiguration:readerId aStopTriggeConfig:config aStatusMessage:&staus_msg];
        if(srfid_result == SRFID_RESULT_SUCCESS){
            NSLog(@"4. Loop Count=%d", i);
            break;
        }
        else
            NSLog(@"!!!!!!!!!! FAILED !!!!!!!!!!!!!!! Loop Count=%d", i);
    }
    
    for(int i=0; i<iLoopMax; i++){
        srfid_result = SRFID_RESULT_FAILURE;
        srfid_result = [self->rfidSdk srfidGetStopTriggerConfiguration:readerId aStopTriggeConfig:&config aStatusMessage:&staus_msg];
        if(srfid_result == SRFID_RESULT_SUCCESS){
            NSLog(@"5. Verify timeout=%d", [config getStopTimeout]);
            break;
        }
        else
            NSLog(@"!!!!!!!!!! FAILED !!!!!!!!!!!!!!! Loop Count=%d", i);
    }
    
    for(int i=0; i<iLoopMax; i++){
        srfid_result = SRFID_RESULT_FAILURE;
        srfid_result = [rfidSdk srfidSaveReaderConfiguration:iConnectedRfidId aSaveCustomDefaults:false aStatusMessage:&staus_msg];
        if(srfid_result == SRFID_RESULT_SUCCESS){
            NSLog(@"6. Saved OK, Loop Count=%d", i);
            break;
        }
    }
    /////////////////////////////////////////////////////////////////
    //Do we need this? Only out of sync app needs it
    //    [self->rfidSdk srfidPurgeTags:readerId aStatusMessage:&staus_msg];

    //});
}

//Test for Location
-(void) startTagLocationing: (int) scannerId
{
    NSLog(@"iRead: ready to startLocation scannerId=%d", scannerId);
    [self startLocation:scannerId];
}

-(void) stopTagLocationing: (int) scannerId
{
    NSLog(@"iRead: ready to stop scannerId=%d", scannerId);
    [self stopLocation:scannerId];
}

/// Display alert message
/// @param title Title string
/// @param messgae message string
-(void)showAlertMessageWithTitle:(NSString*)title withMessage:(NSString*)messgae{
    UIAlertController * alert = [UIAlertController
                    alertControllerWithTitle:title
                                     message:messgae
                              preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okButton = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction * action) {
                                    //Handle ok action
                                }];
    [alert addAction:okButton];
    [self presentViewController:alert animated:YES completion:nil];
}


- (void) messageBox:(NSString*)title withMessage:(NSString*)messgae
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:messgae
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * action) {}];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

/////////////////////////////////////////////////////////////////////////////
// RFID CALLBACK METHODS
/////////////////////////////////////////////////////////////////////////////
#pragma mark - IRfidSdkApiDelegate protocol implementation
- (void)srfidEventReaderAppeared:(srfidReaderInfo *)availableReader
{
    NSLog(@"iRead: srfidEventReaderAppeared RFID Reader ID=%d, Name=%@, conn-type=%d", [availableReader getReaderID],
          [availableReader getReaderName], [availableReader getConnectionType]);
    
//    [self messageBox:@"RFID Reader Detected"
//         withMessage:@"USB only Accessory\r\nDO NOT PAIR Bluetooth\r\n\r\nClick on the RFID Reader Icon Above to Connect" ];
//    
    
    // Handle reader appeared event
    BOOL found = NO;
    
    // Update reader list
    if (YES == [m_readerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (srfidReaderInfo *ex_info in m_readerList)
        {
            if ([ex_info getReaderID] == [availableReader getReaderID])
            {
                [ex_info setActive:NO];
                [ex_info setConnectionType:[availableReader getConnectionType]];
                found = YES;
                break;
            }
        }
        
        if (found == NO)
        {
            srfidReaderInfo *reader_info = [[srfidReaderInfo alloc] init];
            [reader_info setActive:NO];
            [reader_info setReaderID:[availableReader getReaderID]];
            [reader_info setConnectionType:[availableReader getConnectionType]];
            [reader_info setReaderName:[availableReader getReaderName]];
            [reader_info setReaderModel:[availableReader getReaderModel]];
            [m_readerList addObject:reader_info];
            NSLog(@"iRead: m_readerList count = %d",(int) [m_readerList count]);
        }
        
        [m_readerListGuard unlock];
    }
    ///////////////////////////////
    // Update RFID Reader UI List
    [self reloadReaderListOnMainThread];
    
    if ([m_readerList count] >1){
        [self messageBox:@"WARNING: MULTIPLE READERS FOUND " withMessage:@"UNPAIR BLUETOOTH READER\r\n"];
    }
}

- (void)srfidEventReaderDisappeared:(int)readerID
{
    NSLog(@"iRead: srfidEventReaderDisappeared RFID Reader ID=%d", readerID);
    // Handle reader disappeared event
    NSInteger readerIndexToRemove = NSNotFound;
    // Update reader list
    if (YES == [m_readerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (NSInteger index = 0; index < m_readerList.count; index++)
        {
            srfidReaderInfo *ex_info = [m_readerList objectAtIndex:index];
            if ([ex_info getReaderID] == readerID)
            {
                readerIndexToRemove = index;
                break;
            }
        }
        if (readerIndexToRemove != NSNotFound) {
            [m_readerList removeObjectAtIndex:readerIndexToRemove];
        }
        [m_readerListGuard unlock];
    }
    ///////////////////////////////
    // UI RFID Reader
    [self reloadReaderListOnMainThread];
    
    
    
    ///////////////////////////////////////////////////////////////
    ///Chuck: iOS suspend  => cut the power to USB port (RFD40 Bluetooth search light turn on to confirm USB is disabled
    ///
    [self messageBox:@"Confirmed: srfidEventReaderDisappeared after iOS suspend or RFD40 OFF-MODE"
             withMessage:@"USB only Accessory\r\nDO NOT PAIR Bluetooth\r\n\r\nClick on the RFID Reader Icon Above to Connect\r\n\r\nIf no Reader Icon, press and hold the RFD40 trigger to wake up the reader after OFF-MODE" ];
    
        
}

- (void)srfidEventCommunicationSessionEstablished:(srfidReaderInfo*)activeReader
{
    NSLog(@"iRead: srfidEventCommunicationSessionEstablished RFID Reader ID=%d, Name=%@", [activeReader getReaderID], [activeReader getReaderName]);
    BOOL found = NO;
    
    if (YES == [m_readerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (srfidReaderInfo *ex_info in m_readerList)
        {
            if ([ex_info getReaderID] == [activeReader getReaderID])
            {
                [ex_info setActive:[activeReader isActive]];
                [ex_info setConnectionType:[activeReader getConnectionType]];
                found = YES;
                [rfidSdk srfidEstablishAsciiConnection:[activeReader getReaderID] aPassword:nil];
                NSLog(@"iRead: srfidEventCommunicationSessionEstablished Name=%@, setActive=%d", [activeReader getReaderName], [activeReader isActive]);
                iConnectedRfidId = [activeReader getReaderID];
                //[self setAFTriggerStop:[activeReader getReaderID] ];
                //[self setAFTriggerStart:[activeReader getReaderID] ];
                //Single Reasder Mode
                //[self setAFTriggerStop:iConnectedRfidId ];
                //[self setAFTriggerStart:iConnectedRfidId ];
                
                
                //Disable BatchMode
//                SRFID_BATCHMODECONFIG batchMode = SRFID_BATCHMODECONFIG_DISABLE;
//                NSString *staus_msg = [[NSString alloc]init];
//                [rfidSdk srfidSetBatchModeConfig:iConnectedRfidId aBatchModeConfig:batchMode aStatusMessage:&staus_msg];
//                
//                b_isConnected = true;
                NSLog(@"iRead: SET RFD40 ALIVE TIMEOUT");
                [self changeOffModeTimeout:iConnectedRfidId];

                break;
            }
        }
        if (found == NO)
        {
            [m_readerList addObject:activeReader];
        }
        [m_readerListGuard unlock];
        /////////////////////////
        //notify UI refresh
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadReaderListOnMainThread];
            self.btAutoScan.enabled = true;
        });
    }
}

- (void)srfidEventCommunicationSessionTerminated:(int)readerID
{
    NSLog(@"iRead: srfidEventCommunicationSessionTerminated RFID Reader ID=%d", readerID);
    b_isConnected = false;
    // Update device list
    if (YES == [m_readerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (srfidReaderInfo *ex_info in m_readerList)
        {
            if ([ex_info getReaderID] == readerID)
            {
                [ex_info setActive:NO];
                NSLog(@"iRead: srfidEventCommunicationSessionTerminated RFID Reader ID=%d, Active=%d", readerID, [ex_info isActive]);

                break;
            }
        }
        [m_readerListGuard unlock];
    }
    [self reloadReaderListOnMainThread];
}

///////////////////////////////
// RFID SDK Event Read Notify
- (void)srfidEventReadNotify:(int)readerID aTagData:(srfidTagData*)tagData
{
    iTotal++;
    NSLog(@"iRead: srfidEventReadNotify Tag ID=%@ from readerID=%d, RSSI=%d", tagData.getTagId, readerID, tagData.getPeakRSSI);
    {
        [self recordRfidTag:tagData];

        if(iTotal%17==1){
            [self scheduleTagListRefresh];
        }
    }
}

- (void)updateMyAppUI
{
    [self scheduleTagListRefresh];
}


////////////////////////////////////////////////////////////
// RFID SDK Event Status Notify
- (void) srfidEventStatusNotify:(int)readerID aEvent:(SRFID_EVENT_STATUS)event aNotification:(id)notificationData
{
    NSLog(@"iRead: srfidEventStatusNotify fromID=%d", readerID);
    if(event == SRFID_EVENT_STATUS_OPERATION_START) {
        b_isReading = true;
        NSLog(@"iRead: srfidEventStatusNotify SRFID_EVENT_STATUS_OPERATION_START");
        dispatch_async(dispatch_get_main_queue(), ^{
            self.lbStatus.text = @"Reading...";
        });
    }
    else if (event == SRFID_EVENT_STATUS_OPERATION_STOP){
        b_isReading = false;
        NSLog(@"iRead: srfidEventStatusNotify SRFID_EVENT_STATUS_OPERATION_STOP");
        dispatch_async(dispatch_get_main_queue(), ^{
            self.lbStatus.text = @"Read Stop"; //display summary event instead
            [self updateMyAppUI];
       });
    }
    else if (event == SRFID_EVENT_STATUS_OPERATION_END_SUMMARY){
        //*** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'Only run on the main thread!'
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"iRead: srfidEventStatusNotify SRFID_EVENT_STATUS_OPERATION_END_SUMMARY ,Total Tag=%d, Total Read Time=%ld ms", [notificationData getTotalTags], [notificationData getTotalTimeUs]/1000);
            int totalTag = [(srfidOperEndSummaryEvent *)notificationData getTotalTags];
            long totalTimeUS =  [(srfidOperEndSummaryEvent *)notificationData getTotalTimeUs];
            self.lbStatus.text = [NSString stringWithFormat:@"Total tags=%d Time=%ldms", totalTag, totalTimeUS/1000];
            NSLog(@"iRead: srfidEventStatusNotify, Decode notificationData: %@", self.lbStatus.text);
            [self scheduleTagListRefresh];
        });
    }
    else if (SRFID_EVENT_STATUS_OPERATION_BATCHMODE == event)
    {
        NSLog(@"iRead: ******************************************");
        NSLog(@"iRead: * SRFID_EVENT_STATUS_OPERATION_BATCHMODE *");
        NSLog(@"iRead: ******************************************");
        
        NSLog(@"ECRT: Force Stop");
        NSString *staus_msg = [[NSString alloc]init];
        [rfidSdk srfidStopInventory:iConnectedRfidId aStatusMessage:&staus_msg];
        
        NSLog(@"ECRT: srfidPurgeTags");
        [rfidSdk srfidPurgeTags:iConnectedRfidId aStatusMessage:&staus_msg];
        
        NSLog(@"ECRT: srfidGetConfigurations");
        [rfidSdk srfidGetConfigurations];
        
        
        SRFID_BATCHMODECONFIG batchMode = SRFID_BATCHMODECONFIG_DISABLE;
        [rfidSdk srfidSetBatchModeConfig:iConnectedRfidId aBatchModeConfig:batchMode aStatusMessage:&staus_msg];

    }
}

- (void)srfidEventProximityNotify:(int)readerID aProximityPercent:(int)proximityPercent{
    NSLog(@"iRead: srfidEventProximityNotify = %d", proximityPercent);
}

- (void)srfidEventTriggerNotify:(int)readerID aTriggerEvent:(SRFID_TRIGGEREVENT)triggerEvent{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (triggerEvent == SRFID_TRIGGEREVENT_PRESSED) {
            
            if(self->b_isReading){
                NSLog(@"iRead: SKIPPED!!!! RFID Trigger Pressed Event from readerID=%d", readerID);
            }else{
                NSLog(@"iRead: Reset Counter");
                self->iTotal = 0;
                [self->m_tagDB removeAllObjects]; //clear tag DB
                
                NSLog(@"iRead: RFID Trigger Pressed Event from readerID=%d", readerID);
                [self inventory:readerID];
            }
        }
        else {
            NSLog(@"iRead: RFID Trigger Released Event from readerID=%d", readerID);
            [self stopInventory:(int)readerID];
        }
    });
}

- (void)srfidEventBatteryNotity:(int)readerID aBatteryEvent:(srfidBatteryEvent*)batteryEvent{
    NSLog(@"iRead: to do battery event");
}

- (void)srfidEventMultiProximityNotify:(int)readerID aTagData:(srfidTagData *)tagData {
    NSLog(@"iRead: to do a");
}

- (void)srfidEventWifiScan:(int)readerID wlanSCanObject:(srfidWlanScanList *)wlanScanObject { 
    NSLog(@"iRead: to do wifi");
}



/////////////////////////////////////////////
// BARCODE SCANNER SDK Callback Delegates
/////////////////////////////////////////////
- (void)sbtEventScannerAppeared:(SbtScannerInfo*)availableScanner
{
    NSLog(@"iRead: sbtEventScannerAppeared availableScanner name=%@, ID=%d", [availableScanner getScannerName], [availableScanner getScannerID]);
    //Scanner SDK Reader Management API to add reader from availableScanner list
    BOOL found = NO;
    if (YES == [m_scannerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (SbtScannerInfo *ex_info in m_scannerList)
        {
            if ([ex_info getScannerID] == [availableScanner getScannerID])
            {
                [ex_info setActive:NO];
                [ex_info setAutoCommunicationSessionReestablishment:[availableScanner getAutoCommunicationSessionReestablishment]];
                [ex_info setConnectionType:[availableScanner getConnectionType]];
                found = YES;
                break;
            }
        }
        if (found == NO)
        {
            SbtScannerInfo *scanner_info = [[SbtScannerInfo alloc] init];
            [scanner_info setActive:NO];
            [scanner_info setScannerID:[availableScanner getScannerID]];
            [scanner_info setAutoCommunicationSessionReestablishment:[availableScanner getAutoCommunicationSessionReestablishment]];
            [scanner_info setConnectionType:[availableScanner getConnectionType]];
            [scanner_info setScannerName:[availableScanner getScannerName]];
            [scanner_info setScannerModel:[availableScanner getScannerModel]];
            [m_scannerList addObject:scanner_info];
        }
        [m_scannerListGuard unlock];
    }
    ///////////////////////////////
    // Update Scanner UI List
    [self reloadScannerListOnMainThread];
}

- (void)sbtEventScannerDisappeared:(int)scannerID
{
    NSLog(@"iRead: sbtEventScannerDisappeared scannerID=%d", scannerID);
    
    //Scanner SDK Reader Management API to remove list
    NSInteger scannerIndexToRemove = NSNotFound;
    if (YES == [m_scannerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (NSInteger index = 0; index < m_scannerList.count; index++)
        {
            SbtScannerInfo *ex_info = [m_scannerList objectAtIndex:index];
            // find scanner with ID in dev list
            if ([ex_info getScannerID] == scannerID)
            {
                scannerIndexToRemove = index;
                break;
            }
        }
        if (scannerIndexToRemove != NSNotFound) {
            [m_scannerList removeObjectAtIndex:scannerIndexToRemove];
        }
        [m_scannerListGuard unlock];
    }
    ///////////////////////////////
    // Update Scanner UI List
    [self reloadScannerListOnMainThread];
}

- (void)sbtEventCommunicationSessionEstablished:(SbtScannerInfo*)activeScanner
{
    NSLog(@"iRead: sbtEventCommunicationSessionEstablished activeScanner name=%@, ID=%d", [activeScanner getScannerName], [activeScanner getScannerID]);
    //Scanner SDK Reader Management API for ACTIVE Reader List
    BOOL found = NO;
    if (YES == [m_scannerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (SbtScannerInfo *ex_info in m_scannerList)
        {
            if ([ex_info getScannerID] == [activeScanner getScannerID])
            {
                /* find scanner with ID in dev list */
                [ex_info setActive:[activeScanner isActive]];
                [ex_info setAutoCommunicationSessionReestablishment:[activeScanner getAutoCommunicationSessionReestablishment]];
                [ex_info setConnectionType:[activeScanner getConnectionType]];
                NSLog(@"iRead: sbtEventCommunicationSessionEstablished Active=%d", [activeScanner isActive]);
                
                NSLog(@"iRead: turn on GREEN LED");
                [scannerSdk sbtLedControl:true aLedCode:1 forScanner:(int)[activeScanner getScannerID]];
                
                found = YES;
                break;
            }
        }
        if (found == NO)
        {
            [m_scannerList addObject:activeScanner];
        }
        [m_scannerListGuard unlock];
        
        
       
        ////////////////////////////////////
        //Notify UI refresh
        [self reloadScannerListOnMainThread];
    }
    
}

- (void)sbtEventCommunicationSessionTerminated:(int)scannerID
{
    NSLog(@"iRead: sbtEventCommunicationSessionTerminated scanner ID=%d", scannerID);
    
    //Scanner SDK Reader Management API
    if (YES == [m_scannerListGuard lockBeforeDate:[NSDate distantFuture]])
    {
        for (SbtScannerInfo *ex_info in m_scannerList)
        {
            if ([ex_info getScannerID] == scannerID)
            {
                [ex_info setActive:NO]; //Matched Termniated ID, set NOT Active after terminated
  
                NSLog(@"iRead: sbtEventCommunicationSessionTerminated setActive ID=%d, Active=%d", scannerID, [ex_info isActive]);
                break;
            }
        }
        [m_scannerListGuard unlock];
    }
    [self reloadScannerListOnMainThread];
}

///////////////////////////////////////////////////////////////////////////////////
//Barcode Event for Data
- (void) sbtEventBarcode:(NSString *)barcodeData barcodeType:(int)barcodeType fromScanner:(int)scannerID
{
    // Handle received barcode for scanner
    NSLog(@"iRead: sbtEventBarcode: data=%@, type=%d, id=%d", barcodeData, barcodeType, scannerID);
//    iTotal++; //to do count as RFID data
//    ///////////////////////////////////////
    //to do LOCK
    [self recordBarcodeValue:barcodeData];
}


- (void) sbtEventBarcodeData:(NSData *)barcodeData barcodeType:(int)barcodeType fromScanner:(int)scannerID
{
    NSLog(@"iRead: !!!new sbtEventBarcodeData: data=%@, type=%d, id=%d", barcodeData, barcodeType, scannerID);
    
    NSString* barcodeDataNew = [NSString stringWithUTF8String:[barcodeData bytes]];
    NSLog(@"iRead: !!!new sbtEventBarcodeData: dataString=%@", barcodeDataNew);
    
    [self recordBarcodeValue:barcodeDataNew];
}

- (void)sbtEventImage:(NSData*)imageData fromScanner:(int)scannerID{
    //To Do
}

- (void)sbtEventVideo:(NSData*)videoFrame fromScanner:(int)scannerID{
    //To Do
}

- (void)sbtEventFirmwareUpdate:(FirmwareUpdateEvent *)fwUpdateEventObj {
    //To Do
}


- (void)sbtEventRawData:(NSData *)rawData fromScanner:(int)scannerID{
    NSLog(@"iRead: to do d");
}

//////////////////////////////////////////////////
//UI tableView Cell Number
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(tableView==self.tbViewReaderList) //two tableViews
        return m_readerList.count;
    else if (tableView==self.tbViewTagList)
        return m_tagKeysSnapshot.count;
    else if (tableView==self.tbViewScannerList)
        return m_scannerList.count;
    return 1; //default
}
//////////////////////////////////////////////////
//UI tableView Update Status for Connect/Disconnect/Image
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(tableView==self.tbViewReaderList)
    {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reuseID"];
        int index = (int)[indexPath row];
        srfidReaderInfo *info = [m_readerList objectAtIndex:index];
        cell.textLabel.text = [info getReaderName];
        if ([info isActive]){
            cell.imageView.image = [UIImage imageNamed:@"Connected"];
            cell.imageView.contentMode= UIViewContentModeScaleAspectFit;
        }
        else {
            cell.imageView.image = [UIImage imageNamed:@"rfidReader"];
            cell.imageView.contentMode= UIViewContentModeScaleAspectFit;
        }
        return cell;
    }
    else if (tableView==self.tbViewScannerList)
    {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reuseID_Scanner"];
        int index = (int)[indexPath row];
        SbtScannerInfo *info = [m_scannerList objectAtIndex:index];
        cell.textLabel.text = [info getScannerName];
        if ([info isActive]){
            cell.imageView.image = [UIImage imageNamed:@"Connected"];
            cell.imageView.contentMode= UIViewContentModeScaleAspectFit;
        }
        else {
            cell.imageView.image = [UIImage imageNamed:@"barcodeReader"];
            cell.imageView.contentMode= UIViewContentModeScaleAspectFit;
        }
        return cell;
    }
    else
    {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reuseID_TagList"];
        if(m_tagKeysSnapshot.count > indexPath.row){
            NSString *keyTagEPC = m_tagKeysSnapshot[indexPath.row];
            NSString *itemCount = nil;
            if ([m_tagDBGuard lockBeforeDate:[NSDate distantFuture]]) {
                itemCount = m_tagDB[keyTagEPC];
                [m_tagDBGuard unlock];
            }
            cell.textLabel.text = keyTagEPC;
            cell.detailTextLabel.text = itemCount;
        }
        return cell;
    }
}
//////////////////////////////////////////////////
//UI tableView Update did Select Action Operations
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(tableView==self.tbViewReaderList){
        //RFID SDK Reader Managmenet API
        //1. Select Active Reader(Do Action Disconnect)
        //2. Select NOT ACTIVE (Do Action Connect)
        srfidReaderInfo *selectdReader = [m_readerList objectAtIndex:(int)[indexPath row]];
        if([selectdReader isActive]) {
            NSLog(@"iRead: srfidReaderInfo RFID reader management is Active (Connected), Send Disconnect Command for reader name=%@ ID=%d", [selectdReader getReaderName], [selectdReader getReaderID]);
            [self disconnectFromRfidSdk:[selectdReader getReaderID]];
        }
        else {
            NSLog(@"iRead: srfidReaderInfo RFID reader management is NOT Active (Disconnected), Send Connect Command for reader Name=%@ ID=%d", [selectdReader getReaderName], [selectdReader getReaderID]);
            [self connectToRfidSdk:[selectdReader getReaderID]];
        }
    }else if (tableView==self.tbViewScannerList){
        //Barcode Scanner SDK: Scanner Managmenet API
        //1. Select Active Scanner (Do Action Disconnect)
        //2. Select NOT ACTIVE (Do Action Connect)
        SbtScannerInfo *selectedScanner = [m_scannerList objectAtIndex:(int)[indexPath row]];
        if([selectedScanner isActive]) {
            NSLog(@"iRead: srfidReaderInfo Barcode Scanner management is Active (Connected), Send Disconnect Command for Scanner Name=%@, ID=%d", [selectedScanner getScannerName], [selectedScanner getScannerID]);
            [self disconnectFromScannerSdk:[selectedScanner getScannerID]];
        }
        else {
            NSLog(@"iRead: srfidReaderInfo Barcode Scanner management is NOT Active (Disconnected), Send Connect Command");
            [self connectToScannerSdk:[selectedScanner getScannerID]];
        }
    } else {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

//////////////////////////////////////
// UI Buttons Controllers
- (IBAction)btClickedStart:(id)sender
{
//    if(b_isReading){
//        NSLog(@"iRead: SKIP!!!!!!!!!!!!!!!!!!!!!!!!!!READING");
//        return;
//    }
    //UI
    self.lbUnique.text = @"0";
    self.lbStatus.text = @"Attempt Starting RFID Inventory...";
    self.swtichCountRSSI.enabled = false;
    
    self.btStop.enabled = true;
    self.btStart.enabled = false;
    self.btAutoScan.enabled = false;
    self.btStopScan.enabled = false;
    [self clearTagDatabase];
    [self scheduleTagListRefresh];
    /////////////////////////////////////////////
    ///
    ///
    ///
    unsigned long iReaderFound = [m_readerList count];

    if (iReaderFound>0){
        for(srfidReaderInfo *info in m_readerList){
            if([info isActive]) {
                NSLog(@"iRead: Active Reader ID=%d Name=%@, send Inventory Command.", [info getReaderID], [info getReaderName]);
                [self inventory:[info getReaderID]];
            }
            else{
                NSLog(@"iRead: Reader ID=%d Name=%@ is NOT, Skip Inventory!", [info getReaderID], [info getReaderName]);
            }
        }
    }
    else if (iReaderFound==0){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self messageBox:@"ERROR: Reader NOT Found" withMessage:@"To Power On Reader: Pull and Hold Trigger"];
        });
    }
    else{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self messageBox:@"ERROR: Reader Disconnected" withMessage:@"Click on the Reader Icon Above to Connect"];
        });
    }
}

- (IBAction)btClickedStop:(id)sender
{
//    if(b_isReading){
//        NSLog(@"iRead: SKIP STOP!!!!!!!!!!!!!!!!!!!!!!!!!!READING");
//        return;
//    }
    NSLog(@"iRead: srfidStopInventory Attemp to Stop Inventory...");
    self.lbStatus.text = @"Attempt Stop RFID Inventory...";
    self.swtichCountRSSI.enabled = true;
    self.btStart.enabled = true;
    self.btStop.enabled = false;
    self.btAutoScan.enabled = true;
    self.btStopScan.enabled = false;
    //Configure
    //NSString *staus_msg = [[NSString alloc]init];
    if(rfidSdk!=nil) {
        for(srfidReaderInfo *info in m_readerList){
            if([info isActive]) {
                iConnectedRfidId = [info getReaderID];
                NSLog(@"iRead: ##### Active Reader ID=%d, Name=%@, Send Stop Inventory Command: srfidStopInventory.", iConnectedRfidId, [info getReaderName]);
                [self stopInventory: iConnectedRfidId];
            }
            else{
                NSLog(@"iRead: Reader ID=%d, Name=%@ is NOT Active, Skip Stop Inventory!", [info getReaderID], [info getReaderName]);
            }
        }
    }
}

- (IBAction)btClickClear:(id)sender
{
    [self clearTagDatabase];
    [self scheduleTagListRefresh];
    self.lbUnique.text = @"";
}

- (IBAction)switchButtonChanged:(id)sender
{
    if([self.swtichCountRSSI isOn])
        self.lbStatus.text = @"Show Tag Count";
    else
        self.lbStatus.text = @"Show RSSI Value";
}

//Location Code
- (IBAction)btClickedAutoScan:(id)sender
{
//    if(b_isReading){
//        NSLog(@"iRead: SKIP LOCATION!!!!!!!!!!!!!!!!!!!!!!!!!!");
//        return;
//    }
    NSLog(@"iRead: Tag Location-ing.....");
    self.lbStatus.text = @"Tag Location-ing...";
    self.btStart.enabled = false;
    self.btStop.enabled = false;
    self.btAutoScan.enabled = false;
    self.btStopScan.enabled = true;
    ///////////////////////////////////////////////////////////////////////////////////
    //for tag locate
    [self startTagLocationing:iConnectedRfidId];
}

- (IBAction)btClickedStopScan:(id)sender
{
//    if(b_isReading){
//        NSLog(@"iRead: SKIP STOP LOCATION!!!!!!!!!!!!!!!!!!!!!!!!!!READING");
//        return;
//    }
    NSLog(@"iRead: Release Trigger, Attempt Stoping Scan...");
    self.lbStatus.text = @"Stop Scanning";
    self.btStart.enabled = true;
    self.btStop.enabled = false;
    self.btAutoScan.enabled = true;
    self.btStopScan.enabled = false;
    ///////////////////////////////////////////////////////////////////////////////////
    //for Tag Locate
    [self stopTagLocationing:iConnectedRfidId];
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    NSLog(@"iRead: to do 1");
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    NSLog(@"iRead: to do 2");
}

- (void)preferredContentSizeDidChangeForChildContentContainer:(nonnull id<UIContentContainer>)container {
    NSLog(@"iRead: to do 3");
}

- (CGSize)sizeForChildContentContainer:(nonnull id<UIContentContainer>)container withParentContainerSize:(CGSize)parentSize {
    NSLog(@"iRead: to do 4");
    return CGSizeZero;
}

- (void)systemLayoutFittingSizeDidChangeForChildContentContainer:(nonnull id<UIContentContainer>)container {
    NSLog(@"iRead: to do 5");
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(nonnull id<UIViewControllerTransitionCoordinator>)coordinator {
    NSLog(@"iRead: to do 6");
}

- (void)willTransitionToTraitCollection:(nonnull UITraitCollection *)newCollection withTransitionCoordinator:(nonnull id<UIViewControllerTransitionCoordinator>)coordinator {
    NSLog(@"iRead: to do 7");
}

- (void)didUpdateFocusInContext:(nonnull UIFocusUpdateContext *)context withAnimationCoordinator:(nonnull UIFocusAnimationCoordinator *)coordinator {
    NSLog(@"iRead: to do 8");
}

- (void)setNeedsFocusUpdate {
    NSLog(@"iRead: to do 9");
}

- (BOOL)shouldUpdateFocusInContext:(nonnull UIFocusUpdateContext *)context {
    NSLog(@"iRead: to do 10");
    return false;
}

- (void)updateFocusIfNeeded {
    NSLog(@"iRead: to do 11");
}


/*
 typedef NS_ENUM(NSInteger, CBManagerState) {
     CBManagerStateUnknown = 0,
     CBManagerStateResetting,
     CBManagerStateUnsupported,
     CBManagerStateUnauthorized,
     CBManagerStatePoweredOff, //4
     CBManagerStatePoweredOn, //5
 } NS_ENUM_AVAILABLE(10_13, 10_0);
 */

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    NSLog(@"BT State = %d", (int) central.state);
    if(CBManagerStatePoweredOn == central.state){
        NSLog(@"CBManagerStatePoweredOn = %d", (int)central.state);
        [self messageBox:@"DO NOT PAIR Bluetooth"
             withMessage:@"USB only Accessory: \r\nDO NOT PAIR Bluetooth\r\nCBManagerStatePoweredOn" ];
    }
    if(CBManagerStatePoweredOff == central.state){
        NSLog(@"CBManagerStatePoweredOff = %d", (int)central.state);
     
        //Chuck: DO NOT do the following code to avoid the following message
        //API MISUSE: <CBCentralManager: 0x303861cc0> can only accept this command while in the powered on state
        //XPC connection invalid
//        dispatch_async(dispatch_get_main_queue(), ^{
//            NSDictionary *options = @{CBCentralManagerOptionShowPowerAlertKey: @NO};
//            self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:options];
//            self.data = [[NSMutableData alloc] init];
//            [self.centralManager scanForPeripheralsWithServices:nil options:options];
//        });
    }
}


- (void)disable
{
    
    [self centralManager];
}


- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    
    NSLog(@"Discovered %@ at %@", peripheral.name, RSSI);
    
    if (_discoveredPeripheral != peripheral) {
        // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
        _discoveredPeripheral = peripheral;
        
        // And connect
        NSLog(@"Connecting to peripheral %@", peripheral);
        [_centralManager connectPeripheral:peripheral options:nil];
    }
}

@end
