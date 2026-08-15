import 'package:flutter/material.dart';

class SettingsFaqPage extends StatelessWidget {
  const SettingsFaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_FaqItem>[
      const _FaqItem(
        question: '電子發票掃描流程是什麼？',
        answer: '系統會先用 MobileScanner 即時讀 QR Code。若幾秒內沒有成功，會啟動 YOLO 輔助提示並預先載入模型；若即時掃描仍失敗，才會拍照，用 YOLO 定位 QR 並交給 ML Kit 解碼裁切圖；若仍失敗，最後再走 OCR 備援。',
      ),
      const _FaqItem(
        question: 'YOLO 在掃描中負責什麼？',
        answer: 'YOLO 主要負責定位 QR Code，也就是判斷 QR 在畫面或照片中的位置；QR 內容仍需要由 QR 解碼器讀出。',
      ),
      const _FaqItem(
        question: 'CSV 上傳會做什麼？',
        answer: 'CSV 會送到後端進行批次分析，後端回傳分析結果後，App 會提示匯入是否成功。',
      ),
      const _FaqItem(
        question: 'AI 分類建議可以關掉嗎？',
        answer: '可以。關閉後仍會用 AI 協助抓金額、商家與備註，但分類會預設回「其他」讓使用者手動確認，避免自動套用錯分類。',
      ),
      const _FaqItem(
        question: '月底預算提醒怎麼運作？',
        answer: '新手設定會先讓使用者設定每月預算；之後也能在設定頁修改金額與提醒門檻。App 會在記帳後檢查本月支出比例，達到門檻時跳出提醒。',
      ),
      const _FaqItem(
        question: '每日記帳提醒是 App 內提醒嗎？',
        answer: '不是。開啟後會使用手機本機通知，到設定的時間跳出系統通知；若今天已經記帳，App 會把下一次提醒往後排。',
      ),
      const _FaqItem(
        question: '預設幣別會影響哪些地方？',
        answer: '會影響新增手動記帳、掃描/語音 AI 記帳、首頁統計金額、搜尋結果、確認視窗與 CSV 匯出的 currency 欄位。畫面金額會跟著目前預設幣別顯示。',
      ),
      const _FaqItem(
        question: '資料匯出存在哪裡？',
        answer: '匯出時會先產生 CSV，再跳出手機分享視窗。使用者可以選 LINE、Google Drive、Gmail 或其他 App 來儲存/傳送備份。',
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('常見問題'),
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              title: Text(
                item.question,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.answer,
                    style: const TextStyle(height: 1.6, color: Colors.black87),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}
