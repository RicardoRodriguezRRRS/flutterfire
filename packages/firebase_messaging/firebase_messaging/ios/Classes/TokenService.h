//
//  TokenService.h
//  firebase_messaging
//
//  Created by Jhonatan Casaliglla on 4/25/21.
//

#ifndef TokenService_h
#define TokenService_h

#import <Foundation/Foundation.h>

@interface TokenService : NSObject

- (void) refreshTokenWithRefreshedToken:(NSString *_Nonnull)refreshedToken andCompletionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

@end

#endif /* TokenService_h */
