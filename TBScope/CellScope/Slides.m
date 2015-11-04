//
//  Slides.m
//  TBScope
//
//  Created by Frankie Myers on 2/18/14.
//  Copyright (c) 2014 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "Slides.h"
#import "Exams.h"
#import "Images.h"
#import "SlideAnalysisResults.h"
#import "TBScopeData.h"
#import "TBScopeImageAsset.h"
#import "NSData+MD5.h"
#import "PMKPromise+NoopPromise.h"

@implementation Slides

@synthesize googleDriveService;
@dynamic slideNumber;
@dynamic sputumQuality;
@dynamic dateCollected;
@dynamic dateScanned;
@dynamic roiSpritePath;
@dynamic roiSpriteGoogleDriveFileID;
@dynamic slideAnalysisResults;
@dynamic slideImages;
@dynamic exam;

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

- (void)addSlideImagesObject:(Images *)value {
    NSMutableOrderedSet* tempSet = [NSMutableOrderedSet orderedSetWithOrderedSet:self.slideImages];
    [tempSet addObject:value];
    self.slideImages = tempSet;
}

- (PMKPromise *)uploadRoiSpriteSheetToGoogleDrive
{
    __block NSString *remoteMd5;
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        [self.managedObjectContext performBlock:^{
            resolve(self.roiSpritePath);
        }];
    }].then(^(NSString *roiSpritePath) {
        if (!roiSpritePath) return [PMKPromise noopPromise];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                // Fetch metadata
                [self.googleDriveService getMetadataForFileId:self.roiSpriteGoogleDriveFileID]
                    .then(^(GTLDriveFile *file) { resolve(file); })
                    .catch(^(NSError *error) { resolve(error); });
            }];
        }];
    }).then(^(GTLDriveFile *existingRemoteFile) {
        if (!existingRemoteFile) return [PMKPromise noopPromise];

        // Assign remote md5 for later use
        remoteMd5 = [existingRemoteFile md5Checksum];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                // Do nothing if local file is not newer than remote
                NSDate *localTime = [TBScopeData dateFromString:self.exam.dateModified];
                NSDate *remoteTime = existingRemoteFile.modifiedDate.date;
                if ([remoteTime timeIntervalSinceDate:localTime] > 0) {
                    resolve(nil);
                } else {
                    resolve(self.roiSpritePath);
                }
            }];
        }];
    }).then(^(NSString *localPath) {
        if (!localPath) return [PMKPromise noopPromise];

        // Fetch data from the filesystem
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                [TBScopeImageAsset getImageAtPath:self.roiSpritePath]
                    .then(^(NSData *data) { resolve(data); })
                    .catch(^(NSError *error) { resolve(error); });
            }];
        }];
    }).then(^(UIImage *image) {
        // Do nothing if local file is same as remote
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            NSData *localData = UIImageJPEGRepresentation((UIImage *)image, 1.0);
            NSString *localMd5 = [localData MD5];
            if ([localMd5 isEqualToString:remoteMd5]) {
                resolve(nil);
            } else {
                resolve(localData);
            }
        }];
    }).then(^(NSData *data) {
        if (!data) return [PMKPromise noopPromise];

        // Upload the file
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                GTLDriveFile *file = [GTLDriveFile object];
                file.title = [NSString stringWithFormat:@"%@ - %@ - %d rois.jpg",
                              self.exam.cellscopeID,
                              self.exam.examID,
                              self.slideNumber];
                file.descriptionProperty = @"Uploaded from CellScope";
                file.mimeType = @"image/jpeg";
                file.modifiedDate = [GTLDateTime dateTimeWithRFC3339String:self.exam.dateModified];
                [self.googleDriveService uploadFile:file withData:data]
                    .then(^(GTLDriveFile *file) { resolve(file); })
                    .catch(^(NSError *error) { resolve(error); });
            }];
        }];
    }).then(^(GTLDriveFile *remoteFile) {
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            if (remoteFile) {
                [self.managedObjectContext performBlock:^{
                    self.roiSpriteGoogleDriveFileID = remoteFile.identifier;
                    resolve(self);
                }];
            } else {
                resolve(nil);
            }
        }];
    });
}

- (PMKPromise *)downloadRoiSpriteSheetFromGoogleDrive
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        [self.managedObjectContext performBlock:^{
            if (self.roiSpriteGoogleDriveFileID) {
                resolve(self.roiSpriteGoogleDriveFileID);
            } else {
                resolve(nil);
            }
        }];
    }].then(^(NSString *roiSpriteGoogleDriveFileID) {
        if (!roiSpriteGoogleDriveFileID) return [PMKPromise noopPromise];

        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            // Get metadata for existing roiSpriteSheet
            [self.googleDriveService getMetadataForFileId:roiSpriteGoogleDriveFileID]
                .then(^(GTLDriveFile *file) { resolve(file); })
                .catch(^(NSError *error) { resolve(error); });
        }];
    }).then(^(GTLDriveFile *existingRemoteFile) {
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                // Do nothing if remote file is not newer than remote
                NSDate *localTime = [TBScopeData dateFromString:self.exam.dateModified];
                NSDate *remoteTime = existingRemoteFile.modifiedDate.date;
                if ([localTime timeIntervalSinceDate:remoteTime] > 0) {
                    resolve(nil);
                } else {
                    resolve(existingRemoteFile);
                }
            }];
        }];
    }).then(^(GTLDriveFile *existingRemoteFile) {
        if (!existingRemoteFile) return [PMKPromise noopPromise];

        // Download the file
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.googleDriveService getFile:existingRemoteFile]
                .then(^(NSData *data) { resolve(data); })
                .catch(^(NSError *error) { resolve(error); });
        }];
    }).then(^(NSData *data) {
        // Save to file
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [TBScopeImageAsset saveImage:[UIImage imageWithData:data]]
                .then(^(NSString *path) { resolve(path); })
                .catch(^(NSError *error) { resolve(error); });
        }];
    }).then(^(NSString *localFilePath) {
        // Update roiSpritePath
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                self.roiSpritePath = localFilePath;
                resolve(nil);
            }];
        }];
    });
}

@end
