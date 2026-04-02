//
//  AppDelegate.swift
//  Resonance
//
//  Created by Claude on 2/11/26.
//

import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Stores notification userInfo from a cold-start tap, so NotificationManager can pick it up later
    static var pendingNotificationUserInfo: [AnyHashable: Any]?
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Configure Firebase FIRST — must happen before any Auth or Messaging calls
        FirebaseConfig.configure()
        
        // Force Auth singleton initialization so tokenManager is ready for APNs token
        _ = Auth.auth()
        
        // Request notification authorization
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, _ in
                print("Notification permission granted: \(granted)")
            }
        )
        
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // Handle successful APNs registration
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("APNs device token registered: \(token.prefix(20))...")
        
        // Manually pass token to Firebase Messaging (swizzling is disabled)
        Messaging.messaging().apnsToken = deviceToken
        
        // Manually pass token to Firebase Auth for phone auth silent push
        // Use .unknown so Firebase auto-detects sandbox vs production
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }
    
    // Handle APNs registration failure
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
    }
    
    // Forward remote notifications to Firebase Auth (phone auth silent push)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        // Not a Firebase Auth notification — handle normally
        completionHandler(.newData)
    }
    
    // Forward URL callbacks to Firebase Auth (phone auth reCAPTCHA redirect)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if Auth.auth().canHandle(url) {
            return true
        }
        return false
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("Received notification while in foreground: \(userInfo)")
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("User tapped notification (AppDelegate): \(userInfo)")
        
        // Store for NotificationManager to pick up on cold start
        AppDelegate.pendingNotificationUserInfo = userInfo as? [AnyHashable: Any] ?? [:]
        
        completionHandler()
    }
}
