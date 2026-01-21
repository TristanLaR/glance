; Glance NSIS Installer Hooks for File Associations
; Registers .md and .markdown files with Glance

; FileAssociation macros (inline since NSIS doesn't support !include for local files in Tauri)
!define registerExtension "!insertmacro registerExtension"
!define unregisterExtension "!insertmacro unregisterExtension"

!macro registerExtension executable extension description
  Push "${executable}"
  Push "${extension}"
  Push "${description}"
  Call registerExtensionCall
!macroend

!macro unregisterExtension extension description
  Push "${extension}"
  Push "${description}"
  Call un.unregisterExtensionCall
!macroend

Function registerExtensionCall
  ; Retrieve parameters
  Exch $R0 ; description
  Exch
  Exch $R1 ; extension
  Exch
  Exch 2
  Exch $R2 ; executable
  Push $0
  Push $1

  ; Read current association (for backup during uninstall)
  ReadRegStr $1 HKCR $R1 ""
  StrCmp $1 "" NoBackup
    StrCmp $1 $R0 NoBackup
      WriteRegStr HKCR $R1 "backup_val" $1
  NoBackup:

  ; Create file extension key
  WriteRegStr HKCR $R1 "" $R0

  ; Create file type key with shell commands
  WriteRegStr HKCR $R0 "" $R0
  WriteRegStr HKCR "$R0\shell" "" "open"
  WriteRegStr HKCR "$R0\shell\open\command" "" '"$R2" "%1"'
  WriteRegStr HKCR "$R0\DefaultIcon" "" "$R2,0"

  Pop $1
  Pop $0
  Pop $R2
  Pop $R1
  Pop $R0
FunctionEnd

Function un.unregisterExtensionCall
  ; Retrieve parameters
  Exch $R0 ; description
  Exch
  Exch $R1 ; extension
  Push $0
  Push $1

  ; Check if our association exists
  ReadRegStr $0 HKCR $R1 ""
  StrCmp $0 $R0 0 NoOwn

  ; Check for backup value
  ReadRegStr $1 HKCR $R1 "backup_val"
  StrCmp $1 "" 0 Restore
    ; No backup - delete the key
    DeleteRegKey HKCR $R1
    Goto NoOwn

  Restore:
    ; Restore backup value
    WriteRegStr HKCR $R1 "" $1
    DeleteRegValue HKCR $R1 "backup_val"

  NoOwn:
    ; Delete file type key
    DeleteRegKey HKCR $R0

  Pop $1
  Pop $0
  Pop $R1
  Pop $R0
FunctionEnd

; Post-install hook: Register file associations
!macro NSIS_HOOK_POSTINSTALL
  ${registerExtension} "$INSTDIR\glance.exe" ".md" "Glance.MarkdownFile"
  ${registerExtension} "$INSTDIR\glance.exe" ".markdown" "Glance.MarkdownFile"

  ; Notify Windows that file associations have changed
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0x0000, p 0, p 0)'
!macroend

; Post-uninstall hook: Unregister file associations
!macro NSIS_HOOK_POSTUNINSTALL
  ${unregisterExtension} ".md" "Glance.MarkdownFile"
  ${unregisterExtension} ".markdown" "Glance.MarkdownFile"

  ; Notify Windows that file associations have changed
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0x0000, p 0, p 0)'
!macroend
