# Paisa.exe Android learning path

## Learner preference

- Start from zero assumed programming or computer science knowledge.
- Teach the Android app first. Cover the website only when the learner asks.
- Explain what each file, command, setting, and error means in plain language.
- Work in small lessons with examples from this project, then give the learner a small task to try themselves.
- Explain how to reproduce work without the assistant, including how to inspect errors and recover from them.
- Be encouraging and direct; never make the learner feel bad for not knowing something.

## Project map

Paisa.exe is an Android app that hosts a shared HTML/CSS/JavaScript finance interface in an Android WebView. It is an Android app package, but its screens are currently built with web technologies rather than native Android views.

- `android/app/src/main/java/com/paisaexe/app/MainActivity.java`: starts the Android screen and loads the web app in a WebView.
- `android/app/src/main/AndroidManifest.xml`: declares Android permissions and the app's launch screen.
- `android/app/src/main/res/values/styles.xml`: Android theme and system bar colors.
- `android/app/src/main/assets/www/`: the web app files packaged inside Android.
- `android/app/build.gradle`: Android build settings such as app ID and minimum Android version.
- `android/build.gradle` and `android/settings.gradle`: Gradle plugin and project setup.
- `.idea/gradle.xml`: this laptop's Android Studio selection of its local Gradle 9.3.1 installation.
- `app.js`, `index.html`, `styles.css`: shared screen, behavior, and styling. The learner asked to defer website lessons until requested.

## Teaching sequence

1. How a phone app is made of source files, assets, Android configuration, and a build process.
2. Android Studio, Gradle, SDK, emulator/device, and what Sync, Build, and Run each do.
3. Follow one screen from `MainActivity.java` into the WebView and packaged assets.
4. Read the manifest and understand app identity, permissions, launch activity, and Android versions.
5. Make a tiny safe UI change, build it, install it, and observe the result.
6. Learn logs and debugging by intentionally diagnosing a harmless issue.
7. Learn project structure, version control, backups, and how to undo changes.
8. Learn release APK/AAB, signing, and publishing only when ready.

## Current state

- Android Studio successfully synced the project using its local Gradle 9.3.1 installation.
- A debug APK built successfully.
- The debug app was installed and launched on the connected Nothing A059P phone.
