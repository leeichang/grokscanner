import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDA Scanner Intent/KeyEvent Fix',
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
  final KeyboardVisibilityController _keyboardVisibilityController =
      KeyboardVisibilityController();

  bool _isPlatformKeyboardVisible = false; // 由 KeyboardVisibilityController 更新
  String _scannValue = '';
  String _message = '請開始掃描或點擊鍵盤圖示手動輸入';

  // 核心狀態：是否允許軟鍵盤顯示（即是否處於手動輸入模式）
  bool _allowSoftKeyboard = false;

  @override
  void initState() {
    super.initState();

    // 監聽鍵盤實際可見性
    _keyboardVisibilityController.onChange.listen((bool visible) {
      if (!mounted) return;

      final bool hadFocus = _focusNode.hasFocus; // 記錄當前是否有焦點

      setState(() {
        _isPlatformKeyboardVisible = visible;
      });

      if (visible && !_allowSoftKeyboard) {
        // 如果鍵盤意外顯示（不是手動請求的），且當前不允許軟鍵盤，則強制隱藏
        _hideKeyboard();
        _updateMessage('鍵盤自動隱藏 (掃描模式)');
      } else if (!visible && _allowSoftKeyboard) {
        // 如果鍵盤從顯示變為隱藏（例如用戶按了完成或返回鍵關閉鍵盤），
        // 且之前是手動模式，則自動切換回掃描模式。
        _updateMessage('鍵盤已隱藏，切換回掃描模式');
        // 這裡延遲是為了避免在鍵盤關閉過程中立即請求焦點可能導致的問題
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            _switchToScanMode(keepFocus: hadFocus); // 如果之前有焦點，嘗試保持
          }
        });
      } else if (visible && _allowSoftKeyboard) {
        _updateMessage('鍵盤顯示 (手動模式)');
      } else if (!visible && !_allowSoftKeyboard) {
        _updateMessage('鍵盤隱藏 (掃描模式)');
      }
    });

    // 監聽焦點變化
    _focusNode.addListener(_onFocusChange);

    // 初始時請求焦點，並確保鍵盤隱藏 (因為默認是掃描模式)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus(); // 這會觸發 _onFocusChange
      }
    });
  }

  void _onFocusChange() {
    if (!mounted) return;

    if (_focusNode.hasFocus) {
      if (!_allowSoftKeyboard) {
        // 獲得焦點，但處於掃描模式，應隱藏鍵盤
        _hideKeyboard();
        _updateMessage('獲取焦點 (掃描模式)');
      } else {
        // 獲得焦點，且處於手動模式，應顯示鍵盤
        _showKeyboard();
        _updateMessage('獲取焦點 (手動模式)');
      }
    } else {
      // 失去焦點
      if (_allowSoftKeyboard) {
        // 如果在手動模式下失去焦點，也隱藏鍵盤並考慮切回掃描模式
        // _hideKeyboard(); // KeyboardVisibilityController 的監聽器會處理
        // _switchToScanMode(keepFocus: false); // 可能會導致不必要的模式切換，先觀察
      }
      _updateMessage('失去焦點');
    }
  }

  void _hideKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _showKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  void _updateMessage(String msg) {
    if (mounted) {
      setState(() {
        _message = msg;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    // _keyboardVisibilityController is a singleton and doesn't need manual dispose usually
    super.dispose();
  }

  // 切換到手動輸入模式 (允許軟鍵盤)
  void _switchToManualMode() {
    if (!_allowSoftKeyboard) {
      if (mounted) {
        setState(() {
          _allowSoftKeyboard = true;
        });
        _updateMessage('切換到手動輸入模式');
        _focusNode.requestFocus(); // 確保焦點，_onFocusChange會處理顯示鍵盤
        // 有時需要更明確地調用 show，尤其是在狀態改變後
        Future.delayed(const Duration(milliseconds: 50), _showKeyboard);
      }
    }
  }

  // 切換回掃描模式 (不允許軟鍵盤)
  void _switchToScanMode({bool keepFocus = true}) {
    if (_allowSoftKeyboard || !keepFocus) {
      // 只有當之前是手動模式，或者明確不要保持焦點時才操作
      if (mounted) {
        setState(() {
          _allowSoftKeyboard = false;
        });
        _updateMessage('切換回掃描模式');
        _hideKeyboard();
        if (keepFocus) {
          // 延遲後重新請求焦點，確保處於掃描模式下焦點在輸入框
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && !_allowSoftKeyboard && _focusNode.parent != null) {
              _focusNode.requestFocus();
            }
          });
        } else {
          _focusNode.unfocus();
        }
      }
    } else if (keepFocus && !_focusNode.hasFocus && _focusNode.parent != null) {
      // 如果是掃描模式但意外失去焦點，則重新獲取
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDA Scanner Intent/KeyEvent Fix')),
      body: GestureDetector(
        onTap: () {
          // 點擊空白處的行為
          if (_allowSoftKeyboard) {
            // 如果是手動模式，點擊空白處則切換回掃描模式並取消焦點
            _switchToScanMode(keepFocus: false);
          } else {
            // 如果是掃描模式，點擊空白處確保鍵盤隱藏，並讓 TextField 保持焦點
            _hideKeyboard();
            if (_focusNode.parent != null && !_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
          }
        },
        // 使用 Container 包裹並設置 behavior，確保空白區域也能觸發 onTap
        child: Container(
          width: double.infinity, // 讓 GestureDetector 的區域最大化
          height: double.infinity,
          color: Colors.transparent, // 使空白區域可點擊
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                // autofocus: true, // 由 initState 中的 addPostFrameCallback 和 _onFocusChange 控制初始焦點
                // keyboardType 保持默認或 TextInputType.text，不設置為 TextInputType.none
                // 這樣才能接收 Intent/KeyEvent 輸入
                decoration: InputDecoration(
                  labelText: _allowSoftKeyboard ? '手動輸入條碼' : '請掃描條碼',
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
                onChanged: (value) {
                  // 這是最關鍵的地方！Intent/KeyEvent 數據應該會在這裡觸發
                  print('來自 onChanged 的數據: $value');
                  _updateMessage('輸入中: $value');
                  // CipherLab 的 Intent 輸出可能配置為掃描後自動加換行符，
                  // 如果是這樣，onSubmitted 也可能被觸發。
                  // 如果沒有自動換行，你可能需要在這裡檢測條碼結束的條件（如特定長度或結束符）
                },
                onSubmitted: (value) {
                  value = value.trim();
                  print('來自 onSubmitted 的數據: $value');
                  if (value.isNotEmpty) {
                    if (mounted) {
                      setState(() {
                        _scannValue = value;
                        _controller.clear(); // 清空輸入框
                        _updateMessage('條碼提交: $value');
                      });
                    }
                  }
                  // 提交後的操作
                  if (!_allowSoftKeyboard) {
                    // 掃描模式提交後，延遲後重新獲取焦點準備下次掃描
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted &&
                          !_allowSoftKeyboard &&
                          _focusNode.parent != null) {
                        _focusNode.requestFocus();
                        _hideKeyboard(); // 再次確保鍵盤隱藏
                      }
                    });
                  } else {
                    // 手動模式提交，保持焦點，允許連續輸入
                    if (mounted && _focusNode.parent != null) {
                      _focusNode.requestFocus();
                    }
                  }
                },
              ),
              const SizedBox(height: 20),
              Text(
                '當前掃描/輸入資料: ${_scannValue.isEmpty ? '無' : _scannValue}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              Text('訊息: ${_message.isEmpty ? '無' : _message}'),
              const SizedBox(height: 20),
              Text('鍵盤可見 (偵測): ${_isPlatformKeyboardVisible ? '顯示' : '隱藏'}'),
              const SizedBox(height: 10),
              Text('模式: ${_allowSoftKeyboard ? '手動輸入 (允許鍵盤)' : '掃描 (禁止鍵盤)'}'),
            ],
          ),
        ),
      ),
    );
  }
}
