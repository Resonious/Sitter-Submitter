import Testing
@testable import SitterSubmitter

struct YenFormatStyleTests {
    @Test(arguments: [
        (0, "¥0"), (980, "¥980"), (7800, "¥7,800"), (104_650, "¥104,650"), (1_234_567, "¥1,234,567"),
    ])
    func groupsThousandsTheJapaneseWay(amount: Int, expected: String) {
        #expect(amount.formatted(.yen) == expected)
    }
}
