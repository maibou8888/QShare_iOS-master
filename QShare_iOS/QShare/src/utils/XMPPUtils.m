//
//  XMPPUtils.m
//  QShare
//
//  Created by Vic on 14-4-16.
//  Copyright (c) 2014年 vic. All rights reserved.
//

#import "XMPPUtils.h"
#import "QSUtils.h"
#import "XMPPvCardTemp.h"

#define QUERY_ROSTER @"queryRoster"

NSString *password;  //密码
BOOL isanonymousConnect = NO; //是不是匿名登录

@implementation XMPPUtils


+ (XMPPUtils *) sharedInstance
{
    static XMPPUtils *sharedUtils = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedUtils = [[XMPPUtils alloc]init];
    });
    return sharedUtils;
}

-(void)setupStream{
    //初始化XMPPStream
    _xmppStream = [[XMPPStream alloc] init];
    [_xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
    
    //初始化XMPPReconnect
    _xmppReconnect = [[XMPPReconnect alloc]init];
    [_xmppReconnect activate:_xmppStream];
    
    // 初始化 xmppRosterStorage
    _xmppRosterDataStorage = [XMPPRosterCoreDataStorage sharedInstance];
    _xmppRoster = [[XMPPRoster alloc]initWithRosterStorage:_xmppRosterDataStorage];
    [_xmppRoster activate:_xmppStream];
    [_xmppRoster addDelegate:self delegateQueue:dispatch_get_main_queue()];
    _xmppRoster.autoFetchRoster = YES;
    _xmppRoster.autoAcceptKnownPresenceSubscriptionRequests = YES;

    // 初始化 message
    _xmppMessageArchivingCoreDataStorage = [XMPPMessageArchivingCoreDataStorage sharedInstance];
    _xmppMessageArchivingModule = [[XMPPMessageArchiving alloc]initWithMessageArchivingStorage:_xmppMessageArchivingCoreDataStorage];
    [_xmppMessageArchivingModule setClientSideMessageArchivingOnly:YES];
    [_xmppMessageArchivingModule activate:_xmppStream];
    [_xmppMessageArchivingModule addDelegate:self delegateQueue:dispatch_get_main_queue()];
    
    // 初始化 vCard support
    _xmppvCardStorage = [XMPPvCardCoreDataStorage sharedInstance];
    _xmppvCardTempModule = [[XMPPvCardTempModule alloc] initWithvCardStorage:_xmppvCardStorage];
    [_xmppvCardTempModule activate:_xmppStream];
    [_xmppvCardTempModule addDelegate:self delegateQueue:dispatch_get_main_queue()];
    
    // 初始化 XMPPMUC
    _xmppRoomCoreDataStorage = [XMPPRoomCoreDataStorage sharedInstance];
    _xmppMUC = [[XMPPMUC alloc]initWithDispatchQueue:dispatch_get_main_queue()];
    [_xmppMUC activate:_xmppStream];
    [_xmppMUC addDelegate:self delegateQueue:dispatch_get_main_queue()];
}

-(void)goOnline{
    
    //发送在线状态
    XMPPPresence *presence = [XMPPPresence presenceWithType:@"available"];
    [_xmppStream sendElement:presence];
    
}

-(void)goOffline{
    
    //发送下线状态
    XMPPPresence *presence = [XMPPPresence presenceWithType:@"unavailable"];
    [_xmppStream sendElement:presence];
    
}

-(BOOL)connect{
    
    isanonymousConnect = NO;
    
    [self setupStream];
    
    //从本地取得用户名，密码和服务器地址
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSString *userName = [defaults stringForKey:XMPP_USER_NAME];
    NSString *jidString = [NSString stringWithFormat:@"%@@%@",userName,XMPP_HOST_NAME];
    NSString *pass = [defaults stringForKey:XMPP_USER_PASS];
    NSString *server = XMPP_HOST_NAME;
    
    if (![_xmppStream isDisconnected]) {
        return YES;
    }
    
    if (userName == nil || pass == nil) {
        return NO;
    }
    
    //设置用户
    [_xmppStream setMyJID:[XMPPJID jidWithString:jidString]];
    //设置服务器
    [_xmppStream setHostName:server];
    //密码
    password = pass;
    
    //连接服务器
    NSError *error = nil;
    if (![_xmppStream connectWithTimeout:XMPPStreamTimeoutNone error:&error]) {
        NSLog(@"cant connect %@", server);
        return NO;
    }
    
    return YES;
    
}

//用户注册时用
- (void)anonymousConnect{
    /*
     *(1) 带内注册指的是未在你的服务器上开通账号的用户可以通过xmpp协议注册新账号。相反的概念是带外注册（out-of-band registration），
          例如,你必须到某个指定的web页面进行注册。
          如果服务器允许带内注册，那么我们就可以通过自己开发的客户端注册新账号。与带内注册相关的协议是XEP-0077。
     *(2) XMPPStream.h中声明了进行简单带内注册(提供用户名和密码进行注册)的函数
          - (BOOL)registerWithPassword:(NSString *)password error:(NSError **)errPtr;
          注册前需要先建立stream连接, 因为没有帐号,所以需要建立匿名连接
     */
    isanonymousConnect = YES;
    [self setupStream];
    NSString *jidString = [[NSString alloc] initWithFormat:@"anonymous@%@",XMPP_HOST_NAME];
    NSString *server = XMPP_HOST_NAME;
    [_xmppStream setMyJID:[XMPPJID jidWithString:jidString]];
    [_xmppStream setHostName:server];
    NSError *error;
    if (![_xmppStream connectWithTimeout:XMPPStreamTimeoutNone error:&error]) {
        NSLog(@"cant connect server");
    }
}

-(void)enrollWithUserName:(NSString *)userName andPassword:(NSString *)pass
{
    NSString *jidString = [[NSString alloc] initWithFormat:@"%@@%@",userName,XMPP_HOST_NAME];
    [_xmppStream setMyJID:[XMPPJID jidWithString:jidString]];
    NSError *error;
    if (![_xmppStream registerWithPassword:pass error:&error])
    {
        NSLog(@"创建用户失败");
    }
}

- (void)queryRoster {
    /*
    一个 IQ 请求：
    <iq type="get"
    　　from="xiaoming@example.com"
    　　to="example.com"
    　　id="1234567">
    　　<query xmlns="jabber:iq:roster"/>
    <iq />
    
    获取 roster 需要客户端发送 <iq /> 标签向 XMPP 服务器端查询
    type 属性，说明了该 iq 的类型为 get，与 HTTP 类似，向服务器端请求信息
    from 属性，消息来源，这里是你的 JID
    to 属性，消息目标，这里是服务器域名
    id 属性，标记该请求 ID，当服务器处理完毕请求 get 类型的 iq 后，响应的 result 类型 iq 的 ID 与 请求 iq 的 ID 相同
    <query xmlns="jabber:iq:roster"/> 子标签，说明了客户端需要查询 roster
     */
    
    NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:@"jabber:iq:roster"];
    NSXMLElement *iq = [NSXMLElement elementWithName:@"iq"];
    XMPPJID *myJID = _xmppStream.myJID;
    [iq addAttributeWithName:@"from" stringValue:myJID.description];
    [iq addAttributeWithName:@"to" stringValue:myJID.domain];
    [iq addAttributeWithName:@"id" stringValue:QUERY_ROSTER];
    [iq addAttributeWithName:@"type" stringValue:@"get"];
    [iq addChild:query];
    [_xmppStream sendElement:iq];
}


-(void)addFriend:(NSString *)userName;
{
    NSString *jidString = [[NSString alloc] initWithFormat:@"%@@%@",userName,XMPP_HOST_NAME];
    [_xmppRoster addUser:[XMPPJID jidWithString:jidString] withNickname:nil];
}

-(void)delFriend:(NSString *)userName;
{
     NSString *jidString = [[NSString alloc] initWithFormat:@"%@@%@",userName,XMPP_HOST_NAME];
    [_xmppRoster removeUser:[XMPPJID jidWithString:jidString]];
}

-(void)disconnect{
    
    [self goOffline];
    [_xmppRoster deactivate];
    [_xmppStream disconnect];
}

#pragma mark - Add or isExist Room JID

-(void)addRoom:(XMPPRoom *)room
{
    if (!_rooms) {
        _rooms = [[NSMutableSet alloc]init];
    }
    if (![self isExistRoom:[room roomJID]]) {
        [_rooms addObject:room];
    }
}

-(BOOL)isExistRoom:(XMPPJID *)roomJID
{
    BOOL isExist = NO;
    for (XMPPRoom *existRoom in _rooms) {
        if ([[existRoom.roomJID bare] isEqualToString:[roomJID bare]]) {
            isExist = YES;
            break;
        }
    }
    return isExist;
}

-(XMPPRoom *)getExistRoom:(XMPPJID *)roomJID
{
    XMPPRoom *existedRoom = nil;
    for (XMPPRoom *existRoom in _rooms) {
        if ([[existRoom.roomJID bare] isEqualToString:[roomJID bare]]) {
            existedRoom = existRoom;
            break;
        }
    }
    return existedRoom;
}


#pragma mark XMPPStreamDelegate methods

//连接服务器
- (void)xmppStreamDidConnect:(XMPPStream *)sender{
    NSLog(@"didconnect");
    NSError *error = nil;
    if (!isanonymousConnect) {
        //验证密码
        [_xmppStream authenticateWithPassword:password error:&error];
    }
    else
    {
        //带内注册
        //在注册里面调用enrollWithUserName: andPassword:
        [_connectDelegate anonymousConnected];
    }
}

//验证通过
- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender{
    NSLog(@"didauthenticate");
    [_connectDelegate didAuthenticate];
    [self goOnline];

    [_xmppvCardTempModule fetchvCardTempForJID:_xmppStream.myJID];
}


//没有通过验证
- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(NSXMLElement *)error
{
    [_connectDelegate didNotAuthenticate:error];
}

//注册成功
- (void)xmppStreamDidRegister:(XMPPStream *)sender
{
    [_connectDelegate registerSuccess];
}

//注册失败
- (void)xmppStream:(XMPPStream *)sender didNotRegister:(NSXMLElement *)error
{
    [_connectDelegate registerFailed:error];
}

//收到消息
- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    NSString *msg = [[message elementForName:@"body"] stringValue];
    if (!msg)
        return;
    if([message isErrorMessage])
        return;
    
    // block group chat system message
    // message.from -> ty@conference.121.199.23.184/maibou888888
    /*
     <message xmlns="jabber:client" to="qwert2@121.199.23.184/ae9ccab1" type="groupchat" from="dfghds@conference.121.199.23.184/qwert2"><body>weewewewew</body><delay xmlns="urn:xmpp:delay" stamp="2016-07-29T15:08:43.028Z" from="qwert2@121.199.23.184/53674559"></delay><x xmlns="jabber:x:delay" stamp="20160729T15:08:43" from="qwert2@121.199.23.184/53674559"></x></message>
     */
    if ([[[message attributeForName:@"type"] stringValue] isEqualToString:@"groupchat"] && [message.from isBare]) {
        return;
    }
    XMPPJID *fromJID = message.from;
    NSString *from = [fromJID user];    //发消息的用户名称
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:msg forKey:@"body"];
    [dict setObject:[NSDate dateWithTimeIntervalSinceNow:0] forKey:@"timestamp"];
    
    XMPPJID *chatJID;

    //好友聊天
    if ([message isChatMessage]) {
        [dict setObject:from forKey:@"chatwith"];
        [dict setObject:@(NO) forKey:@"isOutgoing"];
        chatJID = fromJID;
    }
    else if ([[[message attributeForName:@"type"] stringValue] isEqualToString:@"groupchat"]){
        //群聊天
        /*
         body = 121212121221122112;
         chatType = groupchat;
         from = qwert2;
         isOutgoing = 1;
         roomJID = "fwefwecdcdcscdcscds@conference.121.199.23.184";
         timestamp = "2016-07-30 11:07:30 +0000";
         */
        [dict setObject:@"groupchat" forKey:@"chatType"];
        [dict setObject:[fromJID resource] forKey:@"from"];
        [dict setObject:[fromJID bare] forKey:@"roomJID"];
        chatJID = [XMPPJID jidWithString:[NSString stringWithFormat:@"%@@%@",[fromJID resource],XMPP_HOST_NAME]];
        dict[@"isOutgoing"] = [[fromJID resource] isEqualToString:_xmppStream.myJID.user] ? @(YES) : @(NO);
    }
    
    [_xmppvCardTempModule fetchvCardTempForJID:chatJID];
    XMPPvCardTemp *vCard = [_xmppvCardTempModule vCardTempForJID:chatJID shouldFetch:YES];
    NSData *avatarData = vCard.photo;
    
    if (avatarData) {
        [dict setObject:avatarData forKey:@"chatWithAvatar"];
    }
    
    [_messageDelegate newMessageReceived:dict];
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFY_CHAT_MSG object:dict];
}

//收到好友状态,参照微信不设置在线状态

/*
- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence
{
    NSString *presentType = [presence type];
    NSString *presentUser = [[presence from] user];
    NSString *senderUser = [[sender myJID]user];
//    NSString *presentFrom = [[presence from]full];
//    NSString *presentTo = [[presence to]full];
    if (![senderUser isEqualToString:presentUser]) {
        if (![presentType isEqualToString:@"unavailable"] )
        {
            [_presentDelegate online:presentUser];
        }
        else
        {
            [_presentDelegate offline:presentUser];
        }
    }
    
}
 
*/

//接受好友请求
- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
    NSXMLElement *queryElement = [iq elementForName: @"query" xmlns: @"jabber:iq:roster"];
    
    if (queryElement) {
            [_friendsDelegate removeFriens];
            NSArray *items = [queryElement elementsForName: @"item"];
            for (NSXMLElement *item in items) {
                NSString *jidString = [item attributeStringValueForName:@"jid"];
                XMPPJID *jid = [XMPPJID jidWithString:jidString];
                [_xmppvCardTempModule fetchvCardTempForJID:jid];
                XMPPvCardTemp *vCard = [_xmppvCardTempModule vCardTempForJID:jid shouldFetch:YES];
        
                NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithCapacity:4];
                //头像
                NSData *avatarData = vCard.photo;
                if (avatarData) {
                    [mutableDict setObject:avatarData forKey:@"avatar"];
                }
                
                //名称
                NSString *userName = [jid user];
                [mutableDict setObject:userName forKey:@"name"];
                
                NSDictionary *friendDict = [[NSDictionary alloc]initWithDictionary:mutableDict];
                [_friendsDelegate friendsList:friendDict];
            }
    }
    return YES;
}

#pragma mark - XMPPRosterDelegate

- (void)xmppRoster:(XMPPRoster *)sender didReceivePresenceSubscriptionRequest:(XMPPPresence *)presence
{
    if([[presence type] isEqualToString:@"subscribe"]){
        NSString *myString = [_xmppStream.myJID user];
        NSString *requestRosterDefault = [NSString stringWithFormat:@"%@_requestRoster",myString];
        NSDictionary *requestRosterDict = @{@"from": [presence fromStr], @"to": [presence toStr]};
        
        //保存是否同意列表（from to result:同意or不同意）
        if([[NSUserDefaults standardUserDefaults] objectForKey:requestRosterDefault]){
            NSMutableArray *array = [[[NSUserDefaults standardUserDefaults] objectForKey:requestRosterDefault] mutableCopy];
            [array insertObject:requestRosterDict atIndex:0];
            [[NSUserDefaults standardUserDefaults] setObject:array forKey:requestRosterDefault];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        else{
            NSMutableArray *array = [NSMutableArray arrayWithObject:requestRosterDict];
            [[NSUserDefaults standardUserDefaults] setObject:array forKey:requestRosterDefault];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFY_Friends_Request object:@"friendsInvite"];
    }
}

#pragma mark - XMPPMUCDelegate

- (void)xmppMUC:(XMPPMUC *)sender roomJID:(XMPPJID *)roomJID didReceiveInvitation:(XMPPMessage *)message
{
    NSString *myString = [_xmppStream.myJID user];
    NSString *groupInviteDefault = [NSString stringWithFormat:@"%@_groupInvite",myString];
    
    NSString *roomName = [roomJID user];                                        //房间名
    
    //<x xmlns="http://jabber.org/protocol/muc#user"><invite from="qw1@121.199.23.184"><reason>欢迎加入！</reason></invite></x>
    NSXMLElement *x = [message elementForName:@"x" xmlns:XMPPMUCUserNamespace];
	NSXMLElement *inviteElement = [x elementForName:@"invite"];                 //邀请人
    NSXMLElement *reasonElement = [inviteElement elementForName:@"reason"];     //欢迎加入!
    
    NSString *whoInvite = [inviteElement attributeStringValueForName:@"from"];
    NSString *inviteMessage = [reasonElement stringValue];
    
    NSDictionary *groupInviteDict = @{@"from": whoInvite, @"room": roomName, @"reason": inviteMessage};
    
    /*
     from = "qwert2@121.199.23.184";
     reason = "欢迎加入！";
     room = tryu;
     */
    if([[NSUserDefaults standardUserDefaults] objectForKey:groupInviteDefault]){
        NSMutableArray *array = [[[NSUserDefaults standardUserDefaults] objectForKey:groupInviteDefault] mutableCopy];
        [array insertObject:groupInviteDict atIndex:0];
        [[NSUserDefaults standardUserDefaults] setObject:array forKey:groupInviteDefault];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    else{
        NSMutableArray *array = [NSMutableArray arrayWithObject:groupInviteDict];
        [[NSUserDefaults standardUserDefaults] setObject:array forKey:groupInviteDefault];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)xmppMUC:(XMPPMUC *)sender roomJID:(XMPPJID *) roomJID didReceiveInvitationDecline:(XMPPMessage *)message
{
    NSLog(@"didReceiveInvitationDecline");
}

@end
