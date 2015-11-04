//
//  Exams.m
//  TBScope
//
//  Created by Frankie Myers on 10/9/2014.
//  Copyright (c) 2014 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "Exams.h"
#import "FollowUpData.h"
#import "Slides.h"
#import "GTLDrive.h"
#import "CoreDataJSONHelper.h"
#import <PromiseKit/Promise+Join.h>
#import "PMKPromise+NoopPromise.h"
#import "PMKPromise+RejectedPromise.h"
#import "NSData+MD5.h"
#import "CoreDataJSONHelper.h"

@implementation Exams

@dynamic bluetoothUUID;
@dynamic cellscopeID;
@dynamic dateModified;
@dynamic diagnosisNotes;
@dynamic examID;
@dynamic googleDriveFileID;
@dynamic gpsLocation;
@dynamic intakeNotes;
@dynamic ipadMACAddress;
@dynamic ipadName;
@dynamic location;
@dynamic patientAddress;
@dynamic patientDOB;
@dynamic patientGender;
@dynamic patientHIVStatus;
@dynamic patientID;
@dynamic patientName;
@dynamic synced;
@dynamic userName;
@dynamic examSlides;
@dynamic examFollowUpData;

- (void)addExamSlidesObject:(Slides *)value {
    NSMutableOrderedSet* tempSet = [NSMutableOrderedSet orderedSetWithOrderedSet:self.examSlides];
    [tempSet addObject:value];
    self.examSlides = tempSet;
}

- (PMKPromise *)uploadToGoogleDrive:(GoogleDriveService *)gds
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        // Upload all slide ROI sprite sheets
        NSMutableArray *promises = [[NSMutableArray alloc] init];
        [self.managedObjectContext performBlockAndWait:^{
            for (Slides *slide in self.examSlides) {
                PMKPromise *promise = [slide uploadRoiSpriteSheetToGoogleDrive];
                [promises addObject:promise];
            }
        }];
        [PMKPromise join:[promises copy]]
            .then(^(id fulfilledResults, NSArray *errors) {
                if ([errors count] > 0) {
                    resolve([errors firstObject]);
                } else {
                    resolve(nil);
                }
            });
    }].then(^{
        // Get remote file
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                if (self.googleDriveFileID) {
                    [gds getMetadataForFileId:self.googleDriveFileID]
                        .then(^(GTLDriveFile *file) { resolve(file); })
                        .catch(^(NSError *error) { resolve(error); });
                } else {
                    resolve(nil);
                }
            }];
        }];
    }).then(^(GTLDriveFile *existingRemoteFile) {
        // Calculate data (for md5 hash)
        NSArray *arrayToSerialize = [NSArray arrayWithObjects:self, nil];
        __block NSData *data;
        [self.managedObjectContext performBlockAndWait:^{
            data = [CoreDataJSONHelper jsonStructureFromManagedObjects:arrayToSerialize];
        }];

        if (existingRemoteFile) {
            // Do nothing if remote file is newer than local
            __block NSDate *localTime;
            [self.managedObjectContext performBlockAndWait:^{
                localTime = [TBScopeData dateFromString:self.dateModified];
            }];
            NSDate *remoteTime = existingRemoteFile.modifiedDate.date;
            if ([remoteTime timeIntervalSinceDate:localTime] > 0) {
                return [PMKPromise noopPromise];
            }

            // Do nothing if remote md5 matches local md5
            NSString *localMd5 = [data MD5];
            if ([localMd5 isEqualToString:[existingRemoteFile md5Checksum]]) {
                return [PMKPromise noopPromise];
            }
        }

        // Continue uploading
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            [self.managedObjectContext performBlock:^{
                // Build file
                GTLDriveFile *newRemoteFile = [GTLDriveFile object];
                newRemoteFile.title = [NSString stringWithFormat:@"%@ - %@.json",
                                       [self cellscopeID],
                                       [self examID]
                                       ];
                newRemoteFile.descriptionProperty = @"Uploaded from CellScope";
                newRemoteFile.mimeType = @"application/json";
                newRemoteFile.modifiedDate = [GTLDateTime dateTimeWithRFC3339String:[self dateModified]];

                // Upload file
                [gds uploadFile:newRemoteFile withData:data]
                    .then(^(GTLDriveFile *file) { resolve(file); })
                    .catch(^(NSError *error) { resolve(error); });
            }];
        }];
    });
}

+ (PMKPromise *)downloadFromGoogleDrive:(NSString *)googleDriveFileId
                   managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                     googleDriveService:(GoogleDriveService *)gds
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        if (!googleDriveFileId) {
            resolve(nil);
            return;
        }

        GTLDriveFile *remoteFile = [[GTLDriveFile alloc] init];
        remoteFile.identifier = googleDriveFileId;
        [gds getFile:remoteFile]
            .then(^(NSData *data) { resolve(data); })
            .catch(^(NSError *error) { resolve(error); });
    }].then(^(NSData *data) {
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            if (!data) {
                resolve(nil);
                return;
            }

            // Parse data into an exam
            NSError *error;
            NSArray *exams = [CoreDataJSONHelper managedObjectsFromJSONStructure:data
                                                        withManagedObjectContext:managedObjectContext
                                                                           error:&error];
            if (error) {
                resolve(error);
            } else if (exams.count <= 0) {
                NSError *error = [[NSError alloc] initWithDomain:@"No exams returned" code:1 userInfo:nil];
                resolve(error);
            } else {
                Exams *remoteExam = exams[0];
                resolve(remoteExam);
            }
        }];
    }).then(^(Exams *exam) {
        return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
            if (!exam) {
                resolve(nil);
                return;
            }

            // Delete local exams matching googleDriveFileId
            [managedObjectContext performBlock:^{
                // Load a copy of the exam belonging to this thread
                Exams *localExam = [managedObjectContext objectWithID:exam.objectID];

                // Figure out which exams we want to delete
                NSPredicate *pred = [NSPredicate predicateWithFormat:@"(googleDriveFileID == %@)", localExam.googleDriveFileID];
                NSArray *examResults = [CoreDataHelper searchObjectsForEntity:@"Exams"
                                                                withPredicate:pred
                                                                   andSortKey:nil
                                                             andSortAscending:YES
                                                                   andContext:managedObjectContext];
                NSMutableArray *examsToDelete = [[NSMutableArray alloc] init];
                for (Exams *possibleDuplicateExam in examResults) {
                    if (possibleDuplicateExam.objectID != localExam.objectID) {
                        [examsToDelete addObject:possibleDuplicateExam];
                    }
                }

                // Delete the exams
                while (examsToDelete.count > 0) {
                    Exams *examToDelete = examsToDelete[0];
                    [examsToDelete removeObjectAtIndex:0];
                    [managedObjectContext deleteObject:[managedObjectContext objectWithID:examToDelete.objectID]];
                }
                resolve(localExam);
            }];
        }];
    });
}

@end
