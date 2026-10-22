# codex-move-session

[![Release](https://github.com/doggy8088/codex-move-session/actions/workflows/release.yml/badge.svg)](https://github.com/doggy8088/codex-move-session/actions/workflows/release.yml)

`codex-move-session` 是一個用 Bash 寫成的命令列工具，用來在兩個不同的
OpenAI Codex CLI `CODEX_HOME` 目錄之間搬移指定的工作階段（session）。

它會同時處理三個最容易漏掉、也最容易造成資料不一致的地方：

1. `sessions/YYYY/MM/DD/` 底下的 rollout 工作階段檔案。
2. `session_index.jsonl` 裡面對應的工作階段索引資料。
3. `history.jsonl` 裡面對應的提示詞歷史（預設一併合併；可用 `--no-history`
   跳過）。

本工具預設支援兩個具名別名：

| 別名 | `CODEX_HOME` 路徑 |
| --- | --- |
| `home` | `$HOME/.codex` |
| `pro500` | `$HOME/games/.codex` |

> 目前版本：**v0.1.0**。使用 `codex-move-session --version` 可查看安裝版本。

---

## 目錄

- [專案簡介](#專案簡介)
- [為什麼需要這個工具](#為什麼需要這個工具)
- [功能特色](#功能特色)
- [背景知識：Codex 的本機資料結構](#背景知識codex-的本機資料結構)
- [系統需求](#系統需求)
- [安裝](#安裝)
- [快速開始](#快速開始)
- [使用方式](#使用方式)
- [搬移範圍與行為](#搬移範圍與行為)
- [安全性與備份](#安全性與備份)
- [與 Codex SQLite 資料庫的關係](#與-codex-sqlite-資料庫的關係)
- [版本與發行流程](#版本與發行流程)
- [開發與測試](#開發與測試)
- [專案結構](#專案結構)
- [疑難排解](#疑難排解)
- [授權](#授權)

---

## 專案簡介

Codex CLI 會把每個工作階段的對話紀錄、工具呼叫紀錄與其他中介資料，存放在
`CODEX_HOME` 所指向的目錄中。當同一個使用者有多個 Codex 訂閱、或多個獨立的
Codex 環境時，通常會使用不同的 `CODEX_HOME`，例如：

```text
/Users/will/.codex
/Users/will/games/.codex
```

這些環境各自擁有自己的：

- 工作階段檔案（rollout JSONL）
- 工作階段索引（`session_index.jsonl`）
- 其他本機狀態（設定、快取、SQLite 資料庫等）

如果想把某個工作階段從一個訂閱搬到另一個訂閱，只複製 rollout 檔案通常不夠，
因為 Codex 的互動式選單還會參考 `session_index.jsonl`。手動處理時很容易發生：

- 只搬了檔案，忘記搬索引。
- 只搬了索引，忘記搬檔案。
- 檔名中的 UUID 看錯，搬到錯誤的工作階段。
- 目的地已經有同名檔案，結果覆蓋掉重要資料。
- 索引檔案被編輯到一半，格式壞掉。
- 搬移失敗後，來源與目的地的狀態不一致。

`codex-move-session` 就是為了把這些步驟自動化、並且在出錯時盡可能安全地回復。

---

## 為什麼需要這個工具

假設你在 `pro500` 環境有一個工作階段：

```text
01a15f36-8e5e-7901-86d9-13b7e1100393
```

它的檔案可能位於：

```text
$HOME/games/.codex/sessions/2026/10/22/rollout-2026-10-22T00-06-13-01a15f36-8e5e-7901-86d9-13b7e1100393.jsonl
```

而索引資料位於：

```text
$HOME/games/.codex/session_index.jsonl
```

內容可能像這樣：

```json
{"id":"01a15f36-8e5e-7901-86d9-13b7e1100393","thread_name":"研究 OAuth 整合與使用者管理 API","updated_at":"2026-10-21T16:22:52.292925Z"}
```

若要搬到 `home` 環境，必須同時完成：

1. 把 rollout 檔案搬到 `$HOME/.codex/sessions/2026/10/22/`。
2. 把索引資料從 `$HOME/games/.codex/session_index.jsonl` 移到
   `$HOME/.codex/session_index.jsonl`。
3. （預設）把 `history.jsonl` 中此工作階段的提示詞歷史合併到
   `$HOME/.codex/history.jsonl`，並從來源移除。

本工具會自動完成上述三件事，並且處理 fork 檔案、壓縮檔案、重複索引、歷史合併、
目的地衝突與失敗回復等情況。若不想搬移提示詞歷史，可加上 `--no-history`。

---

## 功能特色

- **依工作階段 ID 搬移**：傳入 UUID，自動尋找對應的 rollout 檔案。
- **自動判斷來源**：只有在其中一個別名環境找到該工作階段時，自動把它視為來源。
- **支援兩個具名別名**：`home` 與 `pro500`，也可傳入任何現存的 `CODEX_HOME` 路徑。
- **支援 fork／續聊檔案**：會一併搬移檔名帶有
  `rollout-*-<session-id>_<fork-id>.jsonl` 的檔案。
- **支援 `.jsonl.zst`**：較舊或經壓縮的工作階段檔案會原樣搬移，不需要先解壓縮。
- **同步處理 `session_index.jsonl`**：
  - 移除來源環境中對應的索引資料。
  - 將索引資料加入目的地環境。
  - 自動去除同一個 ID 的重複索引。
  - 保留 `updated_at` 最新的那一筆。
  - 以原子性方式改寫索引檔，避免寫到一半損壞。
- **同步處理 `history.jsonl`（預設）**：
  - 取出 `session_id` 等於指定 UUID 的提示詞歷史。
  - 與目的地同工作階段的歷史合併，不會刪掉目的地獨有的資料。
  - 去除完全相同的重複資料，並依 `ts` 遞增排序。
  - 搬移模式會從來源移除對應歷史；`--copy` 會保留來源。
  - 可用 `--no-history` 完全跳過。
  - 若來源或目的地的 `history.jsonl` 格式損壞，會警告並跳過歷史搬移，
    不影響 rollout 檔案與索引的搬移。
- **補搬已移到目的地的歷史**：若 rollout 檔案已經在目的地，但另一個
  `CODEX_HOME` 的 `history.jsonl` 還有此工作階段，會自動只合併歷史，不搬移
  rollout 檔案或索引。
- **目的地衝突保護**：目的地已有同名檔案或索引時，預設直接中止，不會默默覆蓋。
- **`--force` 備份機制**：強制覆蓋前會建立 `.bak.<timestamp>` 備份。
- **`--copy` 模式**：只複製、不刪除來源，適合先備份或平行測試。
- **`--dry-run` 預覽**：只顯示預計執行的動作，完全不變更檔案。
- **失敗回復**：搬移或索引更新失敗時，會嘗試把檔案搬回、還原索引與備份。
- **清除空目錄**：成功搬移後，會移除來源端變成空白的日期目錄。
- **版本查詢**：支援 `-v` 與 `--version`。
- **無需 Codex 執行檔**：工具本身只操作檔案，不會呼叫 Codex CLI。

---

## 背景知識：Codex 的本機資料結構

### `CODEX_HOME`

Codex CLI 會使用 `CODEX_HOME` 環境變數決定本機資料的根目錄。未設定時通常會使用
`$HOME/.codex`。不同訂閱可以透過不同的 `CODEX_HOME` 完全隔離。

本專案預設的兩個環境是：

```text
home    -> $HOME/.codex
pro500  -> $HOME/games/.codex
```

這兩個路徑直接寫在腳本開頭的別名表中，方便依照自己的環境修改。

### 工作階段檔案（rollout files）

工作階段檔案通常長這樣：

```text
sessions/2026/10/22/rollout-2026-10-22T00-06-13-01a15f36-8e5e-7901-86d9-13b7e1100393.jsonl
```

命名規則可以簡化為：

```text
sessions/YYYY/MM/DD/rollout-<時間>-<session-id>.jsonl
```

部分較舊的檔案會被壓縮成：

```text
rollout-<時間>-<session-id>.jsonl.zst
```

本工具會原樣搬移 `.jsonl.zst`，不會自行解壓縮或重新壓縮。

### Fork／續聊檔案

Codex 在 fork 工作階段或建立續聊版本時，檔名可能帶有第二個 UUID：

```text
rollout-2026-10-20T14-34-00-01a157bc-4d80-74f0-bdad-8785b1314125_01a15804-52f7-7d61-a67f-00fddd0f8587.jsonl
```

其中：

- `01a157bc-4d80-74f0-bdad-8785b1314125` 是主要工作階段 ID。
- `01a15804-52f7-7d61-a67f-00fddd0f8587` 是 fork／續聊標記。

這些檔案仍然屬於主要工作階段，因此本工具會一併搬移。若只搬主檔而漏掉 fork 檔，
工作階段的歷史可能會不完整。

### `session_index.jsonl`

`session_index.jsonl` 是一種 JSON Lines 檔案，每一行都是一個 JSON 物件，例如：

```json
{"id":"01a15f36-8e5e-7901-86d9-13b7e1100393","thread_name":"研究 OAuth 整合與使用者管理 API","updated_at":"2026-10-21T16:22:52.292925Z"}
```

常見欄位：

| 欄位 | 說明 |
| --- | --- |
| `id` | 工作階段 UUID |
| `thread_name` | 顯示在 Codex 工作階段選單中的名稱 |
| `updated_at` | 最後更新時間，通常是 UTC ISO 8601 字串 |

本工具會用 `id` 精確比對，不會用模糊字串搜尋，避免搬錯工作階段。

### 為什麼索引也要搬？

rollout 檔案是工作階段的內容本體，而 `session_index.jsonl` 則是 Codex 用來列出、
辨識與排序工作階段的索引。只搬檔案時，Codex 可能無法在選單中正確顯示該工作階段；
只搬索引時，則會留下指向不存在檔案的無效資料。兩者必須一起處理。

### `history.jsonl`

`history.jsonl` 用來儲存提示詞歷史，每一行都是一個 JSON 物件，例如：

```json
{"session_id":"01a15f36-8e5e-7901-86d9-13b7e1100393","ts":1790779341,"text":"幫我整理這段程式碼"}
```

常見欄位：

| 欄位 | 說明 |
| --- | --- |
| `session_id` | 所屬工作階段的 UUID |
| `ts` | 提示詞建立的 Unix epoch 秒數 |
| `text` | 提示詞內容 |

同一個工作階段可能有多筆歷史，而且來源與目的地可能都已經有部分資料。本工具預設會：

1. 只取出 `session_id` 與指定 UUID 完全相同的行。
2. 把來源與目的地同工作階段的資料合併，不會刪除目的地獨有的提示詞。
3. 去除完全相同的重複物件。
4. 將合併後的 `history.jsonl` 依 `ts` 遞增排序。
5. 搬移模式下從來源移除該工作階段的歷史；`--copy` 則保留來源。

`history.jsonl` 不是工作階段本體，沒有它通常不影響 rollout 檔案載入；但若希望
Codex 的提示詞回顧功能也保持一致，建議保留預設的歷史搬移。若你只想搬 rollout 檔案
與索引，請加上 `--no-history`。

若 rollout 檔案已經在目的地，而另一個 `CODEX_HOME` 的 `history.jsonl` 還有此工作
階段的資料，工具會自動進入「只補搬歷史」模式：只合併 `history.jsonl`，不會搬移
rollout 檔案或 `session_index.jsonl`。這適合修正先前只搬了工作階段本體、忘記搬歷史
的情況。

---

## 系統需求

- macOS 或 Linux
- Bash 3.2 以上（macOS 內建的 `/bin/bash` 即可）
- [`jq`](https://stedolan.github.io/jq/)：用於解析與改寫 JSONL
- 標準 Unix 工具：`find`、`mktemp`、`install`、`cp`、`mv` 等
- 若要使用 `install.sh` 的線上下載模式，需要 `curl`
- 不需要安裝 `zstd`；`.jsonl.zst` 會原樣搬移

macOS 可用 Homebrew 安裝 `jq`：

```bash
brew install jq
```

Ubuntu／Debian 可用：

```bash
sudo apt-get update
sudo apt-get install -y jq
```

---

## 安裝

### 方法一：使用 `install.sh`（推薦）

直接從 GitHub 下載並安裝到預設的 `$HOME/.local/bin`：

```bash
curl -fsSL https://raw.githubusercontent.com/doggy8088/codex-move-session/main/install.sh | bash
```

`install.sh` 會：

1. 如果目前目錄有專案原始碼，優先使用本機的 `codex-move-session`。
2. 否則從 GitHub 的 `main` 分支下載最新版本。
3. 建立安裝目錄（預設為 `$HOME/.local/bin`）。
4. 以 `0755` 權限安裝 `codex-move-session`。
5. 檢查 `jq` 是否存在，並提醒 `$HOME/.local/bin` 是否已在 `PATH` 中。
6. 執行 `codex-move-session --version` 確認安裝結果。

### 方法二：從 Git 儲存庫安裝

```bash
git clone https://github.com/doggy8088/codex-move-session.git
cd codex-move-session
./install.sh
```

### 方法三：自訂安裝目錄

使用 `--prefix` 或 `--dir`：

```bash
./install.sh --prefix "$HOME/bin"
```

也可以使用環境變數：

```bash
INSTALL_DIR="$HOME/bin" ./install.sh
```

若使用 `curl | bash`，可改成：

```bash
curl -fsSL https://raw.githubusercontent.com/doggy8088/codex-move-session/main/install.sh \
  | bash -s -- --prefix "$HOME/bin"
```

### 確認安裝

```bash
command -v codex-move-session
codex-move-session --version
```

預期輸出：

```text
codex-move-session v0.1.0
```

### 將 `~/.local/bin` 加入 `PATH`

如果安裝後出現 `command not found`，請確認 `$HOME/.local/bin` 在 `PATH` 中。

Zsh（`~/.zshrc`）：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Bash（`~/.bashrc` 或 `~/.bash_profile`）：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

修改後重新開啟終端機，或執行：

```bash
source ~/.zshrc
```

---

## 快速開始

建議先使用 `--dry-run` 預覽，再實際搬移。

```bash
# 1. 預覽：把指定工作階段從 pro500 搬到 home
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home --dry-run

# 2. 確認無誤後實際搬移
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home

# 3. 反向搬移
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 pro500
```

---

## 使用方式

### 語法

```text
codex-move-session <session-id> <target> [options]
```

- `<session-id>`：工作階段 UUID，例如
  `01a15f36-8e5e-7901-86d9-13b7e1100393`。
- `<target>`：目標別名或 `CODEX_HOME` 路徑。
- 來源預設會自動判斷；若有歧義，使用 `--from` 指定。

### 目標別名

| 別名 | 路徑 |
| --- | --- |
| `home` | `$HOME/.codex` |
| `pro500` | `$HOME/games/.codex` |
| `/path/to/codex-home` | 任何現存的 `CODEX_HOME` 目錄 |
| `~/path/to/codex-home` | 任何現存的 `CODEX_HOME` 目錄（支援 `~` 展開） |

### 選項

| 選項 | 說明 |
| --- | --- |
| `--from <alias\|path>` | 明確指定來源，常用於來源同時存在於多個環境時 |
| `--copy` | 只複製，不刪除來源檔案、索引與歷史 |
| `--dry-run` | 只顯示預計動作，不做任何變更 |
| `--force` | 允許覆蓋目的地已有的工作階段；覆蓋前會建立備份 |
| `--with-history` | 搬移 `history.jsonl` 提示詞歷史（預設） |
| `--no-history` | 跳過 `history.jsonl`，只搬 rollout 檔案與索引 |
| `-v`, `--version` | 顯示版本 |
| `-h`, `--help` | 顯示說明 |

### 範例

#### 預覽搬移

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home --dry-run
```

輸出範例：

```text
[dry-run] session: 01a15f36-8e5e-7901-86d9-13b7e1100393
[dry-run] from:    pro500 (/Users/will/games/.codex)
[dry-run] to:      home (/Users/will/.codex)
[dry-run] mode:    move
[dry-run] move /Users/will/games/.codex/sessions/2026/10/22/rollout-2026-10-22T00-06-13-01a15f36-8e5e-7901-86d9-13b7e1100393.jsonl -> /Users/will/.codex/sessions/2026/10/22/rollout-2026-10-22T00-06-13-01a15f36-8e5e-7901-86d9-13b7e1100393.jsonl
[dry-run] index:   remove 1 source entry/entries; add 1 destination entry
[dry-run] history: merge 27 source entry/entries into 1 destination entry/entries; remove source entries
```

#### 從 `pro500` 搬到 `home`

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home
```

#### 從 `home` 搬到 `pro500`

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 pro500
```

#### 只複製，保留來源

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home --copy
```

#### 只搬 rollout 檔案與索引，不搬提示詞歷史

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home --no-history
```

#### rollout 已在目的地，只補搬提示詞歷史

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home --dry-run
```

若目的地已有 rollout 檔案，來源只剩歷史資料，輸出會類似：

```text
[dry-run] mode:    move (history only)
[dry-run] history: merge 27 source entry/entries into 1 destination entry/entries; remove source entries
```

這種情況不會搬移 rollout 檔案或 `session_index.jsonl`。

#### 目的地已有相同工作階段時強制覆蓋

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 home --force
```

`--force` 會：

- 備份目的地已被覆蓋的 rollout 檔案為 `<原檔名>.bak.<timestamp>`。
- 備份目的地的 `session_index.jsonl` 為
  `session_index.jsonl.bak.<timestamp>`。
- 若目的地 `history.jsonl` 已有同工作階段的歷史，備份為
  `history.jsonl.bak.<timestamp>`。
- 以來源的最新索引資料取代目的地同 ID 的索引資料。
- 歷史資料仍採合併方式處理，不會刪除目的地獨有的提示詞。

#### 明確指定來源

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 /tmp/another-codex --from pro500
```

#### 搬移到任意 `CODEX_HOME`

```bash
codex-move-session 01a15f36-8e5e-7901-86d9-13b7e1100393 ~/codex-work
```

目的地目錄必須存在；若缺少 `sessions/` 或 `session_index.jsonl`，工具會自動建立。

#### 查看版本

```bash
codex-move-session --version
codex-move-session -v
```

---

## 搬移範圍與行為

### 會搬移的檔案

工具會在來源的 `sessions/` 目錄下遞迴尋找符合以下格式的檔案：

```text
rollout-*-<session-id>.jsonl
rollout-*-<session-id>.jsonl.zst
rollout-*-<session-id>_*.jsonl
rollout-*-<session-id>_*.jsonl.zst
```

其中：

- 前兩種是主要工作階段檔案。
- 後兩種是 fork／續聊檔案。
- `.jsonl.zst` 會原樣搬移，不進行壓縮或解壓縮。

搬移時會保留相對於 `sessions/` 的路徑，例如：

```text
sessions/2026/10/22/rollout-...jsonl
```

會搬到目的地的同一個日期目錄：

```text
<target>/sessions/2026/10/22/rollout-...jsonl
```

### `session_index.jsonl` 的處理

1. 從來源索引中找出所有 `id` 等於指定 UUID 的行。
2. 若同一個 ID 有多筆，依 `updated_at` 排序，保留最新的一筆。
3. 移除目的地索引中同一個 ID 的所有舊資料（僅在 `--force` 時允許覆蓋）。
4. 將保留的索引資料加入目的地。
5. 將目的地索引依 `updated_at` 遞增排序，維持與 Codex 既有格式一致的順序。
6. 從來源索引移除該 ID 的所有資料（`--copy` 模式不會移除）。
7. 以暫存檔加 `mv` 的方式原子性替換索引檔，避免寫入中斷造成半成品。

若來源索引檔不存在，或找不到對應 ID，工具會警告並只搬移 rollout 檔案；這種情況通常
表示索引本來就不完整，工具不會自行捏造資料。

### `history.jsonl` 的處理

1. 從來源 `history.jsonl` 找出所有 `session_id` 等於指定 UUID 的行。
2. 同時讀取目的地 `history.jsonl` 中同工作階段的資料。
3. 將兩邊資料合併，不刪除目的地獨有的提示詞。
4. 去除完全相同的重複 JSON 物件。
5. 依 `ts` 遞增排序；缺少 `ts` 或無法轉成數字時視為 `0`。
6. 以暫存檔加 `mv` 的方式原子性替換目的地檔案。
7. 搬移模式下再從來源 `history.jsonl` 移除該工作階段的資料；`--copy` 不會移除。
8. 若目的地原本沒有 `history.jsonl`，會自動建立。

若來源沒有 `history.jsonl`，或檔案中沒有此工作階段的資料，工具會顯示跳過訊息，
不會因此失敗。若來源或目的地的 `history.jsonl` 不是合法 JSONL，工具會警告並跳過
歷史搬移，rollout 檔案與索引仍會照常處理。

歷史資料是「合併」而不是「取代」。即使使用 `--force`，目的地獨有的提示詞也不會被
刪除；`--force` 只會在有既有歷史時額外建立 `.bak.<timestamp>` 備份。

### 只補搬 `history.jsonl`

若指定的目的地已經有該工作階段的 rollout 檔案，但另一個 `CODEX_HOME` 的
`history.jsonl` 還有此工作階段，工具會自動進入 history-only 模式：

- 只讀取並合併來源 `history.jsonl`。
- 不搬移 rollout 檔案。
- 不修改來源或目的地的 `session_index.jsonl`。
- `--copy` 會保留來源歷史。
- 若多個非目的地環境都有此工作階段的歷史，會要求使用 `--from` 指定來源。
- `--no-history` 會停用此模式；此時若沒有 rollout 檔案可搬，仍會依照原本的規則
  顯示錯誤。

這個模式適合修正「rollout 已經搬過去，但 `history.jsonl` 還留在另一邊」的情況。

### 衝突與 `--force`

下列情況會被視為目的地衝突：

- 目的地已有相同相對路徑的 rollout 檔案。
- 目的地 `session_index.jsonl` 已有相同 ID 的索引資料。

預設行為是**中止**，並列出所有衝突項目。只有加上 `--force` 才會覆蓋。

`history.jsonl` 已有同工作階段的資料**不算衝突**，因為歷史資料採合併處理，不會覆蓋
目的地獨有的提示詞。若加上 `--force`，工具仍會在有既有歷史時建立備份。

### 交易與回復

工具會盡量以「先檢查、後執行、失敗回復」的方式運作：

1. 先驗證 UUID、來源、目的地、索引與歷史格式。
2. 檢查所有目的地衝突。
3. 建立索引與歷史的暫存備份。
4. 搬移或複製 rollout 檔案。
5. 合併目的地的 `history.jsonl`。
6. 從來源 `history.jsonl` 移除對應資料（`--copy` 略過）。
7. 更新目的地索引。
8. 更新來源索引。
9. 驗證結果。

若中途失敗：

- 已搬移的檔案會嘗試搬回來源位置。
- 複製模式下，已複製的目的地檔案會被移除。
- `history.jsonl` 會從暫存備份還原；若本次才建立，則會移除。
- 索引會從暫存備份還原。
- `--force` 覆蓋的檔案會從 `.bak.<timestamp>` 備份還原。

> 若進入 history-only 模式，只會執行歷史合併與來源移除，rollout 檔案與索引不會
> 變動。

> 回復是「盡力而為」。仍建議在重要環境中先使用 `--dry-run`，並在搬移前確認 Codex
> 已關閉。

### 空目錄清理

成功搬移後，若來源端的日期目錄變成空白，工具會逐層移除以 `sessions/` 為界的空目錄。
例如：

```text
sessions/2026/10/22/
sessions/2026/10/
sessions/2026/
```

只會刪除空目錄，不會刪除 `sessions/` 本身，也不會刪除仍有其他工作階段的目錄。

---

## 安全性與備份

- **先預覽**：一律建議先執行 `--dry-run`。
- **關閉 Codex**：搬移期間請關閉 Codex，避免 Codex 同時寫入
  `session_index.jsonl` 或 `history.jsonl`。
- **使用 `--force` 前先確認**：強制覆蓋會建立備份，但仍可能造成目的地版本與你預期的
  不同。
- **歷史資料採合併**：`history.jsonl` 不會刪除目的地獨有的提示詞；若不想搬移歷史，
  請加上 `--no-history`。
- **備份整個 `CODEX_HOME`**：若工作階段非常重要，建議先額外備份整個目錄。
- **不要在搬移途中中斷行程**：若終端機被強制關閉，請檢查來源與目的地的 rollout 檔案、
  索引與歷史是否一致。
- **索引格式必須正確**：工具會在搬移前驗證 `session_index.jsonl`；若索引已損壞，會
  中止而不繼續。
- **歷史格式損壞時會跳過**：若 `history.jsonl` 無法解析，工具會警告並跳過歷史搬移，
  rollout 檔案與索引仍會處理。

---

## 與 Codex SQLite 資料庫的關係

本工具**只處理** rollout 檔案、`session_index.jsonl` 與 `history.jsonl`，不會修改
下列資料：

- `state_5.sqlite`：Codex 的本機狀態資料庫。
- `thread_history_1.sqlite`：分頁式工作階段歷史資料庫。
- 其他 SQLite、快取、設定或外掛資料。

`history.jsonl` 只是逐行的提示詞歷史，不是工作階段資料庫；工具會以 JSONL 方式
合併與去重，不會碰觸 SQLite 的交易或 schema。

這是刻意的設計取捨：

- SQLite 資料庫涉及 WAL、交易、版本遷移與並行寫入，直接修改風險較高。
- 不同 Codex 版本的資料表結構可能不同。
- 只搬移 rollout 檔案、索引與提示詞歷史，已能滿足大多數「把工作階段搬到另一個
  `CODEX_HOME`」的需求。

若搬移後 Codex 的選單沒有顯示該工作階段，可以嘗試：

```bash
CODEX_HOME=/path/to/destination codex migrate-rollouts --apply
```

或重新啟動 Codex。實際行為仍以你使用的 Codex 版本為準。

---

## 版本與發行流程

### 版本來源

版本號定義在 `codex-move-session` 開頭：

```bash
VERSION="0.1.0"
```

`--version` 會輸出：

```text
codex-move-session v0.1.0
```

### 發行 Workflow

專案包含 `.github/workflows/release.yml`，會在推送新 commit 到 `main` 分支時執行：

1. 從 `codex-move-session` 讀取 `VERSION`。
2. 驗證版本格式與 `--version` 輸出。
3. 檢查是否已存在 `v<version>` 的 Git tag。
4. 若 tag 不存在，建立 GitHub Release，並附上：
   - `codex-move-session`
   - `install.sh`

若版本沒有變更，且對應的 tag 已存在，workflow 會跳過發行，不會重複建立 Release。

### 發行新版本的步驟

1. 修改 `codex-move-session` 的版本號，例如從 `0.1.0` 改為 `0.1.1`：

   ```bash
   VERSION="0.1.1"
   ```

2. 提交並推送到 `main`：

   ```bash
   git add codex-move-session
   git commit -m "chore: release v0.1.1"
   git push origin main
   ```

3. 到 GitHub Actions 查看 `Release` workflow。
4. workflow 成功後，GitHub Releases 會出現 `v0.1.1`。

> 只有版本號有變更且 tag 尚不存在時，才會建立新的 Release。單純推送一般 commit
> 不會重複發行。

### 重新發行同一個版本

Workflow 只檢查 `v<version>` tag 是否存在，不會比較版本內容。若需要修正同一個版本的
Release 資產（例如補上 `history.jsonl` 搬移功能），必須先刪除現有的 GitHub Release
與 tag，再推送一個新 commit 讓 workflow 重新執行：

```bash
gh release delete v0.1.0 \
  --repo doggy8088/codex-move-session \
  --yes \
  --cleanup-tag

git commit --allow-empty -m "chore: re-release v0.1.0"
git push origin main
```

> `--cleanup-tag` 會一併刪除遠端 tag。若只刪 Release 而沒有刪 tag，workflow 仍會
> 判定 tag 已存在而跳過發行。

---

## 開發與測試

本專案沒有建置步驟，主要驗證方式如下。

### 語法檢查

```bash
bash -n codex-move-session
bash -n install.sh
```

### ShellCheck

```bash
shellcheck codex-move-session install.sh
```

### GitHub Actions 語法檢查

若已安裝 [`actionlint`](https://github.com/rhysd/actionlint)：

```bash
actionlint .github/workflows/release.yml
```

### 版本檢查

```bash
test "$(./codex-move-session --version)" = "codex-move-session v0.1.0"
```

### 使用暫存 `HOME` 測試

建議使用暫存的 `HOME` 建立假的 `.codex` 與 `games/.codex`，避免動到真實資料：

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/home/.codex/sessions" "$tmp/home/games/.codex/sessions"
touch "$tmp/home/.codex/session_index.jsonl" "$tmp/home/games/.codex/session_index.jsonl"

HOME="$tmp/home" ./codex-move-session --version
HOME="$tmp/home" ./codex-move-session --help

rm -rf "$tmp"
```

若要測試完整搬移流程，請在暫存環境中建立假的 rollout JSONL、索引資料與
`history.jsonl`，再執行 `codex-move-session <id> home`，並檢查：

- 來源檔案是否被移除。
- 目的地檔案是否存在。
- 來源索引是否移除對應 ID。
- 目的地索引是否只保留一筆。
- 目的地 `history.jsonl` 是否包含來源與目的地兩邊的提示詞。
- 重複的歷史物件是否只保留一筆，且依 `ts` 排序。
- 搬移模式下來源 `history.jsonl` 是否已移除該工作階段。
- `--copy` 是否保留來源檔案、索引與歷史。
- `--no-history` 是否完全不修改兩邊的 `history.jsonl`。
- `history.jsonl` 格式損壞時，是否只警告並跳過歷史，rollout 檔案仍完成搬移。
- rollout 已在目的地時，是否只補搬 `history.jsonl`，且不改動 rollout 與索引。
- 多個來源都有此工作階段歷史時，是否要求使用 `--from`。
- 日期目錄是否被正確清理。

### 安裝腳本測試

使用暫存安裝目錄，避免覆蓋目前安裝的版本：

```bash
tmp=$(mktemp -d)
./install.sh --prefix "$tmp/bin"
"$tmp/bin/codex-move-session" --version
rm -rf "$tmp"
```

---

## 專案結構

```text
codex-move-session/
├── .github/
│   └── workflows/
│       └── release.yml       # 推送 main 且版本更新時建立 Release
├── LICENSE                   # MIT 授權
├── README.md                 # 本文件
├── codex-move-session        # 主程式（Bash）
└── install.sh                # 安裝腳本
```

---

## 疑難排解

### `jq: command not found`

本工具需要 `jq`。請依作業系統安裝：

```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt-get install -y jq
```

### `codex-move-session: command not found`

確認安裝目錄在 `PATH` 中：

```bash
echo "$PATH"
ls -l "$HOME/.local/bin/codex-move-session"
```

必要時在 shell 設定檔加入：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### `target CODEX_HOME does not exist`

目的地路徑必須存在。若是第一次建立新的 `CODEX_HOME`，請先建立資料夾：

```bash
mkdir -p ~/my-codex-home
codex-move-session <session-id> ~/my-codex-home
```

### `no rollout files found`

可能原因：

- 工作階段 ID 打錯。
- 來源 `CODEX_HOME` 不對。
- 該工作階段只有索引、沒有 rollout 檔案（工具會拒絕單獨搬移索引）。
- 檔案名稱格式與預期不同。

請先用 `find` 確認：

```bash
find ~/.codex/sessions ~/games/.codex/sessions -name '*<session-id>*'
```

### `session found in multiple CODEX_HOMEs`

同一個工作階段同時存在於多個環境，且目標是自訂路徑，工具無法判斷來源。請使用
`--from`：

```bash
codex-move-session <session-id> /path/to/target --from home
```

### `destination already contains this session`

目的地已有同名檔案或索引。先確認是否真的要覆蓋；若確定，使用 `--force`：

```bash
codex-move-session <session-id> home --force
```

### `source session index is not valid JSONL`

`session_index.jsonl` 格式已損壞。請先備份並檢查：

```bash
jq . ~/.codex/session_index.jsonl >/dev/null
```

若無法解析，請手動修復或從備份還原後再執行。

### `history.jsonl` 格式損壞

若看到類似訊息：

```text
warning: source history.jsonl is not valid JSONL; history will not be migrated
history: skipped (invalid source JSONL)
```

表示提示詞歷史無法解析。工具會跳過歷史搬移，但 rollout 檔案與索引仍會完成。請先
備份並檢查：

```bash
jq . ~/.codex/history.jsonl >/dev/null
```

修復後可重新執行，或加上 `--no-history` 明確跳過歷史。

### `history.jsonl` 沒有搬移

可能原因：

- 使用了 `--no-history`。
- 來源沒有 `history.jsonl`。
- 來源檔案中沒有此 `session_id` 的資料。
- 來源或目的地的 `history.jsonl` 格式損壞，工具已警告並跳過。

可先用 `jq` 確認：

```bash
jq -c 'select(.session_id == "<session-id>")' ~/games/.codex/history.jsonl
jq -c 'select(.session_id == "<session-id>")' ~/.codex/history.jsonl
```

### rollout 已在目的地，只想補搬 `history.jsonl`

直接指定目的地即可，工具會自動偵測並進入 history-only 模式：

```bash
codex-move-session <session-id> home --dry-run
codex-move-session <session-id> home
```

若多個非目的地環境都有此工作階段的歷史，請加上 `--from`：

```bash
codex-move-session <session-id> home --from pro500
```

### 搬移後 Codex 選單沒有出現工作階段

- 重新啟動 Codex。
- 確認 `session_index.jsonl` 已包含該 ID。
- 確認 rollout 檔案位於目的地的 `sessions/YYYY/MM/DD/`。
- 嘗試：

  ```bash
  CODEX_HOME=/path/to/destination codex migrate-rollouts --apply
  ```

- 注意本工具不會修改 `state_5.sqlite` 或 `thread_history_1.sqlite`。

### 權限不足

確認安裝目錄與 `CODEX_HOME` 有寫入權限：

```bash
ls -ld ~/.local/bin ~/.codex ~/games/.codex
```

必要時使用可寫入的 `--prefix`，或調整目錄權限。

---

## 授權

本專案採用 [MIT License](LICENSE)。

Copyright © 2026 Will 保哥
