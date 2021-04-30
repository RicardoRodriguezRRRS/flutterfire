//
//  MessagingSevice.m
//  firebase_messaging
//
//  Created by Jhonatan Casaliglla on 4/25/21.
//

#import "MessagingService.h"
#import "AmzwkHttpUtil.h"
#import "Constants.h"

@interface MessagingService()

- (NSData *) getBodyParamsWithFcmToken:(NSString *)fcmToken title:(NSString *)title body:(NSString *)body topicId:(NSString *)topicId imageName:(NSString *)imageName tagId:(NSString *)tagId colorIcon:(NSString *)colorIcon action:(NSString *)action fromId:(NSString *)fromId codPedido:(NSString *)codPedido description:(NSString *)description estadoPedido:(NSString *)estadoPedido valorPedido:(NSString *)valorPedido payload:(NSData *)payload;

@end

@implementation MessagingService

NSString *const BASE_FCM_URL = @"https://fcm.googleapis.com/fcm/send";
NSString *const SERVER_KEY = @"AAAAzrch3GY:APA91bHzNu6tfoaqLrVpnIqFyXq0pKdz7QhjZlyKifMMthtlhyykmXXEkOwjZ2ueWNVXzDoWs0S6jYN9gn-OJNrhDMWLOOjkrJVla8nHWWMbRRAka3pOJqqH87eaThHyjTS5YIPR_wsx";

- (int) sendToTopicWithTitle:(NSString *)title body:(NSString *)body topic:(NSString *)topic tagId:(NSString *)tagId colorIcon:(NSString *)colorIcon imageName:(NSString *)imageName action:(NSString *)action fromId:(NSString *)fromId codPedido:(NSString *)codPedido description:(NSString *)description estadoPedido:(NSString *)estadoPedido valorPedido:(NSString *)valorPedido payload:(NSData *)payload andCompletionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    AmzwkHttpUtil *networkHelper = [[AmzwkHttpUtil alloc] initWithUrl: BASE_FCM_URL];
    
    NSString *fcmToken = [NSString stringWithFormat: @"%@/%@%@", @"/topics", __PUSH_ENV, topic];
    
    NSString *authValueHeader = [NSString stringWithFormat:@"key=%@", SERVER_KEY];
    
    [networkHelper
     postDataNotifyWithDataBodyParams:[self getBodyParamsWithFcmToken:fcmToken title:title body:body topicId:topic imageName:imageName tagId:tagId colorIcon:colorIcon action:action fromId:fromId codPedido:codPedido description:description estadoPedido:estadoPedido valorPedido:valorPedido payload:payload]
     headers:authValueHeader
     contentType:@"application/json"
     completionHandler:completionHandler];
    
    return 0;
}

- (NSArray *_Nonnull) getBodyParamsWithFcmToken:(NSString *)fcmToken title:(NSString *)title body:(NSString *)body topicId:(NSString *)topicId imageName:(NSString *)imageName tagId:(NSString *)tagId colorIcon:(NSString *)colorIcon action:(NSString *)action fromId:(NSString *)fromId codPedido:(NSString *)codPedido description:(NSString *)description estadoPedido:(NSString *)estadoPedido valorPedido:(NSString *)valorPedido payload:(NSDictionary *)payload {
    
    NSDictionary * dataBodyAndroid = @{
        @"to": fcmToken,
        @"priority": @"high",
        @"mutable_content": @NO,
        @"content_available": @YES,
        @"data": @{
            @"title": title,
            @"body": body,
            @"image": imageName,
            @"android_channel_id": @"channel_id",
            @"icon": @"ic_notification",
            @"sound": @"default",
            @"tag": tagId,
            @"color": colorIcon,
            @"action": action,
            @"from_id": fromId,
            @"topic_id": fromId,
            @"cod_pedido": codPedido,
            @"description": description,
            @"estado_pedido": estadoPedido,
            @"valor_pedido": valorPedido,
            @"silent": @NO,
            @"platform": @"android",
            @"type": @"text",
            @"data_chat": payload
        }
    };
    
    NSDictionary * bodyFCMPayload = @{
        @"to": fcmToken,
        @"priority": @"high",
        @"mutable_content": @YES,
        @"content_available": @YES,
        @"restricted_package_name": @"com.example.myandroidapp",
        @"notification": @{
            @"title": title,
            @"body": body,
            @"image": imageName,
            @"click_action": @"FLUTTER_NOTIFICATION_CLICK",
            @"android_channel_id": @"channel_id",
            @"icon": @"ic_notification",
            @"sound": @"default",
            @"badge": @"1",
            /*@"subtitle": @"subtitle",*/
        },
        @"data": @{
            @"title": title,
            @"body": body,
            @"image": imageName,
            @"click_action": @"FLUTTER_NOTIFICATION_CLICK",
            @"android_channel_id": @"channel_id",
            @"icon": @"ic_notification",
            @"sound": @"default",
            @"tag": tagId,
            @"color": colorIcon,
            @"action": action,
            @"from_id": fromId,
            @"topic_id": topicId,
            @"cod_pedido": codPedido,
            @"description": description,
            @"estado_pedido": estadoPedido,
            @"valor_pedido": valorPedido,
            @"silent": @NO,
            @"platform": @"ios",
            @"type": @"text",
            @"data_chat": payload
        },
        @"options": @{
            @"mutableContent": @YES,
            @"apnsPushType": @"alert"
        }
    };
    
    NSArray *bodyParams = @[dataBodyAndroid, bodyFCMPayload];
    //[bodyParams setValue:dataBodyAndroid forKey:@"android"];
    //[bodyParams setValue:dataBodyIOS forKey:@"iOS"];
    
    return bodyParams;
}

@end
