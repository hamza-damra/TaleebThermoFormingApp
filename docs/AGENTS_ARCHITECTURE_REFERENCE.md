# AGENTS ARCHITECTURE REFERENCE

> **Purpose**: This document describes the ACTUAL architecture, patterns, and conventions used in the Taleeb Warehouse Flutter project. Use this as a precise guide to replicate the same structure in new projects.

---

## 1. PROJECT OVERVIEW

**App Purpose**: Warehouse management mobile app for tracking pallets (مشتاح) movements between locations. Supports QR scanning, manual entry, driver monitoring, and movement logs.

**Architectural Philosophy**:
- **Clean Architecture** with layer-based separation (NOT feature-based)
- Three main layers: `data/`, `domain/`, `presentation/`
- Dependency flows inward: UI → Provider → Repository → DataSource
- No use cases layer (repositories called directly from providers)

---

## 2. FOLDER STRUCTURE

```
lib/
├── core/                    # App-wide utilities and configuration
│   ├── api_config.dart      # Base URL configuration
│   ├── constants.dart       # Enums, validation functions, app constants
│   ├── di.dart              # Dependency injection (ServiceLocator)
│   ├── error_mapping.dart   # Error code to Arabic message mapping
│   ├── theme.dart           # AppTheme with colors and styling
│   └── timezone_helper.dart # Date/time utilities
│
├── data/                    # Data layer (external)
│   ├── datasources/         # API clients
│   │   └── api_client.dart  # Dio client with interceptors
│   ├── models/              # Data models (DTOs with fromJson)
│   │   ├── user_model.dart
│   │   ├── movement_model.dart
│   │   └── ...
│   └── repositories/        # Repository implementations
│       ├── auth_repository_impl.dart
│       ├── movement_repository_impl.dart
│       └── ...
│
├── domain/                  # Domain layer (business)
│   ├── entities/            # Pure domain objects
│   │   ├── user.dart
│   │   ├── movement.dart
│   │   └── ...
│   └── repositories/        # Abstract repository contracts
│       ├── auth_repository.dart
│       ├── movement_repository.dart
│       └── ...
│
├── presentation/            # UI layer
│   ├── providers/           # State management (ChangeNotifier)
│   │   ├── auth_provider.dart
│   │   ├── scan_provider.dart
│   │   └── ...
│   ├── screens/             # Full-page widgets
│   │   ├── login_screen.dart
│   │   ├── home_screen.dart
│   │   └── ...
│   └── widgets/             # Reusable UI components (currently empty)
│
└── main.dart                # App entry point with MultiProvider setup
```

---

## 3. STATE MANAGEMENT

**Library Used**: `provider` package with `ChangeNotifier`

**Pattern**: Each feature has a dedicated Provider class that:
- Extends `ChangeNotifier`
- Receives repository via constructor injection
- Exposes state via getters
- Calls `notifyListeners()` after state changes

### Provider Structure Pattern

```dart
enum ScanFlowState { idle, validating, validated, resolving, resolved, saving, saved, error }

class ScanProvider extends ChangeNotifier {
  final MovementRepository _movementRepo;

  ScanProvider(this._movementRepo);

  // Private state
  ScanFlowState _state = ScanFlowState.idle;
  String? _errorMessage;
  Movement? _savedMovement;

  // Public getters
  ScanFlowState get state => _state;
  String? get errorMessage => _errorMessage;
  Movement? get savedMovement => _savedMovement;

  // Actions
  Future<void> resolve() async {
    _state = ScanFlowState.resolving;
    _errorMessage = null;
    notifyListeners();

    try {
      // call repository
      _state = ScanFlowState.resolved;
    } catch (e) {
      final apiErr = extractApiException(e);
      _errorMessage = apiErr.arabicMessage;
      _state = ScanFlowState.error;
    }
    notifyListeners();
  }

  void reset() {
    _state = ScanFlowState.idle;
    _errorMessage = null;
    notifyListeners();
  }
}
```

### UI Listening Pattern

```dart
// Watch for rebuilds
final auth = context.watch<AuthProvider>();

// Read without rebuild (for actions)
final success = await context.read<AuthProvider>().login(email, password);

// Consumer widget for scoped rebuilds
Consumer<AuthProvider>(
  builder: (context, auth, _) {
    return ElevatedButton(
      onPressed: auth.isLoading ? null : _handleLogin,
      child: auth.isLoading ? CircularProgressIndicator() : Text('Login'),
    );
  },
)
```

### Provider Registration (main.dart)

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => serviceLocator.createAuthProvider(),
    ),
    ChangeNotifierProvider<ScanProvider>(
      create: (_) => serviceLocator.createScanProvider(),
    ),
    // ... more providers
  ],
  child: MaterialApp(...),
)
```

---

## 4. DATA FLOW

```
UI (Screen)
    ↓ context.read<Provider>().action()
Provider (ChangeNotifier)
    ↓ _repository.method()
Repository Implementation (data/)
    ↓ _apiClient.dio.get/post()
ApiClient (Dio)
    ↓ HTTP Request
API Server
    ↓ JSON Response
ApiClient
    ↓ response.data['data']
Repository Implementation
    ↓ Model.fromJson(data)
Provider
    ↓ notifyListeners()
UI rebuilds
```

**Key Points**:
- **Mapping happens in Repository**: `Model.fromJson()` called in repository impl
- **Models extend Entities**: `class UserModel extends User`
- **Business logic lives in Provider**: validation, flow control, state management
- **No UseCases layer**: Providers call repositories directly

---

## 5. MODELS / ENTITIES / MAPPERS

### Entity (domain/entities/)
Pure Dart class with final fields and const constructor:

```dart
class User {
  final int id;
  final String name;
  final String email;
  final UserRole role;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });
}
```

### Model (data/models/)
Extends entity, adds `fromJson` factory:

```dart
class UserModel extends User {
  const UserModel({
    required super.id,
    required super.name,
    required super.email,
    required super.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      role: UserRole.fromApi(json['role'] as String),
    );
  }
}
```

**Pattern Rules**:
- Entity has no dependencies on external packages
- Model inherits from Entity using `super.` syntax
- Enums have `fromApi(String)` static method for parsing
- No separate mapper classes - mapping done in `fromJson`

---

## 6. NETWORK LAYER

**Library**: `dio` package

### ApiClient (data/datasources/api_client.dart)

```dart
class ApiClient {
  late final Dio dio;
  final FlutterSecureStorage _storage;

  ApiClient({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Parse error response into ApiException
        // Handle 401 unauthorized
        // Handle USER_DISABLED
      },
    ));
  }

  Future<void> saveToken(String token) async;
  Future<String?> getToken() async;
  Future<void> clearToken() async;
}
```

### Repository Usage

```dart
Future<User> getMe() async {
  final response = await _apiClient.dio.get('/me');
  final data = response.data['data'] as Map<String, dynamic>;
  return UserModel.fromJson(data);
}

Future<Movement> createMovement({...}) async {
  final response = await _apiClient.dio.post('/movements', data: body);
  final data = response.data['data'] as Map<String, dynamic>;
  return MovementModel.fromJson(data);
}
```

**API Response Format Expected**:
```json
{
  "data": { ... }
}
```

---

## 7. ERROR HANDLING

### Custom Exception

```dart
class ApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  String get arabicMessage => getArabicError(code, message);
}
```

### Error Mapping (core/error_mapping.dart)

```dart
const Map<String, String> arabicErrorMessages = {
  'AUTH_INVALID_CREDENTIALS': 'الإيميل أو كلمة السر غلط',
  'USER_DISABLED': 'الحساب موقوف',
  'NOT_FOUND': 'مش موجود',
  // ...
};

String getArabicError(String? code, [String? fallback]) {
  if (code != null && arabicErrorMessages.containsKey(code)) {
    return arabicErrorMessages[code]!;
  }
  return fallback ?? 'صار خطأ، حاول مرة ثانية';
}
```

### Error Extraction Helper

```dart
ApiException extractApiException(dynamic error) {
  if (error is DioException && error.error is ApiException) {
    return error.error as ApiException;
  }
  // fallback handling...
}
```

### Usage in Provider

```dart
try {
  _result = await _repository.doSomething();
  _state = State.success;
} catch (e) {
  final apiErr = extractApiException(e);
  _errorMessage = apiErr.arabicMessage;
  _state = State.error;
}
notifyListeners();
```

### UI Error Display

```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(provider.errorMessage ?? 'صار خطأ'),
    backgroundColor: Colors.red.shade700,
  ),
);
```

---

## 8. NAMING CONVENTIONS

| Element | Convention | Example |
|---------|-----------|---------|
| Files | snake_case | `auth_provider.dart`, `user_model.dart` |
| Classes | PascalCase | `AuthProvider`, `UserModel` |
| Providers | `FeatureProvider` | `ScanProvider`, `LogsProvider` |
| Screens | `FeatureScreen` | `LoginScreen`, `HomeScreen` |
| Entities | Singular noun | `User`, `Movement` |
| Models | `EntityModel` | `UserModel`, `MovementModel` |
| Repositories | `FeatureRepository` | `AuthRepository`, `MovementRepository` |
| Repo Impl | `FeatureRepositoryImpl` | `AuthRepositoryImpl` |
| Enums | PascalCase | `ScanFlowState`, `Destination` |
| Private fields | `_camelCase` | `_isLoading`, `_errorMessage` |
| Constants | camelCase | `arabicErrorMessages` |

---

## 9. UI STRUCTURE

### Screen Pattern

```dart
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await context.read<AuthProvider>().login(...);
    if (!mounted) return;
    // navigate or show error
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(...);
  }
}
```

### Navigation

```dart
// Push new screen
Navigator.push(context, MaterialPageRoute(builder: (_) => const NewScreen()));

// Replace all (after login/logout)
Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => const HomeScreen()),
  (route) => false,
);
```

### Private Widgets (within same file)

```dart
class _ScanTab extends StatelessWidget {
  const _ScanTab();  // No key for private widgets

  @override
  Widget build(BuildContext context) {...}
}
```

---

## 10. THEME & DESIGN SYSTEM

### Theme Definition (core/theme.dart)

```dart
class AppTheme {
  static const Color primaryColor = Color(0xFF1565C0);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color accentColor = Color(0xFF42A5F5);
  static const Color backgroundColor = Color(0xFFF5F7FA);
  static const Color surfaceColor = Colors.white;
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color successColor = Color(0xFF388E3C);
  static const Color warningColor = Color(0xFFF57C00);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      textTheme: GoogleFonts.cairoTextTheme(),
      colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
      // ... button themes, input themes, card themes
    );
  }
}
```

### Usage

```dart
MaterialApp(
  theme: AppTheme.lightTheme,
  // ...
)
```

### Enums with Styling (core/constants.dart)

```dart
enum DriverStatus {
  active, idle, inactive;

  Color get color {
    switch (this) {
      case DriverStatus.active: return const Color(0xFF388E3C);
      case DriverStatus.idle: return const Color(0xFFF57C00);
      case DriverStatus.inactive: return const Color(0xFFD32F2F);
    }
  }

  String get arabicLabel {
    switch (this) {
      case DriverStatus.active: return 'نشط';
      // ...
    }
  }
}
```

---

## 11. FEATURE CREATION GUIDE

### Step 1: Create Entity (domain/entities/)

```dart
// domain/entities/order.dart
class Order {
  final int id;
  final String code;
  final DateTime createdAt;

  const Order({required this.id, required this.code, required this.createdAt});
}
```

### Step 2: Create Model (data/models/)

```dart
// data/models/order_model.dart
class OrderModel extends Order {
  const OrderModel({required super.id, required super.code, required super.createdAt});

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as int,
      code: json['code'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
```

### Step 3: Create Repository Contract (domain/repositories/)

```dart
// domain/repositories/order_repository.dart
abstract class OrderRepository {
  Future<List<Order>> getOrders();
  Future<Order> getOrderById(int id);
}
```

### Step 4: Create Repository Implementation (data/repositories/)

```dart
// data/repositories/order_repository_impl.dart
class OrderRepositoryImpl implements OrderRepository {
  final ApiClient _apiClient;
  OrderRepositoryImpl(this._apiClient);

  @override
  Future<List<Order>> getOrders() async {
    final response = await _apiClient.dio.get('/orders');
    final data = response.data['data'] as List<dynamic>;
    return data.map((e) => OrderModel.fromJson(e)).toList();
  }
}
```

### Step 5: Create Provider (presentation/providers/)

```dart
// presentation/providers/order_provider.dart
class OrderProvider extends ChangeNotifier {
  final OrderRepository _orderRepo;
  OrderProvider(this._orderRepo);

  List<Order> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Order> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadOrders() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _orders = await _orderRepo.getOrders();
    } catch (e) {
      _errorMessage = extractApiException(e).arabicMessage;
    }
    _isLoading = false;
    notifyListeners();
  }
}
```

### Step 6: Register in ServiceLocator (core/di.dart)

```dart
late OrderRepository _orderRepository;

Future<void> init() async {
  // ...
  _orderRepository = OrderRepositoryImpl(_apiClient);
}

OrderProvider createOrderProvider() {
  return OrderProvider(_orderRepository);
}
```

### Step 7: Add to MultiProvider (main.dart)

```dart
ChangeNotifierProvider<OrderProvider>(
  create: (_) => serviceLocator.createOrderProvider(),
),
```

### Step 8: Create Screen (presentation/screens/)

```dart
// presentation/screens/orders_screen.dart
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    context.read<OrderProvider>().loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrderProvider>();
    // build UI
  }
}
```

---

## 12. DOs and DON'Ts

### ✅ DO

- **Use `const` constructors** for entities and stateless widgets
- **Call `notifyListeners()`** after every state change in providers
- **Check `mounted`** before using context after async operations
- **Use `super.` syntax** in model constructors
- **Extract API exceptions** using `extractApiException(e)`
- **Define enums** with `apiValue`, `arabicLabel`, and `fromApi()` methods
- **Keep entities pure** - no external dependencies
- **Dispose controllers** in `dispose()` method

### ❌ DON'T

- **Don't put business logic in widgets** - keep it in providers
- **Don't call API directly from UI** - go through provider → repository
- **Don't create models without fromJson** - all models need JSON parsing
- **Don't hardcode strings** - use constants or error mapping
- **Don't skip repository abstraction** - always have interface in domain/
- **Don't use `setState` for app-level state** - use Provider
- **Don't forget to handle loading/error states** in providers

---

## 13. READY-TO-USE TEMPLATE

### Feature Folder Structure

```
lib/
├── domain/
│   ├── entities/
│   │   └── {feature}.dart
│   └── repositories/
│       └── {feature}_repository.dart
├── data/
│   ├── models/
│   │   └── {feature}_model.dart
│   └── repositories/
│       └── {feature}_repository_impl.dart
└── presentation/
    ├── providers/
    │   └── {feature}_provider.dart
    └── screens/
        └── {feature}_screen.dart
```

### Entity Template

```dart
class Feature {
  final int id;
  final String name;

  const Feature({required this.id, required this.name});
}
```

### Model Template

```dart
class FeatureModel extends Feature {
  const FeatureModel({required super.id, required super.name});

  factory FeatureModel.fromJson(Map<String, dynamic> json) {
    return FeatureModel(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}
```

### Repository Contract Template

```dart
abstract class FeatureRepository {
  Future<List<Feature>> getAll();
  Future<Feature> getById(int id);
  Future<Feature> create(Map<String, dynamic> data);
}
```

### Repository Impl Template

```dart
class FeatureRepositoryImpl implements FeatureRepository {
  final ApiClient _apiClient;
  FeatureRepositoryImpl(this._apiClient);

  @override
  Future<List<Feature>> getAll() async {
    final response = await _apiClient.dio.get('/features');
    final data = response.data['data'] as List<dynamic>;
    return data.map((e) => FeatureModel.fromJson(e)).toList();
  }

  @override
  Future<Feature> getById(int id) async {
    final response = await _apiClient.dio.get('/features/$id');
    return FeatureModel.fromJson(response.data['data']);
  }

  @override
  Future<Feature> create(Map<String, dynamic> data) async {
    final response = await _apiClient.dio.post('/features', data: data);
    return FeatureModel.fromJson(response.data['data']);
  }
}
```

### Provider Template

```dart
enum FeatureState { idle, loading, loaded, error }

class FeatureProvider extends ChangeNotifier {
  final FeatureRepository _repo;
  FeatureProvider(this._repo);

  List<Feature> _items = [];
  FeatureState _state = FeatureState.idle;
  String? _errorMessage;

  List<Feature> get items => _items;
  FeatureState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == FeatureState.loading;

  Future<void> load() async {
    _state = FeatureState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _items = await _repo.getAll();
      _state = FeatureState.loaded;
    } catch (e) {
      _errorMessage = extractApiException(e).arabicMessage;
      _state = FeatureState.error;
    }
    notifyListeners();
  }
}
```

### Screen Template

```dart
class FeatureScreen extends StatefulWidget {
  const FeatureScreen({super.key});

  @override
  State<FeatureScreen> createState() => _FeatureScreenState();
}

class _FeatureScreenState extends State<FeatureScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FeatureProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeatureProvider>();

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return Center(child: Text(provider.errorMessage!));
    }

    return ListView.builder(
      itemCount: provider.items.length,
      itemBuilder: (context, index) {
        final item = provider.items[index];
        return ListTile(title: Text(item.name));
      },
    );
  }
}
```

---

## DEPENDENCIES (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  provider: ^6.1.4
  dio: ^5.4.0
  flutter_secure_storage: ^9.2.3
  google_fonts: ^6.2.1
  intl: ^0.20.2
  package_info_plus: ^8.3.0
```

---

**Document Version**: 1.0  
**Based on**: Taleeb Warehouse v1.6.0+7  
**Last Updated**: 2026-03-29
