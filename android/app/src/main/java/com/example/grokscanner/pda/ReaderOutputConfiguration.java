package com.example.grokscanner.pda;

/**
 * PDA设备的读取器输出配置类
 * 根据PDA原厂提供的实现
 */
public class ReaderOutputConfiguration {
    /**
     * 键盘模拟类型
     */
    public KeyboardEmulationType enableKeyboardEmulation = KeyboardEmulationType.Default;
    
    // 其他配置属性可以根据PDA原厂的实际实现添加
}