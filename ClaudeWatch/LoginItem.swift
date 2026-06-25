// LoginItem — ログイン時の自動起動（macOS 13+ の SMAppService）。
//
//   • SMAppService.mainApp はこのアプリ自身をログイン項目として登録する。
//     別ヘルパー bundle 不要。登録は「現在実行中の .app の場所」を記録するため、
//     /Applications に置いたものから起動して登録すること（DerivedData から登録すると
//     その一時パスを指してしまい、次回ログインで起動しない）。
//   • メニューのトグルから set(_:) を呼ぶ。実際の状態は status から読む。

import ServiceManagement
import Observation

@Observable
final class LoginItem {
    static let shared = LoginItem()

    /// 現在ログイン項目として有効か。
    private(set) var isEnabled: Bool = SMAppService.mainApp.status == .enabled

    /// system 設定など外部要因で変わり得るので、状態を読み直す。
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// 登録／解除。失敗しても実状態に同期させる。
    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem set(\(on)) failed: \(error.localizedDescription)")
        }
        refresh()
    }
}
