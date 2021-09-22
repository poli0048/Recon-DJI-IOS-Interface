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
#import "DroneComms.hpp"
#import "ConnectionController.h"
#import "DJIUtils.h"
#import "Constants.h"

//#import "VideoPreviewerSDKAdapter.h"
#import "ConnectionPacketComms.h"
#import "ImageProcessor.h"
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
    

#if ENABLE_DEBUG_MODE
    [DJISDKManager enableRemoteLoggingWithDeviceID:@"iOS_App" logServerURLString:[NSString stringWithFormat:@"http://%@:4567",ipAddress]];

#endif
    self->_coreTelemetry = {0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
    self->_extendedTelemetry = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, @"00000"};
    
    // DJI Cam
    [self configureConnectionToProduct];
    
    //ECHAI: Seems like an init function is not ever called
    // But this function is always called. Therefore, I will start my threads here.
    self.writePacketQueue = dispatch_queue_create("com.recon.packet.duplex.write", NULL);
    self.readPacketQueue = dispatch_queue_create("com.recon.packet.duplex.read", NULL);
    self.imageQueue = dispatch_queue_create("com.recon.image", NULL);
    self.lQueue = dispatch_queue_create("com.example.logging", NULL);
    
    
    self->_missionDisplayCounter = 0;
    
    // This must be reset once the we no longer need to block sleep
    // It is reset in the disconnect function
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    DJILogDebug(@"iOS Client ready.");
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


// Executes when DISCONNECT Button is pressed
- (IBAction)disconnectApp:(id)sender {
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [DJISDKManager stopConnectionToProduct];
    _uavConnectionStatusLabel.text = @"UAV Status: Disconnected";
}

// Executes when SEND DEBUG COMMAND button is pressed
- (IBAction)sendDebugMessage:(id)sender {
    //[self sendPacket_CoreTelemetry];
    //[ConnectionPacketComms sendPacket_CoreTelemetryThread:self->_coreTelemetry  toQueue:self.writePacketQueue toStream:outputStream];

    DJILogDebug(@"Sending debug message");
    /*
    if ([self missionOperator].loadedMission){
        DJIWaypointMission * inspectMission = [self missionOperator].loadedMission;
        [self debugWaypointMission:inspectMission];
    }
    
    */

    /*self->_status0Label.text = @"Updating Telemetry";
    if (self->_coreTelemetry._isFlying){
        //self->_status1Label.text = @"Core Telemetry says, is flying";
        DJILogDebug(@"is flying");
    }
    else {
        //self->_status1Label.text = @"Core Telemetry says, is not flying";
        DJILogDebug(@"Drone is not flying");
    }
    DJILogDebug(@"is flying");
    self->_status1Label.text = [NSString stringWithFormat:@"Latitude %.6f",self->_coreTelemetry._latitude];
    self->_status2Label.text = [NSString stringWithFormat:@"Longitude: %.6f",self->_coreTelemetry._longitude];
    self->_status3Label.text = [NSString stringWithFormat:@"HAG: %.6f meters",self->_coreTelemetry._HAG];
    self->_status4Label.text = [NSString stringWithFormat:@"Altitude: %.6f meters ",self->_coreTelemetry._altitude];

    self->_status5Label.text = [NSString stringWithFormat:@"GNSSSatCount: %d",self->_extendedTelemetry._GNSSSatCount];
    self->_status6Label.text = [NSString stringWithFormat:@"GNSSSignal: %d",self->_extendedTelemetry._GNSSSignal];
    self->_status7Label.text = [NSString stringWithFormat:@"WindLevel: %d",self->_extendedTelemetry._wind_level];
    self->_status8Label.text = [NSString stringWithFormat:@"DJICam: %d ",self->_extendedTelemetry._dji_cam];
    self->_status9Label.text = [NSString stringWithFormat:@"Flight Mode: %d ",self->_extendedTelemetry._flight_mode];*/
        
    NSString * DEBUGMessage1;
    if (self->_coreTelemetry._isFlying)
        DEBUGMessage1 = @"IsFlying: Yes";
    else
        DEBUGMessage1 = @"IsFlying: No";
    
    NSString * DEBUGMessage2 = [NSString stringWithFormat:@"Latitude %.6f",self->_coreTelemetry._latitude];
    NSString * DEBUGMessage3 = [NSString stringWithFormat:@"Longitude: %.6f",self->_coreTelemetry._longitude];
    NSString * DEBUGMessage4 = [NSString stringWithFormat:@"HAG: %.1f meters",self->_coreTelemetry._HAG];
    NSString * DEBUGMessage5 = [NSString stringWithFormat:@"Altitude: %.1f meters ",self->_coreTelemetry._altitude];
    
    NSString * DEBUGMessage6 = [NSString stringWithFormat:@"V_N: %.1f",self->_coreTelemetry._velocity_n];
    NSString * DEBUGMessage7 = [NSString stringWithFormat:@"V_E: %.1f",self->_coreTelemetry._velocity_e];
    NSString * DEBUGMessage8 = [NSString stringWithFormat:@"V_D: %.1f",self->_coreTelemetry._velocity_d];
    
    NSString * DEBUGMessage9 = [NSString stringWithFormat:@"GNSSSatCount: %d",self->_extendedTelemetry._GNSSSatCount];
    NSString * DEBUGMessage10 = [NSString stringWithFormat:@"GNSSSignal: %d",self->_extendedTelemetry._GNSSSignal];
    NSString * DEBUGMessage11 = [NSString stringWithFormat:@"WindLevel: %d",self->_extendedTelemetry._wind_level];
    NSString * DEBUGMessage12 = [NSString stringWithFormat:@"DJICam: %d ",self->_extendedTelemetry._dji_cam];
    NSString * DEBUGMessage13 = [NSString stringWithFormat:@"Flight Mode: %d ",self->_extendedTelemetry._flight_mode];
    
    NSString * DebugMessage_Full = [NSString
       stringWithFormat:@"%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n%@\r\n",
       DEBUGMessage1, DEBUGMessage2,  DEBUGMessage3,  DEBUGMessage4,
       DEBUGMessage5, DEBUGMessage6,  DEBUGMessage7,  DEBUGMessage8,
       DEBUGMessage9, DEBUGMessage10, DEBUGMessage11, DEBUGMessage12,
       DEBUGMessage13];

    [ConnectionPacketComms sendPacket_MessageStringThread:DebugMessage_Full ofType: 2 toQueue:self.writePacketQueue toStream:outputStream];
    //[ConnectionPacketComms sendPacket_MessageStringThread:TEST_MESSAGE ofType: 2 toQueue:self.writePacketQueue toStream:outputStream];
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
                    DJILogDebug(@"Deserialized Emergency Command Packet %d", packet_ec->Action);
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:1 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];

                    // no matter what, if flying, must try to stop mission is executing
                    if (DJIFlightControllerParamIsFlying){
                        [self stopDJIWaypointMission];
                    }
                    
                    // From here on, the drone is either hovering or on the ground
                    if (packet_ec->Action == 0){
                        // take off if drone is on the ground
                        if (DJIFlightControllerParamIsFlying){
                            DJILogDebug(@"Drone is on ground. Will take off to hover");
                            
                            // TODO: will fail if motors are on -> must turn off motors to take off
                            if (DJIFlightControllerParamAreMotorsOn){
                                [[DJIUtils fetchFlightController] turnOffMotorsWithCompletion:^(NSError * _Nullable error) {
                                    if (error) {DJILogDebug(@"Motors failed to turn off error: %@", error);
                                    }
                                    else{DJILogDebug(@"Motor off command successfully completed!");
                                    }
                                }];
                            }
                            [[DJIUtils fetchFlightController] startTakeoffWithCompletion:^(NSError * _Nullable error) {
                                if (error) {
                                    DJILogDebug(@"Take off error: %@", error);
                                }
                                else{
                                    DJILogDebug(@"Take off command successfully completed!");
                                }
                            }];
                        }
                    }
                    else if (packet_ec->Action == 1) {
                        if (DJIFlightControllerParamIsFlying){
                            [[DJIUtils fetchFlightController] startLandingWithCompletion:^(NSError * _Nullable error) {
                                if (error) {
                                    DJILogDebug(@"Land Now command error: %@", error);
                                }
                                else{
                                    DJILogDebug(@"Landing command successfully completed!");
                                }
                            }];
                        }
                        else {
                            DJILogDebug(@"Not flying. Land now emergency packet does nothing.");
                        }
                        
                    } else if (packet_ec->Action == 2) {
                        // take off if drone is on the ground
                        
                        if (!DJIFlightControllerParamIsFlying){
                            DJILogDebug(@"Drone is on ground. Will take off to hover");
                            // must turn off motors before take off
                            if ( DJIFlightControllerParamAreMotorsOn){
                                [[DJIUtils fetchFlightController] turnOffMotorsWithCompletion:^(NSError * _Nullable error) {
                                    if (error) {DJILogDebug(@"Error turning off motors: %@", error);
                                    }
                                    else{DJILogDebug(@"Motor off command successfully completed!");
                                    }
                                }];
                            }
                            [[DJIUtils fetchFlightController] startTakeoffWithCompletion:^(NSError * _Nullable error) {
                                if (error) {DJILogDebug(@"Take off error: %@", error);
                                }
                                else{
                                    DJILogDebug(@"Take off command successfully completed!");
                                }
                            }];
                        }
                        
                        // drone is hovering. Time to go home
                        [[DJIUtils fetchFlightController] startGoHomeWithCompletion:^(NSError * _Nullable error) {
                            if (error) {DJILogDebug(@"Go Home command error: %@", error);}
                            else{
                                DJILogDebug(@"Go Home command successfully completed!");
                            }
                        }];
                        
                        // Time to land
                        [[DJIUtils fetchFlightController] startLandingWithCompletion:^(NSError * _Nullable error) {
                            if (error) {DJILogDebug(@"Land Now command error: %@", error);
                            }
                            else{
                                DJILogDebug(@"Landing command successfully completed!");
                            }
                        }];
                    
                    }
                } else {
                    NSLog(@"Error: Tried to deserialize invalid Emergency Command packet.");
                    DJILogDebug(@"Deserialization of emergency command packet failed!");
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
                    
                    struct DroneInterface::WaypointMission* mission = new DroneInterface::WaypointMission();
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
                DJILogDebug(@"About to deserialize packet");
                if (packet_vsc->Deserialize(*packet_fragment)) {
                    NSLog(@"Successfully deserialized Virtual Stick Command packet.");
                    DJILogDebug(@"Received Virtual Stick Command");
                    [ConnectionPacketComms sendPacket_AcknowledgmentThread:1 withPID:PID toQueue:self.writePacketQueue toStream:outputStream];
                    DJILogDebug(@"About to stop Waypoint mission");
                    
                    [self stopDJIWaypointMission];
                    DJILogDebug(@"Stopped Waypoint mission");
                    
                    // ECHAI: These can probably be in their own thread
                    // ECHAI: Probably clear out Waypoint mission thread
                    if (packet_vsc->Mode == 0) {
                        DJILogDebug(@"packet_vsc mode is 0");
                        struct DroneInterface::VirtualStickCommand_ModeA* command = new DroneInterface::VirtualStickCommand_ModeA();
                        DJILogDebug(@"Created new virtual stick command");
                        command->Yaw = packet_vsc->Yaw;
                        command->V_North = packet_vsc->V_x;
                        command->V_East = packet_vsc->V_y;
                        command->HAG = packet_vsc->HAG;
                        command->timeout = packet_vsc->timeout;
                        DJILogDebug(@"About to execute Virtual Stick Command");
                        [self executeVirtualStickCommand_ModeA:command];
                        
                    } else if (packet_vsc->Mode == 1) {
                        struct DroneInterface::VirtualStickCommand_ModeB* command = new DroneInterface::VirtualStickCommand_ModeB();
                        command->Yaw = packet_vsc->Yaw;
                        command->V_Forward = packet_vsc->V_x;
                        command->V_Right = packet_vsc->V_y;
                        command->HAG = packet_vsc->HAG;
                        command->timeout = packet_vsc->timeout;
                        [self executeVirtualStickCommand_ModeB:command];
                    }
                    /*
                    self->_time_of_last_virtual_stick_command = [NSDate date];
                    */
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
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

#pragma mark DJI Methods

- (void) configureConnectionToProduct {
    _uavConnectionStatusLabel.text = @"UAV Status: Connecting...";

    [DJISDKManager startConnectionToProduct];

    [[DJIVideoPreviewer instance] start];
    self.previewerAdapter = [VideoPreviewerSDKAdapter adapterWithDefaultSettings];
    [self.previewerAdapter start];
    [[DJIVideoPreviewer instance] registFrameProcessor:self];
    [[DJIVideoPreviewer instance] setEnableHardwareDecode:true];
    self->_frame_count = 1;
    self->_extendedTelemetry._dji_cam = 1;
    self->_target_fps = 30;
    self->_time_of_last_virtual_stick_command = [NSDate date];
}


#pragma mark DJISDKManagerDelegate Method

- (void)productConnected:(DJIBaseProduct *)product
{
    if (product){
        _uavConnectionStatusLabel.text = @"UAV Status: Connected";
        
        DJIFlightController* flightController = [DJIUtils fetchFlightController];
        // Race condition if drone_serial is not set before flight controller delegate is assigned
        // If delegate is assigned BEFORE drone_serial updated, then the flight controller could connect to Recon and send serial "00000" before the real drone_serial is updated
        [flightController getSerialNumberWithCompletion:^(NSString * serialNumber, NSError * error) {
            self->_extendedTelemetry._drone_serial = serialNumber;
        }];
        
        if (flightController) {
            flightController.delegate = self;
        }
        
        DJICamera *camera = [DJIUtils fetchCamera];
        if (camera != nil) {
            camera.delegate = self;
            DJILogDebug(@"DJI Camera connected!");
        }
        else{
            DJILogDebug(@"DJI Camera not connected!");
        }
        //[camera setVideoResolutionAndFrameRate:(nonnull DJICameraVideoResolutionAndFrameRate *) DJICameraParam withCompletion:<#^(NSError * _Nullable error)completion#>]
        DJIBattery *battery = [DJIUtils fetchBattery];
        if (battery != nil) {
            battery.delegate = self;
        }
        

        
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
/*
- (void)didUpdateDatabaseDownloadProgress:(nonnull NSProgress *)progress {
    <#code#>
}
*/

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
    //if([DJIUtils gpsStatusIsGood:[state GPSSignalLevel]])
    if (state.aircraftLocation != nil)
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
    /*
        if (!self->_camera.isConnected) {
            self->_dji_cam = 0;
        } else {
            if (self->_dji_cam == 0) {
                self ->_dji_cam = 2;
            }
        }
     */
    self->_extendedTelemetry._mission_id = 0;
    
    double time_since_last_virtual_stick_command = [self->_time_of_last_virtual_stick_command timeIntervalSinceNow];
    if (time_since_last_virtual_stick_command > self->_virtual_stick_command_timeout) {
        struct DroneInterface::VirtualStickCommand_ModeA* command = new DroneInterface::VirtualStickCommand_ModeA();
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
    
    //Update Labels
    if (self->_coreTelemetry._isFlying)
        self->_status0Label.text = @"IsFlying: Yes";
    else
        self->_status0Label.text = @"IsFlying: No";
    
    self->_status1Label.text = [NSString stringWithFormat:@"Latitude %.6f",self->_coreTelemetry._latitude];
    self->_status2Label.text = [NSString stringWithFormat:@"Longitude: %.6f",self->_coreTelemetry._longitude];
    self->_status3Label.text = [NSString stringWithFormat:@"HAG: %.6f meters",self->_coreTelemetry._HAG];
    self->_status4Label.text = [NSString stringWithFormat:@"Altitude: %.6f meters ",self->_coreTelemetry._altitude];

    self->_status5Label.text = [NSString stringWithFormat:@"GNSSSatCount: %d",self->_extendedTelemetry._GNSSSatCount];
    self->_status6Label.text = [NSString stringWithFormat:@"GNSSSignal: %d",self->_extendedTelemetry._GNSSSignal];
    self->_status7Label.text = [NSString stringWithFormat:@"WindLevel: %d",self->_extendedTelemetry._wind_level];
    self->_status8Label.text = [NSString stringWithFormat:@"DJICam: %d ",self->_extendedTelemetry._dji_cam];
    self->_status9Label.text = [NSString stringWithFormat:@"Flight Mode: %d ",self->_extendedTelemetry._flight_mode];
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

///////// ECHAI: Here are the functions to be moved out of ConnectionController
///
// ECHAI: This should be in its own thread
// Image related stuff
// Do not move until I have a testbench set up for testing images
// Tested feed: when camera is running and video feed open, packet updates are MUCH slower
// This is needs to be in its own thread
////////////////////
/*
- (void) videoProcessFrame:(VideoFrameYUV *)frame {
    if (frame->cv_pixelbuffer_fastupload != nil) {
        if (self->_extendedTelemetry._dji_cam == 2 && (self->_frame_count % ((int) self->_target_fps) == 0)) {
            

            self->_frame_count = 1;
            [ImageProcessor videoProcessFrameInner:frame toFrame:(CVPixelBufferRef*) &self->_currentPixelBuffer writeQueue:self.writePacketQueue imageQueue:self.imageQueue toStream:outputStream];
            
        }
        self->_frame_count++;
    } else {
        self->_currentPixelBuffer = nil;
    }
}
 */

- (void) videoProcessFrame:(VideoFrameYUV *)frame {
    if (frame->cv_pixelbuffer_fastupload != nil) {
        //According to DJI docs, the live streams are 30 fps regardless of the source
        int targetFramePeriod = std::clamp((int) std::round(30.0f/self->_target_fps), 1, 120);
        
        if (self->_extendedTelemetry._dji_cam == 2 && (self->_frame_count >= targetFramePeriod)) {
            
            CVPixelBufferRef pixelBuffer = (CVPixelBufferRef) frame->cv_pixelbuffer_fastupload;
            if (self->_currentPixelBuffer) {
                CVPixelBufferRelease(self->_currentPixelBuffer);
            }
            self->_currentPixelBuffer = pixelBuffer;
            CVPixelBufferRetain(pixelBuffer);
            
            self->_frame_count = 1;
            
            //[ConnectionPacketComms sendPacket_MessageStringThread:@"VIDEO FRAME WOULD HAVE SENT NOW" ofType:1 toQueue:self.writePacketQueue toStream:outputStream]; // for checking frame timing
            if (self->_currentPixelBuffer) {
                // ECHAI: Using image queue. Imagethread does a lot of image heavy lifting
                [ConnectionPacketComms sendPacket_JpegImageThread: (CVPixelBufferRef*) &self->_currentPixelBuffer toQueue:self.writePacketQueue toImageQueue: self.imageQueue toStream:outputStream];
            }
        }
        else
            self->_frame_count++;
    } else {
        self->_currentPixelBuffer = nil;
    }
}
 
- (BOOL)videoProcessorEnabled {
    return YES;
}

/*
- (void)showCurrentFrameImage {
    CVPixelBufferRef pixelBuffer;
    if (self->_currentPixelBuffer) {
        pixelBuffer = self->_currentPixelBuffer;
        UIImage* image = [ImageUtils imageFromPixelBuffer:pixelBuffer];
        if (image) {
            UIImageView* imgView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, image.size.width / 4, image.size.height / 4)];
            imgView.image = image;
            [self.fpvPreviewView addSubview:imgView];
            self.fpvP
        }
    }
}
 */
////////////////////
- (void) executeVirtualStickCommand_ModeA: (DroneInterface::VirtualStickCommand_ModeA *) command {
    DJIFlightController* fc = [DJIUtils fetchFlightController];

    [fc setRollPitchCoordinateSystem:DJIVirtualStickFlightCoordinateSystemGround];
    
    DJIVirtualStickFlightControlData ctrlData;
    ctrlData.yaw = command->Yaw;
    ctrlData.roll = command->V_North;
    ctrlData.pitch = command->V_East;
    ctrlData.verticalThrottle = command->HAG;
    //DJILogDebug(@"About to send crtlData");
    
    if (fc.isVirtualStickControlModeAvailable) {
        [fc sendVirtualStickFlightControlData:ctrlData withCompletion:^(NSError * _Nullable error) {
            if (error){
                DJILogDebug(@"crtlData failed to Send:%@",error);
            }
            
            /*else {
                DJILogDebug(@"crtlData sucessfully sent");
                NSString *rollPitchUnit = @"m/s";
                NSString *yawUnit = @"m/s";
                NSString *verticalUnit = @"m/s";
                if (fc.rollPitchControlMode == DJIVirtualStickRollPitchControlModeVelocity){
                    rollPitchUnit = @"degrees";
                }
                if (fc.yawControlMode == DJIVirtualStickYawControlModeAngle){
                    yawUnit = @"degrees";
                }
                if (fc.verticalControlMode == DJIVirtualStickVerticalControlModePosition){
                    verticalUnit = @"m";
                }
                DJILogDebug(@"Yaw: %.6f %@",ctrlData.yaw, yawUnit);
                DJILogDebug(@"Roll: %.6f %@",ctrlData.roll, rollPitchUnit);
                DJILogDebug(@"Pitch: %.6f %@",ctrlData.pitch, rollPitchUnit);
                DJILogDebug(@"Vertical Throttle: %.6f %@",ctrlData.verticalThrottle, verticalUnit);
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    self->_status0Label.text = @"Issuing Command Packet ModeA!";
                    self->_status1Label.text = [NSString stringWithFormat:@"Yaw: %.6f %@",ctrlData.yaw, yawUnit];
                    self->_status2Label.text = [NSString stringWithFormat:@"Roll: %.6f %@",ctrlData.roll, rollPitchUnit];
                    self->_status3Label.text = [NSString stringWithFormat:@"Pitch: %.6f %@",ctrlData.pitch, rollPitchUnit];
                    self->_status4Label.text = [NSString stringWithFormat:@"Vertical Throttle: %.6f %@",ctrlData.verticalThrottle, verticalUnit];
                    

                   // do work here to Usually to update the User Interface
                });
            }*/
            
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
            if (error){
                DJILogDebug(@"crtlData failed to Send:%@",error);
            }
            /*else {

                NSString *rollPitchUnit = @"m/s";
                NSString *yawUnit = @"m/s";
                NSString *verticalUnit = @"m/s";
                if (fc.rollPitchControlMode == DJIVirtualStickRollPitchControlModeVelocity){
                    rollPitchUnit = @"degrees";
                }
                if (fc.yawControlMode == DJIVirtualStickYawControlModeAngle){
                    yawUnit = @"degrees";
                }
                if (fc.verticalControlMode == DJIVirtualStickVerticalControlModePosition){
                    verticalUnit = @"m";
                }
                DJILogDebug(@"Mode B");
                DJILogDebug(@"Yaw: %.6f %@",ctrlData.yaw, yawUnit);
                DJILogDebug(@"Roll: %.6f %@",ctrlData.roll, rollPitchUnit);
                DJILogDebug(@"Pitch: %.6f %@",ctrlData.pitch, rollPitchUnit);
                DJILogDebug(@"Vertical Throttle: %.6f %@",ctrlData.verticalThrottle, verticalUnit);
                dispatch_async(dispatch_get_main_queue(), ^{

                    self->_status0Label.text = @"Issuing Command Packet ModeB!";
                    self->_status1Label.text = [NSString stringWithFormat:@"Yaw: %.6f %@",ctrlData.yaw, yawUnit];
                    self->_status2Label.text = [NSString stringWithFormat:@"Roll: %.6f %@",ctrlData.roll, rollPitchUnit];
                    self->_status3Label.text = [NSString stringWithFormat:@"Pitch: %.6f %@",ctrlData.pitch, rollPitchUnit];
                    self->_status4Label.text = [NSString stringWithFormat:@"Vertical Throttle: %.6f %@",ctrlData.verticalThrottle, verticalUnit];

                   // do work here to Usually to update the User Interface
                });
            }*/
        }];
    } else {
        //https://developer.dji.com/api-reference/ios-api/Components/FlightController/DJIFlightController.html#djiflightcontroller_virtualstickcontrolmodecategory_isvirtualstickcontrolmodeavailable_inline
        NSLog(@"Virtual stick control mode is not available in the current flight conditions. See documentation for details.");
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
        if (error) {
            NSLog(@"ERROR: startMission:withCompletion:. %@", error.description);
            DJILogDebug(@"startMission Fail: %@", error);
        }
        else {
            NSLog(@"SUCCESS: startMission:withCompletion:.");
            DJILogDebug(@"startMission Succeeded: %@", error);
        }
        
    }];
}

- (void) stopDJIWaypointMission {
    if(([self missionOperator].currentState != DJIWaypointMissionStateExecuting) || ([self missionOperator].currentState != DJIWaypointMissionStateExecutionPaused)){
        DJILogDebug([NSString stringWithFormat:@"Not ready! stopMissionwithCompletion will fail"]);
    }
    [[self missionOperator] stopMissionWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            DJILogDebug(@"Mission failed to stop with error: %@", error);
        }
        else{
            DJILogDebug(@"Stop and hover command successfully completed!");
        }
    }];
}

- (void) executeDJIWaypointMission: (DroneInterface::WaypointMission *) mission {
    [self createDJIWaypointMission:mission];
    
    if(([self missionOperator].currentState != DJIWaypointMissionStateReadyToUpload) || ([self missionOperator].currentState != DJIWaypointMissionStateReadyToExecute)){
        DJILogDebug([NSString stringWithFormat:@"Not ready! Upload will fail!"]);
    }
    
    NSError *error = [[self missionOperator] loadMission: self->_waypointMission];
    if (error) {
        DJILogDebug(@"loadMission Fail: %@", error);
        }
    else{
        DJILogDebug(@"loadMission succeeded!");
    }

    [[self missionOperator] uploadMissionWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"ERROR: uploadMission:withCompletion:. %@", error.description);
            DJILogDebug(@"uploadMission Fail: %@", error);
        }
        else {
            NSLog(@"SUCCESS: uploadMission:withCompletion:.");
            DJILogDebug(@"uploadMission Succeeded: %@", error);
            
            [self startDJIWaypointMission];

        }
        
    }];
        // On mission finished
        [[self missionOperator] addListenerToFinished:self withQueue:dispatch_get_main_queue() andBlock:^(NSError * _Nullable error) {

        }];
}

- (void) debugWaypointMission: (DJIWaypointMission *) mission{
    
        DJIWaypoint * currentWaypoint = [[NSMutableArray alloc] initWithArray:mission.allWaypoints][self->_missionDisplayCounter];
        // Synchronous dispatch!
        // Wait until text is updated before incrementing
        dispatch_async(dispatch_get_main_queue(), ^{
            
            self->_status1Label.text = [NSString stringWithFormat:@"Waypoint ID: %d",self->_missionDisplayCounter];
            self->_status4Label.text = [NSString stringWithFormat:@"Latitude in WGS 84: %.6f degrees",currentWaypoint.coordinate.latitude];
            self->_status5Label.text = [NSString stringWithFormat:@"Longitude in WGS 84: %.6f degrees",currentWaypoint.coordinate.longitude];
            //6: Altitutde in meters
           self->_status6Label.text = [NSString stringWithFormat:@"Altitude in meters: %.4f",currentWaypoint.altitude];
       // 7: Corner Radius in meters
           self->_status7Label.text = [NSString stringWithFormat:@"Corner Radius in meters: %.4f ",currentWaypoint.cornerRadiusInMeters];
       // 8: Speed in meters
           self->_status8Label.text = [NSString stringWithFormat:@"Speed in m/s: %.4f",currentWaypoint.speed];
       // 9: LoiterTime in milliseconds. This is a waypoint action
           unsigned long num_actions = [currentWaypoint.waypointActions count];
           self->_status9Label.text = [NSString stringWithFormat:@"There are waypoint %lu actions!",num_actions];
            self->_missionDisplayCounter +=1;
            if (self->_missionDisplayCounter >= mission.waypointCount){
                self->_missionDisplayCounter = 0;
            }
        });
}

////////////////////
@end



/*
- (void)videoFeed:(nonnull DJIVideoFeed *)videoFeed didUpdateVideoData:(nonnull NSData *)videoData {
    <#code#>
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    <#code#>
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    <#code#>
}

- (void)preferredContentSizeDidChangeForChildContentContainer:(nonnull id<UIContentContainer>)container {
    <#code#>
}

- (CGSize)sizeForChildContentContainer:(nonnull id<UIContentContainer>)container withParentContainerSize:(CGSize)parentSize {
    <#code#>
}

- (void)systemLayoutFittingSizeDidChangeForChildContentContainer:(nonnull id<UIContentContainer>)container {
    <#code#>
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(nonnull id<UIViewControllerTransitionCoordinator>)coordinator {
    <#code#>
}

- (void)willTransitionToTraitCollection:(nonnull UITraitCollection *)newCollection withTransitionCoordinator:(nonnull id<UIViewControllerTransitionCoordinator>)coordinator {
    <#code#>
}

- (void)didUpdateFocusInContext:(nonnull UIFocusUpdateContext *)context withAnimationCoordinator:(nonnull UIFocusAnimationCoordinator *)coordinator {
    <#code#>
}

- (void)setNeedsFocusUpdate {
    <#code#>
}

- (BOOL)shouldUpdateFocusInContext:(nonnull UIFocusUpdateContext *)context {
    <#code#>
}

- (void)updateFocusIfNeeded {
    <#code#>
}
*/
