// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <GoogleUtilities/GULAppDelegateSwizzler.h>
#import <firebase_core/FLTFirebasePluginRegistry.h>
#import <objc/message.h>

#import "FLTFirebaseMessagingPlugin.h"

#import "ChatworkService.h"
#import "TokenService.h"
#import "MessagingService.h"
#import "Constants.h"

NSString *const kFLTFirebaseMessagingChannelName = @"plugins.flutter.io/firebase_messaging";

NSString *const kMessagingArgumentCode = @"code";
NSString *const kMessagingArgumentMessage = @"message";
NSString *const kMessagingArgumentAdditionalData = @"additionalData";
NSString *const kMessagingPresentationOptionsUserDefaults =
    @"flutter_firebase_messaging_presentation_options";

NSString *const kGCMMessageIDKey = @"gcm.message_id";
NSString *const kGCMMessageSilentKey = @"silent";

NSString *const replyAction = @"REPLY_IDENTIFIER";
NSString *const generalCategory = @"FLUTTER_NOTIFICATION_CLICK";
NSString *const COLOR_PROVEEDOR = @"0x4caf50";
NSString *const COLOR_CONSUMIDOR = @"0x0288D1";

@implementation FLTFirebaseMessagingPlugin {
  FlutterMethodChannel *_channel;
  NSObject<FlutterPluginRegistrar> *_registrar;
  NSDictionary *_initialNotification;

#ifdef __FF_NOTIFICATIONS_SUPPORTED_PLATFORM
  API_AVAILABLE(ios(10), macosx(10.14))
  __weak id<UNUserNotificationCenterDelegate> _originalNotificationCenterDelegate;
  API_AVAILABLE(ios(10), macosx(10.14))
  struct {
    unsigned int willPresentNotification : 1;
    unsigned int didReceiveNotificationResponse : 1;
    unsigned int openSettingsForNotification : 1;
  } _originalNotificationCenterDelegateRespondsTo;
#endif
}

#pragma mark - FlutterPlugin

- (instancetype)initWithFlutterMethodChannel:(FlutterMethodChannel *)channel
                   andFlutterPluginRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  self = [super init];
  if (self) {
    _channel = channel;
    _registrar = registrar;

    // Application
    // Dart -> `getInitialNotification`
    // ObjC -> Initialize other delegates & observers
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(application_onDidFinishLaunchingNotification:)
#if TARGET_OS_OSX
               name:NSApplicationDidFinishLaunchingNotification
#else
               name:UIApplicationDidFinishLaunchingNotification
#endif
             object:nil];
  }
  return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kFLTFirebaseMessagingChannelName
                                  binaryMessenger:[registrar messenger]];
  id instance = [[FLTFirebaseMessagingPlugin alloc] initWithFlutterMethodChannel:channel
                                                       andFlutterPluginRegistrar:registrar];
  // Register with internal FlutterFire plugin registry.
  [[FLTFirebasePluginRegistry sharedInstance] registerFirebasePlugin:instance];

  [registrar addMethodCallDelegate:instance channel:channel];
#if !TARGET_OS_OSX
  [registrar publish:instance];  // iOS only supported
#endif
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)flutterResult {
  FLTFirebaseMethodCallErrorBlock errorBlock = ^(
      NSString *_Nullable code, NSString *_Nullable message, NSDictionary *_Nullable details,
      NSError *_Nullable error) {
    if (code == nil) {
      NSDictionary *errorDetails = [self NSDictionaryForNSError:error];
      code = errorDetails[kMessagingArgumentCode];
      message = errorDetails[kMessagingArgumentMessage];
      details = errorDetails;
    } else {
      details = @{
        kMessagingArgumentCode : code,
        kMessagingArgumentMessage : message,
      };
    }

    if ([@"unknown" isEqualToString:code]) {
      NSLog(@"FLTFirebaseMessaging: An error occurred while calling method %@, errorOrNil => %@",
            call.method, [error userInfo]);
    }

    flutterResult([FLTFirebasePlugin createFlutterErrorFromCode:code
                                                        message:message
                                                optionalDetails:details
                                             andOptionalNSError:error]);
  };

  FLTFirebaseMethodCallResult *methodCallResult =
      [FLTFirebaseMethodCallResult createWithSuccess:flutterResult andErrorBlock:errorBlock];

  if ([@"Messaging#getInitialMessage" isEqualToString:call.method]) {
    methodCallResult.success([self copyInitialNotification]);
  } else if ([@"Messaging#deleteToken" isEqualToString:call.method]) {
    [self messagingDeleteToken:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Messaging#getAPNSToken" isEqualToString:call.method]) {
    [self messagingGetAPNSToken:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Messaging#setForegroundNotificationPresentationOptions"
                 isEqualToString:call.method]) {
    [self messagingSetForegroundNotificationPresentationOptions:call.arguments
                                           withMethodCallResult:methodCallResult];
  } else if ([@"Messaging#getToken" isEqualToString:call.method]) {
    [self messagingGetToken:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Messaging#getNotificationSettings" isEqualToString:call.method]) {
    if (@available(iOS 10, macOS 10.14, *)) {
      [self messagingGetNotificationSettings:call.arguments withMethodCallResult:methodCallResult];
    } else {
      // Defaults handled in Dart.
      methodCallResult.success(@{});
    }
  } else if ([@"Messaging#requestPermission" isEqualToString:call.method]) {
    if (@available(iOS 10, macOS 10.14, *)) {
      [self messagingRequestPermission:call.arguments withMethodCallResult:methodCallResult];
    } else {
      // Defaults handled in Dart.
      methodCallResult.success(@{});
    }
  } else if ([@"Messaging#setAutoInitEnabled" isEqualToString:call.method]) {
    [self messagingSetAutoInitEnabled:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Messaging#subscribeToTopic" isEqualToString:call.method]) {
    [self messagingSubscribeToTopic:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Messaging#unsubscribeFromTopic" isEqualToString:call.method]) {
    [self messagingUnsubscribeFromTopic:call.arguments withMethodCallResult:methodCallResult];
  } else if ([@"Messaging#startBackgroundIsolate" isEqualToString:call.method]) {
    methodCallResult.success(nil);
  } else {
    methodCallResult.success(FlutterMethodNotImplemented);
  }
}
- (void)messagingSetForegroundNotificationPresentationOptions:(id)arguments
                                         withMethodCallResult:
                                             (FLTFirebaseMethodCallResult *)result {
  NSMutableDictionary *persistedOptions = [NSMutableDictionary dictionary];
  if ([arguments[@"alert"] isEqual:@(YES)]) {
    persistedOptions[@"alert"] = @YES;
  }
  if ([arguments[@"badge"] isEqual:@(YES)]) {
    persistedOptions[@"badge"] = @YES;
  }
  if ([arguments[@"sound"] isEqual:@(YES)]) {
    persistedOptions[@"sound"] = @YES;
  }

  [[NSUserDefaults standardUserDefaults] setObject:persistedOptions
                                            forKey:kMessagingPresentationOptionsUserDefaults];
  result.success(nil);
}

#pragma mark - Firebase Messaging Delegate

- (void)messaging:(nonnull FIRMessaging *)messaging
    didReceiveRegistrationToken:(nullable NSString *)fcmToken {
  // Don't crash if the token is reset.
  if (fcmToken == nil) {
    return;
  }

  // Send to Dart.
  [_channel invokeMethod:@"Messaging#onTokenRefresh" arguments:fcmToken];

  // If the users AppDelegate implements messaging:didReceiveRegistrationToken: then call it as well
  // so we don't break other libraries.
  SEL messaging_didReceiveRegistrationTokenSelector =
      NSSelectorFromString(@"messaging:didReceiveRegistrationToken:");
  if ([[GULAppDelegateSwizzler sharedApplication].delegate
          respondsToSelector:messaging_didReceiveRegistrationTokenSelector]) {
    void (*usersDidReceiveRegistrationTokenIMP)(id, SEL, FIRMessaging *, NSString *) =
        (typeof(usersDidReceiveRegistrationTokenIMP)) & objc_msgSend;
    usersDidReceiveRegistrationTokenIMP([GULAppDelegateSwizzler sharedApplication].delegate,
                                        messaging_didReceiveRegistrationTokenSelector, messaging,
                                        fcmToken);
  }
}

#pragma mark - NSNotificationCenter Observers

- (void)application_onDidFinishLaunchingNotification:(nonnull NSNotification *)notification {
  // Setup UIApplicationDelegate.
#if TARGET_OS_OSX
  // For macOS we use swizzling to intercept as addApplicationDelegate does not exist on the macOS
  // registrar Flutter implementation.
  [GULAppDelegateSwizzler registerAppDelegateInterceptor:self];
  [GULAppDelegateSwizzler proxyOriginalDelegateIncludingAPNSMethods];

  SEL didReceiveRemoteNotificationWithCompletionSEL =
      NSSelectorFromString(@"application:didReceiveRemoteNotification:fetchCompletionHandler:");
  if ([[GULAppDelegateSwizzler sharedApplication].delegate
          respondsToSelector:didReceiveRemoteNotificationWithCompletionSEL]) {
    // noop - user has own implementation of this method in their AppDelegate, this
    // means GULAppDelegateSwizzler will have already replaced it with a donor method
  } else {
    // add our own donor implementation of
    // application:didReceiveRemoteNotification:fetchCompletionHandler:
    Method donorMethod = class_getInstanceMethod(object_getClass(self),
                                                 didReceiveRemoteNotificationWithCompletionSEL);
    class_addMethod(object_getClass([GULAppDelegateSwizzler sharedApplication].delegate),
                    didReceiveRemoteNotificationWithCompletionSEL,
                    method_getImplementation(donorMethod), method_getTypeEncoding(donorMethod));
  }
#else
  [_registrar addApplicationDelegate:self];
#endif

  // Set UNUserNotificationCenter but preserve original delegate if necessary.
  if (@available(iOS 10.0, macOS 10.14, *)) {
    BOOL shouldReplaceDelegate = YES;
    UNUserNotificationCenter *notificationCenter =
        [UNUserNotificationCenter currentNotificationCenter];

    if (notificationCenter.delegate != nil) {
#if !TARGET_OS_OSX
      // If the App delegate exists and it conforms to UNUserNotificationCenterDelegate then we
      // don't want to replace it on iOS as the earlier call to `[_registrar
      // addApplicationDelegate:self];` will automatically delegate calls to this plugin. If we
      // replace it, it will cause a stack overflow as our original delegate forwarding handler
      // below causes an infinite loop of forwarding. See
      // https://github.com/FirebaseExtended/flutterfire/issues/4026.
      if ([GULApplication sharedApplication].delegate != nil &&
          [[GULApplication sharedApplication].delegate
              conformsToProtocol:@protocol(UNUserNotificationCenterDelegate)]) {
        // Note this one only executes if Firebase swizzling is **enabled**.
        shouldReplaceDelegate = NO;
      }
#endif

      if (shouldReplaceDelegate) {
        _originalNotificationCenterDelegate = notificationCenter.delegate;
        _originalNotificationCenterDelegateRespondsTo.openSettingsForNotification =
            (unsigned int)[_originalNotificationCenterDelegate
                respondsToSelector:@selector(userNotificationCenter:openSettingsForNotification:)];
        _originalNotificationCenterDelegateRespondsTo.willPresentNotification =
            (unsigned int)[_originalNotificationCenterDelegate
                respondsToSelector:@selector(userNotificationCenter:
                                            willPresentNotification:withCompletionHandler:)];
        _originalNotificationCenterDelegateRespondsTo.didReceiveNotificationResponse =
            (unsigned int)[_originalNotificationCenterDelegate
                respondsToSelector:@selector(userNotificationCenter:
                                       didReceiveNotificationResponse:withCompletionHandler:)];
      }
    }

    if (shouldReplaceDelegate) {
      __strong FLTFirebasePlugin<UNUserNotificationCenterDelegate> *strongSelf = self;
      notificationCenter.delegate = strongSelf;
    }
  }

  // We automatically register for remote notifications as
  // application:didReceiveRemoteNotification:fetchCompletionHandler: will not get called unless
  // registerForRemoteNotifications is called early on during app initialization, calling this from
  // Dart would be too late.
#if TARGET_OS_OSX
  if (@available(macOS 10.14, *)) {
    [[NSApplication sharedApplication] registerForRemoteNotifications];
  }
#else
  [[UIApplication sharedApplication] registerForRemoteNotifications];
#endif
}

#pragma mark - UNUserNotificationCenter Delegate Methods

#ifdef __FF_NOTIFICATIONS_SUPPORTED_PLATFORM
// Called when a notification is received whilst the app is in the foreground.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:
             (void (^)(UNNotificationPresentationOptions options))completionHandler
    API_AVAILABLE(macos(10.14), ios(10.0)) {
  // We only want to handle FCM notifications.
  if (notification.request.content.userInfo[@"gcm.message_id"]) {
    NSDictionary *notificationDict =
        [FLTFirebaseMessagingPlugin NSDictionaryFromUNNotification:notification];

    // Don't send an event if contentAvailable is true - application:didReceiveRemoteNotification
    // will send the event for us, we don't want to duplicate them.
    if (!notificationDict[@"contentAvailable"]) {
      [_channel invokeMethod:@"Messaging#onMessage" arguments:notificationDict];
    }
  }

  // Forward on to any other delegates amd allow them to control presentation behavior.
  if (_originalNotificationCenterDelegate != nil &&
      _originalNotificationCenterDelegateRespondsTo.willPresentNotification) {
    [_originalNotificationCenterDelegate userNotificationCenter:center
                                        willPresentNotification:notification
                                          withCompletionHandler:completionHandler];
  } else {
    UNNotificationPresentationOptions presentationOptions = UNNotificationPresentationOptionNone;
    NSDictionary *persistedOptions = [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:kMessagingPresentationOptionsUserDefaults];
    if (persistedOptions != nil) {
      if ([persistedOptions[@"alert"] isEqual:@(YES)]) {
        presentationOptions |= UNNotificationPresentationOptionAlert;
      }
      if ([persistedOptions[@"badge"] isEqual:@(YES)]) {
        presentationOptions |= UNNotificationPresentationOptionBadge;
      }
      if ([persistedOptions[@"sound"] isEqual:@(YES)]) {
        presentationOptions |= UNNotificationPresentationOptionSound;
      }
    }
    completionHandler(presentationOptions);
  }
}

// Called when a use interacts with a notification.
/*- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler
    API_AVAILABLE(macos(10.14), ios(10.0)) {
  NSDictionary *remoteNotification = response.notification.request.content.userInfo;
  // We only want to handle FCM notifications.
  if (remoteNotification[@"gcm.message_id"]) {
    NSDictionary *notificationDict =
        [FLTFirebaseMessagingPlugin remoteMessageUserInfoToDict:remoteNotification];
    [_channel invokeMethod:@"Messaging#onMessageOpenedApp" arguments:notificationDict];
    @synchronized(self) {
      _initialNotification = notificationDict;
    }
  }

  // Forward on to any other delegates.
  if (_originalNotificationCenterDelegate != nil &&
      _originalNotificationCenterDelegateRespondsTo.didReceiveNotificationResponse) {
    [_originalNotificationCenterDelegate userNotificationCenter:center
                                 didReceiveNotificationResponse:response
                                          withCompletionHandler:completionHandler];
  } else {
    completionHandler();
  }
}*/

// Handle notification messages after display notification is tapped by the user.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
           didReceiveNotificationResponse:(UNTextInputNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler  API_AVAILABLE(macos(10.14), ios(10.0)) {
    //fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
    
    NSLog(@"409 - (void)userNotificationCenter:didReceiveNotificationResponsewithCompletionHandler");

    if ([response.notification.request.content.categoryIdentifier isEqualToString:generalCategory]) {
        // Handle the actions for the expired timer.
        if ([response.actionIdentifier isEqualToString:replyAction]) {
            NSLog(@"414 Button responder pressed! :)");
            NSLog(@"415 response.userText es: %@", response.userText);
            [self handleReplyActionWithResponse:response withCompletionHandler:completionHandler];
            /*completionHandler();*/
            return;
        } /*else if ([response.actionIdentifier isEqualToString:@"APPROVE_ACTION"]) {
            NSLog(@"325 Button aprobar pressed! :)");
        }*/
    }
    
    NSDictionary *remoteNotification = response.notification.request.content.userInfo;
    // Check to key to ensure we only handle messages from Firebase
    // We only want to handle FCM notifications.
    if (remoteNotification[kGCMMessageIDKey]) {
      NSDictionary *notificationDict =
          [FLTFirebaseMessagingPlugin remoteMessageUserInfoToDict:remoteNotification];
      [_channel invokeMethod:@"Messaging#onMessageOpenedApp" arguments:notificationDict];
      @synchronized(self) {
        _initialNotification = notificationDict;
      }
    }
    
    // Forward on to any other delegates.
    if (_originalNotificationCenterDelegate != nil &&
        _originalNotificationCenterDelegateRespondsTo.didReceiveNotificationResponse) {
      [_originalNotificationCenterDelegate userNotificationCenter:center
                                   didReceiveNotificationResponse:response
                                            withCompletionHandler:completionHandler];
    } else {
      completionHandler();
    }
}

// We don't use this for FlutterFire, but for the purpose of forwarding to any original delegates we
// implement this.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    openSettingsForNotification:(nullable UNNotification *)notification
    API_AVAILABLE(macos(10.14), ios(10.0)) {
  // Forward on to any other delegates.
  if (_originalNotificationCenterDelegate != nil &&
      _originalNotificationCenterDelegateRespondsTo.openSettingsForNotification) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    [_originalNotificationCenterDelegate userNotificationCenter:center
                                    openSettingsForNotification:notification];
#pragma clang diagnostic pop
  }
}

#endif

#pragma mark - AppDelegate Methods

#if TARGET_OS_OSX
// Called when `registerForRemoteNotifications` completes successfully.
- (void)application:(NSApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
#else
- (void)application:(UIApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
#endif
#ifdef DEBUG
  [[FIRMessaging messaging] setAPNSToken:deviceToken type:FIRMessagingAPNSTokenTypeSandbox];
#else
  [[FIRMessaging messaging] setAPNSToken:deviceToken type:FIRMessagingAPNSTokenTypeProd];
#endif
}
    
- (void)applicationDidBecomeActive:(UIApplication *)application {
  // Clears push notifications from the notification center, with the
  // side effect of resetting the badge count. We need to clear notifications
  // because otherwise the user could tap notifications in the notification
  // center while the app is in the foreground, and we wouldn't be able to
  // distinguish that case from the case where a message came in and the
  // user dismissed the notification center without tapping anything.
  // TODO(goderbauer): Revisit this behavior once we provide an API for managing
  // the badge number, or if we add support for running Dart in the background.
  // Setting badgeNumber to 0 is a no-op (= notifications will not be cleared)
  // if it is already 0,
  // therefore the next line is setting it to 1 first before clearing it again
  // to remove all notifications.
  application.applicationIconBadgeNumber = 1;
  application.applicationIconBadgeNumber = 0;
}

#if TARGET_OS_OSX
// Called when `registerForRemoteNotifications` fails to complete.
- (void)application:(NSApplication *)application
    didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
#else
- (void)application:(UIApplication *)application
    didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
#endif
  NSLog(@"%@", error.localizedDescription);
}

// Called when a remote notification is received via APNs.
#if TARGET_OS_OSX
- (void)application:(NSApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo {
  // Only handle notifications from FCM.
  if (userInfo[@"gcm.message_id"]) {
    NSDictionary *notificationDict =
        [FLTFirebaseMessagingPlugin remoteMessageUserInfoToDict:userInfo];

    if ([NSApplication sharedApplication].isActive) {
      [_channel invokeMethod:@"Messaging#onMessage" arguments:notificationDict];
    } else {
      [_channel invokeMethod:@"Messaging#onBackgroundMessage" arguments:notificationDict];
    }
  }
}
#endif

#if !TARGET_OS_OSX
- (BOOL)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
    /*NSLog( @"490 didReceiveRemoteNotification()." );*/
#if __has_include(<FirebaseAuth/FirebaseAuth.h>)
  if ([[FIRAuth auth] canHandleNotification:userInfo]) {
    completionHandler(UIBackgroundFetchResultNoData);
    return YES;
  }
#endif
  /*NSLog(@"498 userInfo es: %@", userInfo);*/
  /*NSLog(@"498 platform ID: %@", userInfo[@"platform"]);*/
  if([userInfo[@"platform"] isEqualToString:@"android"]) {
      completionHandler(UIBackgroundFetchResultNoData);
      return YES;
  }
  // Only handle notifications from FCM.
  if (userInfo[@"gcm.message_id"]) {
    NSDictionary *notificationDict =
        [FLTFirebaseMessagingPlugin remoteMessageUserInfoToDict:userInfo];
      /*NSLog( @"507 [UIApplication sharedApplication].applicationState() == UIApplicationStateBackground" );*/
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
      __block BOOL completed = NO;

      // If app is in background state, register background task to guarantee async queues aren't
      // frozen.
      UIBackgroundTaskIdentifier __block backgroundTaskId =
          [application beginBackgroundTaskWithExpirationHandler:^{
            @synchronized(self) {
              if (completed == NO) {
                completed = YES;
                completionHandler(UIBackgroundFetchResultNewData);
                if (backgroundTaskId != UIBackgroundTaskInvalid) {
                  [application endBackgroundTask:backgroundTaskId];
                  backgroundTaskId = UIBackgroundTaskInvalid;
                }
              }
            }
          }];

      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)),
                     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                       @synchronized(self) {
                         if (completed == NO) {
                           completed = YES;
                           completionHandler(UIBackgroundFetchResultNewData);
                           if (backgroundTaskId != UIBackgroundTaskInvalid) {
                             [application endBackgroundTask:backgroundTaskId];
                             backgroundTaskId = UIBackgroundTaskInvalid;
                           }
                         }
                       }
                     });

      [_channel invokeMethod:@"Messaging#onBackgroundMessage"
                   arguments:notificationDict
                      result:^(id _Nullable result) {
                        @synchronized(self) {
                          if (completed == NO) {
                            completed = YES;
                            completionHandler(UIBackgroundFetchResultNewData);
                            if (backgroundTaskId != UIBackgroundTaskInvalid) {
                              [application endBackgroundTask:backgroundTaskId];
                              backgroundTaskId = UIBackgroundTaskInvalid;
                            }
                          }
                        }
                      }];
    } else {
      [_channel invokeMethod:@"Messaging#onMessage" arguments:notificationDict];
      completionHandler(UIBackgroundFetchResultNoData);
    }

    return YES;
  }  // if (userInfo[@"gcm.message_id"])
  return NO;
}  // didReceiveRemoteNotification
#endif

#pragma mark - Firebase Messaging API

- (void)messagingUnsubscribeFromTopic:(id)arguments
                 withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  FIRMessaging *messaging = [FIRMessaging messaging];
  NSString *topic = arguments[@"topic"];
  [messaging unsubscribeFromTopic:topic
                       completion:^(NSError *error) {
                         if (error != nil) {
                           result.error(nil, nil, nil, error);
                         } else {
                           result.success(nil);
                         }
                       }];
}

- (void)messagingSubscribeToTopic:(id)arguments
             withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  FIRMessaging *messaging = [FIRMessaging messaging];
  NSString *topic = arguments[@"topic"];
  [messaging subscribeToTopic:topic
                   completion:^(NSError *error) {
                     if (error != nil) {
                       result.error(nil, nil, nil, error);
                     } else {
                       result.success(nil);
                     }
                   }];
}

- (void)messagingSetAutoInitEnabled:(id)arguments
               withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  FIRMessaging *messaging = [FIRMessaging messaging];
  messaging.autoInitEnabled = [arguments[@"enabled"] boolValue];
  result.success(@{
    @"isAutoInitEnabled" : @(messaging.isAutoInitEnabled),
  });
}

- (void)messagingRequestPermission:(id)arguments
              withMethodCallResult:(FLTFirebaseMethodCallResult *)result
    API_AVAILABLE(ios(10), macosx(10.14)) {
  NSDictionary *permissions = arguments[@"permissions"];
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

  UNAuthorizationOptions options = UNAuthorizationOptionNone;
  NSNumber *isAtLeastVersion12;

  if ([permissions[@"alert"] isEqual:@(YES)]) {
    options |= UNAuthorizationOptionAlert;
  }

  if ([permissions[@"badge"] isEqual:@(YES)]) {
    options |= UNAuthorizationOptionBadge;
  }

  if ([permissions[@"sound"] isEqual:@(YES)]) {
    options |= UNAuthorizationOptionSound;
  }

  if ([permissions[@"provisional"] isEqual:@(YES)]) {
    if (@available(iOS 12.0, *)) {
      isAtLeastVersion12 = [NSNumber numberWithBool:YES];
      options |= UNAuthorizationOptionProvisional;
    } else {
      isAtLeastVersion12 = [NSNumber numberWithBool:YES];
    }
  }

  if ([permissions[@"announcement"] isEqual:@(YES)]) {
    if (@available(iOS 13.0, *)) {
      // TODO not available in iOS9 deployment target - enable once iOS10+ deployment target
      // specified in podspec. options |= UNAuthorizationOptionAnnouncement;
    }
  }

  if ([permissions[@"carPlay"] isEqual:@(YES)]) {
    options |= UNAuthorizationOptionCarPlay;
  }

  if ([permissions[@"criticalAlert"] isEqual:@(YES)]) {
    if (@available(iOS 12.0, *)) {
      options |= UNAuthorizationOptionCriticalAlert;
    }
  }

  id handler = ^(BOOL granted, NSError *_Nullable error) {
    if (error != nil) {
        
      result.error(nil, nil, nil, error);
      return;
    }
      
      NSLog(@"144 Permission granted: %d", granted);
      NSLog( @"145 Push registration success." );
    
      UNNotificationAction* replyAct = [UNTextInputNotificationAction
                                          actionWithIdentifier: replyAction
                                          title:@"Responder"
                                          options:UNNotificationActionOptionNone];  //UNNotificationActionOptionForeground
    
      /*UNNotificationAction* approveAct = [UNNotificationAction
                                        actionWithIdentifier: @"APPROVE_ACTION"
                                        title:@"Aprobar"
                                        options:UNNotificationActionOptionNone];  //UNNotificationActionOptionForeground*/
    
      UNNotificationCategory* generalCat = [UNNotificationCategory
                                          categoryWithIdentifier: generalCategory
                                          actions:@[replyAct]
                                          intentIdentifiers:@[]
                                          options:UNNotificationCategoryOptionCustomDismissAction];

      /*[[UNUserNotificationCenter currentNotificationCenter]
       setNotificationCategories:[NSSet setWithObjects:generalCat, nil]];
       result([NSNumber numberWithBool:granted]);*/

      [[UNUserNotificationCenter currentNotificationCenter]
       setNotificationCategories:[NSSet setWithObjects:generalCat, nil]];

      [[UNUserNotificationCenter currentNotificationCenter]
        getNotificationSettingsWithCompletionHandler:^(
            UNNotificationSettings *_Nonnull settings) {
          
        }];
      //result([NSNumber numberWithBool:granted]);
      
    [center getNotificationSettingsWithCompletionHandler:^(
                UNNotificationSettings *_Nonnull settings) {
      /*NSDictionary *settingsDictionary = @{
        @"sound" : [NSNumber numberWithBool:settings.soundSetting ==
                                            UNNotificationSettingEnabled],
        @"badge" : [NSNumber numberWithBool:settings.badgeSetting ==
                                            UNNotificationSettingEnabled],
        @"alert" : [NSNumber numberWithBool:settings.alertSetting ==
                                            UNNotificationSettingEnabled],
        @"provisional" :
            [NSNumber numberWithBool:granted && [permissions[@"provisional"] isEqual:@(YES)] &&
                                     isAtLeastVersion12],
      };*/
      /*[self->_channel invokeMethod:@"onIosSettingsRegistered"
                         arguments:settingsDictionary];*/
      result.success(
          [FLTFirebaseMessagingPlugin NSDictionaryFromUNNotificationSettings:settings]);
    }];
  };

  [center requestAuthorizationWithOptions:options completionHandler:handler];
  [[UIApplication sharedApplication] registerForRemoteNotifications];
}

- (void)messagingGetNotificationSettings:(id)arguments
                    withMethodCallResult:(FLTFirebaseMethodCallResult *)result
    API_AVAILABLE(ios(10), macos(10.14)) {
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center getNotificationSettingsWithCompletionHandler:^(
              UNNotificationSettings *_Nonnull settings) {
    result.success([FLTFirebaseMessagingPlugin NSDictionaryFromUNNotificationSettings:settings]);
  }];
}

- (void)messagingGetToken:(id)arguments withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  FIRMessaging *messaging = [FIRMessaging messaging];
  NSString *senderId = arguments[@"senderId"];
  if ([senderId isEqual:[NSNull null]]) {
    senderId = [FIRApp defaultApp].options.GCMSenderID;
  }
  [messaging retrieveFCMTokenForSenderID:senderId
                              completion:^(NSString *token, NSError *error) {
                                if (error != nil) {
                                  result.error(nil, nil, nil, error);
                                } else {
                                  result.success(@{@"token" : token});
                                }
                              }];
}

- (void)messagingGetAPNSToken:(id)arguments
         withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  NSData *apnsToken = [FIRMessaging messaging].APNSToken;
  if (apnsToken) {
    result.success(@{@"token" : [FLTFirebaseMessagingPlugin APNSTokenFromNSData:apnsToken]});
  } else {
    result.success(@{@"token" : [NSNull null]});
  }
}

- (void)messagingDeleteToken:(id)arguments
        withMethodCallResult:(FLTFirebaseMethodCallResult *)result {
  FIRMessaging *messaging = [FIRMessaging messaging];
  NSString *senderId = arguments[@"senderId"];
  if ([senderId isEqual:[NSNull null]]) {
    senderId = [FIRApp defaultApp].options.GCMSenderID;
  }
  [messaging deleteFCMTokenForSenderID:senderId
                            completion:^(NSError *error) {
                              if (error != nil) {
                                result.error(nil, nil, nil, error);
                              } else {
                                result.success(nil);
                              }
                            }];
}

#pragma mark - FLTFirebasePlugin

- (void)didReinitializeFirebaseCore:(void (^)(void))completion {
  completion();
}

- (NSDictionary *_Nonnull)pluginConstantsForFIRApp:(FIRApp *)firebase_app {
  return @{
    @"AUTO_INIT_ENABLED" : @([FIRMessaging messaging].isAutoInitEnabled),
  };
}

- (NSString *_Nonnull)firebaseLibraryName {
  return LIBRARY_NAME;
}

- (NSString *_Nonnull)firebaseLibraryVersion {
  return LIBRARY_VERSION;
}

- (NSString *_Nonnull)flutterChannelName {
  return kFLTFirebaseMessagingChannelName;
}

#pragma mark - Utilities

+ (NSDictionary *)NSDictionaryFromUNNotificationSettings:(UNNotificationSettings *_Nonnull)settings
    API_AVAILABLE(ios(10), macos(10.14)) {
  NSMutableDictionary *settingsDictionary = [NSMutableDictionary dictionary];

  // authorizedStatus
  NSNumber *authorizedStatus = @-1;
  if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
    authorizedStatus = @-1;
  } else if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
    authorizedStatus = @0;
  } else if (settings.authorizationStatus == UNAuthorizationStatusAuthorized) {
    authorizedStatus = @1;
  }

  if (@available(iOS 12.0, *)) {
    if (settings.authorizationStatus == UNAuthorizationStatusProvisional) {
      authorizedStatus = @2;
    }
  }

  NSNumber *showPreviews = @-1;
  if (@available(iOS 11.0, *)) {
    if (settings.showPreviewsSetting == UNShowPreviewsSettingNever) {
      showPreviews = @0;
    } else if (settings.showPreviewsSetting == UNShowPreviewsSettingAlways) {
      showPreviews = @1;
    } else if (settings.showPreviewsSetting == UNShowPreviewsSettingWhenAuthenticated) {
      showPreviews = @2;
    }
  }

#pragma clang diagnostic push
#pragma ide diagnostic ignored "OCSimplifyInspectionLegacy"
  if (@available(iOS 13.0, *)) {
    // TODO not available in iOS9 deployment target - enable once iOS10+ deployment target specified
    // in podspec. settingsDictionary[@"announcement"] =
    //   [FLTFirebaseMessagingPlugin NSNumberForUNNotificationSetting:settings.announcementSetting];
    settingsDictionary[@"announcement"] = @-1;
  } else {
    settingsDictionary[@"announcement"] = @-1;
  }
#pragma clang diagnostic pop

  if (@available(iOS 12.0, *)) {
    settingsDictionary[@"criticalAlert"] =
        [FLTFirebaseMessagingPlugin NSNumberForUNNotificationSetting:settings.criticalAlertSetting];
  } else {
    settingsDictionary[@"criticalAlert"] = @-1;
  }

  settingsDictionary[@"showPreviews"] = showPreviews;
  settingsDictionary[@"authorizationStatus"] = authorizedStatus;
  settingsDictionary[@"alert"] =
      [FLTFirebaseMessagingPlugin NSNumberForUNNotificationSetting:settings.alertSetting];
  settingsDictionary[@"badge"] =
      [FLTFirebaseMessagingPlugin NSNumberForUNNotificationSetting:settings.badgeSetting];
  settingsDictionary[@"sound"] =
      [FLTFirebaseMessagingPlugin NSNumberForUNNotificationSetting:settings.soundSetting];
#if TARGET_OS_OSX
  settingsDictionary[@"carPlay"] = @-1;
#else
  settingsDictionary[@"carPlay"] =
      [FLTFirebaseMessagingPlugin NSNumberForUNNotificationSetting:settings.carPlaySetting];
#endif
  settingsDictionary[@"lockScreen"] =
      [FLTFirebaseMessagingPlugin NSNumberForUNNotificationSetting:settings.lockScreenSetting];
  settingsDictionary[@"notificationCenter"] = [FLTFirebaseMessagingPlugin
      NSNumberForUNNotificationSetting:settings.notificationCenterSetting];
  return settingsDictionary;
}

+ (NSNumber *)NSNumberForUNNotificationSetting:(UNNotificationSetting)setting
    API_AVAILABLE(ios(10), macos(10.14)) {
  NSNumber *asNumber = @-1;

  if (setting == UNNotificationSettingNotSupported) {
    asNumber = @-1;
  } else if (setting == UNNotificationSettingDisabled) {
    asNumber = @0;
  } else if (setting == UNNotificationSettingEnabled) {
    asNumber = @1;
  }
  return asNumber;
}

+ (NSString *)APNSTokenFromNSData:(NSData *)tokenData {
  const char *data = [tokenData bytes];

  NSMutableString *token = [NSMutableString string];
  for (NSInteger i = 0; i < tokenData.length; i++) {
    [token appendFormat:@"%02.2hhX", data[i]];
  }

  return [token copy];
}

#if TARGET_OS_OSX
+ (NSDictionary *)NSDictionaryFromUNNotification:(UNNotification *)notification
    API_AVAILABLE(macos(10.14)) {
#else
+ (NSDictionary *)NSDictionaryFromUNNotification:(UNNotification *)notification {
#endif
  return [self remoteMessageUserInfoToDict:notification.request.content.userInfo];
}

+ (NSDictionary *)remoteMessageUserInfoToDict:(NSDictionary *)userInfo {
  NSMutableDictionary *message = [[NSMutableDictionary alloc] init];
  NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
  NSMutableDictionary *notification = [[NSMutableDictionary alloc] init];
  NSMutableDictionary *notificationIOS = [[NSMutableDictionary alloc] init];

  // message.data
  for (id key in userInfo) {
    // message.messageId
    if ([key isEqualToString:@"gcm.message_id"] || [key isEqualToString:@"google.message_id"] ||
        [key isEqualToString:@"message_id"]) {
      message[@"messageId"] = userInfo[key];
      continue;
    }

    // message.messageType
    if ([key isEqualToString:@"message_type"]) {
      message[@"messageType"] = userInfo[key];
      continue;
    }

    // message.collapseKey
    if ([key isEqualToString:@"collapse_key"]) {
      message[@"collapseKey"] = userInfo[key];
      continue;
    }

    // message.from
    if ([key isEqualToString:@"from"]) {
      message[@"from"] = userInfo[key];
      continue;
    }

    // message.sentTime
    if ([key isEqualToString:@"google.c.a.ts"]) {
      message[@"sentTime"] = userInfo[key];
      continue;
    }

    // message.to
    if ([key isEqualToString:@"to"] || [key isEqualToString:@"google.to"]) {
      message[@"to"] = userInfo[key];
      continue;
    }

    // build data dict from remaining keys but skip keys that shouldn't be included in data
    if ([key isEqualToString:@"aps"] || [key hasPrefix:@"gcm."] || [key hasPrefix:@"google."]) {
      continue;
    }

    // message.apple.imageUrl
    if ([key isEqualToString:@"fcm_options"]) {
      if (userInfo[key] != nil && userInfo[key][@"image"] != nil) {
        notificationIOS[@"imageUrl"] = userInfo[key][@"image"];
      }
      continue;
    }

    data[key] = userInfo[key];
  }
  message[@"data"] = data;

  if (userInfo[@"aps"] != nil) {
    NSDictionary *apsDict = userInfo[@"aps"];
    // message.category
    if (apsDict[@"category"] != nil) {
      message[@"category"] = apsDict[@"category"];
    }

    // message.threadId
    if (apsDict[@"thread-id"] != nil) {
      message[@"threadId"] = apsDict[@"thread-id"];
    }

    // message.contentAvailable
    if (apsDict[@"content-available"] != nil) {
      message[@"contentAvailable"] = @([apsDict[@"content-available"] boolValue]);
    }

    // message.mutableContent
    if (apsDict[@"mutable-content"] != nil && [apsDict[@"mutable-content"] intValue] == 1) {
      message[@"mutableContent"] = @([apsDict[@"mutable-content"] boolValue]);
    }

    // message.notification.*
    if (apsDict[@"alert"] != nil) {
      // can be a string or dictionary
      if ([apsDict[@"alert"] isKindOfClass:[NSString class]]) {
        // message.notification.title
        notification[@"title"] = apsDict[@"alert"];
      } else if ([apsDict[@"alert"] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *apsAlertDict = apsDict[@"alert"];

        // message.notification.title
        if (apsAlertDict[@"title"] != nil) {
          notification[@"title"] = apsAlertDict[@"title"];
        }

        // message.notification.titleLocKey
        if (apsAlertDict[@"title-loc-key"] != nil) {
          notification[@"titleLocKey"] = apsAlertDict[@"title-loc-key"];
        }

        // message.notification.titleLocArgs
        if (apsAlertDict[@"title-loc-args"] != nil) {
          notification[@"titleLocArgs"] = apsAlertDict[@"title-loc-args"];
        }

        // message.notification.body
        if (apsAlertDict[@"body"] != nil) {
          notification[@"body"] = apsAlertDict[@"body"];
        }

        // message.notification.bodyLocKey
        if (apsAlertDict[@"loc-key"] != nil) {
          notification[@"bodyLocKey"] = apsAlertDict[@"loc-key"];
        }

        // message.notification.bodyLocArgs
        if (apsAlertDict[@"loc-args"] != nil) {
          notification[@"bodyLocArgs"] = apsAlertDict[@"loc-args"];
        }

        // Apple only
        // message.notification.apple.subtitle
        if (apsAlertDict[@"subtitle"] != nil) {
          notificationIOS[@"subtitle"] = apsAlertDict[@"subtitle"];
        }

        // Apple only
        // message.notification.apple.subtitleLocKey
        if (apsAlertDict[@"subtitle-loc-key"] != nil) {
          notificationIOS[@"subtitleLocKey"] = apsAlertDict[@"subtitle-loc-key"];
        }

        // Apple only
        // message.notification.apple.subtitleLocArgs
        if (apsAlertDict[@"subtitle-loc-args"] != nil) {
          notificationIOS[@"subtitleLocArgs"] = apsAlertDict[@"subtitle-loc-args"];
        }

        // Apple only
        // message.notification.apple.badge
        if (apsAlertDict[@"badge"] != nil) {
          notificationIOS[@"badge"] = apsAlertDict[@"badge"];
        }
      }

      notification[@"apple"] = notificationIOS;
      message[@"notification"] = notification;
    }

    // message.notification.apple.sound
    if (apsDict[@"sound"] != nil) {
      if ([apsDict[@"sound"] isKindOfClass:[NSString class]]) {
        // message.notification.apple.sound
        notification[@"sound"] = @{
          @"name" : apsDict[@"sound"],
          @"critical" : @NO,
          @"volume" : @1,
        };
      } else if ([apsDict[@"sound"] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *apsSoundDict = apsDict[@"sound"];
        NSMutableDictionary *notificationIOSSound = [[NSMutableDictionary alloc] init];

        // message.notification.apple.sound.name String
        if (apsSoundDict[@"name"] != nil) {
          notificationIOSSound[@"name"] = apsSoundDict[@"name"];
        }

        // message.notification.apple.sound.critical Boolean
        if (apsSoundDict[@"critical"] != nil) {
          notificationIOSSound[@"critical"] = @([apsSoundDict[@"critical"] boolValue]);
        }

        // message.notification.apple.sound.volume Number
        if (apsSoundDict[@"volume"] != nil) {
          notificationIOSSound[@"volume"] = apsSoundDict[@"volume"];
        }

        // message.notification.apple.sound
        notificationIOS[@"sound"] = notificationIOSSound;
      }

      notification[@"apple"] = notificationIOS;
      message[@"notification"] = notification;
    }
  }

  return message;
}

- (nullable NSDictionary *)copyInitialNotification {
  @synchronized(self) {
    if (_initialNotification != nil) {
      NSDictionary *initialNotificationCopy = [_initialNotification copy];
      _initialNotification = nil;
      return initialNotificationCopy;
    }
  }

  return nil;
}

- (NSDictionary *)NSDictionaryForNSError:(NSError *)error {
  NSString *code = @"unknown";
  NSString *message = @"An unknown error has occurred.";

  if (error == nil) {
    return @{
      kMessagingArgumentCode : code,
      kMessagingArgumentMessage : message,
    };
  }

  // code - codes from taken from NSError+FIRMessaging.h
  if (error.code == 4) {
    code = @"unavailable";
  } else if (error.code == 7) {
    code = @"invalid-request";
  } else if (error.code == 8) {
    code = @"invalid-argument";
  } else if (error.code == 501) {
    code = @"missing-device-id";
  } else if (error.code == 1001) {
    code = @"unavailable";
  } else if (error.code == 1003) {
    code = @"invalid-argument";
  } else if (error.code == 1004) {
    code = @"save-failed";
  } else if (error.code == 1005) {
    code = @"invalid-argument";
  } else if (error.code == 2001) {
    code = @"already-connected";
  } else if (error.code == 3005) {
    code = @"pubsub-operation-cancelled";
  }

  // message
  if ([error userInfo][NSLocalizedDescriptionKey] != nil) {
    message = [error userInfo][NSLocalizedDescriptionKey];
  }

  return @{
    kMessagingArgumentCode : code,
    kMessagingArgumentMessage : message,
  };
}
        
- (void) handleReplyActionWithResponse:(UNTextInputNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler API_AVAILABLE(ios(10.0)){
    /*NSLog(@"482 handleReplyActionWithResponse()");*/
    ChatworkService *chatService = [[ChatworkService alloc] init];

    NSDictionary *userInfo = response.notification.request.content.userInfo;

    NSString *messageText = response.userText;
    NSString *channelId = userInfo[@"tag"];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *createAt = [dateFormatter stringFromDate:[NSDate date]];
    /*NSLog(@"createAt es: %@", createAt);*/

    [chatService saveMessageWithTextMessage:messageText andChannelId:channelId andCreateAt:createAt andCompletionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponseMain = (NSHTTPURLResponse *)response;
        /*NSLog(@"492 chatService:saveMessage() httpResponse.statusCode es:  %ld", httpResponse.statusCode);*/

        if(httpResponseMain.statusCode == 401) {
            NSLog(@"*****************************************************************");
            NSLog(@"502 ChatworkServiceMain onFailure() %ld", (long)httpResponseMain.statusCode);
            NSLog(@"*****************************************************************");

            TokenService *tokenService = [[TokenService alloc] init];
            NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
            NSString *refreshToken = [prefs stringForKey:@"flutter.refreshToken"];
            NSLog(@"refreshToken es: %@", refreshToken);

            [tokenService refreshTokenWithRefreshedToken:refreshToken andCompletionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSHTTPURLResponse *httpResponseToken = (NSHTTPURLResponse *)response;

                if(httpResponseToken.statusCode == 414) {
                    NSLog(@"*****************************************************************");
                    NSLog(@"TokenService onFailure() %ld", (long)httpResponseToken.statusCode);
                    NSLog(@"*****************************************************************");

                    NSLog(@"Tu sesión ha sido cerrada. Por favor abre la app amazingwork.");
                }

                if(httpResponseToken.statusCode == 200) {
                    NSLog(@"*****************************************************************");
                    NSLog(@"TokenService onSuccess() %ld", (long)httpResponseToken.statusCode);
                    NSLog(@"*****************************************************************");

                    NSError *parseErrorTk = nil;
                    NSDictionary *responseDictionaryTk = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseErrorTk];

                    NSString *newRefreshToken = [responseDictionaryTk objectForKey:@"refresh_token"];
                    NSString *newAccessToken = [responseDictionaryTk objectForKey:@"token"];

                    [[NSUserDefaults standardUserDefaults] setObject:newAccessToken forKey:@"flutter.accessToken"];
                    [[NSUserDefaults standardUserDefaults] synchronize];

                    [chatService saveMessageWithTextMessage:messageText andChannelId:channelId andCreateAt:createAt andCompletionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                        /*NSLog(@"492 chatService:saveMessage() httpResponse.statusCode es:  %ld", httpResponse.statusCode);*/

                        if(httpResponse.statusCode == 401) {
                            NSLog(@"*****************************************************************");
                            NSLog(@"ChatworkServiceNested onFailure() %ld", (long)httpResponse.statusCode);
                            NSLog(@"*****************************************************************");

                            NSLog(@"Tu sesión ha sido cerrada. Por favor abre la app amazingwork.");
                            return;
                        }

                        if(httpResponse.statusCode == 201) {
                            NSLog(@"*****************************************************************");
                            NSLog(@"ChatworkServiceNested onSuccess() %ld", (long)httpResponse.statusCode);
                            NSLog(@"*****************************************************************");

                            NSError *parseError = nil;
                            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                            /*NSLog(@"responseDictionary es: %@",responseDictionary);*/

                            NSMutableDictionary *datosPedido = [responseDictionary objectForKey:@"pedido"];
                            /*NSLog(@"datosPedido es: %@",datosPedido);*/

                            NSMutableDictionary *datosUsuario = [responseDictionary objectForKey:@"datosusuario"];
                            /*NSLog(@"datosUsuario es: %@",datosUsuario);*/

                            NSString *userId = userInfo[@"from_id"];
                            NSString *logoProveedor = userInfo[@"fcm_options"][@"image"];

                            NSString *estadoPedido = userInfo[@"estado_pedido"];
                            NSString *valorPedido = userInfo[@"valor_pedido"];

                            //try {
                            NSString *title = [responseDictionary objectForKey:@"empresa"]; //response.getString("empresa") + " - Chatwork";
                            NSString *tipoUser = [responseDictionary objectForKey:@"tipoUsuario"];
                            NSString *idUser = [[responseDictionary objectForKey:@"idUser"] stringValue];
                            NSString *fromId = [NSString stringWithFormat:@"%@-%@", tipoUser, idUser];
                            NSString *userImage = [responseDictionary objectForKey:@"fotoLogo"];
                            NSInteger messageId = [[responseDictionary objectForKey:@"messageId"] intValue];

                            NSString *dataChat = userInfo[@"data_chat"];
                            NSData *chatData = [dataChat dataUsingEncoding:NSUTF8StringEncoding];
                            NSError *errorParse = nil;

                            //NSDictionary pedido = new JSONObject(bundle.getString("data_chat"));
                            //pedido.put("nombre", response.getString("nombre"));
                            //pedido.put("celular", response.getString("celular"));

                            NSMutableDictionary *chatPedido = [NSJSONSerialization JSONObjectWithData:chatData options:0 error:&errorParse];
                            NSMutableDictionary *pedido = [[NSMutableDictionary alloc] initWithDictionary:chatPedido copyItems:TRUE];

                            [pedido setValue:[responseDictionary objectForKey:@"nombre"] forKey:@"nombre"];
                            [pedido setValue:[responseDictionary objectForKey:@"celular"] forKey:@"celular"];

                            //NSString *currentPage = pedido.getString("currentPage").equals("misCompras") ? "misVentas" : "misCompras";
                            //NSString *idProv = pedido.getString("idProv");
                            //NSString *color = Objects.requireNonNull(idUser).equals(idProv) ? COLOR_CONSUMIDOR : COLOR_PROVEEDOR;

                            NSString *currentPage = [[pedido objectForKey:@"currentPage"] isEqualToString:@"misCompras"] ? @"misVentas" : @"misCompras";
                            NSString *idProv = [pedido objectForKey:@"idProv"];

                            NSString *color = [idUser isEqualToString:idProv] ? COLOR_CONSUMIDOR : COLOR_PROVEEDOR;

                            /*NSLog(@"userId es: %@", userId);*/
                            /*NSLog(@"fromId es: %@", fromId);*/

                            [self sendNotificationWithTitle:title body:messageText userId:userId channelId:channelId color:color userImage:userImage action:@"envio_chat" fromId:fromId codPedido:[NSString stringWithFormat:@"Pedido %@", [datosPedido objectForKey:@"idPediProveedor"]] description:[datosPedido objectForKey:@"descriPedido"] estadoPedido:estadoPedido valorPedido:valorPedido dataChat:[self getDataChatWithChannelId:channelId messageText:messageText topicSenderId:idUser senderId:fromId tipoUser:tipoUser pedido:datosPedido logoProveedor:logoProveedor foto:userImage currentPage:currentPage usuario:datosUsuario messageId:&messageId createAt:createAt] completionHandler:completionHandler];

                        } else {
                            NSLog(@"*****************************************************************");
                            NSLog(@"ChatworkServiceNested onFailure() %ld", (long)httpResponse.statusCode);
                            NSLog(@"*****************************************************************");
                            NSLog(@"Error es: %@", error);
                        }
                    }];

                } else {
                    NSLog(@"*****************************************************************");
                    NSLog(@"TokenService onFailure() %ld", (long)httpResponseToken.statusCode);
                    NSLog(@"*****************************************************************");
                    NSLog(@"Error es: %@", error);
                }
            }];
        }

        if(httpResponseMain.statusCode == 201) {
            NSLog(@"*****************************************************************");
            NSLog(@"624 ChatworkServiceMain onSuccess() %ld", (long)httpResponseMain.statusCode);
            NSLog(@"*****************************************************************");

            NSError *parseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            /*NSLog(@"responseDictionary es: %@",responseDictionary);*/

            NSMutableDictionary *datosPedido = [responseDictionary objectForKey:@"pedido"];
            /*NSLog(@"datosPedido es: %@",datosPedido);*/

            NSMutableDictionary *datosUsuario = [responseDictionary objectForKey:@"datosusuario"];
            /*NSLog(@"datosUsuario es: %@",datosUsuario);*/

            NSString *userId = userInfo[@"from_id"];
            NSString *logoProveedor = userInfo[@"fcm_options"][@"image"];

            NSString *estadoPedido = userInfo[@"estado_pedido"];
            NSString *valorPedido = userInfo[@"valor_pedido"];

            //try {
            NSString *title = [responseDictionary objectForKey:@"empresa"]; //response.getString("empresa") + " - Chatwork";
            NSString *tipoUser = [responseDictionary objectForKey:@"tipoUsuario"];
            NSString *idUser = [[responseDictionary objectForKey:@"idUser"] stringValue];
            NSString *fromId = [NSString stringWithFormat:@"%@-%@", tipoUser, idUser];
            NSString *userImage = [responseDictionary objectForKey:@"fotoLogo"];
            NSInteger messageId = [[responseDictionary objectForKey:@"messageId"] intValue];

            NSString *dataChat = userInfo[@"data_chat"];
            NSData *chatData = [dataChat dataUsingEncoding:NSUTF8StringEncoding];
            NSError *errorParse = nil;

            //NSDictionary pedido = new JSONObject(bundle.getString("data_chat"));
            //pedido.put("nombre", response.getString("nombre"));
            //pedido.put("celular", response.getString("celular"));

            NSMutableDictionary *chatPedido = [NSJSONSerialization JSONObjectWithData:chatData options:0 error:&errorParse];
            NSMutableDictionary *pedido = [[NSMutableDictionary alloc] initWithDictionary:chatPedido copyItems:TRUE];

            [pedido setValue:[responseDictionary objectForKey:@"nombre"] forKey:@"nombre"];
            [pedido setValue:[responseDictionary objectForKey:@"celular"] forKey:@"celular"];

            //NSString *currentPage = pedido.getString("currentPage").equals("misCompras") ? "misVentas" : "misCompras";
            //NSString *idProv = pedido.getString("idProv");
            //NSString *color = Objects.requireNonNull(idUser).equals(idProv) ? COLOR_CONSUMIDOR : COLOR_PROVEEDOR;

            NSString *currentPage = [[pedido objectForKey:@"currentPage"] isEqualToString:@"misCompras"] ? @"misVentas" : @"misCompras";
            NSString *idProv = [pedido objectForKey:@"idProv"];

            NSString *color = [idUser isEqualToString:idProv] ? COLOR_CONSUMIDOR : COLOR_PROVEEDOR;

            /*NSLog(@"userId es: %@", userId);*/
            /*NSLog(@"fromId es: %@", fromId);*/

            [self sendNotificationWithTitle:title body:messageText userId:userId channelId:channelId color:color userImage:userImage action:@"envio_chat" fromId:fromId codPedido:[NSString stringWithFormat:@"Pedido %@", [datosPedido objectForKey:@"idPediProveedor"]] description:[datosPedido objectForKey:@"descriPedido"] estadoPedido:estadoPedido valorPedido:valorPedido dataChat:[self getDataChatWithChannelId:channelId messageText:messageText topicSenderId:idUser senderId:fromId tipoUser:tipoUser pedido:datosPedido logoProveedor:logoProveedor foto:userImage currentPage:currentPage usuario:datosUsuario messageId:&messageId createAt:createAt] completionHandler:completionHandler];

        } else {
            NSLog(@"*****************************************************************");
            NSLog(@"681 ChatworkServiceMain onFailure() %ld", (long)httpResponseMain.statusCode);
            NSLog(@"*****************************************************************");
            NSLog(@"Error es: %@", error);
        }
    }];
}

- (void) sendNotificationWithTitle:(NSString *_Nonnull)title body:(NSString *_Nonnull)body userId:(NSString *_Nonnull)userId channelId:(NSString *_Nonnull)channelId color:(NSString *_Nonnull)color userImage:(NSString *_Nonnull)userImage action:(NSString *_Nonnull)action fromId:(NSString *_Nonnull)fromId codPedido:(NSString *_Nonnull)codPedido description:(NSString *_Nonnull)description estadoPedido:(NSString *_Nonnull)estadoPedido valorPedido:(NSString *_Nonnull)valorPedido dataChat:(NSDictionary *_Nonnull)dataChat completionHandler:(void (^)(void))completionHandler {
    MessagingService *msgService = [[MessagingService alloc] init];

    [msgService
     sendToTopicWithTitle:title
     body:body
     topic:userId
     tagId:channelId
     colorIcon:color
     imageName:userImage
     action:action
     fromId:fromId
     codPedido:codPedido
     description:description
     estadoPedido:estadoPedido
     valorPedido:valorPedido
     payload:dataChat
     andCompletionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        /*NSLog(@"Android httpResponse.statusCode es: %ld", httpResponse.statusCode);*/

        if(httpResponse.statusCode == 200) {
            NSError *parseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            NSLog(@"1366 Android The response is - %@",responseDictionary);
            completionHandler();

        } else {
            NSError *parseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            NSLog(@"593 Android responseDictionary es: %@", responseDictionary);
            NSLog(@"594 Android Error es: %@", error);
            completionHandler();
        }
    }];
}

- (NSDictionary *_Nonnull) getDataChatWithChannelId:(NSString *_Nonnull)channelId messageText:(NSString *_Nonnull)messageText topicSenderId:(NSString *_Nonnull)topicSenderId senderId:(NSString *_Nonnull)senderId tipoUser:(NSString *_Nonnull)tipoUser pedido:(NSDictionary *_Nonnull)pedido logoProveedor:(NSString *_Nonnull)logoProveedor foto:(NSString *_Nonnull)foto currentPage:(NSString *_Nonnull)currentPage usuario:(NSDictionary *_Nonnull)usuario messageId:(NSInteger *_Nonnull)messageId createAt:(NSString *_Nonnull)createAt {
    
//    NSLog(@"[pedido objectForKey:@\"tipoUser\"] es: %@", [pedido objectForKey:@"tipoUser"]);
    
    NSMutableDictionary *proveedorData = [pedido objectForKey:@"proveedor"];
    NSMutableDictionary *empresaData = [proveedorData objectForKey:@"empresa"];
//    NSLog(@"proveedorData es: %@", proveedorData);
//    NSLog(@"empresaData es: %@", empresaData);
    
    NSMutableDictionary *clienteData = [pedido objectForKey:@"cliente"];
//    NSLog(@"clienteData es: %@", clienteData);
//    NSLog(@"clienteData == NULL es: %d", clienteData == [ NSNull null ]);
//    NSLog(@"clienteData != NULL es: %d", clienteData != [ NSNull null ]);
    
    NSMutableDictionary *clienteProveedorData = [pedido objectForKey:@"clienteProveedor"];
//    NSLog(@"clienteProveedorData es: %@", clienteProveedorData);
//    NSLog(@"clienteProveedorData == NULL es: %d", clienteProveedorData == [ NSNull null ]);
//    NSLog(@"clienteProveedorData != NULL es: %d", clienteProveedorData != [ NSNull null ]);
    
    NSMutableDictionary *empresaClienteProvData = clienteProveedorData != [ NSNull null ] ? [clienteProveedorData objectForKey:@"empresa"] : [ NSNull null ];
//    NSLog(@"empresaClienteProvData es: %@", empresaClienteProvData);
    
//    NSLog(@"[[pedido objectForKey:@\"tipoUser\"] isEqualToString:@\"personal/\"] es: %d", [[pedido objectForKey:@"tipoUser"] isEqualToString:@"personal"]);
//    NSLog(@"![[pedido objectForKey:@\"tipoUser\"] isEqualToString:@\"personal\"] es: %d", ![[pedido objectForKey:@"tipoUser"] isEqualToString:@"personal"]);
       
    NSDictionary * dataChat = @{
        @"id": [pedido objectForKey:@"id"],
        @"idPediProveedor": [pedido objectForKey:@"idPediProveedor"],
        @"descriPedido": [pedido objectForKey:@"descriPedido"],
        @"estadoPedido": [pedido objectForKey:@"estadoPedido"],
        @"subtotalPedido": [pedido objectForKey:@"subtotalPedido"],
        @"requerimientoFile": [pedido objectForKey:@"requerimiento"],
        @"estadoPedidoCliente": [pedido objectForKey:@"estadoPedidoCliente"],
        @"createAt": [pedido objectForKey:@"createAt"],
        @"updatedAt": [pedido objectForKey:@"updatedAt"],
        @"propuestaFile": [pedido objectForKey:@"propuesta"],
        @"tipoUser": [pedido objectForKey:@"tipoUser"],
        @"topicSenderId": [usuario objectForKey:@"id"],
        @"isOferta": [pedido objectForKey:@"isOferta"],
        @"imagenPublicacion": [pedido objectForKey:@"imagenPublicacion"],
        @"actions": [pedido objectForKey:@"actions"],
        
        @"proveedor": @{
            @"id": [proveedorData objectForKey:@"id"],
            @"nombreProveedor": [proveedorData objectForKey:@"nombreProveedor"],
            @"apellidoProveedor": [proveedorData objectForKey:@"apellidoProveedor"],
            @"celularProveedor": [proveedorData objectForKey:@"celular"],
            @"actividadEconomica": [proveedorData objectForKey:@"actividadEconomica"],
            @"ubicacion": [proveedorData objectForKey:@"ubicacion"],
            @"pais": [proveedorData objectForKey:@"pais"],
            @"ciudad": [proveedorData objectForKey:@"ciudad"],
            @"urlmap": [proveedorData objectForKey:@"urlmap"],
            @"empresa": @{
                @"id": [empresaData objectForKey:@"id"],
                @"nombre": [empresaData objectForKey:@"nombre"],
                @"logo": [empresaData objectForKey:@"api_logo"],
                @"tipoCuenta": [empresaData objectForKey:@"tipoCuenta"],
            }
        },

        @"cliente": [[pedido objectForKey:@"tipoUser"] isEqualToString:@"personal"] ? @{
            @"id": [clienteData objectForKey:@"id"],
            @"nombre": [clienteData objectForKey:@"nombre"],
            @"apellido": [clienteData objectForKey:@"apellido"],
            @"celular": [clienteData objectForKey:@"celular"],
            @"api_logo": [clienteData objectForKey:@"api_logo"],
            @"urlmap": [clienteData objectForKey:@"urlmap"],
        } : [NSNull null],

        @"clienteProveedor": ![[pedido objectForKey:@"tipoUser"] isEqualToString:@"personal"] ? @{
            @"id": [clienteProveedorData objectForKey:@"id"],
            @"nombreProveedor": [clienteProveedorData objectForKey:@"nombreProveedor"],
            @"apellidoProveedor": [clienteProveedorData objectForKey:@"apellidoProveedor"],
            @"celularProveedor": [clienteProveedorData objectForKey:@"celularProveedor"],
            @"ubicacion": [clienteProveedorData objectForKey:@"ubicacion"],
            @"actividadEconomica": [clienteProveedorData objectForKey:@"actividadEconomica"],
            @"pais": [clienteProveedorData objectForKey:@"pais"],
            @"ciudad": [clienteProveedorData objectForKey:@"ciudad"],
            @"urlmap": [clienteProveedorData objectForKey:@"urlmap"],
            @"empresa": @{
                @"id": [empresaClienteProvData objectForKey:@"id"],
                @"nombre": [empresaClienteProvData objectForKey:@"nombre"],
                @"logo": [empresaClienteProvData objectForKey:@"api_logo"],
                @"tipoCuenta": [empresaClienteProvData objectForKey:@"tipoCuenta"],
            }
        } : [NSNull null],

        @"messageId": [NSNumber numberWithInteger:*messageId],
        @"channel": [pedido objectForKey:@"id"],
        @"senderId": senderId,
        @"message": messageText,
        @"type": @"text",
        @"createAtChat": createAt,
        /*@"width":@"0",
        @"height": @"0",*/

        //@"celular": [proveedorData objectForKey:@"celular"],
        //@"representante": [proveedorData objectForKey:@"nombre_proveedor"],
        @"idProv": [proveedorData objectForKey:@"id"],
        @"logoProveedor": [empresaData objectForKey:@"api_logo"],
        @"foto": foto,
        /*@"tipoChat": @true,
        @"navbarClnts": @true,
        @"logoProv": logoProveedor,
        @"celulartoChat": [usuario objectForKey:@"celular"],
        @"nombretoChat": [usuario objectForKey:@"nombre_consumidor"],*/

        @"image": foto,
        @"description": messageText,
        @"currentPage": currentPage,
        @"typeCliente": tipoUser,
        @"notificationColor": @"#4caf50", // [pedido objectForKey:@"color"]

        /*@"tipoUserItem": @"js-clnts-pers",
        @"nombreUserItem": @"SCOTH WILIAMS",
        @"chatMsgNegoTipoUser": @"proveedor",
        @"chatMsgNegoEvento": @"ProveedorConsumidor",
        @"chatMsgNegoFrom": @"#js-add-chat",
        @"usuario": @"proveedor",
        @"toastrPos": @"toast-top-right",*/
    };

    return dataChat;
}

@end
