package com.example.webrtctest.userservice

/**
 * 用户登录请求参数
 * 封装登录接口所需的参数信息
 */
data class UserLoginRequest(
    /**
     * 用户手机号
     */
    val phoneNumber: String,
    
    /**
     * 用户密码
     */
    val password: String
) {
    
    /**
     * 验证请求参数是否合法
     * 
     * @return 合法返回 true，否则返回 false
     */
    fun isValid(): Boolean {
        return phoneNumber.isNotEmpty() && password.isNotEmpty() && password.length >= 6
    }
    
    /**
     * 获取参数验证错误信息
     * 
     * @return 错误信息，参数合法返回 null
     */
    fun getValidationError(): String? {
        return when {
            phoneNumber.isEmpty() -> "手机号不能为空"
            password.isEmpty() -> "密码不能为空"
            password.length < 6 -> "密码长度不能少于6位"
            else -> null
        }
    }
}
