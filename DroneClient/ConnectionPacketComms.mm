//
//  ConnectionPacketComms.m
//  DroneClient
//
//  Created by EE User on 7/24/21.
//


#import "ConnectionPacketComms.h"
#import "ConnectionController.h"
#import "DJIUtils.h"
#import "Constants.h"
#import "DroneComms.hpp"
#import "ImageUtils.h"
#import "Image.hpp"
#import "Drone.hpp"
@implementation ConnectionPacketComms : NSObject 

struct CommsInterface {
    DroneInterface::Packet packet;
};
#pragma mark TCP Connection
+ (void) _sendPacket:(DroneInterface::Packet *)packet toStream:( NSOutputStream *)outputStream{
    NSData *data = [[NSData alloc] initWithBytesNoCopy:packet->m_data.data() length:packet->m_data.size() freeWhenDone:false];
    const unsigned char *bytes= (const unsigned char *)(data.bytes);
    
    unsigned int bytes_written = 0;

    while (bytes_written != packet->m_data.size()) {
        int remaining = (int)data.length - bytes_written;
        const unsigned char *bytesNew = bytes + bytes_written;
        // Tried to setup outputStream in new thread outside of main
        // Couldn't figure out how to call it from this function if this function exists outside connectioncontroller
        bytes_written += [outputStream write:bytesNew maxLength:remaining];
    }
    [NSThread sleepForTimeInterval: 0.001];
}

+ (void) sendPacket_CoreTelemetryThread:(struct coreTelemetrySkeleton) coreTelemetry  toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream{
     //WeakRef(target);
    dispatch_async(targetQueue, ^{
        //WeakReturn(target);
 
        DroneInterface::Packet_CoreTelemetry packet_core;
        DroneInterface::Packet packet;

        
        //if (self->_isFlying){
        if (TRUE){
            packet_core.IsFlying = coreTelemetry._isFlying;
            packet_core.Latitude = coreTelemetry._latitude;
            packet_core.Longitude = coreTelemetry._longitude;
            packet_core.Altitude = coreTelemetry._altitude;
            packet_core.HAG = coreTelemetry._HAG;
            packet_core.V_N = coreTelemetry._velocity_n;
            packet_core.V_N = coreTelemetry._velocity_e;
            packet_core.V_D = coreTelemetry._velocity_d;
            packet_core.Yaw = coreTelemetry._yaw;
            packet_core.Pitch = coreTelemetry._pitch;
            packet_core.Roll = coreTelemetry._roll;
            
            packet_core.Serialize(packet);

            [self _sendPacket:&packet toStream:writeStream];
        }
    });

}
// ECHAI: thread verified?
+ (void) sendPacket_ExtendedTelemetryThread:(struct extendedTelemetrySkeleton) extendedTelemetry  toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream {

    dispatch_async(targetQueue, ^{

        DroneInterface::Packet_ExtendedTelemetry packet_extended;
        DroneInterface::Packet packet;
        
        packet_extended.GNSSSatCount = extendedTelemetry._GNSSSatCount;
        packet_extended.GNSSSignal = extendedTelemetry._GNSSSignal;
        packet_extended.MaxHeight = extendedTelemetry._max_height;
        packet_extended.MaxDist = extendedTelemetry._max_dist;
        packet_extended.BatLevel = extendedTelemetry._bat_level;
        packet_extended.BatWarning = extendedTelemetry._bat_warning;
        packet_extended.WindLevel = extendedTelemetry._wind_level;
        packet_extended.DJICam = extendedTelemetry._dji_cam;
        packet_extended.FlightMode = extendedTelemetry._flight_mode;
        packet_extended.MissionID = extendedTelemetry._mission_id;
        
        // If drone is not connected, and the app tries to connect to Recon,
        // self->_drone_serial will be null. This will cause an exception
        if (extendedTelemetry._drone_serial){
            packet_extended.DroneSerial = std::string([extendedTelemetry._drone_serial UTF8String]);
        }
        else{
            NSString *serial = @"00000";
            packet_extended.DroneSerial = std::string([serial UTF8String]);
        }
        //packet_extended.DroneSerial = std::string([self->_drone_serial UTF8String]);
        
        packet_extended.Serialize(packet);
        
        [self _sendPacket:&packet toStream:writeStream];
    });
}
// ECHAI: Thread verified?

 //currentPixelBuffer cannot be a null pointer
+ (void) sendPacket_ImageThread:(CVPixelBufferRef*) currentPixelBuffer toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream{
    dispatch_async(targetQueue, ^{
        DroneInterface::Packet_Image packet_image;
        DroneInterface::Packet packet;
        
    //    Uncomment below to show frame being sent in packet.
    //    [self showCurrentFrameImage];
        
        CVPixelBufferRef pixelBuffer;
        pixelBuffer = *currentPixelBuffer;
        UIImage* image = [ImageUtils imageFromPixelBuffer:pixelBuffer];
        packet_image.TargetFPS = [DJIVideoPreviewer instance].currentStreamInfo.frameRate;
        unsigned char *bitmap = [ImageUtils convertUIImageToBitmapRGBA8:image];
        packet_image.Frame = new Image(bitmap, image.size.height, image.size.width, 4);
        
        
        packet_image.Serialize(packet);
        
        [self _sendPacket:&packet toStream:writeStream];
    });
}


+ (void) sendPacket_MessageStringThread:(NSString*)msg ofType:(UInt8)type toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream{
    dispatch_async(targetQueue, ^{
    DroneInterface::Packet_MessageString packet_msg;
    DroneInterface::Packet packet;
    
    packet_msg.Type = type;
    //NSString *test= [NSString stringWithFormat:@"Yaw: %.4f",self->_yaw];
    packet_msg.Message = std::string([msg UTF8String]);
    
    packet_msg.Serialize(packet);
    
    [self _sendPacket:&packet toStream:writeStream];
    });
}

+ (void) sendPacket_AcknowledgmentThread:(BOOL) positive withPID:(UInt8)source_pid toQueue:(dispatch_queue_t) targetQueue toStream:( NSOutputStream *)writeStream{

    dispatch_async(targetQueue, ^{

        DroneInterface::Packet_Acknowledgment packet_acknowledgment;
        DroneInterface::Packet packet;
        
        packet_acknowledgment.Positive = positive ? 1 : 0;
        packet_acknowledgment.SourcePID = source_pid;
        
        packet_acknowledgment.Serialize(packet);
        
        [self _sendPacket:&packet toStream:writeStream];
    });

}


@end

 
