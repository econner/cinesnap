/*
     File: AVCamCaptureManager.m
 Abstract: Uses the AVCapture classes to capture video and still images.
  Version: 1.2
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2011 Apple Inc. All Rights Reserved.
 
 */

#import "AVCamCaptureManager.h"
#import "AVCamRecorder.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/CGImageProperties.h>
#import "Dirac.h"
#import <AudioToolbox/AudioToolbox.h>
#import "EAFWrite.h"


@interface AVCamCaptureManager (RecorderDelegate) <AVCamRecorderDelegate>
@end


#pragma mark -
@interface AVCamCaptureManager (InternalUtilityMethods)
- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition)position;
- (AVCaptureDevice *) frontFacingCamera;
- (AVCaptureDevice *) backFacingCamera;
- (AVCaptureDevice *) audioDevice;
- (NSURL *) tempFileURL;
- (void) removeFile:(NSURL *)outputFileURL;
- (void) copyFileToDocuments:(NSURL *)fileURL;
@end


#pragma mark -
@implementation AVCamCaptureManager

@synthesize session;
@synthesize orientation;
@synthesize videoInput;
@synthesize audioInput;
@synthesize recorder;
@synthesize deviceConnectedObserver;
@synthesize deviceDisconnectedObserver;
@synthesize backgroundRecordingID;
@synthesize delegate;

- (id) init
{
    self = [super init];
    if (self != nil) {
		__block id weakSelf = self;
        void (^deviceConnectedBlock)(NSNotification *) = ^(NSNotification *notification) {
			AVCaptureDevice *device = [notification object];
			
			BOOL sessionHasDeviceWithMatchingMediaType = NO;
			NSString *deviceMediaType = nil;
			if ([device hasMediaType:AVMediaTypeAudio])
                deviceMediaType = AVMediaTypeAudio;
			else if ([device hasMediaType:AVMediaTypeVideo])
                deviceMediaType = AVMediaTypeVideo;
			
			if (deviceMediaType != nil) {
				for (AVCaptureDeviceInput *input in [session inputs])
				{
					if ([[input device] hasMediaType:deviceMediaType]) {
						sessionHasDeviceWithMatchingMediaType = YES;
						break;
					}
				}
				
				if (!sessionHasDeviceWithMatchingMediaType) {
					NSError	*error;
					AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
					if ([session canAddInput:input])
						[session addInput:input];
				}				
			}
            
			if ([delegate respondsToSelector:@selector(captureManagerDeviceConfigurationChanged:)]) {
				[delegate captureManagerDeviceConfigurationChanged:self];
			}			
        };
        void (^deviceDisconnectedBlock)(NSNotification *) = ^(NSNotification *notification) {
			AVCaptureDevice *device = [notification object];
			
			if ([device hasMediaType:AVMediaTypeAudio]) {
				[session removeInput:[weakSelf audioInput]];
				[weakSelf setAudioInput:nil];
			}
			else if ([device hasMediaType:AVMediaTypeVideo]) {
				[session removeInput:[weakSelf videoInput]];
				[weakSelf setVideoInput:nil];
			}
			
			if ([delegate respondsToSelector:@selector(captureManagerDeviceConfigurationChanged:)]) {
				[delegate captureManagerDeviceConfigurationChanged:self];
			}			
        };
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [self setDeviceConnectedObserver:[notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification object:nil queue:nil usingBlock:deviceConnectedBlock]];
        [self setDeviceDisconnectedObserver:[notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification object:nil queue:nil usingBlock:deviceDisconnectedBlock]];
		[[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
		[notificationCenter addObserver:self selector:@selector(deviceOrientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
		orientation = AVCaptureVideoOrientationPortrait;
    }
    
    return self;
}

- (BOOL) setupSession
{
    BOOL success = NO;
    
	// Set torch and flash mode to auto
	if ([[self backFacingCamera] hasFlash]) {
		if ([[self backFacingCamera] lockForConfiguration:nil]) {
			if ([[self backFacingCamera] isFlashModeSupported:AVCaptureFlashModeAuto]) {
				[[self backFacingCamera] setFlashMode:AVCaptureFlashModeAuto];
			}
			[[self backFacingCamera] unlockForConfiguration];
		}
	}
	if ([[self backFacingCamera] hasTorch]) {
		if ([[self backFacingCamera] lockForConfiguration:nil]) {
			if ([[self backFacingCamera] isTorchModeSupported:AVCaptureTorchModeAuto]) {
				[[self backFacingCamera] setTorchMode:AVCaptureTorchModeAuto];
			}
			[[self backFacingCamera] unlockForConfiguration];
		}
	}
	
    // Init the device inputs
    AVCaptureDeviceInput *newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self backFacingCamera] error:nil];
    AVCaptureDeviceInput *newAudioInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self audioDevice] error:nil];
    
	
    // Setup the still image file output
    AVCaptureStillImageOutput *newStillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                    AVVideoCodecJPEG, AVVideoCodecKey,
                                    nil];
    [newStillImageOutput setOutputSettings:outputSettings];
    
    
    // Create session (use default AVCaptureSessionPresetHigh)
    AVCaptureSession *newCaptureSession = [[AVCaptureSession alloc] init];
    
    
    // Add inputs and output to the capture session
    if ([newCaptureSession canAddInput:newVideoInput]) {
        [newCaptureSession addInput:newVideoInput];
    }
    if ([newCaptureSession canAddInput:newAudioInput]) {
        [newCaptureSession addInput:newAudioInput];
    }
    
    [self setVideoInput:newVideoInput];
    [self setAudioInput:newAudioInput];
    [self setSession:newCaptureSession];
    
	// Set up the movie file output
    NSURL *outputFileURL = [self tempFileURL];
    AVCamRecorder *newRecorder = [[AVCamRecorder alloc] initWithSession:[self session] outputFileURL:outputFileURL];
    [newRecorder setDelegate:self];
	
	// Send an error to the delegate if video recording is unavailable
	if (![newRecorder recordsVideo] && [newRecorder recordsAudio]) {
		NSString *localizedDescription = NSLocalizedString(@"Video recording unavailable", @"Video recording unavailable description");
		NSString *localizedFailureReason = NSLocalizedString(@"Movies recorded on this device will only contain audio. They will be accessible through iTunes file sharing.", @"Video recording unavailable failure reason");
		NSDictionary *errorDict = [NSDictionary dictionaryWithObjectsAndKeys:
								   localizedDescription, NSLocalizedDescriptionKey, 
								   localizedFailureReason, NSLocalizedFailureReasonErrorKey, 
								   nil];
		NSError *noVideoError = [NSError errorWithDomain:@"AVCam" code:0 userInfo:errorDict];
		if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
			[[self delegate] captureManager:self didFailWithError:noVideoError];
		}
	}
	
	[self setRecorder:newRecorder];
	NSLog(@"Setup new recorder");
    success = YES;
    
    return success;
}

- (void) startRecording
{
    if ([[UIDevice currentDevice] isMultitaskingSupported]) {
        // Setup background task. This is needed because the captureOutput:didFinishRecordingToOutputFileAtURL: callback is not received until AVCam returns
		// to the foreground unless you request background execution time. This also ensures that there will be time to write the file to the assets library
		// when AVCam is backgrounded. To conclude this background execution, -endBackgroundTask is called in -recorder:recordingDidFinishToOutputFileURL:error:
		// after the recorded file has been saved.
        [self setBackgroundRecordingID:[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}]];
    }
    
    [self removeFile:[[self recorder] outputFileURL]];
    [[self recorder] startRecordingWithOrientation:orientation];
}

- (void) stopRecording
{
    [[self recorder] stopRecording];
}

// Toggle between the front and back camera, if both are present.
- (BOOL) toggleCamera
{
    BOOL success = NO;
    
    if ([self cameraCount] > 1) {
        NSError *error;
        AVCaptureDeviceInput *newVideoInput;
        AVCaptureDevicePosition position = [[videoInput device] position];
        
        if (position == AVCaptureDevicePositionBack)
            newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self frontFacingCamera] error:&error];
        else if (position == AVCaptureDevicePositionFront)
            newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self backFacingCamera] error:&error];
        else
            goto bail;
        
        if (newVideoInput != nil) {
            [[self session] beginConfiguration];
            [[self session] removeInput:[self videoInput]];
            if ([[self session] canAddInput:newVideoInput]) {
                [[self session] addInput:newVideoInput];
                [self setVideoInput:newVideoInput];
            } else {
                [[self session] addInput:[self videoInput]];
            }
            [[self session] commitConfiguration];
            success = YES;
        } else if (error) {
            if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
                [[self delegate] captureManager:self didFailWithError:error];
            }
        }
    }
    
bail:
    return success;
}


#pragma mark Device Counts
- (NSUInteger) cameraCount
{
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
}

- (NSUInteger) micCount
{
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] count];
}


#pragma mark Camera Properties
// Perform an auto focus at the specified point. The focus mode will automatically change to locked once the auto focus is complete.
- (void) autoFocusAtPoint:(CGPoint)point
{
    AVCaptureDevice *device = [[self videoInput] device];
    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setFocusPointOfInterest:point];
            [device setFocusMode:AVCaptureFocusModeAutoFocus];
            [device unlockForConfiguration];
        } else {
            if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
                [[self delegate] captureManager:self didFailWithError:error];
            }
        }        
    }
}

// Switch to continuous auto focus mode at the specified point
- (void) continuousFocusAtPoint:(CGPoint)point
{
    AVCaptureDevice *device = [[self videoInput] device];
	
    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
		NSError *error;
		if ([device lockForConfiguration:&error]) {
			[device setFocusPointOfInterest:point];
			[device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
			[device unlockForConfiguration];
		} else {
			if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
                [[self delegate] captureManager:self didFailWithError:error];
			}
		}
	}
}

@end


#pragma mark -
@implementation AVCamCaptureManager (InternalUtilityMethods)

// Keep track of current device orientation so it can be applied to movie recordings and still image captures
- (void)deviceOrientationDidChange
{	
	UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    
	if (deviceOrientation == UIDeviceOrientationPortrait)
		orientation = AVCaptureVideoOrientationPortrait;
	else if (deviceOrientation == UIDeviceOrientationPortraitUpsideDown)
		orientation = AVCaptureVideoOrientationPortraitUpsideDown;
	
	// AVCapture and UIDevice have opposite meanings for landscape left and right (AVCapture orientation is the same as UIInterfaceOrientation)
	else if (deviceOrientation == UIDeviceOrientationLandscapeLeft)
		orientation = AVCaptureVideoOrientationLandscapeRight;
	else if (deviceOrientation == UIDeviceOrientationLandscapeRight)
		orientation = AVCaptureVideoOrientationLandscapeLeft;
	
	// Ignore device orientations for which there is no corresponding still image orientation (e.g. UIDeviceOrientationFaceUp)
}

// Find a camera with the specificed AVCaptureDevicePosition, returning nil if one is not found
- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}

// Find a front facing camera, returning nil if one is not found
- (AVCaptureDevice *) frontFacingCamera
{
    return [self cameraWithPosition:AVCaptureDevicePositionFront];
}

// Find a back facing camera, returning nil if one is not found
- (AVCaptureDevice *) backFacingCamera
{
    return [self cameraWithPosition:AVCaptureDevicePositionBack];
}

// Find and return an audio device, returning nil if one is not found
- (AVCaptureDevice *) audioDevice
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if ([devices count] > 0) {
        return [devices objectAtIndex:0];
    }
    return nil;
}

- (NSURL *) tempFileURL
{
    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), @"output.mov"]];
}

- (void) removeFile:(NSURL *)fileURL
{
    NSString *filePath = [fileURL path];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        NSError *error;
        if ([fileManager removeItemAtPath:filePath error:&error] == NO) {
            if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
                [[self delegate] captureManager:self didFailWithError:error];
            }            
        }
    }
}

- (void) copyFileToDocuments:(NSURL *)fileURL
{
	NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
	NSString *destinationPath = [documentsDirectory stringByAppendingFormat:@"/output_%@.mov", [dateFormatter stringFromDate:[NSDate date]]];

	NSError	*error;
	if (![[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:destinationPath] error:&error]) {
		if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
			[[self delegate] captureManager:self didFailWithError:error];
		}
	}
}	

@end


#pragma mark -
@implementation AVCamCaptureManager (RecorderDelegate)

-(void)recorderRecordingDidBegin:(AVCamRecorder *)recorder
{
    if ([[self delegate] respondsToSelector:@selector(captureManagerRecordingBegan:)]) {
        [[self delegate] captureManagerRecordingBegan:self];
    }
}

+(NSString *)generateTempFilePath:(NSString *)extension
{
    NSString *tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tempdir.XXXXXX"];
    const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
    strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
    
    char *result = mkdtemp(tempDirectoryNameCString);
    if (!result)
    {
        // handle directory creation failure
    }
    
    NSString *tempDirectoryPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempDirectoryNameCString
                                                                                              length:strlen(result)];
    free(tempDirectoryNameCString);
    
    NSString *filename = [@"temp" stringByAppendingString:extension];
    return [tempDirectoryPath stringByAppendingPathComponent:filename];
}

/*
 This is the callback function that supplies data from the input stream/file whenever needed.
 It should be implemented in your software by a routine that gets data from the input/buffers.
 The read requests are *always* consecutive, ie. the routine will never have to supply data out
 of order.
 */
long myReadData(float **chdata, long numFrames, void *userData)
{
	if (!chdata)
        return 0;
    
//    NSLog(@"GOT HERE");
	
    // The userData parameter can be used to pass information about the caller (for example, "self") to
	// the callback so it can manage its audio streams.
	AVCamCaptureManager *Self = (__bridge AVCamCaptureManager*)userData;
	if (!Self)
        return 0;
        
    OSStatus err = [Self.reader readFloatsConsecutive:numFrames intoArray:chdata];
    
    for (long v = 0; v < 1; v++) {
		for(long f = 0; f < numFrames; f++) {
//            printf("%f", chdata[v][f]);
        }
	}

	
    return err;
}

void DeallocateAudioBuffer(float **audio, int numChannels)
{
	if (!audio) return;
	for (long v = 0; v < numChannels; v++) {
		if (audio[v]) {
			free(audio[v]);
			audio[v] = NULL;
		}
	}
	free(audio);
	audio = NULL;
}
// ---------------------------------------------------------------------------------------------------------------------------

float **AllocateAudioBuffer(int numChannels, int numFrames)
{
	// Allocate buffer for output
	float **audio = (float**)malloc(numChannels*sizeof(float*));
	if (!audio) return NULL;
	memset(audio, 0, numChannels*sizeof(float*));
	for (long v = 0; v < numChannels; v++) {
		audio[v] = (float*)malloc(numFrames*sizeof(float));
		if (!audio[v]) {
			DeallocateAudioBuffer(audio, numChannels);
			return NULL;
		}
		else memset(audio[v], 0, numFrames*sizeof(float));
	}
	return audio;
}

-(NSURL *)transformAudioTrack:(AVAssetTrack *)audioAssetTrack
{    
    long numChannels = 1;		// DIRAC LE allows mono only
	float sampleRate = 44100.;

    // Create output file (overwrite if exists)
    EAFWrite *writer = [[EAFWrite alloc] init];
    NSURL *outputUrl = [NSURL fileURLWithPath:[AVCamCaptureManager generateTempFilePath:@".aif"]];
	[writer openFileForWrite:outputUrl sr:sampleRate channels:numChannels wordLength:16 type:kAudioFileAIFFType];
    
    
    // Open up audio file.
    self.reader = [[EAFRead alloc] init];
    [self.reader fromAudioAssetTrack:audioAssetTrack];
    
	// DIRAC parameters
	// Here we set our time an pitch manipulation values
	float time      = 0.5;                 // 115% length
	float pitch     = pow(2., 0./12.);     // pitch shift (0 semitones)
	float formant   = pow(2., 0./12.);    // formant shift (0 semitones). Note formants are reciprocal to pitch in natural transposing
    
    // First we set up DIRAC to process numChannels of audio at 44.1kHz
	// N.b.: The fastest option is kDiracLambdaPreview / kDiracQualityPreview, best is kDiracLambda3, kDiracQualityBest
	// The probably best *default* option for general purpose signals is kDiracLambda3 / kDiracQualityGood
	void *dirac = DiracCreate(kDiracLambdaPreview, kDiracQualityPreview, numChannels, sampleRate, &myReadData, (__bridge void*)self);
    
    // Pass the values to our DIRAC instance
	DiracSetProperty(kDiracPropertyTimeFactor, time, dirac);
	DiracSetProperty(kDiracPropertyPitchFactor, pitch, dirac);
	DiracSetProperty(kDiracPropertyFormantFactor, formant, dirac);
	
	// upshifting pitch will be slower, so in this case we'll enable constant CPU pitch shifting
	if (pitch > 1.0)
		DiracSetProperty(kDiracPropertyUseConstantCpuPitchShift, 1, dirac);
    
	// Print our settings to the console
	DiracPrintSettings(dirac);
        
    // This is an arbitrary number of frames per call. Change as you see fit
	long numFrames = 8192;
    float totalNumFrames = time * CMTimeGetSeconds([audioAssetTrack asset].duration) * sampleRate;
    float remainingFramesToWrite = totalNumFrames;
    
    // Allocate buffer for output
    float **audio = AllocateAudioBuffer(numChannels, numFrames);
    
    // MAIN PROCESSING LOOP STARTS HERE
	for (int i = 0;;i++) {
		// Call the DIRAC process function with current time and pitch settings
		// Returns: the number of frames in audio
		long ret = DiracProcess(audio, numFrames, dirac);
		
        // Write the data to the output file
        float framesToWrite = numFrames;
        if(remainingFramesToWrite <= numFrames) {
            framesToWrite = remainingFramesToWrite;
        }
        
        OSStatus err = [writer writeFloats:framesToWrite fromArray:audio];
        
        remainingFramesToWrite -= framesToWrite;
        
        // As soon as we've written enough frames we exit the main loop
		if (ret <= 0) {
            break; 
        }
    }
    // Free buffer for output.
    DeallocateAudioBuffer(audio, numChannels);
	
	// Destroy DIRAC instance.
	DiracDestroy( dirac );
	
	// Done!
	NSLog(@"\nDone!");
    
    [self.reader closeFile];
	[writer closeFile]; // important - flushes data to file
    
    return outputUrl;
}


-(void)recorder:(AVCamRecorder *)recorder recordingDidFinishToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error
{
	if ([[self recorder] recordsAudio] && ![[self recorder] recordsVideo]) {
		// If the file was created on a device that doesn't support video recording, it can't be saved to the assets 
		// library. Instead, save it in the app's Documents directory, whence it can be copied from the device via
		// iTunes file sharing.
		[self copyFileToDocuments:outputFileURL];

		if ([[UIDevice currentDevice] isMultitaskingSupported]) {
			[[UIApplication sharedApplication] endBackgroundTask:[self backgroundRecordingID]];
		}		

		if ([[self delegate] respondsToSelector:@selector(captureManagerRecordingFinished:)]) {
			[[self delegate] captureManagerRecordingFinished:self];
		}
	} else {	

        AVURLAsset* videoAsset = [[AVURLAsset alloc] initWithURL:outputFileURL options:NULL];
        
        AVAssetTrack *videoAssetTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
        
        // Scale the audio track by the appropriate factor.
        AVAssetTrack *audioAssetTrack = [[videoAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        
        NSURL* transformedAudioUrl = [self transformAudioTrack:audioAssetTrack];
        NSLog(@"Returned URL: %@", transformedAudioUrl);
        AVURLAsset* transformedAudioAsset = [[AVURLAsset alloc] initWithURL:transformedAudioUrl options:NULL];
        AVAssetTrack *transformedAudioAssetTrack = [[transformedAudioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        CMTime audioDuration = transformedAudioAsset.duration;
        
        CMTimeShow(audioDuration);
        
        CMTime videoDuration = videoAsset.duration;
        
        // Create mutable composition
        AVMutableComposition *mixComposition = [AVMutableComposition composition];
        
        AVMutableCompositionTrack *compositionVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                       preferredTrackID:kCMPersistentTrackID_Invalid];
        AVMutableCompositionTrack *compositionAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                       preferredTrackID:kCMPersistentTrackID_Invalid];
        
        //slow down whole video by 2.0
        double videoScaleFactor = 0.5;
        CMTime newVideoDuration = CMTimeMake(videoDuration.value * videoScaleFactor, videoDuration.timescale);
        
        NSError *videoInsertError = nil;
        BOOL videoInsertResult = [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoDuration)
                                                                ofTrack:videoAssetTrack
                                                                 atTime:kCMTimeZero
                                                                  error:&videoInsertError];

        if (!videoInsertResult || nil != videoInsertError) {
            //handle error
            return;
        }
        
        [compositionVideoTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, videoDuration)
                                   toDuration:newVideoDuration];
        
        CMTime newAudioDuration = [compositionVideoTrack.asset duration];
        NSLog(@"Audio duration val to write: %lld at timescale %d", newAudioDuration.value, newAudioDuration.timescale);
        NSLog(@"Audio duration val: %lld at timescale %d", audioDuration.value, audioDuration.timescale);
        
        NSError *audioInsertError = nil;
        BOOL audioInsertResult = [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, newAudioDuration)
                                                                ofTrack:transformedAudioAssetTrack
                                                                 atTime:kCMTimeZero
                                                                  error:&audioInsertError];
        
        // Fix the orientation of the video by making the preferred transform (rotate 90 degrees) and re-scaling
        AVMutableVideoCompositionLayerInstruction *layerInstruction =
            [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoAssetTrack];
        CGFloat scaleRatio = 320.0 / videoAssetTrack.naturalSize.height;
        CGAffineTransform scaleTransform = CGAffineTransformMakeScale(scaleRatio, scaleRatio);
        CGAffineTransform prefToScaleTransform = CGAffineTransformConcat(videoAssetTrack.preferredTransform, scaleTransform);
        // The capture view is 320x320 and crops out the exact middle of the entire capture screen, which captures the main UIScreen.
        // We need to translate the capture view upwards to align with the window, which starts at the top of the main screen.
        CGAffineTransform translateTransform = CGAffineTransformMakeTranslation(0, -([[UIScreen mainScreen] bounds].size.height - 320) / 2.0);
        CGAffineTransform scaleAndTransTransform = CGAffineTransformConcat(prefToScaleTransform, translateTransform);
        [layerInstruction setTransform:scaleAndTransTransform atTime:kCMTimeZero];

        // Set up the main video composition, which includes the layer instruction for fixing the orientation
        AVMutableVideoComposition *mainComposition = [AVMutableVideoComposition videoComposition];
        AVMutableVideoCompositionInstruction *mainInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        mainInstruction.layerInstructions = [NSArray arrayWithObject:layerInstruction];
        mainInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, newVideoDuration);
        mainComposition.instructions = [NSArray arrayWithObject:mainInstruction];
        mainComposition.frameDuration = newVideoDuration;
        mainComposition.renderSize = CGSizeMake(320, 320);
        
        // Export to a temporary path
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:mixComposition
                                                                               presetName:AVAssetExportPresetHighestQuality];
        NSURL *exportUrl = [NSURL fileURLWithPath:[AVCamCaptureManager generateTempFilePath:@".mov"]];
        [exportSession setOutputURL:exportUrl];
        [exportSession setOutputFileType:AVFileTypeQuickTimeMovie];
        exportSession.videoComposition = mainComposition;
        
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^ {
//            switch ([exportSession status]) {
//                case AVAssetExportSessionStatusFailed:
//                    NSLog(@"Export session faied with error: %@", [exportSession error]);
//                    break;
//                default:
//                    break;
//            }
            [library writeVideoAtPathToSavedPhotosAlbum:exportUrl
                                        completionBlock:^(NSURL *assetURL, NSError *error) {
                                            if (error) {
                                                if ([[self delegate] respondsToSelector:@selector(captureManager:didFailWithError:)]) {
                                                    [[self delegate] captureManager:self didFailWithError:error];
                                                }
                                            }
                                            
                                            if ([[UIDevice currentDevice] isMultitaskingSupported]) {
                                                [[UIApplication sharedApplication] endBackgroundTask:[self backgroundRecordingID]];
                                            }
                                            
                                            if ([[self delegate] respondsToSelector:@selector(captureManagerRecordingFinished:)]) {
                                                [[self delegate] captureManagerRecordingFinished:self];
                                            }
                                            
                                            [[NSFileManager defaultManager] removeItemAtURL:exportUrl error:&error];
                                        }];

        }];
    }
}

@end
