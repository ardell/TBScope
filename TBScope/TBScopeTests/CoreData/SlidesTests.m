//
//  SlidesTests.m
//  TBScope
//
//  Created by Jason Ardell on 11/12/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "Slides.h"
#import "TBScopeData.h"
#import "GoogleDriveService.h"
#import "CoreDataJSONHelper.h"
#import "TBScopeImageAsset.h"
#import "NSData+MD5.h"
#import "PMKPromise+NoopPromise.h"
#import "PMKPromise+RejectedPromise.h"

@interface SlidesTests : XCTestCase
@property (strong, nonatomic) Slides *slide;
@property (strong, nonatomic) NSManagedObjectContext *moc;
@end

@implementation SlidesTests

- (void)setUp
{
    [super setUp];
    
    // Set up the managedObjectContext
    self.moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    self.moc.parentContext = [[TBScopeData sharedData] managedObjectContext];
    
    [self.moc performBlockAndWait:^{
        // Create a slide
        self.slide = (Slides*)[NSEntityDescription insertNewObjectForEntityForName:@"Slides" inManagedObjectContext:self.moc];
        self.slide.exam = (Exams*)[NSEntityDescription insertNewObjectForEntityForName:@"Exams" inManagedObjectContext:self.moc];

        // Inject GoogleDriveService
        GoogleDriveService *mockGds = OCMPartialMock([[GoogleDriveService alloc] init]);
        self.slide.googleDriveService = mockGds;
    }];
}

- (void)tearDown
{
    self.moc = nil;
}

- (void)setSlideRoiSpritePath
{
    [self.moc performBlockAndWait:^{
        self.slide.roiSpritePath = @"test-file-id";
    }];
}

- (void)setSlideRoiSpriteGoogleDriveFileID
{
    [self.moc performBlockAndWait:^{
        self.slide.roiSpriteGoogleDriveFileID = @"test-file-id";
    }];
}

- (void)stubOutRemoteFileTime:(NSString *)remoteTime md5:(NSString *)md5
{
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *remoteFile = [[GTLDriveFile alloc] init];
        
        // Stub out remote file time to newer than local modification time
        remoteFile.modifiedDate = [GTLDateTime dateTimeWithRFC3339String:remoteTime];
        
        // Stub out remote md5 to be different from local
        remoteFile.md5Checksum = md5;
        
        resolve(remoteFile);
    }];
    OCMStub([self.slide.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn(promise);
}

- (void)stubOutGetImageAtPath
{
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSString *imageName = @"fl_01_01";
        NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:imageName ofType:@"jpg"];
        UIImage *image = [UIImage imageWithContentsOfFile:filePath];
        resolve(image);
    }];
    [[[mock stub] andReturn:promise] getImageAtPath:[OCMArg any]];
}

#pragma uploadToGoogleDrive tests

- (void)testThatUploadRoiSpriteSheetToGoogleDriveDoesNotUploadIfPathIsNil
{
    [self.moc performBlockAndWait:^{
        self.slide.roiSpritePath = nil;
    }];

    // Stub out [GoogleDriveService uploadFile:withData:] to fail
    OCMStub([self.slide.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Did not expect uploadFile:withData: to be called");
        });

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Call uploadToGoogleDrive
    [self.slide uploadRoiSpriteSheetToGoogleDrive]
        .then(^(GTLDriveFile *file) { [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadRoiSpriteSheetToGoogleDriveDoesNotUploadIfGetMetadataForFileIdReturnsNil
{
    [self setSlideRoiSpritePath];

    // Stub out getMetadataForFileId to return nil
    OCMStub([self.slide.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn([PMKPromise noopPromise]);

    // Stub out remote file time to be newer
    NSString *md5 = @"abc123";
    [self stubOutRemoteFileTime:@"2014-11-10T12:00:00.00Z" md5:md5];
    [self.moc performBlockAndWait:^{
        self.slide.exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Stub out [TBScopeImageAsset getImageAtPath:] to succeed
    [self stubOutGetImageAtPath];

    // Stub out [GoogleDriveService uploadFile:withData:] to fail
    OCMStub([self.slide.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Did not expect uploadFile:withData: to be called");
        });

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Call uploadToGoogleDrive
    [self.slide uploadRoiSpriteSheetToGoogleDrive]
        .then(^(GTLDriveFile *file) { [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadRoiSpriteSheetToGoogleDriveDoesNotUploadIfRemoteFileIsNewerThanLocalFile
{
    [self setSlideRoiSpritePath];
    [self.moc performBlockAndWait:^{
        self.slide.exam.dateModified = @"2014-11-10T12:00:00.00Z";
    }];

    // Stub out remote file time to be newer
    NSString *md5 = @"abc123";
    [self stubOutRemoteFileTime:@"2015-11-10T12:00:00.00Z" md5:md5];

    // Stub out [TBScopeImageAsset getImageAtPath:] to succeed
    [self stubOutGetImageAtPath];

    // Stub out [GoogleDriveService uploadFile:withData:] to fail
    OCMStub([self.slide.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Did not expect uploadFile:withData: to be called");
        });

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Call uploadToGoogleDrive
    [self.slide uploadRoiSpriteSheetToGoogleDrive]
        .then(^(GTLDriveFile *file) { [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadRoiSpriteSheetToGoogleDriveDoesNotUploadIfRemoteFileHasSameMd5AsLocalFile
{
    [self setSlideRoiSpritePath];

    // Stub out local metadata
    [self.moc performBlockAndWait:^{
        self.slide.exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];
    
    // Stub out [TBScopeImageAsset getImageAtPath:] to succeed
    [self stubOutGetImageAtPath];

    // Stub out [GoogleDriveService uploadFile:withData:] to fail
    OCMStub([self.slide.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Did not expect uploadFile:withData: to be called");
        });

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Get local image at path
    [TBScopeImageAsset getImageAtPath:@"some-path"]
        .then(^(UIImage *image) {
            // Calculate md5 of local file
            NSData *localData = UIImageJPEGRepresentation((UIImage *)image, 1.0);
            NSString *localMd5 = [localData MD5];

            // Stub remote metadata
            [self stubOutRemoteFileTime:@"2014-11-10T12:00:00.00Z" md5:localMd5];

            // Call uploadToGoogleDrive
            [self.slide uploadRoiSpriteSheetToGoogleDrive]
                .then(^(GTLDriveFile *file) { [expectation fulfill]; })
                .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });
        });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveUploadsROISpriteSheet
{
    [self setSlideRoiSpritePath];
    [self.moc performBlockAndWait:^{
        self.slide.exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Stub out remote file time to be newer
    NSString *md5 = @"abc123";
    [self stubOutRemoteFileTime:@"2014-11-10T12:00:00.00Z" md5:md5];

    // Stub out [TBScopeImageAsset getImageAtPath:] to succeed
    [self stubOutGetImageAtPath];

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Stub out [GoogleDriveService uploadFile:withData:] to fail
    OCMStub([self.slide.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn([PMKPromise noopPromise]);

    // Call uploadToGoogleDrive
    [self.slide uploadRoiSpriteSheetToGoogleDrive]
        .then(^(GTLDriveFile *file) { [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveRejectsPromiseIfROISpriteSheetUploadFails
{
    [self setSlideRoiSpritePath];
    [self.moc performBlockAndWait:^{
        self.slide.exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Stub out remote file time to be newer
    NSString *md5 = @"abc123";
    [self stubOutRemoteFileTime:@"2014-11-10T12:00:00.00Z" md5:md5];

    // Stub out [TBScopeImageAsset getImageAtPath:] to succeed
    [self stubOutGetImageAtPath];

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Stub out [GoogleDriveService uploadFile:withData:] to fail
    OCMStub([self.slide.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn([PMKPromise rejectedPromise]);

    // Call uploadToGoogleDrive
    [self.slide uploadRoiSpriteSheetToGoogleDrive]
        .then(^(NSError *error) { XCTFail(@"Expected promise to reject"); })
        .catch(^(GTLDriveFile *file) { [expectation fulfill]; });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveUpdatesROISpriteSheetGoogleDriveIdAfterUploading
{
    [self setSlideRoiSpritePath];
    [self.moc performBlockAndWait:^{
        self.slide.exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Stub out remote file time to be newer
    NSString *md5 = @"abc123";
    [self stubOutRemoteFileTime:@"2014-11-10T12:00:00.00Z" md5:md5];

    // Stub out [TBScopeImageAsset getImageAtPath:] to succeed
    [self stubOutGetImageAtPath];

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Stub out [GoogleDriveService uploadFile:withData:] to fail
    NSString *remoteFileId = @"some-file-id";
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [[GTLDriveFile alloc] init];
        file.identifier = remoteFileId;
        resolve(file);
    }];
    OCMStub([self.slide.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn(promise);

    // Call uploadToGoogleDrive
    [self.slide uploadRoiSpriteSheetToGoogleDrive]
        .then(^{
            [self.moc performBlock:^{
                NSString *localFileId = self.slide.roiSpriteGoogleDriveFileID;
                XCTAssert([localFileId isEqualToString:remoteFileId]);
                [expectation fulfill];
            }];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

#pragma downloadFromGoogleDrive tests

- (void)testThatDownloadFromGoogleDriveDoesNotDownloadIfRoiSpriteGoogleDriveIdIsNil
{
    [self.moc performBlockAndWait:^{
        self.slide.roiSpriteGoogleDriveFileID = nil;
    }];
    
    // Stub out [GoogleDriveService getFile:] to fail
    OCMStub([self.slide.googleDriveService getFile:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Did not expect downloadFileWithId to be called");
        });

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Call download
    [self.slide downloadRoiSpriteSheetFromGoogleDrive]
        .then(^{ [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveDoesNotDownloadIfGetMetadataForFileIdReturnsNil
{
    // Stub out [googleDriveService getMetadataForFileId] to return nil
    OCMStub([self.slide.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn([PMKPromise noopPromise]);

    // Fail if getFile is called
    OCMStub([self.slide.googleDriveService getFile:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Did not expect [googleDriveService getFile] to be called.");
        });

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    [self.slide downloadRoiSpriteSheetFromGoogleDrive]
        .then(^{ [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveDoesNotDownloadIfLocalFileIsNewerThanRemoteFile
{
    // Stub out file times and md5s
    NSString *md5 = @"abc123";
    [self stubOutRemoteFileTime:@"2014-11-10T12:00:00.00Z" md5:md5];
    [self.moc performBlockAndWait:^{
        self.slide.exam.dateModified = @"2015-11-10T12:00:00.00Z";
    }];

    // Fail if getFile is called
    OCMStub([self.slide.googleDriveService getFile:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Did not expect [googleDriveService getFile] to be called.");
        });

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    [self.slide downloadRoiSpriteSheetFromGoogleDrive]
        .then(^{ [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveFetchesSpriteSheetFromServer
{
    [self setSlideRoiSpriteGoogleDriveFileID];

    // Stub out getMetadataForFile to return a file
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [[GTLDriveFile alloc] init];
        resolve(file);
    }];
    OCMStub([self.slide.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn(promise);

    // Stub out getFile to return NSData
    PMKPromise *getFilePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSData *data = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
        resolve(data);
    }];
    OCMStub([self.slide.googleDriveService getFile:[OCMArg any]])
        .andReturn(getFilePromise);

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Call download
    [self.slide downloadRoiSpriteSheetFromGoogleDrive]
        .then(^(GTLDriveFile *file) {
            OCMVerify([self.slide.googleDriveService getFile:[OCMArg any]]);
            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveSavesFileToAssetLibrary
{
    [self setSlideRoiSpriteGoogleDriveFileID];

    // Stub out getMetadataForFile to return a file
    PMKPromise *getMetadataPromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [[GTLDriveFile alloc] init];
        resolve(file);
    }];
    OCMStub([self.slide.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn(getMetadataPromise);

    // Stub out getFile to return NSData
    PMKPromise *getFilePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSData *data = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
        resolve(data);
    }];
    OCMStub([self.slide.googleDriveService getFile:[OCMArg any]])
        .andReturn(getFilePromise);

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Stub out saveImage
    id saveImageMock = [OCMockObject mockForClass:[TBScopeImageAsset class]];

    // Call download
    [self.slide downloadRoiSpriteSheetFromGoogleDrive]
        .then(^{
            OCMVerify([saveImageMock saveImage:[OCMArg any]]);
            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveUpdatesRoiSpriteSheetPathAfterDownloading
{
    [self setSlideRoiSpriteGoogleDriveFileID];

    // Stub out getMetadataForFile to return a file
    PMKPromise *getMetadataPromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [[GTLDriveFile alloc] init];
        resolve(file);
    }];
    OCMStub([self.slide.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn(getMetadataPromise);

    // Stub out getFile to return NSData
    PMKPromise *getFilePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSString *imageName = @"fl_01_01";
        NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:imageName ofType:@"jpg"];
        UIImage *image = [UIImage imageWithContentsOfFile:filePath];
        NSData *data = UIImageJPEGRepresentation(image, 1.0);
        resolve(data);
    }];
    OCMStub([self.slide.googleDriveService getFile:[OCMArg any]])
        .andReturn(getFilePromise);

    // Stub out [TBScopeImageAsset saveImage:] to return a given path
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    NSString *path = @"asset-library://path/to/image.jpg";
    PMKPromise *saveImagePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        resolve(path);
    }];
    [[[mock stub] andReturn:saveImagePromise] saveImage:[OCMArg any]];

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Call download
    [self.slide downloadRoiSpriteSheetFromGoogleDrive]
        .then(^(GTLDriveFile *file) {
            [self.moc performBlock:^{
                // Verify that slide.roiSpritePath was set
                XCTAssert([self.slide.roiSpritePath isEqualToString:path]);
                [expectation fulfill];
            }];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveReplacesExistingROISpriteSheetWithNewerOneFromServer
{
    // Set up existing local file
    [self setSlideRoiSpritePath];

    // Set up existing remote file
    [self setSlideRoiSpriteGoogleDriveFileID];
    [self stubOutRemoteFileTime:@"2014-11-10T12:00:00.00Z" md5:@"abc123"];

    // Stub out getFile to return NSData
    PMKPromise *getFilePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSString *imageName = @"fl_01_01";
        NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:imageName ofType:@"jpg"];
        UIImage *image = [UIImage imageWithContentsOfFile:filePath];
        NSData *data = UIImageJPEGRepresentation(image, 1.0);
        resolve(data);
    }];
    OCMStub([self.slide.googleDriveService getFile:[OCMArg any]])
        .andReturn(getFilePromise);

    // Stub out [TBScopeImageAsset saveImage:] to return a given path
    NSString *path = @"asset-library://path/to/image.jpg";
    PMKPromise *saveImagePromise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        resolve(path);
    }];
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    [[[mock stub] andReturn:saveImagePromise] saveImage:[OCMArg any]];

    // Set up expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Call download
    [self.slide downloadRoiSpriteSheetFromGoogleDrive]
        .then(^(GTLDriveFile *file) {
            [self.moc performBlock:^{
                // Verify that slide.roiSpritePath was set
                XCTAssert([self.slide.roiSpritePath isEqualToString:path]);
                [expectation fulfill];
            }];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

@end
