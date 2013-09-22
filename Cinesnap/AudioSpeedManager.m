//
//  Audio.m
//  Cinesnap
//
//  Created by Eric Conner on 9/22/13.
//  Copyright (c) 2013 Eric Conner. All rights reserved.
//

#import "AudioSpeedManager.h"
#import "AVCamCaptureManager.h"
#import "Dirac.h"
#import <AudioToolbox/AudioToolbox.h>
#import "EAFWrite.h"

@implementation AudioSpeedManager

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
	AudioSpeedManager *Self = (__bridge AudioSpeedManager*)userData;
	if (!Self)
        return 0;
    
    OSStatus err = [Self.reader readFloatsConsecutive:numFrames intoArray:chdata];
	
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

-(NSURL *)transformAudioTrack:(AVAssetTrack *)audioAssetTrack byFactor:(float)factor
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
	// Here we set our time and pitch manipulation values
	float time      = factor;
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
    
    [self.reader closeFile];
	[writer closeFile]; // important - flushes data to file
    
    return outputUrl;
}

@end
