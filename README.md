# Paisa.exe

**Your money, decoded.** — an offline-first pocket-money companion for VIT students, built in Flutter.

> Money talks. This one actually listens (and remembers what you spent it on).

Paisa.exe tracks pocket balance, income, expenses, monthly budgets, and recurring pocket money. It also has transaction history, monthly insights, CSV export/import, Price Memory for comparing prices you've explicitly logged, campus food menus for quick logging, and **"Your Money Has a Lore"** — a seven-chapter offline story that quietly reacts to your spending patterns and remembers every choice you make.

No accounts. No cloud. No ads. Your data lives on your phone and nowhere else.

## Download the app

**[⬇ Download Paisa.apk (latest release)](https://github.com/LikhitCodezz/Paisa-exe/releases/latest/download/Paisa.apk)**

### Install on your Android phone

1. Tap the link above on your phone (or send the APK to yourself via WhatsApp/Drive).
2. Open the downloaded `Paisa.apk`. If Android says "Install blocked", tap **Settings → Allow from this source** for your browser/file manager, then retry.
3. If you already have an older Paisa.exe installed, **uninstall it first** — Android refuses to overwrite an app signed with a different key.
4. Tap **Install**, then **Open**.

> The APK is signed with the debug keystore for now, so it's meant for sideloading among friends, not the Play Store. Updates replace the old version cleanly as long as the signing key stays the same.

## What's inside

- Tracks pocket balance, income, expenses, and monthly budgets
- Records recurring pocket money and shows when the next payment is due
- Wallet illustration that shifts through six states as your balance changes
- Transaction history, monthly insights, CSV export/import
- Price Memory — item history and place labels for prices you've logged
- Campus food menus for one-tap logging
- *Your Money Has a Lore* — a seven-chapter offline story with choices that stick
- Color themes, hidden amounts, reduced motion

## Run it yourself

### You'll need

- Flutter SDK with Dart **3.13.5+**
- Android Studio + Android SDK (or any Android device with USB debugging)
- An Android phone or emulator

### Steps

```sh
git clone https://github.com/LikhitCodezz/Paisa-exe.git
cd Paisa-exe
flutter pub get
flutter run
```

Or open the folder in Android Studio and hit **Run ▶**.

### Build a release APK

```sh
flutter pub get
flutter build apk --release
```

Output lands at `build/app/outputs/flutter-apk/app-release.apk`. Rename it to `Paisa.apk` if you're publishing it as a release asset.

## Project map

```text
lib/
  main.dart          screens, widgets, animations, app entry point
  paisa_store.dart   local data, transactions, settings, allowance logic
  lore.dart          story engine and the seven-chapter arc
  lore_page.dart     cinematic reader, archive, typewriter reveal
assets/images/       logo + wallet artwork
android/             Android + Gradle config
test/                Flutter tests
legacy/              the older web version (kept for reference)
```

## A few honest notes

- **Offline only.** Financial data is stored locally. No account, no cloud sync, no website wired up yet.
- **Hidden transactions** are encrypted with AES-GCM via Android Keystore. There's no PIN recovery — lose the device/key and they're gone. Treat the PIN as a privacy gate, not a security guarantee.
- **Local app data survives updates** but not uninstalls or "clear storage". Export a CSV if you want a real backup.
- App ID: `com.paisaexe.app` · Version: `1.0.0+1`

## Publishing a release (for the download link above)

The README's download link points at the latest GitHub Release asset named `Paisa.apk`. To make it live:

1. Build: `flutter build apk --release`
2. Rename `build/app/outputs/flutter-apk/app-release.apk` → `Paisa.apk`
3. GitHub → Releases → "Draft a new release" → tag `v1.0.0` → attach `Paisa.apk` → Publish

Until a release exists, the link will 404 — that's expected, not a bug.

---

Made by **Likhit**. Enjoy your paisa. 🪙