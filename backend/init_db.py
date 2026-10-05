import pandas as pd
import sqlite3
import os

# 設定檔名 (必須跟你剛剛改的檔名一樣)
CSV_FILE = "tax.csv"
DB_FILE = "tax_data.db"

def load_tax_csv():
    # 檢查 CSV 是否存在
    if not os.path.exists(CSV_FILE):
        print(f"❌ 錯誤：找不到 {CSV_FILE}！")
        print("請確認：1.你有下載並解壓縮 2.你有把檔案改名為 tax.csv 3.檔案有放在這個資料夾裡")
        return

    print("🚀 正在讀取稅籍資料 (檔案很大，這可能需要 30秒 ~ 1分鐘，請耐心等待)...")
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    # 1. 清空舊資料表，重新建立
    cursor.execute("DROP TABLE IF EXISTS companies")
    cursor.execute("""
        CREATE TABLE companies (
            tax_id TEXT PRIMARY KEY,
            name TEXT
        )
    """)
    
    # 2. 讀取 CSV (自動偵測編碼)
    # 政府資料有時候是 Big5 (cp950)，有時候是 UTF-8，這裡做自動判斷
    df = None
    try:
        # 嘗試 UTF-8
        df = pd.read_csv(CSV_FILE, usecols=["統一編號", "營業人名稱"], dtype=str, encoding='utf-8')
    except:
        print("⚠️ UTF-8 讀取失敗，改用 Big5 (cp950) 嘗試...")
        try:
            df = pd.read_csv(CSV_FILE, usecols=["統一編號", "營業人名稱"], dtype=str, encoding='cp950')
        except ValueError:
             # 有時候欄位名稱會變，這裡做個防呆
            print("⚠️ 欄位名稱不符，嘗試讀取所有欄位...")
            df = pd.read_csv(CSV_FILE, dtype=str, encoding='cp950')
            # 假設第一欄是統編，第二欄是名稱 (這是通常的格式)
            df = df.iloc[:, [0, 1]]
            df.columns = ["統一編號", "營業人名稱"]

    if df is None:
        print("❌ 讀取失敗，請檢查 CSV 檔案是否損壞。")
        return

    # 3. 欄位改名以配合 app.py 的查詢邏輯
    df.columns = ['tax_id', 'name']
    
    # 4. 寫入資料庫
    count = len(df)
    print(f"📦 讀取成功！正在將 {count} 筆店家資料寫入資料庫...")
    df.to_sql("companies", conn, if_exists="append", index=False)

    # 5. 建立索引 (這是查詢速度 0.01秒 的關鍵)
    print("⚙️ 正在建立快速搜尋索引...")
    cursor.execute("CREATE INDEX idx_tax_id ON companies (tax_id)")
    
    conn.commit()
    conn.close()
    print(f"🎉 成功！資料庫 {DB_FILE} 已建立完成。")
    print("👉 現在你可以重啟 app.py 進行測試了！")

if __name__ == "__main__":
    # 如果沒有安裝 pandas，提示安裝
    try:
        load_tax_csv()
    except ImportError:
        print("❌ 錯誤：你還沒安裝 pandas 套件。")
        print("請執行指令：pip install pandas")