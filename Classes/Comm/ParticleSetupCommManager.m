//
//  ParticleSetupManager.m
//  spark-setup-ios
//
//  Created by Ido Kleinman on 11/20/14.
//  Copyright (c) 2014-2015 Particle. All rights reserved.
//  This class implements the Particle Soft-AP protocol specified in
//  https://github.com/spark/photon-wiced/blob/master/soft-ap.md
//

#import "ParticleSetupCommManager.h"
#import "ParticleSetupConnection.h"
#import "ParticleSetupSecurityManager.h"
#import <NetworkExtension/NetworkExtension.h>
#import <CoreLocation/CoreLocation.h>

// new iOS 9 requirements:
#import "Reachability.h"
@import UIKit;

// Modern WiFi detection: NEHotspotNetwork (iOS 14+)
// Socket headers for device communication
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <unistd.h>
#import <CoreFoundation/CoreFoundation.h>


#define ENCRYPT_PWD     1

typedef NS_ENUM(NSInteger, ParticleSetupCommandType) {
    ParticleSetupCommandTypeNone=0,
    ParticleSetupCommandTypeVersion=1,
    ParticleSetupCommandTypeDeviceID=2,
    ParticleSetupCommandTypeScanAP=3,
    ParticleSetupCommandTypeConfigureAP=4,
    ParticleSetupCommandTypeConnectAP=5,
    ParticleSetupCommandTypePublicKey,
    ParticleSetupCommandTypeSet,
};


NSString *const kParticleSetupConnectionEndpointAddress = @"192.168.0.1";
NSString *const kParticleSetupConnectionEndpointPortString = @"5609";
int const kParticleSetupConnectionEndpointAddressHex = 0xC0A80001;
int const kParticleSetupConnectionEndpointPort = 5609;


@interface ParticleSetupCommManager() <ParticleSetupConnectionDelegate>

@property (nonatomic, strong) ParticleSetupConnection *connection;
@property (atomic) ParticleSetupCommandType commandType; // last command type
@property (copy)void (^commandCompletionBlock)(id, NSError *); // completion block for last sent command
//@property (copy)void (^commandDeviceIDCompletionBlock)(id, BOOL, NSError *); // completion block for commandID command

@property (copy)void (^commandSendBlock)(void); // code block for sending the command to socket
@property (nonatomic, strong) NSTimer *sendCommandTimeoutTimer;
@property (nonatomic, strong) NSString *networkNamePrefix;
@end

// Static variables to track verification state
static NSDate *_lastForegroundVerification = nil;
static NSString *_lastVerifiedSSID = nil;
static BOOL _wentToBackgroundSinceLastCheck = NO;


@implementation ParticleSetupCommManager

+(void)resetForegroundVerification
{
    _lastForegroundVerification = nil;
    _lastVerifiedSSID = nil;
    _wentToBackgroundSinceLastCheck = NO;
}


//-(instancetype)initWithConnection:(ParticleSetupConnection *)connection
-(instancetype)init
{
    self = [super init];
    if (self)
    {
        self.commandType = ParticleSetupCommandTypeNone;
        self.commandCompletionBlock = nil;
        self.commandSendBlock = nil;
        //        self.ready = NO;
        
        return self;
        
    }
    
    return nil;
}


-(instancetype)initWithNetworkPrefix:(NSString *)networkPrefix
{
    ParticleSetupCommManager *manager = [self init];
    if (manager)
    {
        manager.networkNamePrefix = networkPrefix;
        return manager;
    }
    else
        return nil;
}

#pragma mark Particle photon device wifi connection detection methods

// Simple socket-based check - works in background but doesn't verify network name
+(BOOL)checkParticleDeviceReachability
{

    CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
    if (socket == NULL) {
        return NO;
    }

    // Set non-blocking
    int flags = fcntl(CFSocketGetNative(socket), F_GETFL, 0);
    fcntl(CFSocketGetNative(socket), F_SETFL, flags | O_NONBLOCK);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kParticleSetupConnectionEndpointPort);
    addr.sin_addr.s_addr = htonl(kParticleSetupConnectionEndpointAddressHex);

    CFDataRef address = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&addr, sizeof(addr));
    CFSocketError result = CFSocketConnectToAddress(socket, address, 0.5); // 500ms timeout

    BOOL isConnected = NO;

    if (result == kCFSocketSuccess || result == kCFSocketTimeout) {
        fd_set writefds;
        FD_ZERO(&writefds);
        FD_SET(CFSocketGetNative(socket), &writefds);

        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 500000; // 500ms

        int selectResult = select(CFSocketGetNative(socket) + 1, NULL, &writefds, NULL, &timeout);

        if (selectResult > 0) {
            int error = 0;
            socklen_t len = sizeof(error);
            if (getsockopt(CFSocketGetNative(socket), SOL_SOCKET, SO_ERROR, &error, &len) == 0 && error == 0) {
                isConnected = YES;
            }
        }
    }

    CFRelease(address);
    CFSocketInvalidate(socket);
    CFRelease(socket);

    return isConnected;
}

+(BOOL)checkParticleDeviceWifiConnection:(NSString *)networkPrefix
{
    // Modern approach using NEHotspotNetwork API (iOS 14+)
    // This requires:
    // 1. "Access WiFi Information" entitlement (com.apple.developer.networking.wifi-info)
    // 2. CoreLocation permission for precise location (since user manually connects to WiFi)


    // Check if app is in background - MUST be called on main thread
    __block UIApplicationState state;
    if ([NSThread isMainThread]) {
        state = [[UIApplication sharedApplication] applicationState];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            state = [[UIApplication sharedApplication] applicationState];
        });
    }
    if (state == UIApplicationStateBackground || state == UIApplicationStateInactive) {

        // Mark that we went to background (so next foreground check knows to invalidate cache)
        _wentToBackgroundSinceLastCheck = YES;

        BOOL reachable = [ParticleSetupCommManager checkParticleDeviceReachability];
        if (reachable) {
            return YES;  // Allow background check to succeed for notifications
        } else {
            return NO;
        }
    }

    // App is in FOREGROUND
    NSLog(@"[WiFi Detection] App state: FOREGROUND ✅");

    // Check if we just came back from background
    if (_wentToBackgroundSinceLastCheck) {
        _wentToBackgroundSinceLastCheck = NO;  // Reset flag
        // Clear old verification data
        _lastForegroundVerification = nil;
        _lastVerifiedSSID = nil;
    }


    // PHASE 1: First verify device is reachable via socket
    BOOL deviceReachable = [ParticleSetupCommManager checkParticleDeviceReachability];

    if (!deviceReachable) {
        return NO;
    }


    // PHASE 2: Now verify the network name with NEHotspotNetwork

    // PHASE 2 STEP 1: Check if Location Services are enabled on device
    if (![CLLocationManager locationServicesEnabled]) {
        return NO;
    }

    // PHASE 2 STEP 2: Check app's location authorization status
    CLAuthorizationStatus authStatus = [CLLocationManager authorizationStatus];

    switch (authStatus) {
        case kCLAuthorizationStatusNotDetermined:
            return NO;

        case kCLAuthorizationStatusRestricted:
            return NO;

        case kCLAuthorizationStatusDenied:
            return NO;

        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
            break;

        default:
            NSLog(@"[WiFi Detection] ⚠️ Unknown authorization status: %d", (int)authStatus);
            break;
    }


    __block NSString *currentSSID = nil;
    __block BOOL completionHandlerCalled = NO;
    __block NSError *fetchError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);


    [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork * _Nullable currentNetwork) {
        completionHandlerCalled = YES;

        if (currentNetwork != nil) {
            currentSSID = currentNetwork.SSID;
            NSLog(@"[WiFi Detection] ✅ NEHotspotNetwork returned network object");
            NSLog(@"[WiFi Detection] SSID: '%@'", currentSSID);
        } else {
        }
        dispatch_semaphore_signal(semaphore);
    }];

    // Wait up to 5 seconds for the completion handler (increased from 2s due to slow API)

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
    long result = dispatch_semaphore_wait(semaphore, timeout);

    if (result != 0) {

        return NO;
    }


    if (currentSSID != nil) {
        NSLog(@"[WiFi Detection] Comparing SSID '%@' (length: %lu) with prefix '%@' (length: %lu)",
              currentSSID, (unsigned long)[currentSSID length],
              networkPrefix, (unsigned long)[networkPrefix length]);

        if ([currentSSID hasPrefix:networkPrefix]) {
            // Store successful foreground verification
            BOOL wasFirstVerification = (_lastForegroundVerification == nil);
            _lastForegroundVerification = [NSDate date];
            _lastVerifiedSSID = currentSSID;

            return YES;
        } else {
            return NO;
        }
    } else {
        return NO;
    }
}

#pragma mark ParticleSetupConnection delegate methods

-(void)ParticleSetupConnection:(ParticleSetupConnection *)connection didReceiveData:(NSString *)data
{
    if (connection == self.connection)
    {
        NSNumber *responseCode;
        NSError *e = nil;
        NSDictionary *response = [NSJSONSerialization JSONObjectWithData:[data dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&e];
        if ((!e) && (self.commandCompletionBlock))
        {
            switch (self.commandType) {
                case ParticleSetupCommandTypeVersion:
                    self.commandCompletionBlock(response[@"v"],nil); // the version string
                    //                    self.commandType = ParticleSetupCommandTypeNone;
                    break;
                    
                case ParticleSetupCommandTypeDeviceID:
                    if (self.commandCompletionBlock) // special completion
                    self.commandCompletionBlock(response, nil); // the device ID string + claimed flag dictionary
                    //                    self.commandType = ParticleSetupCommandTypeNone;
                    break;
                    
                case ParticleSetupCommandTypeScanAP:
                    self.commandCompletionBlock(response[@"scans"],nil); // the scan response array
                    //                    self.commandType = ParticleSetupCommandTypeNone;
                    break;
                    
                    
                case ParticleSetupCommandTypeConfigureAP:
                case ParticleSetupCommandTypeConnectAP:
                case ParticleSetupCommandTypeSet:
                    self.commandCompletionBlock(response[@"r"],nil); // the response code number
                    //                    self.commandType = ParticleSetupCommandTypeNone;
                    break;
                    
                case ParticleSetupCommandTypePublicKey:
                    // handle key storage
//                    NSLog(@"ParticleSetupCommandTypePublicKey response is:\n%@",response);
                    
                    responseCode = (NSNumber *)response[@"r"];
                    if (responseCode.intValue != 0)
                    {
                        self.commandCompletionBlock(nil,[NSError errorWithDomain:@"ParticleSetupCommManagerError" code:2006 userInfo:@{NSLocalizedDescriptionKey:@"Could not retrieve public key from device"}]);
                    }
                    else
                    {
                        // decode HEX encoded key to NSData
                        NSString *pubKeyHexCoded = (NSString *)response[@"b"];
//                        NSLog(@"Encoded key is %@", pubKeyHexCoded);
                        
                        NSData *pubKey = [ParticleSetupSecurityManager decodeDataFromHexString:pubKeyHexCoded];
//                        NSLog(@"Decoded key is %@", [pubKey description]);
                        
                        if ([ParticleSetupSecurityManager setPublicKey:pubKey])
                        {
//                            NSLog(@"Public key stored in keychain successfully");
                            self.commandCompletionBlock(response[@"r"],nil);
                        }
                        else
                        {
                            self.commandCompletionBlock(nil,[NSError errorWithDomain:@"ParticleSetupSecurityManager" code:2007 userInfo:@{NSLocalizedDescriptionKey:@"Could not store public key in device keychain"}]);
                        }

                    }
                default: // something else happened
                    //                    self.commandType = ParticleSetupCommandTypeNone;
                    break;
            }
            
        }
    }
    
}





-(void)ParticleSetupConnection:(ParticleSetupConnection *)connection didUpdateState:(ParticleSetupConnectionState)state error:(NSError *)error
{
    if (error)
    {
        [self.sendCommandTimeoutTimer invalidate];
        if (self.commandCompletionBlock)
            self.commandCompletionBlock(nil, [NSError errorWithDomain:@"ParticleSetupCommManagerError" code:2002 userInfo:@{NSLocalizedDescriptionKey:error.localizedDescription}]);
//        self.commandCompletionBlock = nil;
        return;
    }
    
    switch (state) {
        case ParticleSetupConnectionStateClosed:
//            NSLog(@"Connection to spark device closed");
            [self.sendCommandTimeoutTimer invalidate];
            break;
            
        case ParticleSetupConnectionOpenTimeout:
//            NSLog(@"Opening connection to spark device timed out");
            [self.sendCommandTimeoutTimer invalidate];
            if (self.commandCompletionBlock)
            {
                self.commandCompletionBlock(nil, [NSError errorWithDomain:@"ParticleSetupCommManagerError" code:2002 userInfo:@{NSLocalizedDescriptionKey:@"Opening connection to spark device timed out"}]);
                self.commandCompletionBlock = nil;
            }
            break;
            
        case ParticleSetupConnectionStateOpened:
//            NSLog(@"Connection to spark device opened");
            if (self.commandSendBlock)
            {
                self.sendCommandTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:3.0f target:self selector:@selector(sendCommandTimeoutHandler:) userInfo:nil repeats:NO];
                self.commandSendBlock();
//                NSLog(@"Command %ld sent to spark device",(long)self.commandType);
            }
            break;
        case ParticleSetupConnectionStateError:
        case ParticleSetupConnectionStateUnknown:
            self.commandType = ParticleSetupCommandTypeNone;
            [self.sendCommandTimeoutTimer invalidate];
//            NSLog(@"Connection to spark device failed");
            if (self.commandCompletionBlock)
            {
                self.commandCompletionBlock(nil, [NSError errorWithDomain:@"ParticleSetupCommManagerError" code:2002 userInfo:@{NSLocalizedDescriptionKey:@"Connection to spark device failed"}]);
                self.commandCompletionBlock = nil;
            }
            break;
            
        default:
            break;
    }
}

/*
 -(void)writeCommandTimeoutHandler:(id)sender
 {
 self.commandType = ParticleSetupCommandTypeNone;
 //    self.connection = nil;
 
 if (self.commandCompletionBlock)
 self.commandCompletionBlock(nil,[NSError errorWithDomain:@"ParticleSetupCommManagerError" code:2002 userInfo:@{NSLocalizedDescriptionKey:@"Timeout occured while writing data to socket connection"}]);
 
 //    self.commandCompletionBlock = nil;
 }
 */



-(void)sendCommandTimeoutHandler:(id)sender
{
    
    [self.sendCommandTimeoutTimer invalidate];
    //    self.commandType = ParticleSetupCommandTypeNone;
    
    if (self.commandCompletionBlock)
        self.commandCompletionBlock(nil,[NSError errorWithDomain:@"ParticleSetupCommManagerError" code:2004 userInfo:@{NSLocalizedDescriptionKey:@"Timeout occured while waiting for response from socket"}]);
    
    self.commandCompletionBlock = nil;
}

#pragma mark TCP Socket photon soft AP protocol implementation


-(void)openConnection // and then send command (+ timeout)
{
    // TODO: add command queue
    self.connection = [[ParticleSetupConnection alloc] initWithIPAddress:kParticleSetupConnectionEndpointAddress port:kParticleSetupConnectionEndpointPort];
    self.connection.delegate = self;
}


-(BOOL)canSendCommandCallCompletionForError:(void(^)(id obj, NSError *error))completion
{
    if (self.networkNamePrefix)
    {
        if (![ParticleSetupCommManager checkParticleDeviceWifiConnection:self.networkNamePrefix])
        {
            completion(nil, [NSError errorWithDomain:@"ParticleSetupCommManangerError" code:2003 userInfo:@{NSLocalizedDescriptionKey:@"Not connected to Particle device"}]);
            return NO;
        }
    }
    
    if (self.commandType != ParticleSetupCommandTypeNone)
    {
        completion(nil, [NSError errorWithDomain:@"ParticleSetupCommManangerError" code:2005 userInfo:@{NSLocalizedDescriptionKey:@"Use a new instance of ParticleSetupCommManager per command"}]);
        return NO;
    }
    
    return YES;
}

-(void)version:(void(^)(id version, NSError *error))completion
{
    // TODO: new prototype:
    // open connection --> add semaphore to delegate
    // wait on semaphore with timeout (open socket timeout call completion)
    // do write command (+ handle completion)
    // add semaphore to receive data with timeout
    // if fails - receive data timeout
    // else calls completion with data
    // no need for NSTimers
    
    if ([self canSendCommandCallCompletionForError:completion])
    {
        __weak ParticleSetupCommManager *weakSelf = self;
        self.commandCompletionBlock = completion;
        
        self.commandSendBlock = ^{
            
            NSString *commandStr = @"version\n0\n\n";
            weakSelf.commandType = ParticleSetupCommandTypeVersion;
            [weakSelf.connection writeString:commandStr completion:^(NSError *error) {
                if ((error) && (completion))
                {
                    completion(nil, error);
                    weakSelf.commandCompletionBlock = nil;
                    //                weakSelf.commandType = ParticleSetupCommandTypeNone;
                }
            }];
        };
        // start process
        [self openConnection];
    }
    
    
}



-(void)deviceID:(void (^)(id, NSError *))completion
{
    if ([self canSendCommandCallCompletionForError:completion])
    {
        __weak ParticleSetupCommManager *weakSelf = self;
        self.commandCompletionBlock = completion;
        
        self.commandSendBlock = ^{
            
            if (weakSelf.connection.state == ParticleSetupConnectionStateOpened)
            {
                weakSelf.commandType = ParticleSetupCommandTypeDeviceID;
                NSString *commandStr = @"device-id\n0\n\n";
                
                [weakSelf.connection writeString:commandStr completion:^(NSError *error) {
                    if ((error) && (completion))
                    {
                        completion(nil, error);
                        weakSelf.commandCompletionBlock = nil;
                        //                    weakSelf.commandType = ParticleSetupCommandTypeNone;
                        
                    }
                }];
            }
            
        };
        
        [self openConnection];
    }
}



-(void)scanAP:(void(^)(id scanResponse, NSError *error))completion //NSDictionary
{
    if ([self canSendCommandCallCompletionForError:completion])
    {
        __weak ParticleSetupCommManager *weakSelf = self;
        self.commandCompletionBlock = completion;
        
        self.commandSendBlock = ^{
            
            weakSelf.commandType = ParticleSetupCommandTypeScanAP;
            NSString *commandStr = @"scan-ap\n0\n\n";
            
            [weakSelf.connection writeString:commandStr completion:^(NSError *error) {
                if ((error) && (completion))
                {
                    completion(nil, error);
                    weakSelf.commandCompletionBlock = nil;
                    //                weakSelf.commandType = ParticleSetupCommandTypeNone;
                }
            }];
            
        };
        
        [self openConnection];
        
    }
}




-(void)configureAP:(NSString *)ssid passcode:(NSString *)passcode security:(NSNumber *)securityType channel:(NSNumber *)channel completion:(void(^)(id responseCode, NSError *error))completion
{
    if ([self canSendCommandCallCompletionForError:completion])
    {
        __weak ParticleSetupCommManager *weakSelf = self;
        self.commandCompletionBlock = completion;
        
        self.commandSendBlock = ^{

            NSDictionary* requestDataDict;

            // Truncate passcode to 64 chars maximum
            NSRange stringRange = {0, MIN(passcode.length, 64)};
            // adjust the range to include dependent chars
            stringRange = [passcode rangeOfComposedCharacterSequencesForRange:stringRange];
            // Now you can create the short string
            NSString *passcodeTruncated = [passcode substringWithRange:stringRange];
            NSString *hexEncodedEncryptedPasscodeStr;
            
            if (ENCRYPT_PWD)
            {
                SecKeyRef pubKey = [ParticleSetupSecurityManager getPublicKey];
                if (pubKey != NULL)
                {
                    // encrypt it using the stored public key
                    NSData *plainTextData = [passcodeTruncated dataUsingEncoding:NSUTF8StringEncoding];
                    NSData *cipherTextData = [ParticleSetupSecurityManager encryptWithPublicKey:pubKey plainText:plainTextData];
                    if (cipherTextData != nil)
                    {
                        // encode the encrypted data to a hex string
                        hexEncodedEncryptedPasscodeStr = [ParticleSetupSecurityManager encodeDataToHexString:cipherTextData];
//                        NSLog(@"plaintext: %@\nCiphertext:\n%@",passcodeTruncated,hexEncodedEncryptedPasscodeStr);
                        requestDataDict = @{@"idx":@0, @"ssid":ssid, @"pwd":hexEncodedEncryptedPasscodeStr, @"sec":securityType, @"ch":channel};
                    }
                    else
                    {
                        completion(nil, [NSError errorWithDomain:@"ParticleSetupSecurityManager" code:2007 userInfo:@{NSLocalizedDescriptionKey:@"Failed to encrypt passcode"}]);
                        return; //?
                    }
                }
                else
                {
                    completion(nil, [NSError errorWithDomain:@"ParticleSetupSecurityManager" code:2008 userInfo:@{NSLocalizedDescriptionKey:@"Failed to retrieve device public key from keychain"}]);
                    return; //?
                }
            }
            else
            {
                // no passcode encryption // TODO: remove when encryption functional
                requestDataDict = @{@"idx":@0, @"ssid":ssid, @"pwd":passcodeTruncated, @"sec":securityType, @"ch":channel};
            }
            
            NSError *error;
            NSString *jsonString;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestDataDict
                                                               options:0
                                                                 error:&error];
            
            if (jsonData)
                jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            else
                completion(nil, [NSError errorWithDomain:@"ParticleSetupCommManangerError" code:2002 userInfo:@{NSLocalizedDescriptionKey:@"Cannot process configureAP command data to JSON"}]);
            
            NSString *commandStr = [NSString stringWithFormat:@"configure-ap\n%ld\n\n%@",(unsigned long)jsonString.length, jsonString];
            weakSelf.commandType = ParticleSetupCommandTypeConfigureAP;
            [weakSelf.connection writeString:commandStr completion:^(NSError *error) {
                if ((error) && (completion))
                {
                    completion(nil, error);
                    weakSelf.commandCompletionBlock = nil;
                    //                weakSelf.commandType = ParticleSetupCommandTypeNone;
                }
            }];
            
        };
        
        [self openConnection];
    }
    
}




-(void)setClaimCode:(NSString *)claimCode completion:(void (^)(id, NSError *))completion
{
    if ([self canSendCommandCallCompletionForError:completion])
    {
        __weak ParticleSetupCommManager *weakSelf = self;
        self.commandCompletionBlock = completion;
        
        self.commandSendBlock = ^{
            
            NSDictionary* requestDataDict;
            requestDataDict = @{@"k":@"cc",
                                @"v": claimCode};
            
            NSError *error;
            NSString *jsonString;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestDataDict
                                                               options:0
                                                                 error:&error];
            
            if (jsonData)
                jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            else
                completion(nil, [NSError errorWithDomain:@"ParticleSetupCommManangerError" code:2002 userInfo:@{NSLocalizedDescriptionKey:@"Cannot process setClaimCode command data to JSON"}]);
            
            // remove backslahes that might occur from '/' in
            jsonString = [jsonString stringByReplacingOccurrencesOfString:@"\\" withString:@""];
                          
            NSString *commandStr = [NSString stringWithFormat:@"set\n%ld\n\n%@",(unsigned long)jsonString.length, jsonString];
            weakSelf.commandType = ParticleSetupCommandTypeSet;
            [weakSelf.connection writeString:commandStr completion:^(NSError *error) {
                if ((error) && (completion))
                {
                    completion(nil, error);
                    weakSelf.commandCompletionBlock = nil;
                }
            }];
            
        };
        
        [self openConnection];
    }
}

-(void)connectAP:(void(^)(id responseCode, NSError *error))completion
{
    if ([self canSendCommandCallCompletionForError:completion])
    {
        __weak ParticleSetupCommManager *weakSelf = self;
        self.commandCompletionBlock = completion;
        
        self.commandSendBlock = ^{
            
            NSDictionary* requestDataDict = @{@"idx":@0};
            NSError *error;
            NSString *jsonString;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestDataDict
                                                               options:0
                                                                 error:&error];
            
            if (jsonData)
            {
                jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                
                NSString *commandStr = [NSString stringWithFormat:@"connect-ap\n%ld\n\n%@",(unsigned long)jsonString.length, jsonString];
                weakSelf.commandType = ParticleSetupCommandTypeConnectAP;
                [weakSelf.connection writeString:commandStr completion:^(NSError *error) {
                    if ((error) && (completion))
                    {
                        completion(nil, error);
                        weakSelf.commandCompletionBlock = nil;
                        //                weakSelf.commandType = ParticleSetupCommandTypeNone;
                    }
                }];
            }
            else
            {
                completion(nil, [NSError errorWithDomain:@"ParticleSetupCommManangerError" code:2002 userInfo:@{NSLocalizedDescriptionKey:@"Cannot process connectAP command data to JSON"}]);
            }
            
        };
        
        [self openConnection];
    }
    
}


-(void)publicKey:(void (^)(id, NSError *))completion
{
    if ([self canSendCommandCallCompletionForError:completion])
    {
        __weak ParticleSetupCommManager *weakSelf = self;
        self.commandCompletionBlock = completion;
        
        self.commandSendBlock = ^{
            
            weakSelf.commandType = ParticleSetupCommandTypePublicKey;
            NSString *commandStr = @"public-key\n0\n\n";
            
            [weakSelf.connection writeString:commandStr completion:^(NSError *error) {
                if ((error) && (completion))
                {
                    completion(nil, error);
                    weakSelf.commandCompletionBlock = nil;

                }
            }];
            
        };
        
        [self openConnection];
        
    }

}

-(void)dealloc
{
//    NSLog(@"ParticleSetupCommManager %@ dealloced!",self);
    
    self.commandSendBlock = nil;
    self.commandCompletionBlock = nil;
    self.connection = nil;
    
}



@end
