; Polox for Windows: the setup program (Inno Setup 7, https://jrsoftware.org/isinfo.php).
;
; Built by tools\release\build_installer.py, which passes:
;   /DAppVersion=1.29.0          the game's version (project.godot config/version)
;   /DSourceDir=<folder>         an exported build: Polox.exe, and optionally web\, polox.apk, polox.json
;   /DOutputDir=<folder>         where the setup program is written
;   /DOutputName=<file name>     without .exe
;   /DNoticesDir=<folder>        LICENSE, THIRD_PARTY_NOTICES.md and the engine's notices
;
; What it installs and where (docs\RELEASES.md "Windows layout"):
;   program files   {app}: by default %LOCALAPPDATA%\Programs\Polox ("just me", no administrator
;                   needed), or C:\Program Files\Polox when "all users" is chosen
;   your data       %LOCALAPPDATA%\Polox\PersonalData, made by the game on its first start. The setup
;                   never writes there and the uninstaller only removes it when asked to.
;   the marker      {app}\polox-install.json tells the game it is an installed copy
;                   (scripts\core\personal_data.gd INSTALL_MARKER) and which portable PersonalData
;                   folders to bring over.
;
; Command line, besides Inno Setup's own (/SILENT, /VERYSILENT, /DIR=, /CURRENTUSER, /ALLUSERS, /LOG=):
;   /IMPORTFROM="C:\Old Polox"   bring over that portable copy's worlds (the folder with Polox.exe,
;                                or its PersonalData folder)
;   uninstaller: /REMOVEDATA     also delete %LOCALAPPDATA%\Polox\PersonalData (never by default)

#ifndef AppVersion
  #error Pass /DAppVersion=x.y.z (tools\release\build_installer.py does)
#endif
#ifndef SourceDir
  #error Pass /DSourceDir=<exported build folder>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef OutputName
  #define OutputName "Polox-" + AppVersion + "-Setup"
#endif
#ifndef NoticesDir
  #define NoticesDir ""
#endif

#define AppName "Polox"
#define AppExe "Polox.exe"
#define InstallMarker "polox-install.json"
#define HasPhoneFiles FileExists(SourceDir + "\web\index.html")
#define HasAndroidApp FileExists(SourceDir + "\polox.apk")

[Setup]
; AppId never changes: it is how an upgrade finds the copy that is already installed.
AppId={{A6EE18BD-0D52-4538-8DC6-0C266E96603F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Polox
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
; "Just me" needs no administrator; the dialog lets the player choose "all users" instead.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
SetupIconFile={#SourcePath}\..\..\..\assets\icon\polox.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
; An upgrade closes a running Polox first (it would hold Polox.exe open) and offers to start it again.
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
UsePreviousTasks=yes
; No licence page: the GPL asks nothing of someone who only installs and plays. The licence
; and the third-party notices are installed into {app}\licenses and the Start menu links to them.
#ifdef Sign
; build_installer.py --sign "<signtool command with $f>" defines the "signtool" tool and Sign.
SignTool=signtool
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Types]
#if HasPhoneFiles || HasAndroidApp
Name: "full"; Description: "Polox and the files for playing on your phone"
Name: "compact"; Description: "Polox only"
Name: "custom"; Description: "Choose"; Flags: iscustom
#else
; Only the game is in this setup: one type, and the page that would offer a choice is skipped.
Name: "full"; Description: "Polox"
#endif

[Components]
#if HasPhoneFiles || HasAndroidApp
Name: "game"; Description: "Polox"; Types: full compact custom; Flags: fixed
#else
Name: "game"; Description: "Polox"; Types: full; Flags: fixed
#endif
#if HasPhoneFiles
Name: "phone"; Description: "Phone Link files (play the same worlds in your phone's browser)"; Types: full
#endif
#if HasAndroidApp
Name: "android"; Description: "Polox for Android (the app Phone Link offers to your phone)"; Types: full
#endif

[Tasks]
Name: "desktopicon"; Description: "Put a Polox shortcut on the desktop"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\{#AppExe}"; DestDir: "{app}"; Components: game; Flags: ignoreversion
#if HasPhoneFiles
Source: "{#SourceDir}\web\*"; DestDir: "{app}\web"; Components: phone; Flags: ignoreversion recursesubdirs createallsubdirs
#endif
#if HasAndroidApp
Source: "{#SourceDir}\polox.apk"; DestDir: "{app}"; Components: android; Flags: ignoreversion
Source: "{#SourceDir}\polox.json"; DestDir: "{app}"; Components: android; Flags: ignoreversion skipifsourcedoesntexist
#endif
#if NoticesDir != ""
Source: "{#NoticesDir}\*"; DestDir: "{app}\licenses"; Components: game; Flags: ignoreversion
#endif

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
#if HasPhoneFiles
; The Phone Link host: only the server and its small window (host.bat in a source checkout).
Name: "{group}\{#AppName} Phone Link"; Filename: "{app}\{#AppExe}"; Parameters: "--audio-driver Dummy -- --host"; WorkingDir: "{app}"; Comment: "Keeps Polox serving your phone without opening the game"; Components: phone
#endif
#if NoticesDir != ""
Name: "{group}\{#AppName} licences and notices"; Filename: "{app}\licenses"
#endif
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Play {#AppName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Written by this setup after the files (see WriteInstallMarker), so the uninstaller is told about it.
Type: files; Name: "{app}\{#InstallMarker}"
; Written by the game at its first start: the shortcut beside Polox.exe that opens your worlds' folder
; (scripts/core/personal_data.gd, INSTALL_DATA_LINK).
Type: files; Name: "{app}\Personal data.url"

[Code]
var
  ImportPage: TInputQueryWizardPage;

{ The PersonalData folder a portable copy keeps, given the folder the player chose: either the copy's
  own folder (PersonalData is inside it) or that PersonalData folder itself. '' when neither. }
function PortableDataFolder(Chosen: String): String;
begin
  Result := '';
  Chosen := RemoveBackslashUnlessRoot(Trim(Chosen));
  if Chosen = '' then
    Exit;
  if DirExists(AddBackslash(Chosen) + 'PersonalData') then
    Result := AddBackslash(Chosen) + 'PersonalData'
  else if FileExists(AddBackslash(Chosen) + 'settings.json') or DirExists(AddBackslash(Chosen) + 'slots') then
    Result := Chosen;
end;

function RequestedImport: String;
begin
  Result := ExpandConstant('{param:IMPORTFROM|}');
  if (Result = '') and (ImportPage <> nil) then
    Result := ImportPage.Values[0];
end;

procedure BrowseForOldCopy(Sender: TObject);
var
  Folder: String;
begin
  Folder := ImportPage.Values[0];
  if BrowseForFolder('Choose the old Polox folder (the one with Polox.exe in it):', Folder, False) then
    ImportPage.Values[0] := Folder;
end;

{ An optional step, so it is a text box that may stay empty plus a Browse button (Inno Setup's own
  folder page refuses an empty box). }
procedure InitializeWizard;
var
  Browse: TNewButton;
begin
  ImportPage := CreateInputQueryPage(wpSelectTasks,
    'Bring your worlds along',
    'Did you play a portable copy of Polox before?',
    'If you have a Polox folder from before (the one with Polox.exe and a PersonalData folder in it), ' +
    'choose it here. Your worlds, settings and add-ons are copied into this installation the first ' +
    'time it starts. The old folder is left exactly as it is.' + #13#10#13#10 +
    'Leave this empty to start fresh, or if you are updating a Polox that is already installed.');
  ImportPage.Add('Old Polox folder (optional):', False);
  ImportPage.Values[0] := ExpandConstant('{param:IMPORTFROM|}');
  Browse := TNewButton.Create(ImportPage);
  Browse.Parent := ImportPage.Surface;
  Browse.Caption := 'Browse...';
  Browse.Width := ScaleX(90);
  Browse.Height := ScaleY(25);
  Browse.Left := ImportPage.Edits[0].Left;
  Browse.Top := ImportPage.Edits[0].Top + ImportPage.Edits[0].Height + ScaleY(8);
  Browse.OnClick := @BrowseForOldCopy;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
#if !(HasPhoneFiles || HasAndroidApp)
  if PageID = wpSelectComponents then
    Result := True;
#endif
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (ImportPage <> nil) and (CurPageID = ImportPage.ID) and (Trim(ImportPage.Values[0]) <> '') then
    if PortableDataFolder(ImportPage.Values[0]) = '' then
    begin
      MsgBox('That folder has no Polox worlds in it (no PersonalData folder). ' +
        'Choose the folder that contains Polox.exe, or clear the box to skip this step.', mbError, MB_OK);
      Result := False;
    end;
end;

{ JSON string contents for a Windows path: forward slashes (the game reads either), quotes escaped. }
function JsonPath(Path: String): String;
begin
  Result := Path;
  StringChangeEx(Result, '\', '/', True);
  StringChangeEx(Result, '"', '\"', True);
end;

// polox-install.json in the program folder: marks this copy as installed and lists what to bring over.
// A PersonalData folder already inside the program folder means the setup ran over a portable copy:
// list it too. (Written with // because a brace comment would end at the first constant's brace.)
procedure WriteInstallMarker;
var
  Lines: TArrayOfString;
  Imports, Chosen, InPlace: String;
begin
  Imports := '';
  Chosen := PortableDataFolder(RequestedImport);
  if Chosen <> '' then
    Imports := '"' + JsonPath(Chosen) + '"';
  InPlace := ExpandConstant('{app}\PersonalData');
  if DirExists(InPlace) and (CompareText(InPlace, Chosen) <> 0) then
  begin
    if Imports <> '' then
      Imports := Imports + ', ';
    Imports := Imports + '"' + JsonPath(InPlace) + '"';
  end;
  SetArrayLength(Lines, 5);
  Lines[0] := '{';
  Lines[1] := '  "layout": "installed",';
  Lines[2] := '  "version": "{#AppVersion}",';
  Lines[3] := '  "import_from": [' + Imports + ']';
  Lines[4] := '}';
  if not SaveStringsToUTF8FileWithoutBOM(ExpandConstant('{app}\{#InstallMarker}'), Lines, False) then
    MsgBox('Setup could not write ' + ExpandConstant('{app}\{#InstallMarker}') + '. ' +
      'Polox will still run, and will keep your worlds beside Polox.exe or in Documents instead.', mbError, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    WriteInstallMarker;
end;

function UninstallShouldRemoveData: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/REMOVEDATA') = 0 then
      Result := True;
end;

{ Uninstalling removes the program only. Your worlds stay unless you say otherwise: the question is
  asked with "No" as the default, and a silent uninstall never deletes them without /REMOVEDATA. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataFolder: String;
  Remove: Boolean;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;
  DataFolder := ExpandConstant('{localappdata}\Polox\PersonalData');
  if not DirExists(DataFolder) then
    Exit;
  Remove := UninstallShouldRemoveData;
  if (not Remove) and (not UninstallSilent) then
    Remove := MsgBox('Polox is uninstalled. Your worlds, settings and add-ons are still in:' + #13#10 +
      DataFolder + #13#10#13#10 +
      'Keep them? (Choose Yes to keep them for the next time you install Polox. ' +
      'Choose No to delete them for good.)', mbConfirmation, MB_YESNO or MB_DEFBUTTON1) = IDNO;
  if Remove then
  begin
    DelTree(DataFolder, True, True, True);
    RemoveDir(ExpandConstant('{localappdata}\Polox'));
  end;
end;
