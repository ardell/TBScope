//
//  GoogleDriveService.h
//  TBScope
//
//  Created by Jason Ardell on 11/5/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <PromiseKit/Promise.h>
#import "GTLDrive.h"

@interface GoogleDriveService : NSObject

@property (nonatomic, retain) GTLServiceDrive *driveService;

// Public so we can mock it out in tests
@property (nonatomic) float googleDriveTimeout;

- (BOOL)isLoggedIn;
- (NSString*)userEmail;

- (PMKPromise *)getMetadataForFileId:(NSString *)fileId;
- (PMKPromise *)fileExists:(GTLDriveFile *)file;
- (PMKPromise *)getFile:(GTLDriveFile *)file;
- (PMKPromise *)uploadFile:(GTLDriveFile *)file withData:(NSData *)data;
- (PMKPromise *)downloadFileWithId:(NSString *)fileId;
- (PMKPromise *)deleteFileWithId:(NSString *)fileId;

- (PMKPromise *)executeQueryWithTimeout:(GTLQuery *)query;

@end
