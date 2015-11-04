//
//  Images.m
//  TBScope
//
//  Created by Frankie Myers on 2/18/14.
//  Copyright (c) 2014 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "Images.h"
#import <UIKit/UIKit.h>
#import "ImageAnalysisResults.h"
#import "Slides.h"
#import "TBScopeImageAsset.h"
#import "GoogleDriveService.h"
#import "PMKPromise+NoopPromise.h"
#import "PMKPromise+RejectedPromise.h"
#import "Exams.h"

@implementation Images

@synthesize googleDriveService;
@dynamic fieldNumber;
@dynamic metadata;
@dynamic imageContentMetrics;
@dynamic imageFocusMetrics;
@dynamic path;
@dynamic googleDriveFileID;
@dynamic imageAnalysisResults;
@dynamic slide;

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    [self initGoogleDriveService];
}

- (void)awakeFromFetch
{
    [super awakeFromFetch];
    [self initGoogleDriveService];
}

- (void)initGoogleDriveService
{
    self.googleDriveService = [[GoogleDriveService alloc] init];
}

- (PMKPromise *)uploadToGoogleDrive
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        [self.managedObjectContext performBlock:^{
            resolve(self.googleDriveFileID);
        }];
    }].then(^(NSString *googleDriveFileID) {
        if (googleDriveFileID) return [PMKPromise noopPromise];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                [TBScopeImageAsset getImageAtPath:[self path]]
                    .then(^(UIImage *image) { resolve(image); })
                    .catch(^(NSError *error) { resolve(error); });
            }];
        }];
    }).then(^ PMKPromise* (UIImage *image) {
        if (!image) return [PMKPromise noopPromise];

        // Upload the file
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                // Create a google file object from this image
                GTLDriveFile *file = [GTLDriveFile object];
                file.title = [NSString stringWithFormat:@"%@ - %@ - %d-%d.jpg",
                              self.slide.exam.cellscopeID,
                              self.slide.exam.examID,
                              self.slide.slideNumber,
                              self.fieldNumber];
                file.descriptionProperty = @"Uploaded from CellScope";
                file.mimeType = @"image/jpeg";
                file.modifiedDate = [GTLDateTime dateTimeWithRFC3339String:self.slide.exam.dateModified];
                NSData *data = UIImageJPEGRepresentation((UIImage *)image, 1.0);

                [self.googleDriveService uploadFile:file withData:data]
                    .then(^(GTLDriveFile *file) { resolve(file); })
                    .catch(^(NSError *error) { resolve(error); });
            }];
        }];
    }).then(^ PMKPromise* (GTLDriveFile *file) {
        if (!file) return [PMKPromise noopPromise];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            if (file) {
                [self.managedObjectContext performBlock:^{
                    self.googleDriveFileID = file.identifier;
                    resolve(nil);
                }];
            } else {
                NSError *error = [NSError errorWithDomain:@"Images" code:0 userInfo:nil];
                resolve(error);
            }
        }];
    });
}

- (PMKPromise *)downloadFromGoogleDrive
{
    GoogleDriveService *gds = self.googleDriveService;
    __block NSString *path;
    __block NSString *googleDriveFileID;
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        [self.managedObjectContext performBlock:^{
            path = self.path;
            googleDriveFileID = self.googleDriveFileID;
            resolve(nil);
        }];
    }].then(^{
        if (!googleDriveFileID) return [PMKPromise noopPromise];

        GTLDriveFile *file = [GTLDriveFile object];
        file.identifier = googleDriveFileID;
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            if (!path) {
                resolve(file);
                return;
            }

            [TBScopeImageAsset getImageAtPath:path]
                .then(^(UIImage *image) {
                    if (image) {
                        resolve(nil);  // do nothing
                    } else {
                        resolve(file);  // keep downloading
                    }
                })
                .catch(^(NSError *error) {
                    resolve(file);  // no file found, keep downloading
                });
        }];
    }).then(^ PMKPromise* (GTLDriveFile *file) {
        if (!file) return [PMKPromise noopPromise];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [gds getFile:file]
                .then(^(NSData *data) { resolve(data); })
                .catch(^(NSError *error) { resolve(error); });
        }];
    }).then(^ PMKPromise* (NSData *data) {
        if (!data) return [PMKPromise noopPromise];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            // Save this image to asset library as jpg
            UIImage* im = [UIImage imageWithData:data];
            [TBScopeImageAsset saveImage:im]
                .then(^(NSString *path) { resolve(path); })
                .catch(^(NSError *error) { resolve(error); });
        }];
    }).then(^ PMKPromise* (NSString *path) {
        if (!path) return [PMKPromise noopPromise];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                self.path = path;
                resolve(self);
            }];
        }];
    });
}

@end
