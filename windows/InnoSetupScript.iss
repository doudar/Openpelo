[Setup]
AppId={{DOUDAR-OPENPELO-FLUTTER-ID}}
AppName=OpenPelo
AppVersion=1.0.0
;AppVerName=OpenPelo 1.0.0
AppPublisher=doudar
DefaultDirName={autopf}\OpenPelo
DisableProgramGroupPage=yes
; Remove the following line to run in administrative install mode (install for all users.)
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=OpenPelo_Setup_Windows
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The build output is in build/windows/runner/Release
; We need to include everything there
Source: "..\..\build\windows\runner\Release\openpelo.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\OpenPelo"; Filename: "{app}\openpelo.exe"
Name: "{autodesktop}\OpenPelo"; Filename: "{app}\openpelo.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\openpelo.exe"; Description: "{cm:LaunchProgram,OpenPelo}"; Flags: nowait postinstall skipifsilent
