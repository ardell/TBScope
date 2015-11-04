//
//  ImagesTests.m
//  TBScope
//
//  Created by Jason Ardell on 11/10/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "Images.h"
#import "TBScopeData.h"
#import "PMKPromise+NoopPromise.h"
#import "PMKPromise+RejectedPromise.h"
#import "TBScopeImageAsset.h"
#import "GoogleDriveService.h"

@interface ImagesTests : XCTestCase
@property (strong, nonatomic) Images *image;
@property (strong, nonatomic) NSManagedObjectContext *moc;
@end

@implementation ImagesTests

- (void)setUp
{
    [super setUp];

    // Set up the managedObjectContext
    self.moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    self.moc.parentContext = [[TBScopeData sharedData] managedObjectContext];

    [self.moc performBlockAndWait:^{
        // Set up our image
        self.image = (Images*)[NSEntityDescription insertNewObjectForEntityForName:@"Images" inManagedObjectContext:self.moc];
        
        // Inject GoogleDriveService into image
        GoogleDriveService *mockGds = OCMPartialMock([[GoogleDriveService alloc] init]);
        self.image.googleDriveService = mockGds;
    }];
}

- (void)tearDown
{
    self.moc = nil;
}

- (void)setImageGoogleDriveFileID
{
    [self.moc performBlockAndWait:^{
        self.image.googleDriveFileID = @"test-file-id";
    }];
}

- (void)setImagePath
{
    [self.moc performBlockAndWait:^{
        self.image.path = @"asset-url://path/to/image.jpg";
    }];
}

// Stub out [TBScopeImageAsset getImageAtPath:path] with a successfully
// resolved promise resolved to a UIImage instance
- (void)stubGetImageAtPathToResolve
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

// Stub out [TBScopeImageAsset getImageAtPath:path] with a rejected promise
- (void)stubGetImageAtPathToReject
{
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    [[[mock stub] andReturn:[PMKPromise rejectedPromise]] getImageAtPath:[OCMArg any]];
}

// Stub out [googleDriveService getMetadataForFileId:fileId] to return GTLDriveFile
- (void)stubGetMetadataForFileIdToSucceed
{
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [[GTLDriveFile alloc] init];
        resolve(file);
    }];
    OCMStub([self.image.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn(promise);
}

// Stub out [googleDriveService getFile:file] to return NSData
- (void)stubGetFileToSucceed
{
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSData *data = [@"Test Data" dataUsingEncoding:NSUTF8StringEncoding];
        resolve(data);
    }];
    OCMStub([self.image.googleDriveService getFile:[OCMArg any]])
        .andReturn(promise);
}

// Stub out [TBScopeImageAsset saveImage:image] to return rejected promise
- (void)stubSaveImageToReject
{
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    [[[mock stub] andReturn:[PMKPromise rejectedPromise]] saveImage:[OCMArg any]];
}

#pragma uploadToGoogleDrive tests

- (void)testThatUploadToGoogleDriveDoesNotAttemptUploadIfGoogleDriveFileIDIsAlreadySet
{
    [self setImageGoogleDriveFileID];

    // Stub out [TBScopeImageAsset getImageAtPath] to fail the test
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    [[[mock stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"Did not expect getImageAtPath to be called");
    }] getImageAtPath:[OCMArg any]];

    // Set up an expectation, fulfill on then
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    [self.image uploadToGoogleDrive]
        .then(^{ [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveRejectsPromiseIfGetImageAtPathFails
{
    [self stubGetImageAtPathToReject];

    // Set up an expectation, fulfill on catch
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    [self.image uploadToGoogleDrive]
        .then(^{ XCTFail(@"Expected uploadToGoogleDrive to return a rejected promise"); })
        .catch(^{ [expectation fulfill]; });
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveUploadsIfGoogleDriveFileIDIsNil
{
    [self.moc performBlockAndWait:^{
        self.image.googleDriveFileID = nil;
    }];

    // Stub out getImageAtPath
    [self stubGetImageAtPathToResolve];

    // Stub out [googleDriveService uploadFile:withData] to fulfill expectation
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSString *googleDriveFileID = @"test-file-id";
        GTLDriveFile *file = [GTLDriveFile object];
        file.identifier = googleDriveFileID;
        file.md5Checksum = @"abc123";
        resolve(file);
    }];
    OCMStub([self.image.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn(promise);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    [self.image uploadToGoogleDrive]
        .then(^{ [expectation fulfill]; })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatUploadToGoogleDriveUpdatesGoogleDriveFileId
{
    [self.moc performBlockAndWait:^{
        self.image.googleDriveFileID = nil;
    }];

    [self stubGetImageAtPathToResolve];

    // Stub out [googleDriveService uploadFile:withData] to return googleDriveFileId
    NSString *googleDriveFileID = @"test-file-id";
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTLDriveFile *file = [GTLDriveFile object];
        file.identifier = googleDriveFileID;
        file.md5Checksum = @"abc123";
        resolve(file);
    }];
    OCMStub([self.image.googleDriveService uploadFile:[OCMArg any] withData:[OCMArg any]])
        .andReturn(promise);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    [self.image uploadToGoogleDrive]
        .then(^{
            [self.moc performBlock:^{
                XCTAssert([self.image.googleDriveFileID isEqualToString:googleDriveFileID]);
                [expectation fulfill];
            }];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

#pragma downloadFromGoogleDrive tests

- (void)testThatDownloadFromGoogleDriveDoesNotDownloadIfGoogleDriveFileIDIsNil
{
    [self.moc performBlockAndWait:^{
        self.image.googleDriveFileID = nil;
    }];

    // Stub out [TBScopeImageAsset getImageAtPath:path] to fail if called
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    [[[mock stub] andDo:^(NSInvocation *invocation) {
        XCTFail(@"Expected [TBScopeImageAsset getImageAtPath:path] not to be called");
    }] getImageAtPath:[OCMArg any]];

    // Set up an expectation and wait for it
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    [self.image downloadFromGoogleDrive]
        .then(^{ [expectation fulfill]; })
        .catch(^{ XCTFail(@"Expected promise to resolve"); });
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveDownloadsImageIfPathIsNil
{
    [self setImageGoogleDriveFileID];
    [self.moc performBlockAndWait:^{
        self.image.path = nil;
    }];

    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Stub out [googleDriveService getFile:file] to fulfill the expectation
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSData *data = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
        resolve(data);
    }];
    OCMStub([self.image.googleDriveService getFile:[OCMArg any]])
        .andReturn(promise);

    // Call [image downloadFromGoogleDrive]
    [self.image downloadFromGoogleDrive]
        .then(^{
            OCMVerify([self.image.googleDriveService getFile:[OCMArg any]]);
            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveDownloadsIfNoFileIsFoundAtPath
{
    [self setImageGoogleDriveFileID];
    [self setImagePath];

    // Stub out [TBScopeImageAsset getImageAtPath:path] to reject
    [self stubGetImageAtPathToReject];

    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Stub out [googleDriveService getFile:file] to fulfill expectation
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSData *data = [@"Test Data" dataUsingEncoding:NSUTF8StringEncoding];
        resolve(data);
    }];
    OCMStub([self.image.googleDriveService getFile:[OCMArg any]])
        .andReturn(promise);

    // Call [image downloadFromGoogleDrive]
    [self.image downloadFromGoogleDrive]
        .then(^{
            OCMVerify([self.image.googleDriveService getFile:[OCMArg any]]);
            [expectation fulfill];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:901.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveDoesNotDownloadIfImageAlreadyExistsAtPath
{
    [self setImageGoogleDriveFileID];
    [self setImagePath];

    [self stubGetImageAtPathToResolve];
    [self stubGetMetadataForFileIdToSucceed];

    // Stub out [googleDriveService getFile:file] to fail if called
    OCMStub([self.image.googleDriveService getFile:[OCMArg any]])
        .andDo(^(NSInvocation *invocation) {
            XCTFail(@"Expected [googleDriveService getFile:file] not to be called");
        });

    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Call [image downloadFromGoogleDrive] and fulfill expectation on then
    [self.image downloadFromGoogleDrive]
        .then(^{ [expectation fulfill]; })
        .catch(^{ XCTFail(@"Expected promise to resolve"); });

    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveRejectsPromiseIfGetMetadataForFileIdFails
{
    [self setImageGoogleDriveFileID];

    // Stub out getMetadataForFileId to fail
    OCMStub([self.image.googleDriveService getMetadataForFileId:[OCMArg any]])
        .andReturn([PMKPromise rejectedPromise]);

    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Call [image downloadFromGoogleDrive] and fulfill expectation on then
    [self.image downloadFromGoogleDrive]
        .then(^{ XCTFail(@"Expected promise to reject"); })
        .catch(^{ [expectation fulfill]; });
    
    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveRejectsPromiseIfGetFileFails
{
    [self setImageGoogleDriveFileID];
    
    // Stub out getMetadataForFileId to succeed
    [self stubGetMetadataForFileIdToSucceed];

    // Stub out getFile to return a rejected promise
    OCMStub([self.image.googleDriveService getFile:[OCMArg any]])
        .andReturn([PMKPromise rejectedPromise]);

    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Call [image downloadFromGoogleDrive] and fulfill expectation on then
    [self.image downloadFromGoogleDrive]
        .then(^{ XCTFail(@"Expected promise to reject"); })
        .catch(^{ [expectation fulfill]; });
    
    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveRejectsPromiseIfSaveImageFails
{
    [self setImageGoogleDriveFileID];
    
    // Stub out methods to succeed
    [self stubGetMetadataForFileIdToSucceed];
    [self stubGetFileToSucceed];
    
    // Stub out [TBScopeImageAsset saveImage:image] to reject
    [self stubSaveImageToReject];
    
    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];
    
    // Call [image downloadFromGoogleDrive] and fulfill expectation on then
    [self.image downloadFromGoogleDrive]
        .then(^{ XCTFail(@"Expected promise to reject"); })
        .catch(^{ [expectation fulfill]; });
    
    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

- (void)testThatDownloadFromGoogleDriveUpdatesPathOnSuccess
{
    [self setImageGoogleDriveFileID];

    // Stub out stuff that happens earlier in the chain
    [self stubGetMetadataForFileIdToSucceed];
    [self stubGetFileToSucceed];

    // Stub out [TBScopeImageAsset saveImage:im] to return a given path
    NSString *path = @"asset-library://path/to/test/image.jpg";
    PMKPromise *promise = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        resolve(path);
    }];
    id mock = [OCMockObject mockForClass:[TBScopeImageAsset class]];
    [[[mock stub] andReturn:promise] saveImage:[OCMArg any]];

    // Set up an expectation
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for async call to finish"];

    // Call [image downloadFromGoogleDrive]
    [self.image downloadFromGoogleDrive]
        .then(^{
            [self.moc performBlock:^{
                XCTAssert([self.image.path isEqualToString:path]);
                [expectation fulfill];
            }];
        })
        .catch(^(NSError *error) { XCTFail(@"Expected promise to resolve."); });

    // Wait for expectation to be fulfilled
    [self waitForExpectationsWithTimeout:901.0 handler:^(NSError *error) {
        if (error) XCTFail(@"Async test timed out");
    }];
}

@end
