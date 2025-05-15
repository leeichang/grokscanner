package com.example.grokscanner;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.util.Log;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

// 导入PDA厂商提供的类
import com.example.grokscanner.pda.GeneralString;
import com.example.grokscanner.pda.ReaderManager;
import com.example.grokscanner.pda.ReaderOutputConfiguration;
import com.example.grokscanner.pda.KeyboardEmulationType;

public class MainActivity extends FlutterActivity {
    private static final String TAG = "GrokScanner";
    private static final String SCAN_CHANNEL = "com.cympotek.grokscanner/scan_channel";
    private static final String DEBUG_CHANNEL = "com.cympotek.grokscanner/debug_channel";
    
    // 使用PDA厂商提供的Intent Action
    private static final String ACTION_SCAN_RECEIVED = GeneralString.Intent_PASS_TO_APP;
    
    // 使用PDA厂商提供的数据键
    private static final String EXTRA_SCAN_DATA = GeneralString.BcReaderData;
    
    private BroadcastReceiver scanReceiver;
    private EventChannel.EventSink eventSink;
    private ReaderManager mReaderManager = null;
    private MethodChannel debugChannel;
    
    // 调试信息
    private Map<String, Object> debugInfo = new HashMap<>();
    private long lastReceivedTimestamp = 0;
    private String lastReceivedAction = "None";
    private String lastReceivedData = "None";
@Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        Log.d(TAG, "Configuring Flutter Engine");
        
        try {
            // 初始化PDA的ReaderManager
            mReaderManager = ReaderManager.InitInstance(this);
            Log.d(TAG, "ReaderManager initialized successfully");
            updateDebugInfo("readerManagerStatus", "Initialized");
        } catch (Exception e) {
            Log.e(TAG, "Error initializing ReaderManager: " + e.getMessage());
            updateDebugInfo("readerManagerStatus", "Error: " + e.getMessage());
        }

        // 设置扫描事件通道
        new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SCAN_CHANNEL)
                .setStreamHandler(new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object arguments, EventChannel.EventSink events) {
                        // 當 Flutter 端開始監聽時被調用
                        Log.d(TAG, "EventChannel.onListen - Flutter is now listening for scan events");
                        eventSink = events;
                        registerScanReceiver(); // 註冊廣播接收器
                        updateDebugInfo("eventChannelStatus", "Connected");
                    }

                    @Override
                    public void onCancel(Object arguments) {
                        // 當 Flutter 端停止監聽時被調用
                        Log.d(TAG, "EventChannel.onCancel - Flutter stopped listening");
                        unregisterScanReceiver(); // 取消註冊
                        eventSink = null;
                        updateDebugInfo("eventChannelStatus", "Disconnected");
                    }
                });
        
        // 设置调试通道
        debugChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DEBUG_CHANNEL);
        debugChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("getDebugInfo")) {
                result.success(debugInfo);
            } else if (call.method.equals("listAvailableIntents")) {
                try {
                    // 尝试列出系统中可用的广播接收器
                    Map<String, Object> intentInfo = new HashMap<>();
                    intentInfo.put("registeredAction", ACTION_SCAN_RECEIVED);
                    intentInfo.put("registeredDataKey", EXTRA_SCAN_DATA);
                    result.success(intentInfo);
                } catch (Exception e) {
                    Log.e(TAG, "Error listing intents: " + e.getMessage());
                    result.error("INTENT_ERROR", e.getMessage(), null);
                }
            } else if (call.method.equals("simulateScan")) {
                try {
                    // 从Flutter获取测试数据
                    String data = call.argument("data");
                    if (data == null) {
                        data = "TEST_BARCODE_" + System.currentTimeMillis();
                    }
                    
                    Log.d(TAG, "Simulating scan with data: " + data);
                    updateDebugInfo("simulatedScan", data);
                    
                    // 方法1: 直接调用处理方法
                    if (eventSink != null) {
                        Log.d(TAG, "Directly sending simulated data to Flutter");
                        eventSink.success(data);
                        result.success(true);
                    } else {
                        // 方法2: 发送广播给自己
                        Log.d(TAG, "EventSink is null, sending broadcast instead");
                        sendTestIntent(data);
                        result.success(true);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Error simulating scan: " + e.getMessage());
                    result.error("SCAN_ERROR", e.getMessage(), null);
                }
            } else {
                result.notImplemented();
            }
        });
    }
    
    private void updateDebugInfo(String key, Object value) {
        debugInfo.put(key, value);
        debugInfo.put("lastUpdated", System.currentTimeMillis());
        
        // 如果调试通道已初始化，通知Flutter端
        if (debugChannel != null) {
            runOnUiThread(() -> {
                debugChannel.invokeMethod("debugInfoUpdated", debugInfo);
            });
        }
    }

    @Override
    protected void onDestroy() {
        unregisterScanReceiver(); // Activity 銷毀時確保取消註冊
        super.onDestroy();
    }

    private void registerScanReceiver() {
        if (scanReceiver == null) {
            Log.d(TAG, "Creating new BroadcastReceiver for scan events");
            updateDebugInfo("scanReceiverCreation", "Creating new receiver");
            
            scanReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    if (intent == null) {
                        Log.e(TAG, "Received null intent");
                        updateDebugInfo("lastError", "Received null intent");
                        return;
                    }
                    
                    String action = intent.getAction();
                    Log.d(TAG, "Intent received with action: " + action);
                    lastReceivedAction = action != null ? action : "null";
                    lastReceivedTimestamp = System.currentTimeMillis();
                    updateDebugInfo("lastReceivedAction", lastReceivedAction);
                    updateDebugInfo("lastReceivedTime", lastReceivedTimestamp);
                    
                    // 记录所有收到的Intent extras
                    StringBuilder extrasLog = new StringBuilder();
                    if (intent.getExtras() != null) {
                        for (String key : intent.getExtras().keySet()) {
                            Object value = intent.getExtras().get(key);
                            String valueStr = (value != null) ? value.toString() : "null";
                            extrasLog.append(key).append("=").append(valueStr).append(", ");
                            updateDebugInfo("lastExtra_" + key, valueStr);
                        }
                    }
                    Log.d(TAG, "Intent extras: " + extrasLog.toString());
                    updateDebugInfo("lastExtras", extrasLog.toString());
                    
                    // 处理ReaderService连接
                    if (action != null && action.equals(GeneralString.Intent_READERSERVICE_CONNECTED)) {
                        Log.d(TAG, "ReaderService connected, configuring output settings");
                        updateDebugInfo("lastEvent", "ReaderService Connected");
                        
                        try {
                            ReaderOutputConfiguration appSetting = new ReaderOutputConfiguration();
                            mReaderManager.Get_ReaderOutputConfiguration(appSetting);
                            appSetting.enableKeyboardEmulation = KeyboardEmulationType.None;
                            mReaderManager.Set_ReaderOutputConfiguration(appSetting);
                            updateDebugInfo("readerConfig", "Keyboard Emulation: None");
                            Log.d(TAG, "Reader configuration updated successfully");
                        } catch (Exception e) {
                            Log.e(TAG, "Error configuring reader: " + e.getMessage());
                            updateDebugInfo("lastError", "Reader config error: " + e.getMessage());
                        }
                    }
                    
                    // 处理扫描数据 - 首先尝试原始的Intent Action和Extra
                    if (action != null && action.equals(GeneralString.Intent_PASS_TO_APP)) {
                        Log.d(TAG, "Scan data intent received with expected action");
                        updateDebugInfo("lastEvent", "Scan Data Received (Expected Action)");
                        
                        String barcodeData = intent.getStringExtra(GeneralString.BcReaderData);
                        if (barcodeData != null && !barcodeData.isEmpty()) {
                            processBarcodeData(barcodeData, "Expected Action/Extra");
                        } else {
                            Log.d(TAG, "No data found with expected extra key, trying other keys...");
                            tryAllPossibleDataKeys(intent, "Expected Action");
                        }
                    } else {
                        // 尝试处理任何Intent，检查所有可能的数据键
                        Log.d(TAG, "Received action: " + action + ", trying all possible data keys");
                        updateDebugInfo("lastEvent", "Received Intent (Unknown Action)");
                        tryAllPossibleDataKeys(intent, "Unknown Action");
                    }
                }
            };
            
            // 创建IntentFilter来指定要接收的广播Action
            IntentFilter filter = new IntentFilter();
            
            // 添加所有可能的Intent actions
            StringBuilder actionsLog = new StringBuilder();
            for (String actionName : GeneralString.COMMON_SCANNER_ACTIONS) {
                filter.addAction(actionName);
                actionsLog.append(actionName).append(", ");
            }
            
            // 添加通配符Intent action (如果支持)
            try {
                filter.addAction("*");
                actionsLog.append("* (wildcard), ");
            } catch (Exception e) {
                Log.d(TAG, "Wildcard intent action not supported");
            }
            
            // 添加默认类别
            filter.addCategory(Intent.CATEGORY_DEFAULT);
            
            updateDebugInfo("registeredActions", actionsLog.toString());
            
            try {
                // 注册接收器
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    // Android 13及以上需要指定导出行为
                    registerReceiver(scanReceiver, filter, Context.RECEIVER_EXPORTED);
                    Log.d(TAG, "ScanReceiver registered with RECEIVER_EXPORTED flag");
                } else {
                    registerReceiver(scanReceiver, filter);
                    Log.d(TAG, "ScanReceiver registered without flags");
                }
                updateDebugInfo("receiverStatus", "Registered");
                updateDebugInfo("androidVersion", android.os.Build.VERSION.SDK_INT);
                updateDebugInfo("pdaModel", android.os.Build.MODEL);
                updateDebugInfo("pdaManufacturer", android.os.Build.MANUFACTURER);
                
                // 发送一个测试Intent给自己，验证接收器是否正常工作
                sendTestIntent();
            } catch (Exception e) {
                Log.e(TAG, "Error registering receiver: " + e.getMessage());
                updateDebugInfo("lastError", "Receiver registration error: " + e.getMessage());
                updateDebugInfo("receiverStatus", "Error");
            }
        } else {
            Log.d(TAG, "ScanReceiver already registered");
            updateDebugInfo("receiverStatus", "Already Registered");
        }
    }
    
    // 尝试所有可能的数据键
    private void tryAllPossibleDataKeys(Intent intent, String source) {
        boolean dataFound = false;
        
        // 首先检查所有extras
        if (intent.getExtras() != null) {
            for (String key : intent.getExtras().keySet()) {
                Object value = intent.getExtras().get(key);
                if (value instanceof String) {
                    String strValue = (String) value;
                    if (!strValue.isEmpty()) {
                        Log.d(TAG, "Found potential barcode data in key: " + key + " = " + strValue);
                        processBarcodeData(strValue, source + " (Key: " + key + ")");
                        dataFound = true;
                    }
                }
            }
        }
        
        // 然后尝试所有常见的数据键
        for (String key : GeneralString.COMMON_DATA_KEYS) {
            String value = intent.getStringExtra(key);
            if (value != null && !value.isEmpty()) {
                Log.d(TAG, "Found barcode data with key: " + key + " = " + value);
                processBarcodeData(value, source + " (Key: " + key + ")");
                dataFound = true;
            }
        }
        
        // 如果没有找到数据，记录错误
        if (!dataFound) {
            Log.e(TAG, "No barcode data found in any known key");
            updateDebugInfo("lastError", "No barcode data found in any known key");
            if (eventSink != null) {
                eventSink.error("SCAN_ERROR", "No barcode data found in any known key", null);
            }
        }
    }
    
    // 处理条码数据
    private void processBarcodeData(String barcodeData, String source) {
        lastReceivedData = barcodeData;
        updateDebugInfo("lastBarcodeData", lastReceivedData);
        updateDebugInfo("barcodeSource", source);
        
        Log.d(TAG, "Processing barcode data: " + barcodeData + " from " + source);
        
        if (eventSink != null) {
            try {
                // 将扫描数据发送给Flutter
                Log.d(TAG, "Sending barcode data to Flutter via EventSink");
                eventSink.success(barcodeData);
                updateDebugInfo("dataSentToFlutter", "true");
                updateDebugInfo("eventSinkStatus", "Active and used");
                
                // 尝试通过MethodChannel直接发送数据作为备份
                if (debugChannel != null) {
                    runOnUiThread(() -> {
                        try {
                            debugChannel.invokeMethod("directDataReceived", barcodeData);
                            Log.d(TAG, "Also sent data via MethodChannel as backup");
                            updateDebugInfo("methodChannelDataSent", "true");
                        } catch (Exception e) {
                            Log.e(TAG, "Error sending via MethodChannel: " + e.getMessage());
                        }
                    });
                }
            } catch (Exception e) {
                Log.e(TAG, "Error sending via EventSink: " + e.getMessage());
                updateDebugInfo("lastError", "EventSink error: " + e.getMessage());
                updateDebugInfo("dataSentToFlutter", "error");
                updateDebugInfo("eventSinkException", e.toString());
                
                // 如果EventSink失败，尝试通过MethodChannel发送
                if (debugChannel != null) {
                    runOnUiThread(() -> {
                        try {
                            debugChannel.invokeMethod("directDataReceived", barcodeData);
                            Log.d(TAG, "Sent data via MethodChannel after EventSink failure");
                            updateDebugInfo("methodChannelDataSent", "true (after EventSink failure)");
                        } catch (Exception ex) {
                            Log.e(TAG, "Error sending via MethodChannel: " + ex.getMessage());
                        }
                    });
                }
            }
        } else {
            Log.e(TAG, "EventSink is null, cannot send data to Flutter");
            updateDebugInfo("lastError", "EventSink is null");
            updateDebugInfo("dataSentToFlutter", "false");
            updateDebugInfo("eventSinkStatus", "Null");
            
            // 尝试通过MethodChannel直接发送数据作为备份
            if (debugChannel != null) {
                runOnUiThread(() -> {
                    try {
                        debugChannel.invokeMethod("directDataReceived", barcodeData);
                        Log.d(TAG, "Sent data via MethodChannel as fallback");
                        updateDebugInfo("methodChannelDataSent", "true (fallback)");
                    } catch (Exception e) {
                        Log.e(TAG, "Error sending via MethodChannel: " + e.getMessage());
                    }
                });
            }
        }
    }
    
    // 发送测试Intent给自己
    private void sendTestIntent() {
        sendTestIntent("TEST_BARCODE_123");
    }
    
    // 发送测试Intent给自己 (带数据)
    private void sendTestIntent(String data) {
        try {
            Log.d(TAG, "Sending test intent to self with data: " + data);
            Intent testIntent = new Intent(GeneralString.Intent_PASS_TO_APP);
            testIntent.putExtra(GeneralString.BcReaderData, data);
            testIntent.setPackage(getPackageName());
            sendBroadcast(testIntent);
            Log.d(TAG, "Test intent sent");
            updateDebugInfo("testIntentSent", "true");
            updateDebugInfo("testIntentData", data);
        } catch (Exception e) {
            Log.e(TAG, "Error sending test intent: " + e.getMessage());
            updateDebugInfo("lastError", "Test intent error: " + e.getMessage());
        }
    }

    private void unregisterScanReceiver() {
        if (scanReceiver != null) {
            try {
                Log.d(TAG, "Unregistering ScanReceiver");
                unregisterReceiver(scanReceiver);
                scanReceiver = null;
                Log.d(TAG, "ScanReceiver unregistered successfully");
                updateDebugInfo("receiverStatus", "Unregistered");
            } catch (IllegalArgumentException e) {
                // 如果接收器未註冊，可能會拋出此異常，可以安全地忽略
                Log.e(TAG, "Error unregistering receiver: " + e.getMessage());
                updateDebugInfo("lastError", "Unregister error: " + e.getMessage());
            }
        } else {
            Log.d(TAG, "ScanReceiver is already null, nothing to unregister");
        }
    }
}