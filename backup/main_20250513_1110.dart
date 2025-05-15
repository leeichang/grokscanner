import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'dart:async'; // 引入 Timer

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDA Scanner Flicker Fix',
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

  StreamSubscription<bool>? _keyboardSubscription; // 用於取消訂閱
  bool _isPlatformKeyboardVisible = false;
  String _scannValue = '';
  String _message = '請開始掃描或點擊鍵盤圖示手動輸入';
  bool _allowSoftKeyboard = false;
  Timer? _hideKeyboardTimer; // 用於延遲隱藏

  @override
  void initState() {
    super.initState();

    _keyboardSubscription = _keyboardVisibilityController.onChange.listen((
      bool visible,
    ) {
      if (!mounted) return;

      final bool hadFocus = _focusNode.hasFocus;

      // 取消之前的延遲隱藏計時器（如果有的話）
      _hideKeyboardTimer?.cancel();

      // 更新鍵盤可見狀態
      final bool keyboardVisibilityChanged =
          _isPlatformKeyboardVisible != visible;
      if (keyboardVisibilityChanged) {
        if (mounted) {
          setState(() {
            _isPlatformKeyboardVisible = visible;
          });
        }
      }

      if (visible && !_allowSoftKeyboard) {
        // *** 關鍵：檢測到鍵盤意外顯示（掃描模式下），立即嘗試隱藏 ***
        // 這裡不使用延遲，直接、快速地隱藏是減少閃爍的關鍵
        _hideKeyboard();
        _updateMessage('鍵盤自動隱藏 (掃描模式)');
      } else if (!visible && _allowSoftKeyboard) {
        // 從手動模式變為隱藏，切換回掃描模式
        _updateMessage('鍵盤已隱藏，切換回掃描模式');
        // 延遲是為了確保狀態切換穩定
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            _switchToScanMode(keepFocus: hadFocus);
          }
        });
      } else if (visible && _allowSoftKeyboard) {
        _updateMessage('鍵盤顯示 (手動模式)');
      } else if (!visible && !_allowSoftKeyboard) {
        _updateMessage('鍵盤隱藏 (掃描模式)');
      }
    });

    _focusNode.addListener(_onFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus(); // 會觸發 _onFocusChange
      }
    });
  }

  void _onFocusChange() {
    if (!mounted) return;

    // 取消可能的延遲隱藏計時器
    _hideKeyboardTimer?.cancel();

    if (_focusNode.hasFocus) {
      if (!_allowSoftKeyboard) {
        // *** 關鍵：獲得焦點且是掃描模式，確保鍵盤隱藏 ***
        // 同樣，直接隱藏
        _hideKeyboard();
        _updateMessage('獲取焦點 (掃描模式)');
      } else {
        // 手動模式獲得焦點，請求顯示鍵盤
        _showKeyboard();
        _updateMessage('獲取焦點 (手動模式)');
      }
    } else {
      // 失去焦點，確保鍵盤隱藏（以防萬一）
      _hideKeyboard();
      _updateMessage('失去焦點');
      // 如果之前是手動模式，失去焦點也應該切換回掃描模式
      if (_allowSoftKeyboard) {
        _switchToScanMode(keepFocus: false); //失去焦點就不用保持了
      }
    }
  }

  // 封裝隱藏鍵盤操作
  void _hideKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  // 封裝顯示鍵盤操作
  void _showKeyboard() {
    // 確保在請求顯示前 TextField 是可編輯的
    if (mounted && _allowSoftKeyboard) {
      // 稍微延遲以確保 keyboardType 已經是 text
      Future.delayed(const Duration(milliseconds: 20), () {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      });
    }
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
    _keyboardSubscription?.cancel(); // 取消監聽
    _focusNode.removeListener(_onFocusChange);
    _hideKeyboardTimer?.cancel(); // 取消計時器
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _switchToManualMode() {
    if (!_allowSoftKeyboard) {
      if (mounted) {
        setState(() {
          _allowSoftKeyboard = true; // 先改變狀態，觸發 TextField 重建
        });
        _updateMessage('切換到手動輸入模式');
        _focusNode.requestFocus(); // 請求焦點，_onFocusChange 會嘗試顯示鍵盤
        // 再次調用 _showKeyboard 以增加可靠性
        _showKeyboard();
      }
    }
  }

  void _switchToScanMode({bool keepFocus = true}) {
    // 只有當處於手動模式，或者失去焦點時才執行切換邏輯
    if (_allowSoftKeyboard || !keepFocus) {
      if (mounted) {
        setState(() {
          _allowSoftKeyboard = false; // 先改變狀態，觸發 TextField 重建
        });
        _updateMessage('切換回掃描模式');
        _hideKeyboard(); // 確保鍵盤隱藏

        if (keepFocus) {
          // 延遲後重新請求焦點
          Future.delayed(const Duration(milliseconds: 100), () {
            // 再次檢查狀態，防止在延遲期間狀態又變了
            if (mounted && !_allowSoftKeyboard && _focusNode.parent != null) {
              _focusNode.requestFocus();
            }
          });
        } else if (_focusNode.hasFocus) {
          // 如果不需要保持焦點，則取消焦點
          _focusNode.unfocus();
        }
      }
    } else if (keepFocus && !_focusNode.hasFocus && _focusNode.parent != null) {
      // 如果是掃描模式但意外失去焦點，且要求保持焦點，則重新獲取
      _focusNode.requestFocus();
    } else if (keepFocus && _focusNode.hasFocus && !_allowSoftKeyboard) {
      // 如果是掃描模式且有焦點，確保鍵盤隱藏（冗餘保護）
      _hideKeyboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    // print("Building with _allowSoftKeyboard: $_allowSoftKeyboard"); // Debugging
    return Scaffold(
      appBar: AppBar(title: const Text('PDA Scanner Flicker Fix')),
      body: GestureDetector(
        onTap: () {
          if (_allowSoftKeyboard) {
            _switchToScanMode(keepFocus: false); // 手動模式點空白，切換並失焦
          } else {
            // 掃描模式點空白，確保焦點在輸入框且鍵盤隱藏
            if (mounted && _focusNode.parent != null && !_focusNode.hasFocus) {
              _focusNode.requestFocus(); // 會觸發 _onFocusChange 來隱藏鍵盤
            } else {
              _hideKeyboard(); // 如果已有焦點，再次確保鍵盤隱藏
            }
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.transparent,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                // *** 關鍵改動：根據模式動態設置 keyboardType ***
                keyboardType:
                    _allowSoftKeyboard
                        ? TextInputType
                            .text // 手動模式：允許標準鍵盤
                        : TextInputType.none, // 掃描模式：告訴系統不需要軟鍵盤
                // 即使 TextInputType.none，showCursor 仍然有用，指示焦點位置
                showCursor: true,
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
                  print('來自 onChanged 的數據: $value');
                  // onChanged 本身不應影響鍵盤顯示邏輯
                },
                onSubmitted: (value) {
                  value = value.trim();
                  print('來自 onSubmitted 的數據: $value');
                  if (value.isNotEmpty) {
                    if (mounted) {
                      setState(() {
                        _scannValue = value;
                        _controller.clear();
                        _updateMessage('條碼提交: $value');
                      });
                    }
                  }
                  // 提交後
                  if (!_allowSoftKeyboard) {
                    // 掃描模式提交後，保持焦點並確保鍵盤隱藏
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted &&
                          !_allowSoftKeyboard &&
                          _focusNode.parent != null) {
                        _focusNode.requestFocus(); // _onFocusChange 會處理隱藏
                      }
                    });
                  } else {
                    // 手動模式提交，保持焦點和鍵盤
                    if (mounted && _focusNode.parent != null) {
                      _focusNode.requestFocus(); // 保持焦點，鍵盤應已顯示
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
