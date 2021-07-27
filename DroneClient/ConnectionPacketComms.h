//
//  ConnectionPacketComms.h
//  DroneClient
//
//  Created by EE User on 7/24/21.
//

#ifndef ConnectionPacketComms_h
#define ConnectionPacketComms_h


#import <UIKit/UIKit.h>
#import <DJISDK/DJISDK.h>
#import <DJIWidget/DJIVideoPreviewer.h>
//#import "VideoPreviewerSDKAdapter.h"

@interface ConnectionPacketComms : NSObject {
    
}


+ (void) sendPacket_CoreTelemetryThread:(struct coreTelemetrySkeleton) coreTelemetry  toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream;

+ (void) sendPacket_ExtendedTelemetryThread:(struct extendedTelemetrySkeleton) extendedTelemetry  toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream;

+ (void) sendPacket_MessageStringThread:(NSString*)msg ofType:(UInt8)type toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream;

+ (void) sendPacket_AcknowledgmentThread:(BOOL) positive withPID:(UInt8)source_pid toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream;
@end

#endif /* ConnectionPacketComms_h */

