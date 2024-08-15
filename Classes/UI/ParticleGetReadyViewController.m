//
//  ParticleGetReadyViewController.m
//  teacup-ios-app
//
//  Created by Ido on 1/15/15.
//  Copyright (c) 2015 spark. All rights reserved.
//

#import "ParticleGetReadyViewController.h"
#import <CoreLocation/CoreLocation.h>
#import <MediaPlayer/MediaPlayer.h>
#ifdef FRAMEWORK
#import <ParticleSDK/ParticleSDK.h>
#else
#import "Particle-SDK.h"
#endif
#import "ParticleSetupMainController.h"
#import "ParticleDiscoverDeviceViewController.h"
#import "ParticleSetupUIElements.h"
#import "ParticleSetupResultViewController.h"
#import "ParticleSetupCustomization.h"
#import "ParticleGetLocationPermissionViewController.h"


@interface ParticleGetReadyViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *brandImageView;
@property (weak, nonatomic) IBOutlet UIButton *readyButton;
@property (weak, nonatomic) IBOutlet ParticleSetupUISpinner *spinner;

@property (weak, nonatomic) IBOutlet UILabel *loggedInLabel;
@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *instructionsLabel;
//@property (weak, nonatomic) IBOutlet NSLayoutConstraint *scrollViewHeight;

@property (weak, nonatomic) IBOutlet UIImageView *productImageView;

// new claiming process
@property (nonatomic, strong) NSString *claimCode;
@property (nonatomic, strong) NSArray *claimedDevices;
@property (weak, nonatomic) IBOutlet ParticleSetupUIButton *logoutButton;
@property (weak, nonatomic) IBOutlet UIButton *cancelSetupButton;
@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *loggedInUserLabel;

// new outlets - Bevie customise
@property (weak, nonatomic) IBOutlet UILabel *timeToStartLabel;
@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *instructionStep1;
@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *instructionStep2;
@property (weak, nonatomic) IBOutlet ParticleSetupUILabel *instructionStep3;

@end

@implementation ParticleGetReadyViewController


- (UIStatusBarStyle)preferredStatusBarStyle
{
    return ([ParticleSetupCustomization sharedInstance].lightStatusAndNavBar) ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}



- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.brandImageView.image = [ParticleSetupCustomization sharedInstance].brandImage;
    self.brandImageView.backgroundColor = [ParticleSetupCustomization sharedInstance].brandImageBackgroundColor;
    
    UIColor *navBarButtonsColor = ([ParticleSetupCustomization sharedInstance].lightStatusAndNavBar) ? [UIColor whiteColor] : [UIColor blackColor];
    [self.cancelSetupButton setTitleColor:navBarButtonsColor forState:UIControlStateNormal];
    [self.logoutButton setTitleColor:navBarButtonsColor forState:UIControlStateNormal];
    
    if ([ParticleSetupCustomization sharedInstance].productImage)
        self.productImageView.image = [ParticleSetupCustomization sharedInstance].productImage;
    else
        self.loggedInLabel.text = @"";
    self.loggedInLabel.alpha = 0.85;
    self.logoutButton.titleLabel.font = [UIFont fontWithName:[ParticleSetupCustomization sharedInstance].headerTextFontName size:self.logoutButton.titleLabel.font.pointSize];

    self.cancelSetupButton.titleLabel.font = [UIFont fontWithName:[ParticleSetupCustomization sharedInstance].headerTextFontName size:self.self.cancelSetupButton.titleLabel.font.pointSize];

    if ([ParticleSetupCustomization sharedInstance].disableLogOutOption) {
        self.logoutButton.hidden = YES;
    }
    
    [self readyButtonTapped:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    
}

- (IBAction)cancelSetup:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:kParticleSetupDidFinishNotification object:nil userInfo:@{kParticleSetupDidFinishStateKey:@(ParticleSetupMainControllerResultUserCancel)}];

}


-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

}

- (void)selectSegue {
    if (@available(iOS 13.0, *)) {
        if ([CLLocationManager locationServicesEnabled] &&
            ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorizedWhenInUse || [CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorizedAlways)) {
            [self performSegueWithIdentifier:@"discover" sender:self];
        } else {
            [self performSegueWithIdentifier:@"corelocation" sender:self];
        }
    } else {
        [self performSegueWithIdentifier:@"discover" sender:self];
    }
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"discover"]) {
        ParticleDiscoverDeviceViewController *vc = [segue destinationViewController];
        vc.claimCode = self.claimCode;
        vc.claimedDevices = self.claimedDevices;
    } else if ([[segue identifier] isEqualToString:@"corelocation"]) {
        ParticleGetLocationPermissionViewController *vc = [segue destinationViewController];
        vc.claimCode = self.claimCode;
        vc.claimedDevices = self.claimedDevices;
    }

}


- (IBAction)readyButtonTapped:(id)sender
{
    [self.spinner startAnimating];
    self.readyButton.userInteractionEnabled = NO;

    [self selectSegue];    
    
}

-(void)viewWillAppear:(BOOL)animated
{
}



- (IBAction)logoutButtonTouched:(id)sender
{
//    [self.checkConnectionTimer invalidate];
//    [[ParticleCloud sharedInstance] logout];
    // call main delegate or post notification
    [[NSNotificationCenter defaultCenter] postNotificationName:kParticleSetupDidLogoutNotification object:nil userInfo:nil];
    //    [self.navigationController popToRootViewControllerAnimated:YES];
    
}



@end
