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
    ("分類圖示 / 淡底", 3, (0x8B5A71, 0xF3E6EB), (0xD7A3BB, 0x3A2530)),
    ("「編輯」格的字 / 淡底", 4.5, (0x8B5A71, 0xF3E6EB), (0xD7A3BB, 0x3A2530)),
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
