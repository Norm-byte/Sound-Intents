Harmony Admin (Flutter Web)

Quick start (very simple):

Requirements:
- Flutter SDK installed and on PATH
- Chrome browser for `flutter run -d chrome`

Run locally (PowerShell):

```powershell
cd "C:\Users\norms\OneDrive\Desktop\CommunityApps\harmony by intent\harmony-by-intent\src\admin"
flutter pub get
flutter run -d chrome
```

Build for web:

```powershell
flutter build web
```

Notes:
- This is a minimal scaffold (placeholder UI) to start the Admin Web app.
- No Firebase or Gemini credentials are configured. I can add stubs when you confirm credentials or we can keep them as placeholders.
- To share code on GitHub, run `git init` in this folder and push to your repository (you said you have GitHub on this computer).

Firebase setup (recommended next step)
-----------------------------------
This admin app is intended to publish events to Firestore so mobile clients can read and synchronize events worldwide.

1) Create a Firebase project in the Firebase console (https://console.firebase.google.com/).
2) Add a web app in the Firebase project and copy the config values.
3) Run the FlutterFire CLI to generate `firebase_options.dart` (recommended):

```powershell
dart pub global activate flutterfire_cli
cd "C:\Users\norms\OneDrive\Desktop\CommunityApps\harmony by intent\harmony-by-intent\src\admin"
flutterfire configure
```

This will create `lib/firebase_options.dart` with your web config. After that, the app will be able to initialize Firebase and the Firestore stub in `lib/services/firebase_service.dart` can be implemented to publish events.

If you prefer to paste the config manually, add your web config and call `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);` in `main.dart` — the scaffold already tries to initialize Firebase and will continue safely if no config is present.

Local persistence
-----------------
Events are saved locally in browser `localStorage` so you can prototype without Firebase. When you publish (checkbox in Event Creator) the app will call the Firebase stub; after you configure Firebase we will wire it to write to Firestore.

Next steps I can take for you:
- Implement full Firestore wiring and publish/read flows (requires Firebase config)
- Expand Event Creator with media upload (Firebase Storage)
- Add Scheduler UI that saves recurring events to Firestore

