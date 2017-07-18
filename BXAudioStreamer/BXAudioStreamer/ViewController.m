//
//  ViewController.m
//  BXAudioStreamer
//
//  Created by baxiang on 2017/7/14.
//  Copyright © 2017年 baxiang. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>

@interface ViewController ()<NSURLSessionDelegate>
{
    AudioFileStreamID _audioFileStreamID;
    NSMutableArray *_dataArray;
    AudioStreamBasicDescription _audioStreamDescription;
    AudioQueueRef _outputQueue;
    NSInteger _readPacketIndex;
}

@end

@implementation ViewController

void audioFileStreamPropertyListenerProc(void *inClientData,AudioFileStreamID	inAudioFileStream,AudioFileStreamPropertyID	inPropertyID,AudioFileStreamPropertyFlags *	ioFlags)
{
    ViewController *self  = (__bridge ViewController *)(inClientData);
    [self audioFileStreamPropertyListenerProc:inClientData inAudioFileStream:inAudioFileStream inPropertyID:inPropertyID ioFlags:ioFlags];

}
-(void) audioFileStreamPropertyListenerProc:(void *)inClientData inAudioFileStream:(AudioFileStreamID)inAudioFileStream inPropertyID:(AudioFileStreamPropertyID)	inPropertyID ioFlags:(AudioFileStreamPropertyFlags *)ioFlags
{
    if (inPropertyID ==  kAudioFileStreamProperty_DataFormat) {
        UInt32 outDataSize = sizeof(AudioStreamBasicDescription);
        // AudioStreamBasicDescription audioStreamDescription;
        AudioFileStreamGetProperty(inAudioFileStream, inPropertyID,  &outDataSize, &_audioStreamDescription);
        [self _createAudioQueueWithAudioStreamDescription];
    }
}
void audioQueueCallback(void * __nullable inUserData,AudioQueueRef inAQ,AudioQueueBufferRef  inBuffer)
{
    OSStatus status = AudioQueueFreeBuffer(inAQ, inBuffer);
    assert(status == noErr);
    ViewController *self  = (__bridge ViewController *)(inUserData);
    [self _enqueueDataWithPacketsCount:(int)([self packetsPerSecond]*2)];
}

- (void)_createAudioQueueWithAudioStreamDescription
{
    OSStatus status = AudioQueueNewOutput(&_audioStreamDescription, audioQueueCallback, (__bridge void *)(self), NULL, kCFRunLoopCommonModes, 0, &_outputQueue);
    assert(status == noErr);
}
-(UInt32)packetsPerSecond{
    return _audioStreamDescription.mSampleRate / _audioStreamDescription.mFramesPerPacket;
}

- (void)_storePacketsWithNumberOfBytes:(UInt32)inNumberBytes numberOfPackets:(UInt32)inNumberPackets inputData:(const void *)inInputData packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions
{
    if (inPacketDescriptions) {
        for (int i = 0; i < inNumberPackets; i++) {
            SInt64 packetStart = inPacketDescriptions[i].mStartOffset;
            UInt32 packetSize = inPacketDescriptions[i].mDataByteSize;
            NSData *packet = [NSData dataWithBytes:inInputData +packetStart length:packetSize];
            [_dataArray addObject:packet];
        }
    }else{
        UInt32  packetsSize = inNumberBytes/inNumberPackets;
        for (int i = 0; i < inNumberPackets; i++) {
            NSData *packet = [NSData dataWithBytes:inInputData+packetsSize*(i+1) length:packetsSize];
            [_dataArray addObject:packet];
        }
    }
    if (_readPacketIndex == 0 && _dataArray.count > (int)([self packetsPerSecond]*2)) {
        OSStatus status = AudioQueueStart(_outputQueue, NULL);
        assert(status == noErr);
        [self _enqueueDataWithPacketsCount:(int)([self packetsPerSecond]*2)];
    }
}

- (void)_enqueueDataWithPacketsCount:(size_t)inPacketCount
{
    if (!_outputQueue) {
        return;
    }
    if (_readPacketIndex + inPacketCount >= _dataArray.count) {
        inPacketCount = _dataArray.count - _readPacketIndex;
    }
    if (inPacketCount<=0) {
        AudioQueueStop(_outputQueue, false);
        AudioFileStreamClose(_audioFileStreamID);
        return;
    }
    UInt32 totalSize = 0;
    for (UInt32 index = 0; index<inPacketCount; index++) {
        NSData  *data= [_dataArray objectAtIndex:index+_readPacketIndex];
        totalSize += data.length;
    }
    
    OSStatus status = 0;
    AudioQueueBufferRef outBuffer;
    status = AudioQueueAllocateBuffer(_outputQueue, totalSize, &outBuffer);
    assert(status == noErr);
    
    outBuffer->mAudioDataByteSize = totalSize;
    outBuffer->mUserData = (__bridge void * _Nullable)(self);
    AudioStreamPacketDescription *inPacketDescriptions = calloc(inPacketCount, sizeof(AudioStreamPacketDescription));
    UInt32 startOffset = 0;
    for (int  i = 0; i<inPacketCount; i++) {
        NSData *data = [_dataArray objectAtIndex:i+_readPacketIndex];
        memcpy(outBuffer->mAudioData+startOffset, [data bytes], [data length]);
        AudioStreamPacketDescription packetDescriptions ;
        packetDescriptions.mDataByteSize = (UInt32)data.length;
        packetDescriptions.mStartOffset = startOffset;
        packetDescriptions.mVariableFramesInPacket = 0;
        startOffset += data.length;
        memcpy(&inPacketDescriptions[i], &packetDescriptions, sizeof(AudioStreamPacketDescription));
    }
    status = AudioQueueEnqueueBuffer(_outputQueue, outBuffer, (UInt32)inPacketCount, inPacketDescriptions);
    assert(status == noErr);
    free(inPacketDescriptions);
    _readPacketIndex += inPacketCount;
}
void audioFileStreamPacketsProc(void *inClientData,UInt32 inNumberBytes,UInt32 inNumberPackets,const void *inInputData,AudioStreamPacketDescription	*inPacketDescriptions){
     ViewController *self  = (__bridge ViewController *)(inClientData) ;
     [self _storePacketsWithNumberOfBytes:inNumberBytes numberOfPackets:inNumberPackets inputData:inInputData packetDescriptions:inPacketDescriptions];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _dataArray = [NSMutableArray arrayWithCapacity:0];
    AudioFileStreamOpen((__bridge void * _Nullable)(self), audioFileStreamPropertyListenerProc, audioFileStreamPacketsProc, 0, &_audioFileStreamID);
    NSURLSession *session  =  [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
    NSString *wavString = @"http://baxiang.qiniudn.com/VoiceOriginFile.wav";// wav文件
    NSString *mp3String = @"http://baxiang.qiniudn.com/chengdu.mp3";// mp3文件
    NSURLSessionDataTask * task =  [session dataTaskWithURL:[NSURL URLWithString:mp3String]];
    [task resume];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data{
    AudioFileStreamParseBytes(_audioFileStreamID,  (UInt32)[data length], [data bytes], 0);
}

@end
