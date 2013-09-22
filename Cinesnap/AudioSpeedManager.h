//
//  Audio.h
//  Cinesnap
//
//  Created by Eric Conner on 9/22/13.
//  Copyright (c) 2013 Eric Conner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EAFRead.h"

@interface AudioSpeedManager : NSObject

@property (strong, nonatomic) EAFRead *reader;

-(NSURL *)transformAudioTrack:(AVAssetTrack *)audioAssetTrack byFactor:(float)factor;

@end
