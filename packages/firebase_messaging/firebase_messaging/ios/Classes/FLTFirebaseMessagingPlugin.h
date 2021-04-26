// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

#import <Firebase/Firebase.h>
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <firebase_core/FLTFirebasePlugin.h>

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
#define __FF_NOTIFICATIONS_SUPPORTED_PLATFORM
#elif defined(__MAC_10_14)
#define __FF_NOTIFICATIONS_SUPPORTED_PLATFORM
#endif

// Suppress warning - use can add the Flutter plugin for Firebase Analytics.
#define FIREBASE_ANALYTICS_SUPPRESS_WARNING

#if TARGET_OS_OSX
#ifdef __FF_NOTIFICATIONS_SUPPORTED_PLATFORM
@interface FLTFirebaseMessagingPlugin : FLTFirebasePlugin <FlutterPlugin,
                                                           FLTFirebasePlugin,
                                                           FIRMessagingDelegate,
                                                           NSApplicationDelegate,
                                                           UNUserNotificationCenterDelegate>
#else
@interface FLTFirebaseMessagingPlugin : FLTFirebasePlugin <FlutterPlugin,
                                                           FLTFirebasePlugin,
                                                           FIRMessagingDelegate,
                                                           NSApplicationDelegate>
#endif
#else
#ifdef __FF_NOTIFICATIONS_SUPPORTED_PLATFORM
API_AVAILABLE(ios(10.0))
@interface FLTFirebaseMessagingPlugin : FLTFirebasePlugin <FlutterPlugin,
                                                           FLTFirebasePlugin,
                                                           FIRMessagingDelegate,
                                                           UNUserNotificationCenterDelegate>
- (void) sendNotificationWithTitle:(NSString *_Nonnull)title body:(NSString *_Nonnull)body userId:(NSString *_Nonnull)userId channelId:(NSString *_Nonnull)channelId color:(NSString *_Nonnull)color userImage:(NSString *_Nonnull)userImage action:(NSString *_Nonnull)action fromId:(NSString *_Nonnull)fromId codPedido:(NSString *_Nonnull)codPedido description:(NSString *_Nonnull)description estadoPedido:(NSString *_Nonnull)estadoPedido valorPedido:(NSString *_Nonnull)valorPedido dataChat:(NSDictionary *_Nonnull)dataChat completionHandler:(void (^_Nullable)(void))completionHandler;
#else
@interface FLTFirebaseMessagingPlugin
    : FLTFirebasePlugin <FlutterPlugin, FLTFirebasePlugin, FIRMessagingDelegate>
#endif
#endif
@end
