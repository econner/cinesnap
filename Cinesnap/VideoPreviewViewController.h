//
//  VideoPreviewViewController.h
//  Cinesnap
//
//  Created by Eric Conner on 9/22/13.
//  Copyright (c) 2013 Eric Conner. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "AVCamCaptureManager.h"
#import "AudioSpeedManager.h"

@interface VideoPreviewViewController : UIViewController

@property (strong, nonatomic) UIView *videoPreviewView;
@property (strong, nonatomic) AVPlayer *player;
@property (strong, nonatomic) AVPlayerLayer *playerLayer;
@property (strong, nonatomic) AVAsset *asset;
@property (strong, nonatomic) AVPlayerItem *playerItem;
@property (strong, nonatomic) AudioSpeedManager *audioManager;

-(id)initWithVideoURL:(NSURL *)aUrl;

@end
