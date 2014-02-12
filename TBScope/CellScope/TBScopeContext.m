//
//  TBScopeContext.m
//  TBScope
//
//  Created by Frankie Myers on 2/8/14.
//  Copyright (c) 2014 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "TBScopeContext.h"

@implementation TBScopeContext

@synthesize ble;

+ (id)sharedContext {
    static TBScopeContext *newContext = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        newContext = [[self alloc] init];
    });
    return newContext;
}

- (id)init {
    if (self = [super init]) {

        
    }
    return self;
}

- (void)setupBLEConnection {
    
    //todo: handle case where microscope not found
    ble = [[BLE alloc] init];
    [ble controlSetup];
    ble.delegate = self;

    //connect to BLE devices
    //first disconnect from any current connections
    //this is probably not necessary, just start the timer
    if (ble.activePeripheral)
        if(ble.activePeripheral.isConnected)
        {
            [[ble CM] cancelPeripheralConnection:[ble activePeripheral]];
            //[btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
            return;
        }
    if (ble.peripherals)
        ble.peripherals = nil;
    
    //now reconnect
    [ble findBLEPeripherals:2];
    [NSTimer scheduledTimerWithTimeInterval:(float)1.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
}

#pragma mark - BLE delegate

- (void)bleDidDisconnect
{
    [ble findBLEPeripherals:2];
    [NSTimer scheduledTimerWithTimeInterval:(float)1.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
    
    NSLog(@"->Disconnected");
    //fire this off as a notification
}

// When RSSI is changed, this will be called
-(void) bleDidUpdateRSSI:(NSNumber *) rssi
{
    //lblRSSI.text = rssi.stringValue;
    
}

// When disconnected, this will be called
-(void) bleDidConnect
{
    NSLog(@"->Connected");
    //fire this off as a notification
}

// When data is comming, this will be called
-(void) bleDidReceiveData:(unsigned char *)data length:(int)length
{
    NSLog(@"Length: %d", length);
    
    // parse data, all commands are in 3-byte
    for (int i = 0; i < length; i+=3)
    {
        NSLog(@"0x%02X, 0x%02X, 0x%02X", data[i], data[i+1], data[i+2]);
        
        if (data[i] == 0x0A)
        {
        }
        else if (data[i] == 0x0B)
        {
            UInt16 Value;
            
            Value = data[i+2] | data[i+1] << 8;
        }
    }
}

//This function is called by an NSTimer at 1s interval
//It attempts to connect to BLE device, and auto-retries if it fails
-(void) connectionTimer:(NSTimer *)timer
{
    
    if (ble.peripherals.count > 0)
    {
        for (CBPeripheral* p in ble.peripherals)
        {
            NSLog(p.identifier.UUIDString);
            if ([p.identifier.UUIDString isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"CellScopeBTUUID"]])
            {
                [ble connectPeripheral:[ble.peripherals objectAtIndex:0]];
            }
        }
        
    }
    else
    {
        //try connecting again
        if (ble.activePeripheral)
            if(ble.activePeripheral.isConnected)
            {
                [[ble CM] cancelPeripheralConnection:[ble activePeripheral]];
                return;
            }
        
        if (ble.peripherals)
            ble.peripherals = nil;
        
        [ble findBLEPeripherals:2];
        [NSTimer scheduledTimerWithTimeInterval:(float)1.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
        
    }
}


//stage/led controls (maybe belongs in another file)

-(void) disableMotors
{
    UInt8 buf[3] = {0x03, 0x01, 0x00};
    [ble write:[NSData dataWithBytes:buf length:3]];
    buf[1] = 0x02;
    [ble write:[NSData dataWithBytes:buf length:3]];
    buf[1] = 0x03;
    [ble write:[NSData dataWithBytes:buf length:3]];
}

- (void) moveStageWithDirection:(CSStageDirection) dir
                          Steps:(int)steps
                   DisableAfter:(BOOL)disableAfter
{
    NSLog(@"moving stage");
    UInt8 buf[3] = {0x00, 0x00, 0x00};
    
    //set dir
    buf[0] = 0x02;
    switch (dir) {
        case CSStageDirectionUp:
            buf[1] = 0x02;
            buf[2] = 0x01;
            break;
        case CSStageDirectionDown:
            buf[1] = 0x02;
            buf[2] = 0x00;
            break;
        case CSStageDirectionLeft:
            buf[1] = 0x01;
            buf[2] = 0x00;
            break;
        case CSStageDirectionRight:
            buf[1] = 0x01;
            buf[2] = 0x01;
            break;
        case CSStageDirectionFocusUp:
            buf[1] = 0x03;
            buf[2] = 0x00;
            break;
        case CSStageDirectionFocusDown:
            buf[1] = 0x03;
            buf[2] = 0x01;
            break;
    }
    [ble write:[NSData dataWithBytes:buf length:3]];
    
    //enable
    buf[0] = 0x03;
    buf[2] = 0x01;
    [ble write:[NSData dataWithBytes:buf length:3]];
    
    //step
    buf[0] = 0x01;
    buf[2]= (UInt8)steps;
    [ble write:[NSData dataWithBytes:buf length:3]];
    
    //disable
    if (disableAfter)
    {
        buf[0] = 0x03;
        buf[2] = 0x00;
        [ble write:[NSData dataWithBytes:buf length:3]];
    }
    
}

- (void) setMicroscopeLED:(CSLED) led
                    Level:(Byte) level
{
    NSLog(@"setting LED state");
    
    //0x04: LED command
    UInt8 buf[3] = {0x04, 0x00, 0x00};
    
    //set LED
    switch (led) {
        case CSLEDFluorescent:
            buf[1] = 0x01;
            break;
        case CSLEDBrightfield:
            buf[1] = 0x02;
            break;
    }
    
    //set state
    //buf[2] = on?0x01:0x00;
    buf[2] = level;
    
    [ble write:[NSData dataWithBytes:buf length:3]];
}

@end
