//
//  ConnectionController.m
//  DroneClient
//
//  Created by Ben Choi on 2/24/21.
//  Threading added by Elaina Chai 7/22/21

// ECHAI Refactoring Notes:
// ConnectionController.mm is called by the app when "connect" is hit in the UI
// Everything in this function defaults to the main thread. This is Bad
// As a rule: the only things that should be in the main thread are:
//    - UI. This is a requirement by Apple/iOS. This includes updates to iOS app text
//    - Event handling for critical packets such as emergency handling
//    - Starting and tracking queues
// Otherwise, the main thread should be as light weight as possible

// What needs to be in it's own thread, and probably it's own file
// - Packet sending
// - Packet receiving: for emergencing stopping, kick event to main thread
// - Image Processing
// - Logging

// Own file:
// - Inputstream and output stream generation...maybe
// - DJIWayPointMIssion Operator, WaypointMission and virtualstick commands

// Still having some deserialization issues when controller update function
// tries to send BOTH Core and Extended Telemetry
// Will probably have more more packet dropping issues when we also start sending images
// Consider multiple output streams:
// 1) For Core Telemetry
// 2) For Imagery
// 3) For all slower stuff like extended telemetry, messages
// Put them on different ports?

#import "ConnectionController.h"
#import "DJIUtils.h"
#import "Constants.h"
#import "DroneComms.hpp"
//#import "VideoPreviewerSDKAdapter.h"
#import "ConnectionPacketComms.h"
#import "ImageUtils.h"
//#import "Image.hpp"
//#import "Drone.hpp"

#import <DJISDK/DJILightbridgeAntennaRSSI.h>
#import <DJISDK/DJILightbridgeLink.h>

@interface ConnectionController ()

@end

@implementation ConnectionController


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self registerApp];
    [self configureConnectionToProduct];
    
    //ECHAI: Seems like an init function is not ever called
    // But this function is always called. Therefore, I will start my threads here.
    self.writePacketQueue = dispatch_queue_create("com.recon.packet.duplex.write", NULL);
    self.readPacketQueue = dispatch_queue_create("com.recon.packet.duplex.read", NULL);
    self.lQueue = dispatch_queue_create("com.example.logging", NULL);
    
    self->_coreTelemetry = {0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
    self->_extendedTelemetry = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, @"00000"};
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[DJIVideoPreviewer instance] unSetView];
           
    if (self.previewerAdapter) {
        [self.previewerAdapter stop];
        self.previewerAdapter = nil;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self connectToServer];
}


// Executes when SEND DEBUG COMMAND button is pressed
- (IBAction)sendDebugMessage:(id)sender {
    //[self sendPacket_CoreTelemetry];
    [ConnectionPacketComms sendPacket_CoreTelemetryThread:self->_coreTelemetry  toQueue:self.writePacketQueue toStream:outputStream];
    _status3Label.text = [NSString stringWithFormat:@"Yaw: %.4f",self->_coreTelemetry._yaw];

    //[ConnectionPacketComms sendPacket_ExtendedTelemetryThread:self->_extendedTelemetry  toQueue:self.writePacketQueue toStream:outputStream];
    [ConnectionPacketComms sendPacket_MessageStringThread:TEST_MESSAGE ofType: 2 toQueue:self.writePacketQueue toStream:outputStream];
}


// ECHAI: I think the threading for these need to be per case
// For example, obviously case 255 for Emergency Command needs to be on the main queue
- (void) dataReceivedHandler:(uint8_t *)buffer bufferSize: (uint32_t) size withPacket: (DroneInterface::Packet*) packet_fragment {
    
    unsigned int i = 0;
    while(!packet_fragment->IsFinished() && i < size) {
        packet_fragment->m_data.push_back(buffer[i++]);
    }

    if (packet_fragment->IsFinished()) {
        uint8_t PID;
        packet_fragment->GetPID(PID);
        switch(PID) {
            case 255U: {
                // ECHAI: Keep in main thread for now
                DroneInterface::Packet_EmergencyCommand* packet_ec = new DroneInterface::Packet_EmergencyCommand();
                if (packet_ec->Deserialize(*packet_fragment)) {
                    NSLog(@"Successfully deserialized Emergency Command packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:1 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                    
                    [self stopDJIWaypointMission];
                    
                    if (packet_ec->Action == 1) {
                        [[DJIUtils fetchFlightController] startLandingWithCompletion:^(NSError * _Nullable error) {
                        
                        }];
                    } else if (packet_ec->Action == 2) {
                        [[DJIUtils fetchFlightController] startGoHomeWithCompletion:^(NSError * _Nullable error) {
                        
                        }];
                    }
                } else {
                    NSLog(@"Error: Tried to deserialize invalid Emergency Command packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:0 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                }
                break;
            }
            case 254U: {
                // ECHAI: Keep in main thread for now
                DroneInterface::Packet_CameraControl* packet_cc = new DroneInterface::Packet_CameraControl();
                if (packet_cc->Deserialize(*packet_fragment)) {
                    NSLog(@"Successfully deserialized Camera Control packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:1 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                    
                    if (packet_cc->Action == 0) { // stop live feed
                        self->_extendedTelemetry._dji_cam = 1;
                    } else if (packet_cc->Action == 1) { // start live feed
                        self->_extendedTelemetry._dji_cam = 2;
                        self->_target_fps = packet_cc->TargetFPS;
                    }
                } else {
                    NSLog(@"Error: Tried to deserialize invalid Camera Control packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:0 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                }
                break;
            }
            case 253U: {
                DroneInterface::Packet_ExecuteWaypointMission* packet_ewm = new DroneInterface::Packet_ExecuteWaypointMission();
                if (packet_ewm->Deserialize(*packet_fragment)) {
                    NSLog(@"Successfully deserialized Execute Waypoint Mission packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:1 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                    
                    struct DroneInterface::WaypointMission* mission;
                    mission->LandAtLastWaypoint = packet_ewm->LandAtEnd;
                    mission->CurvedTrajectory = packet_ewm->CurvedFlight;
                    mission->Waypoints = packet_ewm->Waypoints;
                    
                    // ECHAI: This can probably be in it's own thread
                    [self executeDJIWaypointMission:mission];
                } else {
                    NSLog(@"Error: Tried to deserialize invalid Execute Waypoint Mission packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:0 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                }
                break;
            }
            case 252U: {
                DroneInterface::Packet_VirtualStickCommand* packet_vsc = new DroneInterface::Packet_VirtualStickCommand();
                if (packet_vsc->Deserialize(*packet_fragment)) {
                    NSLog(@"Successfully deserialized Virtual Stick Command packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:1 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                    
                    [self stopDJIWaypointMission];
                    // ECHAI: These can probably be in their own thread
                    // ECHAI: Probably clear out Waypoint mission thread
                    if (packet_vsc->Mode == 0) {
                        struct DroneInterface::VirtualStickCommand_ModeA* command;
                        command->Yaw = packet_vsc->Yaw;
                        command->V_North = packet_vsc->V_x;
                        command->V_East = packet_vsc->V_y;
                        command->HAG = packet_vsc->HAG;
                        command->timeout = packet_vsc->timeout;
                        [self executeVirtualStickCommand_ModeA:command];
                    } else if (packet_vsc->Mode == 1) {
                        struct DroneInterface::VirtualStickCommand_ModeB* command;
                        command->Yaw = packet_vsc->Yaw;
                        command->V_Forward = packet_vsc->V_x;
                        command->V_Right = packet_vsc->V_y;
                        command->HAG = packet_vsc->HAG;
                        command->timeout = packet_vsc->timeout;
                        [self executeVirtualStickCommand_ModeB:command];
                    }
                    
                    self->_time_of_last_virtual_stick_command = [NSDate date];
                } else {
                    NSLog(@"Error: Tried to deserialize invalid Virtual Stick Command packet.");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:0 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                }
                break;
            }
        }
    }
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {

    NSLog(@"stream event %lu", streamEvent);

    switch (streamEvent) {

        case NSStreamEventOpenCompleted: {
            NSLog(@"Stream opened");
            _serverConnectionStatusLabel.text = @"Server Status: Connected";
            break;
        }
        case NSStreamEventHasBytesAvailable:
            _serverConnectionStatusLabel.text = @"Server Status: Reading from server";
            if (theStream == inputStream)
            {
                uint8_t buffer[1024];
                NSInteger len;

                DroneInterface::Packet* packet_fragment = new DroneInterface::Packet();
                while ([inputStream hasBytesAvailable])
                {
                    len = [inputStream read:buffer maxLength:sizeof(buffer)];
                    if (len > 0)
                    {
                        _serverConnectionStatusLabel.text = @"Server Status: Connected";
                        [self dataReceivedHandler:buffer bufferSize:1024 withPacket:packet_fragment];
                    }
                }
            }
            break;

        case NSStreamEventHasSpaceAvailable:
            NSLog(@"Stream has space available now");
            break;

        case NSStreamEventErrorOccurred:
             NSLog(@"%@",[theStream streamError].localizedDescription);
            break;

        case NSStreamEventEndEncountered:

            [theStream close];
            [theStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            _serverConnectionStatusLabel.text = @"Server Status: Not Connected";
            NSLog(@"close stream");
            break;
        default:
            NSLog(@"Unknown event");
    }

}

- (void)connectToServer {
    _serverConnectionStatusLabel.text = @"Server Status: Connecting...";
    NSLog(@"Setting up connection to %@ : %i", ipAddress, [port intValue]);
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, (__bridge CFStringRef) ipAddress, [port intValue], &readStream, &writeStream);

    messages = [[NSMutableArray alloc] init];

    [self open];
}

- (void)disconnect {
    _serverConnectionStatusLabel.text = @"Server Status: Disconnecting...";
    [self close];
}

- (void)open {

    NSLog(@"Opening streams.");

    outputStream = (__bridge NSOutputStream *)writeStream;
    [outputStream setDelegate:self];
    
    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream open];
    
    inputStream = (__bridge NSInputStream *)readStream;
    [inputStream setDelegate:self];
    [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [inputStream open];
    
     //id<NSStreamDelegate> streamDelegate = self;//object that conforms to the protocol
    /*
    WeakRef(target);
     [NSThread detachNewThreadWithBlock:^(void){
         WeakReturn(target);
         [target->outputStream setDelegate:target];
         //NSOutputStream *outputStream;
         //[ouputStream setDelegate:streamDelegate];
         // define your stream here
         [target->outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                    forMode:NSDefaultRunLoopMode];
         [target->outputStream open];
     }];
     */
     
}

- (void)close {
    NSLog(@"Closing streams.");
    [inputStream close];
    [outputStream close];
    [inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [inputStream setDelegate:nil];
    [outputStream setDelegate:nil];
    inputStream = nil;
    outputStream = nil;
}

#pragma mark DJI Methods

- (void) configureConnectionToProduct {
    _uavConnectionStatusLabel.text = @"UAV Status: Connecting...";
#if ENABLE_DEBUG_MODE
    [DJISDKManager enableBridgeModeWithBridgeAppIP:@"192.168.183.176"];
#else
    [DJISDKManager startConnectionToProduct];
#endif

    [[DJIVideoPreviewer instance] start];
    self.previewerAdapter = [VideoPreviewerSDKAdapter adapterWithDefaultSettings];
    [self.previewerAdapter start];
    [[DJIVideoPreviewer instance] registFrameProcessor:self];
    [[DJIVideoPreviewer instance] setEnableHardwareDecode:true];
    self->_frame_count = 0;
    self->_extendedTelemetry._dji_cam = 2;
    self->_target_fps = 30;
    self->_time_of_last_virtual_stick_command = [NSDate date];
}
// ECHAI: This should be in its own thread

- (BOOL)videoProcessorEnabled {
    return YES;
}

- (UIImage *)imageFromPixelBuffer:(CVPixelBufferRef)pixelBufferRef {
    CVImageBufferRef imageBuffer =  pixelBufferRef;
    CIImage* sourceImage = [[CIImage alloc] initWithCVPixelBuffer:imageBuffer options:nil];
    CGSize size = sourceImage.extent.size;
    UIGraphicsBeginImageContext(size);
    CGRect rect;
    rect.origin = CGPointZero;
    rect.size = size;
    UIImage *remImage = [UIImage imageWithCIImage:sourceImage];
    [remImage drawInRect:rect];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)showCurrentFrameImage {
    CVPixelBufferRef pixelBuffer;
    if (self->_currentPixelBuffer) {
        pixelBuffer = self->_currentPixelBuffer;
        UIImage* image = [self imageFromPixelBuffer:pixelBuffer];
        if (image) {
            UIImageView* imgView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, image.size.width / 4, image.size.height / 4)];
            imgView.image = image;
            [self.fpvPreviewView addSubview:imgView];
        }
    }
}

#pragma mark DJISDKManagerDelegate Method

- (void)productConnected:(DJIBaseProduct *)product
{
    if (product){
        _uavConnectionStatusLabel.text = @"UAV Status: Connected";
        
        DJIFlightController* flightController = [DJIUtils fetchFlightController];
        if (flightController) {
            flightController.delegate = self;
        }
        
        DJICamera *camera = [DJIUtils fetchCamera];
        if (camera != nil) {
            camera.delegate = self;
        }
        
        DJIBattery *battery = [DJIUtils fetchBattery];
        if (battery != nil) {
            battery.delegate = self;
        }
        
        [flightController getSerialNumberWithCompletion:^(NSString * serialNumber, NSError * error) {
            self->_extendedTelemetry._drone_serial = serialNumber;
        }];
        
        [flightController setVirtualStickModeEnabled:TRUE
                                      withCompletion:^(NSError * _Nullable error) {
        
        }];
        
        [[DJIUtils fetchFlightController] setVerticalControlMode:DJIVirtualStickVerticalControlModePosition];
        [[DJIUtils fetchFlightController] setRollPitchControlMode:DJIVirtualStickRollPitchControlModeVelocity];
        [[DJIUtils fetchFlightController] setYawControlMode:DJIVirtualStickYawControlModeAngle];
        
    }
    
    [self setExtendedTelemetryKeyedParameters];
}

- (void)productDisconnected
{
    _uavConnectionStatusLabel.text = @"UAV Status: Not Connected";
}

- (void)registerApp
{
   [DJISDKManager registerAppWithDelegate:self];
}

- (void)appRegisteredWithError:(NSError *)error
{
    NSString* message;
    if (error) {
        message = @"Register App Failed! Please enter your App Key in the plist file and check the network.";
        _registrationStatusLabel.text = @"Registration Status: FAILED";
        
    } else {
        message = @"App successfully registered";
        _registrationStatusLabel.text = @"Registration Status: Registered";
    }
    NSLog(@"%@", message);
}

#pragma mark - DJICameraDelegate

-(void) camera:(DJICamera*)camera didUpdateSystemState:(DJICameraSystemState*)systemState
{
    if (systemState.mode == DJICameraModePlayback ||
        systemState.mode == DJICameraModeMediaDownload) {
        if (self->needToSetMode) {
            self->needToSetMode = NO;
            [camera setMode:DJICameraModeShootPhoto withCompletion:^(NSError * _Nullable error) {
            }];
        }
    }
}

- (void)camera:(DJICamera *_Nonnull)camera
    didReceiveVideoData:(nonnull uint8_t *)videoBuffer
                 length:(size_t)size
{
    
}

#pragma mark - DJIBatteryDelegate

// Use keyed parameters method for battery level because DJIBatteryDelegate unresponsive for some reason. See https://github.com/dji-sdk/Mobile-SDK-iOS/blob/master/docs/README-KeyedInterface.md for more info.
- (void)setExtendedTelemetryKeyedParameters {
    DJIKey * batteryOneKey = [DJIBatteryKey keyWithIndex:0 andParam:DJIBatteryParamChargeRemainingInPercent];
    DJIKey * batteryTwoKey = [DJIBatteryKey keyWithIndex:1 andParam:DJIBatteryParamChargeRemainingInPercent];
    [[DJISDKManager keyManager] startListeningForChangesOnKey: batteryOneKey
                                                 withListener: self
                                               andUpdateBlock: ^(DJIKeyedValue * _Nullable oldKeyedValue, DJIKeyedValue * _Nullable newKeyedValue) {
                                                if (newKeyedValue) {
                                                    self->_extendedTelemetry._bat_level_one = [newKeyedValue.value intValue];
                                                    self->_extendedTelemetry._bat_level = (self->_extendedTelemetry._bat_level_one + self->_extendedTelemetry._bat_level_two) / 2;
                                                }
                                            }];
    [[DJISDKManager keyManager] startListeningForChangesOnKey: batteryTwoKey
                                                 withListener: self
                                               andUpdateBlock: ^(DJIKeyedValue * _Nullable oldKeyedValue, DJIKeyedValue * _Nullable newKeyedValue) {
                                                if (newKeyedValue) {
                                                    self->_extendedTelemetry._bat_level_two = [newKeyedValue.value intValue];
                                                    self->_extendedTelemetry._bat_level = (self->_extendedTelemetry._bat_level_one + self->_extendedTelemetry._bat_level_two) / 2;
                                                }
                                            }];
}

#pragma mark - DJIFlightControllerDelegate
// How often is this getting called?
// If this gets called too frequently, faster than sleep interval for CoreTelemetry
// The thread locks up and we are going to have PROBLEMS with clogged thread
- (void)flightController:(DJIFlightController *)fc didUpdateState:(DJIFlightControllerState *)state
{
    self->_extendedTelemetry._GNSSSignal = [DJIUtils getGNSSSignal:[state GPSSignalLevel]];
    if([DJIUtils gpsStatusIsGood:[state GPSSignalLevel]])
    {
        self->_coreTelemetry._latitude = state.aircraftLocation.coordinate.latitude;
        self->_coreTelemetry._longitude = state.aircraftLocation.coordinate.longitude;
        self->_coreTelemetry._HAG = state.aircraftLocation.altitude;
        self->_coreTelemetry._altitude = state.takeoffLocationAltitude + self->_coreTelemetry._HAG;
        
    }
    
    self->_coreTelemetry._isFlying = state.isFlying ? 1 : 0;
    self->_coreTelemetry._velocity_n = state.velocityX;
    self->_coreTelemetry._velocity_e = state.velocityY;
    self->_coreTelemetry._velocity_d = state.velocityZ;
    self->_coreTelemetry._yaw = state.attitude.yaw;
    self->_coreTelemetry._pitch = state.attitude.pitch;
    self->_coreTelemetry._roll = state.attitude.roll;
    
    self->_extendedTelemetry._GNSSSatCount = state.satelliteCount;
    self->_extendedTelemetry._max_height = state.hasReachedMaxFlightHeight ? 1 : 0;
    self->_extendedTelemetry._max_dist = state.hasReachedMaxFlightRadius ? 1 : 0;
    if (state.isLowerThanSeriousBatteryWarningThreshold) {
        self->_extendedTelemetry._bat_warning = 2;
    } else {
        if (state.isLowerThanBatteryWarningThreshold) {
            self->_extendedTelemetry._bat_warning = 1;
        } else {
            self->_extendedTelemetry._bat_warning = 0;
        }
    }
    self->_extendedTelemetry._wind_level = [DJIUtils getWindLevel:[state windWarning]];
    self->_extendedTelemetry._flight_mode = [DJIUtils getFlightMode:[state flightMode]];

//  KNOWN BUG: Behavior leading to _dji_cam = 0 is currently undefined.
//    if (!self->_camera.isConnected) {
//        self->_dji_cam = 0;
//    } else {
//        if (self->_dji_cam == 0) {
//            self ->_dji_cam = 2;
//        }
//    }
    self->_extendedTelemetry._mission_id = 0;
    
    double time_since_last_virtual_stick_command = [self->_time_of_last_virtual_stick_command timeIntervalSinceNow];
    if (time_since_last_virtual_stick_command > self->_virtual_stick_command_timeout) {
        struct DroneInterface::VirtualStickCommand_ModeA* command;
        command->V_North = 0;
        command->V_East = 0;
        [self executeVirtualStickCommand_ModeA:command];
    }
    
//  KNOWN BUG: Different delay values or slow connections may lead to errors in server-side deserialization
    [ConnectionPacketComms sendPacket_CoreTelemetryThread:self->_coreTelemetry  toQueue:self.writePacketQueue toStream:outputStream];
    //[self sendPacket_CoreTelemetry];
    //[self sendPacket_RSSI];
    //[NSThread sleepForTimeInterval: 0.5];
    [ConnectionPacketComms sendPacket_ExtendedTelemetryThread:self->_extendedTelemetry  toQueue:self.writePacketQueue toStream:outputStream];
    //[NSThread sleepForTimeInterval: 0.5];
}

- (void) executeVirtualStickCommand_ModeA: (DroneInterface::VirtualStickCommand_ModeA *) command {
    DJIFlightController* fc = [DJIUtils fetchFlightController];
    [fc setRollPitchCoordinateSystem:DJIVirtualStickFlightCoordinateSystemGround];
    
    DJIVirtualStickFlightControlData ctrlData;
    ctrlData.yaw = command->Yaw;
    ctrlData.roll = command->V_North;
    ctrlData.pitch = command->V_East;
    ctrlData.verticalThrottle = command->HAG;
    
    if (fc.isVirtualStickControlModeAvailable) {
        [fc sendVirtualStickFlightControlData:ctrlData withCompletion:^(NSError * _Nullable error) {
            
        }];
    } else {
        //https://developer.dji.com/api-reference/ios-api/Components/FlightController/DJIFlightController.html#djiflightcontroller_virtualstickcontrolmodecategory_isvirtualstickcontrolmodeavailable_inline
        NSLog(@"Virtual stick control mode is not available in the current flight conditions. See documentation for details.");
    }
}

- (void) executeVirtualStickCommand_ModeB: (DroneInterface::VirtualStickCommand_ModeB *) command {
    DJIFlightController* fc = [DJIUtils fetchFlightController];
    [fc setRollPitchCoordinateSystem:DJIVirtualStickFlightCoordinateSystemBody];

    DJIVirtualStickFlightControlData ctrlData;
    ctrlData.yaw = command->Yaw;
    ctrlData.roll = command->V_Forward;
    ctrlData.pitch = command->V_Right;
    ctrlData.verticalThrottle = command->HAG;
    
    if (fc.isVirtualStickControlModeAvailable) {
        [fc sendVirtualStickFlightControlData:ctrlData withCompletion:^(NSError * _Nullable error) {
            
        }];
    } else {
        //https://developer.dji.com/api-reference/ios-api/Components/FlightController/DJIFlightController.html#djiflightcontroller_virtualstickcontrolmodecategory_isvirtualstickcontrolmodeavailable_inline
        NSLog(@"Virtual stick control mode is not available in the current flight conditions. See documentation for details.");
    }
}

#pragma mark - DJIMutableWaypointMission
- (void) createDJIWaypointMission: (DroneInterface::WaypointMission *) mission {
    if (self->_waypointMission) {
        [self->_waypointMission removeAllWaypoints];
    } else {
        self->_waypointMission = [[DJIMutableWaypointMission alloc] init];
    }
    
    for (int i = 0; i < mission->Waypoints.size(); i++) {
        CLLocation* location = [[CLLocation alloc] initWithLatitude:mission->Waypoints[i].Latitude longitude:mission->Waypoints[i].Longitude];
        
        if (CLLocationCoordinate2DIsValid(location.coordinate)) {
            DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
            waypoint.altitude = mission->Waypoints[i].Altitude;
            waypoint.cornerRadiusInMeters = mission->Waypoints[i].CornerRadius;
            waypoint.speed = mission->Waypoints[i].Speed;
            if (!isnan(mission->Waypoints[i].LoiterTime)) {
                [waypoint addAction:[[DJIWaypointAction alloc] initWithActionType:DJIWaypointActionTypeStay param:mission->Waypoints[i].LoiterTime]];
            }
            if (!isnan(mission->Waypoints[i].GimbalPitch)) {
                [waypoint addAction:[[DJIWaypointAction alloc] initWithActionType:DJIWaypointActionTypeRotateGimbalPitch param:mission->Waypoints[i].GimbalPitch]];
            }
            [self->_waypointMission addWaypoint:waypoint];
        } else {
            [ConnectionPacketComms sendPacket_MessageStringThread:@"Invalid waypoint coordinate." ofType:3 toQueue:self.writePacketQueue toStream:outputStream];
        }
    }
    
    if (mission->LandAtLastWaypoint == 1) {
        self->_waypointMission.finishedAction = DJIWaypointMissionFinishedAutoLand;
    } else {
        self->_waypointMission.finishedAction = DJIWaypointMissionFinishedNoAction;
    }
    
    if (mission->CurvedTrajectory == 1) {
        self->_waypointMission.flightPathMode = DJIWaypointMissionFlightPathCurved;
    } else {
        self->_waypointMission.flightPathMode = DJIWaypointMissionFlightPathNormal;
    }
}
// This should be in a separate queue
// This code was copied from the DJI sample code, where they likely had on a separate queue
// Evidence for this separate queue is the dispatch_get_main_queue
// That function should be unnecessary here
- (DJIWaypointMissionOperator *)missionOperator {
    return [DJISDKManager missionControl].waypointMissionOperator;
}

- (void) startDJIWaypointMission {
    [[self missionOperator] startMissionWithCompletion:^(NSError * _Nullable error) {
        
    }];
}

- (void) stopDJIWaypointMission {
    [[self missionOperator] stopMissionWithCompletion:^(NSError * _Nullable error) {
        
    }];
}

- (void) executeDJIWaypointMission: (DroneInterface::WaypointMission *) mission {
    [self createDJIWaypointMission:mission];
    
    [[self missionOperator] loadMission: self->_waypointMission];
    
    // On mission upload
    [[self missionOperator] uploadMissionWithCompletion:^(NSError * _Nullable error) {
        [self startDJIWaypointMission];
    }];
    
    // On mission finished
    [[self missionOperator] addListenerToFinished:self withQueue:dispatch_get_main_queue() andBlock:^(NSError * _Nullable error) {

    }];
}
///////// ECHAI: Here are the functions to be moved out of ConnectionController
#pragma mark TCP Connection
// No assignments to self
// ECHAI: Goal is to get all of these functions into its own file

- (void) sendPacket:(DroneInterface::Packet *)packet {
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

// TODO: Create real standard to send this data
// instead of sending as a string (proof of concept and sample
// use of API, maybe this information should be added to an
// existing telemetry packet, or get a packet of its own
// ECHAI: Thread verified? What's the point of this packet?
- (void) sendPacket_RSSI {
    DroneInterface::Packet_MessageString packet_msg;
    DroneInterface::Packet packet;
    
    packet_msg.Type = 2;
    
    DJILightbridgeAntennaRSSI *rssi;
    DJILightbridgeLink *link;
    
    int a1 = [rssi antenna1];
    int a2 = [rssi antenna2];
    NSString *msg = [NSString stringWithFormat:@"antenna1: %d   antenna2: %d", a1, a2];
    NSLog(@"%@", msg);
    
    
//    DJILightbridgeDataRate *rate;
//    NSError *completion;
//    [link getDataRateWithCompletion:(rate, completion];
//
//    NSString *msg2 = [NSString stringWithFormat:@"antenna1: %d   antenna2: %d", a1, a2];

    
    packet_msg.Message = std::string([msg UTF8String]);

    packet_msg.Serialize(packet);

    [self sendPacket: &packet];
}
// ECHAI: Thread verified?
- (void) sendPacket_Image {
    WeakRef(target);
    dispatch_async(self.writePacketQueue, ^{
        WeakReturn(target);
        DroneInterface::Packet_Image packet_image;
        DroneInterface::Packet packet;
        
    //    Uncomment below to show frame being sent in packet.
    //    [self showCurrentFrameImage];
        
        CVPixelBufferRef pixelBuffer;
        if (self->_currentPixelBuffer) {
            pixelBuffer = self->_currentPixelBuffer;
            UIImage* image = [self imageFromPixelBuffer:pixelBuffer];
            packet_image.TargetFPS = [DJIVideoPreviewer instance].currentStreamInfo.frameRate;
            unsigned char *bitmap = [ImageUtils convertUIImageToBitmapRGBA8:image];
            packet_image.Frame = new Image(bitmap, image.size.height, image.size.width, 4);
        }
        
        packet_image.Serialize(packet);
        
        [target sendPacket:&packet];
        //[self _sendPacket:&packet toStream:outputStream];
    });
}

////////////////////
- (void) videoProcessFrame:(VideoFrameYUV *)frame {
    if (frame->cv_pixelbuffer_fastupload != nil) {
        if (self->_extendedTelemetry._dji_cam == 2 && (self->_frame_count % ((int) self->_target_fps) == 0)) {
            CVPixelBufferRef pixelBuffer = (CVPixelBufferRef) frame->cv_pixelbuffer_fastupload;
            if (self->_currentPixelBuffer) {
                CVPixelBufferRelease(self->_currentPixelBuffer);
            }
            self->_currentPixelBuffer = pixelBuffer;
            CVPixelBufferRetain(pixelBuffer);
            
            self->_frame_count = 1;
            
            [ConnectionPacketComms sendPacket_MessageStringThread:@"VIDEO FRAME WOULD HAVE SENT NOW" ofType:1 toQueue:self.writePacketQueue toStream:outputStream]; // for checking frame timing
            [self sendPacket_Image];
        }
        self->_frame_count++;
    } else {
        self->_currentPixelBuffer = nil;
    }
}

////////////////////
@end


