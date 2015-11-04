//
//  PMKPromise+NoopPromise.m
//  TBScope
//
//  Created by Jason Ardell on 11/5/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "PMKPromise+NoopPromise.h"

@implementation PMKPromise(NoopPromise)

+ (PMKPromise *)noopPromise
{
    return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
        // Nothing to do!
        resolve(nil);
    }];
}

@end
