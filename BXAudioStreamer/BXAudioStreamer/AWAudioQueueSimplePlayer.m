//
//  AWAudioQueueSimplePlayer.m
//  AWAudioQueueSimplePlayer
//
//  Created by Abe Wang on 2017/3/28.
//  Copyright © 2017年 AbeWang. All rights reserved.
//

#import "AWAudioQueueSimplePlayer.h"

static void AWAudioFileStreamPropertyListener(void * inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 * ioFlags);
static void AWAudioFileStreamPacketsCallback(void * inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void * inInputData, AudioStreamPacketDescription *inPacketDescriptions);
static void AWAudioQueueOutputCallback(void * inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);
static void AWAudioQueueRunningListener(void * inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID);

@interface AWAudioQueueSimplePlayer ()
<NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *URLSession;
@property (nonatomic, strong) NSMutableArray<NSData *> *packets;
- (double)packetsPerSecond;
@end

@implementation AWAudioQueueSimplePlayer
{
    struct {
        BOOL stopped;
        BOOL loaded;
    } playerStatus;

    AudioFileStreamID audioFileStreamID;
    AudioQueueRef outputQueue;
    AudioStreamBasicDescription streamDescription;
    size_t readHead;
}

- (void)dealloc
{
    OSStatus status = AudioQueueReset(outputQueue);
    assert(status == noErr);
    status = AudioFileStreamClose(audioFileStreamID);
    assert(status == noErr);
    [self.URLSession invalidateAndCancel];
}

- (instancetype)initWithURL:(NSURL *)inURL
{
    if (self = [super init]) {
        playerStatus.stopped = NO;
        self.packets = [NSMutableArray array];
        
        // 第一步驟：建立Audio Parser，指定 Parser callback，建立 HTTP 連線，下載音檔資料
        OSStatus status = AudioFileStreamOpen((__bridge void * _Nullable)self, AWAudioFileStreamPropertyListener, AWAudioFileStreamPacketsCallback, kAudioFileMP3Type, &audioFileStreamID);
        assert(status == noErr);
        
        self.URLSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:nil];
        NSURLSessionDataTask *task = [self.URLSession dataTaskWithURL:inURL];
        [task resume];
    }
    return self;
}

- (double)packetsPerSecond
{
    if (streamDescription.mFramesPerPacket) {
        return streamDescription.mSampleRate / streamDescription.mFramesPerPacket;
    }
    return 44100.0 / 1152.0;
}

- (void)play
{
    OSStatus status = AudioQueueStart(outputQueue, NULL);
    assert(status == noErr);
}

- (void)pause
{
    OSStatus status = AudioQueuePause(outputQueue);
    assert(status == noErr);
}

- (void)stop
{
    OSStatus status = AudioQueueStop(outputQueue, false);
    assert(status == noErr);
}

- (void)_createAudioQueueWithAudioStreamDescription:(AudioStreamBasicDescription *)audioStreamBasicDescription
{
    // 把從 Parser 身上取到的 audio format 資訊（ASBD）複製到自己身上一份
    memcpy(&streamDescription, audioStreamBasicDescription, sizeof(AudioStreamBasicDescription));

    // 建立 Audio Queue，但要注意以下情況：
    // 當要決定 callback function 要在哪個 runloop 時，必須要確保這個 thread 的 runloop 在去呼叫 callback function 時還會在。如果在此範例用 CFRunLoopGetCurrent() 的話，是有可能不會執行到 callback function 而無法一直 enqueue buffer。因為此時的 current thread 是用在接收資料的 data task 上，當資料接收完後，此 thread 之後就會被移掉，所以 callback function 就再也不會被呼叫到。如果給 NULL，則是會使用 Audio Queue 自己內部的 thread runloop。總之，要能夠確保 OutputCallback 可以一直被呼叫到，給 callbackRunloop 時就要注意。
    OSStatus status = AudioQueueNewOutput(audioStreamBasicDescription, AWAudioQueueOutputCallback, (__bridge void *)(self), NULL, kCFRunLoopCommonModes, 0, &outputQueue);
    assert(status == noErr);

    status = AudioQueueAddPropertyListener(outputQueue, kAudioQueueProperty_IsRunning, AWAudioQueueRunningListener, (__bridge void *)(self));
    assert(status == noErr);
    
    status = AudioQueuePrime(outputQueue, 0, NULL);
    assert(status == noErr);
    status = AudioQueueStart(outputQueue, NULL);
    assert(status == noErr);
}

- (void)_storePacketsWithNumberOfBytes:(UInt32)inNumberBytes numberOfPackets:(UInt32)inNumberPackets inputData:(const void *)inInputData packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions
{
    // 將 Parser 分析出來的 packets 都先儲存起來
    for (int i = 0; i < inNumberPackets; i++) {
        SInt64 packetStart = inPacketDescriptions[i].mStartOffset;
        UInt32 packetSize = inPacketDescriptions[i].mDataByteSize;
        
        NSData *packet = [NSData dataWithBytes:inInputData +packetStart length:packetSize];
        [self.packets addObject:packet];
        // 第五步驟：檢查 packets 數量是否已經足夠可以播放。
        // 當 parse 出來的 packets 夠多，緩衝內容夠大，因此就可以先開始播放 (本範例是累積三秒後就先播放)
       
    }
    if (readHead == 0 && self.packets.count > (int)([self packetsPerSecond] * 1)) {
        OSStatus status = AudioQueueStart(outputQueue, NULL);
        assert(status == noErr);
        NSLog(@"緩衝已夠，開始播放");
        // 把儲存起來的 packets 資料往 Audio Queue Buffer 裡塞，第一次先塞個三秒的 Packets 資料量，之後都用五秒
        [self _enqueueDataWithPacketsCount:(int)([self packetsPerSecond] * 1)];
    }
    
}

- (void)_enqueueDataWithPacketsCount:(size_t)inPacketCount
{
    if (!outputQueue) {
        return;
    }
    
    NSLog(@"目前 readHead 位置 / packets 總量 : %zu / %lu", readHead, (unsigned long)self.packets.count);
    
    if (readHead == self.packets.count) {
        if (playerStatus.loaded) {
            NSLog(@"整首播放完畢");
            // 第六步驟：已經把所有 packets 都播完了，播放結束。
            AudioQueueStop(outputQueue, false);
            playerStatus.stopped = YES;
            return;
        }
    }

    if (readHead + inPacketCount >= self.packets.count) {
        inPacketCount = self.packets.count - readHead;
    }

    // 建立 Audio Queue Buffer，並決定 Buffer 需要給多大的 size
    UInt32 totalSize = 0;
    for (UInt32 index = 0; index < inPacketCount; index++) {
        NSData *packet = self.packets[readHead + index];
        totalSize += packet.length;
    }
    
    OSStatus status = 0;
    AudioQueueBufferRef buffer;
    status = AudioQueueAllocateBuffer(outputQueue, totalSize, &buffer);
    assert(status == noErr);

    // 把 Packets 資料塞進剛建立好的 Buffer 中
    buffer->mAudioDataByteSize = totalSize;
    buffer->mUserData = (__bridge void * _Nullable)(self);

    AudioStreamPacketDescription *packetDescs = calloc(inPacketCount, sizeof(AudioStreamPacketDescription));

    totalSize = 0;
    for (UInt32 index = 0; index < inPacketCount; index++) {
        NSData *packet = self.packets[readHead + index];
        memcpy(buffer->mAudioData + totalSize, packet.bytes, packet.length);
        AudioStreamPacketDescription description;
        description.mStartOffset = totalSize;
        description.mDataByteSize = (UInt32)packet.length;
        description.mVariableFramesInPacket = 0;
        totalSize += packet.length;
        memcpy(&(packetDescs[index]), &description, sizeof(AudioStreamPacketDescription));
    }

    // 把塞好資料的 Buffer，enqueue 進入到 buffer queue 中
    status = AudioQueueEnqueueBuffer(outputQueue, buffer, (UInt32)inPacketCount, packetDescs);
    assert(status == noErr);
    free(packetDescs);
    readHead += inPacketCount;
}

- (void)_audioQueueDidStart
{
    NSLog(@"Audio Queue Did Start.");
}

- (void)_audioQueueDidStop
{
    NSLog(@"Audio Queue Did Stop");
    playerStatus.stopped = YES;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        if ([(NSHTTPURLResponse *)response statusCode] != 200) {
            NSLog(@"HTTP Code: %ld", [(NSHTTPURLResponse *)response statusCode]);
            [session invalidateAndCancel];
            playerStatus.stopped = YES;
            completionHandler(NSURLSessionResponseCancel);
        }
        else {
            completionHandler(NSURLSessionResponseAllow);
        }
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    // 第二步驟：開始抓到一點一點的檔案，把 data 交由 Audio Parser (AudioFileStreamID) 開始 Parse 出 data stream 中的 packets 以及 audio format
    OSStatus status = AudioFileStreamParseBytes(audioFileStreamID, (UInt32)data.length, data.bytes, 0);
    assert(status == noErr);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error) {
        NSLog(@"Failed to load data: %@", error.localizedDescription);
        playerStatus.stopped = YES;
    }
    else {
        NSLog(@"Complete loading data");
        playerStatus.loaded = YES;
    }
}

#pragma mark - Properties

- (BOOL)isStopped
{
    return playerStatus.stopped;
}

@end

static void AWAudioFileStreamPropertyListener(void * inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 * ioFlags)
{
    // 第三步驟：Audio Parser 已經成功 Parse 出 audio format，我們要根據檔案格式來建立出 Audio Queue，並同時去監聽 Audio Queue 的 running 屬性，來監聽 Audio Queue 是否正在執行
    AWAudioQueueSimplePlayer *self = (__bridge AWAudioQueueSimplePlayer *)(inClientData);
    if (inPropertyID == kAudioFileStreamProperty_DataFormat) {
        UInt32 dataSize = 0;
        OSStatus status = 0;
        AudioStreamBasicDescription audioStreamDescription;
        Boolean writable = false;
        // 先取得屬性的資訊：如 size 等
        status = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &writable);
        assert(status == noErr);
        // 取得屬性內容，並將內容寫入到自己的 data 中
        status = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &audioStreamDescription);
        assert(status == noErr);
        
        NSLog(@"SampleRate: %f", audioStreamDescription.mSampleRate);
        NSLog(@"FormatID: %u", audioStreamDescription.mFormatID);
        NSLog(@"FormatFlags: %u", audioStreamDescription.mFormatFlags);
        NSLog(@"BytesPerPacket: %u", audioStreamDescription.mBytesPerPacket);
        NSLog(@"FramePerPacket: %u", audioStreamDescription.mFramesPerPacket);
        NSLog(@"BytesPerFrame: %u", audioStreamDescription.mBytesPerFrame);
        NSLog(@"ChannelsPerFrame: %u", audioStreamDescription.mChannelsPerFrame);
        NSLog(@"BitsPerChannel: %u", audioStreamDescription.mBitsPerChannel);
        
        [self _createAudioQueueWithAudioStreamDescription:&audioStreamDescription];
    }
}

static void AWAudioFileStreamPacketsCallback(void * inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void * inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{
    // 第四步驟：Audio Parser 已經成功 parse 出 packets 資料了，我們須先將這些資料儲存起來
    AWAudioQueueSimplePlayer *self = (__bridge AWAudioQueueSimplePlayer *)(inClientData);
    [self _storePacketsWithNumberOfBytes:inNumberBytes numberOfPackets:inNumberPackets inputData:inInputData packetDescriptions:inPacketDescriptions];
}

static void AWAudioQueueOutputCallback(void * inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    // 此範例為了方便，不會去 reuse buffer，用完後直接丟棄。enqueueData 時再建立新的 buffer
    NSLog(@"datacout-----%u",(unsigned int)inBuffer->mAudioDataByteSize);
    OSStatus status = AudioQueueFreeBuffer(inAQ, inBuffer);
    assert(status == noErr);
   
    AWAudioQueueSimplePlayer *self = (__bridge AWAudioQueueSimplePlayer *)(inUserData);
    [self _enqueueDataWithPacketsCount:(int)([self packetsPerSecond] * 1)];
}

static void AWAudioQueueRunningListener(void * inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    AWAudioQueueSimplePlayer *self = (__bridge AWAudioQueueSimplePlayer *)(inUserData);
    
    if (inID == kAudioQueueProperty_IsRunning) {
        UInt32 dataSize;
        UInt32 isRunning;
        OSStatus status = 0;
        status = AudioQueueGetPropertySize(inAQ, inID, &dataSize);
        assert(status == noErr);
        status = AudioQueueGetProperty(inAQ, inID, &isRunning, &dataSize);
        assert(status == noErr);
        isRunning ? [self _audioQueueDidStart] : [self _audioQueueDidStop];
    }
}
