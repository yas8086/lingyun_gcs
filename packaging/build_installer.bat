@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title 灵云01 地面站 - NSIS 安装包构建

rem =====================================================================
rem  用 NSIS 将 build\LingyunGCS（Windows 软件运行根目录）打包为安装包。
rem
rem  用法：packaging\build_installer.bat
rem  产物：build\LingyunGCS-Setup.exe
rem
rem  前置条件：
rem    1) 已用 packaging\pack_win.bat 产出 build\LingyunGCS；
rem    2) 本机已装 NSIS 3.x（Unicode 版），并按实际安装路径修改下方 NSIS 变量。
rem =====================================================================

set "ROOT=%~dp0.."

rem ---------- 按本机环境修改 ----------
set "NSIS=C:\Users\20110\dev\nsis-3.11\makensis.exe"
set "SRC=%ROOT%\build\LingyunGCS"
rem -----------------------------------

echo [1/3] 检查输出目录与 NSIS 工具...
if not exist "%SRC%\LingyunGCS.exe" ( echo   错误：找不到 %SRC%\LingyunGCS.exe，请先运行 pack_win.bat & goto :fail )
if not exist "%NSIS%"                   ( echo   错误：找不到 makensis.exe，请检查 NSIS 安装路径 & goto :fail )

echo [2/3] 编译 NSIS 安装脚本（源目录：%SRC%）...
"%NSIS%" /DOUT="%SRC%" "%ROOT%\packaging\installer.nsi"
if errorlevel 1 ( echo   错误：makensis 编译失败 & goto :fail )

echo [3/3] 完成！
echo   安装包：%ROOT%\build\LingyunGCS-Setup.exe
goto :end

:fail
echo.
echo 安装包构建失败，请根据上方错误信息检查后重试。
exit /b 1

:end
exit /b 0