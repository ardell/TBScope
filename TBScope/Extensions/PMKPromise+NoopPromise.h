//
//  PMKPromise+NoopPromise.h
//  TBScope
//
//  Created by Jason Ardell on 11/5/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <PromiseKit/Promise.h>

@interface PMKPromise(NoopPromise)

+ (PMKPromise *)noopPromise;

@end
