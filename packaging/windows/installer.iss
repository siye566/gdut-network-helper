#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #error SourceDir must be passed by package-windows.ps1
#endif
#ifndef ArtifactDir
  #error ArtifactDir must be passed by package-windows.ps1
#endif

[Setup]
AppId={{2EFDA0BA-3BB5-4EC0-82C4-10B51434EBB5}
AppName=广工校园网助手
AppVersion={#AppVersion}
AppVerName=广工校园网助手 {#AppVersion}
AppPublisher=siye566
AppPublisherURL=https://github.com/siye566/gdut-network-helper
AppSupportURL=https://github.com/siye566/gdut-network-helper/issues
AppUpdatesURL=https://github.com/siye566/gdut-network-helper/releases
DefaultDirName={localappdata}\Programs\GDUT Network Helper
DefaultGroupName=广工校园网助手
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#ArtifactDir}
OutputBaseFilename=gdut-network-helper-{#AppVersion}-windows-x64-setup
UninstallDisplayIcon={app}\gdut_network_helper.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\广工校园网助手"; Filename: "{app}\gdut_network_helper.exe"
Name: "{autodesktop}\广工校园网助手"; Filename: "{app}\gdut_network_helper.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\gdut_network_helper.exe"; Description: "启动广工校园网助手"; Flags: nowait postinstall skipifsilent
