{ DNStdDlg: the standard file dialogs of DN (it replaces DNStdDlg.pas of the archive, which repeated
  StdDlg of Borland TV). The dialog is TFileDialog of tv/ (TvFileDlg); here are the functions that DN calls.

  Not done yet (TODO): the filter of DN (Mask like "*.Ops;-Pas.*;p*.d") is given to the dialog as it is, the
  dialog of tv/ takes ordinary masks; GetFileNameMenu (the choice from a menu, JO) offers no menu and sends the caller to the
  file dialog. }
{$mode objfpc}{$H-}
unit DNStdDlg;

interface

uses
  TvViews, TvFileDlg, TvFiles;

const
  cmFileOpen = TvFileDlg.cmFileOpen;
  cmFileReplace = TvFileDlg.cmFileReplace;
  cmFileClear = TvFileDlg.cmFileClear;
  fdOKButton = TvFileDlg.fdOKButton;
  fdOpenButton = TvFileDlg.fdOpenButton;
  fdReplaceButton = TvFileDlg.fdReplaceButton;
  fdClearButton = TvFileDlg.fdClearButton;
  fdHelpButton = TvFileDlg.fdHelpButton;
  fdNoLoadDir = TvFileDlg.fdNoLoadDir;

type
  TFileCollection = TvFiles.TFileCollection;
  TSortedListBox = TvFileDlg.TSortedListBox;
  TFileInputLine = TvFileDlg.TFileInputLine;
  TFileList = TvFileDlg.TFileList;
  TFileInfoPane = TvFileDlg.TFileInfoPane;
  TFileDialog = TvFileDlg.TFileDialog;

{ The name of a file chosen in the dialog; '' if it was cancelled. }
function GetFileNameDialog(Mask, Title, Name: String; Buttons, HistoryId: Word): String;
{ A choice of a file from a menu; '' and None = True if there is nothing to choose, More = True to choose in the file
  dialog instead. While there is no menu it always answers More (dn#31). }
function GetFileNameMenu(Path, Mask, Default: String; PutNumbers: Boolean; var More, None: Boolean): String;

implementation

uses
  TvApp, TvEvents, TvDialog;

function GetFileNameDialog(Mask, Title, Name: String; Buttons, HistoryId: Word): String;
var
  D: TFileDialog;
  R: Word;
begin
  Result := '';
  D := TFileDialog.Create(Mask, Title, Name, Buttons, HistoryId);
  if TProgram.Application <> nil then
  begin
    R := TProgram.Application.ExecView(D);
    if R <> cmCancel then
      Result := D.GetFileName;
  end;
  D.Free;
end;

function GetFileNameMenu(Path, Mask, Default: String; PutNumbers: Boolean; var More, None: Boolean): String;
begin
  { There is no menu yet: "More" sends every caller to the file dialog (Load palette, the table of xlat). The old
    answer "nothing to choose" made Load palette do nothing at all and the table of xlat never choosable (dn#31). }
  More := True;
  None := False;
  Result := '';
end;

end.
