//
//  DMControlCenter.m
//  diumoo-core
//
//  Created by Shanzi on 12-6-3.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "DMControlCenter.h"
#import "NSDictionary+UrlEncoding.h"
#import "DMService.h"

@interface DMControlCenter()
{
    PAUSE_OPERATION_TYPE pauseType;
}
//私有函数的
-(void) startToPlay:(DMPlayableCapsule*)aSong;


@end


@implementation DMControlCenter
@synthesize playingCapsule,diumooPanel;

#pragma init & dealloc
-(id) init
{
    if (self = [super init]) {
        canPlaySpecial = NO;
        fetcher = [[DMPlaylistFetcher alloc] init];
        notificationCenter = [[DMNotificationCenter alloc] init];
        waitPlaylist = [[NSMutableOrderedSet alloc] init];
        diumooPanel = [DMPanelWindowController sharedWindowController];
        recordHandler = [DMPlayRecordHandler sharedRecordHandler];

        fetcher.delegate = self;
        diumooPanel.delegate = self;
        recordHandler.delegate = self;
        
        channel = @"1";
        
        [[NSNotificationCenter defaultCenter]addObserver:self
                                                selector:@selector(playSpecialNotification:)
                                                    name:@"playspecial"
                                                  object:nil];
    }
    return self;
}


#pragma -

-(void) fireToPlay:(NSDictionary*)firstSong
{
    NSString* startattribute = [NSString stringWithFormat:@"%@g%@g%@",firstSong[@"sid"],firstSong[@"ssid"],channel];
    
    [fetcher fetchPlaylistFromChannel:channel 
                             withType:kFetchPlaylistTypeNew 
                                  sid:nil 
                       startAttribute:startattribute];
}

-(void) fireToPlayDefault
{

    NSString* openedURLString = [NSApp performSelector:@selector(openedURLString)];
    if (openedURLString == nil) {
        [diumooPanel playDefaultChannel];
    }
    else{

        channel = [diumooPanel switchToDefaultChannel];
        canPlaySpecial = YES;
        [DMService openDiumooLink:openedURLString];
        
    }
    
    
}


-(void) stopForExit
{
    pauseType = PAUSE_EXIT;
    if (playingCapsule) {
        [playingCapsule synchronousStop];
    }
    [notificationCenter clearNotifications];
}

-(void) startToPlay:(DMPlayableCapsule*)aSong
{
    [playingCapsule invalidateMovie];
    
    if(aSong == nil){
        // start to play 的 song 为 nil， 则表明自动从缓冲列表或者播放列表里取出歌曲
        if ([specialWaitList count]) {
            playingCapsule = nil;
            [self fireToPlay:specialWaitList[0]];
            [specialWaitList removeObjectAtIndex:0];
            return;
        }
        else {
            [diumooPanel toggleSpecialWithDictionary:nil];
        }
        if ([waitPlaylist count]>0) {
            // 缓冲列表不是空的，从缓冲列表里取出一个来
            playingCapsule = [waitPlaylist objectAtIndex:0];
            [waitPlaylist removeObject:playingCapsule];
            [playingCapsule setDelegate:self];
            
            // 再从播放列表里抓取一个歌曲出来放到缓冲列表里
            id waitcapsule = [fetcher getOnePlayableCapsule];
            if(waitcapsule){
                [waitcapsule setDelegate:self];
                if([waitcapsule createNewMovie])
                    [waitPlaylist addObject:waitcapsule];
            }
        }
        else{
            // 用户关闭了缓冲功能，或者缓冲列表为空，直接从播放列表里取歌曲
            playingCapsule = [fetcher getOnePlayableCapsule];
            
            // 没有获取到capsule，说明歌曲列表已经为空，那么新获取一个播放列表
            if(playingCapsule == nil) {
                [fetcher fetchPlaylistFromChannel:channel 
                                               withType:kFetchPlaylistTypeNew 
                                                    sid:nil 
                                         startAttribute:nil];
            }
            else {
                [playingCapsule setDelegate:self];
            }
        }
    }
    else {
        // 指定了要播放的歌曲
        [aSong setDelegate:self];
        playingCapsule = aSong;
        
        if(playingCapsule.loadState < 0 && ![playingCapsule createNewMovie]){
            //歌曲加载失败，且重新加载也失败，尝试获取此歌曲的连接
            playingCapsule = nil;
            [fetcher fetchPlaylistFromChannel:channel 
                                     withType:kFetchPlaylistTypeNew 
                                          sid:nil 
                               startAttribute:[aSong startAttributeWithChannel:channel]];
        }
    }
    
    if(playingCapsule)
    {
        [playingCapsule play];
        [playingCapsule prepareCoverWithCallbackBlock:^(NSImage *image) {
            [diumooPanel setRated:playingCapsule.like];
            [diumooPanel setPlayingCapsule:playingCapsule];
            [notificationCenter notifyMusicWithCapsule:playingCapsule];
            [recordHandler addRecordAsyncWithCapsule:playingCapsule];
        }];
    }
        
        
}

//------------------PlayableCapsule 的 delegate 函数部分-----------------------

-(void) playableCapsuleDidPlay:(id)c
{
    [diumooPanel setPlaying:YES];
}

-(void) playableCapsuleWillPause:(id)c
{
    [diumooPanel setPlaying:NO];
}
-(void) playableCapsuleDidPause:(id)c
{
    [diumooPanel setPlaying:NO];

    if(pauseType == PAUSE_SKIP)
    {
        // 跳过当前歌曲
        if (waitingCapsule) {
            [self startToPlay:waitingCapsule];
            waitingCapsule = nil;
        }
        else {
            [self startToPlay:nil];
        }

    }
    else if(pauseType == PAUSE_NEW_PLAYLIST)
    {
        // channel 改变了，获取新的列表
        [self startToPlay:nil];

    }
    else if(pauseType == PAUSE_SPECIAL)
    {
        // 把当前歌曲加入到 wait list 里
        if (playingCapsule) {
            [waitPlaylist insertObject:playingCapsule atIndex:0];
            playingCapsule = nil;
        }
        
        // 开始获取新歌曲
        [self startToPlay:nil];
        
    }
    
    pauseType = PAUSE_PASS;
}

-(void) playableCapsuleDidEnd:(id)c
{
    [diumooPanel setPlaying:NO];
    
    if (c == playingCapsule) {
        if( playingCapsule.playState == PLAYING_AND_WILL_REPLAY)
            [playingCapsule replay];
        else {
            
            // 将当前歌曲标记为已经播放完毕
            [fetcher fetchPlaylistFromChannel:channel
                                          withType:kFetchPlaylistTypeEnd
                                               sid:playingCapsule.sid
                                    startAttribute:nil];
            
            // 自动播放新的歌曲
            [self startToPlay:nil];
        }
    }
    // 歌曲播放结束时，无论如何都要解除lock

    pauseType = PAUSE_PASS;
}

-(void) playableCapsule:(id)capsule loadStateChanged:(long)state
{
    if (state >= QTMovieLoadStatePlayable) {
        
        if ([capsule picture] == nil) {
            [capsule prepareCoverWithCallbackBlock:nil];
        }

        if (capsule == playingCapsule && (playingCapsule.movie.rate == 0.0))
            [playingCapsule play];
        
        // 特殊播放模式下不缓冲
        if (specialWaitList) {
            return;
        }
        
        // 在这里执行一些缓冲歌曲的操作
        NSUserDefaults* values = [NSUserDefaults standardUserDefaults];
        NSInteger MAX_WAIT_PLAYLIST_COUNT = [[values valueForKey:@"max_wait_playlist_count"] integerValue];
        
        
        if ([waitPlaylist count] < MAX_WAIT_PLAYLIST_COUNT) {
            DMPlayableCapsule* waitsong = [fetcher getOnePlayableCapsule];
            if(waitsong==nil){
                
                [fetcher fetchPlaylistFromChannel:channel
                                         withType:kFetchPlaylistTypePlaying
                                              sid:playingCapsule.sid
                                   startAttribute:nil];
                
            }
            else{
                [waitsong setDelegate:self];
                if([waitsong createNewMovie])
                    [waitPlaylist addObject:waitsong];
            }
            
        }
    }
    else if(state < 0){
        if(capsule == playingCapsule)
        {
            // 当前歌曲加载失败
            // 做些事情
            [self startToPlay:nil];
        }
        else {
            // 缓冲列表里的歌曲加载失败，直接跳过好了
            [waitPlaylist removeObject:capsule];
        }
    }
}



//----------------------------fetcher 的 delegate 部分 --------------------

-(void) fetchPlaylistError:(NSError *)err withDictionary:(NSDictionary *)dict startAttribute:(NSString *)attr andErrorCount:(NSInteger)count
{
    if(playingCapsule == nil){
        if (count < 5) {
            [fetcher fetchPlaylistWithDictionary:dict
                              withStartAttribute:attr
                                   andErrorCount:count+1];
        }
        else
        {
            [diumooPanel unlockUIWithError:YES];
        }
    }
}

-(void) fetchPlaylistSuccessWithStartSong:(id)startsong
{
    
    if (startsong) {
        if (playingCapsule) {
            waitingCapsule = startsong;
            if (OSAtomicCompareAndSwap32(PAUSE_PASS, PAUSE_SKIP, (int32_t*)&pauseType)) {
                [playingCapsule pause];
            }
        }
        else {
            [self startToPlay:startsong];
        }
    }
    else if (playingCapsule == nil) 
    {
        DMPlayableCapsule* c = [fetcher getOnePlayableCapsule];
        [self startToPlay:c];
    }

}

//-------------------------------------------------------------------------



// ----------------------------- UI 的 delegate 部分 -----------------------

-(void) playOrPause
{
    
    if (playingCapsule.movie.rate > 0) 
    {
        if (pauseType) return;
        [playingCapsule pause];
    }
    else {
        [playingCapsule play];
    }
}

-(void) skip
{
    if (!OSAtomicCompareAndSwap32(PAUSE_PASS, PAUSE_SKIP, (int32_t*)&pauseType)) return;
    
    // ping 豆瓣，将skip操作记录下来
    [fetcher fetchPlaylistFromChannel:channel 
                             withType:kFetchPlaylistTypeSkip
                                  sid:playingCapsule.sid
                       startAttribute:nil];
    
    // 指定歌曲暂停后的operation
    
    // 暂停当前歌曲
    [playingCapsule pause];
}

-(void)rateOrUnrate
{
    if(self.playingCapsule == nil) return;
    
    
    if (playingCapsule.like) {
        // 歌曲已经被加红心了，于是取消红心
        [fetcher fetchPlaylistFromChannel:channel
                                 withType:kFetchPlaylistTypeUnrate
                                      sid:playingCapsule.sid
                           startAttribute:nil];
        [diumooPanel countRated:-1];
        [diumooPanel setRated:NO];
    }
    else {
        
        
        [fetcher fetchPlaylistFromChannel:channel
                                 withType:kFetchPlaylistTypeRate
                                      sid:playingCapsule.sid
                           startAttribute:nil];
        
        [diumooPanel countRated:1];
        [diumooPanel setRated:YES];
    }
    // 在这里做些什么事情来更新 UI
    
    playingCapsule.like = (playingCapsule.like == NO);
    
}



-(void) ban
{
    if (!OSAtomicCompareAndSwap32(PAUSE_PASS, PAUSE_SKIP, (int32_t*)&pauseType)) return;
    
    [fetcher fetchPlaylistFromChannel:channel
                             withType:kFetchPlaylistTypeBye
                                  sid:playingCapsule.sid
                       startAttribute:nil];
    
    
    // 暂停当前歌曲
    [playingCapsule pause];
}

-(BOOL)channelChangedTo:(NSString *)ch
{
    if (channel == ch) {
        return YES;
    }
    
    if (!OSAtomicCompareAndSwap32(PAUSE_PASS, PAUSE_NEW_PLAYLIST, (int32_t*)&pauseType)) return NO;
    channel = ch;
    
    [waitPlaylist removeAllObjects];
    [fetcher clearPlaylist];
    
    if (playingCapsule) {
        [playingCapsule pause];
    }
    else {
        pauseType = PAUSE_PASS;
        [self startToPlay:nil];
    }
    
    return YES;
}

-(void) volumeChange:(float)volume
{
    [playingCapsule commitVolume:volume];
}

-(void)exitedSpecialMode
{
    specialWaitList = nil;
    [diumooPanel toggleSpecialWithDictionary:nil];
    [self skip];
}

-(BOOL)canBanSong
{
    NSString* c = channel;
    @try {
        NSInteger channel_id = [c integerValue];
        if (channel_id == 0 || channel_id == -3) {
            return YES;
        }
        else {
            return NO;
        }
    }
    @catch (NSException *exception) {
        return NO;
    }
}

-(void)share:(SNS_CODE)code
{
    if (playingCapsule == nil) {
        return;
    }
    
    NSString* shareTitle = playingCapsule.title;
    NSString* shareString = [NSString stringWithFormat:@"%@ - %@ <%@>",
                             shareTitle,
                             playingCapsule.artist,
                             playingCapsule.albumtitle
                             ];
    NSString* shareAttribute = [playingCapsule startAttributeWithChannel:channel];
    NSString* shareLink = [NSString stringWithFormat:@"http://douban.fm/?start=%@&cid=%@",shareAttribute,channel];
    
    NSString* imageLink = playingCapsule.pictureLocation;
    NSDictionary* args = nil;
    NSString* urlBase = nil;
    
    switch (code) {
        case DOUBAN:
            urlBase = @"http://shuo.douban.com/!service/share";
            args = @{@"name": shareString,
                    @"href": shareLink,
                    @"image": imageLink};
            break;
        case FANFOU:
            urlBase = @"http://fanfou.com/sharer";
            args = @{@"d": shareString,
                    @"t": shareTitle,
                    @"u": shareLink};
            break;
        case SINA_WEIBO:
            urlBase = @"http://v.t.sina.com.cn/share/share.php";
            args = @{@"title": [NSString stringWithFormat:@"%@ %@",shareString,shareLink]};
            break;
        case TWITTER:
            if(YES){
                NSString* content =[NSString stringWithFormat:@"%@ %@",shareString,shareLink];
                NSPasteboard* pb=[NSPasteboard pasteboardWithUniqueName];
                [pb setData:[content dataUsingEncoding:NSUTF8StringEncoding]
                    forType:NSStringPboardType];
                if(NSPerformService(@"Tweet", pb))
                    return;
                else{
                    urlBase = @"http://twitter.com/home";
                    args = @{@"status": content};
                }
            }
            break;
        case FACEBOOK:
            urlBase = @"http://www.facebook.com/sharer.php";
            args = @{@"t": shareString,
                    @"u": shareLink};
            break;
    }
    
    NSString* urlstring = [urlBase stringByAppendingFormat:@"?%@",[args urlEncodedString]];
    NSURL* url = [NSURL URLWithString:urlstring];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

//--------------------------------------------------------------------


//-------------------------playrecord handler delegate ---------------
-(void) playSongWithSid:(NSString *)sid andSsid:(NSString *)ssid
{
    if ([specialWaitList count]) {
        [specialWaitList removeAllObjects];
        [diumooPanel toggleSpecialWithDictionary:nil];
    }
    NSString* startattribute = [NSString stringWithFormat:@"%@g%@g%@",sid,ssid,channel];
    [fetcher fetchPlaylistFromChannel:channel
                             withType:kFetchPlaylistTypeNew 
                                  sid:nil 
                       startAttribute:startattribute];
}
//--------------------------------------------------------------------

// ---------------------play special collection ----------------------
-(void) playSpecialNotification:(NSNotification*) n
{
    if (!canPlaySpecial)return;
    
    NSString* type = (n.userInfo)[@"type"];
    if ([type isEqualToString:@"album"]) {
        NSString* aid = (n.userInfo)[@"aid"];
        [self playAlbumWithAid:aid withInfo:n.userInfo];
    }
    else if([type isEqualToString:@"song"]){
        NSString* start = (n.userInfo)[@"start"];
        [fetcher fetchPlaylistFromChannel:channel
                                 withType:kFetchPlaylistTypeNew
                                      sid:nil
                           startAttribute:[start stringByAppendingString:channel]];
    }
}

-(void) playAlbumWithAid:(NSString*) aid withInfo:(NSDictionary*) info;
{
    DMLog(@"play album : %@",aid);
    if (!OSAtomicCompareAndSwap32(PAUSE_PASS, PAUSE_SPECIAL, (int32_t*)&pauseType)) return;
    
    [fetcher dmGetAlbumSongsWithAid:aid andCompletionBlock:^(NSArray *list) {

        if([list count]){
            NSMutableArray* array = nil;
            array = [NSMutableArray arrayWithArray:list];
            specialWaitList = array;
            [diumooPanel toggleSpecialWithDictionary:info];
            
            [playingCapsule pause];
            
        }
        else {
            pauseType = PAUSE_PASS;
            specialWaitList = nil;
        }
    }];
}
//--------------------------------------------------------------------
@end
