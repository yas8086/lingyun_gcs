; ============================================================================
;  灵云01 地面站 · NSIS 安装包脚本（需 NSIS 3.x Unicode 版）
;
;  功能：
;    - 将 build\LingyunGCS（Windows 软件运行根目录）整体打包为安装包
;    - 安装/卸载均支持 右键 → 以管理员身份运行
;    - 生成桌面快捷方式 + 开始菜单快捷方式 + 卸载入口
;    - 写入"添加或删除程序"注册表项，可在系统设置中卸载
;    - 卸载时保留用户数据目录 data/（截图/录像/曲线快照/导出文件）
;
;  用法：
;    makensis /DOUT=..\build\LingyunGCS installer.nsi
;    （或直接运行 packaging\build_installer.bat）
;    产物：build\LingyunGCS-Setup.exe
; ============================================================================

Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!ifndef OUT
  !define OUT "..\build\LingyunGCS"
!endif

!define APP_NAME     "灵云01 地面站"
!define APP_SHORT    "LingyunGCS"
!define APP_EXE      "LingyunGCS.exe"
!define APP_VERSION  "1.0.0"
!define PUBLISHER    "浙江灵云境界航空科技有限公司"
!define REG_UNINST   "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SHORT}"

; ---------- 安装器属性 ----------
Name "${APP_NAME} ${APP_VERSION}"
OutFile "..\build\${APP_SHORT}-Setup.exe"
InstallDir "$PROGRAMFILES64\${APP_SHORT}"
InstallDirRegKey HKLM "${REG_UNINST}" "InstallLocation"
RequestExecutionLevel admin
SetCompressor /SOLID lzma   ; GStreamer 体积大，lzma 压得小但较慢；追求速度可改 SetCompressor lzma

; ---------- 页面 ----------
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "立即运行 ${APP_NAME}"
!define MUI_FINISHPAGE_NOREBOOTSUPPORT

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

; ---------- 安装 ----------
Section "安装 ${APP_NAME}" SecMain
  ; 整体复制 Windows 软件运行根目录（exe + Qt 运行库 + GStreamer 运行库/插件）
  SetOutPath "$INSTDIR"
  File /r "${OUT}\*.*"

  ; 卸载器
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; 桌面快捷方式
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  ; 开始菜单快捷方式（含卸载入口）
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"

  ; "添加或删除程序"注册表项
  WriteRegStr   HKLM "${REG_UNINST}" "DisplayName"        "${APP_NAME}"
  WriteRegStr   HKLM "${REG_UNINST}" "DisplayVersion"     "${APP_VERSION}"
  WriteRegStr   HKLM "${REG_UNINST}" "Publisher"          "${PUBLISHER}"
  WriteRegStr   HKLM "${REG_UNINST}" "DisplayIcon"        "$INSTDIR\${APP_EXE}"
  WriteRegStr   HKLM "${REG_UNINST}" "UninstallString"    '"$INSTDIR\Uninstall.exe"'
  WriteRegStr   HKLM "${REG_UNINST}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegStr   HKLM "${REG_UNINST}" "InstallLocation"    "$INSTDIR"
  WriteRegDWORD HKLM "${REG_UNINST}" "NoModify"           1
  WriteRegDWORD HKLM "${REG_UNINST}" "NoRepair"           1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${REG_UNINST}" "EstimatedSize"      "$0"
SectionEnd

; ---------- 卸载 ----------
Section "Uninstall"
  ; 先把用户数据目录 data/ 移到临时位置，卸载完成后放回（避免丢失截图/录像/快照）
  ${If} ${FileExists} "$INSTDIR\data\*.*"
    Rename "$INSTDIR\data" "$TEMP\${APP_SHORT}-data"
  ${EndIf}

  RMDir /r "$INSTDIR"

  ; 移除快捷方式
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  ; 移除卸载注册表项
  DeleteRegKey HKLM "${REG_UNINST}"

  ; 恢复用户数据（卸载后安装目录仅剩 data/）
  CreateDirectory "$INSTDIR"
  ${If} ${FileExists} "$TEMP\${APP_SHORT}-data"
    Rename "$TEMP\${APP_SHORT}-data" "$INSTDIR\data"
  ${EndIf}
SectionEnd
