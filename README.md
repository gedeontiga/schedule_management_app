# Schedule Management Application

A comprehensive Flutter application that allows organizations to create and manage schedules with role-based permissions, user participation, offline capabilities, and real-time synchronization.

![Schedule Management App](assets/schedulo_logo.png)

## Features

### Authentication & User Management

- User registration and login system
- Secure authentication using Supabase
- Biometric authentication (TouchID/Device password) for accessing schedules

### Schedule Creation & Management

- Create personal and organizational schedules
- Configure schedule properties:
  - Name and description
  - Available days selection
  - Schedule duration (1-5 days/weeks/months)
  - Participant management with custom roles
  - Notification system for inviting participants

### Schedule Interaction

- Interactive calendar interface for selecting free days
- Permutation requests between users
- In-app notification system for permutation approvals/rejections
- Real-time schedule updates

### Customization & Notifications

- Set up alarms/reminders (1hr, 2hrs, 24hrs before appointments)
- Custom role creation for each schedule
- Role-based permissions for schedule interactions

### Export & Offline Capabilities

- Export schedules as PDF (generated on-demand)
- Offline functionality with synchronization when connection is restored
- Data synchronization using stack-based modification tracking

## Technical Overview

### Architecture

- Frontend: Flutter (Cross-platform mobile development)
- Backend: Supabase (Backend as a Service)
- Authentication: Supabase Auth + Device biometrics
- Database: PostgreSQL (via Supabase)
- Real-time capabilities: Supabase Realtime

### Data Flow

1. User authenticates using Supabase authentication
2. Application fetches and displays schedules where the user is owner or participant
3. Changes are sent to Supabase in real-time when online
4. Offline changes are stored locally and synchronized when connection is restored

## Getting Started

### Prerequisites

- Flutter SDK (2.5.0 or higher)
- Dart SDK (2.14.0 or higher)
- A Supabase account and project
- Android Studio / VS Code with Flutter plugins

### Installation

1. Clone the repository

```bash
git clone https://github.com/gedeontiga/schedule_management_app.git
cd schedule_management_app
```

2. Install dependencies

```bash
flutter pub get
```

3. Configure Supabase

   - Create a `.env` file in the project root
   - Add your Supabase URL and anonymous key:

   ```
   SUPABASE_URL=your_supabase_url
   SUPABASE_ANON_KEY=your_supabase_anon_key
   ```

4. Run the application

```bash
flutter run
```

## Project Structure

```
lib/
├── core/
│   ├── constants/
│   │   └── app_colors.dart
│   ├── utils/
│   │   ├── validators.dart
│   │   └── supabase_manager.dart       # Supabase initialization and utilities
│   ├── widgets/
│   │   ├── connection_status_indicator.dart
│   │   ├── custom_text_field.dart
│   │   ├── gradient_button.dart
│   │   └── schedule_card.dart          # For displaying schedules in Home
│   └── services/
│       ├── auth_service.dart           # Authentication logic
│       ├── schedule_service.dart       # Schedule CRUD operations
│       ├── notification_service.dart   # In-app notifications for invitations/permutations
│       └── pdf_service.dart            # PDF generation
├── models/
│   ├── schedule.dart                   # Schedule model
│   ├── role.dart                       # Role model
│   ├── participant.dart                # Participant model
│   └── permutation_request.dart        # Permutation request model
├── screens/
│   ├── login_screen.dart
│   ├── registration_screen.dart
│   ├── home_screen.dart                # Displays schedules
│   ├── schedule_creation_screen.dart   # Create/edit schedules
│   ├── schedule_management_screen.dart # Manage free days
└── main.dart
```

## Database Schema

### Users Table

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### Schedules Table

```sql
CREATE TABLE schedules (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  owner_id UUID REFERENCES users(id) NOT NULL,
  available_days JSONB NOT NULL,
  duration TEXT NOT NULL,
  duration_type TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### Roles Table

```sql
CREATE TABLE roles (
  id UUID PRIMARY KEY,
  schedule_id UUID REFERENCES schedules(id) NOT NULL,
  name TEXT NOT NULL,
  permissions JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### Participants Table

```sql
CREATE TABLE participants (
  id UUID PRIMARY KEY,
  schedule_id UUID REFERENCES schedules(id) NOT NULL,
  user_id UUID REFERENCES users(id) NOT NULL,
  role_id UUID REFERENCES roles(id) NOT NULL,
  free_days JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(schedule_id, user_id)
);
```

### Notifications Table

```sql
CREATE TABLE notifications (
  id UUID PRIMARY KEY,
  sender_id UUID REFERENCES users(id) NOT NULL,
  recipient_id UUID REFERENCES users(id) NOT NULL,
  type TEXT NOT NULL,
  content JSONB NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [Flutter](https://flutter.dev)
- [Supabase](https://supabase.io)
- [PDF](https://pub.dev/packages/pdf)
- [Local Auth](https://pub.dev/packages/local_auth)
