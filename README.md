# Patched macOS OpenAI Codex / ChatGPT Desktop App (In-App Browser & Luna IAB)

[![Release](https://img.shields.io/github/v/release/obhasashare2024-namo/codex-macos-iab-patched?style=flat-square)](https://github.com/obhasashare2024-namo/codex-macos-iab-patched/releases)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

[English](#english) | [繁體中文](#繁體中文) | [日本語](#日本語)

---

## 繁體中文

本專案提供針對 macOS 官方正式版 OpenAI Codex / ChatGPT Desktop（版本 `26.1016.62342`）及社區版（`26.623.141536`）的完整修復補丁與技術除錯說明，徹底解決內置瀏覽器（IAB, In-App Browser）無法啟動、白屏卡死、以及 `gpt-6-luna` 模型的自動化網頁操作難題。

### 核心技術瓶頸與 Debug 排查 SOP

#### 1. Electron 31+ ASAR 三重完整性校驗穿透
- **Mach-O 哨兵 Slot 繞過**：
  在 `Codex Framework` 二進制中，定位哨兵字串 `AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A`（偏移 291447080），將結構體中的 `used` 位元組置為 `0`。此操作觸發框架內部 `kIntegrityDictionaryDigest.used == false` 邏輯，實現 `fail-open` 繞過二進制摘要比對。
- **ASAR 區塊級雜湊對齊**：
  底層 `validateBufferIntegrity` 報錯機制為 `got vs expected` 格式。修補 `main-JI9qDiXp.js` 後，必須重新計算檔案本體的 SHA256，精確寫入 ASAR Header 的 `integrity.hash` 與 `integrity.blocks` 陣列，並將 Header 字串的新 SHA256 寫入 `Info.plist` 的 `ElectronAsarIntegrity` 字典，徹底消除 `ASAR Integrity Violation`。

#### 2. MachPort 權限與代碼簽名修復
- 修改 ASAR 及 Info.plist 後，官方封裝簽名失效，會引發 Helper 進程在建立 IPC 時報錯：
  ```text
  ERROR:base/apple/mach_port_rendezvous_mac.cc:256] bootstrap_look_up com.openai.codex.MachPortRendezvousServer.1: Permission denied (1100)
  ```
- 執行 Ad-hoc 深度重簽名：
  ```bash
  codesign --force --deep --sign - /Volumes/disk1/Apps/Codex.app
  ```

#### 3. macOS 鑰匙圈 ACL 死鎖解除
- **病徵**：啟動後彈出 `SecurityAgent`「Codex Storage Key」密碼輸入框，輸入任何正確登入密碼均被拒絕且無限彈窗卡死。
- **根因**：該條目原由官方 Team ID 建立，Ad-hoc 簽名因缺少證書 Team ID 無法寫入 Keychain ACL。
- **解決方案**：
  ```bash
  security delete-generic-password -s "Codex Storage Key"
  ```
  刪除舊條目後重啟，App 將自動建立相容的新金鑰。

#### 4. Rust `reject_symlink_ancestors` 祖先符號連結崩潰排查
- **病徵**：Luna 調用內置瀏覽器時報錯「執行環境拒絕了含有符號連結的可寫入目錄，所以我還沒能打開網頁」。
- **根因**：`node_repl` 內部的 Rust 內核在初始化沙盒時會檢查 `writable_roots`。若當前環境變數繼承了包含符號連結的目錄（如 macOS 下常見的 `~/.agy_profiles` 或 `/var` 軟連結），會直接拋出異常並重置 kernel。
- **解決方案**：啟動環境中強制導出真實實體路徑：
  ```bash
  export HOME="/Users/namobuddha"
  ```

---

## English

This project provides verified patches and a technical debugging guide for the macOS official OpenAI Codex / ChatGPT Desktop App (`26.1016.62342`) and Community Edition (`26.623.141536`), fixing In-App Browser (IAB) automation failures and enabling full `gpt-6-luna` web browsing operations.

### Key Debugging Highlights:
1. **Electron 31+ ASAR Integrity Bypass**: Setting the sentinel slot (`AGbevlPCksUGKNL8TSn7wGmJEuJsXb2A`) `used` byte to `0` for fail-open authorization, along with precise block-level hash synchronization in the ASAR header and `Info.plist`.
2. **MachPort Rendezvous Fix**: Resolving IPC `Permission denied (1100)` errors by applying deep ad-hoc code signing (`codesign --force --deep --sign -`).
3. **Keychain ACL Deadlock Relief**: Resolving the recurring `Codex Storage Key` prompt loop by purging stale Keychain entries via `security delete-generic-password -s "Codex Storage Key"`.
4. **Rust Symlink Ancestor Safety**: Resolving `node_repl` kernel crashes by ensuring workspace writable roots are pure physical paths without symlink ancestors.

---

## 日本語

本リポジトリは、macOS 版公式 OpenAI Codex / ChatGPT デスクトップアプリ（バージョン `26.1016.62342`）およびコミュニティ版向けの In-App Browser (IAB) 修正パッチとデバッグ解説を提供します。`gpt-6-luna` によるブラウザ自動操作が完全に動作します。

---

## Releases & Downloads

請至 [GitHub Releases](https://github.com/obhasashare2024-namo/codex-macos-iab-patched/releases) 下載完整打包套件：
- `Codex-Official-Patched-26.1016.62342-macOS.tar.zst`
- `Codex-Community-Patched-26.623.141536-macOS.tar.zst`
- `SHA256SUMS.txt`
EOF