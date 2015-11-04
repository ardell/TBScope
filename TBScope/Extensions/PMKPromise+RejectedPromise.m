//
//  PMKPromise+RejectedPromise.m
//  TBScope
//
//  Created by Jason Ardell on 11/10/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "PMKPromise+RejectedPromise.h"

@implementation PMKPromise(RejectedPromise)

+ (PMKPromise *)rejectedPromise
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        NSError *error = [NSError errorWithDomain:@"PMKPromise+RejectedPromise" code:1 userInfo:nil];
        resolve(error);
    }];
}

@end
