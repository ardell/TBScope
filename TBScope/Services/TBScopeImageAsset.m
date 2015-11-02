//
//  TBScopeImageAsset.m
//  TBScope
//
//  Created by Jason Ardell on 11/3/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "TBScopeImageAsset.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <UIKit/UIKit.h>
#import "TBScopeData.h"

@implementation TBScopeImageAsset

+ (PMKPromise *)getImageAtPath:(NSString *)assetsLibraryPath
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSURL *aURL = [NSURL URLWithString:assetsLibraryPath];
        if ([[aURL scheme] isEqualToString:@"assets-library"]) {
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library assetForURL:aURL resultBlock:^(ALAsset *asset) {
                NSError* err = nil;
                UIImage* image = nil;
                
                if (asset==nil) {
                    err = [NSError errorWithDomain:@"TBScopeData" code:1 userInfo:nil];
                    NSString *message = [NSString stringWithFormat:@"Image at path %@ was nil", assetsLibraryPath];
                    [TBScopeData CSLog:message inCategory:@"DATA"];
                } else {
                    //load the image
                    ALAssetRepresentation* rep = [asset defaultRepresentation];
                    CGImageRef iref = [rep fullResolutionImage];
                    image = [UIImage imageWithCGImage:iref];
                    
                    rep = nil;
                    iref = nil;
                }
                resolve(err ?: image);
            }
            failureBlock:^(NSError *error) {
                NSString *message = [NSString stringWithFormat:@"Error while loading image from path %@", assetsLibraryPath];
                [TBScopeData CSLog:message inCategory:@"DATA"];
                resolve(error);
            }];
        } else {
            // this is a file in the bundle (only necessary for demo images)
            UIImage* image = [UIImage imageNamed:assetsLibraryPath];
            resolve(image);
        }
    }];
}

+ (PMKPromise *)saveImage:(UIImage *)image
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        ALAssetOrientation orientation = [image imageOrientation];
        [library writeImageToSavedPhotosAlbum:image.CGImage
                                  orientation:orientation
                              completionBlock:^(NSURL *assetURL, NSError *error){
                                  if (error) {
                                      resolve(error);
                                  } else {
                                      resolve(assetURL);
                                  }
                              }];
    }];
}

@end
