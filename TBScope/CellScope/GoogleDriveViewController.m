//
//  GoogleDriveViewController.m
//  CellScopeLoa
//
//  Created by UC Berkeley Fletcher Lab on 10/20/13.
//  Copyright (c) 2013 UC Berkeley Fletcher Lab. All rights reserved.
//

#import "GoogleDriveViewController.h"
#import "GoogleDriveService.h"

//#import "ViewController.h"

static NSString *const kKeychainItemName = @"CellScope";
static NSString *const kClientID = @"822665295778.apps.googleusercontent.com";
static NSString *const kClientSecret = @"mbDjzu2hKDW23QpNJXe_0Ukd";

//TODO: needs to be merged with GoogleDriveSync/context model (this should just be thin UI)

@implementation GoogleDriveViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    
}

- (void)viewDidAppear:(BOOL)animated
{
    
    //if logged in, display current username and the logout button, else, load the login screen
    if ([[[GoogleDriveService alloc] init] isLoggedIn]) {
        self.usernameLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Logged in as: %@", nil),[[GoogleDriveSync sharedGDS] userEmail]];
        [self.loginButton setTitle:NSLocalizedString(@"Log Out",nil) forState:UIControlStateNormal];
    }
    else
    {
        self.usernameLabel.text = NSLocalizedString(@"Not logged in to Google Drive",nil);
        [self.loginButton setTitle:NSLocalizedString(@"Log In",nil) forState:UIControlStateNormal];
    }
}

- (IBAction)logInOut:(id)sender
{
    
    if ([[[GoogleDriveService alloc] init] isLoggedIn]) {
        [GTMOAuth2ViewControllerTouch removeAuthFromKeychainForName:@"CellScope"];
        [GTMOAuth2ViewControllerTouch revokeTokenForGoogleAuthentication:[[[GoogleDriveSync sharedGDS] driveService] authorizer]];
        [[[GoogleDriveSync sharedGDS] driveService] setAuthorizer:nil];
        [self viewDidAppear:NO];
    }
    else
    {
        
        [self.navigationController pushViewController:[self createAuthController] animated:YES];
        
    }
    
 }


// Creates the auth controller for authorizing access to Google Drive.
- (GTMOAuth2ViewControllerTouch *)createAuthController
{
    GTMOAuth2ViewControllerTouch *authController;
    authController = [[GTMOAuth2ViewControllerTouch alloc] initWithScope:kGTLAuthScopeDriveFile
                                                                clientID:kClientID
                                                            clientSecret:kClientSecret
                                                        keychainItemName:kKeychainItemName
                                                                delegate:self
                                                        finishedSelector:@selector(viewController:finishedWithAuth:error:)];
    return authController;
}

// Handle completion of the authorization process, and updates the Drive service
// with the new credentials.
- (void)viewController:(GTMOAuth2ViewControllerTouch *)viewController
      finishedWithAuth:(GTMOAuth2Authentication *)authResult
                 error:(NSError *)error
{
    if (error != nil)
    {
        
        UIAlertView *alert;
        alert = [[UIAlertView alloc] initWithTitle: NSLocalizedString(@"Authentication Error",nil)
                                           message: error.localizedDescription
                                          delegate: nil
                                 cancelButtonTitle: NSLocalizedString(@"OK",nil)
                                 otherButtonTitles: nil];
        [alert show];
        
        [[[GoogleDriveSync sharedGDS] driveService] setAuthorizer:nil];
        
    }
    else
    {
        
        [[[GoogleDriveSync sharedGDS] driveService] setAuthorizer:authResult];
        [self viewDidAppear:NO];
    }
}

@end
