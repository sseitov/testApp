//
//  FFmpegTranscoder.h
//  testApp
//
//  Created by Сергей Сейтов on 15.04.2018.
//  Copyright © 2018 V-Channel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FFmpegTranscoder : NSObject

+ (BOOL)transcode:(NSString*)inFile outFile:(NSString*)outFile meta:(NSDictionary*)meta;

@end
