//
//  VideoPreviewViewController.m
//  Cinesnap
//
//  Created by Eric Conner on 9/22/13.
//  Copyright (c) 2013 Eric Conner. All rights reserved.
//

#import "VideoPreviewViewController.h"

@interface VideoPreviewViewController ()

@end

@implementation VideoPreviewViewController

-(id)initWithVideoURL:(NSURL *)aUrl
{
    self = [super init];
    if (self) {
        self.asset = [AVAsset assetWithURL:aUrl];
        NSLog(@"Asset length is: %lld", [self.asset duration].value);
        self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
        self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        
        CGRect viewRect = CGRectMake(0, 40, 320, 320);
        self.videoPreviewView = [[UIView alloc] initWithFrame:viewRect];
        self.videoPreviewView.backgroundColor = [UIColor blueColor];
        
        [self.playerLayer setFrame:viewRect];
        [[self.videoPreviewView layer] addSublayer:self.playerLayer];
        
        [self.view addSubview:self.videoPreviewView];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    NSLog(@"DID GET HERE.");
    
    NSLog(@"Player time is at: %lld", [self.player currentTime].value);
    [self.player play];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
}

@end
