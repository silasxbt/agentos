import SwiftUI

/// Binance App 深色主题设计 token(对齐 Binance 官方 App 2024–2025 视觉)
enum Theme {
    // 品牌
    static let yellow = Color(hex: 0xFCD535)     // 主按钮 / 强调
    static let brand  = Color(hex: 0xF0B90B)     // Logo / 图标黄
    static let onYellow = Color(hex: 0x202630)   // 黄底上的文字

    // 背景层级
    static let bg     = Color(hex: 0x181A20)     // 页面底色
    static let card   = Color(hex: 0x1E2329)     // 卡片 / 面板
    static let card2  = Color(hex: 0x2B3139)     // 输入框 / chip / 次级面板
    static let line   = Color(hex: 0x2B3139)     // 分隔线
    static let line2  = Color(hex: 0x333B47)     // 强分隔线 / 描边

    // 文字
    static let text   = Color(hex: 0xEAECEF)     // 主文
    static let text2  = Color(hex: 0xB7BDC6)     // 次文
    static let text3  = Color(hex: 0x848E9C)     // 三级 / 标签
    static let text4  = Color(hex: 0x5E6673)     // 禁用 / 占位

    // 行情语义
    static let green  = Color(hex: 0x2EBD85)     // 买入 / 做多 / 上涨
    static let red    = Color(hex: 0xF6465D)     // 卖出 / 做空 / 下跌
    static let greenBg = Color(hex: 0x2EBD85).opacity(0.12)
    static let redBg   = Color(hex: 0xF6465D).opacity(0.12)
    static let yellowBg = Color(hex: 0xFCD535).opacity(0.12)

    // 圆角(Binance App 以 4 / 8 为主)
    static let r4: CGFloat = 4
    static let r8: CGFloat = 8
    static let r12: CGFloat = 12

    // 字阶(BinancePlex 为私有字体,这里用系统字体 + 等宽数字复刻字阶与字重;Binance 偏 500/600,少用 700)
    static func f(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w).monospacedDigit() }
    static let title   = f(20, .semibold)   // 页面标题
    static let h2      = f(16, .semibold)   // 卡片标题 / 交易对
    static let body    = f(14, .regular)
    static let bodyM   = f(14, .medium)
    static let bodyS   = f(14, .semibold)
    static let caption = f(12, .regular)
    static let captionM = f(12, .medium)
    static let tiny    = f(10, .medium)
    static let num     = f(16, .medium)     // 数值
    static let numL    = f(24, .semibold)   // 大数值
    static let button  = f(16, .semibold)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - 通用组件

/// Binance 主按钮:黄底 #FCD535 深字,高 48,圆角 8
struct BinanceButton: ButtonStyle {
    var fill: Color = Theme.yellow
    var fg: Color = Theme.onYellow
    var height: CGFloat = 48
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button).foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: Theme.r8))
    }
}

/// 灰底次按钮
struct SecondaryButton: ButtonStyle {
    var height: CGFloat = 48
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(Theme.card2.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: Theme.r8))
    }
}

/// 灰底小标签(如 "全仓" "20x" "USDT 永续")
struct Chip: View {
    let text: String
    var fg: Color = Theme.text2
    var bg: Color = Theme.card2
    var body: some View {
        Text(text).font(Theme.captionM).foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(bg, in: RoundedRectangle(cornerRadius: Theme.r4))
    }
}

/// Binance 风格分段选择:灰底,选中项填充指定色
struct BinanceSegment<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var activeColor: (T) -> Color = { _ in Theme.card2 }
    var activeFg: (T) -> Color = { _ in Theme.text }
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                let on = item.0 == selection
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = item.0 } } label: {
                    Text(item.1).font(Theme.bodyS)
                        .foregroundStyle(on ? activeFg(item.0) : Theme.text3)
                        .frame(maxWidth: .infinity).frame(height: height - 4)
                        .background(on ? activeColor(item.0) : .clear, in: RoundedRectangle(cornerRadius: Theme.r4))
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r4 + 2))
        .overlay(RoundedRectangle(cornerRadius: Theme.r4 + 2).stroke(Theme.line2, lineWidth: 1))
    }
}

/// Binance 输入框:#2B3139 底,圆角 4,高 44,左标签右数值
struct BinanceField<Content: View>: View {
    let label: String
    var unit: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.body).foregroundStyle(Theme.text3)
            Spacer(minLength: 8)
            content.font(Theme.num).foregroundStyle(Theme.text)
            if let unit { Text(unit).font(Theme.body).foregroundStyle(Theme.text3) }
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: Theme.r4))
    }
}

/// 卡片容器
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.r8))
    }
}

/// 页面顶栏(Binance 二级页样式:左返回/文字,中标题 16/600,右操作)
struct NavBar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        ZStack {
            Text(title).font(Theme.h2).foregroundStyle(Theme.text)
            HStack { leading; Spacer(); trailing }
        }
        .font(Theme.body)
        .padding(.horizontal, 16).frame(height: 44)
    }
}

extension View {
    /// 用 SwiftUI 默认 Divider 复刻 Binance 1px #2B3139 分隔线
    func bnDivider(leading: CGFloat = 0) -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, leading) }
    }
}

/// App 图标同款品牌 Logo(App 与灵动岛共用)
struct BrandLogo: View {
    var size: CGFloat = 24
    var body: some View {
        Image("BrandLogo").resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
