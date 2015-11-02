//
//  TBScopeImageAsset.h
//  TBScope
//
//  Created by Jason Ardell on 11/3/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <PromiseKit/Promise.h>

@interface TBScopeImageAsset : NSObject

+ (PMKPromise *)getImageAtPath:(NSString *)assetsLibraryPath;
+ (PMKPromise *)saveImage:(UIImage *)image;

@end
