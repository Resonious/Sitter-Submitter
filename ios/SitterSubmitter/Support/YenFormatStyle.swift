import Foundation

/// Amounts of yen as the app shows them, like ¥104,650: grouped the Japanese way, whatever the device's region.
struct YenFormatStyle: FormatStyle {
    func format(_ amount: Int) -> String {
        "¥" + amount.formatted(.number.locale(Locale(identifier: "ja_JP")))
    }
}

extension FormatStyle where Self == YenFormatStyle {
    static var yen: YenFormatStyle { YenFormatStyle() }
}
