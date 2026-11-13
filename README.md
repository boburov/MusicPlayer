# Music Widget

macOS ish stoli uchun musiqa widgeti. Spotify yoki Apple Music'da hozir chalinayotgan qo'shiqni ko'rsatadi va boshqaradi:

- albom rasmi (chap tepada);
- qo'shiq nomi va ijrochi;
- ⏮ ⏯ ⏭ tugmalari;
- qo'shiq so'zlari: hozirgi qator karaoke kabi so'zma-so'z yumshoq yorug'lik bilan to'lib boradi, musiqa qismida ♪ belgilari to'ladi, keyingi qatorga silliq o'tadi; keyingi 3 qator xira.

Ikki o'lchamda ishlaydi: **Large** (kvadrat) va **Extra Large Portrait** (tik, macOS 27+).

## Talablar

| Nima | Izoh |
|---|---|
| macOS 15 yoki yangisi | Tik o'lcham faqat macOS 27+ da |
| Xcode | App Store'dan, bir marta ochib litsenziyani qabul qiling |
| Xcode'da Apple ID | Xcode → Settings → Accounts → `+` → Apple ID |
| Homebrew | [brew.sh](https://brew.sh). `install.sh` u orqali `xcodegen` o'rnatadi |
| Spotify yoki Apple Music | Ikkalasi bo'lsa, qaysi biri chalayotgan bo'lsa, o'shani ko'rsatadi |

Xcode'da **Apple Development** sertifikati bo'lishi kerak. Bo'lmasa: Xcode → Settings → Accounts → akkauntingiz → **Manage Certificates…** → `+` → **Apple Development**.

## O'rnatish

```bash
git clone https://github.com/boburov/MusicPlayer.git
cd MusicPlayer
./install.sh
```

Skript nimalarni qiladi:

1. Jamoa ID'ingizni Apple Development sertifikatingizdan o'qiydi.
2. Shu jamoa uchun loyihani yaratadi va Release qilib yig'adi.
3. `/Applications/MusicWidget.app` ga o'rnatadi va ishga tushiradi.

Jamoa ID'sini qo'lda berish (bir nechta akkaunt bo'lsa):

```bash
DEVELOPMENT_TEAM=ABCDE12345 ./install.sh
```

Jamoa ID'si Xcode → Settings → Accounts'da yoki [developer.apple.com/account](https://developer.apple.com/account) → Membership'da yozilgan.

## Widgetni ish stoliga qo'yish

1. Ish stolida o'ng tugma → **Edit Widgets…**
2. Qidiruvga **MusicWidget** deb yozing.
3. **Large** yoki **Extra Large Portrait** o'lchamini tanlab, ish stoliga torting va **Done** bosing.

Birinchi qo'shiqda macOS *"Music Widget wants to control Spotify"* deb so'raydi: **OK** bosing. Bu ruxsatsiz widget qo'shiqni ko'ra olmaydi.

### Jonli karta

macOS widgetni bir necha soniyada bir marta qayta chizadi. Bundan tashqari, fondagi ilova widgetni kuniga cheklangan marta yangilay oladi, limit tugagach widget qotib qoladi. Shuning uchun ilova widgetning jonli nusxasini o'z oynasida chizadi va uni aynan widget ustiga qo'yadi. Rasm, nom, tugmalar va so'zlar Spotify bilan bir vaqtda yangilanadi.

1. Ilova birinchi ochilganda ish stoli o'rtasida karta paydo bo'ladi.
2. Uni sichqoncha bilan widget ustiga torting. Yaqin kelganda o'zi joyiga yopishadi.
3. Yopishgan kartaning tugmalari oddiy tugmadek ishlaydi.

So'zlar kech yoki erta chiqsa: kursorni karta ustiga olib boring va aylantiring. Tepaga aylantirsangiz so'zlar oldinroq, pastga aylantirsangiz kechroq chiqadi (har qadam 0.25 s). Sozlama eslab qolinadi.

Karta boshqa oynalar ostida turadi va joyini eslab qoladi. Widgetni boshqa joyga ko'chirsangiz, karta bo'shab qoladi: uni yana widget ustiga torting. Ilova o'chiq bo'lsa, ostidagi oddiy widget ko'rinadi.

## Qanday ishlaydi

```
Spotify / Music ──AppleScript──▶ MusicWidget.app (fonda, ko'rinmas)
                                   │  qo'shiq, rasm, so'zlarni yozadi
                                   ▼
                          umumiy papka (App Group)
                                   │
                                   ▼
                         Widget (ish stolida chiziladi)
                                   │  tugma bosildi
                                   └──buyruq──▶ MusicWidget.app ──▶ pleyer
```

- Widget macOS sandbox ichida ishlaydi, boshqa ilovalarni o'zi boshqara olmaydi. Shuning uchun fonda `MusicWidget.app` ishlaydi: u qo'shiqni kuzatadi va tugma buyruqlarini pleyerga yetkazadi.
- Ilova kompyuter yoqilganda o'zi ishga tushadi (Login Items).
- Qo'shiq so'zlari bepul [LRCLIB](https://lrclib.net) xizmatidan olinadi. Spotify'ning o'z so'zlarini tashqaridan olib bo'lmaydi.

| Fayl | Vazifasi |
|---|---|
| `App/main.swift` | Fondagi ilova: pleyerni kuzatish, rasm va so'zlarni yuklash, tugma buyruqlari |
| `App/LiveCard.swift` | Widget ustidagi jonli karta oynasi |
| `Shared/PlayerCard.swift` | Karta ko'rinishi: rasm, nom, tugmalar, so'zlar (ilova va widget uchun umumiy) |
| `Widget/NowPlayingWidget.swift` | Widget ko'rinishi va tugmalar |
| `Shared/NowPlaying.swift` | Ilova va widget orasidagi umumiy ma'lumot |
| `project.yml` | XcodeGen loyiha tavsifi (`.xcodeproj` shundan yaratiladi) |
| `install.sh` | Yig'ish va o'rnatish |

## Muammolar

**Widget galereyada yo'q.** Ilovani bir marta oching: `open /Applications/MusicWidget.app`. Keyin widget xizmatini qayta ishga tushiring:

```bash
killall chronod
```

**Kod o'zgargandan keyin ham eski ko'rinish chiqyapti.** macOS widgetni versiya raqami bo'yicha keshlaydi. `project.yml` da `CURRENT_PROJECT_VERSION` ni oshiring, `./install.sh` ni qayta ishga tushiring va widgetni ish stolidan olib, qaytadan qo'shing.

**Qo'shiq ko'rinmayapti.** Pleyerni boshqarish ruxsatini rad etgan bo'lsangiz, uni qayta yoqing: System Settings → Privacy & Security → Automation → Music Widget → Spotify / Music.

**So'zlar chiqmayapti.** Qo'shiq LRCLIB'da vaqtlari bilan bo'lmasligi mumkin (ayniqsa kam tanilgan qo'shiqlar). Internet ham kerak.

**So'zlar orqada qolyapti yoki widget qotib qolgan.** Jonli karta widget ustiga yopishmagan. Uni widget ustiga torting (yuqoridagi "Jonli karta" bo'limi).


**Bundle ID band degan xato.** Bundle ID butun Apple bo'yicha yagona bo'lishi kerak. Boshqasini bering:

```bash
BUNDLE_ID=com.ismingiz.musicwidget ./install.sh
```

## O'chirish

```bash
pkill -x MusicWidget
rm -rf /Applications/MusicWidget.app
```

Login Items'dan ham olib tashlang: System Settings → General → Login Items.

## Maxfiylik

- Qo'shiq nomi va ijrochi so'zlarni topish uchun `lrclib.net` ga yuboriladi.
- Spotify albom rasmi Spotify serveridan yuklanadi.
- Boshqa hech narsa yuborilmaydi.
