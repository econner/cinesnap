//
//  ViewController.m
//  Cinesnap
//
//  Created by Eric Conner on 9/1/13.
//  Copyright (c) 2013 Eric Conner. All rights reserved.
//

#import "ViewController.h"
#import "AVCamRecorder.h"

@interface ViewController (AVCamCaptureManagerDelegate) <AVCamCaptureManagerDelegate>
@end

@implementation ViewController

- (void)viewDidLoad
{
    UILongPressGestureRecognizer *longPress =
    [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                            action:@selector(holdAction:)];
    [self.videoPreviewView addGestureRecognizer:longPress];
    
    [super viewDidLoad];
}

// Create and add the video recording preview window.  In auto layout mode,
// views do not have a frame size until after viewDidLoad is called so we
// must setup the preview after the subviews have already been laid out.
-(void)viewDidLayoutSubviews
{
    if ([self captureManager] == nil) {
        AVCamCaptureManager *manager = [[AVCamCaptureManager alloc] init];
        self.captureManager = manager;
        [self.captureManager setDelegate:self];
        
        if ([[self captureManager] setupSession]) {
            // Create video preview layer and add it to the UI
            AVCaptureVideoPreviewLayer *newCaptureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:[[self captureManager] session]];
            UIView *view = [self videoPreviewView];
            
            CALayer *viewLayer = [view layer];
            [viewLayer setMasksToBounds:YES];
            
            CGRect bounds = [view bounds];
            [newCaptureVideoPreviewLayer setFrame:bounds];
            
            [newCaptureVideoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
            
            [viewLayer insertSublayer:newCaptureVideoPreviewLayer below:[[viewLayer sublayers] objectAtIndex:0]];
            
            self.captureVideoPreviewLayer = newCaptureVideoPreviewLayer;
            
            NSLog(@"Finished setting capture video preview layer.");
            
            // Start the session. This is done asychronously since -startRunning doesn't return until the session is running.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [[[self captureManager] session] startRunning];
                NSLog(@"Starting capture manager session.");
            });
        }
    }
}

- (void)holdAction:(UILongPressGestureRecognizer *)holdRecognizer
{
    if (holdRecognizer.state == UIGestureRecognizerStateBegan) {
        if (![[self.captureManager recorder] isRecording])
            [self.captureManager startRecording];
    } else if (holdRecognizer.state == UIGestureRecognizerStateEnded) {
        if ([[self.captureManager recorder] isRecording])
            [self.captureManager stopRecording];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

@implementation ViewController (AVCamCaptureManagerDelegate)

- (void)captureManager:(AVCamCaptureManager *)captureManager didFailWithError:(NSError *)error
{
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^(void) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[error localizedDescription]
                                                            message:[error localizedFailureReason]
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"OK", @"OK button title")
                                                  otherButtonTitles:nil];
        [alertView show];
    });
}

@end
