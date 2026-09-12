import Foundation
import UserNotifications
import UIKit

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyFilled(_ f: FilledOrder) {
        let o = f.order
        let content = UNMutableNotificationContent()
        content.title = "✅ 合约订单已成交"
        content.subtitle = "\(o.baseAsset)USDT 永续 · \(o.side.short) \(o.leverage)x \(o.marginMode == .cross ? "全仓" : "逐仓")"
        var body = "开仓价 \(Fmt.price(f.entryPrice)) · 数量 \(String(format: "%.4f", f.quantity)) \(o.baseAsset) · 保证金 \(Fmt.usdt(o.notionalUSDT))"
        if let tp = o.takeProfit { body += "\n止盈 \(Fmt.price(tp.resolved(entry: f.entryPrice, side: o.side, isTakeProfit: true)))" }
        if let sl = o.stopLoss { body += "  止损 \(Fmt.price(sl.resolved(entry: f.entryPrice, side: o.side, isTakeProfit: false)))" }
        body += "\n订单号 \(f.orderId)"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "orders"
        content.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: f.orderId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func notifyFailed(_ o: TradeOrder, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "❌ 下单失败"
        content.body = "\(o.orderedSummary)\n\(reason)"
        content.sound = .defaultCritical
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // 前台也弹横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
