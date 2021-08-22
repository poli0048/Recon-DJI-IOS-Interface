//
//  ImageProcessor.m
//  DroneClient
//
//  Created by EE User on 8/19/21.
//

#import <Foundation/Foundation.h>
#import "ImageProcessor.h"
#import "ConnectionController.h"
#import "ConnectionPacketComms.h"
#import "ImageUtils.h"



@implementation ImageProcessor : NSObject

+ (void) showCurrentFrameImage:(CVPixelBufferRef*) currentPixelBuffer toQueue:(dispatch_queue_t) imageQueue toView:(UIView*) fpvPreviewView {
    CVPixelBufferRef pixelBuffer;
    if (currentPixelBuffer) {
        pixelBuffer = *currentPixelBuffer;
        dispatch_async(imageQueue, ^{
            UIImage* image = [ImageUtils imageFromPixelBuffer:pixelBuffer];
            if (image) {
                
                UIImageView* imgView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, image.size.width / 4, image.size.height / 4)];
                imgView.image = image;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [fpvPreviewView addSubview:imgView];

                   // do work here to Usually to update the User Interface
                });
                
            }
        });
        

    }
}
@end
