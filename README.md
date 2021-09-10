# Recon-DJI-IOS-Interface
This is an iOS companion App to enable the Recon ground control station (https://github.com/poli0048/Recon) to interact with DJI drones.

Latest update requires adding the opencv framework from the "iOS pack": https://opencv.org/releases/ 
Drag and drop opencv2.framework into DroneClient project folder in Xcode to setup.

# Contributors and License
Recon is primarily developed by:
 * Stanford University

Recon-DJI-IOS-Interface is not a commercial product; it is developed as part of a USDA/NIFA research project: “NRI: FND: COLLAB: Multi-Vehicle Systems for Collecting Shadow-Free Imagery in Precision Agriculture” (NIFA Award # 2020-67021-30758). Recon-DJI-IOS-Interface is open source and distributed under a 3-clause BSD license (See "LICENSE"). It is not commercially supported and you use it at your own risk.

# Build Instructions

1) Install minimum Xcode 12.5.1
2) Download and open this github project inside Xcode
3) This project requires DJI Mobile SDK for iOS. Follow the instructions on this webpage (https://developer.dji.com/mobile-sdk/documentation/quick-start/index.html) to register as a DJI Developer and generate an App Key.
4) To set up the DJI Mobile SDK, follow the instructions on this webpage (https://developer.dji.com/mobile-sdk/documentation/quick-start/index.html) to install the mobile SDK via cocoapods. This may require an install of Ruby. I strongly recommend creating a separate ruby install and do not use tamper with the Ruby install that is default in OSX.
5) Import the OpenCV Framework inside your Xcode project. This is NOT an install of OpenCV in OSX. Instead, a) download the "iOS Pack" from https://opencv.org/releases/. Then, b) import the framework into th Xcode project using the instructions https://docs.opencv.org/4.5.3/d7/d88/tutorial_hello.html
6) Inside the Xcode project, add the App Key and bundle identifier from step (3) to your Xcode project file (.xcodeproj)
7) Build and install on your iOS device. Disconnect the iOS device from your computer
8) The first time the App is opened without the iOS connected to Xcode, it needs to be verified over the internet. Therefore, ensure the iOS device is connected to the internet. Then open the App and ensure it starts up without any issues.



# Current State
In development... most intended functionality is implemented but many components are minimally tested.

