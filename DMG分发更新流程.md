# Seal Note：macOS DMG 分发与更新流程

后续每次更新 DMG，按照以下顺序执行：

> 更新版本号 → Release Archive → Developer ID 导出 → Apple 公证 → 装订票据 → 制作 DMG → Gatekeeper 验证

## 1. 更新版本号

在 macOS Target 中更新：

- `MARKETING_VERSION`：例如 `0.3 → 0.4`
- `CURRENT_PROJECT_VERSION`：例如 `3 → 4`

确认版本号：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project EncryptNotes.xcodeproj \
  -scheme EncryptNotesMac \
  -configuration Release \
  -showBuildSettings |
rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
```

## 2. 创建 Release Archive

```bash
VERSION=0.4
ARCHIVE="/tmp/SealNote-${VERSION}.xcarchive"

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild archive \
  -project EncryptNotes.xcodeproj \
  -scheme EncryptNotesMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Automatic
```

检查是否同时包含 Apple Silicon 和 Intel 架构：

```bash
file "$ARCHIVE/Products/Applications/Seal Note.app/Contents/MacOS/Seal Note"
file "$ARCHIVE/Products/Applications/Seal Note.app/Contents/Helpers/sealnote"
```

应看到类似结果：

```text
Mach-O universal binary ... x86_64 ... arm64
```

## 3. 准备 Developer ID 导出配置

创建临时文件 `/tmp/SealNoteDeveloperIDExport.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>BPP589VP97</string>
</dict>
</plist>
```

## 4. 导出 Developer ID App

```bash
EXPORT_DIR="/tmp/SealNote-${VERSION}-DeveloperID"

rm -rf "$EXPORT_DIR"

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -exportArchive \
  -allowProvisioningUpdates \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist /tmp/SealNoteDeveloperIDExport.plist
```

检查签名：

```bash
codesign --verify --deep --strict --verbose=2 \
  "$EXPORT_DIR/Seal Note.app"

codesign --verify --strict --verbose=2 \
  "$EXPORT_DIR/Seal Note.app/Contents/Helpers/sealnote"

codesign -dvvv "$EXPORT_DIR/Seal Note.app"
```

应看到：

```text
Authority=Developer ID Application: Weinan Xu (BPP589VP97)
```

## 5. 上传 Apple 公证

创建 `/tmp/SealNoteDeveloperIDUpload.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>upload</string>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>BPP589VP97</string>
</dict>
</plist>
```

上传：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -exportArchive \
  -allowProvisioningUpdates \
  -archivePath "$ARCHIVE" \
  -exportPath "/tmp/SealNote-${VERSION}-NotaryUpload" \
  -exportOptionsPlist /tmp/SealNoteDeveloperIDUpload.plist
```

成功时会显示：

```text
Uploaded Seal Note
** EXPORT SUCCEEDED **
```

这一步只提交给 Apple 公证服务，不会上传到 Mac App Store。

## 6. 等待并装订公证票据

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun stapler staple \
  "$EXPORT_DIR/Seal Note.app"
```

如果出现 `Record not found`，说明 Apple 仍在处理，等待约 20–60 秒后重试。

成功时会显示：

```text
The staple and validate action worked!
```

验证票据：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun stapler validate \
  "$EXPORT_DIR/Seal Note.app"
```

## 7. 制作 DMG

```bash
DMG_ROOT="/tmp/SealNote-${VERSION}-DMGRoot"
DMG="dist/Seal-Note-${VERSION}.dmg"

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT" dist

cp -R "$EXPORT_DIR/Seal Note.app" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG"

hdiutil create \
  -volname "Seal Note" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG"
```

DMG 中会包含：

- `Seal Note.app`
- `Applications` 快捷方式

用户打开 DMG 后，只需把 App 拖入 Applications。

## 8. 最终验证

验证镜像：

```bash
hdiutil verify "$DMG"
```

挂载：

```bash
hdiutil attach -readonly -nobrowse "$DMG"
```

验证镜像内部的 App：

```bash
APP="/Volumes/Seal Note/Seal Note.app"

codesign --verify --deep --strict --verbose=2 "$APP"

xcrun stapler validate "$APP"

spctl -a -t exec -vv "$APP"

file "$APP/Contents/MacOS/Seal Note"
file "$APP/Contents/Helpers/sealnote"
codesign --verify --strict --verbose=2 "$APP/Contents/Helpers/sealnote"
```

关键结果应为：

```text
accepted
source=Notarized Developer ID
```

卸载镜像：

```bash
hdiutil detach "/Volumes/Seal Note"
```

生成 SHA-256 校验值并查看大小：

```bash
shasum -a 256 "$DMG"
ls -lh "$DMG"
```

## 每次更新的检查清单

- [ ] `MARKETING_VERSION` 已增加
- [ ] `CURRENT_PROJECT_VERSION` 已增加且不能与历史 Build 重复
- [ ] 使用 Release Archive
- [ ] 同时包含 `arm64` 和 `x86_64`
- [ ] 使用 Developer ID Application 签名
- [ ] 使用 Production iCloud profile
- [ ] `Contents/Helpers/sealnote` 已内嵌且签名有效
- [ ] App 与 CLI 的 App Group entitlement 一致
- [ ] Apple 公证成功
- [ ] 公证票据已经 staple
- [ ] DMG 内有 Applications 快捷方式
- [ ] `codesign` 验证通过
- [ ] `xcrun stapler validate` 验证通过
- [ ] `spctl` 返回 `accepted` 和 `source=Notarized Developer ID`
- [ ] 已记录文件大小和 SHA-256
- [ ] 已删除或下架旧 DMG，避免版本混淆

## 当前已验证版本

- 版本：`0.3 (3)`
- 文件：`dist/Seal-Note-0.3.dmg`
- 架构：Apple Silicon + Intel
- 状态：Developer ID 签名、Apple 公证、票据装订和 Gatekeeper 验证均通过
