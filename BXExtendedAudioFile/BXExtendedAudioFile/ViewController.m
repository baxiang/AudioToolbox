//
//  ViewController.m
//  BXExtendedAudioFile
//
//  Created by baxiang on 2017/7/14.
//  Copyright © 2017年 baxiang. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import "lame.h"
@interface ViewController ()
{
    ExtAudioFileRef _audioFileRef;
    AudioStreamBasicDescription   _outputFormat;
    AudioStreamBasicDescription   _inputFormat;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
   NSString *path =  [[NSBundle mainBundle] pathForResource:@"VoiceOriginFile" ofType:@"wav"];
  // 读取音频文件
   OSStatus status = ExtAudioFileOpenURL((__bridge CFURLRef _Nonnull)([NSURL fileURLWithPath:path]), &_audioFileRef);
    if (status!= noErr) {
        NSLog(@"数据读取错误 %d",status);
    }
    _outputFormat.mSampleRate = 44100;
    _outputFormat.mBitsPerChannel = 16;
    _outputFormat.mChannelsPerFrame = 2;
    _outputFormat.mFormatID = kAudioFormatMPEGLayer3;
    
    UInt32 descSize = sizeof(AudioStreamBasicDescription);
    ExtAudioFileGetProperty(_audioFileRef, kExtAudioFileProperty_FileDataFormat, &descSize, &_inputFormat);
    
    
    _inputFormat.mSampleRate = _outputFormat.mSampleRate;
    _inputFormat.mChannelsPerFrame = _outputFormat.mChannelsPerFrame;
    _inputFormat.mBytesPerFrame = _inputFormat.mChannelsPerFrame* _inputFormat.mBytesPerFrame;
    _inputFormat.mBytesPerPacket =  _inputFormat.mFramesPerPacket*_inputFormat.mBytesPerFrame;
    

    ExtAudioFileSetProperty(_audioFileRef,
                            kExtAudioFileProperty_ClientDataFormat,
                            sizeof(AudioStreamBasicDescription),
                            &_inputFormat),

    [self startConvertMP3:_inputFormat];
    
    // Do any additional setup after loading the view, typically from a nib.
}
-(void)startConvertMP3:(AudioStreamBasicDescription) inputFormat{
    
    lame_t lame = lame_init();
    lame_set_in_samplerate(lame, inputFormat.mSampleRate);
    lame_set_num_channels(lame, inputFormat.mChannelsPerFrame);
    lame_set_VBR(lame, vbr_default);
    lame_init_params(lame);
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* outputFilePath = [[paths lastObject] stringByAppendingPathComponent:@"music.mp3"];
    FILE* outputFile = fopen([outputFilePath cStringUsingEncoding:1], "wb");
    NSLog(@"path:%@",outputFilePath);
    UInt32 sizePerBuffer = 32*1024;
    UInt32 framesPerBuffer = sizePerBuffer/sizeof(SInt16);
    
    int write;
    
    // allocate destination buffer
    SInt16 *outputBuffer = (SInt16 *)malloc(sizeof(SInt16) * sizePerBuffer);
    
    while (1) {
        AudioBufferList outputBufferList;
        outputBufferList.mNumberBuffers              = 1;
        outputBufferList.mBuffers[0].mNumberChannels = inputFormat.mChannelsPerFrame;
        outputBufferList.mBuffers[0].mDataByteSize   = sizePerBuffer;
        outputBufferList.mBuffers[0].mData           = outputBuffer;
        
        UInt32 framesCount = framesPerBuffer;
        
        ExtAudioFileRead(_audioFileRef,&framesCount,&outputBufferList);
        
        SInt16 pcm_buffer[framesCount];
        unsigned char mp3_buffer[framesCount];
        memcpy(pcm_buffer,
               outputBufferList.mBuffers[0].mData,
               framesCount);
        if (framesCount==0) {
            printf("Done reading from input file\n");
            free(outputBuffer);
            outputBuffer = NULL;
            //TODO:Add lame_encode_flush for end of file
            return;
        }
        
        //the 3rd parameter means number of samples per channel, not number of sample in pcm_buffer
        write = lame_encode_buffer_interleaved(lame,
                                               outputBufferList.mBuffers[0].mData,
                                               framesCount,
                                               mp3_buffer,
                                               0);
         fwrite(mp3_buffer,1,write,outputFile);
    }
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
