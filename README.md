# Chrome Janitor

A small native macOS app that finds and stops the processes agent sessions leave
behind: orphaned headless Chrome instances that keep `Google Chrome.app` locked,
and the TCP ports nobody remembers opening.

**Tiếng Việt:** xem [Tóm tắt tiếng Việt](#tóm-tắt-tiếng-việt) ở cuối file.

## Why it exists

Coding agents drive Chrome with `--headless=new --remote-debugging-port=…`. When
the shell that launched it exits, the browser is reparented to `launchd` and
keeps running forever — nothing owns it, so nothing ever stops it.

Two consequences you actually feel:

1. The process holds `/Applications/Google Chrome.app` open, so dragging a new
   build into `/Applications` fails with
   *"The operation can't be completed because the item 'Google Chrome.app' is in use."*
2. Its debug port, and every dev server the session started, stay bound.

`kill`-ing them by hand means reading `ps` output and guessing which pid is yours
and which one belongs to the browser window you are looking at. This app does the
guessing, and shows its reasoning.

## What it does

Two tabs over one scan (`ps` + `lsof`, refreshed every 1/3/10s).

### Chrome tab

Every Chrome instance grouped by root process, with its children, debug port,
profile directory, target URL, CPU, memory and uptime.

| Badge | Meaning |
| --- | --- |
| `HEADLESS` | launched with `--headless` / `--remote-debugging-port` |
| `ORPHAN` | headless root whose parent is `launchd` — an agent left it behind |
| `YOUR BROWSER` | visible Chrome. Selected by role, not by parent, see below |
| `HOLDS APP BUNDLE` | has `Google Chrome.app` mapped open — the lock in question |

The classification lives in
[`Model.swift`](Sources/Model.swift) and is deliberately narrow:

```swift
var isOrphan: Bool { ppid == 1 && role == .headlessRoot }
```

A Chrome you opened from the Dock is *also* parented to `launchd`, so `ppid == 1`
alone says nothing about who owns it. Requiring `headlessRoot` is what keeps your
own browser off the kill list.

### Ports tab

Every TCP listener not belonging to Chrome, grouped `pid → port → bound addresses`:

| Badge | Meaning |
| --- | --- |
| `LOCALHOST` | bound to loopback — only this machine can reach it |
| `EXPOSED` | bound to `*` / `::` / `0.0.0.0` — **reachable from your network** |
| `CHROME` | the port owner is a Chrome process (hidden by default) |

Exposed ports are counted in the header in orange, because those are the ones
worth a second look.

## Safety rules

These are the properties the app is built around, not aspirations:

- Nothing is ever killed without a click. **Clean all abandoned** opens a
  confirmation naming the exact pid count.
- A kill targets a pid *tree*: `SIGTERM` the root and its descendants, wait 1.5s,
  then `SIGKILL` whatever survived.
- **Release lock** only ever stops headless roots. If the only thing holding the
  bundle is your visible browser, it says so instead of quitting it — losing
  unsaved tabs is your decision, not a side effect.
- Force-kill is a separate, deliberately labelled action on every row.

## Usage

```
open build/ChromeJanitor.app        # or launch from /Applications
```

1. **Finder says "Google Chrome.app is in use"** → Chrome tab → **Release lock
   (headless only)**. Retry the drag.
2. **Sweep up old sessions** → Chrome tab → **Clean all abandoned** (`⇧⌘D`), or
   select one row and use **Terminate tree** in the detail pane.
3. **Something is holding a port** → Ports tab → filter by port or name →
   **Stop process holding port**. The detail pane shows the full command line
   first, so you can check it is really the leftover server.
4. **Decide what to keep** → click any row: parent pid, start time, CPU, memory,
   debug port, profile dir, command line and the child list.
5. **Watch it live** → *Auto* with a 1/3/10s interval, or `⌘R` to rescan once.

Right-click a row for the same actions without selecting it. The filter box
matches pid, URL and flags on the Chrome tab, and port, process name, address and
command on the Ports tab.

## Build from source

Needs the Swift toolchain from Xcode or the Command Line Tools; there is no
`.xcodeproj` on purpose, so a build is one shell command.

```bash
./build.sh                 # -> build/ChromeJanitor.app
open build/ChromeJanitor.app
```

`build.sh` compiles `Sources/*.swift` for `uname -m` (override with `ARCH=…`),
copies `Resources/Info.plist`, the icon and the `.lproj` folders, then ad-hoc
signs the bundle. Regenerate the icon only if you change the artwork:

```bash
./Tools/makeicon.sh        # Resources/icon-source.png -> Resources/AppIcon.icns
```

Install:

```bash
cp -R build/ChromeJanitor.app "/Applications/Chrome Janitor.app"
codesign --force --sign - "/Applications/Chrome Janitor.app"
```

The signature is ad-hoc, so Gatekeeper may want a right-click → **Open** the
first time. Target is macOS 12+, x86_64 and arm64.

## Repo layout

```
Sources/
  App.swift      SwiftUI App entry, menu commands and shortcuts
  Model.swift    process/port records, role + orphan rules, ps & lsof parsers
  Probe.swift    runs ps / lsof / kill, one scan() feeding both tabs
  Store.swift    observable state, refresh loop, kill tree, release lock
  Views.swift    tab view, Chrome tab, Ports tab, detail panes
  L10n.swift     the whole VI/EN string table
Resources/       Info.plist, AppIcon.icns, icon-source.png, vi|en.lproj
Tools/           makeicon.sh + maskicon.swift (icon grid generator)
build.sh         compile, bundle, sign
```

## Localisation notes

- One `(vi, en)` table in `L10n.swift`; the SwiftUI views observe it, so switching
  language in the header updates immediately.
- AppKit's standard menus do **not** read that table. They need real bundle
  localisation (`Resources/*.lproj/Localizable.strings` plus
  `CFBundleLocalizations`) and an `AppleLanguages` override in the app's own
  defaults domain, which is only read at launch — hence the **Restart** button
  that appears after you switch.
- A duplicated key in the dictionary literal is a runtime trap, not a compile
  error, and it crashes at launch. `build.sh` greps for duplicates and fails the
  build instead.

## Known limits

- TCP listeners only — no UDP, no unix sockets.
- Runs as you: it can neither see nor stop another user's or root's processes.
- "Abandoned" is a heuristic (`ppid == 1` + headless). A headless Chrome started
  by a long-lived supervisor is real work and gets badged `HEADLESS` only.
- Ad-hoc signed, so no notarization and no automatic updates.

## Development notes

Pushing over HTTPS can fail with `HTTP 400` and a misleading
`Everything up-to-date`, because git sends the pack with chunked
transfer-encoding. Send a `Content-Length` instead:

```bash
git -c http.postBuffer=524288000 push
```

## Tóm tắt tiếng Việt

**Tác dụng.** Các phiên agent chạy Chrome ở chế độ headless rồi bỏ lại: tiến trình
mồ côi (cha là `launchd`) giữ mở `/Applications/Google Chrome.app`, khiến thao tác
kéo app vào `/Applications` báo lỗi *"the item is in use"*. Chúng chiếm luôn cả
cổng debug và các dev server mà không ai nhớ đã bật.

**Cách dùng.**

- Tab **Chrome**: liệt kê từng tiến trình Chrome theo cụm tiến trình cha — con,
  kèm badge `BỎ HOANG` / `HEADLESS` / `TRÌNH DUYỆT CỦA BẠN` / `ĐANG GIỮ APP BUNDLE`.
  Gặp lỗi "is in use" → bấm **Giải khoá bundle (chỉ headless)**.
  Dọn loạt → **Dọn hết bỏ hoang** (`⇧⌘D`), có hộp thoại xác nhận số pid.
- Tab **Cổng**: mọi cổng TCP do tiến trình ngoài Chrome đang giữ, gộp theo
  pid → cổng → địa chỉ bind. Badge `MỞ RA MẠNG` nghĩa là bind vào `*`, tức máy
  khác trong cùng mạng truy cập được — cái này nên xem kỹ.
- Bấm vào một dòng để xem cha, thời điểm khởi động, CPU, bộ nhớ, dòng lệnh đầy đủ
  và danh sách tiến trình con trước khi quyết định dừng.
- Đầu trên có bộ đếm, danh sách tự quét lại 1/3/10 giây, `⌘R` để quét ngay.
  Chuột phải vào dòng để dừng ngay hàng đó.

**An toàn.** App không bao giờ tự tay đụng vào Chrome đang hiển thị của bạn: tiêu
 chí "bỏ hoang" đòi hỏi *headless* chứ không chỉ "cha là launchd", và nút giải khoá
 chỉ chọn tiến trình headless. Mọi thao tác dừng đều phải có một cú click.

**Build.** Cần Swift toolchain, không có `.xcodeproj`: `./build.sh` rồi
`open build/ChromeJanitor.app`. Chữ ký ad-hoc nên lần đầu có thể phải chuột phải →
**Open**. Yêu cầu macOS 12 trở lên.
