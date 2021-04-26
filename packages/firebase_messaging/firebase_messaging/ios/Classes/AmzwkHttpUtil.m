//
//  AmzwkHttpUtil.m
//  firebase_messaging
//
//  Created by Jhonatan Casaliglla on 4/25/21.
//

#import "AmzwkHttpUtil.h"

@interface AmzwkHttpUtil()

- (NSData *_Nonnull) getBodyParamsWithJsonParams:(NSDictionary *_Nonnull)jsonParams;
- (int) clientHttpPostWithDataParams:(NSData *)dataParams headers:(NSString *)headers contentType:(NSString *)contentType completionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

@end

@implementation AmzwkHttpUtil {
    NSString *_url;
}

- (instancetype) initWithUrl:(NSString *)url {
    self = [super init];
    if(self) {
        _url = url;
    }
    return self;
}

- (int) postDataWithParams:(NSData *)paramsData andHeaders:(NSString *)headers andContentType:(NSString *)contentType andCompletionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:_url]];
    
    //create the Method "GET" or "POST"
    [urlRequest setHTTPMethod:@"POST"];
    
    //Apply authentication header
    [urlRequest addValue:headers forHTTPHeaderField:@"Authorizationz"];
    
    //Apply the data to the body
    [urlRequest setHTTPBody:paramsData];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:urlRequest completionHandler:completionHandler];
    
    [dataTask resume];
    
    return 0;
}

- (int) postDataNotifyWithDataBodyParams:(NSArray *_Nonnull)dataBodyParams headers:(NSString *)headers contentType:(NSString *)contentType completionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    [self sendToPlatformsWithBodyFcmPayload:[self getBodyParamsWithJsonParams:dataBodyParams[0]] headers:headers contentType:contentType completionHandler:completionHandler];
    
    return 0;
}

- (int) refreshAuthWithParams:(NSData *)paramsData andContentType:(NSString *)contentType andCompletionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:_url]];
    
    //create the Method "GET" or "POST"
    [urlRequest setHTTPMethod:@"POST"];
    
    //Apply the data to the body
    [urlRequest setHTTPBody:paramsData];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:urlRequest completionHandler:completionHandler];
    
    [dataTask resume];
    
    return 0;
}

- (NSData *_Nonnull) getBodyParamsWithJsonParams:(NSDictionary *_Nonnull)jsonParams {
    // Make sure that the above dictionary can be converted to JSON data
    if([NSJSONSerialization isValidJSONObject:jsonParams]) {
        // Convert the JSON object to NSData
        //NSData * httpBodyData = [NSJSONSerialization dataWithJSONObject:dataNotifyMap options:0 error:nil];
        NSLog(@"isValidJSONObject :)");
    }
    
    NSData * httpBodyData = [NSJSONSerialization dataWithJSONObject:jsonParams options:0 error:nil];

    return httpBodyData;
}

- (int) sendToPlatformsWithBodyFcmPayload:(NSData *)bodyFcmPayload headers:(NSString *)headers contentType:(NSString *)contentType completionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    /*[self clientHttpPostWithDataParams:bodyFcmPayload headers:headers contentType:contentType completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"httpResponse.statusCode es: %ld", httpResponse.statusCode);
        
        if(httpResponse.statusCode == 200) {
            NSError *parseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            NSLog(@"iOS The responseDictionary is - %@",responseDictionary);
            
        } else {
            NSError *parseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            NSLog(@"iOS The responseDictionary is - %@", responseDictionary);
            NSLog(@"iOS Error es: %@", error);
        }
    }];*/
    
    return [self clientHttpPostWithDataParams:bodyFcmPayload headers:headers contentType:contentType completionHandler:completionHandler];
}

- (int) clientHttpPostWithDataParams:(NSData *)dataParams headers:(NSString *)headers contentType:(NSString *)contentType completionHandler:(void (^_Nonnull)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:_url]];
    
    //create the Method "GET" or "POST"
    [urlRequest setHTTPMethod:@"POST"];
    
    //Apply authentication header
    [urlRequest addValue:headers forHTTPHeaderField:@"Authorization"];
    [urlRequest setValue:contentType forHTTPHeaderField:@"Content-Type"];
    
    //Apply the data to the body
    [urlRequest setHTTPBody:dataParams];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:urlRequest completionHandler:completionHandler];
    
    [dataTask resume];
    
    return 0;
}

@end
