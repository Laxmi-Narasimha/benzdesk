# BenzMobiTraq Mobile App

A field-force tracking Flutter application with background location tracking, session management, expenses, and push notifications.

## Features

- **Background Location Tracking**: Reliable GPS tracking with battery optimization
- **Session Management**: Present/Work Done workflow with distance calculation
- **Expense Management**: Submit and track expense claims with receipts
- **Push Notifications**: Real-time alerts for stuck employees and expense updates
- **Offline Support**: SQLite queue for location points when offline

## Getting Started

### Prerequisites

- Flutter SDK (3.0+)
- Dart SDK
- Android Studio / Xcode
- Supabase account

### Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd benzmobitraq_mobile
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Configure Supabase:
   - Create a Supabase project
   - Run the schema SQL in `supabase/schema.sql`
   - Update `lib/core/constants/app_constants.dart` with your Supabase URL and anon key

4. Configure Firebase (for push notifications):
   - Create a Firebase project
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Place them in the respective platform directories

5. Run the app:
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── core/
│   ├── constants/      # App constants, themes
│   ├── di/             # Dependency injection
│   ├── router/         # Navigation routing
│   └── utils/          # Utility functions
├── data/
│   ├── datasources/    # Local & remote data sources
│   ├── models/         # Data models
│   └── repositories/   # Repository implementations
├── presentation/
│   ├── blocs/          # State management (BLoC)
│   ├── screens/        # UI screens
│   └── widgets/        # Reusable widgets
└── services/           # Background services
```

## Architecture

This app follows Clean Architecture principles with:
- **Presentation Layer**: BLoC for state management, widgets for UI
- **Domain Layer**: Business logic in repositories
- **Data Layer**: Supabase for remote, SQLite/SharedPreferences for local

## Key Technologies

- **Flutter**: Cross-platform mobile framework
- **flutter_bloc**: State management
- **Supabase**: Backend (auth, database, storage)
- **geolocator**: Location services
- **flutter_background_service**: Background tracking
- **sqflite**: Local SQLite database
- **firebase_messaging**: Push notifications

## Environment Variables

Update `lib/core/constants/app_constants.dart`:
```dart
static const String supabaseUrl = 'YOUR_SUPABASE_URL';
static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

## License

MIT License
