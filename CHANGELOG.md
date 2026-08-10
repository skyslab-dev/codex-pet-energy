# Changelog

All notable changes to Codex Pet Energy are documented here.

## Unreleased

- Added a seven-day token activity summary beneath the weekly usage limit.
- Aligned the displayed date range and daily token buckets to each account's current weekly reset cycle.
- Added compact token totals, highlighted the current day, and preserved the original single-limit overlay when token history is unavailable.
- Added local `account/usage/read` polling without storing or uploading token history.
- Expanded token parsing, reset-cycle aggregation, date formatting, and compact-number coverage, bringing the test suite to 20 cases.

## 0.3.0 — 2026-08-07

- Redesigned the energy overlay with native macOS 26 Liquid Glass and an adaptive macOS 14+ fallback.
- Added semantic energy colors and compact 224×174 dual-window and 224×116 single-window layouts.
- Added automatic Launch at Login registration on first run.
- Adapted limit labels, ordering, and panel height to the windows currently returned by Codex.
- Restored hover detection and drag following for the current split-window Codex Pet layout while preserving legacy compatibility.
- Made full rate-limit reads authoritative so removed usage windows no longer remain stale.
- Added Swift 5.10 build compatibility for the Liquid Glass fallback and expanded the test suite to 16 cases.

## 0.2.0 — 2026-07-10

- Added a compact 207×178 Apple-style glass usage panel.
- Added live 5-hour and weekly usage with reset countdowns.
- Added hover activation, automatic dismissal, and drag following.
- Added multi-display and screen-edge-aware placement.
- Added menu-bar refresh, enable/disable, Launch at Login, and quit controls.
- Added robust Codex app-server lifecycle management and reconnect behavior.
- Reduced idle CPU usage through cached window IDs and adaptive polling.
- Added strict concurrency validation and expanded the test suite to 12 cases.
