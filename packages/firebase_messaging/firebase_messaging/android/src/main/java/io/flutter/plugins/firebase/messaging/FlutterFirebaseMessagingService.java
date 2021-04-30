// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.firebase.messaging;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.Rect;
import android.graphics.RectF;
import android.media.RingtoneManager;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;
import androidx.core.app.RemoteInput;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.util.Map;

import static android.R.drawable.ic_delete;

public class FlutterFirebaseMessagingService extends FirebaseMessagingService {
  private static final String TAG = "FLTFireMsgService";
  public static final String NOTIFICATION_REPLY = "NotificationReply";
  public static final int NOTIFICATION_ID = 200;
  public static final int REQUEST_CODE_APPROVE = 101;
  public static final String KEY_INTENT_APPROVE = "keyintentaccept";

  public static final String NOTIFICATION_CHANNEL_ID = "channel_id";
  public static final String CHANNEL_NAME = "Notificaciones de mensage";
  private static Class<?> classNameReceiver;
  private static Class<?> classNameMainActivity;

  private int numMessages = 0;

  public static String REPLY_ACTION = "io.flutter.plugins.firebasemessaging.REPLY_ACTION";

  private int mNotificationId;
  private int mMessageId;

  private static final String KEY_MESSAGE_ID = "key_message_id";
  private static final String KEY_NOTIFY_ID = "key_notify_id";

  @Override
  public void onNewToken(@NonNull String token) {
    Intent onMessageIntent = new Intent(FlutterFirebaseMessagingUtils.ACTION_TOKEN);
    onMessageIntent.putExtra(FlutterFirebaseMessagingUtils.EXTRA_TOKEN, token);
    LocalBroadcastManager.getInstance(getApplicationContext()).sendBroadcast(onMessageIntent);
  }

  @RequiresApi(api = Build.VERSION_CODES.KITKAT)
  @Override
  public void onMessageReceived(@NonNull RemoteMessage remoteMessage) {
    // Added for commenting purposes;
    // We don't handle the message here as we already handle it in the receiver and don't want to duplicate.
    /*Log.d(TAG, "onMessageReceived() executed!");*/

    if (FlutterFirebaseMessagingUtils.isApplicationForeground(this)) { return; }

    // Show native remote notification
    sendNotification(remoteMessage, this);
  }

  // TODO(jh0n4): Improve implementation
  @RequiresApi(api = Build.VERSION_CODES.KITKAT)
  private void sendNotification(RemoteMessage remoteMessage, Context context) {
    // Check if message contains a data payload.
    if (remoteMessage.getData().size() == 0 || remoteMessage.toIntent().getExtras() == null) {
      return;
    }

    initializedClassNameVal();

    final Map<String, String> data = remoteMessage.getData();
    final String actionNotify = data.get("action");

    if(actionNotify.equals("descartar_pedido")
      || actionNotify.equals("descartar_pedido_cliente")
      || actionNotify.equals("entregar_pedido")
      || actionNotify.equals("recibir_pedido")
      || actionNotify.equals("completar_pedido")
      || actionNotify.equals("finalizar_pedido")
      || actionNotify.equals("update_data")) {
      return;
    }

    JSONObject dataChat = null;
    String subtotalPed = "0.00";

    try {
      dataChat = new JSONObject(data.get("data_chat"));

      subtotalPed = dataChat.getString("subtotalPedido");
    } catch (JSONException e) {
      e.printStackTrace();
    }

    int colorNotify = Color.GRAY;

    try {
      colorNotify = Integer.decode(data.get("color"));
    } catch (Exception e) {
      Log.e(TAG, "Could not parse " + e);
    }

    int NotifyId = 0;

    try {
      NotifyId = Integer.parseInt(data.get("tag"));
    } catch(NumberFormatException nfe) {
      Log.e(TAG, "Could not parse " + nfe);
    }

    Intent replyIntent = new Intent(context, classNameReceiver);
    replyIntent.putExtra("channelId", data.get("tag"));
    replyIntent.putExtra(KEY_INTENT_APPROVE, REQUEST_CODE_APPROVE);
    replyIntent.putExtra("data", remoteMessage.toIntent().getExtras());

    PendingIntent approvePendingIntent = PendingIntent.getBroadcast(
      context,
      NotifyId,
      replyIntent,
      PendingIntent.FLAG_UPDATE_CURRENT
    );

    // 1. Build label
    String replyLabel = "Enviar mensaje";
    RemoteInput remoteInput = new RemoteInput.Builder(NOTIFICATION_REPLY)
      .setLabel(replyLabel)
      .build();

    // 2. Build action
    NotificationCompat.Action replyAction = new NotificationCompat.Action.Builder(
      ic_delete, "Responder", approvePendingIntent)
      .addRemoteInput(remoteInput)
//            .setAllowGeneratedReplies(true)
      .build();

    // 3. Build notification
    Intent intent = new Intent(context, classNameMainActivity);
    intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
      .setPackage(getPackageName())
      .setAction(Intent.ACTION_MAIN)
      .addCategory(Intent.CATEGORY_LAUNCHER)
      .putExtras(remoteMessage.toIntent().getExtras());

    PendingIntent pi = PendingIntent.getActivity(context, NotifyId, intent, PendingIntent.FLAG_UPDATE_CURRENT); // FLAG_ONE_SHOT

//    Bitmap icon = BitmapFactory.decodeResource(getResources(), R.mipmap.ic_launcher);
//    String channelId = getString(R.string.default_notification_channel_id);

    int icLauncherActivity = getResources().getIdentifier("ic_notification", "mipmap", getPackageName());
    NotificationCompat.Builder notificationBuilder =
      new NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
        .setSmallIcon(icLauncherActivity, 10)   //.setSmallIcon(R.mipmap.ic_launcher, 10)
        .setContentTitle(data.get("title"))           //notification.getTitle()
        .setContentText(data.get("body"))             //notification.getBody()  0x0288d1-Azul 0x4caf50-Verde
        .setAutoCancel(true)
        .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
        .setContentIntent(pi)
//                    .setContentInfo("setContentInfo")
//                    .setLargeIcon(getLargeIcon(data))
//                    .setTicker("setTicker")
        .setColor(colorNotify)
        .setLights(Color.GRAY, 1000, 300)
        .setColorized(true)
//                    .setDefaults(Notification.DEFAULT_VIBRATE)
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setVibrate(new long[] { 1000, 1000, 1000, 1000, 1000 })
        .setCategory(NotificationCompat.CATEGORY_MESSAGE)
        .setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
//                    .setContentInfo("setContentInfo")
        .setNumber(++numMessages)
        //.setStyle(new NotificationCompat.DecoratedCustomViewStyle());
        //.setCustomContentView(collapsedView)
        //.setCustomBigContentView(expandedView)
        .setStyle(new NotificationCompat.BigPictureStyle()
          .setBigContentTitle(data.get("title"))
          .setSummaryText(data.get("description"))
          .bigPicture(getLargeIcon(data))
          .bigLargeIcon(null));

    NotificationManager notificationManager =
      (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);

    // Since android Oreo notification channel is needed.
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
      CharSequence description = "Channel Description"; //CharSequence description = getString(R.string.default_notification_channel_id);
      String name = "YOUR_CHANNEL_NAME";      // CharSequence channelName = "Some Channel";
      int importance = NotificationManager.IMPORTANCE_HIGH;

      NotificationChannel channel = new NotificationChannel(NOTIFICATION_CHANNEL_ID, CHANNEL_NAME, importance);
      channel.setDescription("YOUR_NOTIFICATION_CHANNEL_DISCRIPTION");

      channel.enableLights(true);
      channel.setLightColor(Color.RED);
      channel.enableVibration(true);
      channel.setVibrationPattern(new long[]{100, 200, 300, 400, 500, 400, 300, 200, 400});

      notificationManager.createNotificationChannel(channel);
    }

    if (android.os.Build.VERSION.SDK_INT > Build.VERSION_CODES.M) {
      notificationBuilder.addAction(replyAction);
    }

    /*if( data.get("action").equals("valor_enviado") ) {
      Intent approveReceive = new Intent(context, classNameReceiver);
      approveReceive.setAction("com.amazingwork.amazingwork.PEDIDO");

      approveReceive.putExtra("channelId", data.get("tag"));
      approveReceive.putExtra(KEY_INTENT_APPROVE, REQUEST_CODE_APPROVE);
      approveReceive.putExtra("data", remoteMessage.toIntent().getExtras());

      PendingIntent pendingIntentYes = PendingIntent.getBroadcast(this, 12345, approveReceive, PendingIntent.FLAG_UPDATE_CURRENT);
      notificationBuilder.addAction(ic_menu_send, "Aprobar", pendingIntentYes);
    }*/

    notificationManager.notify(NotifyId, notificationBuilder.build());
  }

  private void initializedClassNameVal() {
    /*FlutterFirebaseMessagingService.setPluginRegistryRegistrar(registrar.context(), , registrar.activeContext().getPackageName(), imageId, viewCollapseNotify, timeStamp);*/
    if( classNameReceiver == null) {
      try {
        classNameReceiver = Class.forName("com.amazingwork.amazingwork.NotificationReceiver");
      } catch (ClassNotFoundException e) {
        e.printStackTrace();
      }
    }

    if( classNameMainActivity == null) {
      try {
        classNameMainActivity = Class.forName("com.amazingwork.amazingwork.MainActivity");
      } catch (ClassNotFoundException e) {
        e.printStackTrace();
      }
    }
  }

  @RequiresApi(api = Build.VERSION_CODES.KITKAT)
  private Bitmap getLargeIcon(Map<String, String> data) {
    String imageNotif = data.get("image");
    Bitmap bmpIcon = null;
    try {
      InputStream in = new URL(data.get("image")).openStream();    //InputStream in = new URL(notification.getImageUrl().toString()).openStream();
      bmpIcon = BitmapFactory.decodeStream(in);

    } catch (IOException e) {
      e.printStackTrace();
    }

//    return getCircleBitmap(bmpIcon);
    return bmpIcon;
  }

  private Bitmap getCircleBitmap(Bitmap bitmap) {
    final Bitmap output = Bitmap.createBitmap(bitmap.getWidth(),
      bitmap.getHeight(), Bitmap.Config.ARGB_8888);
    final Canvas canvas = new Canvas(output);

    final int color = Color.RED;
    final Paint paint = new Paint();
    final Rect rect = new Rect(0, 0, bitmap.getWidth(), bitmap.getHeight());
    final RectF rectF = new RectF(rect);

    paint.setAntiAlias(true);
    canvas.drawARGB(0, 0, 0, 0);
    paint.setColor(color);
    canvas.drawOval(rectF, paint);

    paint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.SRC_IN));
    canvas.drawBitmap(bitmap, rect, rect, paint);

    bitmap.recycle();

    return output;
  }

  private PendingIntent getReplyPendingIntent(Context context, Class<?> broadCastReceiver) {
    Intent intent;
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
      intent = getReplyMessageIntent(context, mNotificationId, mMessageId, broadCastReceiver);

      return PendingIntent.getBroadcast(
        context,
        REQUEST_CODE_APPROVE, // 100
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT
      );

    } else {
      // start your activity
      intent = getReplyMessageIntent(context, mNotificationId, mMessageId, broadCastReceiver);
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      return PendingIntent.getActivity(
        context,
        REQUEST_CODE_APPROVE, // 100
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT
      );
    }
  }

  private Intent getReplyMessageIntent(Context context, int notificationId, int messageId, Class<?> broadCastReceiver) {
    Intent intent = new Intent(context, broadCastReceiver);
    intent.setAction(REPLY_ACTION);
    intent.putExtra(KEY_NOTIFY_ID, notificationId);
    intent.putExtra(KEY_MESSAGE_ID, messageId);
    return intent;
  }
}
