//
//  VideoPreviewViewController.m
//  Cinesnap
//
//  Created by Eric Conner on 9/22/13.
//  Copyright (c) 2013 Eric Conner. All rights reserved.
//

#import "VideoPreviewViewController.h"
#import "UIColor+FlatUI.h"
#import "UISlider+FlatUI.h"

@interface VideoPreviewViewController ()
@end

@implementation VideoPreviewViewController

-(id)initWithVideoURL:(NSURL *)aUrl
{
    self = [super init];
    if (self) {
        // Setup audio manager to control speed of audio recording.
        self.audioManager = [[AudioSpeedManager alloc] init];
        
        self.asset = [AVAsset assetWithURL:aUrl];
        NSLog(@"Asset length is: %lld", [self.asset duration].value);
        self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
        self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];

        CGRect viewRect = CGRectMake(0, 0, 320, 320);
        self.videoPreviewView = [[UIView alloc] initWithFrame:viewRect];
        self.videoPreviewView.backgroundColor = [UIColor blueColor];

        [self.playerLayer setFrame:viewRect];
        [[self.videoPreviewView layer] addSublayer:self.playerLayer];
        
        self.slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 400, 320, 100)];

        [self.view addSubview:self.videoPreviewView];
        [self.view insertSubview:self.slider belowSubview:self.videoPreviewView];
    }
    return self;
}

- (void)onSliderValueChange:(UISlider *)slider {
    self.player.rate = [slider value] * 2.0f;
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem *p = [notification object];
    [p seekToTime:kCMTimeZero];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // TODO: make this player rate configurable by user
    double videoScaleFactor = 0.5f;

    
    [self.player play];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:[self.player currentItem]];
    
    [self.slider configureFlatSliderWithTrackColor:[UIColor silverColor]
                                     progressColor:[UIColor alizarinColor]
                                        thumbColor:[UIColor pomegranateColor]];
    [self.slider setValue:0.5f];
    [self.slider addTarget:self action:@selector(onSliderValueChange:) forControlEvents:UIControlEventValueChanged];
    
//    
//    [self scaleAndWriteVideoToPhotosAlbum:videoScaleFactor];
//}
//
//- (void) scaleAndWriteVideoToPhotosAlbum:(float) videoScaleFactor
//{
    NSURL *videoAssetUrl = [(AVURLAsset *)self.asset URL];
    AVURLAsset* videoAsset = [[AVURLAsset alloc] initWithURL:videoAssetUrl options:NULL];
    CMTime videoDuration = videoAsset.duration;
    CMTime newVideoDuration = CMTimeMake(videoDuration.value * videoScaleFactor, videoDuration.timescale);

    AVAssetTrack *videoAssetTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];

    AVAssetTrack *audioAssetTrack = [[videoAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    NSURL* transformedAudioUrl = [self.audioManager transformAudioTrack:audioAssetTrack byFactor:videoScaleFactor];
    AVURLAsset* transformedAudioAsset = [[AVURLAsset alloc] initWithURL:transformedAudioUrl options:NULL];
    AVAssetTrack *transformedAudioAssetTrack = [[transformedAudioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];

    // Create mutable composition
    AVMutableComposition *mixComposition = [AVMutableComposition composition];

    AVMutableCompositionTrack *compositionVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                   preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *compositionAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                   preferredTrackID:kCMPersistentTrackID_Invalid];

    NSError *videoInsertError = nil;
    BOOL videoInsertResult = [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoDuration)
                                                            ofTrack:videoAssetTrack
                                                             atTime:kCMTimeZero
                                                              error:&videoInsertError];
    if (!videoInsertResult || nil != videoInsertError) {
        // TODO: handle error
        return;
    }

    [compositionVideoTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, videoDuration)
                               toDuration:newVideoDuration];

    CMTime newAudioDuration = [compositionVideoTrack.asset duration];
    NSError *audioInsertError = nil;

    BOOL audioInsertResult = [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, newAudioDuration)
                                                        ofTrack:transformedAudioAssetTrack
                                                         atTime:kCMTimeZero
                                                          error:&audioInsertError];
    if (!audioInsertResult || nil != audioInsertError) {
        // TODO: handle error
        return;
    }

    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:mixComposition
                                                                           presetName:AVAssetExportPresetHighestQuality];
    NSURL *exportUrl = [NSURL fileURLWithPath:[AVCamCaptureManager generateTempFilePath:@".mov"]];
    [exportSession setOutputURL:exportUrl];
    [exportSession setOutputFileType:AVFileTypeQuickTimeMovie];
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^ {
        [library writeVideoAtPathToSavedPhotosAlbum:exportUrl
                                    completionBlock:^(NSURL *assetURL, NSError *error) {
//                                        if (error) {
//                                            if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
//                                                [[self delegate] captureManager:self didFailWithError:error];
//                                            }
//                                        }
//
//                                        if ([[UIDevice currentDevice] isMultitaskingSupported]) {
//                                            [[UIApplication sharedApplication] endBackgroundTask:[self backgroundRecordingID]];
//                                        }
//
//                                        if ([[self delegate] respondsToSelector:@selector(captureManagerRecordingFinished:)]) {
//                                            [[self delegate] captureManagerRecordingFinished:self];
//                                        }
                                        [[NSFileManager defaultManager] removeItemAtURL:videoAssetUrl error:&error];
                                        [[NSFileManager defaultManager] removeItemAtURL:exportUrl error:&error];
      }];
    }];


}

@end
