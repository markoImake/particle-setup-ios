//
//  ParticleSetupSuccessFailureViewController.m
//  teacup-ios-app
//
//  Created by Ido on 2/3/15.
//  Copyright (c) 2015 spark. All rights reserved.
//


#ifdef FRAMEWORK
#import <ParticleSDK/ParticleSDK.h>
#else
#import "Particle-SDK.h"
#endif
#import "ParticleSetupUIElements.h"
#import "ParticleSetupMainController.h"
#import "ParticleSetupCustomization.h"
#import "ParticleSetupResultViewController.h"
#ifdef ANALYTICS
#import <SEGAnalytics.h>
#endif

@interface ParticleSetupResultViewController () <UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *shortMessageLabel;
@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *longMessageLabel;
@property (weak, nonatomic) IBOutlet UIImageView *setupResultImageView;
@property (weak, nonatomic) IBOutlet UIImageView *brandImageView;

@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *nameDeviceLabel;
@property (weak, nonatomic) IBOutlet UITextField *nameDeviceTextField;
@property (strong, nonatomic) NSArray *randomDeviceNamesArray;
@property (nonatomic) BOOL deviceNamed;
@end

@implementation ParticleSetupResultViewController


- (UIStatusBarStyle)preferredStatusBarStyle
{
    return ([ParticleSetupCustomization sharedInstance].lightStatusAndNavBar) ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    // set logo
    self.brandImageView.image = [ParticleSetupCustomization sharedInstance].brandImage;
    self.brandImageView.backgroundColor = [ParticleSetupCustomization sharedInstance].brandImageBackgroundColor;
    
    self.nameDeviceLabel.hidden = YES;
    self.nameDeviceTextField.hidden = YES;

    // Trick to add an inset from the left of the text fields
    CGRect  viewRect = CGRectMake(0, 0, 10, 32);
    UIView* emptyView = [[UIView alloc] initWithFrame:viewRect];
    
    self.nameDeviceTextField.leftView = emptyView;
    self.nameDeviceTextField.leftViewMode = UITextFieldViewModeAlways;
    self.nameDeviceTextField.delegate = self;
    self.nameDeviceTextField.returnKeyType = UIReturnKeyDone;
    self.nameDeviceTextField.font = [UIFont fontWithName:[ParticleSetupCustomization sharedInstance].normalTextFontName size:16.0];

    // init funny random device names
//    self.randomDeviceNamesArray = [NSArray arrayWithObjects:@"aardvark", @"bacon", @"badger", @"banjo", @"bobcat", @"boomer", @"captain", @"chicken", @"cowboy", @"maker", @"splendid", @"sparkling", @"dentist", @"doctor", @"green", @"easter", @"ferret", @"gerbil", @"hacker", @"hamster", @"wizard", @"hobbit", @"hoosier", @"hunter", @"jester", @"jetpack", @"kitty", @"laser", @"lawyer", @"mighty", @"monkey", @"morphing", @"mutant", @"narwhal", @"ninja", @"normal", @"penguin", @"pirate", @"pizza", @"plumber", @"power", @"puppy", @"ranger", @"raptor", @"robot", @"scraper", @"burrito", @"station", @"tasty", @"trochee", @"turkey", @"turtle", @"vampire", @"wombat", @"zombie", nil];
    
    self.deviceNamed = NO;

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void)viewDidAppear:(BOOL)animated
{
    if ((!isiPhone4) && (!isiPhone5))
        [self disableKeyboardMovesViewUp];
    
    if (self.setupResult == ParticleSetupMainControllerResultSuccess && ![ParticleSetupCustomization sharedInstance].skipRename)
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.nameDeviceTextField becomeFirstResponder];
        });
    }
}

-(void)viewWillAppear:(BOOL)animated
{
#ifdef ANALYTICS
    [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Setup Result Screen"];
#endif

    
    [super viewWillAppear:animated];
    
    switch (self.setupResult) {
        case ParticleSetupMainControllerResultSuccess:
        {
            self.setupResultImageView.image = [ParticleSetupMainController loadImageFromResourceBundle:@"success"];
            self.shortMessageLabel.text = @"SETUP COMPLETED SUCCESSFULLY";
            self.longMessageLabel.text = @"Congrats! You've successfully set up your {device}.";
            // Store the particle device in app user defaults
            NSString *value = self.device.id;
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:value forKey:@"particleSuccessId"];
            [defaults synchronize];
            if (![ParticleSetupCustomization sharedInstance].skipRename) {
                self.nameDeviceLabel.hidden = NO;
                self.nameDeviceTextField.hidden = NO;
                //            NSString *randomDeviceName1 = self.randomDeviceNamesArray[arc4random_uniform((UInt32)self.randomDeviceNamesArray.count)];
                //            NSString *randomDeviceName2 = self.randomDeviceNamesArray[arc4random_uniform((UInt32)self.randomDeviceNamesArray.count)];
                if ([self.device.name length] == 0){
                    self.nameDeviceTextField.text = [ParticleSetupCustomization sharedInstance].deviceDefaultName;
                } else {
                   self.nameDeviceTextField.text = self.device.name;
                }

            }
            
#ifdef ANALYTICS
            [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Success"];
#endif

            break;
        }
            
        case ParticleSetupMainControllerResultSuccessDeviceOffline:
        {
            self.setupResultImageView.image = [ParticleSetupMainController loadImageFromResourceBundle:@"warning"];
            self.shortMessageLabel.text = @"SETUP COMPLETED";
            self.longMessageLabel.text = @"Your device has been successfully claimed to your account, however it is offline. If the device was already claimed before this setup, then the Wi-Fi connection may have failed, and you should try setup again.";
            
#ifdef ANALYTICS
            [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Success" properties:@{@"reason":@"device offline"}];
#endif
            break;
        }

        case ParticleSetupMainControllerResultSuccessNotClaimed:
        {
            self.setupResultImageView.image = [ParticleSetupMainController loadImageFromResourceBundle:@"success"];
            self.shortMessageLabel.text = @"SETUP COMPLETED";
            self.longMessageLabel.text = @"Setup was successful, but since you do not own this device we cannot know if the {device} has connected to the Internet. If you see the WiFi icon with some bars on the screen this means it worked! If not, please restart the setup process.";
            
            
#ifdef ANALYTICS
            [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Success" properties:@{@"reason":@"not claimed"}];
#endif
            break;
            
        }
            
        case ParticleSetupMainControllerResultFailureClaiming:
        {
            self.setupResultImageView.image = [ParticleSetupMainController loadImageFromResourceBundle:@"failure"];
            self.shortMessageLabel.text = @"SETUP FAILED";
            // TODO: add customization point for custom troubleshoot texts
//            self.longMessageLabel.text = @"Setup process failed at claiming your {device}, if your {device} LED is blinking in blue or green this means that you provided wrong Wi-Fi credentials. If {device} LED is breathing cyan an internal cloud issue occured - please contact product support.";
            self.longMessageLabel.text = @"Setup process failed at claiming your {device}, if your {device} display is showing a WiFi icon with a line through it, that means you provided wrong Wi-Fi credentials, please try setup process again.";
#ifdef ANALYTICS
            [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Failure" properties:@{@"reason":@"claiming failed"}];
#endif

            break;
        }
            
        case ParticleSetupMainControllerResultFailureCannotDisconnectFromDevice:
        {
            self.setupResultImageView.image = [ParticleSetupMainController loadImageFromResourceBundle:@"failure"];
            self.shortMessageLabel.text = @"OOPS!";
            self.longMessageLabel.text = @"Setup process couldn't disconnect from the {device} Wi-fi network. This is an internal problem with the device, so please try running setup again after resetting your {device} and putting it back in connection mode if needed.";
#ifdef ANALYTICS
            [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Failure" properties:@{@"reason":@"cannot disconnect"}];
#endif

            break;
        }
            
  
        case ParticleSetupMainControllerResultFailureConfigure:
        {
            self.setupResultImageView.image = [ParticleSetupMainController loadImageFromResourceBundle:@"failure"];
            self.shortMessageLabel.text = @"ERROR!";
            self.longMessageLabel.text = @"Setup process couldn't configure the Wi-Fi credentials for your {device}, please try running setup again after resetting your {device} and putting it back in connection mode if needed.";
#ifdef ANALYTICS
            [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Failure" properties:@{@"reason":@"cannot configure"}];
#endif
            break;
        }
            
        default: //ParticleSetupMainControllerResultFailureLostConnectionToDevice
        {
            self.setupResultImageView.image = [ParticleSetupMainController loadImageFromResourceBundle:@"failure"];
            self.shortMessageLabel.text = @"UH OH!";
            self.longMessageLabel.text = @"Setup lost connection to the device before finalizing configuration process, please try running setup again after putting {device} back in connection mode.";
#ifdef ANALYTICS
            [[SEGAnalytics sharedAnalytics] track:@"Device Setup: Failure" properties:@{@"reason":@"lost connection"}];
#endif
            
            break;
        }
            
            
    }
    
    [self.longMessageLabel setType:@"normal"];

    /*
    if ([ParticleSetupCustomization sharedInstance].tintSetupImages)
    {
        self.setupResultImageView.image = [self.setupResultImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.setupResultImageView.tintColor = [ParticleSetupCustomization sharedInstance].normalTextColor;// elementBackgroundColor;;
    }
     */

}


-(BOOL)textFieldShouldReturn:(UITextField *)textField
{
    
    if (textField == self.nameDeviceTextField)
    {
         if (![ParticleSetupCustomization sharedInstance].skipRename) {
             if ([self.nameDeviceTextField.text length] == 0) {
                 if ([self.device.name length] == 0){
                     self.nameDeviceTextField.text = [ParticleSetupCustomization sharedInstance].deviceDefaultName;
                 } else {
                    self.nameDeviceTextField.text = self.device.name;
                 }
             }
            [self.device rename:self.nameDeviceTextField.text completion:^(NSError *error) {
                if (error) {
                    NSLog(@"Error naming device %@",error.description);
                } else {
                    self.deviceNamed = YES;
                }
                [textField resignFirstResponder];
                [self doneButtonTapped:self];
            }];
         }
        
    }
    
    return YES;
    
}


- (IBAction)doneButtonTapped:(id)sender
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    if (self.device)
        userInfo[kParticleSetupDidFinishDeviceKey] = self.device;

    if (self.deviceID)
        userInfo[kParticleSetupDidFailDeviceIDKey] = self.deviceID;

    userInfo[kParticleSetupDidFinishStateKey] = @(self.setupResult);
    
    if (self.setupResult == ParticleSetupMainControllerResultSuccess)
    {
     
        if (!self.deviceNamed && ![ParticleSetupCustomization sharedInstance].skipRename) {
            if ([self.nameDeviceTextField.text length] == 0) {
                if ([self.device.name length] == 0){
                    self.nameDeviceTextField.text = [ParticleSetupCustomization sharedInstance].deviceDefaultName;
                } else {
                   self.nameDeviceTextField.text = self.device.name;
                }
            }
            [self.device rename:self.nameDeviceTextField.text completion:^(NSError *error) {
                if (error) {
                    NSLog(@"error name device %@",error.description);
                } else {
                    self.deviceNamed = YES;
                }
            }];
        }

        // Update zero notice to user
        // TODO: condition message only if its really getting update zero (need event listening)
//        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"shownUpdateZeroNotice"]) {
//            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Firmware update" message:@"If this is the first time you are setting up this device it might blink its LED in magenta color for a while, this means the device is currently updating its firmware from the cloud to the latest version. Please be patient and do not press the reset button. Device LED will breathe cyan once update has completed and it has come online." delegate:nil cancelButtonTitle:@"Understood" otherButtonTitles:nil];
//            [alert show];
//
//            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"shownUpdateZeroNotice"];
//            [[NSUserDefaults standardUserDefaults] synchronize];
//        }
    }
    
    // finish with success and provide device
    [[NSNotificationCenter defaultCenter] postNotificationName:kParticleSetupDidFinishNotification
                                                        object:nil
                                                      userInfo:userInfo];

}



@end
