# تطبيق تكوين المشتاح - دليل تسجيل الدخول برمز الموظف

## نظرة عامة

تم إضافة طريقة تسجيل دخول جديدة للتطبيق باستخدام رمز موظف مكون من 4 أرقام بدلاً من البريد الإلكتروني وكلمة المرور. هذه الطريقة مصممة خصيصاً لعمال المصنع الذين يستخدمون تطبيق التكوين.

## التغييرات المطلوبة في التطبيق

### 1. شاشة تسجيل الدخول الجديدة

استبدال شاشة تسجيل الدخول الحالية بشاشة بسيطة تحتوي على:
- حقل واحد فقط: رمز الموظف (4 أرقام)
- زر تسجيل الدخول

### 2. واجهة المستخدم المقترحة

```
┌────────────────────────────┐
│                            │
│        [شعار طليب]         │
│                            │
│   ┌────┬────┬────┬────┐   │
│   │ 1  │ 2  │ 3  │ 4  │   │
│   └────┴────┴────┴────┘   │
│                            │
│      رمز الموظف            │
│                            │
│   ┌──────────────────────┐ │
│   │      دخول            │ │
│   └──────────────────────┘ │
│                            │
└────────────────────────────┘
```

### 3. نقطة النهاية الجديدة

**URL:** `POST /api/v1/auth/pin-login`

**الطلب:**
```json
{
  "employeeCode": "1234"
}
```

**الاستجابة الناجحة (200):**
```json
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiJ9...",
    "user": {
      "id": 5,
      "name": "محمد المكوّن",
      "email": "mohammed@taleeb.ps",
      "role": "PALLETIZER"
    }
  }
}
```

### 4. معالجة الأخطاء

| كود الخطأ | HTTP Status | الرسالة للمستخدم |
|-----------|-------------|------------------|
| `EMPLOYEE_CODE_NOT_FOUND` | 401 | رمز الموظف غير صحيح |
| `USER_DISABLED` | 403 | الحساب معطل، تواصل مع الإدارة |
| `ROLE_NOT_ELIGIBLE_FOR_PIN_LOGIN` | 403 | هذا الحساب غير مصرح له |

### 5. كود Flutter المقترح

```dart
// نموذج الطلب
class PinLoginRequest {
  final String employeeCode;
  
  PinLoginRequest({required this.employeeCode});
  
  Map<String, dynamic> toJson() => {
    'employeeCode': employeeCode,
  };
}

// خدمة تسجيل الدخول
class AuthService {
  final Dio _dio;
  
  AuthService(this._dio);
  
  Future<LoginResponse> pinLogin(String employeeCode) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/pin-login',
        data: {'employeeCode': employeeCode},
      );
      
      final apiResponse = ApiResponse.fromJson(response.data);
      if (apiResponse.success) {
        return LoginResponse.fromJson(apiResponse.data);
      } else {
        throw ApiException(
          code: apiResponse.error?.code ?? 'UNKNOWN',
          message: apiResponse.error?.message ?? 'خطأ غير متوقع',
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException(
          code: 'EMPLOYEE_CODE_NOT_FOUND',
          message: 'رمز الموظف غير صحيح',
        );
      }
      rethrow;
    }
  }
}
```

### 6. واجهة إدخال الرمز

```dart
class PinInputField extends StatefulWidget {
  final Function(String) onCompleted;
  
  const PinInputField({Key? key, required this.onCompleted}) : super(key: key);
  
  @override
  State<PinInputField> createState() => _PinInputFieldState();
}

class _PinInputFieldState extends State<PinInputField> {
  final List<TextEditingController> _controllers = 
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = 
      List.generate(4, (_) => FocusNode());
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 60,
          height: 70,
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) {
              if (value.isNotEmpty && index < 3) {
                _focusNodes[index + 1].requestFocus();
              }
              _checkCompletion();
            },
          ),
        ),
      )),
    );
  }
  
  void _checkCompletion() {
    final code = _controllers.map((c) => c.text).join();
    if (code.length == 4) {
      widget.onCompleted(code);
    }
  }
}
```

## ملاحظات مهمة

1. **التوافق**: الـ JWT Token المُرجع متوافق تماماً مع النظام الحالي
2. **الأدوار المسموحة**: PALLETIZER, DRIVER, OFFICER
3. **الأدوار الممنوعة**: ADMIN, MONITORING
4. **رمز الموظف**: يحصل عليه العامل من المشرف أو الإدارة

## تدفق تسجيل الدخول

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  شاشة الإدخال   │────▶│   API Request   │────▶│   JWT Token     │
│  (4 أرقام)     │     │  pin-login      │     │   + User Info   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                              │
        │                                              ▼
        │                                    ┌─────────────────┐
        │                                    │  حفظ الـ Token  │
        │                                    │  في التخزين     │
        ▼                                    └─────────────────┘
 ┌─────────────────┐                                  │
 │   خطأ؟ عرض     │◀─────────────────────────────────┘
 │   رسالة الخطأ   │        (في حالة الفشل)
 └─────────────────┘
```

## اختبار التكامل

```bash
# تسجيل دخول ناجح
curl -X POST https://api.taleeb.me/api/v1/auth/pin-login \
  -H "Content-Type: application/json" \
  -d '{"employeeCode": "1234"}'

# رمز غير موجود
curl -X POST https://api.taleeb.me/api/v1/auth/pin-login \
  -H "Content-Type: application/json" \
  -d '{"employeeCode": "0000"}'
```

## الحصول على رمز الموظف

1. يقوم المدير بتسجيل الدخول إلى لوحة التحكم
2. يذهب إلى إدارة المستخدمين
3. يختار المستخدم أو ينشئ مستخدم جديد
4. يعيّن رمز موظف مكون من 4 أرقام
5. يبلغ الموظف برمزه الخاص

## الأمان

- كل رمز موظف فريد ولا يمكن تكراره
- الرموز تعمل فقط للأدوار التشغيلية
- يمكن للمدير تعطيل الرمز في أي وقت
