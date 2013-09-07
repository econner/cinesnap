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
@property (strong, nonatomic) UIView *videoCaptureView;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;

@end
