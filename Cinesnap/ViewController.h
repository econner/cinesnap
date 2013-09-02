//
//  ViewController.h
//  Cinesnap
//
//  Created by Eric Conner on 9/1/13.
//  Copyright (c) 2013 Eric Conner. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "AVCamCaptureManager.h"

@interface ViewController : UIViewController <UIImagePickerControllerDelegate,
                                              UINavigationControllerDelegate>

@property (strong, nonatomic) AVCamCaptureManager *captureManager;
@property (strong, nonatomic) IBOutlet UIView *videoPreviewView;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *cameraToggleButton;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *recordButton;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *stillButton;
@property (strong, nonatomic) IBOutlet UILabel *focusModeLabel;

#pragma mark Toolbar Actions
- (IBAction)toggleRecording:(id)sender;
- (IBAction)captureStillImage:(id)sender;
- (IBAction)toggleCamera:(id)sender;

@end
