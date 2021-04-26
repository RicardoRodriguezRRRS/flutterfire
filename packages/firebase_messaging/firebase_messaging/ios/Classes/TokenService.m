//
//  TokenService.m
//  firebase_messaging
//
//  Created by Jhonatan Casaliglla on 4/25/21.
//

#import "TokenService.h"
#import "AmzwkHttpUtil.h"
#import "Constants.h"

@interface TokenService()

//- (NSString *_Nonnull) getAuthHeader;

@end

@implementation TokenService {
    NSString *_key;
}

- (void) refreshTokenWithRefreshedToken:(NSString *)refreshedToken andCompletionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    AmzwkHttpUtil *networkHelper = [[AmzwkHttpUtil alloc] initWithUrl: [NSString stringWithFormat: @"%@/%@", __SERVER_DOMAIN, @"api/tokens/refresh"]];
    
    NSString *bodyParams =[NSString stringWithFormat:@"refresh_token=%@", refreshedToken];
    /*NSLog(@"bodyParams es: %@", bodyParams);*/
    //Convert the String to Data
    NSData *dataParams = [bodyParams dataUsingEncoding:NSUTF8StringEncoding];
    
    [networkHelper refreshAuthWithParams:dataParams andContentType:@"application/x-www-form-urlencoded" andCompletionHandler:completionHandler];
}

@end
