# Windows 平台编译与开发环境配置指南

灵云01号飞艇地面站（LingyunGCS）Windows 版本搭建指南。项目为 CMake + C++17 + Qt Quick (QML) 架构，摄像头拉流依赖 GStreamer，已内置 Windows 网口检测适配（IP Helper API）。

> 参考基准版本（Linux 开发机实测）：Qt 6.10.1、GStreamer 1.24.2。Windows 侧建议使用相同或更高版本，避免 QML/行为差异。

---

## 1. 依赖总览

| 组件 | 用途 | 建议版本 | 备注 |
|---|---|---|---|
| Visual Studio 2022 | C++ 编译工具链（MSVC） | 17.x | 勾选"使用 C++ 的桌面开发" |
| Qt 6 | UI 框架 | 6.10.x（MSVC 2022 64-bit） | 需含 Quick/Qml/Charts/SerialPort/Network 等组件 |
| GStreamer | RTSP 拉流与录像 | 1.24+（MSVC 版） | **runtime 与 development 两个安装包都要装** |
| pkg-config | CMake 定位 GStreamer | pkg-config 或 pkgconf | GStreamer 官方包不带，需单独装 |
| CMake | 构建系统 | 3.21+ | VS2022 自带，也可独立安装 |
| Ninja（可选） | 构建执行器 | 最新 | VS 自带；比 msbuild 快 |
| Git | 源码管理 | 最新 | |

Qt 组件依赖清单（对应 CMakeLists `find_package`）：

```
Core  Gui  Widgets  SerialPort  Test  Quick  Qml  QuickControls2  Charts  Network
```

---

## 2. 软件安装

### 2.1 Visual Studio 2022

1. 下载 [Visual Studio 2022 Community](https://visualstudio.microsoft.com/zh-hans/vs/)（免费）。
2. 安装器勾选工作负载 **"使用 C++ 的桌面开发"**，右侧默认组件保持勾选（含 MSVC v143、Windows 10/11 SDK、CMake、Ninja）。

### 2.2 Qt 6

1. 下载 [Qt 在线安装器](https://www.qt.io/download-qt-installer)，登录 Qt 账号。
2. 选择安装目录，例如 `C:\Qt`。
3. 选择 **Qt 6.10.x → MSVC 2022 64-bit** 组件（无需 MinGW，无需 Android/WSK 等）。
4. "开发者与设计工具"里可顺带勾选 **CMake/Ninja**（若用 VS 自带的可不勾）。

安装结果示例：`C:\Qt\6.10.1\msvc2022_64\`。

### 2.3 GStreamer（关键依赖）

1. 下载 [GStreamer MSVC 版](https://gstreamer.freedesktop.org/download/)，**同一版本号的两 个包都要装**：
   - `gstreamer-1.0-msvc-x86_64-<版本>.msi`（runtime）
   - `gstreamer-1.0-devel-msvc-x86_64-<版本>.msi`（development，含头文件/库/pkgconfig）
2. 安装时选择 **Complete（完整安装）**，默认路径 `C:\gstreamer\1.0\msvc_x86_64\`。
3. ⚠️ runtime 与 devel 必须同为 **MSVC** 架构（不要 MinGW 版），且版本完全一致。

验证安装：

```bat
dir C:\gstreamer\1.0\msvc_x86_64\lib\pkgconfig\gstreamer-1.0.pc
```

### 2.4 pkg-config

CMake 通过 `pkg_check_modules` 查找 GStreamer，Windows 需单独提供 pkg-config 可执行文件，任选其一：

- **方式 A（推荐）**：`choco install pkgconfiglite`（需先装 Chocolatey），或到 pkgs.org 下载 pkg-config-lite 解压到 `C:\tools\pkg-config` 并加入 PATH。
- **方式 B**：安装 [MSYS2](https://www.msys2.org/)，在 MSYS2 shell 中 `pacman -S pkgconf mingw-w64-x86_64-pkg-config`，然后把 `C:\msys64\usr\bin` 与 `C:\msys64\mingw64\bin` 加入 PATH（仅借用工具，编译仍用 MSVC）。

验证：

```bat
pkg-config --modversion gstreamer-1.0
```

### 2.5 Git

[Git for Windows](https://git-scm.com/download/win)，默认选项即可。建议保持 `core.autocrlf=false`（避免源码行尾被改写）：

```bat
git config --global core.autocrlf false
```

---

## 3. 环境变量（系统级）

打开"系统属性 → 高级 → 环境变量"，在**系统变量**中新建/修改（按实际安装路径调整）：

| 变量 | 值 |
|---|---|
| `Path` 追加 | `C:\gstreamer\1.0\msvc_x86_64\bin` |
| `PKG_CONFIG_PATH` | `C:\gstreamer\1.0\msvc_x86_64\lib\pkgconfig` |
| `GSTREAMER_1_0_ROOT_MSVC_X86_64` | `C:\gstreamer\1.0\msvc_x86_64\`（GStreamer MSI 一般自动创建） |

设置后重开终端验证：

```bat
where gst-launch-1.0
pkg-config --cflags gstreamer-1.0
gst-launch-1.0 videotestsrc num-buffers=1 ! fakesink
```

三条都成功说明 GStreamer 与 pkg-config 就绪。

---

## 4. 获取源码

```bat
git clone <仓库地址> lingyun_gcs
cd lingyun_gcs
```

- 源码（C++/QML/SVG 资源/CMake/tests）全部入库，SVG 通过 `qt_add_resources` 编译进 exe，运行时无外部资源依赖。
- `.gitignore` 忽略的均为构建产物与运行期生成物（`build/`、`*.csv`、`diag/`），不影响编译。
- 无需从 Linux 机器复制任何文件。

---

## 5. 配置与编译

### 5.1 生成构建目录

**方式 A：Ninja（推荐，速度快）**——在"Developer Command Prompt for VS 2022"（x64）中执行：

```bat
cmake -B build -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_PREFIX_PATH=C:\Qt\6.10.1\msvc2022_64
```

**方式 B：Visual Studio 生成器**（习惯用 IDE 打开 sln 的选这个）：

```bat
cmake -B build -G "Visual Studio 17 2022" -A x64 ^
  -DCMAKE_PREFIX_PATH=C:\Qt\6.10.1\msvc2022_64
```

`CMAKE_PREFIX_PATH` 指向 Qt 的 MSVC 安装目录，CMake 据此找到全部 Qt 组件。

若 `pkg-config` 仍找不到 GStreamer，可显式传入：

```bat
  -DPKG_CONFIG_EXECUTABLE=C:\tools\pkg-config\pkg-config.exe ^
  -DCMAKE_PREFIX_PATH=C:\Qt\6.10.1\msvc2022_64;C:\gstreamer\1.0\msvc_x86_64
```

### 5.2 编译

```bat
:: Ninja
cmake --build build

:: VS 生成器
cmake --build build --config Release
```

产物：`build\LingyunGCS.exe`（单一目标，与 Linux 一致）。

### 5.3 单元测试

```bat
cd build
ctest --output-on-failure -C Release
```

共 7 项测试（帧解析/JSON 解析/告警引擎/配置管理/协议等），全部应 PASS。

---

## 6. 运行时部署（解决缺 DLL）

exe 运行需要 Qt 与 GStreamer 的 DLL。两种方式：

**开发调试（简单）**：确保 `C:\gstreamer\1.0\msvc_x86_64\bin` 已在 PATH（第 3 节），Qt DLL 用 PATH 指向 `C:\Qt\6.10.1\msvc2022_64\bin`（可同样追加到 PATH），直接运行：

```bat
build\LingyunGCS.exe
```

**独立发布（拷给别的电脑用）**：用 windeployqt 收集 Qt 依赖，再手动补 GStreamer 插件：

```bat
build\windeployqt.bat 2>nul
windeployqt --qmldir src\qml build\LingyunGCS.exe
xcopy /E /I C:\gstreamer\1.0\msvc_x86_64\bin\*.dll build\
xcopy /E /I C:\gstreamer\1.0\msvc_x86_64\lib\gstreamer-1.0 build\lib\gstreamer-1.0
```

发布机若未装 GStreamer，`lib\gstreamer-1.0`（插件目录）必须随 exe 一起带，并在启动前设置 `GST_PLUGIN_PATH` 指向该目录。

---

## 7. IDE 开发环境

### 7.1 Visual Studio（推荐）

1. 装 [Qt Visual Studio Tools](https://marketplace.visualstudio.com/items?itemName=TheQtCompany.QtVisualStudioTools-19123) 扩展。
2. 扩展 → Qt VS Tools → Qt Options → Add → 选择 `C:\Qt\6.10.1\msvc2022_64`。
3. 直接打开 `build\LingyunGCS.sln`（5.1 方式 B 生成），或 VS "打开文件夹"模式识别 CMakePresets。
4. 调试：右键 LingyunGCS → 设为启动项 → F5。调试前确认 PATH 含 GStreamer bin（否则启动即报缺 DLL）。

### 7.2 VS Code + CMake Tools（轻量）

1. 装扩展：CMake Tools、Qt tools。
2. `F1 → CMake: Select a Kit` 选 Visual Studio amd64；`CMake: Select Variant` 选 Release。
3. 底部状态栏 Configure/Build/Run；`launch.json` 中 `"env"` 加入 GStreamer 的 PATH。

---

## 8. 运行期注意事项（Windows 特有）

| 事项 | 说明 |
|---|---|
| 串口 | 设备管理器确认 COM 号；界面串口下拉自动枚举 `COMx`，波特率 115200 |
| 网口数据源 | 默认监听 UDP 20000；首次运行 Windows 防火墙弹窗需**允许专用+公用网络**，否则收不到遥测 |
| 网口物理链路检测 | 已适配 Windows（IP Helper API `GetAdaptersAddresses`），插拔网线状态正确 |
| 摄像头 RTSP | 思翼默认 `192.168.144.25:8554/main.264`；本机需有 192.168.144.x 网段地址 |
| 配置文件位置 | `QStandardPaths::AppConfigLocation` → `%APPDATA%\<组织>\<应用>\`，自检配置 `check_config.json` 等在此 |
| 视频渲染 | GStreamer 管道 + QQuickPaintedItem 方案与平台无关，Windows 正常工作 |

---

## 9. 常见问题排查

| 现象 | 原因与解决 |
|---|---|
| CMake 报 `gstreamer-1.0 NOT FOUND` | PKG_CONFIG_PATH 未设/未装 pkg-config；按第 2.4/3 节补齐后删除 build 目录重新 configure |
| 找到的是 MinGW 版 GStreamer 或架构不符 | runtime/devel 必须同为 MSVC x86_64；`pkg-config --variable=targets gstreamer-1.0` 检查 |
| 编译期找不到 Qt 头文件 | `-DCMAKE_PREFIX_PATH` 未指向 Qt MSVC 目录，或 Qt 安装时未勾 MSVC 组件 |
| 启动闪退 / 缺 `Qt6Quick.dll`、`gstreamer-1.0-0.dll` | PATH 未含 Qt bin 与 GStreamer bin；或发布未做第 6 节部署 |
| 拉流黑屏但无报错 | GStreamer 插件不全（重装 devel 包选 Complete）；或 `GST_PLUGIN_PATH` 未指向插件目录 |
| Charts 曲线不显示 | Qt 安装缺 QtCharts 模块，重开在线安装器补勾 |
| ctest 个别用例失败 | 先确认在 build 目录内执行且带 `-C Release`；配置残留可删 `%APPDATA%` 下应用目录重试 |
| 中文界面乱码 | 源码 UTF-8；VS 中打开 QML 确认编码为 UTF-8（勿用 GBK 保存） |

---

## 10. 与 Linux 平台的差异说明

- 构建目标一致：仅 `LingyunGCS` 单一 exe（+ 7 个测试），无平台分支目标。
- 网口链路检测：Linux 用 netlink/IOCTL，Windows 用 `iphlpapi`（CMakeLists 自动链接，无需手工处理）。
- 串口：跨平台 QSerialPort，无 `/dev/ttyUSB` 概念，Windows 为 COM 口。
- 其余业务逻辑（协议解析、告警、能源拓扑、自检、云台控制）为纯跨平台代码，两平台行为一致。

---

## 11. 推荐环境自检清单

```
□ VS2022 可新建并编译 C++ 控制台工程
□ Qt 安装含 msvc2022_64 目录
□ gst-launch-1.0 在 PATH 中可执行
□ pkg-config --modversion gstreamer-1.0 输出 1.24+
□ git clone 源码后 cmake configure 无 WARNING 涉及 GStreamer/Qt
□ cmake --build 成功产出 LingyunGCS.exe
□ ctest 7/7 PASS
□ 运行 exe：串口下拉有 COM 列表、网口监听可开启、摄像头页可拉流
```
