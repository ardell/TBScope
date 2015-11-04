//
//  UIImage+Crop.m
//  TBScope
//
//  Created by Jason Ardell on 11/2/15.
//  Copyright © 2015 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "UIImage+Crop.h"

@implementation UIImage (Crop)

// From: http://stackoverflow.com/questions/158914/cropping-an-uiimage
- (UIImage *)crop:(CGRect)rect {
    rect = CGRectMake(rect.origin.x*self.scale,
                      rect.origin.y*self.scale,
                      rect.size.width*self.scale,
                      rect.size.height*self.scale);

    CGImageRef imageRef = CGImageCreateWithImageInRect([self CGImage], rect);
    UIImage *result = [UIImage imageWithCGImage:imageRef
                                          scale:self.scale
                                    orientation:self.imageOrientation];
    CGImageRelease(imageRef);
    return result;
}

@end
