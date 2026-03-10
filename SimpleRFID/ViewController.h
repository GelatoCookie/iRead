//
//  ViewController.h
//  SimpleRFID
//
//  Created by RFID ECRT on 6/23/16.
//  Copyright © 2016 Zebra Technologies. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "RfidSdkApi.h" // RFID SDK Header
#import "ISbtSdkApi.h" // Scanner SDK Header

#import "CoreBluetooth/CoreBluetooth.h"

@interface ViewController : UIViewController <UITableViewDataSource, UITableViewDelegate,
srfidISdkApiDelegate, ISbtSdkApiDelegate, CBCentralManagerDelegate, CBPeripheralDelegate>

@property (weak, nonatomic) IBOutlet UITableView *tbViewReaderList;
@property (weak, nonatomic) IBOutlet UITableView *tbViewTagList;
@property (weak, nonatomic) IBOutlet UITableView *tbViewScannerList;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *btClear;
@property (weak, nonatomic) IBOutlet UILabel *lbUnique;
@property (weak, nonatomic) IBOutlet UILabel *lbStatus;
@property (weak, nonatomic) IBOutlet UIButton *btStart;
@property (weak, nonatomic) IBOutlet UIButton *btStop;
@property (weak, nonatomic) IBOutlet UIButton *btAutoScan;
@property (weak, nonatomic) IBOutlet UIButton *btStopScan;
@property (weak, nonatomic) IBOutlet UISwitch *swtichCountRSSI;

@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheral *discoveredPeripheral;
@property (strong, nonatomic) NSMutableData *data;

@end

