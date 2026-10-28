# Paisa.exe

**Your money, decoded.** Paisa.exe is an Android-first pocket-money and spending companion for VIT students. This repository is the private source-code bookmark for the current Flutter version of the app.

## What it does

- Tracks your pocket balance, income, expenses, and monthly budgets.
- Lets you record recurring pocket money and see when the next payment is due.
- Includes a wallet illustration that changes through six states as your balance changes relative to your pocket-money amount.
- Offers transaction history, monthly insights, and CSV export/import.
- Includes campus food menus for testing; the current menu data is sample data.
- Supports color themes, hidden amounts, and reduced motion.

## Current scope

- **Platform:** Android, built with Flutter and Dart.
- **Storage:** Financial data is stored locally on the device. There is no account, cloud sync, or website connected to this version yet.
- **Website:** Not included in this repository version.
- **App ID:** `com.paisaexe.app`
- **Version:** `0.1.0+1`

GitHub stores this app's source code. It does **not** back up the transactions or settings on your phone. Local app data usually survives app updates, but uninstalling the app or clearing its storage can erase it. Export a CSV from the app if you need a separate transaction backup.

## Run it again

### What you need

- Flutter SDK with Dart **3.13.5 or newer**.
- Android Studio with the Android SDK installed, or another Android device configured for Flutter.
- An Android phone with USB debugging enabled, or an Android emulator.

### Open the project

1. Clone this private repository with GitHub Desktop, or open its existing local folder.
2. Open the `Paisa-exe` folder in Android Studio. If prompted, let Android Studio install or configure the Flutter and Dart plugins.
3. In Android Studio's terminal, run:

   ```sh
   flutter pub get
   ```

4. Connect your phone, accept its USB debugging prompt, or start an emulator.
5. Check that Flutter sees the device, then launch the app:

   ```sh
   flutter devices
   flutter run
   ```

You can also select the phone in Android Studio's device menu and press **Run ▶**.

## Build an Android APK

From the project folder, run:

```sh
flutter pub get
flutter build apk --release
```

The APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

To install that APK on a connected phone with Flutter, run:

```sh
flutter install
```

The current Android release build uses debug signing for local testing. It is not configured as a Play Store release.

## Project map

```text
lib/
  main.dart          Flutter screens, widgets, animations, and app entry point
  paisa_store.dart   Local data, transactions, settings, and allowance logic
assets/images/       App logo and wallet artwork
android/             Android app and Gradle configuration
test/                Flutter tests
```

## Keep this repository private

This repository is intended as a personal project backup. Before making it public, review the files and Git history for personal data, credentials, signing keys, or other private material. Never commit real transaction exports or Android signing secrets.

---

Made by **Likhit**.
