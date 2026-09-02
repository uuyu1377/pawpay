import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async'; // 必須導入 Timer

class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final TextEditingController _textController = TextEditingController();

  bool _isRecording = false;
  bool _isProcessing = false;
  String _statusText = "點擊麥克風開始說話";

  // --- 自動停止相關變數 ---
  Timer? _silenceTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  // 音量門檻 (dB)，數值越接近 0 越靈敏。通常 -40 到 -30 之間適合。
  final double _volumeThreshold = -30.0;

  final String _apiKey = "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";
  final String _apiUrl = "https://api.openai.com/v1/audio/transcriptions";

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    _textController.dispose();
    super.dispose();
  }

  // 1. 開始錄音與啟動音量監測
  Future<void> _startListening() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/audio_temp.m4a';

      await _audioRecorder.start(const RecordConfig(), path: path);

      setState(() {
        _isRecording = true;
        _statusText = "正在聆聽中... (3秒沒聲音將自動結束)";
        _textController.clear();
      });

      // 啟動音量監測
      _startSilenceDetection();
    } else {
      setState(() => _statusText = "需要麥克風權限");
    }
  }

  // 2. 核心：偵測音量變化
  void _startSilenceDetection() {
    _silenceTimer?.cancel();
    _amplitudeSub?.cancel();

    // 每 200 毫秒檢查一次音量
    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      // 如果目前音量大於門檻值 (代表有在說話)
      if (amp.current > _volumeThreshold) {
        _resetSilenceTimer(); // 重置 3 秒倒數
      }
    });

    // 初始化第一次倒數
    _resetSilenceTimer();
  }

  // 重置計時器
  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 3), () {
      if (_isRecording) {
        print("偵測到3秒沈默，自動停止錄音");
        _stopListening();
      }
    });
  }

  // 3. 停止錄音
  Future<void> _stopListening() async {
    // 停止錄音時，務必取消計時與監聽
    _silenceTimer?.cancel();
    _amplitudeSub?.cancel();

    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _statusText = "Whisper 正在分析中...";
    });

    if (path != null) {
      await _sendAudioToOpenAI(File(path));
    }
  }

  // 4. OpenAI API 傳送 (保持不變)
  Future<void> _sendAudioToOpenAI(File audioFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.headers.addAll({'Authorization': 'Bearer $_apiKey'});
      request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'zh';

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        setState(() {
          _textController.text = data['text'] ?? "";
          _statusText = "辨識完成";
        });
      } else {
        var error = json.decode(response.body);
        setState(() => _statusText = "API 錯誤: ${error['error']['message']}");
      }
    } catch (e) {
      setState(() => _statusText = "連線失敗: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _confirmAndReturn() {
    if (_textController.text.isEmpty) return;
    Navigator.pop(context, {
      'type': 'voice_input',
      'text': _textController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("智慧語音辨識", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          children: [
            const SizedBox(height: 40),

            if (_isProcessing)
              Column(
                children: [
                  const CircularProgressIndicator(color: Colors.blue),
                  const SizedBox(height: 12),
                  const Text("Whisper 正在分析中...",
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              )
            else
              Text(_statusText, style: TextStyle(color: Colors.grey[600], fontSize: 14)),

            const SizedBox(height: 20),
            TextField(
              controller: _textController,
              maxLines: 5,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                hintText: "辨識結果...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _confirmAndReturn,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black87),
                child: const Text("確認送出分析", style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: _isRecording ? _stopListening : _startListening,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: _isRecording ? Colors.red[50] : Colors.blue[50],
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: _isRecording ? Colors.red : Colors.blue,
                  size: 35,
                ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}