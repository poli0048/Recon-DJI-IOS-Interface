//
//  ImageProcessor.h
//  DroneClient
//
//  Created by EE User on 8/19/21.
//

#ifndef ImageProcessor_h
#define ImageProcessor_h

#import <UIKit/UIKit.h>
#import <DJISDK/DJISDK.h>
#import <DJIWidget/DJIVideoPreviewer.h>
//#import "VideoPreviewerSDKAdapter.h"

@interface ImageProcessor : NSObject {
    
}

+ (void) videoProcessFrameInner:(VideoFrameYUV *)frame toFrame:(CVPixelBufferRef*) currentPixelBuffer writeQueue:writePacketQueue imageQueue:imageQueue toStream:outputStream;

+ (void) showCurrentFrameImage:(CVPixelBufferRef*) currentPixelBuffer toQueue:(dispatch_queue_t) imageQueue toView:(UIView*) fpvPreviewView;
@end
#endif /* ImageProcessor_h */
