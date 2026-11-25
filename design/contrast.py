"""算這個 app 自己加的顏色和套上去的組合，對比夠不夠。改了 Theme.swift 的色值就重跑：python design/contrast.py
設計系統本身的組合由 domy-design 的 npm test 管。一般字要 4.5，圖示和圖形要 3。"""


def luminance(color):
    parts = [((color >> shift) & 255) / 255 for shift in (16, 8, 0)]
    parts = [p / 12.92 if p <= 0.04045 else ((p + 0.055) / 1.055) ** 2.4 for p in parts]
    return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


def contrast(a, b):
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


PAIRS = [
    ("收入數字 / 卡片", 4.5, (0x24785C, 0xFFFFFF), (0x4CC29B, 0x1C1C1E)),
    ("收入數字 / 底色", 4.5, (0x24785C, 0xF5F5F7), (0x4CC29B, 0x000000)),
    ("停用按鈕的字 / 停用底", 4.5, (0x66666D, 0xE5E5EA), (0xA1A1A8, 0x2C2C2E)),
    ("平常範圍 / 卡片", 3, (0x8E8E93, 0xFFFFFF), (0x7C7C82, 0x1C1C1E)),
    ("圖示 / 吃喝色塊", 3, (0xFFFFFF, 0xA65F45), (0x1D1D1F, 0xDB9C84)),
    ("圖示 / 交通色塊", 3, (0xFFFFFF, 0x4B6C8F), (0x1D1D1F, 0x8FB0D4)),
    ("圖示 / 住家色塊", 3, (0xFFFFFF, 0x7A6A3A), (0x1D1D1F, 0xC2B078)),
    ("圖示 / 購物玩樂色塊", 3, (0xFFFFFF, 0x6F5F8F), (0x1D1D1F, 0xA99BD0)),
    ("圖示 / 其餘色塊", 3, (0xFFFFFF, 0x66666D), (0x1D1D1F, 0xA1A1A8)),
    ("圖示 / 收入色塊", 3, (0xFFFFFF, 0x24785C), (0x1D1D1F, 0x4CC29B)),
    ("吃喝色塊 / 卡片", 3, (0xA65F45, 0xFFFFFF), (0xDB9C84, 0x1C1C1E)),
    ("交通色塊 / 卡片", 3, (0x4B6C8F, 0xFFFFFF), (0x8FB0D4, 0x1C1C1E)),
    ("住家色塊 / 卡片", 3, (0x7A6A3A, 0xFFFFFF), (0xC2B078, 0x1C1C1E)),
    ("購物玩樂色塊 / 卡片", 3, (0x6F5F8F, 0xFFFFFF), (0xA99BD0, 0x1C1C1E)),
    ("其餘色塊 / 卡片", 3, (0x66666D, 0xFFFFFF), (0xA1A1A8, 0x1C1C1E)),
    ("還能花 / 卡片", 4.5, (0x74485D, 0xFFFFFF), (0xE7C0D1, 0x1C1C1E)),
    ("「編輯」的字 / 底色", 4.5, (0x8B5A71, 0xF5F5F7), (0xD7A3BB, 0x000000)),
    ("主色字 / 卡片", 4.5, (0x8B5A71, 0xFFFFFF), (0xD7A3BB, 0x1C1C1E)),
    ("主色上的字", 4.5, (0xFFFFFF, 0x8B5A71), (0x2A1520, 0xD7A3BB)),
    ("次要字 / 底色", 4.5, (0x66666D, 0xF5F5F7), (0xA1A1A8, 0x000000)),
    ("錯誤字 / 底色", 4.5, (0xC4372C, 0xF5F5F7), (0xFF6B5E, 0x000000)),
]

bad = 0
for name, need, light, dark in PAIRS:
    for mode, pair in (("淺", light), ("深", dark)):
        value = contrast(*pair)
        bad += value < need
        print(f"{'過' if value >= need else '不過'} {name} {mode} {value:.2f}（要 {need}）")
raise SystemExit(bad)
