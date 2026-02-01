# BenzMobiTraq Project Handover

## Project Overview
**BenzMobiTraq** is a field-force tracking Flutter application for sales teams. It tracks employee work sessions with GPS, manages expenses, and sends push notifications.

**Workspace**: `e:\Benzmobitraq\benzmobitraq_mobile`

---

## Architecture

```
┌─────────────────┐
│  Presentation   │  ← BLoC pattern, Screens, Widgets
├─────────────────┤
│    Services     │  ← SessionManager, TrackingService, PermissionService
├─────────────────┤
│  Repositories   │  ← SessionRepository, ExpenseRepository, etc.
├─────────────────┤
│  Data Sources   │  ← SupabaseDataSource, LocalQueue, Preferences
├─────────────────┤
│    Supabase     │  ← PostgreSQL backend
└─────────────────┘
```

---

## What's Implemented ✅

### Screens (8)
| File | Purpose |
|------|---------|
| `home_screen.dart` | Main dashboard with session start/stop |
| `login_screen.dart` | Phone number authentication |
| `session_history_screen.dart` | Past sessions grouped by date |
| `expenses_screen.dart` | Expense claims with status filters |
| `add_expense_screen.dart` | Submit expense with receipt photo |
| `profile_screen.dart` | User info and navigation menu |
| `notifications_screen.dart` | In-app notifications |
| `splash_screen.dart` | App initialization |

### Services (7)
| File | Purpose |
|------|---------|
| `permission_service.dart` | Runtime permissions (location, battery, notifications) |
| `tracking_service.dart` | Background GPS with foreground service |
| `session_manager.dart` | Session lifecycle orchestration |
| `notification_service.dart` | FCM push notifications |
| `background_location_service.dart` | Low-level location service |
| `location_queue_service.dart` | Offline storage queue |
| `motion_detector_service.dart` | Accelerometer motion detection |

### BLoCs (4)
- `AuthBloc` - Authentication state
- `SessionBloc` - Session management
- `ExpenseBloc` - Expense claims
- `NotificationBloc` - Notifications

### Key Free Packages (no paid alternatives)
```yaml
geolocator: ^11.0.0              # GPS
flutter_background_service: ^5.0.5  # Foreground service
sensors_plus: ^4.0.2             # Motion detection
permission_handler: ^11.1.0      # Permissions
sqflite: ^2.3.0                  # Offline queue
supabase_flutter: ^2.3.0         # Backend
firebase_messaging: ^14.7.10     # Push notifications
```

---

## What's NOT Done ❌

### Critical (Must Do)
1. **Flutter SDK not in PATH** - User needs to install/configure
2. **Supabase credentials** - Update `lib/core/constants/app_constants.dart`:
   ```dart
   static const String supabaseUrl = 'YOUR_URL';
   static const String supabaseAnonKey = 'YOUR_KEY';
   ```
3. **Run database schema** - Execute `supabase/schema.sql` in Supabase SQL Editor
4. **`flutter pub get`** - Dependencies not yet installed

### Testing Required
- [ ] Real device testing (emulator GPS is unreliable)
- [ ] Background tracking on Samsung/Xiaomi (aggressive battery)
- [ ] Session resume after app kill
- [ ] Offline location queuing

### Optional Features
- [ ] Route map visualization (Google Maps)
- [ ] Admin dashboard (Next.js)
- [ ] Expense receipt OCR
- [ ] Stuck detection notifications

---

## File Structure

```
lib/
├── core/
│   ├── constants/app_constants.dart  ← NEEDS SUPABASE CREDS
│   ├── di/injection.dart            ← GetIt dependency injection
│   ├── router/app_router.dart       ← All routes defined
│   └── theme/app_theme.dart
├── data/
│   ├── datasources/
│   │   ├── local/
│   │   │   ├── location_queue_local.dart  ← SQLite queue
│   │   │   └── preferences_local.dart
│   │   └── remote/
│   │       └── supabase_client.dart
│   ├── models/
│   │   ├── session_model.dart
│   │   ├── expense_model.dart
│   │   ├── simple_expense_model.dart
│   │   └── notification_model.dart
│   └── repositories/
├── presentation/
│   ├── blocs/
│   │   ├── auth/
│   │   ├── session/
│   │   ├── expense/
│   │   └── notification/
│   ├── screens/                     ← ALL 8 SCREENS
│   └── widgets/
├── services/                        ← ALL 7 SERVICES
├── app.dart
└── main.dart
```

---

## Platform Config Done

### Android (`android/app/src/main/AndroidManifest.xml`)
- `ACCESS_FINE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`

### iOS (`ios/Runner/Info.plist`)
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- Background modes: `location`, `fetch`, `remote-notification`

---

## Key Design Decisions

1. **Free packages only** - No `flutter_background_geolocation` (paid)
2. **Anti-jitter filter** - GPS readings with accuracy > 20m ignored
3. **Anti-teleport filter** - Speed > 180 km/h rejected
4. **Foreground service** - Android requires notification for background GPS
5. **SQLite queue** - Locations stored offline, synced when connected
6. **State persistence** - Session survives app restart via SharedPreferences

---

## How to Continue

1. Install Flutter SDK and add to PATH
2. `cd e:\Benzmobitraq\benzmobitraq_mobile`
3. `flutter pub get`
4. Update Supabase credentials in `app_constants.dart`
5. `flutter run` on real device
6. Test background tracking
7. Fix any compilation errors (run `flutter analyze`)

---

## Known Potential Issues

| Issue | Likely Cause | Fix |
|-------|--------------|-----|
| Missing imports | Part files not resolving | Check `part of` directives |
| Type mismatches | `ManagerSessionState` vs `SessionState` | Already renamed in code |
| Background stops on Samsung | Doze mode | Prompt battery optimization disable |
| iOS background fails | Missing entitlements | Check Xcode capabilities |

---

## Contact Points in Code

- **Entry point**: `lib/main.dart`
- **DI setup**: `lib/core/di/injection.dart`
- **Routing**: `lib/core/router/app_router.dart`
- **Tracking core**: `lib/services/session_manager.dart`
- **Supabase schema**: `supabase/schema.sql`
