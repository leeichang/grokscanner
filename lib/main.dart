import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDA Scanner Intent Fix',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  _ScannerPageState createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // --- Intent 接收相關 ---
  // EventChannel 名稱必須與原生端一致
  static const EventChannel _scanEventChannel = EventChannel(
    'com.cympotek.grokscanner/scan_channel',
  );
  StreamSubscription? _scanSubscription;
  // ------------------------

  // --- 調試信息相關 ---
  static const MethodChannel _debugChannel = MethodChannel(
    'com.cympotek.grokscanner/debug_channel',
  );
  Map<String, dynamic> _debugInfo = {};
  StreamSubscription? _debugSubscription;
  bool _showDebugPanel = false; // 是否顯示調試面板
  // ------------------------

  String _scannValue = '';
  String _message = '請配置PDA掃描器以Intent模式輸出，或點擊鍵盤圖示手動輸入';

  // 核心狀態：是否允許軟鍵盤顯示（即是否處於手動輸入模式）
  bool _allowSoftKeyboard = false;
  bool _isKeyboardVisible = false; // 簡單追蹤鍵盤狀態

  @override
  void initState() {
    super.initState();

    // --- 開始監聽來自原生端的掃描事件 ---
    _scanSubscription = _scanEventChannel.receiveBroadcastStream().listen(
      _onScanReceived, // 成功接收到掃描數據
      onError: _onScanError, // 監聽過程中發生錯誤
    );
    // ---------------------------------

    // --- 設置調試信息通道 ---
    _setupDebugChannel();
    // --------------------------

    _focusNode.addListener(_onFocusChange);

    // 初始時請求焦點，確保處於掃描模式 (readOnly=true)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _hideKeyboard(); // 初始隱藏
        _refreshDebugInfo(); // 獲取初始調試信息
      }
    });
  }

  // 設置調試信息通道
  void _setupDebugChannel() {
    // 設置方法調用處理器
    _debugChannel.setMethodCallHandler((call) async {
      if (call.method == 'debugInfoUpdated') {
        if (mounted) {
          setState(() {
            _debugInfo = Map<String, dynamic>.from(call.arguments);
            print('調試信息更新: ${_debugInfo.length} 項');
          });
        }
        return null;
      } else if (call.method == 'directDataReceived') {
        // 直接從 MethodChannel 接收掃描數據（作為 EventChannel 的備用方案）
        if (mounted && call.arguments is String) {
          final String scannedData = call.arguments.trim();
          print("來自 MethodChannel 的掃描數據: $scannedData");
          setState(() {
            _scannValue = scannedData;
            _message = '掃描成功 (通過 MethodChannel): $scannedData';
          });
        }
        return null;
      }
      return null;
    });

    // 初始獲取調試信息
    _refreshDebugInfo();
  }

  // 刷新調試信息
  Future<void> _refreshDebugInfo() async {
    try {
      final result = await _debugChannel.invokeMethod('getDebugInfo');
      if (result != null && mounted) {
        setState(() {
          _debugInfo = Map<String, dynamic>.from(result);
          print('獲取調試信息: ${_debugInfo.length} 項');
        });
      }
    } catch (e) {
      print('獲取調試信息錯誤: $e');
    }
  }

  // --- Intent 數據處理 ---
  void _onScanReceived(dynamic data) {
    if (mounted && data is String && data.isNotEmpty) {
      final String scannedData = data.trim();
      print("來自 Intent 的掃描數據: $scannedData");
      setState(() {
        _scannValue = scannedData;
        // Intent 模式下，通常不需要將掃描結果填入 TextField，
        // 但如果需要也可以取消下面這行的註解
        // _controller.text = scannedData;
        _message = '掃描成功: $scannedData';
        // 掃描成功後可以清空 TextField 以便下次手動輸入 (如果允許的話)
        _controller.clear();
      });
      // 掃描後確保焦點仍在 TextField 且鍵盤隱藏（如果處於掃描模式）
      if (!_allowSoftKeyboard && _focusNode.parent != null) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && !_allowSoftKeyboard) {
            _focusNode.requestFocus();
            _hideKeyboard();
          }
        });
      }
    }
  }

  void _onScanError(dynamic error) {
    print("掃描事件通道錯誤: $error");
    if (mounted) {
      setState(() {
        _message = '掃描通道錯誤: $error';
      });
    }
  }
  // ------------------------

  void _onFocusChange() {
    if (!mounted) return;
    _updateMessage(_focusNode.hasFocus ? '獲取焦點' : '失去焦點');

    if (_focusNode.hasFocus) {
      if (!_allowSoftKeyboard) {
        // 掃描模式下獲得焦點，必須隱藏鍵盤
        _hideKeyboard();
        _updateMessage('獲取焦點 (掃描模式)');
      } else {
        // 手動模式下獲得焦點，嘗試顯示鍵盤
        // 顯示鍵盤的請求主要在 _switchToManualMode 中處理
        _updateMessage('獲取焦點 (手動模式，等待鍵盤)');
      }
    } else {
      // 失去焦點
      _updateMessage('失去焦點');
      // 如果是手動模式失去焦點，也切換回掃描模式
      if (_allowSoftKeyboard) {
        _hideKeyboard(); // 確保鍵盤隱藏
        _switchToScanMode(keepFocus: false);
      }
    }
  }

  void _hideKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.hide').then((_) {
      if (mounted) setState(() => _isKeyboardVisible = false);
    });
  }

  void _showKeyboard() {
    if (mounted && _allowSoftKeyboard && _focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod('TextInput.show').then((_) {
        if (mounted) setState(() => _isKeyboardVisible = true);
      });
    }
  }

  void _updateMessage(String msg) {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _message = msg;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel(); // *** 取消 Intent 監聽 ***
    _debugSubscription?.cancel(); // 取消調試信息監聽
    _debugChannel.setMethodCallHandler(null); // 清除方法調用處理器
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 切換到手動輸入模式
  void _switchToManualMode() {
    if (!_allowSoftKeyboard) {
      if (mounted) {
        _updateMessage('切換到手動輸入模式...');
        setState(() {
          _allowSoftKeyboard = true; // -> TextField readOnly 變 false
        });
        // 在下一幀執行，確保 TextField 已更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _allowSoftKeyboard) {
            _focusNode.requestFocus();
            _showKeyboard(); // 請求顯示鍵盤
            _updateMessage('請求顯示鍵盤 (手動模式)');
          }
        });
      }
    }
  }

  // 切換回掃描模式
  void _switchToScanMode({bool keepFocus = true}) {
    if (_allowSoftKeyboard || !keepFocus) {
      if (mounted) {
        _updateMessage('切換回掃描模式...');
        _hideKeyboard(); // 先隱藏鍵盤
        setState(() {
          _allowSoftKeyboard = false; // -> TextField readOnly 變 true
        });
        // 處理焦點
        if (keepFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_allowSoftKeyboard && _focusNode.parent != null) {
              _focusNode.requestFocus();
              _updateMessage('保持焦點 (掃描模式)');
              _hideKeyboard(); // 再次確保隱藏
            }
          });
        } else if (_focusNode.hasFocus) {
          _focusNode.unfocus();
          _updateMessage('移除焦點 (掃描模式)');
        }
      }
    } else if (keepFocus && !_focusNode.hasFocus && _focusNode.parent != null) {
      _focusNode.requestFocus();
      _updateMessage('重新獲取焦點 (掃描模式)');
      _hideKeyboard();
    } else if (keepFocus && _focusNode.hasFocus && !_allowSoftKeyboard) {
      _hideKeyboard(); // 冗餘保護
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDA Scanner Intent Fix'),
        actions: [
          // 添加調試按鈕
          IconButton(
            icon: Icon(_showDebugPanel ? Icons.bug_report : Icons.bug_report_outlined),
            tooltip: _showDebugPanel ? '隱藏調試面板' : '顯示調試面板',
            onPressed: () {
              setState(() {
                _showDebugPanel = !_showDebugPanel;
                if (_showDebugPanel) {
                  _refreshDebugInfo(); // 顯示調試面板時刷新調試信息
                }
              });
            },
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          if (_allowSoftKeyboard) {
            _switchToScanMode(keepFocus: false);
          } else {
            if (mounted && _focusNode.parent != null) {
              if (!_focusNode.hasFocus) {
                _focusNode.requestFocus();
              } else {
                _hideKeyboard();
              }
            }
          }
        },
        child: Container(
          color: Colors.transparent,
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                // *** 關鍵：掃描模式 readOnly=true，手動模式 readOnly=false ***
                readOnly: !_allowSoftKeyboard,
                // 鍵盤類型保持 text，以便手動模式能彈出
                keyboardType: TextInputType.text,
                showCursor: true, // 顯示光標提示焦點
                decoration: InputDecoration(
                  labelText: _allowSoftKeyboard ? '手動輸入條碼' : '請掃描條碼 (Intent模式)',
                  hintText: _allowSoftKeyboard ? '請輸入...' : '等待掃描...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _allowSoftKeyboard ? Icons.scanner : Icons.keyboard,
                    ),
                    tooltip: _allowSoftKeyboard ? '切換到掃描模式' : '切換到手動輸入模式',
                    onPressed: () {
                      if (_allowSoftKeyboard) {
                        _switchToScanMode(keepFocus: true);
                      } else {
                        _switchToManualMode();
                      }
                    },
                  ),
                ),
                // onChanged 和 onSubmitted 在 Intent 模式下，
                // 僅對手動輸入有效
                onChanged: (value) {
                  if (_allowSoftKeyboard) {
                    print('手動輸入 onChanged: $value');
                  }
                },
                onSubmitted: (value) {
                  if (_allowSoftKeyboard) {
                    value = value.trim();
                    print('手動輸入 onSubmitted: $value');
                    if (value.isNotEmpty) {
                      if (mounted) {
                        setState(() {
                          _scannValue = value; // 手動提交也更新結果
                          _controller.clear();
                          _message = '手動提交: $value';
                        });
                        // 手動提交後通常保持焦點和鍵盤
                        _focusNode.requestFocus();
                        // _showKeyboard(); // 一般不需要重複調用
                      }
                    } else {
                      // 如果提交空值，可以選擇切換回掃描模式
                      // _switchToScanMode(keepFocus: true);
                    }
                  }
                },
                onTap: () {
                  // 點擊輸入框的處理
                  if (!_allowSoftKeyboard) {
                    // 掃描模式 (readOnly=true)，點擊時確保鍵盤隱藏
                    _hideKeyboard();
                  } else {
                    // 手動模式，如果鍵盤意外隱藏了，點擊時嘗試再次顯示
                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (mounted &&
                          _allowSoftKeyboard &&
                          _focusNode.hasFocus &&
                          !_isKeyboardVisible) {
                        _showKeyboard();
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 20),
              // 掃描資料顯示區域 - 添加更明顯的視覺反饋
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _scannValue.isEmpty ? Colors.grey[200] : Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _scannValue.isEmpty ? Colors.grey : Colors.green,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '最後掃描/輸入資料:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _scannValue.isEmpty ? Colors.grey[700] : Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scannValue.isEmpty ? '無' : _scannValue,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _scannValue.isEmpty ? Colors.grey[700] : Colors.green[800],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 訊息顯示區域
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '訊息: ${_message.isEmpty ? '無' : _message}',
                  style: const TextStyle(color: Colors.blue),
                ),
              ),
              const SizedBox(height: 10),
              Text('鍵盤可見 (估計): ${_isKeyboardVisible ? '顯示' : '隱藏'}'),
              const SizedBox(height: 5),
              Text('模式: ${_allowSoftKeyboard ? '手動輸入 (允許鍵盤)' : '掃描 (禁止鍵盤)'}'),
              const SizedBox(height: 5),
              Text('TextField ReadOnly: ${!_allowSoftKeyboard}'),
              
              // 調試面板
              if (_showDebugPanel) ...[
                const Divider(height: 30, thickness: 2),
                Expanded(
                  child: _buildDebugPanel(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _refreshDebugInfo,
                      child: const Text('刷新調試信息'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          final result = await _debugChannel.invokeMethod('listAvailableIntents');
                          if (mounted) {
                            setState(() {
                              _debugInfo['intentInfo'] = result;
                            });
                          }
                        } catch (e) {
                          print('獲取Intent信息錯誤: $e');
                        }
                      },
                      child: const Text('檢查Intent配置'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        try {
                          await _debugChannel.invokeMethod('simulateScan', {'data': 'TEST_SCAN_123'});
                          setState(() {
                            _message = '已發送測試掃描 (通過Intent)';
                          });
                        } catch (e) {
                          print('發送測試掃描錯誤: $e');
                          setState(() {
                            _message = '發送測試掃描錯誤: $e';
                          });
                        }
                      },
                      child: const Text('模擬掃描 (Intent)'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        // 直接在Flutter端處理掃描數據，完全繞過Android原生端
                        final testData = 'DIRECT_TEST_${DateTime.now().millisecondsSinceEpoch}';
                        setState(() {
                          _scannValue = testData;
                          _message = '直接測試: $testData';
                        });
                      },
                      child: const Text('直接測試 (繞過原生端)'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  // 構建調試面板
  Widget _buildDebugPanel() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: ListView(
        children: [
          const Text('調試信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          
          // PDA設備信息
          _buildDebugSection('PDA設備信息', [
            'pdaModel',
            'pdaManufacturer',
            'androidVersion',
          ]),
          
          // 接收器狀態
          _buildDebugSection('接收器狀態', [
            'receiverStatus',
            'eventChannelStatus',
            'readerManagerStatus',
            'scanReceiverCreation',
          ]),
          
          // 最後接收的Intent
          _buildDebugSection('最後接收的Intent', [
            'lastReceivedAction',
            'lastReceivedTime',
            'lastEvent',
            'lastBarcodeData',
            'dataSentToFlutter',
          ]),
          
          // Intent配置
          _buildDebugSection('Intent配置', [
            'registeredActions',
          ]),
          
          // 錯誤信息
          _buildDebugSection('錯誤信息', [
            'lastError',
          ]),
          
          // 其他調試信息
          _buildDebugSection('其他調試信息', _debugInfo.keys
              .where((key) => !key.startsWith('lastExtra_') &&
                  !['pdaModel', 'pdaManufacturer', 'androidVersion',
                    'receiverStatus', 'eventChannelStatus', 'readerManagerStatus', 'scanReceiverCreation',
                    'lastReceivedAction', 'lastReceivedTime', 'lastEvent', 'lastBarcodeData', 'dataSentToFlutter',
                    'registeredActions', 'lastError', 'lastUpdated'].contains(key))
              .toList()),
          
          // Intent Extras
          _buildDebugSection('Intent Extras', _debugInfo.keys
              .where((key) => key.startsWith('lastExtra_'))
              .toList()),
        ],
      ),
    );
  }
  
  // 構建調試信息部分
  Widget _buildDebugSection(String title, List<String> keys) {
    final items = <Widget>[];
    
    for (final key in keys) {
      if (_debugInfo.containsKey(key)) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    key.startsWith('lastExtra_') ? key.substring(10) : key,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '${_debugInfo[key]}',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
          ),
        ),
        ...items,
        const Divider(),
      ],
    );
  }
}
