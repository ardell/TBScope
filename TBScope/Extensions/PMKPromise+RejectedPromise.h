//
//  PMKPromise+RejectedPromise.h
//  TBScope
//
//  Created by Jason Ardell on 11/10/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <PromiseKit/Promise.h>

@interface PMKPromise(RejectedPromise)

+ (PMKPromise *)rejectedPromise;

@end
