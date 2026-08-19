@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title 灵云01 地面站 - Windows 自包含打包

rem =====================================================================
rem  灵云01 地面站 · Windows 自包含打包脚本
rem
rem  产物根目录：<工程根>\build\LingyunGCS
rem  （即 Windows 软件运行根目录：exe + Qt 运行库 + GStreamer 运行库/插件。
rem   整目录拷到目标机即可运行，目标机无需安装 Qt / GStreamer；
rem   唯一例外：USB 转串口芯片驱动需现场单独装一次。）
rem
rem  用法：
rem    packaging\pack_win.bat
rem
rem  前置条件：
rem    1) 已用 Release 配置构建出 LingyunGCS.exe：
rem         cmake -S . -B build-win -DCMAKE_BUILD_TYPE=Release
rem         cmake --build build-win -j8
rem    2) 本机已装 Qt（含 windeployqt）与 GStreamer runtime，
rem       并在下方按本机实际路径修改 QT_BIN / GST_ROOT。
rem =====================================================================

set "ROOT=%~dp0.."
set "OUT=%ROOT%\build\LingyunGCS"

rem ---------- 按本机环境修改以下三项 ----------
set "QT_BIN=C:\Qt\6.10.1\mingw_64\bin"
set "GST_ROOT=C:\gstreamer\1.0\mingw_x86_64"
set "BUILD_DIR=%ROOT%\build-win"
rem -------------------------------------------

echo [1/7] 检查工具链与构建产物...
if not exist "%QT_BIN%\windeployqt.exe" ( echo   错误：找不到 windeployqt，请检查 QT_BIN 路径 & goto :fail )
if not exist "%GST_ROOT%\bin"            ( echo   错误：找不到 GStreamer runtime，请检查 GST_ROOT 路径 & goto :fail )
if not exist "%GST_ROOT%\lib\gstreamer-1.0" ( echo   错误：GStreamer runtime 缺少插件目录 lib\gstreamer-1.0 & goto :fail )

rem 自动定位 LingyunGCS.exe（MinGW 单配置 Release 在子目录 Release，其他在根）
set "EXE="
if exist "%BUILD_DIR%\Release\LingyunGCS.exe"      set "EXE=%BUILD_DIR%\Release\LingyunGCS.exe"
if not defined EXE if exist "%BUILD_DIR%\LingyunGCS.exe" set "EXE=%BUILD_DIR%\LingyunGCS.exe"
if not defined EXE ( echo   错误：找不到 LingyunGCS.exe，请先构建 Release 版本 & goto :fail )

echo [2/7] 创建输出目录：%OUT%
if not exist "%OUT%"                    mkdir "%OUT%"
if not exist "%OUT%\gstreamer-1.0"      mkdir "%OUT%\gstreamer-1.0"

echo [3/7] 复制可执行文件...
copy /y "%EXE%" "%OUT%\" >nul

echo [4/7] windeployqt 收集 Qt 运行库（dll / platforms / qml / styles ...）...
"%QT_BIN%\windeployqt.exe" --release --no-translations "%OUT%\LingyunGCS.exe"
if errorlevel 1 ( echo   错误：windeployqt 执行失败 & goto :fail )

echo [5/7] 收集 GStreamer 运行库（全部 dll 放 exe 同级，插件加载时从 exe 目录解析依赖）...
copy /y "%GST_ROOT%\bin\*.dll" "%OUT%\" >nul
copy /y "%GST_ROOT%\bin\gst-plugin-scanner.exe" "%OUT%\" >nul 2>nul

echo [6/7] 收集 GStreamer 插件目录（rtspsrc / decodebin / h264 解码 等）...
xcopy /y /e /i "%GST_ROOT%\lib\gstreamer-1.0" "%OUT%\gstreamer-1.0" >nul

echo [7/7] 打包完成！
echo.
echo   产物目录：%OUT%
echo   下一步：把整个 %OUT% 目录复制到 Windows 目标机即可运行
echo   （程序内已按 Windows 分支自动设置 GST_PLUGIN_PATH 指向自带插件）。
echo   注意：目标机首次使用 USB 转串口，需单独安装一次芯片驱动。

rem 可选：追加参数 "/pkg" 时，用 NSIS 直接生成安装包（需本机已装 NSIS）
if /I "%~1"=="/pkg" (
    echo.
    echo [可选] 生成 NSIS 安装包...
    if not exist "%ROOT%\build\LingyunGCS-Setup.exe" (
        call "%ROOT%\packaging\build_installer.bat"
    ) else (
        echo   已存在 build\LingyunGCS-Setup.exe，跳过（删除后重跑可重新生成）。
    )
)
goto :end

:fail
echo.
echo 打包失败，请根据上方错误信息检查后重试。
exit /b 1

:end
exit /b 0
