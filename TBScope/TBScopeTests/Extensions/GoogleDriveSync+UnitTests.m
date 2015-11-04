//
//  GoogleDriveSync+UnitTests.m
//  TBScope
//
//  Created by Jason Ardell on 11/10/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "GoogleDriveSync+UnitTests.h"

@implementation GoogleDriveSync(UnitTests)

+ (instancetype)sharedGDS
{
    return [[GoogleDriveSync alloc] performSelector:@selector(initPrivate)];
}

@end