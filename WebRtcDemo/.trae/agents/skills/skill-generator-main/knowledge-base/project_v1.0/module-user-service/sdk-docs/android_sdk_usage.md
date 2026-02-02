# Android SDK 使用说明

## 1. SDK 概述

### 1.1 功能介绍
- **用户认证**：提供手机号登录、注册、密码重置等功能
- **用户信息管理**：提供获取和更新用户信息的功能
- **安全加密**：提供密码加密、Token管理等安全功能
- **网络请求**：封装了网络请求的通用方法
- **错误处理**：提供统一的错误处理机制

### 1.2 版本信息
- **当前版本**：1.0.0
- **最低支持 Android 版本**：7.0 (API 24)
- **依赖库**：
  - Retrofit 2.9.0
  - OkHttp 4.9.3
  - Gson 2.9.1
  - Kotlinx Coroutines 1.5.2
  - Room 2.4.0

## 2. 环境搭建

### 2.1 集成方式

#### 2.1.1 Gradle 依赖
在项目的 `build.gradle` 文件中添加以下依赖：

```gradle
// 项目级 build.gradle
allprojects {
    repositories {
        google()
        jcenter()
        maven {
            url "https://maven.example.com/repository"
        }
    }
}

// 应用级 build.gradle
dependencies {
    // 核心依赖
    implementation "com.example:user-service-sdk:1.0.0"
    
    // 必要的第三方依赖
    implementation "com.squareup.retrofit2:retrofit:2.9.0"
    implementation "com.squareup.retrofit2:converter-gson:2.9.0"
    implementation "com.squareup.okhttp3:okhttp:4.9.3"
    implementation "com.squareup.okhttp3:logging-interceptor:4.9.3"
    implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.5.2"
    implementation "androidx.room:room-runtime:2.4.0"
    kapt "androidx.room:room-compiler:2.4.0"
}
```

#### 2.1.2 权限配置
在 `AndroidManifest.xml` 文件中添加以下权限：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">

    <!-- 网络权限 -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    
    <!-- 可选：读取手机状态权限（用于获取设备ID） -->
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />

</manifest>
```

### 2.2 初始化 SDK

在应用程序的 `Application` 类中初始化 SDK：

```kotlin
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // 初始化 UserService SDK
        UserServiceSDK.init(this, "YOUR_APP_KEY", "YOUR_APP_SECRET") {
            // 配置选项
            enableDebug(true) // 开启调试模式
            setBaseUrl("https://api.example.com") // 设置 API 基础 URL
            setConnectTimeout(30) // 设置连接超时时间（秒）
            setReadTimeout(30) // 设置读取超时时间（秒）
        }
    }
}
```

## 3. 核心功能

### 3.1 用户认证

#### 3.1.1 注册

```kotlin
// 1. 发送验证码
val sendCodeRequest = SendCodeRequest(
    phoneNumber = "13800138000",
    type = 1 // 1: 注册
)

UserServiceSDK.authService.sendCode(sendCodeRequest)
    .enqueue(object : Callback<BaseResponse<Unit>> {
        override fun onResponse(call: Call<BaseResponse<Unit>>, response: Response<BaseResponse<Unit>>) {
            if (response.isSuccessful && response.body()?.code == 200) {
                // 验证码发送成功
            } else {
                // 验证码发送失败
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<Unit>>, t: Throwable) {
            // 网络错误
        }
    })

// 2. 注册
val registerRequest = RegisterRequest(
    phoneNumber = "13800138000",
    password = "Password123",
    code = "123456",
    username = "张三"
)

UserServiceSDK.authService.register(registerRequest)
    .enqueue(object : Callback<BaseResponse<LoginResponse>> {
        override fun onResponse(call: Call<BaseResponse<LoginResponse>>, response: Response<BaseResponse<LoginResponse>>) {
            if (response.isSuccessful && response.body()?.code == 200) {
                val loginResponse = response.body()?.data
                val token = loginResponse?.token
                val userInfo = loginResponse?.user
                // 注册成功，保存 token 和用户信息
            } else {
                // 注册失败
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<LoginResponse>>, t: Throwable) {
            // 网络错误
        }
    })
```

#### 3.1.2 登录

```kotlin
val loginRequest = LoginRequest(
    phoneNumber = "13800138000",
    password = "Password123"
)

UserServiceSDK.authService.login(loginRequest)
    .enqueue(object : Callback<BaseResponse<LoginResponse>> {
        override fun onResponse(call: Call<BaseResponse<LoginResponse>>, response: Response<BaseResponse<LoginResponse>>) {
            if (response.isSuccessful && response.body()?.code == 200) {
                val loginResponse = response.body()?.data
                val token = loginResponse?.token
                val userInfo = loginResponse?.user
                // 登录成功，保存 token 和用户信息
                UserServiceSDK.setToken(token)
                UserServiceSDK.setUserInfo(userInfo)
            } else {
                // 登录失败
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<LoginResponse>>, t: Throwable) {
            // 网络错误
        }
    })
```

#### 3.1.3 密码重置

```kotlin
// 1. 发送验证码
val sendCodeRequest = SendCodeRequest(
    phoneNumber = "13800138000",
    type = 3 // 3: 重置密码
)

// 2. 重置密码
val resetPasswordRequest = ResetPasswordRequest(
    phoneNumber = "13800138000",
    code = "123456",
    newPassword = "NewPassword123"
)

UserServiceSDK.authService.resetPassword(resetPasswordRequest)
    .enqueue(object : Callback<BaseResponse<Unit>> {
        override fun onResponse(call: Call<BaseResponse<Unit>>, response: Response<BaseResponse<Unit>>) {
            if (response.isSuccessful && response.body()?.code == 200) {
                // 密码重置成功
            } else {
                // 密码重置失败
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<Unit>>, t: Throwable) {
            // 网络错误
        }
    })
```

### 3.2 用户信息管理

#### 3.2.1 获取用户信息

```kotlin
UserServiceSDK.userService.getUserInfo()
    .enqueue(object : Callback<BaseResponse<UserInfo>> {
        override fun onResponse(call: Call<BaseResponse<UserInfo>>, response: Response<BaseResponse<UserInfo>>) {
            if (response.isSuccessful && response.body()?.code == 200) {
                val userInfo = response.body()?.data
                // 获取用户信息成功
            } else {
                // 获取用户信息失败
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<UserInfo>>, t: Throwable) {
            // 网络错误
        }
    })
```

#### 3.2.2 更新用户信息

```kotlin
val updateUserRequest = UpdateUserRequest(
    username = "李四",
    avatar = "https://example.com/avatar.jpg",
    birthday = "1990-01-01",
    gender = 1, // 1: 男
    email = "lisi@example.com"
)

UserServiceSDK.userService.updateUserInfo(updateUserRequest)
    .enqueue(object : Callback<BaseResponse<UserInfo>> {
        override fun onResponse(call: Call<BaseResponse<UserInfo>>, response: Response<BaseResponse<UserInfo>>) {
            if (response.isSuccessful && response.body()?.code == 200) {
                val userInfo = response.body()?.data
                // 更新用户信息成功
                UserServiceSDK.setUserInfo(userInfo)
            } else {
                // 更新用户信息失败
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<UserInfo>>, t: Throwable) {
            // 网络错误
        }
    })
```

#### 3.2.3 修改密码

```kotlin
val changePasswordRequest = ChangePasswordRequest(
    oldPassword = "OldPassword123",
    newPassword = "NewPassword123"
)

UserServiceSDK.userService.changePassword(changePasswordRequest)
    .enqueue(object : Callback<BaseResponse<Unit>> {
        override fun onResponse(call: Call<BaseResponse<Unit>>, response: Response<BaseResponse<Unit>>) {
            if (response.isSuccessful && response.body()?.code == 200) {
                // 密码修改成功
                // 注意：密码修改成功后需要重新登录
                UserServiceSDK.clearToken()
                UserServiceSDK.clearUserInfo()
            } else {
                // 密码修改失败
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<Unit>>, t: Throwable) {
            // 网络错误
        }
    })
```

### 3.3 安全功能

#### 3.3.1 Token 管理

```kotlin
// 保存 Token
UserServiceSDK.setToken("YOUR_TOKEN")

// 获取 Token
val token = UserServiceSDK.getToken()

// 清除 Token
UserServiceSDK.clearToken()

// 检查 Token 是否存在
val hasToken = UserServiceSDK.hasToken()
```

#### 3.3.2 用户信息管理

```kotlin
// 保存用户信息
UserServiceSDK.setUserInfo(userInfo)

// 获取用户信息
val userInfo = UserServiceSDK.getUserInfo()

// 清除用户信息
UserServiceSDK.clearUserInfo()
```

#### 3.3.3 密码加密

```kotlin
// 加密密码（SDK 内部使用，一般不需要直接调用）
val encryptedPassword = UserServiceSDK.securityService.encryptPassword("Password123")
```

## 4. 数据模型

### 4.1 请求模型

#### 4.1.1 发送验证码请求

```kotlin
data class SendCodeRequest(
    val phoneNumber: String,
    val type: Int // 1: 注册, 2: 登录, 3: 重置密码
)
```

#### 4.1.2 注册请求

```kotlin
data class RegisterRequest(
    val phoneNumber: String,
    val password: String,
    val code: String,
    val username: String
)
```

#### 4.1.3 登录请求

```kotlin
data class LoginRequest(
    val phoneNumber: String,
    val password: String
)
```

#### 4.1.4 重置密码请求

```kotlin
data class ResetPasswordRequest(
    val phoneNumber: String,
    val code: String,
    val newPassword: String
)
```

#### 4.1.5 更新用户信息请求

```kotlin
data class UpdateUserRequest(
    val username: String,
    val avatar: String? = null,
    val birthday: String? = null,
    val gender: Int? = null, // 0: 未知, 1: 男, 2: 女
    val email: String? = null
)
```

#### 4.1.6 修改密码请求

```kotlin
data class ChangePasswordRequest(
    val oldPassword: String,
    val newPassword: String
)
```

### 4.2 响应模型

#### 4.2.1 基础响应

```kotlin
data class BaseResponse<T>(
    val code: Int,
    val message: String,
    val data: T?
)
```

#### 4.2.2 登录响应

```kotlin
data class LoginResponse(
    val token: String,
    val user: UserInfo
)
```

#### 4.2.3 用户信息

```kotlin
data class UserInfo(
    val id: Long,
    val phoneNumber: String,
    val username: String,
    val avatar: String?,
    val birthday: String?,
    val gender: Int, // 0: 未知, 1: 男, 2: 女
    val email: String?,
    val createTime: String,
    val updateTime: String,
    val lastLoginTime: String?,
    val status: Int // 0: 正常, 1: 锁定, 2: 禁用
)
```

## 5. 错误处理

### 5.1 网络错误

```kotlin
// 使用 try-catch 捕获网络错误（协程方式）
CoroutineScope(Dispatchers.IO).launch {
    try {
        val response = UserServiceSDK.authService.login(loginRequest).await()
        if (response.code == 200) {
            // 登录成功
        } else {
            // 登录失败
        }
    } catch (e: Exception) {
        when (e) {
            is IOException -> {
                // 网络连接错误
            }
            is TimeoutException -> {
                // 网络超时错误
            }
            else -> {
                // 其他错误
            }
        }
    }
}
```

### 5.2 业务错误

```kotlin
UserServiceSDK.authService.login(loginRequest)
    .enqueue(object : Callback<BaseResponse<LoginResponse>> {
        override fun onResponse(call: Call<BaseResponse<LoginResponse>>, response: Response<BaseResponse<LoginResponse>>) {
            if (response.isSuccessful) {
                val baseResponse = response.body()
                when (baseResponse?.code) {
                    200 -> {
                        // 成功
                    }
                    1001 -> {
                        // 手机号格式错误
                    }
                    1002 -> {
                        // 手机号已注册
                    }
                    1003 -> {
                        // 手机号未注册
                    }
                    1004 -> {
                        // 验证码错误
                    }
                    1005 -> {
                        // 验证码过期
                    }
                    1006 -> {
                        // 密码错误
                    }
                    1007 -> {
                        // 账号被锁定
                    }
                    1008 -> {
                        // 账号被禁用
                    }
                    else -> {
                        // 其他错误
                    }
                }
            } else {
                // HTTP 错误
            }
        }
        
        override fun onFailure(call: Call<BaseResponse<LoginResponse>>, t: Throwable) {
            // 网络错误
        }
    })
```

## 6. 最佳实践

### 6.1 使用协程

推荐使用 Kotlin 协程进行网络请求，代码更加简洁：

```kotlin
// 1. 添加依赖
implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.5.2"

// 2. 定义扩展函数
fun <T> Call<T>.await(): T = suspendCancellableCoroutine {
    enqueue(object : Callback<T> {
        override fun onResponse(call: Call<T>, response: Response<T>) {
            if (response.isSuccessful) {
                it.resume(response.body()!!) {}
            } else {
                it.resumeWithException(HttpException(response))
            }
        }
        
        override fun onFailure(call: Call<T>, t: Throwable) {
            it.resumeWithException(t)
        }
    })
}

// 3. 使用协程
CoroutineScope(Dispatchers.Main).launch {
    try {
        val response = UserServiceSDK.authService.login(loginRequest).await()
        if (response.code == 200) {
            // 登录成功
        } else {
            // 登录失败
        }
    } catch (e: Exception) {
        // 错误处理
    }
}
```

### 6.2 封装通用方法

可以封装一些通用的方法，简化重复代码：

```kotlin
class ApiService {
    companion object {
        fun <T> request(call: Call<BaseResponse<T>>, onSuccess: (T?) -> Unit, onError: (String) -> Unit) {
            call.enqueue(object : Callback<BaseResponse<T>> {
                override fun onResponse(call: Call<BaseResponse<T>>, response: Response<BaseResponse<T>>) {
                    if (response.isSuccessful) {
                        val baseResponse = response.body()
                        if (baseResponse?.code == 200) {
                            onSuccess(baseResponse.data)
                        } else {
                            onError(baseResponse?.message ?: "请求失败")
                        }
                    } else {
                        onError("网络请求失败")
                    }
                }
                
                override fun onFailure(call: Call<BaseResponse<T>>, t: Throwable) {
                    onError("网络连接失败")
                }
            })
        }
    }
}

// 使用
ApiService.request(
    call = UserServiceSDK.authService.login(loginRequest),
    onSuccess = {
        // 登录成功
    },
    onError = {
        // 登录失败
    }
)
```

### 6.3 缓存策略

对于一些不常变化的数据，可以使用缓存：

```kotlin
// 使用 Room 缓存用户信息
@Dao
interface UserDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(user: UserEntity)
    
    @Query("SELECT * FROM user WHERE id = :userId")
    suspend fun getUserById(userId: Long): UserEntity?
    
    @Query("DELETE FROM user")
    suspend fun deleteAll()
}

// 缓存用户信息
val userEntity = UserEntity(
    id = userInfo.id,
    phoneNumber = userInfo.phoneNumber,
    username = userInfo.username,
    // 其他字段
)
userDao.insert(userEntity)

// 从缓存获取用户信息
val cachedUser = userDao.getUserById(userId)
```

## 7. 常见问题

### 7.1 网络请求失败

**问题**：网络请求总是失败，返回 `java.net.SocketTimeoutException`

**解决方案**：
- 检查网络连接是否正常
- 检查 API 基础 URL 是否正确
- 检查服务器是否正常运行
- 增加超时时间设置

### 7.2 Token 失效

**问题**：请求返回 `401 Unauthorized` 错误

**解决方案**：
- 检查 Token 是否过期
- 检查 Token 是否正确保存
- 重新登录获取新 Token

### 7.3 验证码发送失败

**问题**：发送验证码接口返回错误

**解决方案**：
- 检查手机号格式是否正确
- 检查手机号是否在黑名单中
- 检查短信服务是否正常
- 检查是否频繁发送验证码（一般有发送频率限制）

### 7.4 密码验证失败

**问题**：登录或修改密码时密码验证失败

**解决方案**：
- 检查密码是否正确
- 检查密码格式是否符合要求
- 检查密码加密方式是否正确

### 7.5 依赖冲突

**问题**：集成 SDK 后出现依赖冲突

**解决方案**：
- 检查依赖版本是否兼容
- 使用 `exclude` 排除冲突的依赖
- 使用 `resolutionStrategy` 强制使用特定版本

## 8. 版本升级

### 8.1 升级指南

#### 8.1.1 从 0.9.x 升级到 1.0.0

**主要变更**：
- 包名变更：从 `com.example.usersdk` 变更为 `com.example.userservice`
- API 变更：部分接口参数和返回值发生变化
- 依赖变更：升级了 Retrofit 和 OkHttp 的版本

**升级步骤**：
1. 更新 Gradle 依赖
2. 修改包名导入
3. 适配 API 变更
4. 测试功能是否正常

### 8.2 版本规划

| 版本 | 计划发布时间 | 主要功能 |
|------|------------|---------|
| 1.0.0 | 2023-12-31 | 基础功能 |
| 1.1.0 | 2024-03-31 | 添加第三方登录 |
| 1.2.0 | 2024-06-30 | 添加生物识别登录 |
| 2.0.0 | 2024-12-31 | 重构架构，优化性能 |

## 9. 技术支持

### 9.1 联系方式
- **邮箱**：support@example.com
- **电话**：400-123-4567
- **文档**：https://docs.example.com/user-service-sdk
- **GitHub**：https://github.com/example/user-service-sdk

### 9.2 问题反馈

如果遇到问题，可以通过以下方式反馈：

1. **GitHub Issues**：在 GitHub 仓库中提交 Issue
2. **邮箱**：发送邮件到 support@example.com
3. **在线客服**：访问官网联系在线客服

### 9.3 常见问题解答

**Q**：SDK 是否支持混淆？
**A**：支持。在 `proguard-rules.pro` 文件中添加以下规则：

```
-keep class com.example.userservice.** { *; }
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-keep class com.google.gson.** { *; }
```

**Q**：SDK 是否支持多语言？
**A**：支持。SDK 内部使用英文错误信息，外部可以根据错误码映射为不同语言。

**Q**：SDK 是否支持离线操作？
**A**：部分支持。用户认证相关功能需要网络连接，用户信息管理功能可以离线使用缓存数据。

**Q**：SDK 的安全性如何？
**A**：SDK 采用了以下安全措施：
- 密码加密存储
- Token 管理
- 网络请求加密
- 防 SQL 注入
- 防 XSS 攻击