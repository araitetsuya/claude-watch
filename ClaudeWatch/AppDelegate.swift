// AppDelegate — アプリ起動時の初期化と通知デリゲート。
//
//   • applicationDidFinishLaunching : 通知許可を要求し、ポーリングを開始する
//   • willPresent                   : アプリが前面でも通知バナーを出す
//   • didReceive                    : 通知タップでそのプロジェクトを開く

import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestAuth()
        LoginItem.shared.refresh()
        SessionStore.shared.start()
    }

    // show banners even while the app is frontmost
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    // clicking the banner opens the project
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let cwd = response.notification.request.content.userInfo["cwd"] as? String ?? ""
        openInPhpStorm(cwd, fromNotification: true)
    }
}