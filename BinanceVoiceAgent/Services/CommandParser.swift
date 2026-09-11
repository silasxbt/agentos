import Foundation

/// 规则解析器:把中英文自然语言交易指令转换成结构化 TradeOrder
/// 示例:"做多比特币 十倍 全仓 200U 止盈7万 止损6万" / "short ETH 20x isolated 500 usdt tp 5% sl 3%"
struct CommandParser {

    struct ParseResult {
        var order: TradeOrder
        var confidence: Double          // 0~1
        var notes: [String]             // agent 解释,展示给用户
    }

    private static let cnAssets: [String: String] = [
        "比特币": "BTC", "大饼": "BTC", "以太坊": "ETH", "以太": "ETH", "姨太": "ETH",
        "索拉纳": "SOL", "狗狗币": "DOGE", "狗币": "DOGE", "币安币": "BNB", "瑞波": "XRP",
        "艾达": "ADA", "波卡": "DOT", "莱特币": "LTC", "佩佩": "PEPE", "阿童木": "ATOM", "链接": "LINK",
    ]
    private static let knownAssets: Set<String> = [
        "BTC","ETH","SOL","BNB","XRP","DOGE","ADA","DOT","LTC","PEPE","ATOM","LINK","AVAX","SUI","APT","ARB","OP","TON","TRX","WIF","SHIB","MATIC","NEAR","INJ","FIL","UNI","AAVE","ORDI"
    ]
    private static let cnDigits: [Character: Int] = ["零":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]

    func parse(_ raw: String) -> ParseResult {
        let text = Self.normalize(raw)
        var notes: [String] = []
        var score = 0.0

        // 方向
        var side: TradeSide = .long
        if text.range(of: #"做空|开空|卖出|空单|short|sell"#, options: .regularExpression) != nil { side = .short; score += 0.15 }
        else if text.range(of: #"做多|开多|买入|多单|long|buy"#, options: .regularExpression) != nil { side = .long; score += 0.15 }
        else { notes.append("未听到方向,默认做多") }

        // 币种
        var symbol = ""
        for (cn, code) in Self.cnAssets where text.contains(cn) { symbol = code; break }
        if symbol.isEmpty {
            let re = try! NSRegularExpression(pattern: #"\b([A-Z]{2,6})(?:USDT|/USDT|USD)?\b"#)
            let upper = text.uppercased()
            for m in re.matches(in: upper, range: NSRange(upper.startIndex..., in: upper)) {
                let tok = String(upper[Range(m.range(at: 1), in: upper)!])
                if Self.knownAssets.contains(tok) { symbol = tok; break }
            }
        }
        if symbol.isEmpty { notes.append("未识别币种") } else { score += 0.3 }

        // 杠杆
        var leverage = 0
        if let n = Self.firstNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:倍|x|×|杠杆)"#) ??
                   Self.firstNumber(in: text, pattern: #"杠杆\s*(\d+)"#) ??
                   Self.firstNumber(in: text, pattern: #"(\d+)\s*(?:leverage|lev)"#) {
            leverage = Int(n)
            score += 0.2
        } else { notes.append("未听到杠杆,默认 5x"); leverage = 5 }
        leverage = min(max(leverage, 1), 125)

        // 全仓/逐仓
        var margin: MarginMode = .cross
        if text.range(of: #"逐仓|isolated"#, options: .regularExpression) != nil { margin = .isolated; score += 0.1 }
        else if text.range(of: #"全仓|cross"#, options: .regularExpression) != nil { margin = .cross; score += 0.1 }
        else { notes.append("未听到仓位模式,默认全仓") }

        // 金额
        var amount = 0.0
        if let a = Self.firstNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:usdt|u|美元|刀|美金)(?![a-z])"#) { amount = a; score += 0.2 }
        else if let a = Self.firstNumber(in: text, pattern: #"(?:金额|仓位|下|买|投)\s*(\d+(?:\.\d+)?)"#) { amount = a; score += 0.1 }
        else { notes.append("未听到金额,默认 100 USDT"); amount = 100 }

        // 止盈 / 止损
        let tp = Self.target(in: text, keys: #"止盈|tp|take\s*profit"#)
        let sl = Self.target(in: text, keys: #"止损|sl|stop\s*loss"#)
        if tp != nil { score += 0.025 }
        if sl != nil { score += 0.025 }

        let order = TradeOrder(symbol: symbol.isEmpty ? "" : symbol + "USDT", side: side, leverage: leverage,
                               marginMode: margin, notionalUSDT: amount, takeProfit: tp, stopLoss: sl, rawTranscript: raw)
        return ParseResult(order: order, confidence: min(score, 1), notes: notes)
    }

    // MARK: - helpers

    /// 中文数字 / 万 / 千 → 阿拉伯数字;全角→半角;小写英文
    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
            .replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "％", with: "%").replacingOccurrences(of: "％", with: "%")
        // 十倍/二十倍/一百倍
        let cnNum = try! NSRegularExpression(pattern: #"([零一二两三四五六七八九十百]+)(?=\s*(?:倍|万|千|u|美元|刀|个点|%))"#)
        for m in cnNum.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            let r = Range(m.range(at: 1), in: t)!
            if let v = cnToInt(String(t[r])) { t.replaceSubrange(r, with: String(v)) }
        }
        // 6.5万 → 65000, 3千 → 3000
        let wan = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*万"#)
        for m in wan.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            let r = Range(m.range, in: t)!; let n = Double(t[Range(m.range(at: 1), in: t)!])!
            t.replaceSubrange(r, with: String(Int(n * 10_000)))
        }
        let qian = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*千"#)
        for m in qian.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            let r = Range(m.range, in: t)!; let n = Double(t[Range(m.range(at: 1), in: t)!])!
            t.replaceSubrange(r, with: String(Int(n * 1_000)))
        }
        t = t.replacingOccurrences(of: "个点", with: "%")
        return t
    }

    static func cnToInt(_ s: String) -> Int? {
        var total = 0, cur = 0
        for c in s {
            if let d = cnDigits[c] { cur = d }
            else if c == "十" { total += (cur == 0 ? 1 : cur) * 10; cur = 0 }
            else if c == "百" { total += (cur == 0 ? 1 : cur) * 100; cur = 0 }
            else { return nil }
        }
        return total + cur
    }

    static func firstNumber(in text: String, pattern: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }

    static func target(in text: String, keys: String) -> PriceTarget? {
        let pattern = "(?:\(keys))\\s*(?:价|价格|到|at|价位)?\\s*(\\d+(?:\\.\\d+)?)\\s*(%)?"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text), let v = Double(text[r]) else { return nil }
        let isPct = m.range(at: 2).location != NSNotFound
        return isPct ? .percent(v) : .price(v)
    }
}
