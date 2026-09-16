; Inno Setup script for BloBnot.
;
; Packages the Flutter Windows build (the exe alone does not run — it needs its
; data/ folder and the plugin DLLs beside it, which is the whole reason this
; installer exists), and optionally the MCP server for AI assistants.
;
; Build with:
;   iscc /DAppVersion=2.2 installer\blobnot.iss
;
; Expects, relative to the repo root:
;   build\windows\x64\runner\Release\   Flutter release output
;   mcp\build\blobnot-mcp.exe           optional, from `npm run build:exe`

#ifndef AppVersion
  #define AppVersion "2.1"
#endif

#define AppName "BloBnot"
#define AppPublisher "Andrii Nazarenko"
#define AppUrl "https://github.com/nazarenko87-cloud/BloBnot"
#define AppExe "blobnot.exe"
#define FlutterOut "..\build\windows\x64\runner\Release"
#define McpExe "..\mcp\build\blobnot-mcp.exe"

; Whether the MCP server was built is decided here, at compile time — an
; app-only build must not offer a component that would install nothing.
#if FileExists(AddBackslash(SourcePath) + McpExe)
  #define HasMcp
#endif

[Setup]
AppId={{8F3C1A72-6D4B-4E19-9C2A-5B7E0D1F4A83}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=BloBnot-{#AppVersion}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Per-user install by default, so no admin prompt is needed.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"

[Types]
Name: "full"; Description: "Full installation"
Name: "compact"; Description: "Notes app only"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "app"; Description: "BloBnot notes app"; Types: full compact custom; Flags: fixed
#ifdef HasMcp
Name: "mcp"; Description: "MCP server — lets Claude read and write your notes"; Types: full
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
#ifdef HasMcp
Name: "registermcp"; Description: "Connect the MCP server to Claude Desktop"; Components: mcp
#endif

[Files]
Source: "{#FlutterOut}\{#AppExe}"; DestDir: "{app}"; Components: app; Flags: ignoreversion
Source: "{#FlutterOut}\*.dll"; DestDir: "{app}"; Components: app; Flags: ignoreversion
Source: "{#FlutterOut}\data\*"; DestDir: "{app}\data"; Components: app; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef HasMcp
Source: "{#McpExe}"; DestDir: "{app}"; Components: mcp; Flags: ignoreversion
#endif

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
#ifdef HasMcp
; Writes the server into claude_desktop_config.json, merging with whatever is
; already there. runascurrentuser: the config lives in the user's profile.
Filename: "{app}\blobnot-mcp.exe"; Parameters: "--register"; \
  Components: mcp; Tasks: registermcp; \
  StatusMsg: "Connecting the MCP server to Claude Desktop..."; \
  Flags: runhidden runascurrentuser
#endif
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

#ifdef HasMcp
[UninstallRun]
; Leave no dangling entry in someone's Claude config after uninstalling.
Filename: "{app}\blobnot-mcp.exe"; Parameters: "--unregister"; \
  RunOnceId: "UnregisterMcp"; Flags: runhidden runascurrentuser skipifdoesntexist
#endif
