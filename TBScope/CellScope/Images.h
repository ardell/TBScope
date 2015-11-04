//
//  Images.h
//  TBScope
//
//  Created by Frankie Myers on 2/18/14.
//  Copyright (c) 2014 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <PromiseKit/Promise.h>
#import "GoogleDriveService.h"

@class ImageAnalysisResults, Slides;

@interface Images : NSManagedObject

// Only public so we can mock it out in tests
@property (nonatomic, retain) GoogleDriveService *googleDriveService;

@property (nonatomic) int32_t fieldNumber;
@property (nonatomic, retain) NSString * metadata;
@property (nonatomic, retain) NSString * imageContentMetrics;
@property (nonatomic, retain) NSString * imageFocusMetrics;
@property (nonatomic, retain) NSString * path;
@property (nonatomic, retain) NSString * googleDriveFileID;
@property (nonatomic, retain) ImageAnalysisResults *imageAnalysisResults;
@property (nonatomic, retain) Slides *slide;

- (PMKPromise *)uploadToGoogleDrive;
- (PMKPromise *)downloadFromGoogleDrive;

@end
