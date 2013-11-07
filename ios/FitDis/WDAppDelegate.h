//
//  WDAppDelegate.h
//  WeatherDemo
//
//  Created by Martijn The on 2/7/13.
//  Copyright (c) 2013 Pebble Technology Corp. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface WDAppDelegate : UIResponder <UIApplicationDelegate, UITabBarControllerDelegate> {
    CBCentralManager *manager;
    CBPeripheral *peripheral;
    BOOL autoConnect;
}

@property (strong, nonatomic) UIWindow *window;

@end
