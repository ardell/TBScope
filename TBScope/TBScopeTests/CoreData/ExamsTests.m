//
//  ExamsTests.m
//  TBScope
//
//  Created by Jason Ardell on 11/10/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "Exams.h"
#import "TBScopeData.h"
#import "GoogleDriveService.h"
#import "CoreDataJSONHelper.h"
#import "NSData+MD5.h"
#import "PMKPromise+NoopPromise.h"
#import "PMKPromise+RejectedPromise.h"
#import "TBScopeImageAsset.h"

@interface ExamsTests : XCTestCase
@end

@implementation ExamsTests

- (NSManagedObjectContext *)getManagedObjectContext
{
    __block NSManagedObjectContext *moc;
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        moc.parentContext = [[TBScopeData sharedData] managedObjectContext];
    });
    return moc;
}

- (Exams *)getExam:(NSManagedObjectContext *)moc
{
    __block Exams *exam;
    [moc performBlockAndWait:^{
        exam = (Exams*)[NSEntityDescription insertNewObjectForEntityForName:@"Exams"
                                                     inManagedObjectContext:moc];
    }];
    return exam;
}

- (GoogleDriveService *)getGoogleDriveService
{
    return [[GoogleDriveService alloc] init];
}

- (void)stubOutGoogleDriveService:(GoogleDriveService *)gds
               withRemoteFileTime:(NSString *)remoteTime
                              md5:(NSString *)md5
{
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *remoteFile = [[GTLDriveFile alloc] init];

        // Stub out remote file time to newer than local modification time
        remoteFile.modifiedDate = [GTLDateTime dateTimeWithRFC3339String:remoteTime];

        // Stub out remote md5 to be different from local
        remoteFile.md5Checksum = md5;

        resolve(remoteFile);
    }];
    OCMStub([gds getMetadataForFileId:[OCMArg any]])
        .andReturn(promise);
}

- (void)stubOutGetFileToReturnData:(GoogleDriveService *)gds
{
    PMKPromise *getFilePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        resolve([@"{ \"test\": \"json\" }" dataUsingEncoding:NSUTF8StringEncoding]);
    }];
    OCMStub([gds getFile:[OCMArg any]])
        .andReturn(getFilePromise);
}

#pragma uploadToGoogleDrive tests

- (void)testThatUploadToGoogleDriveUploadsIfNoRemoteFileExists
{
    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    NSManagedObjectContext *moc = [self getManagedObjectContext];
    Exams *exam = [self getExam:moc];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);

    [moc performBlockAndWait:^{
        // Set local exam to NOT have a remote file
        exam.googleDriveFileID = nil;
    }];

    // Stub out [googleDriveService uploadFile:withData:]
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [[GTLDriveFile alloc] init];
        file.identifier = @"google-drive-file-id";
        resolve(file);
    }];
    OCMStub([gds uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn(promise);

    // Call uploadToGoogleDrive
    [exam uploadToGoogleDrive:gds]
        .then(^{
            OCMVerify([gds uploadFile:[OCMArg any] withData:[OCMArg any]]);
            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveDoesNotUploadIfRemoteFileIsNewerThanLocalModificationDate
{
    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    Exams *exam = [self getExam:moc];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);

    [moc performBlockAndWait:^{
        exam.googleDriveFileID = @"test-file-id";

        // Set local modification date to older than remote time
        exam.dateModified = @"2014-11-10T12:00:00.00Z";
    }];

    // Stub out remote file time to newer than local modification time
    [self stubOutGoogleDriveService:gds
                 withRemoteFileTime:@"2015-11-10T12:00:00.00Z"
                                md5:@"abc123"];

    // Stub out [googleDriveService uploadFile:withData:] to fail test
    OCMStub([gds uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Expected uploadFile:withData: not to be called");
        });

    // Call uploadToGoogleDrive
    [exam uploadToGoogleDrive:gds]
        .then(^{ [expectation fulfill]; })
        .catch(^{ XCTFail(@"Expected promise to be fulfilled"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveDoesNotUploadIfRemoteFileHasSameMd5SignatureAsLocalFile
{
    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    Exams *exam = [self getExam:moc];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    [moc performBlockAndWait:^{
        exam.googleDriveFileID = @"test-file-id";

        // Set local modification date to newer than remote time
        exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Calculate md5 of local data
    NSArray *arrayToSerialize = [NSArray arrayWithObjects:exam, nil];
    __block NSData *data;
    [moc performBlockAndWait:^{
        data = [CoreDataJSONHelper jsonStructureFromManagedObjects:arrayToSerialize];
    }];
    NSString *md5 = [data MD5];

    // Stub out getMetadataForFileId
    [self stubOutGoogleDriveService:gds
                 withRemoteFileTime:@"2014-11-10T12:00:00.00Z"
                                md5:md5];

    // Stub out [googleDriveService uploadFile:withData:] to fail test
    OCMStub([gds uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Expected uploadFile:withData: not to be called");
        });

    // Call uploadToGoogleDrive
    [exam uploadToGoogleDrive:gds]
        .then(^{ [expectation fulfill]; })
        .catch(^{ XCTFail(@"Expected promise to be fulfilled"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveUploadsIfRemoteFileIsOlderThanLocalAndMd5sDoNotMatch
{
    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    Exams *exam = [self getExam:moc];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    [moc performBlockAndWait:^{
        exam.googleDriveFileID = @"test-file-id";
        exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Stub out getMetadataForFileId
    [self stubOutGoogleDriveService:gds
                 withRemoteFileTime:@"2014-11-10T12:00:00.00Z"
                                md5:@"abc123"];

    // Stub out [googleDriveService uploadFile:withData:] to fulfill expectation
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        resolve([[GTLDriveFile alloc] init]);
    }];
    OCMStub([gds uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn(promise);

    // Call uploadToGoogleDrive
    [exam uploadToGoogleDrive:gds]
        .then(^{
            OCMVerify([gds uploadFile:[OCMArg any] withData:[OCMArg any]]);
            [expectation fulfill];
        })
        .catch(^{ XCTFail(@"Expected promise to be fulfilled"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveRejectsPromiseIfUploadFails
{
    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    Exams *exam = [self getExam:moc];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    [moc performBlockAndWait:^{
        exam.googleDriveFileID = @"test-file-id";
        exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Stub out getMetadataForFileId
    [self stubOutGoogleDriveService:gds
                 withRemoteFileTime:@"2014-11-10T12:00:00.00Z"
                                md5:@"abc123"];

    // Stub out [googleDriveService uploadFile:withData:] to fulfill expectation
    OCMStub([gds uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn([PMKPromise rejectedPromise]);

    // Call uploadToGoogleDrive
    [exam uploadToGoogleDrive:gds]
        .then(^{ XCTFail(@"Expected promise to be rejected"); })
        .catch(^{ [expectation fulfill]; });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveUploadsROISpriteSheetForEachSlide
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    Exams *exam = [self getExam:moc];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);

    [moc performBlockAndWait:^{
        Slides *slide = (Slides *)[NSEntityDescription insertNewObjectForEntityForName:@"Slides"
                                                                inManagedObjectContext:moc];
        [exam addExamSlidesObject:slide];
    }];

    __block NSMutableArray *mocks = [[NSMutableArray alloc] init];
    __block NSMutableArray *promises = [[NSMutableArray alloc] init];
    [moc performBlockAndWait:^{
        // Set up slide mocks
        for (Slides *slide in exam.examSlides) {
            id mock = OCMPartialMock(slide);
            PMKPromise *promise = [PMKPromise noopPromise];
            [[[mock stub] andReturn:promise] uploadRoiSpriteSheetToGoogleDrive];
            [mocks addObject:mock];
            [promises addObject:promise];
        }
    }];

    // Stub out [googleDriveService uploadFile: withData:]
    PMKPromise *uploadFilePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [[GTLDriveFile alloc] init];
        file.identifier = @"google-drive-file-id";
        resolve(file);
    }];
    OCMStub([gds uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn(uploadFilePromise);

    // Call [exam uploadToGoogleDrive]
    [exam uploadToGoogleDrive:gds]
        .then(^{
            // Expect [slide uploadToGoogleDrive] to be called for each slide
            for (id mock in mocks) {
                OCMVerify([mock uploadRoiSpriteSheetToGoogleDrive]);
            }

            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveRejectsPromiseIfSlideRoiSpriteSheetUploadFails
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    Exams *exam = [self getExam:moc];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    [moc performBlockAndWait:^{
        Slides *slide = (Slides *)[NSEntityDescription insertNewObjectForEntityForName:@"Slides"
                                                                inManagedObjectContext:moc];
        [exam addExamSlidesObject:slide];
    }];
    
    // Set up slide upload to fail
    // NOTE: OCMock can't stub out core data relationships, so we stub out
    // TBScopeImageAsset getImageAtPath to fail
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    [[[mock stub] andReturn:[PMKPromise rejectedPromise]] getImageAtPath:[OCMArg any]];

    // Call [exam uploadToGoogleDrive]
    [exam uploadToGoogleDrive:gds]
        .then(^(NSError *error) { XCTFail(@"Expected promise to reject."); })
        .catch(^{
            [mock stopMocking];
            [expectation fulfill];
        });

    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

#pragma downloadFromGoogleDrive tests

- (void)testThatDownloadFromGoogleDriveDoesNotDownloadIfRemoteFileIdIsNil
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);

    // Stub out [googleDriveService getFile] to fail
    OCMStub([gds getFile:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Expected getFile NOT to be called.");
        });

    // Call downloadFromGoogleDrive
    [Exams downloadFromGoogleDrive:nil
              managedObjectContext:moc
                googleDriveService:gds]
        .then(^{ [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveResolvesToNilIfRemoteFileDoesNotExist
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    // Stub out [googleDriveService getFile] to resolve to nil
    PMKPromise *getFilePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        resolve(nil);
    }];
    OCMStub([gds getFile:[OCMArg any]])
        .andReturn(getFilePromise);

    // Call downloadFromGoogleDrive
    [Exams downloadFromGoogleDrive:@"test-file-id"
              managedObjectContext:moc
                googleDriveService:gds]
        .then(^(Exams *exam) {
            XCTAssertNil(exam);
            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDrivePromiseIsRejectedIfGetFileFails
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    // Stub out [googleDriveService getFile] to reject
    OCMStub([gds getFile:[OCMArg any]])
        .andReturn([PMKPromise rejectedPromise]);

    // Call downloadFromGoogleDrive
    [Exams downloadFromGoogleDrive:@"test-file-id"
              managedObjectContext:moc
                googleDriveService:gds]
        .then(^(Exams *exam) { XCTFail(@"Expected promise to reject."); })
        .catch(^(NSError *error) { [expectation fulfill]; });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveResolvesToAnExam
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    [self stubOutGetFileToReturnData:gds];

    // Stub out [CoreDataJSONHelper managedObjectsFromJSONStructure] to return the exams we expect
    __block NSString *newPatientName = @"Jane Doe";
    __block Exams *newExam;
    [moc performBlockAndWait:^{
        newExam = (Exams*)[NSEntityDescription insertNewObjectForEntityForName:@"Exams"
                                                        inManagedObjectContext:moc];
        newExam.patientName = newPatientName;
    }];
    id mock = [OCMockObject mockForClass:[CoreDataJSONHelper class]];
    [[[mock stub] andReturn:@[newExam]] managedObjectsFromJSONStructure:[OCMArg any]
                                               withManagedObjectContext:[OCMArg any]
                                                                  error:[OCMArg setTo:nil]];

    // Call downloadFromGoogleDrive
    [Exams downloadFromGoogleDrive:@"test-file-id"
              managedObjectContext:moc
                googleDriveService:gds]
        .then(^(Exams *exam) {
            [moc performBlock:^{
                XCTAssert([exam.patientName isEqualToString:newPatientName]);
                [mock stopMocking];
                [expectation fulfill];
            }];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveRejectsPromiseIfRemoteJSONCannotBeParsed
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    [self stubOutGetFileToReturnData:gds];

    // Stub out [CoreDataJSONHelper managedObjectsFromJSONStructure] to err
    NSError* someError = [[NSError alloc] initWithDomain:@"ExamsTests" code:1 userInfo:nil];
    id mock = [OCMockObject mockForClass:[CoreDataJSONHelper class]];
    [[[mock stub] andReturn:nil] managedObjectsFromJSONStructure:[OCMArg any]
                                        withManagedObjectContext:[OCMArg any]
                                                           error:[OCMArg setTo:someError]];

    // Call downloadFromGoogleDrive
    [Exams downloadFromGoogleDrive:@"test-file-id"
              managedObjectContext:moc
                googleDriveService:gds]
        .then(^(Exams *exam) { XCTFail(@"Expected promise to reject."); })
        .catch(^(NSError *error) {
            [mock stopMocking];
            [expectation fulfill];
        });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveRejectsPromiseIfRemoteJSONHasNoExams
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);
    
    [self stubOutGetFileToReturnData:gds];

    // Stub out [CoreDataJSONHelper managedObjectsFromJSONStructure] to return empty array
    id mock = [OCMockObject mockForClass:[CoreDataJSONHelper class]];
    [[[mock stub] andReturn:@[]] managedObjectsFromJSONStructure:[OCMArg any]
                                        withManagedObjectContext:[OCMArg any]
                                                           error:[OCMArg setTo:nil]];

    // Call downloadFromGoogleDrive
    [Exams downloadFromGoogleDrive:@"test-file-id"
              managedObjectContext:moc
                googleDriveService:gds]
        .then(^(Exams *exam) { XCTFail(@"Expected promise to reject."); })
        .catch(^(NSError *error) {
            [mock stopMocking];
            [expectation fulfill];
        });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveDeletesOldExamMatchingGoogleDriveFileId
{
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    NSManagedObjectContext *moc = [self getManagedObjectContext];
    GoogleDriveService *gds = OCMPartialMock([self getGoogleDriveService]);

    // Stub out [CoreDataJSONHelper managedObjectsFromJSONStructure] to return an exam
    __block id mock = [OCMockObject mockForClass:[CoreDataJSONHelper class]];

    [moc performBlockAndWait:^{
        // Set up exam
        Exams *exam = (Exams*)[NSEntityDescription insertNewObjectForEntityForName:@"Exams"
                                                            inManagedObjectContext:moc];
        exam.googleDriveFileID = @"test-exam-id";

        [self stubOutGetFileToReturnData:gds];

        // Stub out [CoreDataJSONHelper managedObjectsFromJSONStructure...]
        NSString *newPatientName = @"Jane Doe";
        Exams *newExam = (Exams*)[NSEntityDescription insertNewObjectForEntityForName:@"Exams"
                                                               inManagedObjectContext:moc];
        newExam.patientName = newPatientName;
        newExam.googleDriveFileID = exam.googleDriveFileID;
        [[[mock stub] andReturn:@[newExam]] managedObjectsFromJSONStructure:[OCMArg any]
                                                   withManagedObjectContext:[OCMArg any]
                                                                      error:[OCMArg setTo:nil]];

        // Assert that there are 2 new objects
        XCTAssertEqual([[moc insertedObjects] count], 2);

        // Call downloadFromGoogleDrive
        [Exams downloadFromGoogleDrive:exam.googleDriveFileID
                  managedObjectContext:moc
                    googleDriveService:gds]
            .then(^(Exams *exam) {
                [moc performBlock:^{
                    // After deletion there should only be one new object (exam)
                    XCTAssertEqual([[moc insertedObjects] count], 1);
                    [mock stopMocking];
                    [expectation fulfill];
                }];
            }).catch(^(NSError *error) {
                XCTFail(@"Expected promise to resolve.");
            });
    }];

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

@end
