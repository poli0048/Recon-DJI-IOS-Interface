//
//  ConnectionController.h
//  DroneClient
//
//  Created by Ben Choi on 2/24/21.
//

#import <UIKit/UIKit.h>
#import <DJISDK/DJISDK.h>
#import <DJIWidget/DJIVideoPreviewer.h>
#import "VideoPreviewerSDKAdapter.h"




#define WeakRef(__obj) __weak typeof(self) __obj = self
#define WeakReturn(__obj) if(__obj ==nil)return;
#define ENABLE_DEBUG_MODE 1

NS_ASSUME_NONNULL_BEGIN
struct coreTelemetrySkeleton{
    UInt8 _isFlying;
    double _latitude;
    double _longitude;
    double _altitude;
    double _HAG;
    float _velocity_n;
    float _velocity_e;
    float _velocity_d;
    double _yaw;
    double _pitch;
    double _roll;
};

struct extendedTelemetrySkeleton{
    UInt16 _GNSSSatCount;
    int8_t _GNSSSignal;
    UInt8 _max_height;
    UInt8 _max_dist;
    UInt8 _bat_level;
    UInt8 _bat_level_one;
    UInt8 _bat_level_two;
    UInt8 _bat_warning;
    int8_t _wind_level;
    UInt8 _dji_cam;
    UInt8 _flight_mode;
    UInt16 _mission_id;
    NSString *_drone_serial;
};
@interface ConnectionController : UIViewController <DJISDKManagerDelegate, DJICameraDelegate, DJIBatteryDelegate, DJIBatteryAggregationDelegate, DJIFlightControllerDelegate, NSStreamDelegate, DJIVideoFeedListener, VideoFrameProcessor>
{
    @public NSString *ipAddress;
    @public NSString *port;
    
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;

    NSInputStream   *inputStream;
    NSOutputStream  *outputStream;

    NSMutableArray  *messages;
    
    int needToSetMode;
    int _missionDisplayCounter;
    bool _retryConnection;
    // Core Telemetry

    struct coreTelemetrySkeleton _coreTelemetry;
    struct extendedTelemetrySkeleton _extendedTelemetry;

    // Video
    CVPixelBufferRef *_pixelBuffer;
    
    int _frame_count;
    float _target_fps;
    NSDate* _time_of_last_virtual_stick_command;
    float _virtual_stick_command_timeout;
    
    // lock
    NSLock* _socket_lock;
    
    // display
    int _display_type; // 0 for Core Telemetry, 1 for Extended Telemetry,
    //55 for Emergency Command
    //54 for Camera Control
    //53 for Waypoint mission: This will display on a loop
    //52 virtual Stick Command
    
}
@property (nonatomic, strong) DJICamera* camera;
@property (weak, nonatomic) IBOutlet UIView *fpvPreviewView;
@property (weak, nonatomic) IBOutlet UILabel *registrationStatusLabel;
@property (weak, nonatomic) IBOutlet UILabel *serverConnectionStatusLabel;
@property (weak, nonatomic) IBOutlet UILabel *uavConnectionStatusLabel;
@property (weak, nonatomic) IBOutlet UILabel *socketStatusLabel;
@property (weak, nonatomic) IBOutlet UILabel *status0Label;
@property (weak, nonatomic) IBOutlet UILabel *status1Label;
@property (weak, nonatomic) IBOutlet UILabel *status2Label;
@property (weak, nonatomic) IBOutlet UILabel *status3Label;
@property (weak, nonatomic) IBOutlet UILabel *status4Label;
@property (weak, nonatomic) IBOutlet UILabel *status5Label;
@property (weak, nonatomic) IBOutlet UILabel *status6Label;
@property (weak, nonatomic) IBOutlet UILabel *status7Label;
@property (weak, nonatomic) IBOutlet UILabel *status8Label;
@property (weak, nonatomic) IBOutlet UILabel *status9Label;
@property (weak, nonatomic) IBOutlet UIButton *debugButton;
@property (weak, nonatomic) IBOutlet UIButton *disconnectButton;


@property(nonatomic) VideoPreviewerSDKAdapter *previewerAdapter;
@property(atomic) CVPixelBufferRef currentPixelBuffer;
@property(nonatomic, strong) DJIMutableWaypointMission* waypointMission;

@property (nonatomic)dispatch_queue_t writePacketQueue;
@property (nonatomic)dispatch_queue_t readPacketQueue;
@property (nonatomic)dispatch_queue_t imageQueue;
@property (nonatomic)dispatch_queue_t lQueue;


@end

NS_ASSUME_NONNULL_END

