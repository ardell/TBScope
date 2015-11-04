//
//  UIImage+Crop.h
//  TBScope
//
//  Created by Jason Ardell on 11/2/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface UIImage (Crop)
- (UIImage *)crop:(CGRect)rect;
@end
