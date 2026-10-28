# Patched macOS OpenAI Codex / ChatGPT Desktop App (In-App Browser & Luna IAB)

[![Release](https://img.shields.io/github/v/release/obhasashare2024-namo/codex-macos-iab-patched?style=flat-square)](https://github.com/obhasashare2024-namo/codex-macos-iab-patched/releases)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

[繁體中文](#繁體中文) | [English](#english) | [日本語](#日本語)

---

## 繁體中文

本專案提供針對 macOS 官方正式版 OpenAI Codex / ChatGPT Desktop（版本 `26.1016.62342`）及社區版（`26.623.141536`）的完整修復補丁與深層技術除錯報告。徹底解決 In-App Browser (IAB 內置瀏覽器) 無法啟動、白屏崩潰、符號連結目錄拒絕、鑰匙圈死鎖、以及 `gpt-6-luna` 模型的自動化網頁操作難題。

---

### 一、 社區版 vs 官方正式版 核心架構與補丁深度對比

社區版與官方正式版在底層 Electron 架構、完整性校驗體系、IAB 管道實現與安全校驗上有著根本性的代際差異：

| 評估維度 | 社區版 (`26.623.141536`) | 官方正式版 (`26.1016.62342`) | 技術本質與補丁差異 |
| :--- | :--- | :--- | :--- |
| **Electron 運行時** | 舊版 Electron `40.0.0` / Chromium `128` | 新版 Electron / Chromium `155.0.8059.80` | 正式版升級至包含 Chromium 155 的現代化 Owl 容器，沙盒與權限限制更為嚴格。 |
| **ASAR 完整性校驗** | **無區塊級鎖 (Single-layer)** | **三重硬鎖 (Triple Integrity Lock)** | 社區版僅校驗整體檔案；正式版對 ASAR Header 區塊 SHA256 陣列、二進制 Mach-O slot 哨兵 (`AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A`)、及 `Info.plist` 的 `ElectronAsarIntegrity` 施加全域聯鎖校驗。 |
| **IAB 瀏覽器管道** | **外部獨立服務 (browser-service)** | **應用內建原生 (App-Native Runtime)** | 社區版需啟動額外的 `browser-service.mjs` 並透過 `host-services` Unix socket 提供 IPC；正式版已全面原生化整合至主進程，走 `/tmp/codex-app-tools/*.sock`。 |
| **主進程 JS 補丁** | 補丁較輕量 | **三重核心繞過 (main-JI9qDiXp.js)** | 正式版必須在主進程強制注入：<br>1. `Vd()` 函式強制 `authorized:!0`（Mac TCC peer 授權放行）；<br>2. `ensureBrowserUseSessionRoute` 繞過強制 session 路由檢查；<br>3. `resolveBrowserRoute` 注入後備值 `?? this.sessionRoutes.values().next().value`。 |
| **瀏覽器客戶端補丁** | **深入修改 `browser-client.mjs`** | 無需大幅修改 client | 社區版需在 `browser-client.mjs` 中修補 `wu()` nativePipe 信任檢查、`Qi()` 繞過 elicitation、及修補 `setResponseMeta?.()` 可選鏈；正式版直接復用原生 pipe。 |
| **帳號登入態強綁定** | 無強制遠端授權阻斷 | **硬性阻斷門禁 (bootstrap-DCRTDDSX.js)** | 正式版在視窗創建前強制調用 `refreshLocalRemoteControlClientId`，若未登入會拋出 `Sign in to ChatGPT to check remote control authorization` 並終止 `createMainWindow()`，導致無視窗退出；社區版無此限制。 |
| **macOS 鑰匙圈 ACL** | 不易死鎖 | **Ad-hoc 簽名 ACL 衝突死鎖** | 正式版依賴 `Codex Storage Key`。當 App 經修改並重簽為 Ad-hoc 簽名後，macOS 因缺少 Team ID 拒絕更新存取控制表，導致無限彈出密碼框且拒絕任何密碼；需手動清除條目重設。 |
| **路徑符號連結檢查** | 被外層腳本規避 | **Rust 內核 `reject_symlink_ancestors`** | `node_repl` 嚴格審查 `writable_roots`。若環境變數繼承了包含 symlink 的路徑（例如 macOS 下常見的 `~/.agy_profiles`），內核會立即崩潰並提示「執行環境拒絕了含有符號連結的可寫入目錄」。 |
| **配置與目錄隔離** | 使用 `~/.codex/config.toml` | **獨立物理目錄完全物理隔離** | 正式版運行於獨立的 `CODEX_HOME=/Volumes/disk1/data_namobuddha/codex_official_home`，使用專屬的 `config.toml`，杜絕兩者相互覆蓋污染。 |

---

### 二、 社區版 (`26.623.141536`) 補丁架構與實施細節

社區版核心設計思路是採用「外掛服務橋接」模式：

1. **外部獨立服務 (`browser-service.mjs`)**：
   社區版未將瀏覽器工具完全整合至主進程，而是依賴後台常駐獨立進程 `browser-service.mjs`。Codex 主程式透過 `host-services` 的 Unix domain socket 與其進行跨進程通訊（IPC）。
2. **`browser-client.mjs` 客戶端補丁細節**：
   - **`wu()` 管道信任放行**：解除原生客戶端對管道通訊憑證的硬編碼校驗，強制將本地建立的 Unix socket 判定為受信任環境。
   - **`Qi()` 交互確認繞過**：社區版在呼叫高階網頁自動化或 DOM 讀取時，預設會觸發 `elicitation` 確認請求，導致無人值守任務中斷。補丁將該流程旁路，直接放行執行。
   - **`setResponseMeta?.()` 防護**：針對社區版在部分響應缺乏元數據時拋出 `TypeError: Cannot read properties of undefined` 的缺陷，補丁全面引入可選鏈（Optional Chaining），保證長文本與複雜 DOM 抽取不崩潰。
3. **無區塊校驗的 ASAR 打包**：
   社區版使用的舊版 Electron 未啟用二進制級別的區塊雜湊校驗，只需常規 `asar pack` 即可生效，不需修補 Mach-O 二進制或 `Info.plist`。

---

### 三、 官方正式版 (`26.1016.62342`) 深入除錯與修復 SOP (Step-by-Step)

官方正式版採用現代 Electron 31+ 架構與 Owl 容器，具備極為嚴苛的多層安全防護，必須依序穿透以下四道核心關卡：

#### 1. 突破 Electron 31+ ASAR 三重完整性硬鎖
- **二進制 Mach-O 哨兵放行 (Fail-Open)**：
  在 `/Volumes/disk1/Apps/Codex.app/Contents/Frameworks/Codex Framework.framework/Versions/Current/Codex Framework` 中定位哨兵特徵 `AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A`（偏移 291447080），將結構體中的 `used` 位元組由 `1` 修改為 `0`。這會觸發 `kIntegrityDictionaryDigest.used == false` 邏輯，使二進制驗證直接返回 `true`。
- **ASAR 區塊級雜湊與 Info.plist 雙重對齊**：
  `validateBufferIntegrity` 底層報錯格式為 `(${s} vs ${e.hash})`（實際計算值 vs Header 宣告值）。對 `main-JI9qDiXp.js` 完成補丁後，提取實際二進制區塊重算 SHA256，精確寫入 ASAR Header 的 `integrity.hash` 與 `integrity.blocks`。隨後重算新 Header 字串的 SHA256，使用 `/usr/libexec/PlistBuddy` 寫入 `Info.plist` 的 `ElectronAsarIntegrity:Resources/app.asar:hash`。

#### 2. 主進程核心路由與授權補丁 (`main-JI9qDiXp.js`)
在主進程 JavaScript 中注入三重放行邏輯：
1. **`Vd()` 授權放行**：強制覆寫返回值為 `authorized:!0`，繞過 macOS TCC 對 peer 進程的連線授權限制。
2. **`ensureBrowserUseSessionRoute`**：移除嚴苛的 session 匹配檢查，確保 Luna 模型的請求能無條件穿透至 IAB 管道。
3. **`resolveBrowserRoute` 後備值**：在無法即時獲取 session 標籤時注入後備邏輯 `?? this.sessionRoutes.values().next().value`，防止管道路由拋出 null 指針異常。

#### 3. 修復 MachPort 權限與代碼簽名
修改二進制與 ASAR 後，原廠密封簽名失效，會引發 Helper 子進程因 Mach Port 權限被拒而退出（`Permission denied (1100)`）。必須強制執行 Ad-hoc 遞歸重簽署：
```bash
codesign --force --deep --sign - /Volumes/disk1/Apps/Codex.app
xattr -cr /Volumes/disk1/Apps/Codex.app
```

#### 4. 解除 macOS 鑰匙圈 SecurityAgent 密碼死鎖
- **現象**：App 啟動後跳出系統彈窗要求輸入密碼以允許存取「Codex Storage Key」，但輸入任何正確的 macOS 登入密碼均被判定為錯誤，陷入無限彈窗死鎖。
- **根因**：原密鑰條目是由 OpenAI 官方 Developer ID 簽名建立並設定了 ACL。Ad-hoc 自簽名因缺少合法 Team ID，macOS 安全子系統拒絕將新簽名加入 ACL 白名單。
- **徹底解法**：執行以下指令自鑰匙圈資料庫中刪除舊金鑰並終止卡死的彈窗：
  ```bash
  security delete-generic-password -s "Codex Storage Key"
  killall SecurityAgent
  ```
  App 下次啟動時會自動以當前簽名無感建立新的金鑰，不再彈窗。

#### 5. 繞過 Rust `reject_symlink_ancestors` 祖先符號連結崩潰
- **現象**：Luna 模型調用內置瀏覽器時提示：「內置瀏覽器工具啟動失敗，因為執行環境拒絕了含有符號連結的可寫入目錄，所以我還沒能打開網頁。」
- **根因**：`node_repl` 內建 Rust 編寫之安全檢查函式 `reject_symlink_ancestors`。若啟動環境繼承之 `HOME` 變數路徑中含有任何符號連結（如 `~/.agy_profiles -> /Volumes/disk1/...`），該路徑被加入 `writable_roots` 後會直接觸發校驗失敗中斷。
- **徹底解法**：在啟動腳本中強制導出無任何符號連結元件的純物理路徑：
  ```bash
  export HOME="/Users/namobuddha"
  export CODEX_HOME="/Volumes/disk1/data_namobuddha/codex_official_home"
  ```

#### 6. 登入態強綁定機制解析 (`bootstrap-DCRTDDSX.js`)
正式版在建立主視窗前會調用 `refreshLocalRemoteControlClientId`。若使用者未登入 OpenAI 帳號，會拋出 `Sign in to ChatGPT to check remote control authorization` 並終止視窗渲染流程（導致無視窗閃退）。因此首次啟動必須先以乾淨狀態手動完成帳號登入，後續即可全自動受控。

---

### 四、 啟動與環境隔離運行指南

使用專屬的物理隔離啟動腳本，確保正式版與社區版設定檔互不干擾：
```bash
/Volumes/disk1/Apps/launch-codex-official-isolated.sh
```

---

## English

This project provides production-grade patches and an in-depth technical debugging report for the macOS official OpenAI Codex / ChatGPT Desktop App (`26.1016.62342`) and the Community Edition (`26.623.141536`). It resolves In-App Browser (IAB) automation failures, renderer blank screens, symlink path rejections, Keychain ACL deadlocks, and enables seamless `gpt-6-luna` web browsing operations.

---

### I. Community Edition vs. Official Build: In-Depth Comparison

The Community Edition and the Official Build have fundamental generational differences across Electron architecture, integrity verification, IAB IPC pipelines, and sandbox security:

| Metric | Community Edition (`26.623.141536`) | Official Build (`26.1016.62342`) | Architectural & Patch Details |
| :--- | :--- | :--- | :--- |
| **Electron Runtime** | Legacy Electron `40.0.0` / Chromium `128` | Modern Electron / Chromium `155.0.8059.80` | Official build upgrades to modern Owl/Chromium with significantly stricter sandbox and permission constraints. |
| **ASAR Integrity Lock** | **Single-layer (No per-block lock)** | **Triple Integrity Lock** | Community edition only checks package-level integrity; Official build validates Mach-O binary sentinel (`AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A`), ASAR header block hashes, and `Info.plist` `ElectronAsarIntegrity`. |
| **IAB Pipeline** | **External Service (`browser-service`)** | **App-Native Runtime** | Community edition requires spawning `browser-service.mjs` via `host-services` Unix socket; Official build embeds the browser runtime directly into the main process over `/tmp/codex-app-tools/*.sock`. |
| **Main Process JS Patches** | Minimal patches | **Triple Core Bypass (`main-JI9qDiXp.js`)** | Official build requires patching: 1) `Vd()` forced to `authorized:!0` (macOS TCC peer auth bypass); 2) `ensureBrowserUseSessionRoute` bypass; 3) `resolveBrowserRoute` fallback value. |
| **Client Script Patches** | **Heavily patched `browser-client.mjs`** | Preserved native pipe | Community edition patches `wu()` nativePipe trust check, `Qi()` elicitation bypass, and `setResponseMeta?.()` optional chaining; Official build directly utilizes native app tools. |
| **Authentication Binding** | No remote control gate | **Strict Auth Gate (`bootstrap-DCRTDDSX.js`)** | Official build calls `refreshLocalRemoteControlClientId` before window creation. If unauthenticated, it throws and skips `createMainWindow()`, causing silent termination. |
| **macOS Keychain ACL** | Unlikely to deadlock | **Ad-hoc Signature ACL Deadlock** | Re-signing official build ad-hoc causes ACL mismatch on `Codex Storage Key`. Password prompts loop infinitely and reject valid passwords; requires purging the stale generic password. |
| **Symlink Safety** | Handled by launcher | **Rust `reject_symlink_ancestors`** | `node_repl` strictly inspects `writable_roots`. If any ancestor is a symlink (e.g. `~/.agy_profiles`), the Rust kernel halts with an error. |
| **Isolation & Config** | Uses `~/.codex/config.toml` | **Completely Isolated Directory** | Official build uses isolated `CODEX_HOME=/Volumes/disk1/data_namobuddha/codex_official_home` to avoid overwriting community configuration. |

---

### II. Community Edition (`26.623.141536`) Patch Architecture & Implementation Details

The Community Edition is built around an "external sidecar service bridge" model:

1. **External Service Architecture (`browser-service.mjs`)**:
   Instead of embedding browser execution into the main Electron process, the Community Edition relies on a detached Node.js service (`browser-service.mjs`). Codex communicates with it over IPC using Unix domain sockets managed by `host-services`.
2. **Client Patches in `browser-client.mjs`**:
   - **`wu()` Native Pipe Trust Verification**: Removes hardcoded socket signature checks, forcing the client to treat the local Unix socket pipe as trusted.
   - **`Qi()` Elicitation Bypass**: In the unpatched build, high-level automation requests trigger user confirmation dialogues (`elicitation`). The patch bypasses this gate to enable unattended browser automation.
   - **`setResponseMeta?.()` Defensive Chaining**: Prevents `TypeError: Cannot read properties of undefined` crashes during heavy DOM scraping when metadata payloads are incomplete.
3. **Packaging without Block Hash Constraints**:
   Legacy Electron does not enforce Mach-O binary block digests on ASAR packages. Standard `asar pack` is sufficient without touching binary frameworks or `Info.plist`.

---

### III. Official Build (`26.1016.62342`) Debugging & Patch SOP (Step-by-Step)

The Official Build utilizes modern Electron 31+ and Owl containers with multi-layered defenses. Patches must systematically penetrate four distinct subsystems:

#### 1. Piercing Electron 31+ Triple ASAR Integrity Lock
- **Mach-O Sentinel Patch (Fail-Open)**:
  In `Codex Framework.framework/Versions/Current/Codex Framework`, locate sentinel `AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A` (offset 291447080). Change `used` byte from `1` to `0` to trigger `kIntegrityDictionaryDigest.used == false`, making binary integrity verification always return `true`.
- **ASAR Header Block Hash & Info.plist Synchronization**:
  Underlying `validateBufferIntegrity` reports `(${actual} vs ${header})`. Compute the SHA256 of patched `main-JI9qDiXp.js` and write it into both `integrity.hash` and `integrity.blocks`. Then recalculate the SHA256 of the ASAR header JSON string and update `Info.plist` using `PlistBuddy`.

#### 2. Main Process Routing & Authorization Bypass (`main-JI9qDiXp.js`)
Inject a three-tier bypass into main process JavaScript:
1. **`Vd()` Authorization Override**: Force return `{ authorized: !0 }` to bypass macOS TCC peer authentication.
2. **`ensureBrowserUseSessionRoute` Bypass**: Disable mandatory session lookup, allowing Luna browser requests direct entry into the IAB pipeline.
3. **`resolveBrowserRoute` Fallback Value**: Inject `?? this.sessionRoutes.values().next().value` to prevent null-pointer route exceptions when session IDs are unmapped.

#### 3. Resolving MachPort Permissions & Code Signing
Re-pack ASAR and binaries, then apply a recursive ad-hoc signature to eliminate `MachPortRendezvousServer: Permission denied (1100)` IPC crashes:
```bash
codesign --force --deep --sign - /Volumes/disk1/Apps/Codex.app
xattr -cr /Volumes/disk1/Apps/Codex.app
```

#### 4. Relieving macOS Keychain SecurityAgent Deadlock
- **Symptom**: `SecurityAgent` prompts for password to access "Codex Storage Key", but endlessly rejects valid credentials.
- **Cause**: Existing key ACL requires the original OpenAI Team ID. Ad-hoc signatures lack Team ID and cannot be appended to the ACL.
- **Resolution**:
  ```bash
  security delete-generic-password -s "Codex Storage Key"
  killall SecurityAgent
  ```
  The app will recreate a compatible key automatically on the next launch.

#### 5. Bypassing Rust `reject_symlink_ancestors` Crash
- **Symptom**: Luna replies "Browser tool failed to start because the runtime rejected a writable directory containing symlinks."
- **Cause**: `node_repl` enforces `reject_symlink_ancestors` on all `writable_roots`. If `HOME` contains symlinks (e.g., `~/.agy_profiles`), the sandbox immediately aborts.
- **Resolution**: Enforce pure physical paths in the launch wrapper:
  ```bash
  export HOME="/Users/namobuddha"
  export CODEX_HOME="/Volumes/disk1/data_namobuddha/codex_official_home"
  ```

#### 6. Authentication Gate & Lifecycle (`bootstrap-DCRTDDSX.js`)
The official build invokes `refreshLocalRemoteControlClientId` prior to spawning the main window. If unauthenticated, it throws `Sign in to ChatGPT to check remote control authorization` and aborts window creation. Initial manual login is required to initialize tokens.

---

### IV. Launch & Environment Isolation Guide

Run the dedicated isolation launcher to prevent cross-contamination between official and community settings:
```bash
/Volumes/disk1/Apps/launch-codex-official-isolated.sh
```

---

## 日本語

本リポジトリは、macOS 版公式 OpenAI Codex / ChatGPT デスクトップアプリ（バージョン `26.1016.62342`）およびコミュニティ版（`26.623.141536`）を対象とした完全な In-App Browser (IAB) 修正パッチと詳細な技術デバッグレポートを提供します。内蔵ブラウザの起動失敗、白画面クラッシュ、キーチェーン ACL デッドロック、シンボリックリンク検証エラーを根本的に解決し、`gpt-6-luna` による自動ブラウジング操作を実現します。

---

### 一、 コミュニティ版 vs 公式正式版のアーキテクチャ・パッチ比較

コミュニティ版と公式正式版は、Electron 基盤、整合性検証メカニズム、IAB パイプライン実装、サンドボックスセキュリティにおいて根本的な世代差が存在します：

| 評価項目 | コミュニティ版 (`26.623.141536`) | 公式正式版 (`26.1016.62342`) | 技術的な本質とパッチの差異 |
| :--- | :--- | :--- | :--- |
| **Electron 基盤** | 旧版 Electron `40.0.0` / Chromium `128` | 最新 Electron / Chromium `155.0.8059.80` | 正式版は最新の Owl/Chromium 155 コンテナを採用し、サンドボックス保護と権限制限が大幅に厳格化。 |
| **ASAR 整合性検証** | **ブロックレベル検証なし (単層)** | **三重整合性ロック (Triple Lock)** | コミュニティ版は単一のハッシュのみ検証。正式版は Mach-O センチネル構造体 (`AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A`)、ASAR ヘッダーのブロック単位 SHA256 配列、`Info.plist` の三位一体で検証を実施。 |
| **IAB パイプライン** | **外部独立サービス (`browser-service`)** | **アプリ内蔵ネイティブ (`App-Native`)** | コミュニティ版は独立した `browser-service.mjs` を `host-services` 経由で実行。正式版はメインプロセスにネイティブ統合されており、`/tmp/codex-app-tools/*.sock` を利用。 |
| **メインプロセス JS パッチ** | 軽微なパッチのみ | **三重コアバイパス (`main-JI9qDiXp.js`)** | 正式版では以下が必須：<br>1. `Vd()` 関数強制 `authorized:!0`（macOS TCC 権限バイパス）；<br>2. `ensureBrowserUseSessionRoute` セッションルート検証の無効化；<br>3. `resolveBrowserRoute` フォールバック値の注入。 |
| **クライアントスクリプト** | **`browser-client.mjs` を大幅改修** | ネイティブパイプをそのまま維持 | コミュニティ版は `wu()` nativePipe 検証、`Qi()` 緩和、`setResponseMeta?.()` オプショナルチェーンを追加。正式版はネイティブランタイムと直接通信。 |
| **認証とログイン状態強制** | リモート認証ブロックなし | **厳格な認証ゲート (`bootstrap-DCRTDDSX.js`)** | 正式版はウィンドウ生成前に `refreshLocalRemoteControlClientId` を要求。未ログイン時は例外を送出して `createMainWindow()` をスキップし、サイレント終了します。 |
| **キーチェーン ACL 競合** | デッドロックなし | **Ad-hoc 署名による ACL デッドロック** | 正式版は `Codex Storage Key` を使用。Ad-hoc 再署名を行うと Team ID 欠如によりパスワード入力が無限ループで拒否されるため、既存キーの削除が必須。 |
| **シンボリックリンク検証** | ラッパー側で解決済み | **Rust `reject_symlink_ancestors`** | `node_repl` の Rust コアが `writable_roots` 内の祖先シンボリックリンクを拒否。「シンボリックリンクを含む書き込み可能ディレクトリ」エラーの原因となるため物理パスの指定が必須。 |
| **環境分離** | `~/.codex/config.toml` を利用 | **完全分離ディレクトリを使用** | 正式版は `CODEX_HOME=/Volumes/disk1/data_namobuddha/codex_official_home` で完全に物理隔離して運用。 |

---

### 二、 コミュニティ版 (`26.623.141536`) のパッチ構成と実装詳細

コミュニティ版は「外部サイドカーブリッジ」モデルを採用しています：

1. **外部独立サービス (`browser-service.mjs`)**：
   ブラウザ実行部をメインプロセスに内蔵せず、独立した Node.js プロセス `browser-service.mjs` として起動します。Codex 本隊とは `host-services` の Unix ドメインソケットを経由して IPC 通信を行います。
2. **`browser-client.mjs` の修正点**：
   - **`wu()` ネイティブパイプ信頼性検証の緩和**：ソケット通信の証明書検証をバイパスし、ローカルパイプを無条件に信頼環境として認識させます。
   - **`Qi()` 確認プロンプトの自動パス**：通常は高度な自動化や DOM 読み出し時にユーザー承認（`elicitation`）ダイアログが発生しますが、これをスキップして自動実行を可能にします。
   - **`setResponseMeta?.()` 防御的チェーンの適用**：応答メタデータが未定義の場合に `TypeError: Cannot read properties of undefined` でクラッシュする不具合を防ぐため、オプショナルチェーンを全面導入。
3. **ブロックハッシュ制約のない ASAR パッケージング**：
   旧バージョンの Electron はバイナリレベルでの ASAR ブロックハッシュ検証を行わないため、通常の `asar pack` で即座にパッチが有効化されます。

---

### 三、 公式正式版 (`26.1016.62342`) の深層デバッグ・修復手順 (SOP)

公式正式版はモダンな Electron 31+ および Owl コンテナを採用しており、以下の4つの防壁を順次解除する必要があります：

#### 1. Electron 31+ ASAR 三重完全性ロックの解除
- **Mach-O センチネルの Fail-Open 化**：
  `Codex Framework` 内の `AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A`（オフセット 291447080）にある `used` バイトを `1` から `0` に書き換えます。これにより `kIntegrityDictionaryDigest.used == false` と判定され、バイナリ側の整合性検証がバイパスされます。
- **ASAR ブロック単位ハッシュと Info.plist の完全同期**：
  `main-JI9qDiXp.js` の修正後、ファイルの SHA256 を正確に ASAR ヘッダーの `integrity.hash` および `blocks` に書き戻します。さらに新ヘッダー文字列の SHA256 を `Info.plist` の `ElectronAsarIntegrity` に反映させます。

#### 2. メインプロセスのルーティングおよび権限バイパス (`main-JI9qDiXp.js`)
メインプロセスの JavaScript に三重のバイパス処理を注入します：
1. **`Vd()` 権限付与**：戻り値を強制的に `{ authorized: !0 }` とし、macOS TCC によるピアプロセス制限を回避。
2. **`ensureBrowserUseSessionRoute` のバイパス**：厳格なセッション検証を解除し、Luna モデルからのリクエストを直接 IAB パイプラインに通します。
3. **`resolveBrowserRoute` フォールバック値の注入**：`?? this.sessionRoutes.values().next().value` を注入し、セッション未マッピング時の null ポインタ例外を防止。

#### 3. MachPort 権限エラーとコード再署名
ASAR 変更後、Mach Port Rendezvous エラー（`Permission denied (1100)`）によるクラッシュを防ぐため、Ad-hoc 再署名を実施します：
```bash
codesign --force --deep --sign - /Volumes/disk1/Apps/Codex.app
xattr -cr /Volumes/disk1/Apps/Codex.app
```

#### 4. キーチェーン SecurityAgent デッドロックの解除
- **症状**：起動時に「Codex Storage Key」のパスワード入力を求められ、正しいパスワードを入力しても無限ループで拒否される。
- **原因**：既存キーの ACL が OpenAI 公式の Team ID を要求しているため、Ad-hoc 署名では ACL 更新が拒否される。
- **恒久解決策**：既存の競合キーをキーチェーンから削除します：
  ```bash
  security delete-generic-password -s "Codex Storage Key"
  killall SecurityAgent
  ```
  次回の起動時に、現在の署名に基づいた新しいキーが自動作成されます。

#### 5. Rust `reject_symlink_ancestors` シンボリックリンク検証クラッシュの回避
- **症状**：Luna が「シンボリックリンクを含む書き込み可能ディレクトリが拒否されたため、ブラウザを起動できませんでした」と返答する。
- **原因**：`node_repl` の Rust コアが `writable_roots` を検査する際、`HOME` にシンボリックリンクが含まれていると即座にプロセスを中断する。
- **恒久解決策**：ラッパースクリプトで純粋な物理絶対パスを環境変数に指定します：
  ```bash
  export HOME="/Users/namobuddha"
  export CODEX_HOME="/Volumes/disk1/data_namobuddha/codex_official_home"
  ```

#### 6. 認証状態とウィンドウ生成ライフサイクルの解析 (`bootstrap-DCRTDDSX.js`)
正式版はウィンドウ描画前に `refreshLocalRemoteControlClientId` を実行します。未ログインの場合は例外を送出し、メインウィンドウ生成を行わずに終了します。初回のみクリーンな環境で手動ログインを完了させる必要があります。

---

### 四、 起動および環境分離ガイド

設定ファイルの競合を防ぐ専用の分離起動スクリプトを使用してください：
```bash
/Volumes/disk1/Apps/launch-codex-official-isolated.sh
```

---

## Downloads (Releases)

[GitHub Releases](https://github.com/obhasashare2024-namo/codex-macos-iab-patched/releases) より完全なビルド済みパッケージをダウンロードいただけます：
- `Codex-Official-Patched-26.1016.62342-macOS.tar.zst` (1.10 GiB)
- `Codex-Community-Patched-26.623.141536-macOS.tar.zst` (680 MiB)
- `SHA256SUMS.txt`
