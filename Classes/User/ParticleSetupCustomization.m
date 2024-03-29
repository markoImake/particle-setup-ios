//
//  ParticleSetupCustomization.m
//  mobile-sdk-ios
//
//  Created by Ido Kleinman on 12/12/14.
//  Copyright (c) 2014-2015 Particle. All rights reserved.
//

#import "ParticleSetupCustomization.h"
#import "ParticleSetupMainController.h"



@interface UIColor(withDecimalRGB) // TODO: move to category in helpers
+(UIColor *)colorWithRed:(NSInteger)r green:(NSInteger)g blue:(NSInteger)b;
@end

@implementation UIColor(withDecimalRGB) // TODO: move to category in helpers
+(UIColor *)colorWithRed:(NSInteger)r green:(NSInteger)g blue:(NSInteger)b
{
    return [UIColor colorWithRed:((float)r/255.0f) green:((float)g/255.0f) blue:((float)b/255.0f) alpha:1.0f];
}
@end

@implementation ParticleSetupCustomization


+(instancetype)sharedInstance
{
    static ParticleSetupCustomization *sharedInstance = nil;
    @synchronized(self) {
        if (sharedInstance == nil)
        {
            sharedInstance = [[self alloc] init];
        }
    }
    return sharedInstance;
  
}



-(instancetype)init
{
    if (self = [super init])
    {
        // Defaults
        self.deviceName = @"Particle device";
//        self.deviceImage = [UIImage imageNamed:@"photon" inBundle:[ParticleSetupMainController getResourcesBundle] compatibleWithTraitCollection:nil]; // TODO: make iOS7 compatible
        self.brandName = @"Particle";
//        self.brandImage = [UIImage imageNamed:@"spark-logo-head" inBundle:[ParticleSetupMainController getResourcesBundle] compatibleWithTraitCollection:nil]; // TODO: make iOS7 compatible
        self.brandImage = [ParticleSetupMainController loadImageFromResourceBundle:@"spark-logo-head"];
//        self.brandImageBackgroundColor = [UIColor colorWithRed:0.79f green:0.79f blue:0.79f alpha:1.0f];
        self.brandImageBackgroundColor = [UIColor colorWithRed:229 green:229 blue:237];
      
        self.modeButtonName = @"Setup button";
        self.networkNamePrefix = @"Photon";
        self.listenModeLEDColorName = @"blue";
//        self.appName = self.brandName;// @"ParticleSetup";
        self.fontSizeOffset = 0;
        
        self.privacyPolicyLinkURL = [NSURL URLWithString:@"https://www.particle.io/legal/privacy"];
        self.termsOfServiceLinkURL = [NSURL URLWithString:@"https://www.particle.io/legal/terms-of-service"];
        self.forgotPasswordLinkURL = [NSURL URLWithString:@"https://login.particle.io/forgot"];
        self.troubleshootingLinkURL = [NSURL URLWithString:@"https://community.spark.io/t/spark-core-troubleshooting-guide-spark-team/696"];
        // TODO: add default HTMLs
        
//        self.normalTextColor = [UIColor blackColor];
        self.normalTextColor = [UIColor colorWithRed:28 green:26 blue:25];
        self.pageBackgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0f];
//        self.pageBackgroundColor = [UIColor colorWithRed:250 green:250 blue:250];
        self.linkTextColor = [UIColor colorWithRed:0 green:204 blue:184];
//        self.linkTextColor = [UIColor colorWithRed:6 green:165 blue:226];
//        self.errorTextColor = [UIColor redColor];
//        self.errorTextColor = [UIColor colorWithRed:254 green:71 blue:71];
//        self.elementBackgroundColor = [UIColor colorWithRed:0.84f green:0.32f blue:0.07f alpha:1.0f];
//        self.elementBackgroundColor = [UIColor colorWithRed:0 green:165 blue:231]; // gf yellow
        self.elementBackgroundColor = [UIColor colorWithRed:79 green:222 blue:102];
//        self.elementTextColor = [UIColor whiteColor]; // white button color
        self.elementTextColor = [UIColor colorWithRed:20 green:20 blue:20];
        
        self.normalTextFontName = @"GFKEverett-Regular";
        self.boldTextFontName = @"TWKEverett-Bold";
        self.headerTextFontName = @"GFKEverett-Regular";
        
        self.tintSetupImages = NO;
        self.lightStatusAndNavBar = YES;
        
//        self.organization = NO;
        self.productId = 0;
        self.productMode = NO;
//        self.organizationSlug = @"particle";
//        self.organizationName = @"Particle";
//        self.productSlug = @"photon";
        self.productName = @"Photon";
        self.allowPasswordManager = YES;

        self.allowSkipAuthentication = NO;
        self.skipAuthenticationMessage = @"Skipping authentication will allow you to configure Wi-Fi credentials to your device but it will not be claimed to your account. Are you sure you want to skip authentication?";
        self.disableLogOutOption = NO;
        
        self.instructionStep1 = @"Attach your controller to a Conical Fermenter to power it on";
        self.instructionStep2 = @"The device should be in connection mode. If it's not, use the menu to select 'Connection Config' and then 'Add Wifi'";
        self.instructionStep3 = @"Make sure your iOS device is connected to the Internet";
        
        self.skipRename = NO;
        self.deviceDefaultName = @"Default-device-name";
        return self;
    }
    
    return nil;
}

@end
