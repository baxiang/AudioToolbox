//
//  ViewController.m
//  AudioFileServices
//
//  Created by baxiang on 2017/7/13.
//  Copyright © 2017年 baxiang. All rights reserved.
//

#import "ViewController.h"
#import "BXAudioPlayer.h"
@interface ViewController ()
{

    BXAudioPlayer* _player;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"VoiceOriginFile" ofType:@"wav"];
    _player = [[BXAudioPlayer alloc]initWithPath:path];
   
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
