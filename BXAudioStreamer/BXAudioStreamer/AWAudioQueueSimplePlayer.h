//
//  AWAudioQueueSimplePlayer.h
//  AWAudioQueueSimplePlayer
//
//  Created by Abe Wang on 2017/3/28.
//  Copyright © 2017年 AbeWang. All rights reserved.
//

@import Foundation;
@import AudioToolbox;

@interface AWAudioQueueSimplePlayer : NSObject
- (instancetype)initWithURL:(NSURL *)inURL;
- (void)play;
- (void)pause;
- (void)stop;
@property (readonly, getter=isStopped) BOOL stopped;
@end
