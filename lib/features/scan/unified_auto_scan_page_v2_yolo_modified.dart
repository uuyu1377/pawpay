import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 引入震動功能
import 'package:mobile_scanner/mobile_scanner.dart';
// 🔥 音效套件
import 'package:audioplayers/audioplayers.dart';

// 引入 Service
import 'package:dio/dio.dart';
// 2. 加入你的 RemoteOcrService 路徑
import '../../services/remote_ocr_service.dart';
import '../../services/yolo_qr_pipeline_letterbox.dart';

enum ScanMode { electronicQr, traditionalOcr }

class UnifiedAutoScanPageV2 extends StatefulWidget {
  final bool forceTraditional;
  const UnifiedAutoScanPageV2({super.key, this.forceTraditional = false});

  @override
  State<UnifiedAutoScanPageV2> createState() => _UnifiedAutoScanPageV2State();
}

class _UnifiedAutoScanPageV2State extends State<UnifiedAutoScanPageV2> with TickerProviderStateMixin, WidgetsBindingObserver {
  // ====== Mode ======
  late ScanMode _mode;

  // ====== QR Scanner ======
  MobileScannerController? _qrController;
  int _qrSession = 0;

  // ====== Camera (OCR) ======
  CameraController? _cam;
  bool _camReady = false;

  // ====== State ======
  bool _processing = false;
  String _hint = '';
  String? _qrValue;
  String? _rawOcrResult;

  // ====== E-Invoice Dual QR Buffer ======
  String? _eiLeftQr;
  String? _eiRightQr;
  Timer? _eiFinalizeTimer;
  static const Duration _kEiFinalizeDelay = Duration(milliseconds: 900);

  // ====== YOLO assist for real-time QR scanning ======
  Timer? _yoloAssistTimer;
  bool _yoloAssistActive = false;
  bool _yoloModelReady = false;
  String? _yoloAssistMessage;
  static const Duration _kYoloAssistDelay = Duration(seconds: 3);

  // ====== 動畫與特效 ======
  late AnimationController _energyController; // 能量條控制器

  // 獨立控制左右框顏色
  bool _isLeftSuccess = false;
  bool _isRightSuccess = false;
  bool _isOcrSuccess = false;

  // 音效播放器
  final AudioPlayer _audioPlayer = AudioPlayer();

  static const int kElectronicTimeoutSeconds = 10;
  static const int kTraditionalAutoShootSeconds = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 初始化能量條
    _energyController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: kElectronicTimeoutSeconds),
    );

    // 1. 監聽倒數進度，提前更換提示詞
    _energyController.addListener(() {
      if (_qrValue != null || _processing) return;
      if (_mode != ScanMode.electronicQr) return;

      final val = _energyController.value;

      if (_yoloAssistActive) return;

      if (val > 0.95) {
        if (_hint != '我看不太清楚，我們用拍的吧？') {
          setState(() => _hint = '我看不太清楚，我們用拍的吧？');
        }
      } else if (val > 0.7) {
        if (_hint != '嗚... 有點模糊，請拿遠一點～') {
          setState(() => _hint = '嗚... 有點模糊，請拿遠一點～');
        }
      } else if (val > 0.35 && !_yoloAssistActive) {
        if (_hint != '我正在找 QR 的位置，請保持發票平穩～') {
          setState(() => _hint = '我正在找 QR 的位置，請保持發票平穩～');
        }
      }
    });

    // 監聽動畫結束 -> 自動觸發拍照
    _energyController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_mode == ScanMode.electronicQr) _switchToAutoPhoto();
        else if (_mode == ScanMode.traditionalOcr) _shootAndOcr();
      }
    });

    _mode = widget.forceTraditional ? ScanMode.traditionalOcr : ScanMode.electronicQr;

    if (_mode == ScanMode.traditionalOcr) {
      _hint = '主人～ 請讓我看看發票喔';
      _enterTraditional(immediateShoot: false);
    } else {
      _hint = '主人～ 請讓我看看兩個 QR Code 喔';
      _enterElectronic();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eiFinalizeTimer?.cancel();
    _yoloAssistTimer?.cancel();
    _energyController.dispose();
    _audioPlayer.dispose();
    _disposeQr();
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _yoloAssistTimer?.cancel();
      if (_mode == ScanMode.traditionalOcr) {
        _cam?.dispose();
        _cam = null;
        _camReady = false;
      } else {
        _qrController?.stop();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_mode == ScanMode.traditionalOcr) {
        _initCameraIfNeeded();
      } else {
        _restartQr();
      }
    }
  }

  // ====== QR control ======
  void _ensureQrController() {
    _qrController?.dispose();
    _qrController = MobileScannerController(autoStart: false, torchEnabled: false);
  }

  Future<void> _restartQr() async {
    if (!mounted) return;
    _qrSession++;
    _ensureQrController();
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 120));
    await _qrController?.start();
  }

  void _disposeQr() {
    final c = _qrController;
    _qrController = null;
    if (c != null) { try { c.dispose(); } catch (_) {} }
  }

  // ====== 音效輔助函式 ======
  Future<void> _playSound(String fileName) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/$fileName'));
    } catch (e) {
      debugPrint('音效播放失敗: $e');
    }
  }

  // ====== Mode switching ======
  Future<void> _enterElectronic() async {
    _eiFinalizeTimer?.cancel();
    await _disposeCamera();
    _rawOcrResult = null;
    _qrValue = null;

    // 重置狀態
    _isLeftSuccess = false;
    _isRightSuccess = false;
    _isOcrSuccess = false;
    _eiLeftQr = null;
    _eiRightQr = null;
    _yoloAssistTimer?.cancel();
    _yoloAssistActive = false;
    _yoloModelReady = false;
    _yoloAssistMessage = null;

    setState(() {
      _mode = ScanMode.electronicQr;
      _processing = false;
      _hint = '主人～ 請讓我看看兩個 QR Code 喔';
    });

    await _restartQr();

    // 啟動能量條動畫
    _energyController.duration = const Duration(seconds: kElectronicTimeoutSeconds);
    _energyController.reset();
    _energyController.forward();
    _scheduleYoloAssistProbe();
  }

  Future<void> _enterTraditional({required bool immediateShoot, String? hintOverride}) async {
    _eiFinalizeTimer?.cancel();
    _yoloAssistTimer?.cancel();
    _yoloAssistActive = false;
    await _qrController?.stop();
    await Future.delayed(const Duration(milliseconds: 180));
    _rawOcrResult = null;
    _qrValue = null;

    // 重置狀態
    _isLeftSuccess = false;
    _isRightSuccess = false;
    _isOcrSuccess = false;

    setState(() {
      _mode = ScanMode.traditionalOcr;
      _processing = false;
      _hint = hintOverride ?? '主人～ 請讓我看看發票喔';
    });

    await _initCameraIfNeeded();

    if (immediateShoot) {
      await Future.delayed(const Duration(milliseconds: 180));
      if (mounted) await _shootAndOcr();
    } else {
      _energyController.duration = const Duration(seconds: kTraditionalAutoShootSeconds);
      _energyController.reset();
      _energyController.forward();
    }
  }

  Future<void> _initCameraIfNeeded() async {
    if (_camReady && _cam != null) return;
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      try { await controller.setFocusMode(FocusMode.auto); await controller.setExposureMode(ExposureMode.auto); } catch (_) {}
      await _disposeCamera();
      _cam = controller;
      _camReady = true;
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() { _camReady = false; _hint = '相機初始化失敗：$e'; });
    }
  }

  Future<void> _disposeCamera() async {
    final c = _cam;
    _cam = null;
    _camReady = false;
    if (c != null) { try { await c.dispose(); } catch (_) {} }
  }

  // 自動切換邏輯
  Future<void> _switchToAutoPhoto() async {
    if (!mounted) return;
    if (_mode != ScanMode.electronicQr) return;
    if (_qrValue != null) return;
    if (_processing) return;

    _yoloAssistTimer?.cancel();
    // 提示詞已由 listener 更新
    await _qrController?.stop();
    await _initCameraIfNeeded();
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) await _shootAndOcr();
  }

  void _scheduleYoloAssistProbe({Duration delay = _kYoloAssistDelay}) {
    _yoloAssistTimer?.cancel();
    if (_mode != ScanMode.electronicQr) return;
    if (_qrValue != null || _processing) return;
    _yoloAssistTimer = Timer(delay, () {
      if (mounted) _startYoloMobileScannerAssist();
    });
  }

  /// 展示版的「YOLO + MobileScanner」：
  ///
  /// MobileScanner 繼續掌握相機、即時讀 QR；YOLO 在旁邊先載入模型並提示使用者
  /// 對準 QR，不再中途搶相機拍照。這樣可避免上一版出現「有鏡頭 → 空白 → 有鏡頭」
  /// 的畫面閃爍。若倒數結束仍讀不到，才會切換一次到拍照強化流程：
  /// YOLO 定位 QR → ML Kit 解碼裁切圖 → OCR 備援。
  Future<void> _startYoloMobileScannerAssist() async {
    if (!mounted) return;
    if (_mode != ScanMode.electronicQr) return;
    if (_qrValue != null || _processing || _yoloAssistActive) return;

    setState(() {
      _yoloAssistActive = true;
      _yoloAssistMessage = 'YOLO 輔助已啟動：請把兩個 QR 放進框內，MobileScanner 會持續讀取內容';
      _hint = 'YOLO 正在輔助對準，請保持發票平穩～';
    });

    try {
      await YoloQrPipeline.instance.loadModel();
      if (!mounted || _mode != ScanMode.electronicQr || _qrValue != null) return;
      setState(() {
        _yoloModelReady = true;
        _yoloAssistMessage = 'YOLO 模型已準備好；若即時掃描失敗，下一步會拍照定位 QR';
      });
    } catch (e) {
      if (!mounted || _mode != ScanMode.electronicQr || _qrValue != null) return;
      setState(() {
        _yoloAssistMessage = 'YOLO 輔助載入失敗，仍會繼續用 MobileScanner 掃描';
      });
    }
  }

  void _startTraditionalAutoShoot() {
    _energyController.duration = const Duration(seconds: kTraditionalAutoShootSeconds);
    _energyController.reset();
    _energyController.forward();
  }

  // 內容檢查
  bool _isValidReceipt(String text) {
    if (text.length < 10) return false;
    if (!text.contains(RegExp(r'\d'))) return false;
    final keywords = ['發票', '收銀機', '總計', '合計', '民國', '日期', '統編', '賣方', '金額'];
    for (var k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }

  // ====== Actions ======
  Future<void> _shootAndOcr() async {
    if (_cam == null || !_camReady) {
      await _initCameraIfNeeded();
      if (_cam == null || !_camReady) return;
    }
    if (_processing) return;

    _energyController.stop();

    setState(() {
      _processing = true;
      _hint = '拍照處理中...';
    });

    try {
      final x = await _cam!.takePicture();
      final file = File(x.path);

      // 電子發票模式下：MobileScanner 即時掃描逾時後，使用 YOLO 定位 QR，
      // 再交給 QR 解碼器讀取內容。失敗才走原本後端 OCR。
      if (_mode == ScanMode.electronicQr) {
        if (mounted) {
          setState(() => _hint = 'AI 正在定位 QR Code...');
        }

        final qrPayload = await YoloQrPipeline.instance.tryScanInvoiceQr(
          file,
          confidenceThreshold: 0.18,
          maxBoxes: 6,
        );

        if (!mounted) return;

        if (qrPayload != null && qrPayload.trim().isNotEmpty) {
          _playSound('done.mp3');
          HapticFeedback.heavyImpact();

          setState(() {
            _isLeftSuccess = true;
            _isRightSuccess = qrPayload.contains('[EINV_RIGHT_QR]');
            _hint = qrPayload.contains('[EINV_RIGHT_QR]')
                ? 'AI 找到雙邊 QR！處理中...'
                : 'AI 找到左邊 QR！處理中...';
          });

          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.of(context).pop(qrPayload);
          });
          return;
        }

        setState(() => _hint = 'YOLO 定位或 ML Kit 解碼失敗，改用 OCR 辨識...');
      }

      final modeStr = (_mode == ScanMode.traditionalOcr) ? 'traditional' : 'electronic';

      // 呼叫後端
      final rawText = await RemoteOcrService.visionOcr(file, mode: modeStr);

      if (!mounted) return;

      if (_isValidReceipt(rawText)) {
        // ★★★ 成功特效 ★★★
        _playSound('shutter.mp3');
        HapticFeedback.heavyImpact();
        setState(() => _isOcrSuccess = true);

        // 延遲跳轉
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) Navigator.of(context).pop(rawText);
        });
      } else {
        setState(() {
          _processing = false;
          _rawOcrResult = null;
          _hint = '沒看清楚捏，我們再試一次～';
        });

        if (!_processing && _mode == ScanMode.traditionalOcr) {
          _startTraditionalAutoShoot();
        }
      }

    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _hint = '連線失敗：Dio ${e.type}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _hint = '發生錯誤：$e';
      });
    }
  }

  Future<void> _resetScan() async {
    _energyController.stop();
    _eiFinalizeTimer?.cancel();

    setState(() {
      _qrValue = null;
      _rawOcrResult = null;
      _processing = false;
      _isLeftSuccess = false;
      _isRightSuccess = false;
      _isOcrSuccess = false;
      _eiLeftQr = null;
      _eiRightQr = null;
      _yoloAssistActive = false;
      _yoloModelReady = false;
      _yoloAssistMessage = null;
    });

    if (_mode == ScanMode.electronicQr) {
      await _enterElectronic();
    } else {
      await _enterTraditional(immediateShoot: false);
    }
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final isResult = _qrValue != null || _rawOcrResult != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('掃描發票'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),

          if (!isResult)
            Positioned.fill(child: _buildScanGuideWithEnergy()),

          if (!isResult && _mode == ScanMode.electronicQr && _yoloAssistActive)
            Positioned(
              top: 18,
              left: 16,
              right: 16,
              child: _buildYoloAssistBadge(),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(isResult),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_mode == ScanMode.electronicQr) {
      final controller = _qrController;
      if (controller == null) return const Center(child: CircularProgressIndicator());

      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          final scanRect = Rect.fromCenter(
            center: Offset(w / 2, h / 2),
            width: w * 0.6,
            height: 140,
          );

          return MobileScanner(
            key: ValueKey('qr_session_$_qrSession'),
            controller: controller,
            scanWindow: scanRect,
            onDetect: (capture) => _handleEInvoiceQrDetect(capture),
          );
        },
      );
    }

    if (_cam == null || !_camReady) return const Center(child: CircularProgressIndicator());
    return CameraPreview(_cam!);
  }

  // 貓耳框 + 能量條
  Widget _buildScanGuideWithEnergy() {
    final bool isQr = _mode == ScanMode.electronicQr;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;
        final double guideW = isQr ? screenW * 0.6 : screenW * 0.55;
        final double guideH = isQr ? 140 : screenH * 0.7;

        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: guideW,
              height: guideH,
              child: CustomPaint(
                painter: CatEarFramePainter(
                  isQr: isQr,
                  isLeftSuccess: _isLeftSuccess,
                  isRightSuccess: _isRightSuccess,
                  isOcrSuccess: _isOcrSuccess,
                ),
              ),
            ),

            Positioned(
              top: (screenH + guideH) / 2 + 16,
              width: guideW,
              height: 4,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _energyController,
                  builder: (context, child) {
                    return LinearProgressIndicator(
                      value: 1.0 - _energyController.value,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB39DDB)),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildYoloAssistBadge() {
    final text = _yoloAssistMessage ?? 'YOLO 輔助定位已啟動';

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF69F0AE).withOpacity(0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_yoloModelReady)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF69F0AE)),
              )
            else
              const Icon(Icons.center_focus_strong_rounded, color: Color(0xFF69F0AE), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 白色簡約風格 UI
  Widget _buildBottomPanel(bool isResult) {
    const primaryPurple = Color(0xFF6750A4);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // 第一排：提示文字 + 小圓形重新掃描按鈕
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                      _hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w500)
                  ),
                ),
                GestureDetector(
                  onTap: _processing ? null : _resetScan,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      shape: BoxShape.circle,
                      border: Border.all(color: primaryPurple.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.refresh, size: 20, color: primaryPurple),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (isResult) ...[
              _buildResultBox(),
              const SizedBox(height: 12),
            ],

            // 按鈕組
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _processing ? null : () async {
                      if (_mode == ScanMode.electronicQr) await _enterTraditional(immediateShoot: false);
                      else await _enterElectronic();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: primaryPurple,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Center(
                        child: Text(
                          _mode == ScanMode.electronicQr ? '切換：傳統發票' : '切換：電子發票',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Text('返回', style: TextStyle(color: Colors.black54)),
                  ),
                ),
              ],
            ),

            if (_mode == ScanMode.traditionalOcr && !isResult) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _processing ? null : _shootAndOcr,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('立即拍照', style: TextStyle(color: primaryPurple, decoration: TextDecoration.underline)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultBox() {
    final qr = _qrValue;
    final txt = _rawOcrResult;
    String content = '';
    if (qr != null) content = '【QR 內容】\n$qr';
    else if (txt != null) content = '【掃描結果】\n${txt.isEmpty ? "（未偵測到文字）" : txt}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(child: Text(content, style: const TextStyle(color: Colors.black87))),
    );
  }

// =========================
// E-Invoice QR（左右雙 QR）處理
// =========================

  bool _isGarbageQr(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;
    if (t == '**') return true;
    if (RegExp(r'^\*{6,}$').hasMatch(t)) return true;
    if (RegExp(r'^[\*\s:]+$').hasMatch(t)) return true;
    return false;
  }

  bool _looksLikeLeftEInvoiceQr(String s) {
    final t = s.trim();
    if (!RegExp(r'^[A-Z]{2}\d{8}').hasMatch(t)) return false;
    return t.length >= 77;
  }

  bool _looksLikeRightEInvoiceQr(String s) {
    final t = s.trim();
    if (!t.startsWith('**')) return false;
    return t.length > 2;
  }

  void _handleEInvoiceQrDetect(BarcodeCapture capture) {
    if (!mounted) return;
    if (_mode != ScanMode.electronicQr) return;
    if (_qrValue != null) return;
    if (_processing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    _yoloAssistTimer?.cancel();

    for (final b in barcodes) {
      final raw = (b.rawValue ?? '').trim();
      if (raw.isEmpty) continue;
      if (_isGarbageQr(raw)) continue;

      if (_looksLikeLeftEInvoiceQr(raw)) {
        if (_eiLeftQr == raw) continue;
        _eiLeftQr = raw;

        // ★★★ 觸發回饋 ★★★
        _playSound('done.mp3');
        HapticFeedback.lightImpact();
        setState(() {
          _isLeftSuccess = true;
          _hint = '左邊 OK！請把鏡頭往右邊移...';
        });

        _scheduleEiFinalizeIfReady();
        continue;
      }

      if (_looksLikeRightEInvoiceQr(raw)) {
        if (_eiRightQr == raw) continue;
        _eiRightQr = raw;

        // ★★★ 觸發回饋 ★★★
        _playSound('done.mp3');
        HapticFeedback.lightImpact();
        setState(() {
          _isRightSuccess = true;
          if ((_eiLeftQr ?? '').isEmpty) _hint = '右邊 OK！請把鏡頭往左邊移...';
          else _hint = '雙邊 OK！處理中...';
        });

        _scheduleEiFinalizeIfReady();
        continue;
      }
    }
  }

  void _scheduleEiFinalizeIfReady() {
    if ((_eiLeftQr ?? '').isEmpty) return;
    _eiFinalizeTimer?.cancel();
    _eiFinalizeTimer = Timer(_kEiFinalizeDelay, () {
      if (!mounted) return;
      if (_mode != ScanMode.electronicQr) return;
      if (_qrValue != null) return;
      _finalizeEInvoiceQr();
    });
  }

  void _finalizeEInvoiceQr() {
    _qrController?.stop();
    _eiFinalizeTimer?.cancel();
    _yoloAssistTimer?.cancel();
    _energyController.stop();

    final left = (_eiLeftQr ?? '').trim();
    final right = (_eiRightQr ?? '').trim();
    final payload = [
      '[MODE] E_INVOICE_QR',
      if (left.isNotEmpty) '[EINV_LEFT_QR] $left',
      if (right.isNotEmpty) '[EINV_RIGHT_QR] $right',
    ].join('\n');

    // ★★★ 成功特效：強制雙綠框 ★★★
    HapticFeedback.heavyImpact();
    setState(() {
      _isLeftSuccess = true;
      _isRightSuccess = true;
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.of(context).pop(payload);
    });
  }

// =========================
// OCR Logic (不變)
// =========================

  String _buildOcrPayload(String rawText, {required bool isTraditional}) {
    final raw = rawText.trim();
    final lines = _splitCleanLines(raw);

    final keylines = isTraditional
        ? _extractTraditionalKeylines(lines)
        : _extractElectronicKeylines(lines);

    final merchant = _extractMerchantHints(lines);
    final medicalContext = _detectMedicalContext(lines);

    final keywordTotal = _extractTotalFromKeyword(lines);
    final candidates = _extractTotalCandidates(lines);
    final total = keywordTotal ?? (candidates.isNotEmpty ? candidates.first : null);

    final modeTag = isTraditional ? 'TRADITIONAL_OCR' : 'E_INVOICE_OCR';

    final locationHints = (merchant['location_hints'] is List<String>)
        ? (merchant['location_hints'] as List<String>)
        : <String>[];

    return [
      '[MODE] $modeTag',
      if (merchant['brand'] != null) '[BRAND] ${merchant['brand']}',
      if (merchant['branch'] != null) '[BRANCH] ${merchant['branch']}',
      if (merchant['merchant_hint'] != null) '[MERCHANT_HINT] ${merchant['merchant_hint']}',
      if (locationHints.isNotEmpty) '[LOCATION_HINTS] ${locationHints.join(', ')}',
      '[MEDICAL_CONTEXT] ${medicalContext ? 'true' : 'false'}',
      if (total != null) '[TOTAL] $total',
      if (candidates.isNotEmpty) '[TOTAL_CANDIDATES] ${candidates.join(', ')}',
      if (keylines.isNotEmpty) '[KEYLINES]\n${keylines.map((e) => '- $e').join('\n')}',
      '[RAW_OCR]\n$raw',
    ].join('\n\n');
  }

  List<String> _splitCleanLines(String rawText) {
    final out = <String>[];
    final seen = <String>{};
    for (final ln in rawText.split('\n')) {
      final t = ln.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  List<String> _extractElectronicKeylines(List<String> lines) {
    final picks = <String>[];
    for (final ln in lines.take(8)) {
      if (picks.length >= 8) break;
      if (!_mostlyNumbers(ln)) picks.add(ln);
    }
    final kw = [
      '賣方', '買方', '統編', '統一編號',
      '總計', '合計', '應付', '總額', '總金額', '交易金額',
      '電話', 'TEL', '地址', '門市', '分店', '店',
      '電子發票', '發票',
    ];
    for (final ln in lines) {
      if (picks.length >= 14) break;
      if (kw.any((k) => ln.contains(k))) picks.add(ln);
    }
    return _uniqueLimit(picks, 14);
  }

  List<String> _extractTraditionalKeylines(List<String> lines) {
    final picks = <String>[];
    final phoneRe = RegExp(r'(?:\+?886[-\s]?)?0\d{1,2}[-\s]?\d{3,4}[-\s]?\d{3,4}');
    final taxIdRe = RegExp(r'\b\d{8}\b');
    final addrKw = ['縣', '市', '區', '鄉', '鎮', '里', '路', '街', '巷', '弄', '段', '號', '樓'];

    for (final ln in lines) {
      if (phoneRe.hasMatch(ln) || ln.contains('電話') || ln.toLowerCase().contains('tel')) picks.add(ln);
      if (ln.contains('統編') || ln.contains('統一編號') || taxIdRe.hasMatch(ln)) picks.add(ln);
      if (addrKw.any((k) => ln.contains(k))) picks.add(ln);
    }
    for (final ln in lines.take(10)) {
      if (picks.length >= 18) break;
      if (!_mostlyNumbers(ln)) picks.add(ln);
    }
    return _uniqueLimit(picks, 18);
  }

  bool _mostlyNumbers(String s) {
    final digits = RegExp(r'\d').allMatches(s).length;
    return s.isNotEmpty && (digits / s.length) > 0.6;
  }

  List<String> _uniqueLimit(List<String> items, int limit) {
    final out = <String>[];
    final seen = <String>{};
    for (final x in items) {
      final t = x.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) out.add(t);
      if (out.length >= limit) break;
    }
    return out;
  }

  Map<String, dynamic> _extractMerchantHints(List<String> lines) {
    const generic = [
      '電子發票證明聯','電子發票','統一發票','發票證明聯','證明聯','交易明細','明細',
      '載具','隨機碼','總計','合計','應付','賣方','買方','交易日期','發票號碼'
    ];
    String? brand;
    for (final ln in lines.take(10)) {
      final s = ln.replaceAll(' ', '');
      if (s.length < 2 || s.length > 14) continue;
      if (RegExp(r'\d').hasMatch(s)) continue;
      if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(s)) continue;
      if (generic.any((g) => s.contains(g))) continue;
      brand = ln.trim();
      break;
    }
    String? branch;
    for (final ln in lines) {
      final m = RegExp(r'(?:門市|分店|店名)\s*[:：]?\s*([^\s]{2,20})').firstMatch(ln);
      if (m != null) {
        final cand = (m.group(1) ?? '').trim();
        if (cand.isNotEmpty && !generic.any((g) => cand.contains(g))) {
          branch = cand;
          break;
        }
      }
      final m2 = RegExp(r'([\u4e00-\u9fffA-Za-z0-9]{2,18}店)').firstMatch(ln);
      if (m2 != null) {
        final cand = m2.group(1)!.trim();
        if (!generic.any((g) => cand.contains(g))) {
          branch = cand;
          break;
        }
      }
    }
    final locationHints = <String>[];
    const locWords = ['長庚','台大','榮總','醫院','分院','園區','校園','車站','捷運','服務區'];
    final joined = lines.join(' ');
    for (final w in locWords) {
      if (joined.contains(w)) locationHints.add(w);
    }
    String? merchantHint;
    if (brand != null && branch != null) merchantHint = '$brand $branch';
    else merchantHint = brand ?? branch;
    return {
      if (brand != null) 'brand': brand,
      if (branch != null) 'branch': branch,
      if (merchantHint != null) 'merchant_hint': merchantHint,
      if (locationHints.isNotEmpty) 'location_hints': locationHints,
    };
  }

  bool _detectMedicalContext(List<String> lines) {
    final joined = lines.join(' ');
    const strong = [
      '掛號','門診','看診','診所','藥局','健保','處方','醫師','急診','住院',
      '復健','檢查','檢驗','治療','藥品','藥費'
    ];
    return strong.any(joined.contains);
  }

  int? _extractTotalFromKeyword(List<String> lines) {
    final kw = RegExp(r'(總計|合計|應付|總額|總金額|交易金額)\s*[:：]?\s*\$?\s*([0-9]{1,6})');
    for (final ln in lines) {
      final noSpace = ln.replaceAll(' ', '');
      if (noSpace.contains('隨機碼') || noSpace.contains('統編') || noSpace.contains('發票號碼')) continue;
      final m = kw.firstMatch(noSpace);
      if (m != null) {
        final v = int.tryParse(m.group(2)!);
        if (v != null && v > 0) return v;
      }
    }
    return null;
  }

  List<int> _extractTotalCandidates(List<String> lines) {
    final nums = <int>{};
    final numRe = RegExp(r'\b\d{1,6}\b');
    for (final ln in lines) {
      final lower = ln.toLowerCase();
      if (ln.contains('發票號碼') || ln.contains('隨機碼') || ln.contains('統編') || ln.contains('電話') || lower.contains('tel')) continue;
      if (RegExp(r'\d{1,2}:\d{2}').hasMatch(ln)) continue;
      if (RegExp(r'\d{4}[-/]\d{2}[-/]\d{2}').hasMatch(ln)) continue;
      if (RegExp(r'\d{3}[-/]\d{2}[-/]\d{2}').hasMatch(ln)) continue;
      for (final m in numRe.allMatches(ln)) {
        final v = int.tryParse(m.group(0)!);
        if (v == null || v <= 0) continue;
        if (v >= 1900 && v <= 2099) continue;
        nums.add(v);
      }
    }
    final list = nums.toList()..sort((a, b) => b.compareTo(a));
    return list.take(12).toList();
  }
}

// ====== Painters ======

// 科技貓耳框 (效能極高)
class CatEarFramePainter extends CustomPainter {
  final bool isQr;
  final bool isLeftSuccess;
  final bool isRightSuccess;
  final bool isOcrSuccess;

  static const Color colorNormal = Colors.white;
  static const Color colorSuccess = Color(0xFF69F0AE); // 亮綠色

  CatEarFramePainter({
    required this.isQr,
    this.isLeftSuccess = false,
    this.isRightSuccess = false,
    this.isOcrSuccess = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (isQr) {
      final double gap = 15.0;
      final double boxSize = (size.width - gap) / 2;
      final double top = (size.height - boxSize) / 2;

      // 左框 (獨立變色)
      paint.color = isLeftSuccess ? colorSuccess : colorNormal;
      _drawCatBox(canvas, paint, Rect.fromLTWH(0, top, boxSize, boxSize));

      // 右框 (獨立變色)
      paint.color = isRightSuccess ? colorSuccess : colorNormal;
      _drawCatBox(canvas, paint, Rect.fromLTWH(boxSize + gap, top, boxSize, boxSize));
    } else {
      // 傳統發票長框
      paint.color = isOcrSuccess ? colorSuccess : colorNormal;
      final rect = Rect.fromLTWH(0, 0, size.width, size.height);
      _drawCatBox(canvas, paint, rect);

      // 虛線
      final Paint dashedPaint = Paint()
        ..color = paint.color.withOpacity(0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final double headerHeight = size.height * 0.18;
      double dashWidth = 5, dashSpace = 5, startX = 0;
      while (startX < size.width) {
        canvas.drawLine(Offset(startX, headerHeight), Offset(startX + dashWidth, headerHeight), dashedPaint);
        startX += dashWidth + dashSpace;
      }

      // ★★★ 加回「發票號碼對準上方」文字 ★★★
      final textPainter = TextPainter(
        text: TextSpan(
          text: '發票號碼對準上方',
          style: TextStyle(
            color: paint.color, // 文字顏色跟隨框框 (平時白，掃到變綠)
            fontSize: 14,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black)], // 加上陰影確保可見
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2, 12), // 置中，距離上方 12px
      );
    }
  }

  void _drawCatBox(Canvas canvas, Paint paint, Rect rect) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rrect, paint);

    final Path earPath = Path();
    final double earSize = 12.0;

    // 左耳
    earPath.moveTo(rect.left + 10, rect.top);
    earPath.lineTo(rect.left + 5, rect.top - earSize);
    earPath.lineTo(rect.left + 20, rect.top);

    // 右耳
    earPath.moveTo(rect.right - 20, rect.top);
    earPath.lineTo(rect.right - 5, rect.top - earSize);
    earPath.lineTo(rect.right - 10, rect.top);

    final Paint earFill = Paint()..color = paint.color;
    canvas.drawPath(earPath, earFill);
  }

  @override
  bool shouldRepaint(covariant CatEarFramePainter oldDelegate) {
    return oldDelegate.isQr != isQr ||
        oldDelegate.isLeftSuccess != isLeftSuccess ||
        oldDelegate.isRightSuccess != isRightSuccess ||
        oldDelegate.isOcrSuccess != isOcrSuccess;
  }
}