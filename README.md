# psd-preview

Windows 资源管理器 PSD/PSB 缩略图与预览窗格扩展，使用 Zig 0.17.1 编写。
产物为单个进程内 COM DLL（`psd_preview.dll`），无外部运行时依赖：缩略图由
`dllhost.exe` 隔离加载，预览窗格由 `prevhost.exe` 隔离加载，DLL 不会注入
`explorer.exe`。

## 构建与测试

前置条件：Zig `0.17.1`（`build.zig.zon` 已锁定 `minimum_zig_version`）。

```powershell
zig build                 # 输出 zig-out\bin\psd_preview.dll
zig build test            # 运行解析器与渲染单元测试
zig fmt build.zig src     # 格式化（提交前执行）
```

目标固定为 `x86_64-windows-gnu`。仓库无第三方依赖。

## CI 与发布

- `.github/workflows/ci.yml`：push 到 `master` 或 Pull Request 时，在
  `windows-latest` 上用 Zig 0.17.1 执行 `zig fmt --check`、`zig build`
  与 `zig build test`。
- `.github/workflows/release.yml`：推送 `v*` 形式的 tag 时触发。工作流
  先校验 tag 版本（去掉 `v` 前缀）与 `build.zig.zon` 中 `.version` 完全
  一致，不一致直接失败、不构建不发布；一致才执行测试、ReleaseSafe 构建，
  并把 `psd_preview.dll` 打包为 `psd-preview-v<版本>-x86_64-windows.zip`
  发布到对应 GitHub Release。
- 发版流程：先修改 `build.zig.zon` 的 `.version` 并合入 `master`，再打
  同版本 tag，例如版本 `0.1.0` 对应 `git tag v0.1.0` 后推送 tag。

## 注册与卸载

当前用户注册（免管理员，推荐）：

```powershell
regsvr32 /s /n /i:user zig-out\bin\psd_preview.dll
regsvr32 /u /s /n /i:user zig-out\bin\psd_preview.dll
```

- `DllInstall` 解析 `/i:` 后的参数：`user` 写 `HKCU\Software\Classes`，
  `machine` 写 `HKLM\Software\Classes`，`auto` 在已提权时优先 `HKLM`
  并回退 `HKCU`、未提权时只写 `HKCU`；无参数时默认为 `user`。
- 直接调用 `DllRegisterServer` / `DllUnregisterServer`（不带 `/i:`）走
  `auto` 模式。
- 注册内容：CLSID `{7B9E4A10-3C82-4F51-9D2A-8E1C6B04F291}` 的
  `InprocServer32`（`ThreadingModel=Apartment`）、`AppID`
  `{6D2B5079-2F0B-48DD-AB7F-97CEC514D30B}`（指向 Windows 自带的共享
  Prevhost 代理；本扩展从不创建或删除 `HKCR\AppID` 本身，卸载不会影响
  其他预览器）、`.psd` / `.psb` 及 `SystemFileAssociations` 下的
  `ShellEx`（缩略图 IID `{E357FCCD-A995-4576-B01F-234630154E96}`、
  预览 IID `{8895B1C6-B41F-4C1C-A562-0D564250836F}`），以及
  `PreviewHandlers` 条目。注册/卸载后通过 `SHChangeNotify` 通知 Shell 刷新。
- 初始化只实现 `IInitializeWithStream`，不实现 `IInitializeWithFile`，
  这是保持宿主隔离的关键。

## 支持范围

解码走两条路径，优先快路径：

1. 内嵌预览：扫描 Image Resources 中的 `8BIM 0x040C` 块，`format == 1`
   时取出 JPEG 切片，交系统 WIC 解码。
2. 合并图回退：解析文件尾 Image Data 并转换为预乘 BGRA。

| 维度 | 支持 |
| :--- | :--- |
| 格式 | PSD（版本 1）、PSB（版本 2） |
| 位深 | 1 / 8 / 16 / 32-bit（32-bit 按线性值处理，不套 sRGB gamma） |
| 色彩模式 | 0 Bitmap、1 灰度、2 索引色（768 字节调色板）、3 RGB、4 CMYK（反向存储已处理） |
| 压缩 | 0 Raw、1 PackBits RLE（含 PSB 4 字节行长表） |
| 预览交互 | 棋盘格透明底、滚轮锚点缩放（0.1x–16x）、拖拽平移、双击切换自适应/1:1 |

安全上限：单边最大 `100000` px、解码/工作预算 `256 MB`、缩略图请求
钳制为 `1024` px；超限或畸形文件返回 `E_FAIL`，由 Shell 回退默认图标。

## 不支持（明确边界）

- 压缩 `2` ZIP 与 `3` ZIP Prediction：返回 `UnsupportedCompression`。
- 色彩模式 `7` 多通道、`8` 双色调、`9` Lab：返回 `UnsupportedColorMode`。
- 旧版 `0x0409` 未压缩缩略图块：不解析，仅 `0x040C` JPEG 生效。
- 真正的流式解析：`IStream` 内容会被整文件读入内存后再解析，大文件受
  上述 `256 MB` 预算约束；方案文档中的 Seek 跳过图层树尚未实现。

## 与方案文档的差异

参考文档 `zig_windows_psd_psb.md` 建议 Direct2D 预览 + WIC Fant 缩放，
当前实现有意保持更小的 GDI 管线，差异如下，后续如需再升级：

- 预览窗格使用 GDI `AlphaBlend` + `HALFTONE` 拉伸模式绘制，无 GPU
  加速、无 DPI 感知声明、无 HUD 信息角标。
- 缩略图缩放使用最近邻采样（`render/thumbnail.zig`），WIC 仅用于内嵌
  JPEG 解码，未使用 `IWICBitmapScaler` 的 Fant 插值，边缘质量弱于文档方案。
- 无独立 `preview_harness.exe` 调试宿主，调试依赖真实 Shell 宿主。

## 故障排查

- 预览不出现：确认已用当前 DLL 路径注册；换路径后需重新注册。删除
  缩略图缓存或重启资源管理器可排除旧缓存影响。
- 重新编译时 DLL 被占用：文件被 `dllhost.exe` / `prevhost.exe` 锁定
  属正常现象，关闭预览窗格并等待宿主退出后再编译，不要结束
  `explorer.exe`。
- 某些文件回退默认图标：多为 ZIP 压缩、Lab/双色调模式或超出预算的
  超大文件，属上面的明确不支持范围。
- 卸载残留：用同一 DLL 执行 `/u` 卸载；它只删除自身 CLSID、ShellEx
  与 PreviewHandlers 条目，不动共享 AppID。
