//
//  ChatworkService.h
//  firebase_messaging
//
//  Created by Jhonatan Casaliglla on 4/25/21.
//

#ifndef ChatworkService_h
#define ChatworkService_h


#import <Foundation/Foundation.h>

@interface ChatworkService : NSObject

- (void) saveMessageWithTextMessage:(NSString *_Nonnull)textMessage andChannelId:(NSString *_Nonnull)channelId andCreateAt:(NSString *_Nonnull)createAt andCompletionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

@end

#endif /* ChatworkService_h */
