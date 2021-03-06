//
//  TBScopeContext.m
//  TBScope
//
//  Created by Frankie Myers on 2/8/14.
//  Copyright (c) 2014 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "TBScopeHardwareReal.h"

BOOL _isMoving = NO;
CBPeripheral* _tbScopePeripheral;

@implementation TBScopeHardwareReal

const int MIN_Z_POSITION = 0;
const int MAX_Z_POSITION = 50000;  //  50,000 is safely clear of the tray
                                   // 107,500 is starting to make weird noises against the base
                                   // 109,200 is absolute bottom

@synthesize batteryVoltage,
            temperature,
            humidity,
            ble,
            delegate,
            xPosition,
            yPosition,
            zPosition;

- (instancetype)init
{
    if (self = [super init]) {
        self.xPosition = 0;
        self.yPosition = 0;
        self.zPosition = 0;
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
        if(ble.activePeripheral.state == CBPeripheralStateConnected)
        {
            [[ble CM] cancelPeripheralConnection:[ble activePeripheral]];
            return;
        }
    if (ble.peripherals)
        ble.peripherals = nil;
    
    
    [TBScopeData CSLog:@"Searching for Bluetooth CellScope" inCategory:@"HARDWARE"];
    
    //now connect
    [ble findBLEPeripherals:2];
    [NSTimer scheduledTimerWithTimeInterval:(float)1.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
}

- (BOOL)isConnected
{
    return [self.ble isConnected];
}

#pragma mark - BLE delegate

- (void)bleDidDisconnect
{
    [ble findBLEPeripherals:2];
    [NSTimer scheduledTimerWithTimeInterval:(float)1.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
    
    [TBScopeData CSLog:@"Bluetooth Disconnected" inCategory:@"HARDWARE"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BluetoothDisconnected" object:nil];
    
}

// When RSSI is changed, this will be called
-(void) bleDidUpdateRSSI:(NSNumber *) rssi
{
    
}

// When connected, this will be called
-(void) bleDidConnect
{
    [TBScopeData CSLog:@"Bluetooth Connected" inCategory:@"HARDWARE"];
    
    [self setMicroscopeLED:CSLEDBrightfield Level:0];
    [self setMicroscopeLED:CSLEDFluorescent Level:0];
    [self disableMotors];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BluetoothConnected" object:nil];
}

// When data is comming, this will be called
-(void) bleDidReceiveData:(unsigned char *)data length:(int)length
{
    // parse data, all commands are in 3-byte chunks
    for (int i = 0; i < length; i+=3)
    {
        
        if (data[i] == 0xFF) //all "move completed" messages should start with FF
        {
            BOOL xLimit = ((data[i+1] & 0b00000100)!=0);
            BOOL yLimit = ((data[i+1] & 0b00000010)!=0);
            BOOL zLimit = ((data[i+1] & 0b00000001)!=0);
            
            _isMoving = NO;
            
            //[[self delegate] tbScopeStageMoveDidCompleteWithXLimit:xLimit YLimit:yLimit ZLimit:zLimit];
        }
        else if (data[i] == 0xFE) //battery
        {
            float batteryVoltage = ((data[i+1]<<8) | data[i+2])*5.0/1024;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"StatusUpdated" object:nil];
            NSLog(@"battery = %f",batteryVoltage);
            self.batteryVoltage = batteryVoltage;
        }
        else if (data[i] == 0xFD) //temp
        {
            float temperature = ((data[i+1]<<8) | data[i+2])*1.007e-2 - 40.0;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"StatusUpdated" object:nil];
            NSLog(@"temp = %f",temperature);
            self.temperature = temperature;
        }
        else if (data[i] == 0xFC) //humidity
        {
            float humidity = ((data[i+1]<<8) | data[i+2])*6.1e-3;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"StatusUpdated" object:nil];
            NSLog(@"humidity = %f",humidity);
            self.humidity = humidity;
        }
        
        else
        {
            NSLog(@"unrecognized response from scope");
        }
    }
}

//This function is called by an NSTimer at 1s interval
//It attempts to connect to BLE device, and auto-retries if it fails
-(void) connectionTimer:(NSTimer *)timer
{
    BOOL NewTBScopeWasFound = NO;
    BOOL PreviouslyPairedTBScopeWasFound = NO;
    _tbScopePeripheral = nil;
    
    if (ble.peripherals.count > 0)
    {
        for (CBPeripheral* p in ble.peripherals)
        {
            if ([p.name isEqualToString:@"TB Scope"]) {
                [TBScopeData CSLog:[NSString stringWithFormat:@"TB Scope detected w/ UUID: %@",p.identifier.UUIDString]
                        inCategory:@"HARDWARE"];
                
                _tbScopePeripheral = p;
                
                if ([p.identifier.UUIDString isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"CellScopeBTUUID"]])
                {
                    PreviouslyPairedTBScopeWasFound = YES;
                    _tbScopePeripheral = p;
                    break; //stop searching
                }
                else
                {
                    NewTBScopeWasFound = YES;
                    //keep searching, in case we see the one we want
                }
            }
        }
    }
    
    if (PreviouslyPairedTBScopeWasFound) {
        [ble connectPeripheral:_tbScopePeripheral];
    }
    else if (NewTBScopeWasFound) {

        [TBScopeData CSLog:@"Currently paired CellScope was not detected." inCategory:@"HARDWARE"];
        
        UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Bluetooth Connection", nil)
                                                         message:NSLocalizedString(@"A new CellScope has been detected. Pair this iPad with this CellScope?",nil)
                                                        delegate:self
                                               cancelButtonTitle:NSLocalizedString(@"No",nil)
                                               otherButtonTitles:NSLocalizedString(@"Yes",nil),nil];
        alert.alertViewStyle = UIAlertViewStyleDefault;
        alert.tag = 1;
        [alert show];
    }
    else
    {
        //try connecting again
        if (ble.activePeripheral)
            if(ble.activePeripheral.state == CBPeripheralStateConnected)
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

-(void) pairBLECellScope
{
    if (ble.peripherals.count > 0)
    {
        NSString* newUUID = (_tbScopePeripheral).identifier.UUIDString;
        
        [[NSUserDefaults standardUserDefaults] setObject:newUUID forKey:@"CellScopeBTUUID"];
        
        [ble connectPeripheral:_tbScopePeripheral];
        
        [TBScopeData CSLog:[NSString stringWithFormat:@"This iPad is now paired with CellScope Bluetooth UUID: %@",newUUID]
                inCategory:@"HARDWARE"];
        
    }
    
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag==1) //this is the title prompt for new photo/video
    {
        if (buttonIndex==1) {
            [self pairBLECellScope];
        }
    }
}

//stage/led controls (maybe belongs in another file)

-(void) disableMotors
{
    [self moveStageWithDirection:CSStageDirectionDown Steps:0 StopOnLimit:NO DisableAfter:YES];
    [self moveStageWithDirection:CSStageDirectionLeft Steps:0 StopOnLimit:NO DisableAfter:YES];
    [self moveStageWithDirection:CSStageDirectionFocusUp Steps:0 StopOnLimit:NO DisableAfter:YES];

}

//TODO: would be better to have this automatic
//also, should fire off a warning message if battery, temp, or humidity out of spec
- (void) requestStatusUpdate
{
    //top 3 bits = opcode (5 for status request)
    UInt8 buf[3] = {0b10100000, 0x00, 0x00};
    [ble write:[NSData dataWithBytes:buf length:3]];
    
    //this will result in 3 responses, which will fire off 3 separate notifications
}

- (void) setStepperInterval:(UInt16)stepInterval
{
    UInt8 buf[3] = {0x00, 0x00, 0x00};
    
    // set speed
    //   0   1   0   -   -   -   -   -                           {16 bits}
    // |-----------  ------  --- --- ---||-------------------------||---------------------------|
    //   move cmd                                  speed (half step interval in ms)
    
    buf[0] |= 0b01000000; //move command
    buf[1] = (UInt8)((stepInterval & 0xFF00) >> 8);
    buf[2] = (UInt8)(stepInterval & 0x00FF);
    
    //send move command
    [ble write:[NSData dataWithBytes:buf length:3]];
}

// Move stage in maxStepsPerRound increments since moving in larger
// increments makes a lot of noise and causes the microscope to
// vibrate
- (void)moveStageWithDirection:(CSStageDirection)dir
                         Steps:(UInt16)steps
                   StopOnLimit:(BOOL)stopOnLimit
                  DisableAfter:(BOOL)disableAfter
{
    const int maxStepsPerRound = 100;
    int stepsSoFar = 0;
    while (stepsSoFar < steps) {
        int stepsThisRound = MIN(steps, maxStepsPerRound);
        NSLog(@"Moving %d steps", stepsThisRound);
        [self _moveStageWithDirection:dir
                                Steps:stepsThisRound
                          StopOnLimit:stopOnLimit
                         DisableAfter:disableAfter];
        [self waitForStage];
        stepsSoFar += stepsThisRound;
    }
}

- (void) _moveStageWithDirection:(CSStageDirection)dir
                           Steps:(UInt16)steps
                     StopOnLimit:(BOOL)stopOnLimit
                    DisableAfter:(BOOL)disableAfter
{
    UInt8 buf[3] = {0x00, 0x00, 0x00};
    
    // move stage
    //   0   0   1   A   A   D   L   E                           {16 bits}
    // |-----------  ------  --- --- ---||-------------------------||---------------------------|
    //   move cmd     axis   dir lim en                         # steps
    
    buf[0] |= 0b00100000; //move command
    
    switch (dir) {
        case CSStageDirectionUp:
            self.yPosition += steps;
            buf[0] |= 0b00001100;
            break;
        case CSStageDirectionDown:
            self.yPosition -= steps;
            buf[0] |= 0b00001000;
            break;
        case CSStageDirectionLeft:
            self.xPosition -= steps;
            buf[0] |= 0b00010000;
            break;
        case CSStageDirectionRight:
            self.xPosition += steps;
            buf[0] |= 0b00010100;
            break;
        case CSStageDirectionFocusUp:
            if (self.zPosition-steps < MIN_Z_POSITION) { // Don't move past limit
                steps = self.zPosition - MIN_Z_POSITION;
            }
            self.zPosition -= steps;  // zPosition is distance from origin which is (counter-intuitively) at the top
            buf[0] |= 0b00011000;
            break;
        case CSStageDirectionFocusDown:
            if (self.zPosition+steps > MAX_Z_POSITION) { // Don't move past limit
                steps = MAX_Z_POSITION - self.zPosition;
            }
            self.zPosition += steps;  // zPosition is distance from origin which is (counter-intuitively) at the top
            buf[0] |= 0b00011100;
            break;
    }
    if (stopOnLimit)
        buf[0] |= 0b00000010;
    if (disableAfter)
        buf[0] |= 0b00000001;
    
    //last 2 bytes = # steps
    buf[1] = (UInt8)((steps & 0xFF00) >> 8);
    buf[2] = (UInt8)(steps & 0x00FF);
    
    //send move command
    _isMoving = YES;
    [ble write:[NSData dataWithBytes:buf length:3]];
    NSLog(@"moved to (%d, %d, %d)", self.xPosition, self.yPosition, self.zPosition);
}

- (void) moveToPosition:(CSStagePosition) position
{
    UInt8 buf[3] = {0b01100000, 0x00, 0x00};
    _isMoving = YES;
    
    switch (position) {
        case CSStagePositionHome:
            self.xPosition = 0;
            self.yPosition = 0;
            buf[1] = 0x00;
            break;
        case CSStagePositionTestTarget:
            // What to do here?
            buf[1] = 0x01;
            break;
        case CSStagePositionSlideCenter:
            // What to do here?
            buf[1] = 0x02;
            break;
        case CSStagePositionLoading:
            // What to do here?
            buf[1] = 0x03;
            break;
        case CSStagePositionZHome:
            self.zPosition = 0;
            buf[1] = 0x04;
            break;
    }
    
    
    [ble write:[NSData dataWithBytes:buf length:3]];
}

- (void)moveToX:(int)x Y:(int)y Z:(int)z
{
    if (x >= 0) {
        int xSteps = (int)x - self.xPosition;
        if (xSteps > 0) {
            [self moveStageWithDirection:CSStageDirectionRight
                                   Steps:xSteps
                             StopOnLimit:YES
                            DisableAfter:NO];
            [self waitForStage];
        } else if (xSteps < 0) {
            [self moveStageWithDirection:CSStageDirectionLeft
                                   Steps:ABS(xSteps)
                             StopOnLimit:YES
                            DisableAfter:NO];
            [self waitForStage];
        }
    }

    if (y >= 0) {
        int ySteps = (int)y - self.yPosition;
        if (ySteps > 0) {
            [self moveStageWithDirection:CSStageDirectionUp
                                   Steps:ySteps
                             StopOnLimit:YES
                            DisableAfter:NO];
            [self waitForStage];
        } else if (ySteps < 0) {
            [self moveStageWithDirection:CSStageDirectionDown
                                   Steps:ABS(ySteps)
                             StopOnLimit:YES
                            DisableAfter:NO];
            [self waitForStage];
        }
    }

    if (z >= 0) {
        int zSteps = (int)z - self.zPosition;
        if (zSteps > 0) {
            [self moveStageWithDirection:CSStageDirectionFocusDown
                                   Steps:zSteps
                             StopOnLimit:YES
                            DisableAfter:NO];
            [self waitForStage];
        } else if (zSteps < 0) {
            [self moveStageWithDirection:CSStageDirectionFocusUp
                                   Steps:ABS(zSteps)
                             StopOnLimit:YES
                            DisableAfter:NO];
            [self waitForStage];
        }
    }

    [[TBScopeHardware sharedHardware] disableMotors];
}

- (void) waitForStage
{
    while (_isMoving)
        [NSThread sleepForTimeInterval:0.05];
    
    //[NSThread sleepForTimeInterval:0.1]; //give stage some time to settle
}

- (void) setMicroscopeLED:(CSLED) led
                    Level:(Byte) level
{
    NSLog(@"setting LED state");
    
    //0x04: LED command
    UInt8 buf[3] = {0b10000000, 0x00, 0x00};
    
    //set LED
    switch (led) {
        case CSLEDFluorescent:
            buf[1] = 0x01;
            break;
        case CSLEDBrightfield:
            buf[1] = 0x02;
            break;
    }
    
    buf[2] = level;
    
    [ble write:[NSData dataWithBytes:buf length:3]];
}


@end
