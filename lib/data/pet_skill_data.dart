import 'package:flutter/material.dart';

class PetSkillData {
  final String key;

  final String displayName;
  final String personality;

  final String passiveName;
  final String passiveDescription;

  final String activeName;
  final String activeDescription;

  final IconData skillIcon;

  const PetSkillData({
    required this.key,
    required this.displayName,
    required this.personality,
    required this.passiveName,
    required this.passiveDescription,
    required this.activeName,
    required this.activeDescription,
    required this.skillIcon,
  });
}


// =========================================================
// PAWPAY 寵物技能資料
// =========================================================

const Map<String, PetSkillData> petSkillData = {

  // -------------------------------------------------------
  // 狗狗
  // -------------------------------------------------------
  'dog': PetSkillData(
    key: 'dog',
    displayName: '狗狗',
    personality: '友善、活潑、忠心',
    passiveName: '幸運尾巴',
    passiveDescription:
    '第一次遇到負面機會事件時，金錢損失減少 50%。',
    activeName: '再試一次',
    activeDescription:
    '每局一次，可以重新擲骰一次。',
    skillIcon: Icons.casino_rounded,
  ),


  // -------------------------------------------------------
  // 貓咪
  // -------------------------------------------------------
  'cat': PetSkillData(
    key: 'cat',
    displayName: '貓咪',
    personality: '冷靜、優雅、好奇',
    passiveName: '優雅閃避',
    passiveDescription:
    '第一次踩到其他玩家的土地時，租金減少 50%。',
    activeName: '輕盈腳步',
    activeDescription:
    '每局一次，本回合可將移動點數減少 2 格，最低為 1 格。',
    skillIcon: Icons.auto_awesome_rounded,
  ),


  // -------------------------------------------------------
  // 鸚鵡
  // -------------------------------------------------------
  'parrot': PetSkillData(
    key: 'parrot',
    displayName: '鸚鵡',
    personality: '活潑、話多、消息靈通',
    passiveName: '消息靈通',
    passiveDescription:
    '踩到正面機會事件時，獲得的獎勵增加 15%。',
    activeName: '預言家',
    activeDescription:
    '每局一次，可以查看下一個機會格的位置。',
    skillIcon: Icons.visibility_rounded,
  ),


  // -------------------------------------------------------
  // 樹懶
  // -------------------------------------------------------
  'sloth': PetSkillData(
    key: 'sloth',
    displayName: '樹懶',
    personality: '慢吞吞、佛系、愛休息',
    passiveName: '慢慢來',
    passiveDescription:
    '進入監獄時，監獄回合數減少 1 回合。',
    activeName: '休息一下',
    activeDescription:
    '每局一次，跳過目前回合並獲得 \$1500。',
    skillIcon: Icons.bedtime_rounded,
  ),


  // -------------------------------------------------------
  // 狐狸
  // -------------------------------------------------------
  'fox': PetSkillData(
    key: 'fox',
    displayName: '狐狸',
    personality: '聰明、狡猾、精打細算',
    passiveName: '精明議價',
    passiveDescription:
    '第一次購買土地時，購地價格享有 8 折。',
    activeName: '討價還價',
    activeDescription:
    '每局一次，下一次購地或升級費用享有 7 折。',
    skillIcon: Icons.percent_rounded,
  ),


  // -------------------------------------------------------
  // 柴犬
  // -------------------------------------------------------
  'cute_dog': PetSkillData(
    key: 'cute_dog',
    displayName: '柴犬',
    personality: '衝動、直率、容易激動',
    passiveName: '熱血衝刺',
    passiveDescription:
    '擲出兩顆相同點數時，額外前進 1 格。',
    activeName: '暴衝！',
    activeDescription:
    '每局一次，立即額外前進 3 格。',
    skillIcon: Icons.bolt_rounded,
  ),


  // -------------------------------------------------------
  // 博美
  // -------------------------------------------------------
  'pomeranian': PetSkillData(
    key: 'pomeranian',
    displayName: '博美犬',
    personality: '愛漂亮、自信、喜歡被稱讚',
    passiveName: '明星光環',
    passiveDescription:
    '第一次收到其他玩家租金時，租金增加 25%。',
    activeName: '人氣爆棚',
    activeDescription:
    '每局一次，下一次收到的租金提高為 1.5 倍。',
    skillIcon: Icons.star_rounded,
  ),


  // -------------------------------------------------------
  // 佛系狗
  // -------------------------------------------------------
  'norm_dog': PetSkillData(
    key: 'norm_dog',
    displayName: '佛系狗',
    personality: '淡定、隨緣、不急不躁',
    passiveName: '看開一點',
    passiveDescription:
    '第一次遭遇金錢損失時，損失減少 50%。',
    activeName: '隨緣散步',
    activeDescription:
    '每局一次，本回合免疫一次負面機會事件。',
    skillIcon: Icons.self_improvement_rounded,
  ),


  // -------------------------------------------------------
  // 黏人狗
  // -------------------------------------------------------
  'wagging_dog': PetSkillData(
    key: 'wagging_dog',
    displayName: '黏人狗',
    personality: '超熱情、黏人、喜歡一起行動',
    passiveName: '一起玩！',
    passiveDescription:
    '每次經過起點時，額外獲得 \$500。',
    activeName: '跟我來！',
    activeDescription:
    '每局一次，讓一位電腦玩家額外前進 2 格。',
    skillIcon: Icons.group_rounded,
  ),


  // -------------------------------------------------------
  // 愛心貓
  // -------------------------------------------------------
  'lovely_cat': PetSkillData(
    key: 'lovely_cat',
    displayName: '愛心貓',
    personality: '溫柔、貼心、喜歡照顧人',
    passiveName: '暖心守護',
    passiveDescription:
    '資金第一次低於 \$5000 時，自動獲得 \$2000。',
    activeName: '治癒時間',
    activeDescription:
    '每局一次，立即獲得 \$2500。',
    skillIcon: Icons.favorite_rounded,
  ),


  // -------------------------------------------------------
  // 工作貓
  // -------------------------------------------------------
  'blue_cat': PetSkillData(
    key: 'blue_cat',
    displayName: '工作貓',
    personality: '認真、效率、做事俐落',
    passiveName: '效率管理',
    passiveDescription:
    '自己的土地升級費用永久享有 9 折。',
    activeName: '加班模式',
    activeDescription:
    '每局一次，免費升級一塊自己的土地。',
    skillIcon: Icons.work_rounded,
  ),


  // -------------------------------------------------------
  // 火箭貓
  // -------------------------------------------------------
  'rocket_cat': PetSkillData(
    key: 'rocket_cat',
    displayName: '火箭貓',
    personality: '愛幻想、冒險、充滿想像力',
    passiveName: '冒險加成',
    passiveDescription:
    '踩到正面機會事件時，獲得的獎勵增加 20%。',
    activeName: '發射！',
    activeDescription:
    '每局一次，直接前往下一個機會格。',
    skillIcon: Icons.rocket_launch_rounded,
  ),


  // -------------------------------------------------------
  // 等待貓
  // -------------------------------------------------------
  'loader_cat': PetSkillData(
    key: 'loader_cat',
    displayName: '等待貓',
    personality: '有耐心、慢條斯理、喜歡等待',
    passiveName: '耐心利息',
    passiveDescription:
    '遇到可購買土地但選擇不購買時，下回合獲得 \$800。',
    activeName: '等等再說',
    activeDescription:
    '每局一次，將一次租金延後到下個自己的回合再支付。',
    skillIcon: Icons.hourglass_bottom_rounded,
  ),


  // -------------------------------------------------------
  // 熊熊
  // -------------------------------------------------------
  'bear': PetSkillData(
    key: 'bear',
    displayName: '熊熊',
    personality: '愛吃、愛睡、懶洋洋',
    passiveName: '吃飽再走',
    passiveDescription:
    '每次經過起點時，額外獲得 \$1000。',
    activeName: '午睡時間',
    activeDescription:
    '每局一次，跳過目前回合並獲得 \$2000。',
    skillIcon: Icons.nightlight_round,
  ),


  // -------------------------------------------------------
  // 蜜蜂
  // -------------------------------------------------------
  'bee': PetSkillData(
    key: 'bee',
    displayName: '蜜蜂',
    personality: '勤奮、精準、工作狂',
    passiveName: '辛勤工作',
    passiveDescription:
    '每次經過起點時，額外獲得 \$1200。',
    activeName: '超時工作',
    activeDescription:
    '每局一次，可以立即再擲一次骰子。',
    skillIcon: Icons.handyman_rounded,
  ),


  // -------------------------------------------------------
  // 長頸鹿
  // -------------------------------------------------------
  'giraffe': PetSkillData(
    key: 'giraffe',
    displayName: '長頸鹿',
    personality: '看得遠、冷靜、喜歡思考',
    passiveName: '遠見',
    passiveDescription:
    '每回合擲骰前，可以預覽前方 3 格。',
    activeName: '看得更遠',
    activeDescription:
    '每局一次，可以自行選擇前進 1～6 格。',
    skillIcon: Icons.travel_explore_rounded,
  ),
};


// =========================================================
// Helper
// =========================================================

PetSkillData? getPetSkill(String? petKey) {
  if (petKey == null) return null;

  return petSkillData[petKey];
}