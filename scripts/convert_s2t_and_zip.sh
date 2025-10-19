#!/usr/bin/env bash
# Usage:
#   chmod +x scripts/convert_s2t_and_zip.sh
#   ./scripts/convert_s2t_and_zip.sh /path/to/local/repo output-zh-TW.zip
#
# 功能：
# 1. 在複本上做備份與轉換（不會直接覆寫原始 repo）
# 2. 對文字檔用 OpenCC 做簡體->繁體轉換
# 3. 對固定 token 做字串替換 (zh-CN -> zh-TW, zh-cn -> zh-tw, toLocaleString('zh-CN') -> 'zh-TW', lang='zh-cn' -> 'zh-tw')
# 4. 建立 zip（不包含 node_modules, .git）
#
# 需求：opencc (命令列工具)、zip、rsync、sed、find
# 在 Ubuntu/Debian: sudo apt install opencc zip rsync
# 在 macOS (Homebrew): brew install opencc zip rsync
set -euo pipefail

REPO_PATH="${1:-.}"
OUT_ZIP="${2:-output-zh-TW.zip}"
TMP_DIR="$(mktemp -d)"
BACKUP_DIR="${TMP_DIR}/repo-copy"

if [ ! -d "$REPO_PATH" ]; then
  echo "指定的 repo 路徑不存在: $REPO_PATH"
  exit 1
fi

echo "建立工作複本到: $BACKUP_DIR"
# 使用 rsync 排除 node_modules 與 .git 等
rsync -a --exclude='.git' --exclude='node_modules' --exclude='dist' --exclude='.venv' --exclude='venv' "$REPO_PATH/" "$BACKUP_DIR/"

cd "$BACKUP_DIR"

# 檔案類型白名單（只對這些副檔名做 OpenCC 轉換）
EXTS="\( -iname '*.js' -o -iname '*.ts' -o -iname '*.jsx' -o -iname '*.tsx' -o -iname '*.json' -o -iname '*.html' -o -iname '*.htm' -o -iname '*.css' -o -iname '*.md' -o -iname '*.txt' -o -iname '*.py' -o -iname '*.go' -o -iname '*.java' -o -iname '*.rb' -o -iname '*.yml' -o -iname '*.yaml' -o -iname '*.vue' -o -iname '*.scss' \)"

echo "開始替換語言代碼 token（純文字替換）..."
# 對 repository 中的檔案做幾個固定 token 的替換（只替換文字檔）
# 替換 zh-CN => zh-TW (大小寫兩種)
find . -type f $EXTS ! -path "./node_modules/*" -print0 | xargs -0 sed -i.bak \
  -e "s/zh-CN/zh-TW/g" \
  -e "s/zh-CN'/zh-TW'/g" \
  -e 's/"zh-CN"/"zh-TW"/g' \
  -e "s/zh-cn/zh-tw/g" \
  -e "s/toLocaleString('zh-CN')/toLocaleString('zh-TW')/g" \
  -e "s/toLocaleTimeString('zh-CN')/toLocaleTimeString('zh-TW')/g" \
  -e "s/lang='zh-cn'/lang='zh-tw'/g" \
  -e 's/lang="zh-cn"/lang="zh-tw"/g' \
  -e "s/Content-Language: zh-CN/Content-Language: zh-TW/g" \
  -e "s/Content-Language\" content=\"zh-CN\"/Content-Language\" content=\"zh-TW\"/g" \
  || true

# 刪除 .bak 檔（備份已在 TMP）
find . -name "*.bak" -type f -delete

echo "開始用 OpenCC (s2t) 做簡體 -> 繁體轉換（僅文字檔）..."
# 逐一用 opencc 轉換合法副檔名檔案
# 若系統沒有 opencc，提示並退出
if ! command -v opencc >/dev/null 2>&1; then
  echo "找不到 opencc。請先安裝 opencc。"
  echo "Ubuntu/Debian: sudo apt install opencc"
  echo "macOS (Homebrew): brew install opencc"
  exit 1
fi

# 逐檔轉換：將輸入覆寫（先產生 tmp 檔再取代）
find . -type f $EXTS ! -path "./node_modules/*" -print0 | while IFS= read -r -d '' file; do
  # 忽略二進位或過大檔案（例如 >1MB）
  size=$(wc -c <"$file" || echo 0)
  if [ "$size" -gt $((5*1024*1024)) ]; then
    echo "跳過過大檔案: $file"
    continue
  fi
  # 使用 opencc 轉換（簡體到繁體：s2t.json）
  # 先產生暫存檔
  tmpf="${file}.opencc.tmp"
  if opencc -i "$file" -o "$tmpf" -c s2t.json 2>/dev/null; then
    mv "$tmpf" "$file"
  else
    # 若 opencc 失敗，就刪除暫存並跳過
    rm -f "$tmpf"
    echo "opencc 轉換失敗或跳過: $file"
  fi
done

echo "再次替換少數英數 token/格式（必要時）..."
# 例如 toLocaleString 內的引號可能是雙引號
find . -type f $EXTS ! -path "./node_modules/*" -print0 | xargs -0 sed -i \
  -e 's/toLocaleString("zh-CN")/toLocaleString("zh-TW")/g' \
  -e 's/toLocaleTimeString("zh-CN")/toLocaleTimeString("zh-TW")/g' \
  -e 's/lang="zh-CN"/lang="zh-TW"/g' \
  -e 's/lang="zh-cn"/lang="zh-tw"/g' \
  -e "s/'简体'/'繁體'/g" \
  -e 's/"简体"/"繁體"/g' \
  -e "s/'导入'/'匯入'/g" \
  -e 's/"导入"/"匯入"/g' \
  -e "s/'导出'/'匯出'/g" \
  -e 's/"导出"/"匯出"/g' \
  || true

echo "建立 zip: $OUT_ZIP (不包含 node_modules 與 .git)"
# 使用 zip，排除 node_modules 與 .git
zip -r "../$OUT_ZIP" . -x "node_modules/*" -x ".git/*" -x "dist/*" -x "*.zip" >/dev/null

# 將 zip 移回起始目錄
mv "../$OUT_ZIP" "$OLDPWD/"

echo "完成。轉換後的 zip 在: $OLDPWD/$OUT_ZIP"
echo "暫存資料夾 (若要檢查) : $TMP_DIR"
# 不自動刪 TMP_DIR，讓使用者可檢查；若希望自動刪除，取消下一行註解
# rm -rf "$TMP_DIR"
exit 0
