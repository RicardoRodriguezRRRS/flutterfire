//
//  MessagingService.h
//  firebase_messaging
//
//  Created by Jhonatan Casaliglla on 11/20/19.
//

#ifndef MessagingService_h
#define MessagingService_h

#import <Foundation/Foundation.h>

@interface MessagingService : NSObject

- (int) sendToTopicWithTitle:(NSString *_Nonnull)title body:(NSString *)body topic:(NSString *)topic tagId:(NSString *)tagId colorIcon:(NSString *)colorIcon imageName:(NSString *)imageName action:(NSString *)action fromId:(NSString *)fromId codPedido:(NSString *)codPedido description:(NSString *)description estadoPedido:(NSString *)estadoPedido valorPedido:(NSString *)valorPedido payload:(NSDictionary *)payload andCompletionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;;

@end

#endif /* MessagingService_h */
