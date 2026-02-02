package com.example.webrtctest.userservice

import android.util.Log

/**
 * 用户登录服务
 * 提供用户登录相关功能，包含参数校验和异常处理
 */
class UserLoginService {

    private val TAG = "UserLoginService"

    /**
     * 用户登录方法
     * 
     * @param phoneNumber 用户手机号
     * @param password 用户密码
     * @return 登录结果，成功返回 true，失败返回 false
     * @throws IllegalArgumentException 当手机号或密码为空时抛出
     * @throws Exception 其他登录过程中的异常
     */
    @Throws(IllegalArgumentException::class, Exception::class)
    fun login(phoneNumber: String?, password: String?): Boolean {
        try {
            // 应用 Bug 修复方案：添加手机号非空校验
            // 修复内容：登录接口未校验手机号为空的情况，导致运行时空指针异常
            if (phoneNumber.isNullOrEmpty()) {
                throw IllegalArgumentException("手机号不能为空")
            }

            // 添加密码非空校验
            if (password.isNullOrEmpty()) {
                throw IllegalArgumentException("密码不能为空")
            }

            // 手机号格式校验
            if (!isValidPhoneNumber(phoneNumber)) {
                throw IllegalArgumentException("手机号格式不正确")
            }

            // 密码长度校验
            if (password.length < 6) {
                throw IllegalArgumentException("密码长度不能少于6位")
            }

            // 执行登录业务逻辑
            Log.d(TAG, "执行登录操作: 手机号=$phoneNumber")

            // 模拟登录成功
            Log.d(TAG, "登录成功: 手机号=$phoneNumber")
            return true

        } catch (e: IllegalArgumentException) {
            // 捕获参数校验异常
            Log.e(TAG, "登录参数错误: ${e.message}")
            throw e
        } catch (e: Exception) {
            // 捕获其他异常
            Log.e(TAG, "登录失败: ${e.message}")
            throw e
        }
    }

    /**
     * 验证手机号格式是否正确
     * 
     * @param phoneNumber 手机号
     * @return 格式正确返回 true，否则返回 false
     */
    private fun isValidPhoneNumber(phoneNumber: String): Boolean {
        // 简单的手机号格式校验（中国大陆手机号）
        val phoneRegex = "1[3-9]\\d{9}".toRegex()
        return phoneRegex.matches(phoneNumber)
    }

    /**
     * 登出方法
     * 
     * @param userId 用户ID
     * @return 登出结果，成功返回 true，失败返回 false
     */
    fun logout(userId: String?): Boolean {
        try {
            if (userId.isNullOrEmpty()) {
                throw IllegalArgumentException("用户ID不能为空")
            }

            Log.d(TAG, "执行登出操作: 用户ID=$userId")
            Log.d(TAG, "登出成功: 用户ID=$userId")
            return true

        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "登出参数错误: ${e.message}")
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "登出失败: ${e.message}")
            throw e
        }
    }
}
