package com.example.grokscanner.pda;

/**
 * PDA设备的键盘模拟类型枚举
 * 根据PDA原厂提供的实现
 */
public enum KeyboardEmulationType {
    /**
     * 默认键盘模拟
     */
    Default,
    
    /**
     * 无键盘模拟
     */
    None,
    
    /**
     * 其他键盘模拟类型可以根据PDA原厂的实际实现添加
     */
}