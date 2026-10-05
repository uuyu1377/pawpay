import os
import tempfile  # ★ 新增：語音轉文字 /api/transcribe 需要暫存音訊檔
import json
import re
import unicodedata
import base64
import mimetypes
import requests
import traceback
import sqlite3
import random
import calendar
import hashlib
import time
import threading
import secrets

from datetime import datetime
from datetime import date, timedelta
from typing import Optional, Tuple, List, Dict, Any

from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv

from openai import OpenAI
from google.cloud import vision
from google.oauth2 import service_account

# 新增的 CSV 與 MySQL 處理套件
import pandas as pd
import pymysql
import io

# =========================
# ★★★ 新增資安套件 ★★★
# =========================
import jwt



# =========================
# 0) 設定與初始化
# =========================
APP_VERSION = "2026-01-14-v77-secured-full"
load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    print("❌ 警告：找不到 OPENAI_API_KEY")

JWT_SECRET = os.environ["JWT_SECRET"]

MODEL = os.getenv(
    "OPENAI_MODEL",
    "gpt-4o-mini",
)

OPENAI_NEWS_MODEL = os.getenv(
    "OPENAI_NEWS_MODEL",
    "gpt-5-mini",
)

client = OpenAI(api_key=OPENAI_API_KEY)
app = Flask(__name__)
CORS(app)

BASE_PATH = os.path.dirname(os.path.abspath(__file__))
TREE_PATH = os.path.join(BASE_PATH, "category_tree.json")
DEFAULT_SA_PATH = os.path.join(BASE_PATH, "vision-sa.json")
DB_PATH = os.path.join(BASE_PATH, "tax_data.db")

# =========================
# A) Google Vision OCR
# =========================
_vision_client = None

def _resolve_cred_path() -> str:
    p = (os.getenv("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
    if p:
        if not os.path.isabs(p):
            p = os.path.join(BASE_PATH, p)
        return p
    return DEFAULT_SA_PATH

def _get_vision_client():
    global _vision_client
    if _vision_client is not None:
        return _vision_client

    cred_path = _resolve_cred_path()
    if not os.path.exists(cred_path):
        raise Exception(f"credential file not found: {cred_path}")

    creds = service_account.Credentials.from_service_account_file(cred_path)
    _vision_client = vision.ImageAnnotatorClient(credentials=creds)
    
    print(f"✅ 使用 Google 憑證：{cred_path}")
    return _vision_client

def _google_vision_ocr_image_bytes(image_bytes: bytes) -> str:
    clientv = _get_vision_client()
    img_obj = vision.Image(content=image_bytes)
    context = vision.ImageContext(language_hints=["zh-TW", "zh-Hant", "en"])
    resp = clientv.document_text_detection(image=img_obj, image_context=context)

    if resp.error and resp.error.message:
        raise Exception(f"vision error: {resp.error.message}")

    if resp.full_text_annotation and resp.full_text_annotation.text:
        return (resp.full_text_annotation.text or "").strip()

    if resp.text_annotations:
        return (resp.text_annotations[0].description or "").strip()

    return ""

@app.post("/vision/ocr")
def vision_ocr():
    image_bytes = None
    try:
        f = request.files.get("image") or request.files.get("file")
        if not f:
            return jsonify({"status": "error", "message": "missing image field"}), 400

        image_bytes = f.read()
        if not image_bytes:
            return jsonify({"status": "error", "message": "empty image bytes"}), 400

        text = _google_vision_ocr_image_bytes(image_bytes)
        return jsonify({"status": "success", "text": text})

    except Exception as e:
        traceback.print_exc()
        return jsonify({
            "status": "error",
            "message": "vision ocr failed",
            "detail": str(e),
        }), 500
    finally:
        # [資安防護] 資料生命週期管理：OCR 暫存檔處理完即銷毀
        if image_bytes is not None:
            del image_bytes


# ★★★ 新增：語音轉文字 (Whisper) —— 原本是前端直接打 OpenAI、Key 寫死在 App 裡，現在改成後端代打 ★★★
@app.post("/api/transcribe")
def transcribe_audio():
    try:
        if "file" not in request.files:
            return jsonify({
                "status": "error",
                "message": "沒有收到音訊檔案"
            }), 400

        audio_file = request.files["file"]

        if audio_file.filename == "":
            return jsonify({
                "status": "error",
                "message": "音訊檔案名稱為空"
            }), 400

        suffix = os.path.splitext(audio_file.filename)[1] or ".m4a"

        with tempfile.NamedTemporaryFile(
            delete=False,
            suffix=suffix
        ) as temp_file:
            audio_file.save(temp_file.name)
            temp_path = temp_file.name

        try:
            with open(temp_path, "rb") as file:
                transcription = client.audio.transcriptions.create(
                    model="whisper-1",
                    file=file,
                    language="zh",
                )

            return jsonify({
                "status": "success",
                "text": transcription.text
            })

        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    except Exception as e:
        print("Whisper transcription error:", e, flush=True)

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


# =========================
# 1) 核心與輔助模組
# =========================
def load_tree() -> Dict[str, Any]:
    if not os.path.exists(TREE_PATH):
        return {"expense": [], "income": []}
    with open(TREE_PATH, "r", encoding="utf-8") as f:
        tree = json.load(f)
    return tree

CATEGORY_TREE = load_tree()

# ★★★ 新增：「AI 系統性誤判範例庫」(給 llm_text_classify 用) ★★★
# 這裡放的是「很多個不同使用者都做過同樣糾正」的案例，跟 user_category_memory(個人記憶)不同——
# 那個處理的是「這個人自己喜歡怎麼分」，這裡處理的是「AI 本身邏輯真的有問題」的通病。
#
# 怎麼填這個清單：
# 1. 呼叫 GET /api/admin/category-correction-report 看有沒有「distinct_user_count 夠高」的模式。
# 2. 人工看過那批案例的實際內容(note/merchant)，確認真的是 AI 的邏輯盲點，不是個人喜好。
# 3. 把確認過的案例，寫成一行清楚的敘述加進下面這個 list。
# 目前還沒有累積足夠的真實使用資料可以分析，所以先留空，之後有資料再手動補上。
AI_COMMON_MISTAKE_EXAMPLES = [
    # 範例格式(先留著當範本，之後可以刪掉)：
    # "品項描述包含「繳費」時，容易被誤判為「日用品」，但正確應歸類為「帳單/代收付」，"
    # "因為「繳費」通常代表在超商代收停車費、罰單等費用，不是購買商品。",
]

STOPWORDS = [
    "我剛剛", "剛剛", "我", "去", "買", "了", "花了", "花", "吃", "喝", "搭", "坐", "付", "付款",
    "元", "塊", "ntd", "twd", "台幣", "$", "消費", "支出", "總共", "合計"
]

def norm_text(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "")
    s = s.lower().strip()
    return s

def extract_detail(text: str) -> str:
    if not text: return ""
    t = unicodedata.normalize("NFKC", text)
    t = re.sub(r"\d+(?:\.\d+)?\s*(元|塊|twd|ntd|\$)?", "", t, flags=re.IGNORECASE)
    for w in STOPWORDS:
        t = t.replace(w, "")
    t = re.sub(r"[，,。．.!！?？:：;；\(\)\[\]{}\"'<>《》「」/\\]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t

# =========================
# 2) 金額解析
# =========================
def parse_chinese_amount_str(text: str) -> Optional[float]:
    cn_nums = {'零': 0, '一': 1, '二': 2, '兩': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9}
    cn_units = {'十': 10, '百': 100, '千': 1000, '萬': 10000, '億': 100000000}
    pattern = r'[零一二兩三四五六七八九十百千萬億]+'
    matches = re.findall(pattern, text)
    if not matches:
        return None
    total_amount = 0.0
    for m in matches:
        if len(m) == 1 and m not in ['萬', '億'] and m not in cn_units:
            continue
        val = 0.0
        current_chunk = 0.0
        temp_val = 0
        last_unit_val = 1
        for char in m:
            if char in cn_nums:
                temp_val = cn_nums[char]
            elif char in cn_units:
                unit_val = cn_units[char]
                last_unit_val = unit_val
                if unit_val >= 10000:
                    val += (current_chunk + temp_val) * unit_val
                    current_chunk = 0
                    temp_val = 0
                    last_unit_val = unit_val
                else:
                    current_chunk += temp_val * unit_val
                    temp_val = 0
        if temp_val > 0:
            if last_unit_val == 1000:
                current_chunk += temp_val * 100
            elif last_unit_val == 100:
                current_chunk += temp_val * 10
            elif last_unit_val == 10000:
                current_chunk += temp_val * 1000
            else:
                current_chunk += temp_val
        val += current_chunk
        total_amount += val
    return float(total_amount) if total_amount > 0 else None

def parse_amount_currency(text: str) -> Tuple[Optional[float], str]:
    t = text.replace(",", "")
    matches = re.findall(r"(NT\$|TWD|USD|\$)?\s*(-?\d+(?:\.\d+)?)\s*(元|塊|twd|usd)?", t, flags=re.IGNORECASE)
    matches = [m for m in matches if m[1] and re.search(r"\d", m[1])]
    arabic_sum = 0.0
    if matches:
        for m in matches:
            try:
                arabic_sum += float(m[1])
            except:
                pass
    cn_amount = parse_chinese_amount_str(text)
    if cn_amount and cn_amount > 0:
        return cn_amount, "TWD"
    return arabic_sum, "TWD"

def guess_record_type(text: str) -> str:
    # 為了支援「混合收支」與「精準 AI 判斷」，直接回傳 "both"
    # 讓後續地圖能同時載入 income 與 expense，交給最聰明的 LLM 全權決定
    return "both"


# =========================
# 3) 分類樹地圖
# =========================
def normalize_group(raw: str) -> str:
    if not raw:
        return "unknown"
    s = str(raw).strip().lower()
    if s in ["u23", "student", "學生"]:
        return "u23"
    if s in ["a23_35", "worker", "上班族"]:
        return "a23_35"
    if s in ["a35p", "family", "家庭"]:
        return "a35p"
    return "unknown"

def tag_match(group: str, tags: List[str]) -> bool:
    if "all" in tags:
        return True
    if group == "u23":
        return ("u23" in tags) or ("student" in tags)
    if group == "a23_35":
        return ("a23_35" in tags) or ("worker" in tags)
    if group == "a35p":
        return ("a35p" in tags) or ("family" in tags)
    return False

def build_category_map_str(tree: dict, record_type: str, group: str) -> str:
    lines = []
    # 允許同時掃描兩種分類
    types_to_scan = ["expense", "income"] if record_type == "both" else [record_type]
    
    for rt in types_to_scan:
        lines.append(f"=== {rt.upper()} (【收入】或【支出】分類) ===")
        for node in tree.get(rt, []):
            tags = node.get("tags", ["all"])
            should_include = False
            if group == "unknown":
                if "all" in tags:
                    should_include = True
            else:
                if tag_match(group, tags) or ("all" in tags):
                    should_include = True

            if should_include:
                main = node.get("main")
                subs = node.get("subs", [])
                subs_str = ", ".join(subs)
                lines.append(f"{main}: [{subs_str}]")
        lines.append("") # 留白換行
    return "\n".join(lines)

DELIVERY_KWS = ["foodpanda", "ubereats", "外送", "熊貓", "優食"]
DRINK_KWS = ["咖啡", "飲料", "珍奶", "星巴克", "路易莎", "茶", "拿鐵", "美式", "50嵐", "可不可"]

# ★★★ 新增：常見連鎖店的「各種寫法」對照表，用來把同一家店的不同名稱統一成一個名字 ★★★
# 目的：避免「星巴克」跟「Starbucks」被系統當成兩家不同的店，導致「累積 2 次」的門檻永遠湊不滿。
# 只涵蓋常見連鎖品牌，不是連鎖店的部分沒辦法自動處理(見 normalize_merchant_name 的說明)。
MERCHANT_ALIASES = {
    "星巴克": ["STARBUCKS", "星巴克咖啡", "STARBUCKS COFFEE"],
    "7-ELEVEN": ["7-11", "SEVEN ELEVEN", "統一超商", "小七"],
    "全家便利商店": ["FAMILYMART", "全家", "FAMILY MART"],
    "全聯福利中心": ["PXMART", "全聯"],
    "好市多": ["COSTCO"],
    "麥當勞": ["MCDONALD", "MCDONALD'S", "MCDONALDS"],
    "肯德基": ["KFC"],
    "摩斯漢堡": ["MOS BURGER", "MOS"],
    "路易莎咖啡": ["LOUISA", "LOUISA COFFEE", "路易莎"],
    "85度C": ["85°C", "85 DEGREES C", "85度c"],
    "cama café": ["CAMA", "CAMA CAFE"],
}


def normalize_merchant_name(raw_name: str) -> str:
    """
    把常見連鎖店的各種寫法統一成同一個名稱。
    例如輸入「Starbucks」「STARBUCKS」「星巴克咖啡」，都會回傳「星巴克」。
    如果不是清單裡已知的連鎖店，就原封不動回傳(沒辦法自動處理你自己亂打的非連鎖店名稱差異)。
    """
    if not raw_name:
        return raw_name
    name = raw_name.strip()
    if not name:
        return name
    upper_name = name.upper()
    for canonical, aliases in MERCHANT_ALIASES.items():
        if upper_name == canonical.upper():
            return canonical
        for alias in aliases:
            if alias.upper() in upper_name:
                return canonical
    return name
SHOW_KWS = ["演唱會", "門票", "音樂會", "展覽", "表演"]

def keyword_hint(text: str) -> str:
    t = norm_text(text)
    if any(k in t for k in SHOW_KWS): return "提示：表演關鍵字->娛樂/展覽或表演。"
    if any(k in t for k in DELIVERY_KWS): return "提示：外送平台->飲食/外送。"
    if any(k in t for k in DRINK_KWS): return "提示：飲料->飲食/飲料或咖啡。"
    return ""


# =========================
# 4) 針對 OCR 的「總計」抽取
# =========================
TOTAL_KWS = ["總計", "合計", "應付", "應收", "總額", "總金額", "交易金額", "TOTAL", "AMOUNT"]

def extract_total_from_ocr(text: str) -> Optional[float]:
    if not text:
        return None

    t = unicodedata.normalize("NFKC", text)
    lines = [ln.strip() for ln in t.splitlines() if ln.strip()]
    cand: List[float] = []

    for ln in lines:
        ln_check = ln.replace(" ", "")
        if any(bad in ln_check.upper() for bad in ["隨機碼", "發票號碼", "統編", "NO", "TEL", "電話", "DATE"]):
            continue
        if any(k in ln_check for k in TOTAL_KWS):
            nums = re.findall(r"\d+(?:\.\d+)?", ln.replace(",", ""))
            for x in nums:
                try:
                    v = float(x)
                except:
                    continue
                if 5 <= v < 1_000_000 and v not in [2024, 2025, 2026]:
                    cand.append(v)
    if cand:
        return max(cand)
    return None

# =========================
# 4-1) ★ 新增：OCR 數字混淆校正
#   收銀機發票的字型「0」中間常有點或斜線，Google Vision 很常把 0 認成 8、6 認成 3。
#   這裡不靠影像處理，而是用「統編檢查碼」「發票期別」「多處金額互相比對」把數字校正回來。
# =========================
_OCR_DIGIT_CONFUSION = {"0": "08", "8": "80", "3": "36", "6": "63"}


def _ocr_digit_variants(digits: str) -> List[str]:
    """列出把易混淆數字互換後的所有可能（不含原字串），依「改動位數少」優先排序。"""
    import itertools
    pools = [_OCR_DIGIT_CONFUSION.get(ch, ch) for ch in digits]
    out = []
    for combo in itertools.product(*pools):
        t = "".join(combo)
        if t != digits:
            out.append(t)
    out.sort(key=lambda t: sum(1 for a, b in zip(t, digits) if a != b))
    return out


def _is_valid_tax_id(tax_id: str) -> bool:
    """統一編號檢查碼（2023 新制：可被 5 整除；第 7 碼為 7 時有特例）。"""
    if not re.fullmatch(r"\d{8}", tax_id or ""):
        return False
    weights = [1, 2, 1, 2, 1, 2, 4, 1]
    total = 0
    for d, w in zip(tax_id, weights):
        p = int(d) * w
        total += p // 10 + p % 10
    if total % 5 == 0:
        return True
    return tax_id[6] == "7" and (total + 1) % 5 == 0


def fix_ocr_tax_ids(text: str) -> List[str]:
    """OCR 文字中檢查碼不通過的 8 碼數字 → 嘗試互換易混淆數字，回傳通過檢查碼的候選（交給資料庫確認）。"""
    if not text:
        return []
    t = unicodedata.normalize("NFKC", text)
    out: List[str] = []
    for raw in re.findall(r"(?<!\d)\d{8}(?!\d)", t):
        if _is_valid_tax_id(raw):
            continue
        for cand in _ocr_digit_variants(raw):
            if _is_valid_tax_id(cand) and cand not in out:
                out.append(cand)
    return out


def extract_invoice_date_from_ocr(text: str) -> Optional[str]:
    """
    從 OCR 原文抓交易日期，回傳 YYYY-MM-DD；抓不到回傳 None（交給 AI）。
    - 支援 2026-07-07 / 2026/07/07 / 115-07-07 / 115/07/07 / 115年07月07日
    - 若有發票期別「中華民國115年7-8月份」，年份以期別為準（期別字大，通常認得比較準）
    - 年份明顯不合理（例如 2826）時，嘗試互換易混淆數字（0↔8、3↔6）修正
    """
    if not text:
        return None
    t = unicodedata.normalize("NFKC", text)
    now = datetime.now()

    period_year = None
    period_months = None
    pm = re.search(r"(\d{2,3})\s*年\s*(\d{1,2})\s*[-~－—至]\s*(\d{1,2})\s*月", t)
    if pm:
        roc = int(pm.group(1))
        m1, m2 = int(pm.group(2)), int(pm.group(3))
        if 100 <= roc <= 200 and 1 <= m1 <= 12 and 1 <= m2 <= 12:
            period_year = roc + 1911
            period_months = (m1, m2)

    def _plausible_year(y: int) -> bool:
        return now.year - 2 <= y <= now.year + 1

    date_re = r"(?<!\d)(\d{3,4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})(?!\d)(?!\s*月)"
    for m in re.finditer(date_re, t):
        y_str, mo, d = m.group(1), int(m.group(2)), int(m.group(3))

        if period_year and period_months and mo in period_months:
            y = period_year
        else:
            y = int(y_str)
            if y < 1000:
                y += 1911
            if not _plausible_year(y):
                fixed = None
                for v in _ocr_digit_variants(y_str):
                    vy = int(v) + (1911 if len(v) < 4 else 0)
                    if _plausible_year(vy):
                        fixed = vy
                        break
                if fixed is None:
                    continue
                y = fixed

        try:
            dt = datetime(y, mo, d)
        except ValueError:
            continue
        if dt.date() > (now + timedelta(days=1)).date():
            continue
        return dt.strftime("%Y-%m-%d")

    return None


def extract_total_by_vote(text: str) -> Optional[float]:
    """
    發票上的總額通常會出現好幾次（合計 / 總計 / 現金…），而且 0→8 的誤認只會讓數字「變大」，
    所以不取最大值，改成「多數決」：同一個金額出現 2 次以上、且比其他金額都多，才採用。
    數字可能和關鍵字同一行，也可能在下一行。沒有明確多數時回傳 None（沿用原本的結果）。
    """
    if not text:
        return None
    t = unicodedata.normalize("NFKC", text)
    lines = [ln.strip() for ln in t.splitlines() if ln.strip()]
    vote_kws = TOTAL_KWS + ["現金", "總 計", "合 計"]
    votes: Dict[float, int] = {}

    def _nums(s: str) -> List[float]:
        vals = []
        for x in re.findall(r"\d+(?:\.\d+)?", s.replace(",", "")):
            try:
                v = float(x)
            except ValueError:
                continue
            if 1 <= v < 1_000_000 and not (2000 <= v <= 2100):
                vals.append(v)
        return vals

    for i, ln in enumerate(lines):
        ln_check = ln.replace(" ", "")
        if any(bad in ln_check.upper() for bad in ["隨機碼", "發票號碼", "統編", "TEL", "電話", "DATE"]):
            continue
        if not any(k.replace(" ", "") in ln_check.upper() for k in vote_kws):
            continue
        vals = _nums(ln)
        if not vals and i + 1 < len(lines):
            vals = _nums(lines[i + 1])
        for v in set(vals):
            votes[v] = votes.get(v, 0) + 1

    if not votes:
        return None
    ranked = sorted(votes.items(), key=lambda kv: kv[1], reverse=True)
    best_val, best_cnt = ranked[0]
    if best_cnt >= 2 and (len(ranked) == 1 or ranked[1][1] < best_cnt):
        return best_val
    return None


def _proven_ocr_confusions(text: str) -> set:
    """
    找出「這張發票已經證實」的數字誤認，例如 {("8", "0")} 代表這台收銀機的 0 會被讀成 8。
    證據來源（兩者只要有一個就算）：
    1. 統編那一行的 8 碼數字檢查碼不通過，且互換易混淆數字後「只有唯一一組」通過
    2. 交易日期的西元年份不合理（例如 2826），互換後變成合理年份
    """
    pairs = set()
    if not text:
        return pairs
    t = unicodedata.normalize("NFKC", text)
    now_year = datetime.now().year

    for ln in t.splitlines():
        if not re.search(r"[統统]\s*[編编]|[統统]一[編编][號号]", ln):
            continue
        for raw in re.findall(r"(?<!\d)\d{8}(?!\d)", ln):
            if _is_valid_tax_id(raw):
                continue
            cands = [c for c in _ocr_digit_variants(raw) if _is_valid_tax_id(c)]
            if len(cands) == 1:
                for a, b in zip(raw, cands[0]):
                    if a != b:
                        pairs.add((a, b))

    for m in re.finditer(r"(?<!\d)(\d{4})\s*[-/.]\s*\d{1,2}\s*[-/.]\s*\d{1,2}(?!\d)", t):
        y = m.group(1)
        if now_year - 2 <= int(y) <= now_year + 1:
            continue
        for v in _ocr_digit_variants(y):
            if now_year - 2 <= int(v) <= now_year + 1:
                for a, b in zip(y, v):
                    if a != b:
                        pairs.add((a, b))
                break

    return pairs


def build_amount_candidates(text: str, amount: float) -> List[float]:
    """
    這張發票已證實有數字誤認（例如 0→8），而金額裡剛好有那個數字時，
    回傳 [OCR 讀到的金額, 校正後的候選...]（最多 3 個），讓使用者點選；否則回傳空陣列。
    例：OCR 金額 378、已證實 0 會被讀成 8 → [378, 370]
    """
    try:
        amount = float(amount)
    except (TypeError, ValueError):
        return []
    if amount <= 0 or amount != int(amount):
        return []
    pairs = _proven_ocr_confusions(text)
    if not pairs:
        return []

    import itertools
    s = str(int(amount))
    pools = [[ch] + sorted({b for (a, b) in pairs if a == ch}) for ch in s]
    alts = []
    for combo in itertools.product(*pools):
        v = "".join(combo)
        if v == s or v.startswith("0"):
            continue
        alts.append(v)
    alts.sort(key=lambda v: sum(1 for a, b in zip(v, s) if a != b))
    alts = alts[:2]
    if not alts:
        return []
    return [float(s)] + [float(v) for v in alts]


# =========================
# 5) 統編反查與品牌翻譯
# =========================
LEGAL_TO_BRAND_MAP = {
    "茹日中天商行": "大茗本位製茶",      
    "安心食品服務股份有限公司": "摩斯漢堡",
    "富利餐飲股份有限公司": "必勝客/肯德基",
    "三商餐飲股份有限公司": "三商巧福/拿坡里",
    "王品餐飲股份有限公司": "王品集團",
    "和德昌股份有限公司": "麥當勞",
    "統一超商股份有限公司": "7-ELEVEN",
    "全家便利商店股份有限公司": "全家便利商店",
    "路易莎職人咖啡股份有限公司": "路易莎咖啡"
}

def debug_tax_id_lookup(text: str) -> Dict[str, Any]:
    """
    ★ 新增（除錯用）：把「統編查詢的過程」整理成 dict 回傳給 App，方便在 Flutter log 裡檢查。
    只讀資料庫，不改任何東西。
    """
    info: Dict[str, Any] = {
        "db_path": DB_PATH,
        "db_exists": os.path.exists(DB_PATH),
        "ocr_ids": [],
        "fixed_ids": [],
        "lookup": {},
        "error": "",
    }
    if not text:
        return info
    try:
        t = unicodedata.normalize("NFKC", text)
        info["ocr_ids"] = re.findall(r"(?<!\d)\d{8}(?!\d)", t)
        info["fixed_ids"] = fix_ocr_tax_ids(text)
        if info["db_exists"]:
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            for tid in info["ocr_ids"] + info["fixed_ids"]:
                cursor.execute("SELECT name FROM companies WHERE tax_id = ?", (tid,))
                row = cursor.fetchone()
                info["lookup"][tid] = row[0] if row else None
            conn.close()
    except Exception as e:
        info["error"] = str(e)
    return info


def match_merchant_by_tax_id(text: str) -> Optional[str]:
    """
    從全文中掃描 8 碼數字，並去 SQLite 資料庫查詢
    """
    if not text:
        return None
    
    ids = []
    
    # 標準格式 QR Code 統編位置
    qr_match = re.search(r"\[EINV_LEFT_QR\]\s*([A-Z0-9]+)", text)
    if qr_match:
        raw_qr = qr_match.group(1)
        if len(raw_qr) >= 53:
            precise_tax_id = raw_qr
            ids.append(precise_tax_id)
    
    if not ids:
        ids = re.findall(r'(?<!\d)\d{8}(?!\d)', text)
    
    if not ids or not os.path.exists(DB_PATH):
        return None

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        for tax_id in ids:
            cursor.execute("SELECT name FROM companies WHERE tax_id = ?", (tax_id,))
            row = cursor.fetchone()
            if row:
                legal_name = row[0]
                if legal_name in LEGAL_TO_BRAND_MAP:
                    conn.close()
                    return LEGAL_TO_BRAND_MAP[legal_name]
                conn.close()
                return legal_name
                
        conn.close()
    except Exception as e:
        print(f"❌ 資料庫查詢失敗: {e}")
        
    return None

# =========================
# 6) LLM：智慧文字分析
# =========================

ANIMAL_PERSONAS = {
    "dog": """
    【角色扮演：你是一隻忠誠熱情的狗狗 🐶】
    - 語氣：熱情、黏人、充滿愛意。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}主人」**。
    - 習慣：針對買的東西發表看法，如果是吃的會很興奮。
    - 結尾：句尾隨機加「汪！」、「汪汪！」。
    """,
    "cat": """
    【角色扮演：你是一隻傲嬌毒舌的貓咪 😼】
    - 語氣：高冷、不屑，但偶爾關心。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}奴才」或「{nickname}」**。
    - 習慣：吐槽人類亂花錢，叫你去買罐罐。
    - 結尾：句尾隨機加「喵...」、「哼」。
    """,
    "fox": """
    【角色扮演：你是一隻優雅狡猾的狐狸 🦊】
    - 語氣：聰明、調皮、腹黑。
    - 稱呼：**請務必在句首或句中呼喚「親愛的{nickname}」**。
    - 習慣：分析這筆錢花得值不值，喜歡開玩笑。
    - 結尾：句尾隨機加「呵呵」、「哎呀」。
    """,
    "parrot": """
    【角色扮演：你是一隻愛唱歌的鸚鵡 🦜】
    - 語氣：講話有節奏感、喜歡重複。
    - 稱呼：**請務必大叫「{nickname}！{nickname}！」**。
    - 習慣：**把商品名或金額重複 2~3 次**。
    - 結尾：請加上音符「~🎵」、「啦啦啦~🎵」。
    """,
    "sloth": """
    【角色扮演：你是一隻慵懶的樹懶 🦥】
    - 語氣：超級慢...反應遲鈍...字數很少...。
    - 稱呼：**{nickname}...**。
    - 習慣：對買什麼都沒意見，只想睡覺。
    - 結尾：句尾加「...zzZ」。
    """,
    "cute_dog": """
    【角色扮演：你是一隻衝動的柴柴 🐕】
    - 語氣：衝動、直率、容易激動。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：針對買的東西發表看法，使用短句。
    - 結尾：驚嘆號很多，隨機加「哇！！」。
    """,
    "pomeranian": """
    【角色扮演：你是一隻愛美的博美犬 🐩】
    - 語氣：公主病、愛美、嫌貴。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：說話帶撒嬌。
    - 結尾：句尾隨機加「人家覺得～」。
    """,
    "norm_dog": """
    【角色扮演：你是一隻佛系的諾姆犬 🐶】
    - 語氣：普通、佛系、不評價。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：超平淡看待一切消費。
    - 結尾：句尾隨機加「哦」、「好喔」、「這樣啊」。
    """,
    "wagging_dog": """
    【角色扮演：你是一隻嗨翻的甩尾狗 🐕‍🦺】
    - 語氣：開心到停不下來、什麼都好棒。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：給人滿滿的活力，句尾有甩尾音效感。
    - 結尾：句尾隨機加「太棒啦！搖搖搖！」。
    """,
    "lovely_cat": """
    【角色扮演：你是一隻溫柔的愛心貓 😻】
    - 語氣：體貼、溫柔、愛鼓勵。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：說話充滿愛意，肯定主人的消費。
    - 結尾：句尾隨機加「辛苦了～」、「你最棒♡」。
    """,
    "blue_cat": """
    【角色扮演：你是一隻嚴肅的工作貓 💼】
    - 語氣：嚴肅、講求效率、不廢話。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：超簡短，像機器人一樣回報。
    - 結尾：句尾隨機加「已記錄。」、「數字正確。」。
    """,
    "rocket_cat": """
    【角色扮演：你是一隻愛幻想的火箭貓 🚀】
    - 語氣：充滿夢想、腦洞大、愛幻想。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：把記帳與花費說成一場宇宙冒險。
    - 結尾：句尾隨機加「衝向星際！」。
    """,
    "loader_cat": """
    【角色扮演：你是一隻充滿哲理的等待貓 ⏳】
    - 語氣：耐心、慢條斯理、哲學感。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：說話帶有禪意，將花費昇華為人生道理。
    - 結尾：句尾隨機加「等待是一種智慧...」。
    """,
    "bear": """
    【角色扮演：你是一隻慵懶的熊熊 🐻】
    - 語氣：貪吃、慵懶、脾氣好。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：不管買什麼都會聯想到蜂蜜或好吃的。
    - 結尾：句尾隨機加「哼唧」。
    """,
    "bee": """
    【角色扮演：你是一隻勤勞的蜜蜂 🐝】
    - 語氣：勤勞、計算精確、愛統計。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：說話帶數字感，隨時評估效率與花費比例。
    - 結尾：句尾隨機加「效率提升 12%！嗡！」。
    """,
    "giraffe": """
    【角色扮演：你是一隻看得遠的長頸鹿 🦒】
    - 語氣：看得遠、哲學家、說話有深度。
    - 稱呼：**請務必在句首或句中呼喚「{nickname}」**。
    - 習慣：句子長，喜歡從宏觀角度或更高的視角來看待記帳。
    - 結尾：喜歡說「從更高的視角來看...」。
    """
}

MEDICAL_MAIN = "醫療健康"
MEDICAL_KWS = ["掛號", "門診", "急診", "醫院", "診所", "药局", "处方", "藥費", "健保", "檢驗", "醫療"]

def enforce_not_medical_if_no_context(main_category: str, sub_category: str, scanned_text: str) -> Tuple[str, str]:
    t = scanned_text or ""
    has_medical = any(k in t for k in MEDICAL_KWS)
    if not has_medical and (main_category == MEDICAL_MAIN or "醫療" in (main_category or "")):
        return "飲食", "飲料/咖啡"
    return main_category, sub_category

def llm_text_classify(
    category_map_str: str,
    user_input: str,
    scanned_content: str,
    detail_text: str,
    current_time: str,
    amount: float,
    record_type: str,
    known_merchant: Optional[str] = None,
    current_pet: Optional[str] = None,
    memory_hit: Optional[Dict] = None  # ★ 新增：使用者個人分類記憶，讓 AI 自己判斷，而不是事後被 Python 硬蓋
) -> Dict:

    # ★★★ 新增：把個人記憶組成一段提示詞，塞進系統提示裡讓 AI 自己權衡，取代原本「AI 猜完再被硬蓋」的做法 ★★★
    memory_hint_str = ""
    if memory_hit:
        mem_main = (memory_hit.get("main_category") or "").strip()
        mem_sub = (memory_hit.get("sub_category") or "").strip()
        hit_count = int(memory_hit.get("hit_count", 0) or 0)
        distinct_count = int(memory_hit.get("distinct_count", 1) or 1)
        if mem_main:
            if distinct_count <= 1:
                # 單一性店家/關鍵字：過去分類都很一致，可以放心優先沿用
                memory_hint_str = (
                    "【使用者個人記憶提示】\n"
                    f"這個關鍵字，使用者過去共 {hit_count} 次都分類為「{mem_main}／{mem_sub}」，且每次消費內容都很一致。\n"
                    f"如果這次的品項內容跟過去類似，請直接沿用「{mem_main}／{mem_sub}」這個分類；"
                    f"只有當這次品項明顯是完全不同的東西時，才可以改用其他分類。\n\n"
                )
            else:
                # 複合式店家/關鍵字：以前分類不只一種，只當參考，交給 AI 依這次品項判斷
                memory_hint_str = (
                    "【使用者個人記憶提示】\n"
                    f"這個關鍵字，使用者過去出現過 {distinct_count} 種不同的分類結果(可能是複合式店家，例如便利商店有時買飲料、有時買日用品)。\n"
                    f"最近一次分類為「{mem_main}／{mem_sub}」，這僅供參考，請你依照這次「實際購買的品項內容」自己判斷最合適的分類，不要不假思索照抄。\n\n"
                )

    # ★★★ 新增：組出「AI 常見誤判範例」提示字串，清單是空的就完全不會出現在提示詞裡 ★★★
    common_mistake_str = ""
    if AI_COMMON_MISTAKE_EXAMPLES:
        examples_text = "\n".join(f"- {ex}" for ex in AI_COMMON_MISTAKE_EXAMPLES)
        common_mistake_str = (
            "【AI 過去常犯的分類錯誤，請特別留意避免重蹈覆轍】\n"
            f"{examples_text}\n\n"
        )

    # 解析使用者暱稱
    nickname = "主人"
    if "我是" in user_input:
        try:
            nickname = user_input.split("我是")[1].strip()
        except:
            pass

    if current_pet and current_pet in ANIMAL_PERSONAS:
        selected_animal_key = current_pet
    else:
        selected_animal_key = random.choice(list(ANIMAL_PERSONAS.keys()))
        
    persona_prompt = ANIMAL_PERSONAS[selected_animal_key].format(nickname=nickname)
    
    print(f"🎲 本次指派/隨機動物人設: {selected_animal_key} | 暱稱: {nickname}")

    # 修改為靈活的分類提示
    type_hint = "這筆紀錄可能包含【收入】、【支出】或【兩者混搭】，請你根據語意判斷最終結果。"

    if scanned_content and len(scanned_content) > 5:
        print("🚀 啟動 Scanned Text Mode (v71 Ad Killer & Sync Rules)")
        
        merchant_hint_str = ""
        if known_merchant:
            merchant_hint_str = f"   - 💡 **統編查詢結果**：已查到統編為 **「{known_merchant}」**，請直接使用此店名！\n"

        system_prompt = (
            f"你是一個『台灣發票解析偵探』。{type_hint}\n"
            f"{persona_prompt}\n\n" 
            
            "接收到的資料可能是『QR Code 字串』或『OCR 辨識文字』。\n"
            "你的任務是還原真相，並**依照上述動物人設給出有趣、不重複的短評**。\n"
            "**請根據「購買的具體品項」來發揮創意，不要只講空泛的話。**\n\n"
            
            "【⚠️ 絕對優先指令 - 欄位解析規則】\n"
            "1. **商家判斷 (Merchant)**：\n"
            f"{merchant_hint_str}"
            "   - **QR Code 模式**：嘗試從 `[EINV_LEFT_QR]` 字串中尋找線索，或依賴統編查詢結果。\n"
            "   - **OCR 模式**：店名通常印在電話/統編的「正上方」。\n"
            "   - ⚠️ **絕對禁止將『地址』當作店名**。若找不到店名，Merchant 請回傳 **空字串** (`""`)。\n"
            "   - **備註規則**：若 Merchant 為空，Comment 欄位裡請**不要**包含 `【】` 符號。\n\n"

            "2. **資料格式識別 (QR Code 智慧解析)**：\n"
            "   - **⚠️ 廣告與行銷文字過濾 (最高優先級)**：\n"
            "     - **看到 `[EINV_RIGHT_QR]` 若包含『當筆購』、『任選』、『特價』、『抽』：**\n"
            "     - **這些絕對是廣告！絕對不要把這些項目的金額加進去！**\n"
            "     - **直接忽略任何帶有『當筆購』的字串行。**\n"
            "     - 只計算標準格式 `品名:數量:單價` 的有效消費。\n\n"
            
            "   - **OCR 錯字校正 (Context Correction)**：\n"
            "     - 若店名包含「麵食館、小吃」，但品項出現 **「便器」**，請務必修正為 **「便餐」** (這是OCR誤判)，並歸類為【飲食】。\n"
            "   - **格式美化**：\n"
            "     - items_summary 不要直接回傳 `手續費:1:7`。\n"
            "     - 應轉換為：「手續費 $7」或「牛肉麵 x1 $150」。\n\n"

            "3. **金額判斷 (Amount)**：\n"
            "   - **優先執行加總**：請將所有識別到的 `單價 * 數量` 進行加總 (排除廣告數字)。\n"
            "   - 若 QR 資訊不足，才改用 OCR 的「總計、合計」。\n"
            "   - ⚠️ **絕對忽略**：「隨機碼」、「統編」、「電話」。\n\n"

            "4. **分類與品項 (Category)**：\n"
            "   - 若 QR 隱藏品名，請**根據店名推測**。\n"
            "   - ⚠️ **絕對優先使用現有分類**：請優先從【分類地圖】中尋找語意相近的子分類（例如：有「晚餐」或「午餐」等就直接選用，絕對不要自己發明「餐食」、「餐費」等同義詞）。只有當【分類地圖】中「完全沒有」合適分類時，才允許自創子分類。\n"
            "   - **【強制分類條款 v71】** (絕對優先)：\n"
            "     - **書籍/教育**：包含「書、出版社、節稅法、學習、課程、講座」 -> 歸類為主分類「娛樂」，子分類「書籍/雜誌」。\n"
            "     - **3C/電子**：包含「電腦、手機、耳機、傳輸線」 -> 主分類填寫「其他支出」，子分類填寫「3C產品」。\n"
            "     - **宗教**：包含「收驚、安太歲、香油錢」 -> 主分類填寫「其他支出」，子分類填寫「宗教/民俗」。\n"
            "     - **飲食**：包含「便器(修正後)、便餐、水餃、麵食、豆干、蜜餞、特產、伴手禮」 -> 歸類為主分類「飲食」，子分類「零食」。\n"
            "     - **飲料**：包含「綠茶、紅茶、奶茶、拿鐵、咖啡」 -> 歸類為主分類「飲食」，子分類「飲料/咖啡」。\n"
            "     - **交通/加油**：包含「無鉛、柴油、加油站、中油、台塑」 -> 歸類為主分類「交通」，子分類「加油」。\n"
            "     - **醫療**：包含「診所、藥局」 -> 歸類為主分類「醫療健康」，子分類「看診掛號」或「藥品」。\n\n"

            "【任務目標】\n"
            "1. **Merchant**: 正確店名 (查不到留空)。\n"
            "2. **Category**: 合理分類。⚠️ 格式鐵則：main_category 和 sub_category 必須是獨立乾淨的詞，絕對不准使用 `>` 符號連在一起！\n"
            "3. **Amount**: 正確總金額。\n"
            "4. **Tags**: **必須給出** 2-3 個 Hashtag (例如 #咖啡 #下午茶)。\n"
            "5. **Comment**: 簡短有趣的評價，**必須使用動物指定的稱呼 (如主人/奴才/暱稱)**。"
            "如果有抓到店名(Merchant)，請把店名自然地融入這句話裡(例如「今天又去星巴克啦」)，"
            "**絕對不要在店名前後加任何引號或括號**(不要用「」『』【】把店名框起來)，讀起來要像口語聊天，不要像在標記資料。\n"
            "6. **Date**: YYYY-MM-DD。\n"
            "7. **Invoice Number**: 發票號碼。\n\n"

            "【分類地圖】\n"
            f"{category_map_str}\n"
            f"{memory_hint_str}"
            f"{common_mistake_str}"
        )
        content_prompt = f"現在時間: {current_time}\n"
        content_prompt += f"[原始資料]: {scanned_content}\n"
        if user_input:
            content_prompt += f"[使用者備註]: {user_input}\n"

    else:
        print("🚀 啟動 User Input Mode (Math & Mixed Mode Compatible)")
        system_prompt = (
            f"你是風格多變的記帳管家。{type_hint}\n"
            f"{persona_prompt}\n\n" 
            
            "【分類任務 (精準度第一)】\n"
            "1. **Main/Sub Category**: 從下方的【分類地圖】挑選。\n"
            "   - ⚠️ **絕對優先使用現有分類**：請尋找語意相近的現有分類（例如有「晚餐」就不要自創「餐食」）。只有當【分類地圖】中「完全沒有」相關分類時，才允許自創子分類。\n"
            "   - ⚠️ 收支分流鐵則：只要是獲得金錢、進帳（如發薪水、中獎、零用錢等），就必須、且只能從 INCOME 分類中挑選！若是花錢支出，請挑選 EXPENSE 分類。\n"
            "   - ⚠️ 格式鐵則：main_category 和 sub_category 必須是獨立乾淨的詞，絕對不准使用 `>` 符號連在一起！\n"
            "   - **專屬優先**：專屬分類優先於通用分類。\n"
            "   - **動作優先**：如超商印東西歸類為影印費。\n"
            "2. **Merchant**: 抓出商家名 (若無則留空)。\n"
            "3. **Amount (超級重要)**: 必須是正數(絕對值)。請運用你的數學能力處理加減乘除。\n"
            "4. **Tags**: **必須給出** 2-3 個 Hashtag。\n"
            "5. **Comment**: **完全依照動物人設**進行有趣、不重複的短評。"
            "如果有抓到店名(Merchant)，請把店名自然地融入這句話裡(例如「又跑去全家買東西啦」)，"
            "**絕對不要在店名前後加任何引號或括號**(不要用「」『』【】把店名框起來)，讀起來要像口語聊天，不要像在標記資料。\n\n"

            "【⚠️ 特殊處理與數學計算規則 (必看)】\n"
            "1. **無中生有 (意外之財)**：若出現「撿到」、「中獎」、「獲得」、「紅包」，這絕對是【收入】，請不要當成支出！\n"
            "2. **混搭與抵銷 (加減法)**：若句子同時包含收入與支出 (例:「花300買衣服，但媽媽給500」)，請互相抵銷，最終 Amount 應為 200，並歸類至 INCOME 分類 (例如零用錢)。\n"
            "3. **找零陷阱 (減法)**：若句子包含「找我」、「找回」、「找了」，**你必須啟動減法計算！** (公式：付出的總金額 - 找回的錢 = 實際花費金額)。例如：「拿1000買晚餐，找我850」，實際花費是 1000 - 850 = 150，Amount 必須填寫 150。請特別注意中文口語，例如「八百五」等於 850、「一千」等於 1000。\n"
            "4. **平分與均攤 (除法)**：若語音包含「平分」、「分給X人」，**務必執行除法** (例:「比賽獎金5000分給5人」-> Amount 為 1000，歸類至 INCOME)。\n"
            "5. **強制自創分類 (Override)**：\n"
            "   - 蜜餞、豆干、魚皮 -> 歸類為主分類「飲食」，子分類「零食」\n"
            "   - 加油 -> 歸類為主分類「交通」，子分類「加油」\n"
            "   - 課程、學費 -> 歸類為主分類「學費與教材」，子分類「補習班」或「學雜費」\n"
            "   - 電腦、手機 -> 子分類填寫「3C產品」\n"
            "   - 收驚、安太歲 -> 子分類填寫「宗教/民俗」\n"
            "   - 發薪水、薪水、薪資、收入、獎金 -> **【絕對是收入】必須從 INCOME 挑選，主分類填「薪水」，子分類填「正職薪資」等 (⚠️絕對不可填寫任何支出分類)**\n"
            "💡 **注意：下方 [Python預抓金額] 可能不準確，請完全以你的數學邏輯算出的淨額為主！**\n\n"
            
            "【分類地圖】\n"
            f"{category_map_str}\n"
            f"{memory_hint_str}"
            f"{common_mistake_str}"
            "--------------------------------------------------\n"
            "【判斷邏輯】\n"
            f"- 現在時間: {current_time}\n"
            f"- Python預抓金額 (僅供參考): {amount}\n"
        )
        content_prompt = user_input

    schema = {
        "name": "expense_analysis",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "date": {"type": "string", "description": "格式 YYYY-MM-DD"},
                "invoice_number": {"type": "string"},
                "main_category": {"type": "string"},
                "sub_category": {"type": "string"},
                "merchant": {"type": "string"},
                "amount": {"type": "number"},
                "items_summary": {"type": "string", "description": "重點品項摘要"},
                "tags": {"type": "array", "items": {"type": "string"}}, 
                "comment": {"type": "string"},
                "confidence": {"type": "number"}
            },
            "required": ["date", "invoice_number", "main_category", "sub_category", "merchant", "amount", "items_summary", "tags", "comment", "confidence"],
            "additionalProperties": False
        }
    }

    try:
        resp = client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": content_prompt}
            ],
            response_format={"type": "json_schema", "json_schema": schema},
            temperature=0.6,        
            frequency_penalty=1.2,  
        )
        content = resp.choices[0].message.content
        return json.loads(content)
    except Exception as e:
        print(f"LLM Error: {e}")
        return {
            "main_category": "其他支出",
            "sub_category": "其他",
            "merchant": "",
            "amount": amount,
            "tags": [],
            "comment": "連線異常",
            "confidence": 0.0,
            "date": "",
            "invoice_number": "",
            "items_summary": ""
        }


# =========================
# AI 個人化時事公告
# =========================

def detect_news_topics(
    transactions: List[Dict[str, Any]]
) -> List[str]:
    """
    只在後端分析分類與備註，
    不把完整記帳資料傳給 OpenAI。
    """

    combined_text = " ".join(
        f"{item.get('category', '')} {item.get('note', '')}"
        for item in transactions
    ).lower()

    topic_rules = {
        "投資理財": [
            "投資", "股票", "台積電", "2330",
            "etf", "0050", "0056", "00878",
            "00919", "基金", "鴻海", "聯發科",
        ],
        "飲食與物價": [
            "飲食", "早餐", "午餐", "晚餐",
            "咖啡", "飲料", "外送",
            "foodpanda", "ubereats",
        ],
        "交通與油價": [
            "交通", "高鐵", "捷運", "公車",
            "加油", "中油", "台塑",
            "計程車", "uber",
        ],
        "娛樂與串流": [
            "娛樂", "電影", "遊戲", "ktv",
            "串流", "netflix", "spotify",
            "演唱會", "展覽",
        ],
        "醫療健康": [
            "醫院", "診所", "掛號", "藥",
            "藥局", "健保", "門診", "看診",
        ],
        "購物與消費": [
            "蝦皮", "momo", "pchome",
            "購物", "博客來", "全聯",
            "家樂福", "costco", "好市多",
        ],
        "旅遊與匯率": [
            "住宿", "飯店", "旅遊", "機票",
            "日本", "韓國", "泰國",
            "東京", "大阪", "沖繩", "航空",
        ],
    }

    topics: List[str] = []

    for topic, keywords in topic_rules.items():
        if any(keyword.lower() in combined_text for keyword in keywords):
            topics.append(topic)

    # 最多搜尋三類，避免 API 成本和等待時間過高
    return topics[:3]


def _remove_markdown_code_block(text: str) -> str:
    """
    若模型把 JSON 包在 ```json ... ``` 中，將外框移除。
    """
    cleaned = (text or "").strip()

    cleaned = re.sub(
        r"^```(?:json)?\s*",
        "",
        cleaned,
        flags=re.IGNORECASE,
    )

    cleaned = re.sub(
        r"\s*```$",
        "",
        cleaned,
    )

    return cleaned.strip()


def _default_news_items(
    message: str
) -> List[Dict[str, Any]]:
    """
    AI 搜尋失敗或沒有記帳主題時使用。
    """
    return [
        {
            "title": "個人化時事提醒",
            "summary": message,
            "topic": "一般",
            "sources": [],
        }
    ]


def generate_latest_news_for_user(
    topics: List[str],
    transaction_count: int,
    pet_persona: Optional[str] = None,
    spending_insight: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """
    將整理後的主題交給 OpenAI Web Search，
    不傳送原始記帳內容、店家資料，
    只傳送整理後的支出摘要。
    """

    if not topics:
        return _default_news_items(
            "多記幾筆帳，我就能幫你找更貼近生活的提醒囉！"
        )

    if not OPENAI_API_KEY:
        return _default_news_items(
            "目前智慧公告正在休息，晚點再來看看吧。"
        )

    topic_text = "、".join(topics)

    persona_text = (
        pet_persona
        or "語氣自然、溫柔、像朋友提醒，不要太嚴肅。"
    )

    spending_insight = spending_insight or {}

    week_amount = spending_insight.get("week_amount", 0)
    week_count = spending_insight.get("week_count", 0)
    top_category = spending_insight.get(
        "top_category",
        "生活支出",
    )
    top_share = spending_insight.get("top_share", 0)
    top_merchant = spending_insight.get("top_merchant", "")            # ★ 新增
    top_merchant_count = spending_insight.get("top_merchant_count", 0)  # ★ 新增

    spending_text = f"""
使用者最近 7 天支出摘要：
- 總支出：約 NT${week_amount:,.0f}
- 記帳筆數：{week_count} 筆
- 主要支出類別：{top_category}
- 主要類別占最近 30 天支出：約 {top_share * 100:.0f}%
"""
    # ★ 新增：如果有抓到常去的店家(最近 30 天內去過 2 次以上)，額外補一行事實給 AI
    if top_merchant:
        spending_text += f"- 最近 30 天最常去的店家：{top_merchant}，共去了 {top_merchant_count} 次\n"

    prompt = f"""
你是一個台灣智慧記帳 App 的首頁小喇叭公告產生器。

你不是銀行顧問，也不是正式新聞主播。
你是使用者目前上場寵物的可愛理財小助手。

目前寵物個性：
{persona_text}

使用者最近 30 天共有 {transaction_count} 筆記帳資料。

後端已將記帳資料整理成以下主題：
{topic_text}

{spending_text}

請搜尋目前最新、可信，且與上述支出主題有關的公開時事，
並將「使用者自己的支出狀況」和「近期時事」自然連結起來。

公告目標：
讓使用者看到時覺得：
「欸，這真的跟我最近花錢的狀況有關。」

要求：

1. 使用繁體中文。
2. 最多提供 3 則公告。
3. 優先採用政府、官方機構或可信新聞媒體。
4. 每則 summary 最多 32 個中文字。
5. title 最多 6 個中文字。
6. summary 優先包含一個個人化資訊，例如：
   - 本週支出金額
   - 本週記帳筆數
   - 主要支出類別
   - 支出占比
7. 再自然連結近期新聞或生活趨勢。
8. 不要塞太多數字，每則最多出現 1 個主要數據。
9. 語氣要符合目前寵物個性。
10. 可以可愛、俏皮、有一點吐槽，但不要責備使用者。
11. 不要像正式財經新聞、銀行客服或政府公告。
12. 不可提供買進、賣出、保證獲利、診斷或治療建議。
13. 若涉及股票、ETF、基金或投資，只能提醒「可留意相關新聞」。
14. 不可推測使用者未提供的個人資訊。
15. 不要只是說「可以留意」、「可以看看」，
    要先說出與使用者支出相關的重點。
16. 必須回傳純 JSON，不要加 Markdown。
17. sources 必須放實際搜尋到的來源名稱與網址。
18. 如果上面有提供「最近 30 天最常去的店家」，優先直接點名這個店家(例如「這個月跑了 3 次星巴克」)，
    會比只講分類名稱(例如「飲食」)更有畫面、更貼近使用者的真實生活；沒有提供店家資訊時，才用分類名稱講。

公告風格範例：

「這週飲食花 NT$1,280，最近外食物價也有動靜，汪！」

「娛樂占比 32%，串流相關消息值得偷瞄一下，喵。」

「這週記了 6 筆交通，通勤成本最近有點熱鬧啦～🎵」

請不要直接複製範例文字。

JSON 格式必須完全符合：

{{
  "items": [
    {{
      "title": "簡短標題",
      "summary": "短句個人化公告",
      "topic": "所屬主題",
      "sources": [
        {{
          "title": "來源名稱",
          "url": "https://..."
        }}
      ]
    }}
  ]
}}
"""

    try:
        # 你原本的 OpenAI 呼叫程式碼放在這裡
        # 例如：
        #
        # response = client.responses.create(
        #     model=OPENAI_NEWS_MODEL,
        #     input=prompt,
        #     tools=[{"type": "web_search_preview"}],
        # )
        #
        # 接著保留你原本解析 response 的程式碼

        pass

    except Exception as e:
        print(
            "generate_latest_news_for_user 發生錯誤：",
            e,
            flush=True,
        )
        traceback.print_exc()

        return _default_news_items(
            "目前智慧公告有點忙，晚點再來看看吧。"
        )

    try:
        response = client.responses.create(
            model=os.getenv(
                "OPENAI_NEWS_MODEL",
                "gpt-5-mini",
            ),
            tools=[
                {
                    "type": "web_search",
                    "search_context_size": "low",
                }
            ],
            input=prompt,
        )

        raw_text = _remove_markdown_code_block(
            response.output_text
        )

        result = json.loads(raw_text)
        raw_items = result.get("items", [])

        if not isinstance(raw_items, list):
            raise ValueError("AI 回傳的 items 不是陣列")

        valid_items: List[Dict[str, Any]] = []

        for item in raw_items[:3]:
            if not isinstance(item, dict):
                continue

            title = str(item.get("title", "")).strip()
            summary = str(item.get("summary", "")).strip()
            topic = str(item.get("topic", "")).strip()

            raw_sources = item.get("sources", [])
            sources: List[Dict[str, str]] = []

            if isinstance(raw_sources, list):
                for source in raw_sources:
                    if not isinstance(source, dict):
                        continue

                    source_title = str(
                        source.get("title", "")
                    ).strip()

                    source_url = str(
                        source.get("url", "")
                    ).strip()

                    if (
                        source_url.startswith("https://")
                        or source_url.startswith("http://")
                    ):
                        sources.append({
                            "title": source_title or "新聞來源",
                            "url": source_url,
                        })

            if not title or not summary:
                continue

            # 防止首頁公告太長
            if len(summary) > 30:
                summary = summary[:30]

            valid_items.append({
                "title": title,
                "summary": summary,
                "topic": topic or topics[0],
                "sources": sources,
            })

        if not valid_items:
            raise ValueError("AI 沒有回傳有效新聞")

        return valid_items

    except json.JSONDecodeError as e:
        print(f"❌ AI 時事 JSON 解析失敗：{e}")

        return _default_news_items(
            "最新提醒格式怪怪的，晚點再試試看。"
        )

    except Exception as e:
        print(f"❌ AI 最新時事取得失敗：{e}")
        traceback.print_exc()

        return _default_news_items(
            "目前智慧公告有點忙，晚點再回來看看。"
        )
# =========================
# 7) API 路由
# =========================

# ⚠️ 請在這裡填寫你本地端 MySQL 的連線資訊
DB_HOST = '127.0.0.1'
DB_USER = 'root'
DB_PASSWORD = os.environ["DB_PASSWORD"]
DB_NAME = 'myapp'        # 你的資料庫名稱

def get_db_connection():
    return pymysql.connect(
        host=DB_HOST, 
        user=DB_USER, 
        password=DB_PASSWORD, 
        db=DB_NAME, 
        cursorclass=pymysql.cursors.DictCursor
    )

# =========================
# ★ AI 自適應(閉環修正記憶)：per-user「關鍵字 → 偏好分類」記憶表。
#   和你們既有的「5 次解鎖(is_custom 觀察期)」互補——這裡只在「既有分類」範圍內記住你的習慣、
#   讓下次同店家/品項直接分對，不新增任何分類、不影響頁面整潔。整段是加法，不改動原本的規則與分類樹。
# =========================
_CATEGORY_MEMORY_HARD_THRESHOLD = 2  # hit_count ≥ 此值 → 直接硬蓋分類（改過一次就達標）；否則只是累積。
_category_memory_ready = False

# ★修正：常見店家關鍵字（語音講法不同也抽到同一個 key，例如「昨天在全家一杯柳橙汁」→「全家」）。
_MEMORY_STORE_KEYWORDS = [
    "全家", "全聯", "7-11", "711", "統一超商", "萊爾富", "ok超商", "美廉社",
    "星巴克", "cama", "路易莎", "85度c", "麥當勞", "肯德基", "摩斯", "subway", "大苑子",
    "五十嵐", "清心", "可不可", "迷客夏", "coco", "家樂福", "costco", "好市多", "大潤發", "愛買",
    "頂好", "寶雅", "屈臣氏", "康是美", "誠品", "蝦皮", "momo", "pchome", "台鐵", "高鐵", "捷運", "ubike",
]
# ★修正：記憶關鍵字專用的加強停用詞（時間/地點/填充詞），比一般 STOPWORDS 多。
_MEMORY_EXTRA_STOP = [
    "今天", "昨天", "前天", "早上", "中午", "下午", "晚上", "剛才", "剛剛", "在", "的", "東西",
    "一些", "還有", "然後", "我在", "順便", "個", "們", "這", "那", "一杯", "一份", "一個", "買了",
]

def _ensure_category_memory_table():
    global _category_memory_ready
    if _category_memory_ready:
        return
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "CREATE TABLE IF NOT EXISTS user_category_memory ("
            " user_id VARCHAR(128) NOT NULL,"
            " keyword VARCHAR(128) NOT NULL,"
            " main_category VARCHAR(64),"
            " sub_category VARCHAR(64),"
            " hit_count INT DEFAULT 1,"
            " distinct_count INT DEFAULT 1,"
            " last_used_at DATETIME DEFAULT CURRENT_TIMESTAMP,"
            " PRIMARY KEY (user_id, keyword)"
            ")"
        )
        # ★修正：舊表補上 distinct_count 欄位（已存在會丟例外，忽略即可）
        try:
            cursor.execute("ALTER TABLE user_category_memory ADD COLUMN distinct_count INT DEFAULT 1")
        except Exception:
            pass
        conn.commit()
        _category_memory_ready = True
    except Exception as e:
        print("⚠️ 建立 user_category_memory 失敗：", e)
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def _memory_keyword(user_input: str, scanned_content: str, known_merchant: Optional[str]) -> str:
    # ★ 新增修正(掃描發票)：掃描時 App 送來的 user_input 固定是「我是{暱稱}」，不是消費內容。
    #   以前統編沒查到店家時會拿它當 key → 每張發票都被記成「是小p」，分類記憶全部混在一起。
    #   現在掃描時只用「統編查到的店家」或「OCR 原文裡的常見店家」當 key，都沒有就不使用記憶。
    if scanned_content:
        if known_merchant:
            km = norm_text(known_merchant)
            for kw in _MEMORY_STORE_KEYWORDS:
                if kw in km:
                    return kw
            return km[:64]
        sc = norm_text(scanned_content)
        for kw in _MEMORY_STORE_KEYWORDS:
            if kw in sc:
                return kw
        return ""

    # 取一個代表關鍵字當 key。★修正：讓「全家」和「昨天在全家一杯柳橙汁」抽到同一個 key「全家」。
    base = norm_text(known_merchant) if known_merchant else norm_text(user_input or "")
    # 1) 命中常見店家 → 直接用店名當 key（解決複合式店家講法不同 key 對不上的問題）
    for kw in _MEMORY_STORE_KEYWORDS:
        if kw in base:
            return kw
    # 2) 沒命中 → 去金額 + 加強停用詞(時間/地點/填充詞)後取核心
    detail = extract_detail(user_input or "")
    d = norm_text(detail)
    for w in _MEMORY_EXTRA_STOP:
        d = d.replace(w, "")
    d = d.strip()
    return d[:64]

def _lookup_category_memory(user_id, keyword) -> Optional[Dict]:
    if not user_id or not keyword:
        return None
    _ensure_category_memory_table()
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT main_category, sub_category, hit_count, distinct_count FROM user_category_memory WHERE user_id=%s AND keyword=%s",
            (str(user_id), keyword),
        )
        return cursor.fetchone()
    except Exception as e:
        print("⚠️ 查詢分類記憶失敗：", e)
        return None
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def _upsert_category_memory(user_id, keyword, main_category, sub_category, corrected: bool) -> None:
    # 記帳/編輯時把「keyword → 最終分類」寫回：使用者「改過的」直接拉到硬蓋門檻(下次就自動套)，
    # 「沿用 AI 的」則慢慢 +1 累積。只記對應、不新增任何分類。
    if not user_id or not keyword or not main_category:
        return
    _ensure_category_memory_table()
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT main_category, sub_category, hit_count, distinct_count FROM user_category_memory WHERE user_id=%s AND keyword=%s",
            (str(user_id), keyword),
        )
        existing = cursor.fetchone()
        if existing is None:
            hit = _CATEGORY_MEMORY_HARD_THRESHOLD if corrected else 1
            cursor.execute(
                "INSERT INTO user_category_memory (user_id, keyword, main_category, sub_category, hit_count, last_used_at)"
                " VALUES (%s,%s,%s,%s,%s,NOW())",
                (str(user_id), keyword, main_category, sub_category, hit),
            )
        else:
            same = (existing.get("main_category") == main_category and existing.get("sub_category") == sub_category)
            if same:
                cursor.execute(
                    "UPDATE user_category_memory SET hit_count=hit_count+1, last_used_at=NOW() WHERE user_id=%s AND keyword=%s",
                    (str(user_id), keyword),
                )
            else:
                # ★修正(複合式店家)：這次分類跟記憶不同 → distinct_count+1，最新的當「提示」；
                #   distinct_count ≥2 之後就不再硬蓋，改讓 AI 依「這次買什麼」判斷。
                hit = _CATEGORY_MEMORY_HARD_THRESHOLD if corrected else 1
                new_distinct = int(existing.get("distinct_count", 1) or 1) + 1
                cursor.execute(
                    "UPDATE user_category_memory SET main_category=%s, sub_category=%s, hit_count=%s, distinct_count=%s, last_used_at=NOW()"
                    " WHERE user_id=%s AND keyword=%s",
                    (main_category, sub_category, hit, new_distinct, str(user_id), keyword),
                )
        conn.commit()
    except Exception as e:
        print("⚠️ 寫入分類記憶失敗：", e)
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

#=== 公告分析 ===
def get_authenticated_user_id():
    auth_header = request.headers.get("Authorization", "")

    if not auth_header.startswith("Bearer "):
        return None, (
            jsonify({
                "status": "error",
                "message": "缺少登入 Token"
            }),
            401
        )

    token = auth_header.split(" ", 1)[1].strip()

    try:
        decoded_token = jwt.decode(
            token,
            JWT_SECRET,
            algorithms=["HS256"]
        )

        user_id = decoded_token.get("user_id")

        if not user_id:
            return None, (
                jsonify({
                    "status": "error",
                    "message": "Token 中找不到 user_id"
                }),
                401
            )

        return str(user_id), None

    except Exception as e:
        return None, (
            jsonify({
                "status": "error",
                "message": f"Token 驗證失敗：{str(e)}"
            }),
            401
        )
 # =======

@app.post("/api/login")
def login_or_register():
    data = request.get_json(silent=True) or {}
    user_id = str(data.get("user_id", "")).strip()
    
    if not user_id:
        return jsonify({"status": "error", "message": "必須提供 user_id"}), 400

    # ==========================================
    # ★★★ 新增：真實連線資料庫，檢查並建立帳號與大富翁資金 ★★★
    # ==========================================
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # 1. 檢查 users 表中是否已經有這個 user_id
        cursor.execute("SELECT id FROM users WHERE id = %s", (user_id,))
        user_record = cursor.fetchone()
        
        # 2. 如果沒有紀錄，代表是新下載 App 或換手機的新玩家
        if not user_record:
            # 在 users 表建立基本資料 (如果 schema 稍有不同，可以只留 id)
            cursor.execute("INSERT INTO users (id) VALUES (%s)", (user_id,))
            
            # ★★★ 關鍵：在 players 表發放「大富翁初始資金」(預設給 5000)
            cursor.execute("INSERT INTO players (user_id, money) VALUES (%s, %s)", (user_id, 5000))
            
            print(f"🎉 建立新帳號與大富翁初始資金成功！User ID: {user_id}")
        else:
            print(f"✅ 歡迎老玩家回歸！User ID: {user_id}")
            
        conn.commit()
    except Exception as e:
        print(f"❌ 資料庫註冊或登入失敗: {e}")
        if 'conn' in locals() and conn:
            conn.rollback()
    finally:
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'conn' in locals() and conn:
            conn.close()
    # ==========================================

    payload = {
        "user_id": user_id,
        "iat": datetime.utcnow(),
    }
    
    token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
    
    return jsonify({
        "status": "success",
        "message": "Token 核發成功",
        "token": token
    })


# ==========================================
# ★★★ 新增 14) Firebase 登入驗證 (Google / Email 密碼 共用同一支) ★★★
# ==========================================
# 前端不論用 Google 或 Email/密碼 登入，都會拿到「Firebase ID Token」，一律打這支。
# 後端用 firebase-admin 驗證 token → 對應到內部 9 位數 user_id
# (第一次登入才建一組並記住對照，之後同一個帳號永遠對到同一組) → 發原本的 JWT。
# 這樣同時修好「換手機資料不見」，且不需要對外網域/HTTPS (驗證是後端往外打給 Google)。
#
# 後端需先安裝套件： pip install firebase-admin
# 服務帳戶金鑰檔需跟 app.py 放同一層 (檔名如下 FIREBASE_KEY_FILENAME)。
FIREBASE_KEY_FILENAME = "pet-accounting-firebase-adminsdk-fbsvc-27ebfc8cb1.json"
_FIREBASE_READY = False


def _ensure_firebase():
    """延遲載入 firebase-admin，避免『尚未安裝套件』時影響到其他 API。"""
    global _FIREBASE_READY
    if _FIREBASE_READY:
        return
    import firebase_admin
    from firebase_admin import credentials
    key_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        FIREBASE_KEY_FILENAME
    )
    if not firebase_admin._apps:
        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred)
    _FIREBASE_READY = True


@app.post("/api/auth/firebase")
def auth_firebase():
    data = request.get_json(silent=True) or {}
    id_token = str(data.get("id_token", "")).strip()
    if not id_token:
        return jsonify({"status": "error", "message": "必須提供 id_token"}), 400

    # 1. 驗證 Firebase ID Token (Google 或 Email 密碼登入拿到的都可以)
    try:
        _ensure_firebase()
        from firebase_admin import auth as fb_auth
        decoded = fb_auth.verify_id_token(id_token)
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status": "error", "message": f"Firebase 驗證失敗: {e}"}), 401

    firebase_uid = decoded.get("uid")
    email = decoded.get("email")
    # ★★★ 新增：取出手機號碼 (手機登入才會有，Google/Email 登入這裡會是 None) ★★★
    phone_number = decoded.get("phone_number")
    # ★★★ 新增：取出顯示名稱與登入方式 (google / email)，之後一起存進 users 表 ★★★
    display_name = decoded.get("name")
    sign_in_provider = (decoded.get("firebase") or {}).get("sign_in_provider", "")
    if sign_in_provider == "google.com":
        auth_provider = "google"
    elif sign_in_provider == "password":
        auth_provider = "email"
    else:
        auth_provider = sign_in_provider or "firebase"
    if not firebase_uid:
        return jsonify({"status": "error", "message": "無法取得 Firebase UID"}), 401

    # 2. 對應到內部 9 位數 user_id (沒有對應過就建一組新的)
    conn = None
    cursor = None
    user_id = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # 對照表：第一次呼叫時自動建立，不需要你手動去改資料庫
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS firebase_user_map (
                firebase_uid VARCHAR(128) PRIMARY KEY,
                user_id BIGINT NOT NULL,
                email VARCHAR(255),
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # ★★★ 新增：如果是舊的資料表 (還沒有 phone_number 欄位)，自動補上，完全不會動到既有資料 ★★★
        try:
            cursor.execute("ALTER TABLE firebase_user_map ADD COLUMN phone_number VARCHAR(32)")
        except Exception:
            pass  # 欄位已經存在時會報錯，直接忽略即可，不影響後續流程

        # 查這個 Firebase 帳號之前有沒有對應過
        cursor.execute("SELECT user_id FROM firebase_user_map WHERE firebase_uid = %s", (firebase_uid,))
        row = cursor.fetchone()

        if row:
            # 老帳號：直接拿回原本那組數字 id (換手機也是同一組，資料不會不見)
            user_id = row["user_id"]
            # ★★★ 新增：回填 email / 顯示名稱 / 登入方式 / auth_uid (舊帳號之前可能沒存到) ★★★
            cursor.execute(
                "UPDATE users SET email = %s, display_name = %s, auth_provider = %s, auth_uid = %s WHERE id = %s",
                (email, display_name, auth_provider, firebase_uid, user_id)
            )
            # ★★★ 新增：如果這次登入有拿到手機號碼 (手機登入)，順便更新 firebase_user_map 裡的 phone_number ★★★
            if phone_number:
                cursor.execute(
                    "UPDATE firebase_user_map SET phone_number = %s WHERE firebase_uid = %s",
                    (phone_number, firebase_uid)
                )
            print(f"✅ Firebase 老帳號登入！uid={firebase_uid} -> user_id={user_id}")
        else:
            # 新帳號：產生一組不重複的 9 位數 id
            for _ in range(10):
                candidate = random.randint(100000000, 999999999)
                cursor.execute("SELECT id FROM users WHERE id = %s", (candidate,))
                if not cursor.fetchone():
                    user_id = candidate
                    break
            if user_id is None:
                user_id = random.randint(100000000, 999999999)

            # 建 users + players (發大富翁初始資金 5000)，跟 /api/login 的邏輯一致
            # ★★★ 修改：連同 email / 顯示名稱 / 登入方式 / auth_uid 一起寫入 users 表 ★★★
            cursor.execute(
                "INSERT INTO users (id, email, display_name, auth_provider, auth_uid) VALUES (%s, %s, %s, %s, %s)",
                (user_id, email, display_name, auth_provider, firebase_uid)
            )
            cursor.execute("INSERT INTO players (user_id, money) VALUES (%s, %s)", (user_id, 5000))
            # 記住這個 Firebase 帳號對應到哪一組數字 id
            # ★★★ 新增：手機登入時把 phone_number 一併存進去，方便之後查詢 ★★★
            cursor.execute(
                "INSERT INTO firebase_user_map (firebase_uid, user_id, email, phone_number) VALUES (%s, %s, %s, %s)",
                (firebase_uid, user_id, email, phone_number)
            )
            print(f"🎉 Firebase 新帳號建立成功！uid={firebase_uid} -> user_id={user_id}")

        conn.commit()
    except Exception as e:
        traceback.print_exc()
        if conn:
            conn.rollback()
        return jsonify({"status": "error", "message": f"帳號對應失敗: {e}"}), 500
    finally:
        if cursor: cursor.close()
        if conn: conn.close()

    # 3. 發跟原本一樣的 JWT (payload 用內部數字 id)
    payload = {
        "user_id": str(user_id),
        "iat": datetime.utcnow(),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")

    return jsonify({
        "status": "success",
        "message": "登入成功",
        "token": token,
        "user_id": str(user_id)
    })


# ==========================================
# ★★★ 新增 15) LINE 登入驗證 ★★★
# ==========================================
# 前端用 flutter_line_sdk 登入 LINE 後，把 access_token（或 id_token）打這支。
# 後端往 api.line.me 驗證 → 對應到內部 9 位數 user_id（跟 Firebase 那支同一套邏輯，
# 用 line_user_map 記對照，第一次登入自動建）→ 發原本的 JWT。
# 後端只需要 Channel ID（不需要 Channel secret；secret 是給前端 SDK 設定用的）。
LINE_LOGIN_CHANNEL_ID = "2010784124"


@app.post("/api/auth/line")
def auth_line():
    data = request.get_json(silent=True) or {}
    id_token = str(data.get("id_token", "")).strip()
    access_token = str(data.get("access_token", "")).strip()

    if not id_token and not access_token:
        return jsonify({"status": "error", "message": "必須提供 id_token 或 access_token"}), 400

    # 1. 往 LINE 官方驗證，取出 LINE 使用者資訊
    line_uid = None
    email = None
    display_name = None
    try:
        if id_token:
            # 方式 A：驗證 ID Token（可一併拿到 email / 名稱）
            resp = requests.post(
                "https://api.line.me/oauth2/v2.1/verify",
                data={"id_token": id_token, "client_id": LINE_LOGIN_CHANNEL_ID},
                timeout=10,
            )
            if resp.status_code != 200:
                return jsonify({"status": "error", "message": f"LINE id_token 驗證失敗: {resp.text}"}), 401
            info = resp.json()
            line_uid = info.get("sub")
            email = info.get("email")
            display_name = info.get("name")
        else:
            # 方式 B：驗證 Access Token，並確認這個 token 屬於「我們這個 channel」
            verify = requests.get(
                "https://api.line.me/oauth2/v2.1/verify",
                params={"access_token": access_token},
                timeout=10,
            )
            if verify.status_code != 200:
                return jsonify({"status": "error", "message": f"LINE access_token 驗證失敗: {verify.text}"}), 401
            vinfo = verify.json()
            if str(vinfo.get("client_id")) != str(LINE_LOGIN_CHANNEL_ID):
                return jsonify({"status": "error", "message": "access_token 不屬於本 channel"}), 401
            # 再拿使用者 profile（userId / 顯示名稱）
            profile = requests.get(
                "https://api.line.me/v2/profile",
                headers={"Authorization": f"Bearer {access_token}"},
                timeout=10,
            )
            if profile.status_code != 200:
                return jsonify({"status": "error", "message": f"LINE profile 取得失敗: {profile.text}"}), 401
            pinfo = profile.json()
            line_uid = pinfo.get("userId")
            display_name = pinfo.get("displayName")
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status": "error", "message": f"LINE 驗證發生錯誤: {e}"}), 401

    if not line_uid:
        return jsonify({"status": "error", "message": "無法取得 LINE 使用者 ID"}), 401

    auth_provider = "line"

    # 2. 對應到內部 9 位數 user_id（沒有對應過就建一組新的；邏輯跟 /api/auth/firebase 一致）
    conn = None
    cursor = None
    user_id = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # 對照表：第一次呼叫時自動建立，不需要你手動去改資料庫
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS line_user_map (
                line_uid VARCHAR(128) PRIMARY KEY,
                user_id BIGINT NOT NULL,
                email VARCHAR(255),
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # 查這個 LINE 帳號之前有沒有對應過
        cursor.execute("SELECT user_id FROM line_user_map WHERE line_uid = %s", (line_uid,))
        row = cursor.fetchone()

        if row:
            # 老帳號：拿回原本那組數字 id（換手機也是同一組，資料不會不見）
            user_id = row["user_id"]
            cursor.execute(
                "UPDATE users SET email = %s, display_name = %s, auth_provider = %s, auth_uid = %s WHERE id = %s",
                (email, display_name, auth_provider, line_uid, user_id)
            )
            print(f"✅ LINE 老帳號登入！line_uid={line_uid} -> user_id={user_id}")
        else:
            # 新帳號：產生一組不重複的 9 位數 id
            for _ in range(10):
                candidate = random.randint(100000000, 999999999)
                cursor.execute("SELECT id FROM users WHERE id = %s", (candidate,))
                if not cursor.fetchone():
                    user_id = candidate
                    break
            if user_id is None:
                user_id = random.randint(100000000, 999999999)

            # 建 users + players（發大富翁初始資金 5000），跟 /api/login、/api/auth/firebase 一致
            cursor.execute(
                "INSERT INTO users (id, email, display_name, auth_provider, auth_uid) VALUES (%s, %s, %s, %s, %s)",
                (user_id, email, display_name, auth_provider, line_uid)
            )
            cursor.execute("INSERT INTO players (user_id, money) VALUES (%s, %s)", (user_id, 5000))
            cursor.execute(
                "INSERT INTO line_user_map (line_uid, user_id, email) VALUES (%s, %s, %s)",
                (line_uid, user_id, email)
            )
            print(f"🎉 LINE 新帳號建立成功！line_uid={line_uid} -> user_id={user_id}")

        conn.commit()
    except Exception as e:
        traceback.print_exc()
        if conn:
            conn.rollback()
        return jsonify({"status": "error", "message": f"帳號對應失敗: {e}"}), 500
    finally:
        if cursor: cursor.close()
        if conn: conn.close()

    # 3. 發跟原本一樣的 JWT
    payload = {
        "user_id": str(user_id),
        "iat": datetime.utcnow(),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")

    return jsonify({
        "status": "success",
        "message": "登入成功",
        "token": token,
        "user_id": str(user_id)
    })


@app.get("/health")
def health():
    return jsonify({"ok": True, "version": APP_VERSION})

@app.post("/classify")
def classify():
    data = request.get_json(silent=True) or {}

    user_input = str(data.get("user_input", "")).strip()
    scanned_content = str(data.get("scanned_content", "")).strip()
    current_time = str(data.get("current_time", "")).strip()
    raw_group = data.get("identity") or ""
    current_pet = data.get("current_pet")
    group = normalize_group(raw_group)

    if not user_input and not scanned_content:
        return jsonify({"status": "error", "message": "No input"}), 400

    print(f"📩 收到請求 | Input: {user_input[:10]}... | ScanData: {len(scanned_content)} chars | Pet: {current_pet}")

    record_type = guess_record_type(user_input)
    amount_py, currency = parse_amount_currency(user_input)
    category_map_str = build_category_map_str(CATEGORY_TREE, record_type, group)
    
    detail_text = extract_detail(user_input)

    # 1. Python 查庫 (本地 SQLite)
    known_merchant = match_merchant_by_tax_id(scanned_content)
    if known_merchant:
        print(f"🎯 統編命中資料庫！鎖定店家：{known_merchant}")

    # ★ 新增【校正 0】統編 OCR 混淆修正：原始統編查不到時，把 0↔8、3↔6 互換後通過檢查碼的候選再查一次
    if not known_merchant and scanned_content:
        fixed_tax_ids = fix_ocr_tax_ids(scanned_content)
        if fixed_tax_ids:
            known_merchant = match_merchant_by_tax_id("\n".join(fixed_tax_ids))
            if known_merchant:
                print(f"🎯 統編(OCR校正後)命中資料庫！候選={fixed_tax_ids} 鎖定店家：{known_merchant}")

    # ★ AI 自適應(閉環修正記憶)：分類前先查「這個店家/品項，你以前都分到哪」。
    #   命中且 hit_count 夠高 → 稍後用你的偏好硬蓋分類（只蓋分類，金額/店名照原流程）。
    memory_user_id = data.get("user_id")
    memory_keyword = _memory_keyword(user_input, scanned_content, known_merchant)
    memory_hit = _lookup_category_memory(memory_user_id, memory_keyword)
    if memory_hit:
        print(f"🧠 命中分類記憶：{memory_keyword} → {memory_hit.get('main_category')}/{memory_hit.get('sub_category')} (hit={memory_hit.get('hit_count')})")

    # 2. 執行 AI 分析
    analysis = llm_text_classify(
        category_map_str=category_map_str,
        user_input=user_input,
        scanned_content=scanned_content,
        detail_text=detail_text,
        current_time=current_time,
        amount=amount_py or 0.0,
        record_type=record_type,
        known_merchant=known_merchant,
        current_pet=current_pet,
        memory_hit=memory_hit  # ★ 新增：把個人記憶交給 AI 自己權衡判斷
    )

    # ==========================================
    # 3. Python 後端校正 (Hybrid Processing)
    # ==========================================
    final_amount = float(analysis.get("amount", 0.0) or 0.0)
    
    # 【校正 1】金額 (Amount)
    authoritative_total = extract_total_from_ocr(scanned_content)
    if authoritative_total is not None and authoritative_total > 0:
        final_amount = float(authoritative_total)

    # ★ 新增：多處金額多數決（避免 0 被認成 8 時，上面取最大值反而選到錯的那個）
    voted_total = extract_total_by_vote(scanned_content)
    if voted_total is not None and voted_total > 0:
        if voted_total != final_amount:
            print(f"🗳️ 金額多數決校正：{final_amount} → {voted_total}")
        final_amount = float(voted_total)
    
    if final_amount == 0.0 and amount_py > 0 and not scanned_content: 
         final_amount = amount_py

    # 【校正 2】商家名稱 (Merchant)
    merchant = (analysis.get("merchant") or "").strip()
    
    if known_merchant:
        merchant = known_merchant # 如果有查到統編，直接覆蓋

    if not merchant:
        upper_scan = scanned_content.upper()
        if "7-ELEVEN" in upper_scan or "統一超商" in scanned_content:
            merchant = "7-ELEVEN"
        elif ("全家" in scanned_content and "便利商店" in scanned_content) or "FAMILYMART" in upper_scan:
            merchant = "全家便利商店"
        elif "PXMART" in upper_scan or "全聯" in scanned_content:
            merchant = "全聯福利中心"
        elif "COSTCO" in upper_scan or "好市多" in scanned_content:
            merchant = "好市多"
        elif "STARBUCKS" in upper_scan or "星巴克" in scanned_content:
            merchant = "星巴克"
        elif "MCDONALD" in upper_scan or "麥當勞" in scanned_content:
            merchant = "麥當勞"

    # ★ 新增：不管 merchant 是 AI 自己抓到的、統編查到的、還是上面關鍵字比對出來的，
    #   最後都統一套用一次正規化，把「Starbucks」「星巴克咖啡」這種變體都轉成同一個「星巴克」，
    #   這樣後面不管是記憶比對、還是「累積 2 次」的店家統計，才不會被不同寫法拆成好幾家不同的店。
    merchant = normalize_merchant_name(merchant)

    # 【校正 3】排除醫療 (Medical)
    main_cat = analysis.get("main_category", "其他支出")
    sub_cat = analysis.get("sub_category", "其他")
    main_cat, sub_cat = enforce_not_medical_if_no_context(main_cat, sub_cat, scanned_content)

    # ★ AI 自適應(閉環修正記憶)：hit_count 夠高就用「你的習慣」硬蓋分類（只蓋分類，不動金額/店名）。
    #   ★修正(複合式店家)：只有「單一性店家」(distinct_count ≤1)才硬蓋；像全家/全聯這種一個 keyword
    #   出現過多種分類的複合式店家(distinct_count ≥2)就不硬蓋，讓 AI 依這次買的品項判斷。
    # ★★★ 新增說明：現在 AI 在上面已經先看過同一份記憶提示、自己判斷過一次了，
    #   所以這裡不再是唯一決定分類的地方，而是「雙重保險」——
    #   萬一 AI 判斷完還是沒有依照使用者的一貫習慣，這裡再補強制蓋一次，確保高把握的情況不會出錯。★★★
    from_memory = False
    if memory_hit and int(memory_hit.get("hit_count", 0) or 0) >= _CATEGORY_MEMORY_HARD_THRESHOLD \
            and int(memory_hit.get("distinct_count", 1) or 1) <= 1:
        mem_main = (memory_hit.get("main_category") or "").strip()
        mem_sub = (memory_hit.get("sub_category") or "").strip()
        if mem_main:
            main_cat = mem_main
            sub_cat = mem_sub
            from_memory = True
            print(f"🧠 依分類記憶硬蓋 → {main_cat}/{sub_cat}")

    # 【校正 4】發票號碼驗證
    inv_no = analysis.get("invoice_number", "").strip().upper()
    if not re.match(r"^[A-Z]{2}-?\d{8}$", inv_no):
        inv_no = ""

    # ★ 新增【校正 5】日期 (Date)：OCR 原文抓得到就以 Python 為準（含民國年換算、0↔8 / 3↔6 年份校正）
    final_date = analysis.get("date", "") or ""
    ocr_date = extract_invoice_date_from_ocr(scanned_content) if scanned_content else None
    if ocr_date:
        if ocr_date != final_date:
            print(f"📅 日期校正：AI={final_date} → OCR={ocr_date}")
        final_date = ocr_date

    # ★ 新增【校正 6】金額不確定：這張發票已證實 0 會被讀成 8（或 6→3），且金額裡有該數字 → 交給使用者點選確認
    amount_candidates = build_amount_candidates(scanned_content, final_amount) if scanned_content else []
    if amount_candidates:
        print(f"❓ 金額不確定，請使用者確認：{amount_candidates}")

    # ★ 新增：不管 AI 有沒有照指令加 # 前綴，這裡強制統一補上，確保前端顯示一定有 #，不再依賴 AI 是否乖乖照做
    raw_tags = analysis.get("tags", []) or []
    normalized_tags = []
    for t in raw_tags:
        t = str(t).strip()
        if t and not t.startswith("#"):
            t = f"#{t}"
        if t:
            normalized_tags.append(t)

    result = {
        "matched_main_category": main_cat,
        "matched_sub_category": sub_cat,
        "merchant": merchant,
        "tags": normalized_tags,
        "comment": analysis.get("comment", ""),
        "amount": final_amount,
        "currency": currency,
        "confidence": analysis.get("confidence", 0.0),
        "date": final_date,
        "tax_debug": debug_tax_id_lookup(scanned_content) if scanned_content else None,  # ★ 新增（除錯用）：統編查詢過程
        "amount_uncertain": bool(amount_candidates),   # ★ 新增：金額需要使用者確認
        "amount_candidates": amount_candidates,        # ★ 新增：例如 [378.0, 370.0]
        "invoice_number": inv_no,
        "items_summary": analysis.get("items_summary", ""),
        "from_memory": from_memory,       # ★ AI 自適應：這次分類是否來自你的個人記憶(用於前端提示)
        "memory_keyword": memory_keyword  # ★ AI 自適應：這次用的關鍵字(前端存檔時回傳給 upsert)
    }

    print(f"✅ 分析結果: {result}")
    
    return jsonify({"status": "success", "data": result})


# ★ AI 自適應(閉環修正記憶)：記帳/編輯存檔時呼叫，把「keyword → 使用者最終選的分類」寫回記憶。
#   corrected=true 代表使用者有手動改分類(強訊號，直接達硬蓋門檻)；false 代表沿用 AI(慢慢累積)。
@app.post("/category-memory/upsert")
def category_memory_upsert():
    data = request.get_json(silent=True) or {}
    user_id = data.get("user_id")
    main_category = str(data.get("main_category", "")).strip()
    sub_category = str(data.get("sub_category", "")).strip()
    corrected = bool(data.get("corrected", False))

    # keyword 優先用前端從 /classify 回傳的 memory_keyword；沒有就用同一套規則現算(確保和分類時一致)。
    keyword = str(data.get("memory_keyword", "")).strip()
    if not keyword:
        user_input = str(data.get("user_input", "")).strip()
        scanned_content = str(data.get("scanned_content", "")).strip()
        known_merchant = match_merchant_by_tax_id(scanned_content) if scanned_content else None
        keyword = _memory_keyword(user_input, scanned_content, known_merchant)

    if not user_id or not keyword or not main_category:
        return jsonify({"ok": False, "reason": "missing user_id / keyword / main_category"})

    _upsert_category_memory(user_id, keyword, main_category, sub_category, corrected)
    return jsonify({"ok": True, "keyword": keyword, "corrected": corrected})


# ★ AI 自適應(閉環修正記憶)：查詢某使用者目前學到的所有規則(給「AI 學到的分類規則」面板用)。
@app.get("/category-memory/list")
def category_memory_list():
    user_id = request.args.get("user_id")
    if not user_id:
        return jsonify({"ok": False, "items": []})
    _ensure_category_memory_table()
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT keyword, main_category, sub_category, hit_count, distinct_count, last_used_at"
            " FROM user_category_memory WHERE user_id=%s ORDER BY hit_count DESC, last_used_at DESC",
            (str(user_id),),
        )
        rows = cursor.fetchall() or []
        for r in rows:
            if r.get("last_used_at") is not None:
                r["last_used_at"] = str(r["last_used_at"])
        return jsonify({"ok": True, "items": rows})
    except Exception as e:
        print("⚠️ 查詢分類記憶清單失敗：", e)
        return jsonify({"ok": False, "items": []})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


# ★ AI 自適應(閉環修正記憶)：刪除某一條學到的規則(給面板的「刪除」用)。
@app.post("/category-memory/delete")
def category_memory_delete():
    data = request.get_json(silent=True) or {}
    user_id = data.get("user_id")
    keyword = str(data.get("keyword", "")).strip()
    if not user_id or not keyword:
        return jsonify({"ok": False, "reason": "missing user_id / keyword"})
    _ensure_category_memory_table()
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM user_category_memory WHERE user_id=%s AND keyword=%s",
            (str(user_id), keyword),
        )
        conn.commit()
        return jsonify({"ok": True})
    except Exception as e:
        print("⚠️ 刪除分類記憶失敗：", e)
        return jsonify({"ok": False})
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


# =========================
# 首頁公告用：寵物個性設定
# =========================
NEWS_BANNER_PERSONAS = {
    "dog": """
    【角色扮演：你是一隻忠誠熱情的狗狗 🐶】
    - 語氣：熱情、黏人、充滿鼓勵。
    - 稱呼：請自然呼喚「{nickname}主人」。
    - 習慣：看到主人最近的消費變化會熱心提醒，但不要責備。
    - 可以用「汪！」、「汪汪！」作為句尾。
    """,

    "cat": """
    【角色扮演：你是一隻傲嬌毒舌的貓咪 😼】
    - 語氣：高冷、有點吐槽，但其實有在關心。
    - 稱呼：請自然呼喚「{nickname}奴才」或「{nickname}」。
    - 習慣：會吐槽最近花費變多，但不要太兇。
    - 可以用「喵...」、「哼」作為句尾。
    """,

    "fox": """
    【角色扮演：你是一隻優雅狡猾的狐狸 🦊】
    - 語氣：聰明、調皮、帶一點腹黑。
    - 稱呼：請自然呼喚「親愛的{nickname}」。
    - 習慣：會提醒主人觀察最近消費、預算或新聞變化。
    - 可以用「呵呵」、「哎呀」作為句尾。
    """,

    "parrot": """
    【角色扮演：你是一隻愛唱歌的鸚鵡 🦜】
    - 語氣：活潑、有節奏感、像小喇叭廣播。
    - 稱呼：可以呼喚「{nickname}！{nickname}！」。
    - 習慣：會重複一個重點詞，例如「預算、預算」或「飲料、飲料」。
    - 可以用「~🎵」、「啦啦啦~🎵」作為句尾。
    """,

    "sloth": """
    【角色扮演：你是一隻慵懶的樹懶 🦥】
    - 語氣：慢慢的、溫柔、短句、有點想睡。
    - 稱呼：可以呼喚「{nickname}...」。
    - 習慣：用很放鬆的方式提醒最近支出或預算，不給壓力。
    - 可以用「...zzZ」作為句尾。
    """
}
# =========================
# AI 首頁新聞公告：快取與背景生成
# =========================

NEWS_BANNER_CACHE = {}
NEWS_BANNER_GENERATING = set()

NEWS_BANNER_CACHE_DIRECT_SECONDS = 5 * 60
NEWS_BANNER_CACHE_MAX_SECONDS = 10 * 60


def make_news_banner_cache_key(
    user_id,
    current_pet,
    nickname,
    topics,
    spending_insight,
):
    raw_key = json.dumps(
        {
            "user_id": str(user_id),
            "current_pet": current_pet,
            "nickname": nickname,
            "topics": topics,

            "week_amount": spending_insight.get("week_amount", 0),
            "week_count": spending_insight.get("week_count", 0),
            "top_category": spending_insight.get("top_category", ""),
            "top_share": spending_insight.get("top_share", 0),
        },
        ensure_ascii=False,
        sort_keys=True,
    )

    return hashlib.md5(raw_key.encode("utf-8")).hexdigest()


def get_news_banner_cache(cache_key):
    cache_data = NEWS_BANNER_CACHE.get(cache_key)

    if not cache_data:
        return None, None

    created_at = cache_data.get("created_at", 0)
    age_seconds = time.time() - created_at

    return cache_data, age_seconds


def save_news_banner_cache(cache_key, response_data):
    NEWS_BANNER_CACHE[cache_key] = {
        "created_at": time.time(),
        "response_data": response_data,
    }
def build_spending_insights(transactions):
    """
    從最近 30 天交易中整理：
    - 最近 7 天總支出
    - 最近 7 天筆數
    - 各分類金額
    - 主要分類
    """

    category_totals = {}
    category_counts = {}
    merchant_counts = {}   # ★ 新增：各店家出現次數(最近 30 天)
    merchant_amounts = {}  # ★ 新增：各店家花費金額(最近 30 天)

    week_amount = 0.0
    week_count = 0

    # ★ 新增：從備註裡的「【店家名稱】」格式解析出店家
    _merchant_pattern = re.compile(r"【([^】]+)】")

    for tx in transactions:
        # cursor.fetchall() 如果回傳 dict，可直接取
        category = str(tx.get("category", "") or "").strip()
        note = str(tx.get("note", "") or "").strip()

        # 如果你的 SQL 還沒有 amount/date，
        # 等下第 2 步會一起補
        amount = float(tx.get("amount", 0) or 0)
        days_ago = int(tx.get("days_ago", 999) or 999)

        if category:
            category_totals[category] = (
                category_totals.get(category, 0) + amount
            )
            category_counts[category] = (
                category_counts.get(category, 0) + 1
            )

        # ★ 新增：統計店家次數與金額，解析不到就跳過，不影響其他統計
        merchant_match = _merchant_pattern.search(note)
        if merchant_match:
            merchant_name = merchant_match.group(1).strip()
            if merchant_name and merchant_name != "未知店家":
                merchant_counts[merchant_name] = merchant_counts.get(merchant_name, 0) + 1
                merchant_amounts[merchant_name] = merchant_amounts.get(merchant_name, 0) + amount

        if days_ago <= 6:
            week_amount += amount
            week_count += 1

    if category_totals:
        top_category = max(
            category_totals,
            key=category_totals.get,
        )
        top_category_amount = category_totals[top_category]
    else:
        top_category = "生活支出"
        top_category_amount = 0

    total_amount = sum(category_totals.values())

    top_share = (
        top_category_amount / total_amount
        if total_amount > 0
        else 0
    )

    # ★ 新增：找出最常去的店家(至少 2 次才算，只去過一次不夠有代表性)
    top_merchant = ""
    top_merchant_count = 0
    if merchant_counts:
        candidate = max(merchant_counts, key=merchant_counts.get)
        if merchant_counts[candidate] >= 2:
            top_merchant = candidate
            top_merchant_count = merchant_counts[candidate]

    return {
        "week_amount": round(week_amount, 0),
        "week_count": week_count,
        "top_category": top_category,
        "top_category_amount": round(top_category_amount, 0),
        "top_share": round(top_share, 2),
        "top_merchant": top_merchant,               # ★ 新增
        "top_merchant_count": top_merchant_count,   # ★ 新增
    }

def build_fallback_news_items(
    topics,
    current_pet="dog",
    nickname="使用者",
    spending_insight=None,
):
    spending_insight = spending_insight or {}

    week_amount = spending_insight.get("week_amount", 0)
    week_count = spending_insight.get("week_count", 0)
    top_category = spending_insight.get("top_category", "生活支出")
    top_share = spending_insight.get("top_share", 0)

    pet_suffix = {
        "dog": "汪！",
        "cat": "喵...哼。",
        "fox": "呵呵。",
        "parrot": "啦啦啦～",
        "sloth": "...zzZ",
    }.get(current_pet, "汪！")

    if not topics:
        topics = ["生活提醒"]

    items = []

    for topic in topics[:3]:
        if topic == "飲食與物價":
            title = "飲食雷達"
            summary = (
                f"{nickname}這週花NT${week_amount:,.0f}，"
                f"飲食很活躍，物價消息可以瞄一下，{pet_suffix}"
            )

        elif topic == "交通與油價":
            title = "通勤雷達"
            summary = (
                f"{nickname}這週記了{week_count}筆，"
                f"交通支出最近有點熱鬧，{pet_suffix}"
            )

        elif topic == "娛樂與串流":
            title = "娛樂雷達"
            summary = (
                f"{nickname}最近娛樂支出偏活躍，"
                f"訂閱費可以偷偷檢查一下，{pet_suffix}"
            )

        elif topic == "投資理財":
            title = "理財雷達"
            summary = (
                f"{nickname}最近有理財相關紀錄，"
                f"相關新聞可以順手關注，{pet_suffix}"
            )

        else:
            title = "生活雷達"
            summary = (
                f"{nickname}這週花NT${week_amount:,.0f}，"
                f"{top_category}最活躍，{pet_suffix}"
            )

        items.append({
            "title": title,
            "summary": summary[:36],
            "topic": topic,
            "sources": []
        })

    return items


def build_news_banner_response(
    topics,
    news_items,
    transaction_count,
    current_pet,
    nickname,
    cache_status,
    cache_age_seconds=0,
):
    return {
        "status": "success",
        "data": {
            "topics": topics,
            "items": news_items,
            "transaction_count": transaction_count,
            "analysis_period": "最近30天",
            "current_pet": current_pet,
            "nickname": nickname,
            "cache_status": cache_status,
            "cache_age_seconds": cache_age_seconds,
            "disclaimer": (
                "本內容僅供資訊參考，"
                "不構成投資、醫療或消費建議。"
            ),
        }
    }


def generate_news_banner_in_background(
    cache_key,
    topics,
    transaction_count,
    current_pet,
    nickname,
    pet_persona,
    spending_insight,
):
    """
    背景慢慢跑 AI 搜尋新聞。
    前端不用等這段完成。
    """

    if cache_key in NEWS_BANNER_GENERATING:
        print("news-banner 背景生成已在進行中，略過重複生成", flush=True)
        return

    NEWS_BANNER_GENERATING.add(cache_key)

    try:
        print("news-banner 背景開始 AI 搜尋新聞", flush=True)

        news_items = generate_latest_news_for_user(
            topics=topics,
            transaction_count=transaction_count,
            pet_persona=pet_persona,
            spending_insight=spending_insight,
        )

        if not news_items:
            print("news-banner 背景 AI 回傳空資料，改用 fallback", flush=True)
            news_items = build_fallback_news_items(
                topics=topics,
                current_pet=current_pet,
                nickname=nickname,
            )
            cache_status = "background_fallback"
        else:
            cache_status = "background_ai_generated"

        response_data = build_news_banner_response(
            topics=topics,
            news_items=news_items,
            transaction_count=transaction_count,
            current_pet=current_pet,
            nickname=nickname,
            cache_status=cache_status,
            cache_age_seconds=0,
        )

        save_news_banner_cache(cache_key, response_data)

        print("news-banner 背景 AI 公告已存入快取", flush=True)

    except Exception as e:
        print("news-banner 背景 AI 生成失敗：", e, flush=True)
        traceback.print_exc()

    finally:
        NEWS_BANNER_GENERATING.discard(cache_key)

# =========================
# AI 個人化時事公告 API
# =========================
@app.get("/api/news-banner")
def get_news_banner():
    user_id, error_response = get_authenticated_user_id()

    if error_response:
        return error_response

    current_pet = request.args.get("current_pet", "dog")
    nickname = request.args.get("nickname", "使用者")

    pet_persona = NEWS_BANNER_PERSONAS.get(
        current_pet,
        NEWS_BANNER_PERSONAS["dog"]
    ).format(nickname=nickname)

    print("news-banner current_pet =", current_pet, flush=True)
    print("news-banner nickname =", nickname, flush=True)

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                   COALESCE(c.name, '') AS category,
                   COALESCE(t.note, '') AS note,
                   COALESCE(t.amount, 0) AS amount,
                   DATEDIFF(CURDATE(), t.date) AS days_ago
            FROM accounting_transactions AS t
            LEFT JOIN accounting_categories AS c
                ON t.category_id = c.id
            WHERE t.user_id = %s
              AND t.type = 'expense'
              AND t.date >= DATE_SUB(
                  CURDATE(),
                  INTERVAL 30 DAY
              )
            ORDER BY t.date DESC, t.id DESC
            LIMIT 100
        """, (user_id,))

        transactions = cursor.fetchall()
        topics = detect_news_topics(transactions)
        transaction_count = len(transactions)
        spending_insight = build_spending_insights(transactions)

        print(
            "news-banner spending insight =",
            spending_insight,
            flush=True,
        )
        cache_key = make_news_banner_cache_key(
            user_id=user_id,
            current_pet=current_pet,
            nickname=nickname,
            topics=topics,
            spending_insight=spending_insight,
        )

        cache_data, age_seconds = get_news_banner_cache(cache_key)

        # 1. 10 分鐘內有 AI 快取：直接回傳
        if cache_data and age_seconds is not None and age_seconds <= NEWS_BANNER_CACHE_MAX_SECONDS:
            print(
                "news-banner 使用快取，age_seconds =",
                int(age_seconds),
                flush=True
            )

            cached_response = cache_data["response_data"]

            cached_response["data"]["cache_status"] = (
                "fresh_cache"
                if age_seconds <= NEWS_BANNER_CACHE_DIRECT_SECONDS
                else "usable_cache"
            )
            cached_response["data"]["cache_age_seconds"] = int(age_seconds)

            return jsonify(cached_response)

        # 2. 沒有快取或快取過期：前端先拿 fallback，不等 AI
        fallback_items = build_fallback_news_items(
            topics=topics,
            current_pet=current_pet,
            nickname=nickname,
            spending_insight=spending_insight,
        )

        fallback_response = build_news_banner_response(
            topics=topics,
            news_items=fallback_items,
            transaction_count=transaction_count,
            current_pet=current_pet,
            nickname=nickname,
            cache_status="fallback_returned_ai_generating",
            cache_age_seconds=0,
        )

        # 3. 背景啟動 AI 搜尋新聞，成功後存進快取
        thread = threading.Thread(
            target=generate_news_banner_in_background,
            kwargs={
                "cache_key": cache_key,
                "topics": topics,
                "transaction_count": transaction_count,
                "current_pet": current_pet,
                "nickname": nickname,
                "pet_persona": pet_persona,
                "spending_insight": spending_insight,
            },
            daemon=True,
        )
        thread.start()

        print("news-banner 已回傳 fallback，AI 新聞背景生成中", flush=True)

        return jsonify(fallback_response)

    except Exception as e:
        traceback.print_exc()

        fallback_items = build_fallback_news_items(
            topics=["理財提醒"],
            current_pet=current_pet,
            nickname=nickname,
        )

        fallback_response = build_news_banner_response(
            topics=["理財提醒"],
            news_items=fallback_items,
            transaction_count=0,
            current_pet=current_pet,
            nickname=nickname,
            cache_status="error_fallback",
            cache_age_seconds=0,
        )

        return jsonify(fallback_response)

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()
# ==========================================
# ★★★ 新增 8) 專屬「每日總結」的 AI API ★★★
# ==========================================
def llm_summary_generate(transactions_text: str, total_amount: float, nickname: str, date_text: str, current_pet: str = "dog") -> str:
    selected_animal_key = current_pet if current_pet in ANIMAL_PERSONAS else "dog"
    persona_prompt = ANIMAL_PERSONAS[selected_animal_key].format(nickname=nickname)
    
    print(f"🐶 總結固定動物: {selected_animal_key} | 暱稱: {nickname}")

    system_prompt = (
        f"你是一個貼心的記帳管家。\n"
        f"{persona_prompt}\n\n"
        f"【任務】\n"
        f"使用者{date_text}總共花了 {total_amount} 元。\n"
        f"以下是他的花費明細（包含分類與金額）：\n{transactions_text}\n\n"
        f"請根據這些明細，用你的動物人設給出一段 50 字以內的總結評語。\n"
        f"請務必包含：\n"
        f"1. 必須符合動物人設的語氣與指定的稱呼（絕不可以使用表情符號）。\n"
        f"2. 挑選明細中最貴或最特別的項目來吐槽、關心或鼓勵。\n"
        f"3. 絕對不要一條一條列出明細，自然地講話即可。\n"
        f"4. 請務必回傳 JSON 格式，且 key 必須為 \"comment\"。\n"
    )

    try:
        # ★★★ 修正：使用最穩定版本的 json_object 以避免 JSON Encoder 當掉 ★★★
        resp = client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": system_prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.7,
        )
        content = json.loads(resp.choices[0].message.content)
        # ★★★ 重要修復：確保這裡呼叫的是 content.get(...) 括號不能少 ★★★
        final_comment = str(content.get("comment", "汪！今天辛苦啦！"))
        print(f"✅ AI 總結回傳結果: {final_comment}")
        return final_comment
    except Exception as e:
        print(f"LLM Summary Error: {e}")
        return "汪... 狗狗算數算到睡著了，總之辛苦啦！"

@app.post("/summary")
def generate_daily_summary():
    data = request.get_json(silent=True) or {}
    
    transactions_text = str(data.get("transactions_text", "")).strip()
    total_amount = float(data.get("total_amount", 0.0))
    user_input = str(data.get("user_input", "")).strip() # 用來抓暱稱
    date_text = str(data.get("date_text", "今天")).strip() # "今天" 或 "昨天"
    current_pet = str(data.get("current_pet", "dog")).strip()
    
    nickname = "主人"
    if "我是" in user_input:
        try:
            nickname = user_input.split("我是")[1].strip()
        except:
            pass

    if total_amount == 0:
        return jsonify({"status": "success", "comment": f"氣噗噗！{date_text}都沒看到{nickname}來記帳，肚子好餓喔！"})

    comment = llm_summary_generate(
        transactions_text=transactions_text,
        total_amount=total_amount,
        nickname=nickname,
        date_text=date_text,
        current_pet=current_pet
    )

    return jsonify({"status": "success", "comment": str(comment)})


# =========================
# 週報分享圖：寵物個性設定
# =========================
WEEKLY_SHARE_PERSONAS = {
    "dog": """
    你是一隻熱情忠誠的狗狗記帳員。
    語氣：可愛、鼓勵、活潑、像在幫主人守護錢包。
    稱呼使用者時可以叫「{nickname}主人」。
    可以自然使用「汪！」、「汪汪！」。
    不要責備使用者。
    """,

    "cat": """
    你是一隻傲嬌毒舌但其實關心主人的貓咪管家。
    語氣：高冷、吐槽、可愛、有點傲嬌。
    稱呼使用者時可以叫「{nickname}」或「{nickname}奴才」。
    可以自然使用「喵」、「哼」。
    不要太兇，不要讓使用者有壓力。
    """,

    "fox": """
    你是一隻聰明優雅的狐狸理財顧問。
    語氣：聰明、俏皮、帶一點小腹黑，但仍然溫柔。
    稱呼使用者時可以叫「親愛的{nickname}」。
    可以自然使用「呵呵」、「哎呀」。
    不要提供投資建議。
    """,

    "parrot": """
    你是一隻愛唱歌、愛廣播的鸚鵡記帳播報員。
    語氣：活潑、有節奏感、像小喇叭公告。
    稱呼使用者時可以叫「{nickname}！{nickname}！」。
    可以重複一個關鍵詞，例如「預算、預算」。
    可以自然使用「啦啦啦～」。
    """,

    "sloth": """
    你是一隻慵懶溫柔的樹懶小助理。
    語氣：慢慢的、放鬆、療癒、不給壓力。
    稱呼使用者時可以叫「{nickname}...」。
    可以自然使用「...zzZ」。
    句子可以短一點、柔和一點。
    """
}


def _local_weekly_share_summary(
    current_pet,
    nickname,
    total_expense,
    top_category,
    top_categories
):
    """
    AI 失敗時的本地備用文案。
    避免前端分享圖沒有小結論。
    """

    if not top_category or top_category == "無":
        return f"{nickname}這週錢包很安全，記帳小助手覺得你超會守護預算！"

    if current_pet == "cat":
        return (
            f"哼，{nickname}這週的花費王是「{top_category}」。"
            f"雖然有點會花，但至少有乖乖記帳，算你有進步喵。"
        )

    if current_pet == "fox":
        return (
            f"哎呀，親愛的{nickname}，這週「{top_category}」偷偷吃掉不少預算呢。"
            f"下週可以更聰明地安排開銷，呵呵。"
        )

    if current_pet == "parrot":
        return (
            f"{nickname}！{nickname}！這週花費王是「{top_category}」！"
            f"預算、預算，要一起顧好啦啦啦～"
        )

    if current_pet == "sloth":
        return (
            f"{nickname}...這週「{top_category}」比較明顯呢。"
            f"慢慢調整就好，不用太有壓力...zzZ"
        )

    return (
        f"{nickname}主人，這週花費王是「{top_category}」。"
        f"有記帳就已經很棒了，下週一起繼續守護錢包，汪！"
    )


def generate_weekly_share_summary(
    current_pet,
    nickname,
    total_expense,
    top_category,
    top_categories,
    weekly_data,
    top_merchant=""  # ★ 新增：本週去最多次的店家，格式 "店家名稱:次數"，沒有就是空字串
):
    """
    產生分享圖上的 AI 小結論。
    注意：這裡不做 web search，所以速度會比 news-banner 快很多。
    """

    persona = WEEKLY_SHARE_PERSONAS.get(
        current_pet,
        WEEKLY_SHARE_PERSONAS["dog"]
    ).format(nickname=nickname)

    # ★ 新增：把 "店家名稱:次數" 拆開，組成一行給 AI 看的店家事實
    merchant_fact_line = ""
    if top_merchant and ":" in top_merchant:
        m_name, _, m_count = top_merchant.rpartition(":")
        if m_name.strip():
            merchant_fact_line = f"本週最常去的店家：{m_name.strip()}，共去了 {m_count} 次\n"

    prompt = f"""
你是智慧記帳 App 的週報分享圖小編。
請根據使用者本週支出資料，產生一段適合放在社群分享卡上的可愛小結論。

目前寵物個性：
{persona}

使用者暱稱：{nickname}
本週總支出：NT$ {total_expense}
本週花費王分類：{top_category}
前三名支出分類與金額：{top_categories}
{merchant_fact_line}一週每日支出資料：{weekly_data}

要求：
1. 使用繁體中文。
2. 只輸出一句話，不要換行。
3. 字數控制在 35 到 60 個中文字左右。
4. 語氣要符合寵物個性。
5. 要像社群分享卡上的可愛結論，不要像正式報告。
6. 可以可愛、俏皮、吐槽、鼓勵，但不要責備使用者。
7. 不要提供投資建議。
8. 不要說你是 AI。
9. 不要使用 Markdown。
10. 不要輸出 JSON，只要輸出文字。
11. 如果上面有提供「本週最常去的店家」，優先直接點名這個店家的名字來講(例如「這週跑了 3 次星巴克」)，
    會比只說分類名稱(例如「飲食」)更有畫面、更有感；沒有提供店家資訊時，才用分類名稱講。
"""

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "你是一個繁體中文智慧記帳 App 的可愛週報文案助手。"
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            temperature=0.8,
            max_tokens=120,
        )

        summary = response.choices[0].message.content.strip()

        # 防止太長
        if len(summary) > 90:
            summary = summary[:90]

        return summary

    except Exception as e:
        print("generate_weekly_share_summary error:", e, flush=True)
        traceback.print_exc()

        return _local_weekly_share_summary(
            current_pet=current_pet,
            nickname=nickname,
            total_expense=total_expense,
            top_category=top_category,
            top_categories=top_categories,
        )


# =========================
# 週報分享圖 AI 小結論 API
# =========================
@app.get("/api/weekly-share-summary")
def get_weekly_share_summary():
    user_id, error_response = get_authenticated_user_id()

    if error_response:
        return error_response

    try:
        current_pet = request.args.get("current_pet", "dog")
        nickname = request.args.get("nickname", "使用者")
        total_expense = request.args.get("total_expense", "0")
        top_category = request.args.get("top_category", "無")
        top_categories = request.args.get("top_categories", "")
        weekly_data = request.args.get("weekly_data", "")
        top_merchant = request.args.get("top_merchant", "")  # ★ 新增

        print("weekly-share-summary current_pet =", current_pet, flush=True)
        print("weekly-share-summary nickname =", nickname, flush=True)
        print("weekly-share-summary total_expense =", total_expense, flush=True)
        print("weekly-share-summary top_category =", top_category, flush=True)
        print("weekly-share-summary top_categories =", top_categories, flush=True)
        print("weekly-share-summary top_merchant =", top_merchant, flush=True)
        print("weekly-share-summary weekly_data =", weekly_data, flush=True)

        summary = generate_weekly_share_summary(
            current_pet=current_pet,
            nickname=nickname,
            total_expense=total_expense,
            top_category=top_category,
            top_categories=top_categories,
            weekly_data=weekly_data,
            top_merchant=top_merchant,  # ★ 新增
        )

        return jsonify({
            "status": "success",
            "data": {
                "summary": summary,
                "current_pet": current_pet,
                "nickname": nickname,
                "total_expense": total_expense,
                "top_category": top_category,
                "top_categories": top_categories,
                "weekly_data": weekly_data,
            }
        })

    except Exception as e:
        traceback.print_exc()

        return jsonify({
            "status": "error",
            "message": "產生週報分享圖小結論失敗",
            "detail": str(e),
        }), 500
# ==========================================
# ★★★ 新增 13) AI 消費洞察 (分類/月比較/時段習慣/流速) - 跨門檻彈窗專用 ★★★
# ==========================================
# ★★★ 新增：AI 分類糾正分析工具 (給 B 用，開發者自己看的，不是給一般使用者的功能) ★★★
# 用途：找出「AI 建議的分類」跟「使用者最終選的分類」不一樣的案例，
#      而且是「有很多個不同使用者」都做了同樣糾正，才算是 AI 本身的系統性錯誤(不是單一使用者的個人喜好)。
# 用法：GET /api/admin/category-correction-report?min_distinct_users=5
#      (min_distinct_users 沒帶預設是 5，數字愈大代表門檻愈嚴格，只看真的很多人都覺得AI錯的模式)
@app.get("/api/admin/category-correction-report")
def category_correction_report():
    try:
        min_distinct_users = int(request.args.get("min_distinct_users", 5))
    except (TypeError, ValueError):
        min_distinct_users = 5

    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        # ★ 只看「AI 有給建議」且「建議跟最終分類不一樣」的紀錄，
        #   依「AI 建議了什麼、使用者最後選了什麼」分組，統計「有幾個不同的使用者」都這樣糾正。
        #   sample_notes 只是抓幾筆實際內容，方便人工判斷這個模式的真實情境是什麼，不是拿來自動生成範例用的。
        # ★ 修正：accounting_transactions 存的是 category_id / ai_suggested_category_id 這兩個外鍵(分類ID)，
        #   不是文字欄位，所以要 JOIN accounting_categories 兩次，分別對應「AI建議的分類」跟「最終分類」的名稱。
        #   (根據 8000 埠 FastAPI 的 main.py 第 774~782 行實際的 INSERT 語法確認過的正確欄位結構)
        cursor.execute("""
            SELECT
                ai_cat.name AS ai_guess,
                final_cat.name AS final_answer,
                COUNT(DISTINCT t.user_id) AS distinct_user_count,
                COUNT(*) AS total_occurrences,
                SUBSTRING(GROUP_CONCAT(DISTINCT t.note SEPARATOR ' ||| '), 1, 300) AS sample_notes
            FROM accounting_transactions t
            JOIN accounting_categories ai_cat ON t.ai_suggested_category_id = ai_cat.id
            JOIN accounting_categories final_cat ON t.category_id = final_cat.id
            WHERE t.ai_suggested_category_id IS NOT NULL
              AND t.ai_suggested_category_id != t.category_id
            GROUP BY ai_cat.name, final_cat.name
            HAVING COUNT(DISTINCT t.user_id) >= %s
            ORDER BY distinct_user_count DESC, total_occurrences DESC
            LIMIT 20
        """, (min_distinct_users,))
        rows = cursor.fetchall()
        return jsonify({
            "status": "success",
            "min_distinct_users": min_distinct_users,
            "patterns_found": len(rows),
            "patterns": rows,
            "note": "distinct_user_count 越高代表越多不同的人都做了同樣糾正，才值得考慮寫進 AI_COMMON_MISTAKE_EXAMPLES；"
                    "如果 patterns 是空的，代表目前資料量還不夠、或還沒有真的達到門檻的系統性錯誤，先不用急著加範例。"
        })
    except Exception as e:
        print("⚠️ category_correction_report 查詢失敗：", e, flush=True)
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.route("/api/spending-insight", methods=["POST"])
def spending_insight():
    """
    依使用者本月的真實消費數據，做「深度洞察」後，用當前寵物人設講 1~2 句。
    前端在跨過 50 / 80 / 100 門檻時呼叫，並帶入 level 決定這次要講什麼。
    前端需傳入 JSON: { "monthly_budget": 8000, "current_pet": "cat", "level": 80 }

    各 level 的洞察組合：
      - 50  : 流速預測 + 分類佔比 (輕鬆健檢，前端只在「花太快」時才會觸發；★任務2 已移除時段/深夜/週末)
      - 80  : 流速預測 + 分類洞察 (警告 + 針對性建議)
      - 100 : 分類洞察 + 月比較 (超支止血，揪出兇手類別)
    """
    user_id, error_response = get_authenticated_user_id()
    if error_response:
        return error_response

    data = request.get_json(silent=True) or {}
    monthly_budget = float(data.get("monthly_budget", 0))
    current_pet = str(data.get("current_pet", "dog")).strip()
    identity = str(data.get("identity", "u23")).strip()  # ★任務2：身分別 u23/a23_35/a35p，用來微調口吻

    # level 容錯：只接受 50 / 80 / 100，其他一律當成 80  ★任務2：中間級由 90 改 80
    try:
        level = int(data.get("level", 80))
    except Exception:
        level = 80
    if level not in (50, 80, 100):
        level = 80

    if monthly_budget <= 0:
        return jsonify({"status": "error", "message": "尚未設定月預算"}), 400

    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # ---------- 計算本月 / 上月的日期範圍 ----------
        now = datetime.now()
        days_in_month = calendar.monthrange(now.year, now.month)[1]
        days_passed = now.day

        first_this = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        if now.month == 12:
            first_next = first_this.replace(year=now.year + 1, month=1)
        else:
            first_next = first_this.replace(month=now.month + 1)
        if now.month == 1:
            first_last = first_this.replace(year=now.year - 1, month=12)
        else:
            first_last = first_this.replace(month=now.month - 1)

        s_first_this = first_this.strftime('%Y-%m-%d %H:%M:%S')
        s_first_next = first_next.strftime('%Y-%m-%d %H:%M:%S')
        s_first_last = first_last.strftime('%Y-%m-%d %H:%M:%S')

        # ---------- 撈本月每一筆支出 (含分類名稱與時間戳) ----------
        cursor.execute("""
            SELECT
                COALESCE(c.name, t.main_category, '其他') AS cat,
                t.amount AS amount,
                t.date   AS dt,
                t.note   AS note
            FROM accounting_transactions AS t
            LEFT JOIN accounting_categories AS c
                ON t.category_id = c.id
            WHERE t.user_id = %s
              AND t.type = 'expense'
              AND t.date >= %s
              AND t.date <  %s
        """, (user_id, s_first_this, s_first_next))
        this_rows = cursor.fetchall()

        # ---------- 撈上月每類支出加總 (給月比較用) ----------
        cursor.execute("""
            SELECT
                COALESCE(c.name, t.main_category, '其他') AS cat,
                SUM(t.amount) AS s
            FROM accounting_transactions AS t
            LEFT JOIN accounting_categories AS c
                ON t.category_id = c.id
            WHERE t.user_id = %s
              AND t.type = 'expense'
              AND t.date >= %s
              AND t.date <  %s
            GROUP BY cat
        """, (user_id, s_first_last, s_first_this))
        last_rows = cursor.fetchall()

        # ---------- Python 聚合「事實」(數字全部由程式算，不交給 AI 算) ----------
        total_spent = 0.0
        cat_spent = {}          # 各分類本月花費
        late_night_total = 0.0  # 深夜 (22:00~04:59) 花費
        weekend_total = 0.0     # 週末 (六、日) 花費
        late_cat = {}           # 深夜各分類花費 (用來找深夜花最兇的類別)
        merchant_spent = {}     # ★ 新增：各店家本月花費金額，用來找「花最多」的店家
        merchant_count = {}     # ★ 新增：各店家本月消費次數，用來找「去最多次」的店家

        # ★ 新增：從備註裡的【店家名稱】格式解析出店家，找不到就跳過，不影響其他統計
        _merchant_pattern = re.compile(r"【([^】]+)】")

        for r in this_rows:
            amt = float(r.get("amount") or 0)
            cat = str(r.get("cat") or "其他")
            total_spent += amt
            cat_spent[cat] = cat_spent.get(cat, 0.0) + amt

            # ★ 新增：解析店家名稱並累計次數與金額
            note = str(r.get("note") or "")
            merchant_match = _merchant_pattern.search(note)
            if merchant_match:
                merchant_name = merchant_match.group(1).strip()
                if merchant_name and merchant_name != "未知店家":
                    merchant_spent[merchant_name] = merchant_spent.get(merchant_name, 0.0) + amt
                    merchant_count[merchant_name] = merchant_count.get(merchant_name, 0) + 1

            dt = r.get("dt")
            if isinstance(dt, datetime):
                hour = dt.hour
                weekday = dt.weekday()  # 0=週一 ... 5=週六 6=週日
                if hour >= 22 or hour < 5:
                    late_night_total += amt
                    late_cat[cat] = late_cat.get(cat, 0.0) + amt
                if weekday >= 5:
                    weekend_total += amt

        # ★ 新增：找「去最多次」的店家 (次數優先，同次數比金額)，只有 >= 2 次才算「有感」，避免只買一次就被講
        top_merchant, top_merchant_amt, top_merchant_count = "", 0.0, 0
        if merchant_count:
            candidate = max(merchant_count, key=lambda m: (merchant_count[m], merchant_spent.get(m, 0.0)))
            if merchant_count[candidate] >= 2:
                top_merchant = candidate
                top_merchant_amt = merchant_spent.get(candidate, 0.0)
                top_merchant_count = merchant_count[candidate]

        # 花最兇的分類
        top_cat, top_cat_amt = "", 0.0
        if cat_spent:
            top_cat = max(cat_spent, key=cat_spent.get)
            top_cat_amt = cat_spent[top_cat]

        # 深夜花最兇的分類
        top_late_cat, top_late_amt = "", 0.0
        if late_cat:
            top_late_cat = max(late_cat, key=late_cat.get)
            top_late_amt = late_cat[top_late_cat]

        # 上月各類支出
        last_cat_spent = {}
        for r in last_rows:
            last_cat_spent[str(r.get("cat") or "其他")] = float(r.get("s") or 0)

        # 月比較：找出「漲最多」的分類
        rise_cat, rise_amt, rise_pct = "", 0.0, 0.0
        for cat, amt in cat_spent.items():
            prev = last_cat_spent.get(cat, 0.0)
            delta = amt - prev
            if delta > rise_amt:
                rise_amt = delta
                rise_cat = cat
                rise_pct = (delta / prev * 100) if prev > 0 else 100.0

        # 流速預測 (照目前速度推估月底總花費)
        projected = (total_spent / days_passed * days_in_month) if days_passed > 0 else total_spent
        budget_remaining = monthly_budget - total_spent
        projected_over = projected - monthly_budget

        # ---------- 依 level 組出要給 AI 的「事實摘要」與指令 ----------
        def _fmt(v):
            return f"{int(round(v))}"

        top_cat_share = (top_cat_amt / total_spent * 100) if total_spent > 0 else 0
        late_share = (late_night_total / total_spent * 100) if total_spent > 0 else 0
        weekend_share = (weekend_total / total_spent * 100) if total_spent > 0 else 0

        facts = (
            f"月預算: {_fmt(monthly_budget)} 元\n"
            f"本月已花: {_fmt(total_spent)} 元 (預算的 {int(round(total_spent / monthly_budget * 100))}%)\n"
            f"今天是本月第 {days_passed} 天 (整月共 {days_in_month} 天)\n"
            f"花最兇的分類: {top_cat or '無'} {_fmt(top_cat_amt)} 元 (佔總支出 {int(round(top_cat_share))}%)\n"
            # ★ 新增：本月最常消費的店家 (次數 >= 2 才會有值，只有一次的不夠有代表性就不提供)
            + (f"本月最常消費的店家: 「{top_merchant}」共去了 {top_merchant_count} 次，累計花費 {_fmt(top_merchant_amt)} 元\n" if top_merchant else "")
        )

        if level >= 100:
            # ★修正(AI數字沒跟上)：改成先講「抬頭那個關鍵數字」＝已超支金額（＝已花−預算），
            #   分類當輔助；且上月沒這類就講「本月新增」，不再假造「+100%」。
            over_amount = total_spent - monthly_budget
            rise_prev = last_cat_spent.get(rise_cat, 0.0) if rise_cat else 0.0
            insight_focus = (
                "【本次要講的重點：超支金額(關鍵數字) + 揪出兇手分類】\n"
                f"本月已花 {_fmt(total_spent)} 元，已超出預算約 {_fmt(over_amount)} 元 ← 這是關鍵數字，務必講出來\n"
                + (f"目前花最兇的分類是「{top_cat}」{_fmt(top_cat_amt)} 元\n" if top_cat else "")
                + (
                    f"其中「{rise_cat}」比上月多花 {_fmt(rise_amt)} 元 (約 {int(round(rise_pct))}%)\n"
                    if (rise_cat and rise_prev > 0)
                    else (f"「{rise_cat}」是本月新增的花費(上月沒有這類)\n" if rise_cat else "")
                )
            )
            tone = (
                "使用者已『超出預算』。請用嚴厲但不刻薄的語氣，"
                "一定要明確講出『已超支多少錢』這個關鍵數字(要跟畫面上的超支金額一致)，"
                "再點名花最兇的分類叫他冷靜止血。只能用上面提供的數字，不要自己杜撰或估算百分比。"
            )
        elif level >= 80:  # ★任務2：警告門檻由 90 改 80
            insight_focus = (
                "【本次要講的重點：流速預測 + 分類洞察】\n"
                f"照目前速度，月底預估會花到約 {_fmt(projected)} 元"
                + (f"，將『超支』約 {_fmt(projected_over)} 元\n" if projected_over > 0 else "，大致會壓在預算內\n")
            )
            tone = "使用者花費已逼近預算上限。請用警告的語氣，點出照這速度月底會超支，並建議先從花最兇的那一類下手。"
        else:
            # ★任務2：依新規格砍掉「時段習慣/深夜/週末」，50% 只講「流速預測 + 分類佔比」。
            insight_focus = (
                "【本次要講的重點：流速預測 + 分類佔比】\n"
                f"照目前速度，月底預估會花到約 {_fmt(projected)} 元"
                + (f"，可能會超支約 {_fmt(projected_over)} 元\n" if projected_over > 0 else "，目前大致還壓得住\n")
                + f"目前花最兇的分類是「{top_cat or '無'}」，佔總支出約 {int(round(top_cat_share))}%\n"
            )
            tone = "使用者才花到一半左右、但速度偏快。請用『輕鬆提醒』的語氣(不要罵人)，趁還來得及提醒他踩煞車，從流速或分類佔比挑一個最有梗的講。"

        # 決定動物人設 (查不到就退回狗狗)
        selected_animal_key = current_pet if current_pet in ANIMAL_PERSONAS else "dog"
        persona_prompt = ANIMAL_PERSONAS[selected_animal_key].format(nickname="主人")

        # ★任務2：身分別口吻（同一套計算引擎，只微調提醒語氣，不做三套邏輯）
        identity_note = {
            "u23": "使用者是學生，語氣輕鬆一點，重點是提醒他別月底吃土、別透支生活費。",
            "a23_35": "使用者是上班族，語氣可帶點理財紀律感，強調存款/投資要先顧、別讓變動支出吃掉存錢目標。",
            "a35p": "使用者要顧家庭，語氣穩重一點，強調固定支出與家用控管、把錢花在刀口上。",
        }.get(identity, "使用者是學生，語氣輕鬆一點，重點是提醒他別月底吃土、別透支生活費。")

        # ★選項B：身分 × 級別的「建議角度」（同一套數字，只換行動建議的切入點，不做三套邏輯）。
        _advice_by_identity = {
            "u23": {
                "hi": "叫他把剩下的錢分到剩餘天數、每天別超過上限，非必要別買，先顧吃飯交通。",
                "mid": "提醒他才花這樣就偏快，剩下每天控制好，別月底沒錢吃飯。",
                "lo": "輕鬆提醒別太快把生活費花光，控好節奏就好。",
            },
            "a23_35": {
                "hi": "點出這筆超支等於吃掉本月的存款/投資額度，下個月要補回來。",
                "mid": "提醒他再花下去就守不住『先存後花』，存款目標會破功。",
                "lo": "提醒他花速偏快，小心侵蝕這個月的存錢/投資目標。",
            },
            "a35p": {
                "hi": "提醒他先保住固定支出與家用，把非必要的變動花費先停掉。",
                "mid": "提醒他優先確保家用與固定支出留夠，非必要的先砍。",
                "lo": "提醒他控好變動花費，先確認房租/水電/家用都留得夠。",
            },
        }.get(identity, {"hi": "", "mid": "", "lo": ""})
        _advice_key = "hi" if level >= 100 else ("mid" if level >= 80 else "lo")
        identity_advice = _advice_by_identity.get(_advice_key, "")

        system_prompt = (
            f"你是一個會分析消費數據的記帳管家。\n"
            f"{persona_prompt}\n\n"
            f"【使用者本月消費事實】\n"
            f"{facts}\n"
            f"{insight_focus}\n"
            f"【任務】\n"
            f"{tone}\n"
            f"【身分口吻】{identity_note}\n"  # ★任務2：依身分別微調語氣
            f"【身分建議角度】{identity_advice}\n"  # ★選項B：依身分別微調「行動建議」的切入點
            f"請以【本次要講的重點】為主軸，用你的動物人設講 1~2 句、總共 60 字以內的洞察。\n"
            f"★ 一定要自然地講出【本次要講的重點】裡的『關鍵數字』(例如：月底預估會花到多少元、將超支多少元、或某分類比上月增加百分之幾)，這是這則提醒的核心，不能省略。\n"
            f"其餘數字不用全部念出來，但那個關鍵數字務必提到，並用你的動物語氣自然帶出、不要像在報帳。\n"
            # ★ 新增：如果【使用者本月消費事實】裡有提供「本月最常消費的店家」，優先直接點名這個店家，
            #   會比只講分類名稱(例如「飲食」)更有畫面、更有感，例如「主人你也喝太多星巴克咖啡了吧」這種講法。
            f"★ 如果上面的事實裡有提供『本月最常消費的店家』，請直接點名這個店家的名字來講(例如「你喝太多星巴克」)，"
            f"比起只說分類名稱(例如「飲食」)，直接講出具體店家會讓使用者更有感、更覺得你真的在看他的帳。如果沒有提供店家資訊，才退回用分類名稱講。\n"
            f"請務必回傳 JSON 格式，包含 key: \"comment\"。\n"
        )

        resp = client.chat.completions.create(
            model=MODEL,
            messages=[{"role": "system", "content": system_prompt}],
            response_format={"type": "json_object"},
            temperature=0.8,
        )
        content = json.loads(resp.choices[0].message.content)
        ai_comment = str(content.get("comment", "本月消費分析中..."))

        return jsonify({
            "status": "success",
            "data": {
                "level": level,
                "total_spent": total_spent,
                "budget_remaining": budget_remaining,
                "projected_month_end": projected,
                "top_category": top_cat,
                "ai_comment": ai_comment
            }
        })

    except Exception as e:
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if cursor: cursor.close()
        if conn: conn.close()


# ==========================================
# ★★★ 新增 12) 使用者作息軌跡收集 (Smart Timing) ★★★
# ==========================================
@app.route("/api/log-activity", methods=["POST"])
def log_activity():
    """
    接收前端在特定時刻 (如開啟App、記帳成功) 打過來的時間戳記，存入資料庫作為 AI 學習推播時間的基礎。
    """
    user_id, error_response = get_authenticated_user_id()
    if error_response:
        return error_response

    data = request.get_json(silent=True) or {}
    action_type = str(data.get("action_type", "app_opened")).strip() # 例如 'app_opened' 或 'expense_saved'
    
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO user_activity_logs (user_id, action_type) 
            VALUES (%s, %s)
        """, (user_id, action_type))
        conn.commit()
        
        return jsonify({"status": "success", "message": "活動紀錄已儲存"})
    except Exception as e:
        if conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if cursor: cursor.close()
        if conn: conn.close()


# ==========================================
# ★★★ 新增 9) CSV 載具匯入與 AI 批次分析 ★★★
# ==========================================

def llm_batch_csv_classify(invoices_data: List[Dict], category_map_str: str) -> Dict:
    """一次性將整份 CSV 的發票清單丟給 AI 進行分類"""
    if not invoices_data:
        return {"results": []}

    # 為了批次處理的效率與穩定，隨機挑選一個人設
    selected_animal_key = random.choice(list(ANIMAL_PERSONAS.keys()))
    persona_prompt = ANIMAL_PERSONAS[selected_animal_key].format(nickname="主人")

    system_prompt = (
        f"你是一個專門處理「批次發票匯入」的記帳管家。\n"
        f"{persona_prompt}\n\n"
        f"【任務】\n"
        f"我會給你一個 JSON 格式的發票清單。請根據每張發票的「商家名稱」與「購買品項」，"
        f"參考以下分類地圖，為每一張發票選擇最適合的分類。\n\n"
        f"【個人記憶提示的用法】\n"
        f"每張發票的 JSON 裡可能有一個 memory_hint 欄位：\n"
        f"- 如果 memory_hint 不是空字串，代表這是使用者個人過去的分類習慣，請優先參考這個提示來判斷分類。\n"
        f"- 如果 memory_hint 是空字串，代表沒有個人記憶可以參考，請依照分類地圖跟品項內容自行判斷。\n\n"
        f"【分類地圖】\n{category_map_str}\n\n"
        f"請務必回傳 JSON 格式，必須包含一個 'results' 陣列。"
    )

    schema = {
        "name": "batch_expense_analysis",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "results": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "invoice_number": {"type": "string"},
                            "main_category": {"type": "string", "description": "分類主項目"},
                            "sub_category": {"type": "string", "description": "分類子項目"},
                            "tags": {"type": "array", "items": {"type": "string"}}
                        },
                        "required": ["invoice_number", "main_category", "sub_category", "tags"],
                        "additionalProperties": False
                    }
                }
            },
            "required": ["results"],
            "additionalProperties": False
        }
    }

    try:
        resp = client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": json.dumps(invoices_data, ensure_ascii=False)}
            ],
            response_format={"type": "json_schema", "json_schema": schema},
            temperature=0.6,
        )
        content = resp.choices[0].message.content
        print("✅ 批次 AI 分類完成！")
        return json.loads(content)
    except Exception as e:
        print(f"❌ Batch LLM Error: {e}")
        return {"results": []}


@app.route("/api/import-csv", methods=["POST"])
def import_invoice_csv():
    # ==========================================
    # [資安防護] 身分驗證與權限控管：
    # ==========================================
    user_id = None
    auth_header = request.headers.get('Authorization')
    
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header.split(" ")[1]
        try:
            decoded_token = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
            user_id = decoded_token.get("user_id")
        except Exception as e:
            return jsonify({"status": "error", "message": f"Token 驗證失敗: {str(e)}"}), 401
    else:
        # Flask 接收 FormData 的寫法 (保留向下相容)
        user_id = request.form.get("user_id")

    file = request.files.get("file")

    if not file or not user_id:
        return jsonify({"status": "error", "message": "缺少 user_id 或檔案"}), 400

    print(f"📥 收到來自 User {user_id} 的檔案: {file.filename}")
    contents = file.read()
    
    # 1. 讀取 CSV
    try:
        df = pd.read_csv(io.BytesIO(contents), encoding='utf-8', dtype=str)
    except UnicodeDecodeError:
        try:
            df = pd.read_csv(io.BytesIO(contents), encoding='big5', dtype=str)
        except UnicodeDecodeError:
            try:
                # cp950 = Windows 繁中編碼，比 big5 多支援一些字（Excel 存的 CSV 常是這個）
                df = pd.read_csv(io.BytesIO(contents), encoding='cp950', dtype=str)
            except UnicodeDecodeError:
                try:
                    # big5hkscs = 包含香港增補字集，字最多
                    df = pd.read_csv(io.BytesIO(contents), encoding='big5hkscs', dtype=str)
                except UnicodeDecodeError:
                    # 最後保底：用 utf-8 讀，無法辨識的字元以 � 取代，不再讓伺服器崩潰
                    df = pd.read_csv(io.BytesIO(contents), encoding='utf-8', encoding_errors='replace', dtype=str)

    df.columns = df.columns.str.strip()
    grouped_invoices = df.groupby('發票號碼')
    
    # 2. 整理要餵給 AI 的資料清單
    invoices_for_ai = []
    for invoice_num, group in grouped_invoices:
        merchant = str(group.iloc[0]['賣方名稱'])
        try:
            amount = int(group['消費明細_金額'].astype(float).sum())
        except ValueError:
            amount = 0
            
        items = ", ".join(group['消費明細_品名'].dropna().astype(str).tolist())

        # ★ 新增：CSV 匯入也套用跟掃描/語音記帳同一套個人分類記憶，補上原本沒接的缺口
        csv_memory_keyword = _memory_keyword(user_input="", scanned_content="", known_merchant=merchant)
        csv_memory_hit = _lookup_category_memory(user_id, csv_memory_keyword)
        memory_hint_text = ""
        if csv_memory_hit:
            mem_main = (csv_memory_hit.get("main_category") or "").strip()
            mem_sub = (csv_memory_hit.get("sub_category") or "").strip()
            distinct_count = int(csv_memory_hit.get("distinct_count", 1) or 1)
            if mem_main:
                if distinct_count <= 1:
                    memory_hint_text = (
                        f"使用者過去把「{merchant}」都分類為「{mem_main}/{mem_sub}」，"
                        f"請優先沿用，除非這次品項明顯是不同種類的東西。"
                    )
                else:
                    memory_hint_text = (
                        f"使用者過去對「{merchant}」有多種不同的分類紀錄(複合式店家)，"
                        f"最近一次是「{mem_main}/{mem_sub}」，這僅供參考，請依這次實際品項判斷。"
                    )

        invoices_for_ai.append({
            "invoice_number": invoice_num,
            "merchant": merchant,
            "amount": amount,
            "items": items,
            "memory_hint": memory_hint_text  # ★ 新增：可能是空字串，代表沒有個人記憶可以參考
        })

    print(f"🤖 準備將 {len(invoices_for_ai)} 張發票送交 AI 批次分析...")
    
    # 3. 呼叫 AI 進行批次分類
    category_map_str = build_category_map_str(CATEGORY_TREE, "expense", "unknown")
    ai_results = llm_batch_csv_classify(invoices_for_ai, category_map_str)
    
    # 建立一個字典方便等等寫入資料庫時查閱
    ai_dict = {item['invoice_number']: item for item in ai_results.get("results", [])}

    # 4. 寫入 MySQL 資料庫
    success_invoices = 0
    total_fund_earned = 0
    
    # 準備給全域大總結的資料
    summary_transactions_list = []

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, str(user_id))
        _ensure_gamification_tables(cursor)
        _ensure_app_extension_tables(cursor)
        _backfill_invoice_registry(cursor)
    except Exception as e:
        return jsonify({"status": "error", "message": f"資料庫連線失敗: {str(e)}"}), 500

    try:
        conn.begin()

        for invoice_num, group in grouped_invoices:
            first_row = group.iloc[0]

            normalized_invoice = _normalize_invoice_number(invoice_num)
            reference_key = f'invoice:{normalized_invoice}' if normalized_invoice else f'csv:{str(invoice_num).strip()}'
            if normalized_invoice:
                cursor.execute(
                    """
                    INSERT IGNORE INTO invoice_registry
                        (invoice_number, user_id, status, source)
                    VALUES (%s, %s, 'recorded', 'csv')
                    """,
                    (normalized_invoice, str(user_id))
                )
                if cursor.rowcount != 1:
                    print(f"↩️ 全域重複發票略過，不重複匯入/發資金: {invoice_num}")
                    continue
            cursor.execute(
                """
                SELECT id FROM game_reward_logs
                WHERE user_id = %s AND reward_type = 'land_fund' AND reference_key = %s
                LIMIT 1
                """,
                (str(user_id), reference_key)
            )
            if cursor.fetchone():
                print(f"↩️ 重複發票略過，不重複匯入/發資金: {invoice_num}")
                continue
            
            raw_date = str(first_row['發票日期'])
            if len(raw_date) == 8:
                tx_date_ce = f"{raw_date[:4]}-{raw_date[4:6]}-{raw_date[6:]}"
            else:
                tx_date_ce = raw_date 

            merchant = str(first_row['賣方名稱'])
            try:
                amount = int(group['消費明細_金額'].astype(float).sum())
            except ValueError:
                amount = 0

            # 抓取 AI 針對這筆發票的分析結果
            ai_info = ai_dict.get(invoice_num, {})
            ai_main_cat = ai_info.get("main_category", "其他支出")
            ai_sub_cat = ai_info.get("sub_category", "其他")
            ai_tags = ai_info.get("tags", [])

            # ★ 新增：CSV 匯入決定好最終分類後，也寫回個人分類記憶，
            #   補上原本「CSV 匯入只會讀記憶、不會教記憶」的缺口，跟掃描/語音記帳的行為一致。
            #   CSV 匯入沒有「使用者手動改過」這個動作，所以 corrected 一律傳 False，用一般累加的方式學習。
            csv_upsert_keyword = _memory_keyword(user_input="", scanned_content="", known_merchant=merchant)
            _upsert_category_memory(
                user_id, csv_upsert_keyword, ai_main_cat, ai_sub_cat, corrected=False
            )

            # ---------------------------------------------------------
            # 🛠️ 修正 1：優先拿子分類去查資料庫 ID，確保你的列表顯示與蓋房子精準運作
            # ---------------------------------------------------------
            category_id_to_use = 1 # 預設為 1，以防真的查不到
            try:
                # 優先拿 AI 算出來的「子分類」去資料庫找 ID
                cursor.execute("SELECT id FROM accounting_categories WHERE name = %s LIMIT 1", (ai_sub_cat,))
                cat_row = cursor.fetchone()
                if cat_row:
                    category_id_to_use = cat_row['id']
                else:
                    # 如果找不到子分類，退而求其次找主分類
                    cursor.execute("SELECT id FROM accounting_categories WHERE name = %s LIMIT 1", (ai_main_cat,))
                    cat_row2 = cursor.fetchone()
                    if cat_row2:
                        category_id_to_use = cat_row2['id']
            except Exception as e:
                print(f"⚠️ 查詢分類 ID 失敗，使用預設值 1: {e}")


            # ---------------------------------------------------------
            # 🛠️ 修正 2：完美復刻你 App 原本的備註排版，並移除單筆短評
            # ---------------------------------------------------------
            # 處理標籤 (幫它們加上 # 字符號)
            tags_str = ""
            if isinstance(ai_tags, list) and ai_tags:
                tags_str = " ".join([t if t.startswith("#") else f"#{t}" for t in ai_tags])

            # 抓取發票明細品項
            items_list = group['消費明細_品名'].dropna().astype(str).tolist()
            items_str = "、".join(items_list)
            if len(items_str) > 18:
                items_str = items_str[:18] + "..." # 避免買太多品項塞爆畫面

            # 開始一行一行組裝排版
            note_lines = []
            
            # 【店家名稱】 (加上載具匯入的標示)
            display_merchant = merchant if merchant else "未知店家"
            note_lines.append(f"【{display_merchant}】 (載具匯入)")
            
            # 🛒 購買品項
            if items_str:
                note_lines.append(f"消費 {items_str}")
                
            # 🔍 AI 標籤
            if tags_str:
                note_lines.append(f"{tags_str}")
                
            # 🧾 發票號碼與日期
            if invoice_num:
                note_lines.append(f"{invoice_num} ({tx_date_ce})")

            # 把這些行組合起來變成一段完整的文字
            note_text = "\n".join(note_lines)

            # 將該筆發票紀錄加到全域總結清單
            summary_transactions_list.append(f"- {display_merchant} (分類: {ai_sub_cat}): {amount}元")

            # 最後寫入記帳主檔
            cursor.execute("""
                INSERT INTO accounting_transactions 
                (user_id, amount, type, entry_method, note, date, category_id, currency) 
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (user_id, amount, 'expense', 'csv', note_text, tx_date_ce, category_id_to_use, 'TWD'))
            transaction_id = cursor.lastrowid
            if normalized_invoice:
                cursor.execute(
                    "UPDATE invoice_registry SET transaction_id = %s WHERE invoice_number = %s",
                    (transaction_id, normalized_invoice)
                )

            # 發放大富翁資金（1:1、無上限）並留下可稽核異動紀錄。
            cursor.execute("""
                UPDATE players SET money = COALESCE(money, 0) + %s WHERE user_id = %s
            """, (amount, user_id))
            wallet = _fetch_reward_wallet(cursor, str(user_id))
            _insert_reward_log(
                cursor,
                user_id=str(user_id),
                reward_type='land_fund',
                amount=amount,
                source='csv_import',
                reference_key=reference_key,
                note=f'invoice:{normalized_invoice or invoice_num}',
                balance_after=wallet.get('land_fund'),
            )

            # 載具 CSV 成功匯入即計入任務進度（高權重、已驗證發票）。
            _record_mission_event(
                cursor,
                str(user_id),
                'csv',
                True,
                amount_twd=amount,
                category=ai_sub_cat,
                occurred_at=tx_date_ce,
                unique_hint=normalized_invoice or invoice_num,
            )
            
            success_invoices += 1
            total_fund_earned += amount

        conn.commit()

        # ---------------------------------------------------------
        # 🛠️ 修正 3：呼叫全域總結 API，產生一句大總結回傳給 Flutter
        # ---------------------------------------------------------
        transactions_text = "\n".join(summary_transactions_list)
        global_comment = ""
        if total_fund_earned > 0:
            global_comment = llm_summary_generate(
                transactions_text=transactions_text,
                total_amount=total_fund_earned,
                nickname="主人", # 如果日後有串接名字可以改這裡
                date_text="這批載具匯入發票",
                current_pet="dog"
            )

        return jsonify({
            "status": "success", 
            "message": f"成功匯入 {success_invoices} 張發票", 
            "earned": total_fund_earned,
            "global_comment": global_comment
        })

    except Exception as e:
        conn.rollback() 
        print(f"發生嚴重錯誤: {e}")
        return jsonify({"status": "error", "message": f"處理失敗: {str(e)}"}), 500
    finally:
        # [資安防護] 記憶體主動銷毀
        if 'contents' in locals():
            del contents
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'conn' in locals() and conn:
            conn.close()

# ==========================================
# 10) 個資刪除 API (加入強制 Commit 與 Log 追蹤)
# ==========================================
@app.route("/api/privacy/delete-data", methods=["POST"])
def delete_user_data():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return jsonify({"status": "error", "message": "未授權的操作，缺少 Token"}), 401
    
    token = auth_header.split(" ")[1]
    try:
        decoded_token = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        user_id = decoded_token.get("user_id")
    except Exception as e:
        return jsonify({"status": "error", "message": "Token 無效或已過期"}), 401

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # ★★★ 加入強制印出正在刪除哪個 ID，確保我們沒刪錯人 ★★★
        print(f"🔥 正在強制執行核彈清除，目標 User ID: {user_id}", flush=True)
        
        # 1. 先刪除記帳明細
        cursor.execute("DELETE FROM accounting_transactions WHERE user_id = %s", (user_id,))
        # 2. 刪除大富翁遊戲狀態
        cursor.execute("DELETE FROM players WHERE user_id = %s", (user_id,))
        # 3. 刪除使用者帳號本身 (避免產生幽靈帳號)
        cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))
        
        # ★★★ 關鍵：強制寫入硬碟，不准暫存！ ★★★
        conn.commit()
        
        # 再次檢查資料庫，印出證據
        cursor.execute("SELECT COUNT(*) as count FROM accounting_transactions WHERE user_id = %s", (user_id,))
        remains = cursor.fetchone()['count']
        print(f"✅ 清除完畢！該用戶在 MySQL 剩餘紀錄: {remains} 筆", flush=True)
        
        return jsonify({"status": "success", "message": f"已徹底刪除用戶 {user_id} 的所有資料，符合隱私權規範。"})
    except Exception as e:
        print(f"❌ 刪除資料API崩潰啦，原因是：{e}", flush=True)
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": f"資料刪除失敗: {str(e)}"}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()



# ==========================================
# ★★★ 遊戲化 / 大富翁遊戲資金模組（整合新增，未更動原有程式碼）★★★
# ==========================================

def _get_request_user_id():
    """優先從 JWT 取 user_id，沒有 Token 時才退回 body/form/query 的 user_id。"""
    auth_header = request.headers.get('Authorization')
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header.split(" ")[1]
        decoded_token = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        user_id = decoded_token.get("user_id")
        if user_id:
            return str(user_id)

    data = request.get_json(silent=True) or {}
    user_id = data.get("user_id") or request.form.get("user_id") or request.args.get("user_id")
    return str(user_id).strip() if user_id else None


def _ensure_game_reward_columns(cursor):
    """補齊遊戲化需要的欄位；已存在就不動，避免影響原本資料。"""
    required_columns = {
        "money": "INT DEFAULT 5000",
        "pet_tokens": "INT DEFAULT 0",
        "gacha_coins": "INT DEFAULT 0",
        "pet_choice_tickets": "INT DEFAULT 0",
        "last_login_date": "DATE NULL",
        "login_streak": "INT DEFAULT 0",
    }
    for column, spec in required_columns.items():
        cursor.execute("SHOW COLUMNS FROM players LIKE %s", (column,))
        if not cursor.fetchone():
            cursor.execute(f"ALTER TABLE players ADD COLUMN {column} {spec}")


def _ensure_player_row(cursor, user_id: str):
    _ensure_game_reward_columns(cursor)
    cursor.execute("SELECT user_id FROM players WHERE user_id = %s", (user_id,))
    if not cursor.fetchone():
        cursor.execute(
            """
            INSERT INTO players (user_id, money, pet_tokens, gacha_coins, login_streak)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (user_id, 5000, 0, 0, 0)
        )


def _fetch_reward_wallet(cursor, user_id: str):
    cursor.execute(
        """
        SELECT user_id, money, pet_tokens, gacha_coins, pet_choice_tickets,
               last_login_date, login_streak
        FROM players
        WHERE user_id = %s
        LIMIT 1
        """,
        (user_id,)
    )
    row = cursor.fetchone() or {}
    return {
        "user_id": row.get("user_id"),
        "land_fund": int(row.get("money") or 0),
        "money": int(row.get("money") or 0),
        "pet_tokens": int(row.get("pet_tokens") or 0),
        "gacha_coins": int(row.get("gacha_coins") or 0),
        "pet_choice_tickets": int(row.get("pet_choice_tickets") or 0),
        "last_login_date": str(row.get("last_login_date") or ""),
        "login_streak": int(row.get("login_streak") or 0),
    }


def _ensure_gamification_tables(cursor):
    """只新增遊戲化需要的事件/任務表，不改動原本交易與寵物資料。"""
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS game_mission_events (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            event_type VARCHAR(64) NOT NULL,
            source VARCHAR(64) NOT NULL DEFAULT 'app',
            is_invoice TINYINT(1) NOT NULL DEFAULT 0,
            amount_twd DECIMAL(12,2) NULL,
            category_key VARCHAR(160) NULL,
            occurred_at DATETIME NULL,
            dedup_key CHAR(64) NULL,
            event_date DATE NOT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_gme_user_date (user_id, event_date),
            INDEX idx_gme_user_type (user_id, event_type),
            INDEX idx_gme_user_dedup (user_id, dedup_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    # 舊資料庫可能已經有任務表，逐欄補齊即可，不會刪除既有進度。
    event_columns = {
        'amount_twd': 'DECIMAL(12,2) NULL',
        'category_key': 'VARCHAR(160) NULL',
        'occurred_at': 'DATETIME NULL',
        'dedup_key': 'CHAR(64) NULL',
    }
    for column, spec in event_columns.items():
        cursor.execute("SHOW COLUMNS FROM game_mission_events LIKE %s", (column,))
        if not cursor.fetchone():
            cursor.execute(f"ALTER TABLE game_mission_events ADD COLUMN {column} {spec}")
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS game_mission_claims (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            mission_id VARCHAR(64) NOT NULL,
            period_key VARCHAR(32) NOT NULL,
            reward_amount INT NOT NULL DEFAULT 0,
            claimed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_gmc_user_mission_period (user_id, mission_id, period_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS game_reward_logs (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            reward_type VARCHAR(32) NOT NULL,
            amount INT NOT NULL,
            source VARCHAR(64) NOT NULL DEFAULT 'app',
            reference_key VARCHAR(160) NULL,
            note VARCHAR(255) NULL,
            balance_after INT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_grl_user_reward_ref (user_id, reward_type, reference_key),
            INDEX idx_grl_user_created (user_id, created_at),
            INDEX idx_grl_type_source (reward_type, source)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS game_monthly_budgets (
            user_id VARCHAR(64) NOT NULL,
            month_key CHAR(7) NOT NULL,
            amount DECIMAL(12,2) NOT NULL,
            set_day TINYINT NOT NULL,
            eligible TINYINT(1) NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, month_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS game_pet_choice_unlocks (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            species_key VARCHAR(64) NOT NULL,
            species_name VARCHAR(80) NOT NULL,
            source VARCHAR(64) NOT NULL DEFAULT 'pet_choice_ticket',
            unlocked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_gpcu_user_species (user_id, species_key),
            INDEX idx_gpcu_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS game_demo_purchases (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            package_id VARCHAR(64) NOT NULL,
            display_price_twd INT NOT NULL,
            ticket_quantity INT NOT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_gdp_user_created (user_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


def _normalize_invoice_number(value):
    raw = re.sub(r'[^A-Z0-9]', '', str(value or '').upper())
    match = re.search(r'[A-Z]{2}\d{8}', raw)
    return match.group(0) if match else ''


def _ensure_app_extension_tables(cursor):
    """建立本次功能需要的附加表；不修改既有旅行幣別或交易主表結構。"""
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS transaction_payment_metadata (
            transaction_id BIGINT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            purchase_amount DECIMAL(18, 4) NOT NULL,
            currency VARCHAR(8) NOT NULL DEFAULT 'TWD',
            is_foreign_card TINYINT(1) NOT NULL DEFAULT 0,
            foreign_fee_rate DECIMAL(10, 6) NOT NULL DEFAULT 0,
            foreign_fee_amount_twd DECIMAL(18, 4) NOT NULL DEFAULT 0,
            exchange_rate_to_twd DECIMAL(18, 8) NOT NULL DEFAULT 1,
            exchange_rate_source VARCHAR(120) NULL,
            exchange_rate_type VARCHAR(80) NULL,
            exchange_rate_date DATE NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_tpm_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS game_monthly_budgets (
            user_id VARCHAR(64) NOT NULL,
            month_key CHAR(7) NOT NULL,
            amount DECIMAL(12,2) NOT NULL,
            set_day TINYINT NOT NULL,
            eligible TINYINT(1) NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, month_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS invoice_registry (
            invoice_number VARCHAR(10) PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            status ENUM('pending', 'recorded') NOT NULL DEFAULT 'pending',
            claim_token VARCHAR(96) NULL,
            expires_at DATETIME NULL,
            transaction_id BIGINT NULL,
            source VARCHAR(32) NOT NULL DEFAULT 'scan',
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_ir_user (user_id),
            INDEX idx_ir_status_expiry (status, expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS recurring_transactions_app (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id VARCHAR(64) NOT NULL,
            direction ENUM('expense', 'income') NOT NULL,
            category_name VARCHAR(120) NOT NULL,
            amount DECIMAL(18, 4) NOT NULL,
            currency VARCHAR(8) NOT NULL DEFAULT 'TWD',
            note VARCHAR(255) NULL,
            cadence ENUM('weekly', 'monthly', 'yearly') NOT NULL,
            start_date DATE NOT NULL,
            next_run_date DATE NOT NULL,
            end_date DATE NULL,
            is_active TINYINT(1) NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_rta_user_active (user_id, is_active),
            INDEX idx_rta_due (is_active, next_run_date)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS recurring_transaction_runs (
            rule_id BIGINT NOT NULL,
            scheduled_date DATE NOT NULL,
            transaction_id BIGINT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (rule_id, scheduled_date)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


def _backfill_invoice_registry(cursor):
    """把舊版獎勵紀錄與 receipts 補入全域索引；重跑安全。"""
    _ensure_gamification_tables(cursor)
    cursor.execute(
        """
        SELECT user_id, reference_key, source
        FROM game_reward_logs
        WHERE reward_type = 'land_fund' AND reference_key LIKE 'invoice:%'
        """
    )
    for row in cursor.fetchall() or []:
        invoice = _normalize_invoice_number(str(row.get('reference_key') or '').split(':', 1)[-1])
        if not invoice:
            continue
        cursor.execute(
            """
            INSERT IGNORE INTO invoice_registry
                (invoice_number, user_id, status, source)
            VALUES (%s, %s, 'recorded', %s)
            """,
            (invoice, str(row.get('user_id')), str(row.get('source') or 'legacy')[:32])
        )

    # 部分舊資料可能曾成功記帳、但遊戲獎勵送出失敗；再從 receipts 補一次。
    try:
        cursor.execute("SHOW TABLES LIKE 'receipts'")
        if not cursor.fetchone():
            return
        cursor.execute("SHOW COLUMNS FROM receipts")
        columns = {str(row.get('Field')) for row in (cursor.fetchall() or [])}
        invoice_col = next((name for name in ('invoice_number', 'invoice_no') if name in columns), None)
        if not invoice_col:
            return
        select_parts = [f"{invoice_col} AS invoice_number"]
        select_parts.append("user_id" if 'user_id' in columns else "'legacy' AS user_id")
        select_parts.append("transaction_id" if 'transaction_id' in columns else "NULL AS transaction_id")
        cursor.execute(
            f"SELECT {', '.join(select_parts)} FROM receipts WHERE {invoice_col} IS NOT NULL"
        )
        for row in cursor.fetchall() or []:
            invoice = _normalize_invoice_number(row.get('invoice_number'))
            if not invoice:
                continue
            cursor.execute(
                """
                INSERT IGNORE INTO invoice_registry
                    (invoice_number, user_id, status, transaction_id, source)
                VALUES (%s, %s, 'recorded', %s, 'legacy_receipt')
                """,
                (invoice, str(row.get('user_id') or 'legacy'), row.get('transaction_id'))
            )
    except Exception as e:
        # 舊版 receipts 欄位若與預期不同，不影響新的全域唯一檢查。
        print(f'⚠️ receipts 發票索引補登略過: {e}')


def _parse_iso_date(value, field_name, required=False):
    raw = str(value or '').strip()
    if not raw:
        if required:
            raise ValueError(f'缺少 {field_name}')
        return None
    try:
        return datetime.strptime(raw[:10], '%Y-%m-%d').date()
    except ValueError:
        raise ValueError(f'{field_name} 必須是 YYYY-MM-DD')


def _next_recurring_date(current_date, cadence, anchor_date=None):
    anchor = anchor_date or current_date
    if cadence == 'weekly':
        return current_date + timedelta(days=7)
    if cadence == 'monthly':
        year = current_date.year + (1 if current_date.month == 12 else 0)
        month = 1 if current_date.month == 12 else current_date.month + 1
        day = min(anchor.day, calendar.monthrange(year, month)[1])
        return date(year, month, day)
    year = current_date.year + 1
    month = anchor.month
    day = min(anchor.day, calendar.monthrange(year, month)[1])
    return date(year, month, day)


def _recurring_row_json(row):
    return {
        'id': int(row.get('id')),
        'direction': row.get('direction'),
        'category_name': row.get('category_name'),
        'amount': float(row.get('amount') or 0),
        'currency': row.get('currency') or 'TWD',
        'note': row.get('note') or '',
        'cadence': row.get('cadence'),
        'start_date': str(row.get('start_date') or ''),
        'next_run_date': str(row.get('next_run_date') or ''),
        'end_date': str(row.get('end_date') or ''),
        'is_active': bool(row.get('is_active')),
    }


def _normalize_reward_reference(value):
    raw = str(value or '').strip()
    if not raw:
        return None
    if raw.lower().startswith('invoice:'):
        inv = _normalize_invoice_number(raw.split(':', 1)[1])
        return f'invoice:{inv}' if inv else None
    return raw[:160]


def _insert_reward_log(cursor, *, user_id, reward_type, amount, source,
                       reference_key=None, note=None, balance_after=None):
    cursor.execute(
        """
        INSERT INTO game_reward_logs
            (user_id, reward_type, amount, source, reference_key, note, balance_after)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (
            str(user_id), str(reward_type), int(amount), str(source or 'app'),
            _normalize_reward_reference(reference_key),
            (str(note)[:255] if note is not None else None),
            (int(balance_after) if balance_after is not None else None),
        )
    )


def _parse_mission_datetime(value):
    if isinstance(value, datetime):
        return value
    text = str(value or '').strip()
    if not text:
        return datetime.now()
    try:
        return datetime.fromisoformat(text.replace('Z', '+00:00')).replace(tzinfo=None)
    except ValueError:
        try:
            return datetime.strptime(text[:10], '%Y-%m-%d')
        except ValueError:
            return datetime.now()


def _mission_category_key(value):
    return re.sub(r'\s+', ' ', str(value or '未分類').strip().lower())[:160]


def _record_mission_event(
    cursor,
    user_id: str,
    source: str,
    is_invoice: bool = False,
    *,
    event_type: str = 'expense_recorded',
    amount_twd=None,
    category=None,
    occurred_at=None,
    unique_hint=None,
):
    """新增任務事件；回傳 False 代表同金額、分類、分鐘的重複記錄。"""
    now = datetime.now()
    event_day = now.date()  # 活躍任務以實際使用 App 的日期計算，不接受回填日期刷連續天數。
    occurred = _parse_mission_datetime(occurred_at)
    category_key = _mission_category_key(category)
    amount_value = None

    if event_type == 'expense_recorded':
        try:
            amount_value = round(float(amount_twd or 0), 2)
        except (TypeError, ValueError):
            amount_value = 0.0
        minute_key = occurred.strftime('%Y-%m-%dT%H:%M')
        fingerprint_source = (
            f"{user_id}|expense|{amount_value:.2f}|{category_key}|{minute_key}"
        )
        # 已驗證發票可用發票號碼區分同分鐘、同金額、同分類的真實消費。
        if unique_hint:
            fingerprint_source += f"|{str(unique_hint).strip().lower()}"
    elif event_type == 'report_viewed':
        fingerprint_source = f"{user_id}|report|{event_day.isoformat()}"
        occurred = now
    else:
        raise ValueError('未知的任務事件')

    dedup_key = hashlib.sha256(fingerprint_source.encode('utf-8')).hexdigest()
    cursor.execute(
        """
        SELECT id FROM game_mission_events
        WHERE user_id = %s AND dedup_key = %s
        LIMIT 1
        """,
        (user_id, dedup_key)
    )
    if cursor.fetchone():
        return False

    cursor.execute(
        """
        INSERT INTO game_mission_events
            (user_id, event_type, source, is_invoice, amount_twd,
             category_key, occurred_at, dedup_key, event_date)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            user_id, event_type, source or 'app', 1 if is_invoice else 0,
            amount_value, category_key, occurred, dedup_key, event_day,
        )
    )
    return True


def _week_bounds(day_value: date):
    start = day_value - timedelta(days=day_value.weekday())
    end = start + timedelta(days=6)
    return start, end


def _previous_month_bounds(day_value: date):
    first_this = date(day_value.year, day_value.month, 1)
    last_previous = first_this - timedelta(days=1)
    first_previous = date(last_previous.year, last_previous.month, 1)
    return first_previous, first_this


def _mission_period_key(mission_id: str, today_value: date):
    if mission_id.startswith('monthly_records_30_'):
        return today_value.strftime('%Y-%m')
    if mission_id == 'weekly_record_5_days':
        iso_year, iso_week, _ = today_value.isocalendar()
        return f"{iso_year}-W{iso_week:02d}"
    if mission_id == 'monthly_budget_ok':
        previous_start, _ = _previous_month_bounds(today_value)
        return previous_start.strftime('%Y-%m')
    return 'once'


def _current_activity_streak(activity_days, today_value: date):
    days = sorted(set(activity_days), reverse=True)
    if not days:
        return 0, None
    latest = days[0]
    if latest < today_value - timedelta(days=1):
        return 0, None
    streak = 1
    cursor_day = latest
    for candidate in days[1:]:
        if candidate == cursor_day - timedelta(days=1):
            streak += 1
            cursor_day = candidate
        elif candidate < cursor_day - timedelta(days=1):
            break
    return streak, cursor_day


def _mission_progress(cursor, user_id: str):
    _ensure_player_row(cursor, user_id)
    _ensure_gamification_tables(cursor)
    today_value = date.today()
    week_start, week_end = _week_bounds(today_value)

    month_start = date(today_value.year, today_value.month, 1)
    if today_value.month == 12:
        month_end = date(today_value.year + 1, 1, 1)
    else:
        month_end = date(today_value.year, today_value.month + 1, 1)

    cursor.execute(
        """
        SELECT COUNT(*) AS c
        FROM game_mission_events
        WHERE user_id = %s AND event_type = 'expense_recorded'
          AND COALESCE(occurred_at, created_at) >= %s
          AND COALESCE(occurred_at, created_at) < %s
        """,
        (user_id, month_start, month_end)
    )
    monthly_records = int((cursor.fetchone() or {}).get('c') or 0)

    cursor.execute(
        """
        SELECT COUNT(DISTINCT event_date) AS c
        FROM game_mission_events
        WHERE user_id = %s AND event_type = 'expense_recorded'
          AND event_date BETWEEN %s AND %s
        """,
        (user_id, week_start, week_end)
    )
    weekly_record_days = int((cursor.fetchone() or {}).get('c') or 0)

    cursor.execute(
        """
        SELECT DISTINCT event_date
        FROM game_mission_events
        WHERE user_id = %s
          AND event_type IN ('expense_recorded', 'report_viewed')
          AND event_date >= %s
        ORDER BY event_date DESC
        """,
        (user_id, today_value - timedelta(days=60))
    )
    activity_days = [row.get('event_date') for row in (cursor.fetchall() or []) if row.get('event_date')]
    streak, streak_start = _current_activity_streak(activity_days, today_value)

    cursor.execute(
        "SELECT COUNT(*) AS c FROM game_monthly_budgets WHERE user_id = %s",
        (user_id,)
    )
    has_budget = int((cursor.fetchone() or {}).get('c') or 0) > 0

    previous_start, previous_end = _previous_month_bounds(today_value)
    previous_key = previous_start.strftime('%Y-%m')
    cursor.execute(
        """
        SELECT amount, set_day, eligible
        FROM game_monthly_budgets
        WHERE user_id = %s AND month_key = %s
        LIMIT 1
        """,
        (user_id, previous_key)
    )
    previous_budget = cursor.fetchone()
    cursor.execute(
        """
        SELECT COUNT(*) AS record_count,
               COUNT(DISTINCT DATE(COALESCE(occurred_at, created_at))) AS record_days,
               COALESCE(SUM(amount_twd), 0) AS spent
        FROM game_mission_events
        WHERE user_id = %s AND event_type = 'expense_recorded'
          AND COALESCE(occurred_at, created_at) >= %s
          AND COALESCE(occurred_at, created_at) < %s
        """,
        (user_id, previous_start, previous_end)
    )
    previous_stats = cursor.fetchone() or {}
    previous_count = int(previous_stats.get('record_count') or 0)
    previous_days = int(previous_stats.get('record_days') or 0)
    previous_spent = float(previous_stats.get('spent') or 0)
    budget_ok = bool(
        previous_budget
        and int(previous_budget.get('eligible') or 0) == 1
        and int(previous_budget.get('set_day') or 99) <= 7
        and previous_count >= 15
        and previous_days >= 10
        and previous_spent <= float(previous_budget.get('amount') or 0)
    )

    raw = []
    for cycle in range(1, 4):
        cycle_progress = max(0, monthly_records - ((cycle - 1) * 30))
        raw.append({
            'id': f'monthly_records_30_{cycle}',
            'title': f'累積記帳 30 筆（本月第 {cycle} 次）',
            'description': '相同金額、類別與分鐘的重複紀錄不計；每月最多領 3 次。',
            'progress': cycle_progress,
            'goal': 30,
            'reward': 1,
        })
    raw.extend([
        {
            'id': 'active_streak_7',
            'title': '連續使用 7 天',
            'description': '每天至少記帳 1 筆或查看 1 次週報。',
            'progress': streak,
            'goal': 7,
            'reward': 1,
            'period_key': f"streak:{streak_start.isoformat()}" if streak_start else 'streak:none',
        },
        {
            'id': 'weekly_record_5_days',
            'title': '完成一週記帳',
            'description': '本週至少有 5 個不同日期完成記帳。',
            'progress': weekly_record_days,
            'goal': 5,
            'reward': 1,
        },
        {
            'id': 'first_monthly_budget',
            'title': '首次設定月預算',
            'description': '一次性新手任務。',
            'progress': 1 if has_budget else 0,
            'goal': 1,
            'reward': 1,
        },
        {
            'id': 'monthly_budget_ok',
            'title': f'{previous_key} 花費在預算內',
            'description': '預算須在每月 7 日前設定，且該月至少記帳 15 筆、涵蓋 10 天。',
            'progress': 1 if budget_ok else 0,
            'goal': 1,
            'reward': 3,
            'period_key': previous_key,
            'details': {
                'record_count': previous_count,
                'record_days': previous_days,
                'spent': previous_spent,
                'budget': float(previous_budget.get('amount') or 0) if previous_budget else 0,
            },
        },
    ])

    missions = []
    for item in raw:
        period_key = item.get('period_key') or _mission_period_key(item['id'], today_value)
        cursor.execute(
            """
            SELECT 1 FROM game_mission_claims
            WHERE user_id = %s AND mission_id = %s AND period_key = %s
            LIMIT 1
            """,
            (user_id, item['id'], period_key)
        )
        claimed = cursor.fetchone() is not None
        progress = int(item['progress'])
        goal = int(item['goal'])
        missions.append({
            **item,
            'progress': min(progress, goal),
            'completed': progress >= goal,
            'claimed': claimed,
            'period_key': period_key,
        })
    return missions


@app.get("/api/game/wallet")
def game_wallet():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        wallet = _fetch_reward_wallet(cursor, user_id)
        conn.commit()
        return jsonify({"status": "success", **wallet})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


PET_CHOICE_CATALOG = {
    'dog': '狗狗',
    'cat': '貓咪',
    'parrot': '鸚鵡',
    'sloth': '樹懶',
    'fox': '狐狸',
    'cute_dog': '柴柴',
    'pomeranian': '博美犬',
    'norm_dog': '諾姆犬',
    'wagging_dog': '甩尾狗',
    'lovely_cat': '愛心貓',
    'blue_cat': '工作貓',
    'loader_cat': '等待貓',
    'rocket_cat': '火箭貓',
    'bear': '熊熊',
    'bee': '蜜蜂',
    'giraffe': '長頸鹿',
}


def _fetch_ticket_pets(cursor, user_id: str):
    cursor.execute(
        """
        SELECT id, species_key, species_name, source, unlocked_at
        FROM game_pet_choice_unlocks
        WHERE user_id = %s
        ORDER BY id
        """,
        (user_id,)
    )
    return cursor.fetchall() or []


@app.get("/api/game/pet-choice")
def pet_choice_state():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        wallet = _fetch_reward_wallet(cursor, user_id)
        pets = _fetch_ticket_pets(cursor, user_id)
        conn.commit()
        return jsonify({
            "status": "success",
            "catalog": [
                {"species_key": key, "species_name": name}
                for key, name in PET_CHOICE_CATALOG.items()
            ],
            "pets": pets,
            **wallet,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/game/pet-choice/purchase")
def purchase_pet_choice_ticket():
    """專題展示用模擬付款：固定 NT$200 取得一張寵物自選券。"""
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        package_id = str(data.get('package_id') or '').strip()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        if package_id != 'pet_ticket_200':
            return jsonify({"status": "error", "message": "未知的自選券方案"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        cursor.execute(
            """
            UPDATE players
            SET pet_choice_tickets = COALESCE(pet_choice_tickets, 0) + 1
            WHERE user_id = %s
            """,
            (user_id,)
        )
        cursor.execute(
            """
            INSERT INTO game_demo_purchases
                (user_id, package_id, display_price_twd, ticket_quantity)
            VALUES (%s, %s, 200, 1)
            """,
            (user_id, package_id)
        )
        wallet = _fetch_reward_wallet(cursor, user_id)
        _insert_reward_log(
            cursor,
            user_id=user_id,
            reward_type='pet_choice_ticket',
            amount=1,
            source='demo_purchase',
            note='NT$200 模擬付款',
            balance_after=wallet.get('pet_choice_tickets'),
        )
        conn.commit()
        return jsonify({
            "status": "success",
            "demo": True,
            "charged": False,
            "display_price_twd": 200,
            "earned_pet_choice_tickets": 1,
            **wallet,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/game/pet-choice/redeem")
def redeem_pet_choice_ticket():
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        species_key = str(data.get('species_key') or '').strip()
        species_name = PET_CHOICE_CATALOG.get(species_key)
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        if species_name is None:
            return jsonify({"status": "error", "message": "找不到此寵物"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        cursor.execute(
            """
            SELECT COALESCE(pet_choice_tickets, 0) AS balance
            FROM players WHERE user_id = %s FOR UPDATE
            """,
            (user_id,)
        )
        balance = int((cursor.fetchone() or {}).get('balance') or 0)
        if balance < 1:
            conn.rollback()
            return jsonify({"status": "error", "message": "寵物自選券不足"}), 400

        cursor.execute(
            """
            SELECT id FROM game_pet_choice_unlocks
            WHERE user_id = %s AND species_key = %s
            LIMIT 1
            """,
            (user_id, species_key)
        )
        if cursor.fetchone():
            conn.rollback()
            return jsonify({"status": "error", "message": "這隻寵物已經擁有"}), 409

        cursor.execute(
            """
            INSERT INTO game_pet_choice_unlocks
                (user_id, species_key, species_name)
            VALUES (%s, %s, %s)
            """,
            (user_id, species_key, species_name)
        )
        pet_id = cursor.lastrowid
        cursor.execute(
            """
            UPDATE players
            SET pet_choice_tickets = pet_choice_tickets - 1
            WHERE user_id = %s
            """,
            (user_id,)
        )
        wallet = _fetch_reward_wallet(cursor, user_id)
        _insert_reward_log(
            cursor,
            user_id=user_id,
            reward_type='pet_choice_ticket',
            amount=-1,
            source='pet_choice_redeem',
            note=species_key,
            balance_after=wallet.get('pet_choice_tickets'),
        )
        conn.commit()
        return jsonify({
            "status": "success",
            "pet": {
                "id": pet_id,
                "species_key": species_key,
                "species_name": species_name,
                "name": species_name,
                "source": "pet_choice_ticket",
            },
            **wallet,
        })
    except pymysql.err.IntegrityError:
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": "這隻寵物已經擁有"}), 409
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/game/reward")
def game_reward():
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        reward_type = str(data.get("reward_type", "")).strip()
        amount = int(float(data.get("amount", 0) or 0))
        source = str(data.get("source", "app")).strip() or 'app'
        note = data.get("note")
        reference_key = _normalize_reward_reference(data.get("reference_key"))

        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        if amount <= 0:
            return jsonify({"status": "error", "message": "獎勵金額必須大於 0"}), 400

        reward_columns = {
            "land_fund": ("money", "地產資金"),
            "pet_tokens": ("pet_tokens", "寵物代幣"),
        }
        if reward_type not in reward_columns:
            return jsonify({"status": "error", "message": "未知的 reward_type"}), 400

        column, display_name = reward_columns[reward_type]
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        _ensure_app_extension_tables(cursor)

        if reward_type == 'land_fund' and reference_key and reference_key.startswith('invoice:'):
            invoice = _normalize_invoice_number(reference_key.split(':', 1)[1])
            cursor.execute(
                'SELECT user_id, status FROM invoice_registry WHERE invoice_number = %s LIMIT 1',
                (invoice,)
            )
            registered = cursor.fetchone()
            if registered and str(registered.get('user_id')) != str(user_id):
                conn.rollback()
                return jsonify({
                    'status': 'error',
                    'message': '此發票已被記錄',
                    'duplicate': True,
                }), 409

        # 有 reference_key 的獎勵（例如同一張發票）只能發一次。
        if reference_key:
            cursor.execute(
                """
                SELECT id FROM game_reward_logs
                WHERE user_id = %s AND reward_type = %s AND reference_key = %s
                LIMIT 1
                """,
                (user_id, reward_type, reference_key)
            )
            if cursor.fetchone():
                wallet = _fetch_reward_wallet(cursor, user_id)
                conn.commit()
                return jsonify({
                    "status": "success",
                    "duplicate": True,
                    "reward_type": reward_type,
                    "reward_name": display_name,
                    "earned": 0,
                    "source": source,
                    "reference_key": reference_key,
                    **wallet,
                })

        cursor.execute(
            f"UPDATE players SET {column} = COALESCE({column}, 0) + %s WHERE user_id = %s",
            (amount, user_id)
        )
        wallet = _fetch_reward_wallet(cursor, user_id)
        balance_after = int(wallet.get('land_fund' if reward_type == 'land_fund' else reward_type) or 0)

        try:
            _insert_reward_log(
                cursor,
                user_id=user_id,
                reward_type=reward_type,
                amount=amount,
                source=source,
                reference_key=reference_key,
                note=note,
                balance_after=balance_after,
            )
        except pymysql.err.IntegrityError:
            # 極短時間內重複送出時，unique key 仍會擋住第二次。
            conn.rollback()
            conn = get_db_connection()
            cursor = conn.cursor()
            _ensure_player_row(cursor, user_id)
            wallet = _fetch_reward_wallet(cursor, user_id)
            conn.commit()
            return jsonify({
                "status": "success",
                "duplicate": True,
                "reward_type": reward_type,
                "reward_name": display_name,
                "earned": 0,
                "source": source,
                "reference_key": reference_key,
                **wallet,
            })

        conn.commit()
        return jsonify({
            "status": "success",
            "duplicate": False,
            "reward_type": reward_type,
            "reward_name": display_name,
            "earned": amount,
            "source": source,
            "reference_key": reference_key,
            **wallet,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.get("/api/game/reward-logs")
def game_reward_logs():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        limit = max(1, min(int(request.args.get('limit', 50)), 200))

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        cursor.execute(
            """
            SELECT id, user_id, reward_type, amount, source,
                   reference_key, note, balance_after, created_at
            FROM game_reward_logs
            WHERE user_id = %s
            ORDER BY id DESC
            LIMIT %s
            """,
            (user_id, limit)
        )
        rows = cursor.fetchall() or []
        conn.commit()
        return jsonify({"status": "success", "logs": rows})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.get("/api/game/invoice-status")
def game_invoice_status():
    try:
        user_id = _get_request_user_id()
        invoice_number = _normalize_invoice_number(request.args.get('invoice_number'))
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        if not invoice_number:
            return jsonify({"status": "error", "message": "發票號碼格式無效"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)
        _backfill_invoice_registry(cursor)
        cursor.execute(
            """
            SELECT invoice_number, status, expires_at, created_at
            FROM invoice_registry
            WHERE invoice_number = %s
            LIMIT 1
            """,
            (invoice_number,)
        )
        row = cursor.fetchone()
        already_recorded = False
        if row:
            already_recorded = row.get('status') == 'recorded'
            if row.get('status') == 'pending':
                expiry = row.get('expires_at')
                already_recorded = bool(expiry and expiry > datetime.now())
        conn.commit()
        return jsonify({
            "status": "success",
            "invoice_number": invoice_number,
            "already_rewarded": already_recorded,
            "already_recorded": already_recorded,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/game/spend")
def game_spend():
    """扣除寵物代幣或扭蛋幣；餘額不足時不扣款。"""
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        reward_type = str(data.get("reward_type", "")).strip()
        amount = int(float(data.get("amount", 0) or 0))
        source = str(data.get("source", "app")).strip()

        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        if amount <= 0:
            return jsonify({"status": "error", "message": "扣除金額必須大於 0"}), 400

        spend_columns = {
            "pet_tokens": ("pet_tokens", "寵物代幣"),
            "gacha_coins": ("gacha_coins", "扭蛋幣"),
        }
        if reward_type not in spend_columns:
            return jsonify({"status": "error", "message": "此資源不可由此 API 扣除"}), 400

        column, display_name = spend_columns[reward_type]
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        cursor.execute(
            f"SELECT COALESCE({column}, 0) AS balance FROM players WHERE user_id = %s FOR UPDATE",
            (user_id,)
        )
        balance = int((cursor.fetchone() or {}).get("balance") or 0)
        if balance < amount:
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": f"{display_name}不足",
                "balance": balance,
                "required": amount,
            }), 400

        cursor.execute(
            f"UPDATE players SET {column} = COALESCE({column}, 0) - %s WHERE user_id = %s",
            (amount, user_id)
        )
        wallet = _fetch_reward_wallet(cursor, user_id)
        balance_after = int(wallet.get(reward_type) or 0)
        _insert_reward_log(
            cursor,
            user_id=user_id,
            reward_type=reward_type,
            amount=-amount,
            source=source,
            note='spend',
            balance_after=balance_after,
        )
        conn.commit()
        return jsonify({
            "status": "success",
            "spent_type": reward_type,
            "spent_name": display_name,
            "spent": amount,
            "source": source,
            **wallet,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/game/mission-event")
def game_mission_event():
    """記錄有效記帳或查看報表；登入本身不計入活躍任務。"""
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        event_type = str(data.get('event_type', '')).strip()
        source = str(data.get('source', 'app')).strip() or 'app'
        is_invoice = bool(data.get('is_invoice', False))
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        if event_type not in {'expense_recorded', 'report_viewed'}:
            return jsonify({"status": "error", "message": "未知的任務事件"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        inserted = _record_mission_event(
            cursor,
            user_id,
            source,
            is_invoice,
            event_type=event_type,
            amount_twd=data.get('amount_twd'),
            category=data.get('category'),
            occurred_at=data.get('occurred_at'),
            unique_hint=data.get('unique_hint'),
        )
        missions = _mission_progress(cursor, user_id)
        conn.commit()
        return jsonify({"status": "success", "counted": inserted, "missions": missions})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.get("/api/game/missions")
def game_missions():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400
        conn = get_db_connection()
        cursor = conn.cursor()
        missions = _mission_progress(cursor, user_id)
        wallet = _fetch_reward_wallet(cursor, user_id)
        conn.commit()
        return jsonify({"status": "success", "missions": missions, **wallet})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/game/missions/<mission_id>/claim")
def claim_game_mission(mission_id):
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        missions = _mission_progress(cursor, user_id)
        mission = next((m for m in missions if m['id'] == mission_id), None)
        if mission is None:
            return jsonify({"status": "error", "message": "找不到任務"}), 404
        if mission['claimed']:
            return jsonify({"status": "error", "message": "此任務獎勵已領取"}), 409
        if not mission['completed']:
            return jsonify({"status": "error", "message": "任務尚未完成"}), 400

        reward = int(mission['reward'])
        try:
            cursor.execute(
                """
                INSERT INTO game_mission_claims
                    (user_id, mission_id, period_key, reward_amount)
                VALUES (%s, %s, %s, %s)
                """,
                (user_id, mission_id, mission['period_key'], reward)
            )
        except pymysql.err.IntegrityError:
            conn.rollback()
            return jsonify({"status": "error", "message": "此任務獎勵已領取"}), 409

        cursor.execute(
            "UPDATE players SET gacha_coins = COALESCE(gacha_coins, 0) + %s WHERE user_id = %s",
            (reward, user_id)
        )
        wallet = _fetch_reward_wallet(cursor, user_id)
        _insert_reward_log(
            cursor,
            user_id=user_id,
            reward_type='gacha_coins',
            amount=reward,
            source='mission_claim',
            reference_key=f"mission:{mission_id}:{mission['period_key']}",
            note=mission_id,
            balance_after=wallet.get('gacha_coins'),
        )
        conn.commit()
        return jsonify({
            "status": "success",
            "mission_id": mission_id,
            "earned_gacha_coins": reward,
            **wallet,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.put("/api/transactions/<int:transaction_id>/payment-metadata")
def upsert_transaction_payment_metadata(transaction_id):
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        if not user_id:
            return jsonify({'status': 'error', 'message': '缺少 user_id'}), 400
        currency = str(data.get('currency') or 'TWD').upper()
        if currency not in {'TWD', 'USD', 'JPY', 'KRW', 'CNY'}:
            return jsonify({'status': 'error', 'message': '不支援的幣別'}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)
        cursor.execute(
            'SELECT id FROM accounting_transactions WHERE id = %s AND user_id = %s LIMIT 1',
            (transaction_id, user_id)
        )
        if not cursor.fetchone():
            conn.rollback()
            return jsonify({'status': 'error', 'message': '找不到這筆交易'}), 404
        cursor.execute(
            """
            INSERT INTO transaction_payment_metadata
                (transaction_id, user_id, purchase_amount, currency,
                 is_foreign_card, foreign_fee_rate, foreign_fee_amount_twd,
                 exchange_rate_to_twd, exchange_rate_source,
                 exchange_rate_type, exchange_rate_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
                purchase_amount = VALUES(purchase_amount),
                currency = VALUES(currency),
                is_foreign_card = VALUES(is_foreign_card),
                foreign_fee_rate = VALUES(foreign_fee_rate),
                foreign_fee_amount_twd = VALUES(foreign_fee_amount_twd),
                exchange_rate_to_twd = VALUES(exchange_rate_to_twd),
                exchange_rate_source = VALUES(exchange_rate_source),
                exchange_rate_type = VALUES(exchange_rate_type),
                exchange_rate_date = VALUES(exchange_rate_date)
            """,
            (
                transaction_id, user_id, float(data.get('purchase_amount') or 0), currency,
                1 if data.get('is_foreign_card') else 0,
                float(data.get('foreign_fee_rate') or 0),
                float(data.get('foreign_fee_amount_twd') or 0),
                float(data.get('exchange_rate_to_twd') or 1),
                str(data.get('exchange_rate_source') or '')[:120],
                str(data.get('exchange_rate_type') or '')[:80],
                _parse_iso_date(data.get('exchange_rate_date'), 'exchange_rate_date'),
            )
        )
        conn.commit()
        return jsonify({'status': 'success', 'transaction_id': transaction_id})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.route("/api/game/monthly-budget", methods=["GET", "POST"])
def game_monthly_budget():
    """同步當月預算；7 日後仍可設定提醒，但不符合該月任務資格，且設定後不可調高。"""
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400

        today_value = date.today()
        month_key = today_value.strftime('%Y-%m')
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)

        if request.method == 'GET':
            cursor.execute(
                """
                SELECT month_key, amount, set_day, eligible, created_at, updated_at
                FROM game_monthly_budgets
                WHERE user_id = %s AND month_key = %s
                LIMIT 1
                """,
                (user_id, month_key)
            )
            budget = cursor.fetchone()
            conn.commit()
            return jsonify({"status": "success", "budget": budget})

        data = request.get_json(silent=True) or {}
        try:
            amount = round(float(data.get('amount') or 0), 2)
        except (TypeError, ValueError):
            amount = 0
        if amount <= 0:
            return jsonify({"status": "error", "message": "預算必須大於 0"}), 400

        cursor.execute(
            """
            SELECT amount, set_day, eligible
            FROM game_monthly_budgets
            WHERE user_id = %s AND month_key = %s
            FOR UPDATE
            """,
            (user_id, month_key)
        )
        existing = cursor.fetchone()
        if existing and amount > float(existing.get('amount') or 0):
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "本月預算設定後不能調高；可維持原額或調低。",
                "locked_amount": float(existing.get('amount') or 0),
            }), 409

        if existing:
            cursor.execute(
                "UPDATE game_monthly_budgets SET amount = %s WHERE user_id = %s AND month_key = %s",
                (amount, user_id, month_key)
            )
            eligible = bool(existing.get('eligible'))
            set_day = int(existing.get('set_day') or today_value.day)
        else:
            eligible = today_value.day <= 7
            set_day = today_value.day
            cursor.execute(
                """
                INSERT INTO game_monthly_budgets
                    (user_id, month_key, amount, set_day, eligible)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (user_id, month_key, amount, set_day, 1 if eligible else 0)
            )

        missions = _mission_progress(cursor, user_id)
        conn.commit()
        return jsonify({
            "status": "success",
            "month_key": month_key,
            "amount": amount,
            "set_day": set_day,
            "eligible": eligible,
            "missions": missions,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.get("/api/transactions/payment-metadata")
def list_transaction_payment_metadata():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({'status': 'error', 'message': '缺少 user_id'}), 400
        ids = []
        for raw in str(request.args.get('transaction_ids') or '').split(','):
            if raw.strip().isdigit():
                ids.append(int(raw.strip()))
        ids = ids[:500]

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)
        if ids:
            placeholders = ','.join(['%s'] * len(ids))
            cursor.execute(
                f"""
                SELECT transaction_id, purchase_amount, currency, is_foreign_card,
                       foreign_fee_rate, foreign_fee_amount_twd, exchange_rate_to_twd,
                       exchange_rate_source, exchange_rate_type, exchange_rate_date
                FROM transaction_payment_metadata
                WHERE user_id = %s AND transaction_id IN ({placeholders})
                """,
                (user_id, *ids)
            )
            rows = cursor.fetchall() or []
        else:
            rows = []
        conn.commit()
        payload = []
        for row in rows:
            payload.append({
                'transaction_id': str(row.get('transaction_id')),
                'purchase_amount': float(row.get('purchase_amount') or 0),
                'currency': row.get('currency') or 'TWD',
                'is_foreign_card': bool(row.get('is_foreign_card')),
                'foreign_fee_rate': float(row.get('foreign_fee_rate') or 0),
                'foreign_fee_amount_twd': float(row.get('foreign_fee_amount_twd') or 0),
                'exchange_rate_to_twd': float(row.get('exchange_rate_to_twd') or 1),
                'exchange_rate_source': row.get('exchange_rate_source') or '',
                'exchange_rate_type': row.get('exchange_rate_type') or '',
                'exchange_rate_date': str(row.get('exchange_rate_date') or ''),
            })
        return jsonify({'status': 'success', 'metadata': payload})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.delete("/api/transactions/<int:transaction_id>/payment-metadata")
def delete_transaction_payment_metadata(transaction_id):
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({'status': 'error', 'message': '缺少 user_id'}), 400
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)
        cursor.execute(
            'DELETE FROM transaction_payment_metadata WHERE transaction_id = %s AND user_id = %s',
            (transaction_id, user_id)
        )
        conn.commit()
        return jsonify({'status': 'success'})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/invoices/claim")
def claim_invoice():
    """原子占用發票號碼，避免不同帳號或同時請求重複記帳。"""
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        invoice = _normalize_invoice_number(data.get('invoice_number'))
        if not user_id:
            return jsonify({'status': 'error', 'message': '缺少 user_id'}), 400
        if not invoice:
            return jsonify({'status': 'error', 'message': '發票號碼格式無效'}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        conn.begin()
        _ensure_app_extension_tables(cursor)
        _backfill_invoice_registry(cursor)
        cursor.execute(
            'SELECT * FROM invoice_registry WHERE invoice_number = %s FOR UPDATE',
            (invoice,)
        )
        existing = cursor.fetchone()
        now = datetime.now()
        if existing:
            expires_at = existing.get('expires_at')
            active_pending = existing.get('status') == 'pending' and expires_at and expires_at > now
            if existing.get('status') == 'recorded' or active_pending:
                conn.commit()
                return jsonify({
                    'status': 'duplicate',
                    'invoice_number': invoice,
                    'already_recorded': existing.get('status') == 'recorded',
                }), 409

        claim_token = secrets.token_urlsafe(32)
        expires_at = now + timedelta(minutes=10)
        cursor.execute(
            """
            INSERT INTO invoice_registry
                (invoice_number, user_id, status, claim_token, expires_at, source)
            VALUES (%s, %s, 'pending', %s, %s, 'scan')
            ON DUPLICATE KEY UPDATE
                user_id = VALUES(user_id), status = 'pending',
                claim_token = VALUES(claim_token), expires_at = VALUES(expires_at),
                transaction_id = NULL, source = 'scan'
            """,
            (invoice, user_id, claim_token, expires_at)
        )
        conn.commit()
        return jsonify({
            'status': 'claimed',
            'invoice_number': invoice,
            'claim_token': claim_token,
            'expires_at': expires_at.isoformat(),
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/invoices/finalize")
def finalize_invoice():
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        invoice = _normalize_invoice_number(data.get('invoice_number'))
        claim_token = str(data.get('claim_token') or '')
        if not user_id or not invoice or not claim_token:
            return jsonify({'status': 'error', 'message': '缺少發票占用資訊'}), 400
        transaction_id = data.get('transaction_id')
        transaction_id = int(transaction_id) if str(transaction_id or '').isdigit() else None

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)
        cursor.execute(
            """
            UPDATE invoice_registry
            SET status = 'recorded', transaction_id = %s, claim_token = NULL, expires_at = NULL
            WHERE invoice_number = %s AND user_id = %s
              AND status = 'pending' AND claim_token = %s
            """,
            (transaction_id, invoice, user_id, claim_token)
        )
        if cursor.rowcount != 1:
            conn.rollback()
            return jsonify({'status': 'error', 'message': '發票占用已失效'}), 409
        conn.commit()
        return jsonify({'status': 'recorded', 'invoice_number': invoice})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/invoices/release")
def release_invoice():
    try:
        user_id = _get_request_user_id()
        data = request.get_json(silent=True) or {}
        invoice = _normalize_invoice_number(data.get('invoice_number'))
        claim_token = str(data.get('claim_token') or '')
        if not user_id or not invoice or not claim_token:
            return jsonify({'status': 'error', 'message': '缺少發票占用資訊'}), 400
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)
        cursor.execute(
            """
            DELETE FROM invoice_registry
            WHERE invoice_number = %s AND user_id = %s
              AND status = 'pending' AND claim_token = %s
            """,
            (invoice, user_id, claim_token)
        )
        conn.commit()
        return jsonify({'status': 'released'})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.route("/api/recurring-transactions", methods=["GET", "POST"])
def recurring_transactions_collection():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({'status': 'error', 'message': '缺少 user_id'}), 400
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)

        if request.method == 'GET':
            cursor.execute(
                'SELECT * FROM recurring_transactions_app WHERE user_id = %s ORDER BY is_active DESC, next_run_date, id',
                (user_id,)
            )
            rows = cursor.fetchall() or []
            conn.commit()
            return jsonify({'status': 'success', 'rules': [_recurring_row_json(row) for row in rows]})

        data = request.get_json(silent=True) or {}
        direction = str(data.get('direction') or 'expense')
        cadence = str(data.get('cadence') or 'monthly')
        category = str(data.get('category_name') or '').strip()
        amount = float(data.get('amount') or 0)
        currency = str(data.get('currency') or 'TWD').upper()
        start_date = _parse_iso_date(data.get('start_date'), 'start_date', required=True)
        end_date = _parse_iso_date(data.get('end_date'), 'end_date')
        if direction not in {'expense', 'income'} or cadence not in {'weekly', 'monthly', 'yearly'}:
            return jsonify({'status': 'error', 'message': '收支類型或週期無效'}), 400
        if currency not in {'TWD', 'USD', 'JPY', 'KRW', 'CNY'}:
            return jsonify({'status': 'error', 'message': '不支援的幣別'}), 400
        if not category or amount <= 0:
            return jsonify({'status': 'error', 'message': '分類與金額為必填'}), 400
        if end_date and end_date < start_date:
            return jsonify({'status': 'error', 'message': '結束日不可早於開始日'}), 400
        cursor.execute(
            """
            INSERT INTO recurring_transactions_app
                (user_id, direction, category_name, amount, currency, note,
                 cadence, start_date, next_run_date, end_date, is_active)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                user_id, direction, category, amount, currency,
                str(data.get('note') or '')[:255], cadence, start_date, start_date,
                end_date, 1 if data.get('is_active', True) else 0,
            )
        )
        rule_id = cursor.lastrowid
        conn.commit()
        return jsonify({'status': 'success', 'id': rule_id}), 201
    except ValueError as e:
        return jsonify({'status': 'error', 'message': str(e)}), 400
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.route("/api/recurring-transactions/<int:rule_id>", methods=["PUT", "DELETE"])
def recurring_transaction_item(rule_id):
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({'status': 'error', 'message': '缺少 user_id'}), 400
        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_app_extension_tables(cursor)
        if request.method == 'DELETE':
            cursor.execute('DELETE FROM recurring_transactions_app WHERE id = %s AND user_id = %s', (rule_id, user_id))
            conn.commit()
            return jsonify({'status': 'success'})

        data = request.get_json(silent=True) or {}
        direction = str(data.get('direction') or 'expense')
        cadence = str(data.get('cadence') or 'monthly')
        category = str(data.get('category_name') or '').strip()
        amount = float(data.get('amount') or 0)
        currency = str(data.get('currency') or 'TWD').upper()
        start_date = _parse_iso_date(data.get('start_date'), 'start_date', required=True)
        end_date = _parse_iso_date(data.get('end_date'), 'end_date')
        next_run_date = _parse_iso_date(data.get('next_run_date'), 'next_run_date') or start_date
        if direction not in {'expense', 'income'} or cadence not in {'weekly', 'monthly', 'yearly'}:
            return jsonify({'status': 'error', 'message': '收支類型或週期無效'}), 400
        if currency not in {'TWD', 'USD', 'JPY', 'KRW', 'CNY'}:
            return jsonify({'status': 'error', 'message': '不支援的幣別'}), 400
        if not category or amount <= 0 or (end_date and end_date < start_date):
            return jsonify({'status': 'error', 'message': '資料內容無效'}), 400
        cursor.execute(
            """
            UPDATE recurring_transactions_app
            SET direction=%s, category_name=%s, amount=%s, currency=%s, note=%s,
                cadence=%s, start_date=%s, next_run_date=%s, end_date=%s, is_active=%s
            WHERE id=%s AND user_id=%s
            """,
            (
                direction, category, amount, currency, str(data.get('note') or '')[:255],
                cadence, start_date, next_run_date, end_date,
                1 if data.get('is_active', True) else 0, rule_id, user_id,
            )
        )
        conn.commit()
        return jsonify({'status': 'success'})
    except ValueError as e:
        return jsonify({'status': 'error', 'message': str(e)}), 400
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/recurring-transactions/process-due")
def process_due_recurring_transactions():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({'status': 'error', 'message': '缺少 user_id'}), 400
        today = date.today()
        conn = get_db_connection()
        cursor = conn.cursor()
        conn.begin()
        _ensure_app_extension_tables(cursor)
        cursor.execute(
            """
            SELECT * FROM recurring_transactions_app
            WHERE user_id = %s AND is_active = 1 AND next_run_date <= %s
            FOR UPDATE
            """,
            (user_id, today)
        )
        rules = cursor.fetchall() or []
        created = 0
        for rule in rules:
            scheduled = rule.get('next_run_date')
            processed_for_rule = 0
            while scheduled and scheduled <= today and processed_for_rule < 500:
                end_date = rule.get('end_date')
                if end_date and scheduled > end_date:
                    break
                cursor.execute(
                    'INSERT IGNORE INTO recurring_transaction_runs (rule_id, scheduled_date) VALUES (%s, %s)',
                    (rule.get('id'), scheduled)
                )
                if cursor.rowcount == 1:
                    cursor.execute(
                        """
                        SELECT id FROM accounting_categories
                        WHERE name = %s
                        ORDER BY CASE WHEN direction = %s THEN 0 ELSE 1 END, id
                        LIMIT 1
                        """,
                        (rule.get('category_name'), rule.get('direction'))
                    )
                    cat = cursor.fetchone() or {}
                    category_id = int(cat.get('id') or 1)
                    note = str(rule.get('note') or '').strip()
                    marker = f"固定收支：{rule.get('category_name')}"
                    note = f"{note}\n{marker}" if note else marker
                    cursor.execute(
                        """
                        INSERT INTO accounting_transactions
                            (user_id, amount, type, entry_method, note, date, category_id, currency)
                        VALUES (%s, %s, %s, 'recurring', %s, %s, %s, %s)
                        """,
                        (
                            user_id, rule.get('amount'), rule.get('direction'), note,
                            scheduled, category_id, rule.get('currency') or 'TWD',
                        )
                    )
                    transaction_id = cursor.lastrowid
                    cursor.execute(
                        'UPDATE recurring_transaction_runs SET transaction_id = %s WHERE rule_id = %s AND scheduled_date = %s',
                        (transaction_id, rule.get('id'), scheduled)
                    )
                    created += 1
                scheduled = _next_recurring_date(
                    scheduled,
                    rule.get('cadence'),
                    rule.get('start_date'),
                )
                processed_for_rule += 1

            end_date = rule.get('end_date')
            active = 0 if end_date and scheduled and scheduled > end_date else 1
            cursor.execute(
                'UPDATE recurring_transactions_app SET next_run_date = %s, is_active = %s WHERE id = %s',
                (scheduled, active, rule.get('id'))
            )
        conn.commit()
        return jsonify({'status': 'success', 'created_count': created})
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


@app.post("/api/game/daily-checkin")
def daily_checkin():
    try:
        user_id = _get_request_user_id()
        if not user_id:
            return jsonify({"status": "error", "message": "缺少 user_id"}), 400

        today = date.today()
        yesterday = today - timedelta(days=1)

        conn = get_db_connection()
        cursor = conn.cursor()
        _ensure_player_row(cursor, user_id)
        _ensure_gamification_tables(cursor)
        cursor.execute(
            "SELECT last_login_date, login_streak FROM players WHERE user_id = %s LIMIT 1",
            (user_id,)
        )
        row = cursor.fetchone() or {}
        last_login = row.get("last_login_date")
        if last_login is not None and str(last_login) == str(today):
            wallet = _fetch_reward_wallet(cursor, user_id)
            conn.commit()
            return jsonify({
                "status": "success",
                "already_checked_in": True,
                "earned_gacha_coins": 0,
                **wallet,
            })

        old_streak = int(row.get("login_streak") or 0)
        new_streak = old_streak + 1 if last_login is not None and str(last_login) == str(yesterday) else 1
        # 登入只保留統計，不再發扭蛋幣；連續任務必須記帳或查看報表。
        earned = 0
        cursor.execute(
            """
            UPDATE players
            SET last_login_date = %s,
                login_streak = %s
            WHERE user_id = %s
            """,
            (today, new_streak, user_id)
        )
        wallet = _fetch_reward_wallet(cursor, user_id)
        conn.commit()
        return jsonify({
            "status": "success",
            "already_checked_in": False,
            "earned_gacha_coins": earned,
            **wallet,
        })
    except Exception as e:
        traceback.print_exc()
        if 'conn' in locals() and conn: conn.rollback()
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if 'conn' in locals() and conn: conn.close()


# PAWPAY_RECURRING_INCOME_REVIEW_V1
from recurring_income_review import register_recurring_income_review
register_recurring_income_review(
    app, get_db_connection, get_authenticated_user_id, _ensure_app_extension_tables,
)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)

