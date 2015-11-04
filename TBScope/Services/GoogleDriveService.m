//
//  GoogleDriveService.m
//  TBScope
//
//  Created by Jason Ardell on 11/5/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "GoogleDriveService.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "NSData+MD5.h"
#import "PMKPromise+NoopPromise.h"

static NSString *const kKeychainItemName = @"CellScope";
static NSString *const kClientID = @"822665295778.apps.googleusercontent.com";
static NSString *const kClientSecret = @"mbDjzu2hKDW23QpNJXe_0Ukd";

@implementation GoogleDriveService

@synthesize googleDriveTimeout;

#pragma Initializers

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Initialize the drive service & load existing credentials from the keychain if available
        self.driveService = [[GTLServiceDrive alloc] init];
        self.driveService.authorizer = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:kKeychainItemName
                                                                                             clientID:kClientID
                                                                                         clientSecret:kClientSecret];
        self.driveService.shouldFetchNextPages = YES;
        self.googleDriveTimeout = 5.0;
    }
    return self;
}

#pragma Status methods

- (BOOL)isLoggedIn
{
    return [self.driveService.authorizer canAuthorize];
}

- (NSString*)userEmail
{
    return [self.driveService.authorizer userEmail];
}

#pragma Queries

- (PMKPromise *)getMetadataForFileId:(NSString *)fileId
{
    GTLQueryDrive *query = [GTLQueryDrive queryForFilesGetWithFileId:fileId];
    return [self executeQueryWithTimeout:query];
}

- (PMKPromise *)fileExists:(GTLDriveFile *)file
{
    NSString *fileId = [file identifier];
    return [self getMetadataForFileId:fileId];
}

- (PMKPromise *)getFile:(GTLDriveFile *)file
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        GTMHTTPFetcher *fetcher = [GTMHTTPFetcher fetcherWithURLString:file.downloadUrl];
        
        // For downloads requiring authorization, set the authorizer.
        fetcher.authorizer = self.driveService.authorizer;

        // TODO: check what happens w/o network
        [fetcher beginFetchWithCompletionHandler:^(NSData *data, NSError *error) {
            if (error) {
                resolve(error);
            } else {
                resolve(data);
            }
        }];
    }];
}

- (PMKPromise *)uploadFile:(GTLDriveFile *)file withData:(NSData *)data
{
    // Check whether file exists
    return [self fileExists:file].then(^(GTLDriveFile *existingFile) {
        // Create query
        GTLUploadParameters *uploadParameters = [GTLUploadParameters uploadParametersWithData:data MIMEType:file.mimeType];
        GTLQueryDrive* query;
        if (existingFile) {
            // Check whether file has been modified
            NSString *localMD5 = [data MD5];
            NSString *remoteMD5 = [existingFile md5Checksum];
            if (localMD5 == remoteMD5) {
                // Files have same contents, do not upload
            } else {
                // Files are different, upload
                query = [GTLQueryDrive queryForFilesUpdateWithObject:file
                                                              fileId:[file identifier]
                                                    uploadParameters:uploadParameters];
            }
        } else {
            // File does not exist on remote server, upload
            query = [GTLQueryDrive queryForFilesInsertWithObject:file
                                                uploadParameters:uploadParameters];
        }

        // Return a no-op promise if we don't have any work to do
        if (!query) return [PMKPromise noopPromise];
        query.setModifiedDate = YES;

        // Execute query
        return [self executeQueryWithTimeout:query];
    });
}

- (PMKPromise *)deleteFileWithId:(NSString *)fileId
{
    return [self getMetadataForFileId:fileId].then(^(GTLDriveFile *existingFile) {
        if (!existingFile) return [PMKPromise noopPromise];

        // Delete the file
        GTLQueryDrive* query = [GTLQueryDrive queryForFilesTrashWithFileId:fileId];
        return [self executeQueryWithTimeout:query];
    });
}

- (PMKPromise *)executeQueryWithTimeout:(GTLQuery *)query
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_main_queue(), ^{
            GTLServiceTicket* ticket = [self.driveService executeQuery:query
                                                     completionHandler:^(GTLServiceTicket *ticket, id object, NSError *error) {
                                                         if (error) {
                                                             resolve(error);
                                                         } else {
                                                             resolve(object);
                                                         }
                                                     }];

            //since google drive API doesn't call completion or error handler when network connection drops (arg!),
            //set this timer to check the query ticket and make sure it returned something. if not, cancel the query
            //and return an error
            //TODO: roll this into my own executeQuery function and make it universal
            //TODO: check what happens if we are uploading a big file (hopefully returns a diff status code)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.googleDriveTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                //NSLog(@"google returned status code: %ld",(long)ticket.statusCode);
                if (ticket.statusCode==0) { //might also handle other error codes? code of 0 means that it didn't even attempt I guess? the other HTTP codes should get handled in the errorhandler above
                    [ticket cancelTicket];
                    NSError* error = [NSError errorWithDomain:@"GoogleDriveSync" code:123 userInfo:[NSDictionary dictionaryWithObject:@"No response from query. Likely network failure." forKey:@"description"]];
                    resolve(error);
                }
            });
        });
    }];
}

@end
