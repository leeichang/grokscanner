package com.example.grokscanner.pda;

/**
 * 定义PDA设备使用的常量字符串
 * 根据PDA原厂提供的实现
 */
public class GeneralString {
    // 原始PDA厂商提供的常量
    public static final String BcReaderServicePackageName = "com.cipherlab.clbarcodeservice";
    public static final String BcReaderData = "Decoder_Data";
    public static final String BcReaderDataArray = "Decoder_DataArray";
    public static final String BcReaderCodeType = "Decoder_CodeType";
    public static final String BcReaderCodeTypeStr = "Decoder_CodeType_String";
    public static final String BcReaderDecodeError = "Decoder_Error";
    public static final String Intent_READERSERVICE_CONNECTED = "com.cipherlab.barcodebaseapi.SERVICE_CONNECTED";
    public static final String Intent_SOFTTRIGGER_DATA = "com.cipherlab.barcodebaseapi.SOFTTRIGGER_DATA";
    public static final String Intent_PASS_TO_APP = "com.cipherlab.barcodebaseapi.PASS_DATA_2_APP";
    public static final String Intent_DECODE_ERROR = "com.cipherlab.barcodebaseapi.decode_error";

    // 常见的扫描器Intent Actions (用于测试)
    public static final String[] COMMON_SCANNER_ACTIONS = {
        // 原厂提供的
        Intent_PASS_TO_APP,
        Intent_READERSERVICE_CONNECTED,
        Intent_SOFTTRIGGER_DATA,
        Intent_DECODE_ERROR,
        
        // 通用Intent
        "android.intent.action.MAIN",
        
        // 常见扫描器Intent Actions
        "com.symbol.datawedge.api.ACTION",
        "com.honeywell.decode.intent.action.BARCODE_DATA",
        "com.datalogic.decode.action.BARCODE_DATA",
        "device.common.SCANNER_STATE",
        "android.intent.action.DECODE_DATA",
        "scan.rcv.message",
        "com.android.server.scannerservice.broadcast",
        "com.google.zxing.client.android.SCAN",
        
        // 其他可能的Intent Actions
        "scanner.action.DECODE_DATA",
        "scanner.action.BARCODE_DATA",
        "barcode.data",
        "barcode.result",
        "com.barcode.sendResult",
        "com.scanner.broadcast",
    };
    
    // 常见的扫描器数据键 (用于测试)
    public static final String[] COMMON_DATA_KEYS = {
        // 原厂提供的
        BcReaderData,
        BcReaderDataArray,
        BcReaderCodeType,
        BcReaderCodeTypeStr,
        BcReaderDecodeError,
        
        // 常见数据键
        "data",
        "barcode",
        "barcodeData",
        "barcode_string",
        "SCAN_RESULT",
        "RESULT",
        "decode_data",
        "barcode_value",
        "data_string",
        "scanData",
        "barocode",
        "barcode_data",
        "BARCODE",
        "DECODED_DATA",
        "decode_result",
        "scan_result",
    };

    public GeneralString() {
    }
}