//
//  WDAppDelegate.m
//  WeatherDemo
//
//  Created by Martijn The on 2/7/13.
//  Copyright (c) 2013 Pebble Technology Corp. All rights reserved.
//

#import "WDAppDelegate.h"
#import <PebbleKit/PebbleKit.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface WDAppDelegate () <PBPebbleCentralDelegate, CLLocationManagerDelegate>
@end

@implementation WDAppDelegate {
    PBWatch *_targetWatch;
    CLLocationManager *_locationManager;
    UILabel *heartRateLabel;
    UILabel *hrmStatusLabel;
    UILabel *devicenameLabel;
    UILabel *manufacturerLabel;
    UILabel *pebbleStatusLabel;
    UILabel *pebbleWatchNameLabel;}

NSData *dataByIntepretingHexString(NSString *hexString) {
    char const *chars = hexString.UTF8String;
    NSUInteger charCount = strlen(chars);
    if (charCount % 2 != 0) {
        return nil;
    }
    NSUInteger byteCount = charCount / 2;
    uint8_t *bytes = malloc(byteCount);
    for (int i = 0; i < byteCount; ++i) {
        unsigned int value;
        sscanf(chars + i * 2, "%2x", &value);
        bytes[i] = value;
    }
    return [NSData dataWithBytesNoCopy:bytes length:byteCount freeWhenDone:YES];
}

- (uint16_t) heartRateFromData:(NSData *)data
{
    const uint8_t *reportData = [data bytes];
    uint16_t bpm = 0;
    
    if ((reportData[0] & 0x01) == 0) {
        /* uint8 bpm */
        bpm = reportData[1];
    }
    else {
        /* uint16 bpm */
        bpm = CFSwapInt16LittleToHost(*(uint16_t *)(&reportData[1]));
    }
    
    return bpm;
}

/*
 Update UI with heart rate data received from device
 */
- (void) updateWithHRMData:(NSData *)data {
    int heartRate = [self heartRateFromData:data];
    
    // NSURLConnection's completionHandler is called on the background thread.
    // Prepare a block to show an alert on the main thread:
    __block NSString *message = @"";
    void (^showAlert)(void) = ^{
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }];
    };

    // NSURLConnection's completionHandler is called on the background thread.
    // Prepare a block to show an alert on the main thread:
    __block NSString *newHR = @"";
    void (^paintHR)(void) = ^{
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self->heartRateLabel setText:newHR];
        }];
    };
    
    newHR = [NSString stringWithFormat:@"%d",heartRate];
    paintHR();

    // Send data to watch:
    // See demos/feature_app_messages/weather.c in the native watch app SDK for the same definitions on the watch's end:
    NSNumber *heartRateKey = @(0); // This is our custom-defined key for the heart rate string.
    NSDictionary *update = @{ heartRateKey:[NSString stringWithFormat:@"%d bpm", heartRate] };
 
    if (_targetWatch != nil && [_targetWatch isConnected] == YES) {
        [_targetWatch appMessagesPushUpdate:update onSent:^(PBWatch *watch, NSDictionary *update, NSError *error) {
            message = error ? [error localizedDescription] : [NSString stringWithFormat:@"sent: %d bpm", heartRate];
            NSLog(@"Update watch: %@", message);
        }];
    }
    
}


#pragma mark - Start/Stop Scan methods

/*
 Uses CBCentralManager to check whether the current platform/hardware supports Bluetooth LE. An alert is raised if Bluetooth LE is not enabled or is not supported.
 */
- (BOOL) isLECapableHardware {
    NSString * state = nil;
    
    switch ([manager state]) {
        case CBCentralManagerStateUnsupported:
            state = @"The platform/hardware doesn't support Bluetooth Low Energy.";
            break;
        case CBCentralManagerStateUnauthorized:
            state = @"The app is not authorized to use Bluetooth Low Energy.";
            break;
        case CBCentralManagerStatePoweredOff:
            state = @"Bluetooth is currently powered off.";
            break;
        case CBCentralManagerStatePoweredOn:
            return TRUE;
        case CBCentralManagerStateUnknown:
        default:
            return FALSE;
    }
    
    NSLog(@"Central manager state: %@", state);
    return FALSE;
}

/*
 Request CBCentralManager to scan for heart rate peripherals using service UUID 0x180D
 */
- (void) startScan {
    [manager scanForPeripheralsWithServices:[NSArray arrayWithObject:[CBUUID UUIDWithString:@"180D"]] options:nil];
}

/*
 Request CBCentralManager to stop scanning for heart rate peripherals
 */
- (void) stopScan {
    [manager stopScan];
}

#pragma mark - CBCentralManager delegate methods
/*
 Invoked whenever the central manager's state is updated.
 */
- (void) centralManagerDidUpdateState:(CBCentralManager *)central {
    [self isLECapableHardware];
}

/*
 Invoked when the central discovers heart rate peripheral while scanning.
 */
- (void) centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)aPeripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    [manager retrievePeripherals:[NSArray arrayWithObject:(id)aPeripheral.UUID]];
}

/*
 Invoked when the central manager retrieves the list of known peripherals.
 Automatically connect to first known peripheral
 */
- (void)centralManager:(CBCentralManager *)central didRetrievePeripherals:(NSArray *)peripherals {
    NSLog(@"Retrieved peripheral: %d - %@", [peripherals count], peripherals);
    
    [self stopScan];
    
    /* If there are any known devices, automatically connect to it.*/
    if([peripherals count] >=1)
    {
        peripheral = [peripherals objectAtIndex:0];
        //[peripheral retain];
        [manager connectPeripheral:peripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
    }
}

/*
 Invoked whenever a connection is succesfully created with the peripheral.
 Discover available services on the peripheral
 */
- (void) centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)aPeripheral {
    [aPeripheral setDelegate:self];
    [aPeripheral discoverServices:nil];
    NSLog(@"Connected to peripheral!");
    [hrmStatusLabel setText: @"Connected"];
    [hrmStatusLabel setTextColor: [UIColor greenColor]];
}

/*
 Invoked whenever an existing connection with the peripheral is torn down.
 Reset local variables
 */
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)aPeripheral error:(NSError *)error {
	NSLog(@"Peripheral Disconnected");
    if( peripheral ) {
        [peripheral setDelegate:nil];
        //        [peripheral release];
        peripheral = nil;
    }
    [hrmStatusLabel setText: @"Disconnected!"];
    [hrmStatusLabel setTextColor: [UIColor redColor]];
    NSLog(@"Rescanning...");
    [self stopScan];
    [self startScan];
}

/*
 Invoked whenever the central manager fails to create a connection with the peripheral.
 */
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)aPeripheral error:(NSError *)error {
    NSLog(@"Fail to connect to peripheral: %@ with error = %@", aPeripheral, [error localizedDescription]);
    //[connectButton setTitle:@"Connect"];
    if( peripheral )
    {
        [peripheral setDelegate:nil];
        //[peripheral release];
        peripheral = nil;
    }
}

#pragma mark - CBPeripheral delegate methods
/*
 Invoked upon completion of a -[discoverServices:] request.
 Discover available characteristics on interested services
 */
- (void) peripheral:(CBPeripheral *)aPeripheral didDiscoverServices:(NSError *)error {
    for (CBService *aService in aPeripheral.services)
    {
        NSLog(@"Service found with UUID: %@", aService.UUID);
        
        /* Heart Rate Service */
        if ([aService.UUID isEqual:[CBUUID UUIDWithString:@"180D"]])
        {
            [aPeripheral discoverCharacteristics:nil forService:aService];
        }
        
        /* Device Information Service */
        if ([aService.UUID isEqual:[CBUUID UUIDWithString:@"180A"]])
        {
            [aPeripheral discoverCharacteristics:nil forService:aService];
        }
        
        /* GAP (Generic Access Profile) for Device Name */
        if ( [aService.UUID isEqual:[CBUUID UUIDWithString:CBUUIDGenericAccessProfileString]] )
        {
            [aPeripheral discoverCharacteristics:nil forService:aService];
        }
    }
}


/*
 Invoked upon completion of a -[discoverCharacteristics:forService:] request.
 Perform appropriate operations on interested characteristics
 */
- (void) peripheral:(CBPeripheral *)aPeripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if ([service.UUID isEqual:[CBUUID UUIDWithString:@"180D"]]) {
        for (CBCharacteristic *aChar in service.characteristics) {
            /* Set notification on heart rate measurement */
            if ([aChar.UUID isEqual:[CBUUID UUIDWithString:@"2A37"]]) {
                [aPeripheral setNotifyValue:YES forCharacteristic:aChar];
                NSLog(@"Found a Heart Rate Measurement Characteristic");
            }
            
            /* Write heart rate control point */
            if ([aChar.UUID isEqual:[CBUUID UUIDWithString:@"2A39"]]) {
                uint8_t val = 1;
                NSData* valData = [NSData dataWithBytes:(void*)&val length:sizeof(val)];
                [aPeripheral writeValue:valData forCharacteristic:aChar type:CBCharacteristicWriteWithResponse];
            }
        }
    }
    
    if ( [service.UUID isEqual:[CBUUID UUIDWithString:CBUUIDGenericAccessProfileString]] ) {
        for (CBCharacteristic *aChar in service.characteristics) {
            /* Read device name */
            if ([aChar.UUID isEqual:[CBUUID UUIDWithString:CBUUIDDeviceNameString]]) {
                [aPeripheral readValueForCharacteristic:aChar];
                NSLog(@"Found a Device Name Characteristic");
            }
        }
    }
    
    if ([service.UUID isEqual:[CBUUID UUIDWithString:@"180A"]]) {
        for (CBCharacteristic *aChar in service.characteristics) {
            /* Read manufacturer name */
            if ([aChar.UUID isEqual:[CBUUID UUIDWithString:@"2A29"]]) {
                [aPeripheral readValueForCharacteristic:aChar];
                NSLog(@"Found a Device Manufacturer Name Characteristic");
            }
        }
    }
}

/*
 Invoked upon completion of a -[readValueForCharacteristic:] request or on the reception of a notification/indication.
 */
- (void) peripheral:(CBPeripheral *)aPeripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    /* Updated value for heart rate measurement received */
    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@"2A37"]]) {
        if( (characteristic.value)  || !error ) {
            /* Update UI with heart rate data */
            [self updateWithHRMData:characteristic.value];
        }
    }
    /* Value for device Name received */
    else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:CBUUIDDeviceNameString]]) {
        NSString * deviceName = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
        NSLog(@"Device Name = %@", deviceName);
        [devicenameLabel setText:deviceName];
    }
    /* Value for manufacturer name received */
    else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@"2A29"]]) {
        NSString * manufacturer = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
        NSLog(@"Manufacturer Name = %@", manufacturer);
        [manufacturerLabel setText:manufacturer];
    }
}

- (NSString *)heartRateStringFromBLE {
    //return @"163A1304";
    return @"16388304";
}

- (void)refreshAction:(id)sender {
    if (_targetWatch == nil || [_targetWatch isConnected] == NO) {
        [[[UIAlertView alloc] initWithTitle:nil message:@"No connected watch!" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    
    // Fetch weather at current location using openweathermap.org's JSON API:
    CLLocationCoordinate2D coordinate = _locationManager.location.coordinate;
    NSString *apiURLString = [NSString stringWithFormat:@"http://api.openweathermap.org/data/2.1/find/city?lat=%f&lon=%f&cnt=1", coordinate.latitude, coordinate.longitude];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:apiURLString]];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSHTTPURLResponse *httpResponse = nil;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *) response;
        }
        
        // NSURLConnection's completionHandler is called on the background thread.
        // Prepare a block to show an alert on the main thread:
        __block NSString *message = @"";
        void (^showAlert)(void) = ^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }];
        };
        
        // Check for error or non-OK statusCode:
        if (error || httpResponse.statusCode != 200) {
            message = @"Error fetching weather";
            showAlert();
            return;
        }
        
        // Parse the JSON response:
        NSError *jsonError = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        @try {
            if (jsonError == nil && root) {
                // TODO: type checking / validation, this is really dangerous...
                NSDictionary *firstListItem = [root[@"list"] objectAtIndex:0];
                NSDictionary *main = firstListItem[@"main"];
                
                // Get the temperature:
                NSNumber *temperatureNumber = main[@"temp"]; // in degrees Kelvin
                int temperature = [temperatureNumber integerValue] - 273.15;
                
                // Get weather icon:
                //        NSNumber *weatherIconNumber = firstListItem[@"weather"][0][@"icon"];
                //        uint8_t weatherIconID = [self getIconFromWeatherId:[weatherIconNumber integerValue]];
                
                int heartRate = 0;
                
                // Send data to watch:
                // See demos/feature_app_messages/weather.c in the native watch app SDK for the same definitions on the watch's end:
                NSNumber *iconKey = @(0); // This is our custom-defined key for the icon ID, which is of type uint8_t.
                NSNumber *heartRateKey = @(0); // This is our custom-defined key for the temperature string.
                NSDictionary *update = @{ heartRateKey:[NSString stringWithFormat:@"%d bpm", heartRate] };
                [_targetWatch appMessagesPushUpdate:update onSent:^(PBWatch *watch, NSDictionary *update, NSError *error) {
                    message = error ? [error localizedDescription] : @"Update sent!";
                    showAlert();
                }];
                return;
            }
        }
        @catch (NSException *exception) {
        }
        message = @"Error parsing response";
        showAlert();
    }];
}

- (void)setTargetWatch:(PBWatch*)watch {
    _targetWatch = watch;
    
    // NOTE:
    // For demonstration purposes, we start communicating with the watch immediately upon connection,
    // because we are calling -appMessagesGetIsSupported: here, which implicitely opens the communication session.
    // Real world apps should communicate only if the user is actively using the app, because there
    // is one communication session that is shared between all 3rd party iOS apps.
    
    // Test if the Pebble's firmware supports AppMessages / Weather:
    [watch appMessagesGetIsSupported:^(PBWatch *watch, BOOL isAppMessagesSupported) {
        if (isAppMessagesSupported) {
            // Configure our communications channel to target the weather app:
            // See demos/feature_app_messages/weather.c in the native watch app SDK for the same definition on the watch's end:
            uint8_t bytes[] = {0x51, 0x7B, 0xBE, 0x33, 0xFC, 0x34, 0x43, 0x10, 0x93, 0xAE, 0x04, 0xF6, 0x7C, 0x2B, 0xF5, 0xFD};
            NSData *uuid = [NSData dataWithBytes:bytes length:sizeof(bytes)];
            [watch appMessagesSetUUID:uuid];
            
            NSLog(@"Connected to pebble!");
            [pebbleStatusLabel setText: @"Connected"];
            [pebbleStatusLabel setTextColor: [UIColor greenColor]];
            [pebbleWatchNameLabel setText:[watch name]];

        } else {
            
            NSString *message = [NSString stringWithFormat:@"Blegh... %@ does NOT support AppMessages :'(", [watch name]];
            [[[UIAlertView alloc] initWithTitle:@"Connected..." message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
    }];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.distanceFilter = 5.0 * 1000.0; // Move at least 5km until next location event is generated
    _locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
    _locationManager.delegate = self;
    [_locationManager startUpdatingLocation];

    UILabel *appTitle = [[UILabel alloc] init];
    [appTitle setText: @"Pat's Fit Dis!"];
    [appTitle setTextColor: [UIColor whiteColor]];
    [appTitle setFont:[UIFont boldSystemFontOfSize:20]];
    [appTitle setFrame:CGRectMake(100, 10, 300, 100)];
    [self.window addSubview:appTitle];

    
    UIImageView *heartImage=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Heart.png"]];
    [heartImage setFrame:CGRectMake(20,120,128,128)];
    [self.window addSubview:heartImage];
  
    heartRateLabel = [[UILabel alloc] init];
    [heartRateLabel setFont:[UIFont boldSystemFontOfSize:100]];
    [heartRateLabel setTextColor: [UIColor whiteColor]];
    [heartRateLabel setText:@"--"];
    [heartRateLabel setFrame:CGRectMake(170,130,120,120)];
    [self.window addSubview:heartRateLabel];
    
    UIButton *refreshButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [refreshButton setTitle:@"Clear Heart Rate" forState:UIControlStateNormal];
    [refreshButton addTarget:self action:@selector(refreshAction:) forControlEvents:UIControlEventTouchUpInside];
    [refreshButton setFrame:CGRectMake(10, 300, 300, 100)];
    [self.window addSubview:refreshButton];
    
    UILabel *hrmStatusTitle = [[UILabel alloc] init];
    [hrmStatusTitle setText: @"HRM Status:"];
    [hrmStatusTitle setTextColor: [UIColor lightGrayColor]];
    [hrmStatusTitle setFrame:CGRectMake(10, 400, 300, 100)];
    [self.window addSubview:hrmStatusTitle];
    hrmStatusLabel = [[UILabel alloc] init];
    [hrmStatusLabel setText: @"Disconnected!"];
    [hrmStatusLabel setTextColor: [UIColor redColor]];
    [hrmStatusLabel setFrame:CGRectMake(160, 400, 300, 100)];
    [self.window addSubview:hrmStatusLabel];

    manufacturerLabel = [[UILabel alloc] init];
    [manufacturerLabel setText: @""];
    [manufacturerLabel setTextColor: [UIColor lightGrayColor]];
    [manufacturerLabel setFrame:CGRectMake(160, 420, 300, 100)];
    [self.window addSubview:manufacturerLabel];
    devicenameLabel = [[UILabel alloc] init];
    [devicenameLabel setText: @""];
    [devicenameLabel setTextColor: [UIColor lightGrayColor]];
    [devicenameLabel setFrame:CGRectMake(160, 440, 300, 100)];
    [self.window addSubview:devicenameLabel];

    UILabel *pebbleStatusTitle = [[UILabel alloc] init];
    [pebbleStatusTitle setText: @"Pebble Status:"];
    [pebbleStatusTitle setTextColor: [UIColor lightGrayColor]];
    [pebbleStatusTitle setFrame:CGRectMake(10, 470, 300, 100)];
    [self.window addSubview:pebbleStatusTitle];
    pebbleStatusLabel = [[UILabel alloc] init];
    [pebbleStatusLabel setText: @"Disconnected!"];
    [pebbleStatusLabel setTextColor: [UIColor redColor]];
    [pebbleStatusLabel setFrame:CGRectMake(160, 470, 300, 100)];
    [self.window addSubview:pebbleStatusLabel];
    
    pebbleWatchNameLabel = [[UILabel alloc] init];
    [pebbleWatchNameLabel setText: @""];
    [pebbleWatchNameLabel setTextColor: [UIColor lightGrayColor]];
    [pebbleWatchNameLabel setFrame:CGRectMake(160, 490, 300, 100)];
    [self.window addSubview:pebbleWatchNameLabel];


    
    [self.window makeKeyAndVisible];
    
    // We'd like to get called when Pebbles connect and disconnect, so become the delegate of PBPebbleCentral:
    [[PBPebbleCentral defaultCentral] setDelegate:self];
    
    // Initialize with the last connected watch:
    [self setTargetWatch:[[PBPebbleCentral defaultCentral] lastConnectedWatch]];
    
    //initialise bluetooth
    manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    NSLog(@"Starting SCAN");
    [manager scanForPeripheralsWithServices:[NSArray arrayWithObject:[CBUUID UUIDWithString:@"180D"]] options:nil];
    return YES;
}

/*
 *  PBPebbleCentral delegate methods
 */

- (void)pebbleCentral:(PBPebbleCentral*)central watchDidConnect:(PBWatch*)watch isNew:(BOOL)isNew {
    [self setTargetWatch:watch];
}

- (void)pebbleCentral:(PBPebbleCentral*)central watchDidDisconnect:(PBWatch*)watch {
    NSLog(@"Disconnected from pebble!");
    [pebbleStatusLabel setText: @"Disconnected!"];
    [pebbleStatusLabel setTextColor: [UIColor redColor]];
    [[[UIAlertView alloc] initWithTitle:@"Disconnected!" message:[watch name] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    if (_targetWatch == watch || [watch isEqual:_targetWatch]) {
        [self setTargetWatch:nil];
    }
}

/*
 *  CLLocationManagerDelegate
 */

// iOS 5 and earlier:
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    NSLog(@"New Location: %@", newLocation);
}

// iOS 6 and later:
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *lastLocation = [locations lastObject];
    [self locationManager:manager didUpdateToLocation:lastLocation fromLocation:nil];
}

@end
