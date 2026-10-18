{/////////////////////////////////////////////////////////////////////////
//
//  Dos Navigator Open Source 1.51.08
//  Based on Dos Navigator (C) 1991-99 RIT Research Labs
//
//  This programs is free for commercial and non-commercial use as long as
//  the following conditions are aheared to.
//
//  Copyright remains RIT Research Labs, and as such any Copyright notices
//  in the code are not to be removed. If this package is used in a
//  product, RIT Research Labs should be given attribution as the RIT Research
//  Labs of the parts of the library used. This can be in the form of a textual
//  message at program startup or in documentation (online or textual)
//  provided with the package.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
//
//  1. Redistributions of source code must retain the copyright
//     notice, this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer in the
//     documentation and/or other materials provided with the distribution.
//  3. All advertising materials mentioning features or use of this software
//     must display the following acknowledgement:
//     "Based on Dos Navigator by RIT Research Labs."
//
//  THIS SOFTWARE IS PROVIDED BY RIT RESEARCH LABS "AS IS" AND ANY EXPRESS
//  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
//  GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
//  IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
//  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
//  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The licence and distribution terms for any publically available
//  version or derivative of this code cannot be changed. i.e. this code
//  cannot simply be copied and put under another distribution licence
//  (including the GNU Public Licence).
//
//////////////////////////////////////////////////////////////////////////}
{$I STDEFINE.INC}

unit progress;

{$V-}

interface

uses
  Drivers, Defines, Views, Dialogs, Collect
  ;

const
cmUpdateGauge = 12000;
cmResetGauge = 12001;
cmAddGauge = 12002;

type
  TPercentGauge = class;
  TBarGauge = class;

  { shows how much of the work is done, in per cent (MaxValue is 100 %) }
  TPercentGauge = class(TView)
    MaxValue, CurValue: LongInt;
    procedure AddProgress(Progress: LongInt);
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    constructor Create(const Bounds: TRect; AMaxValue: LongInt);
    function SolveForX(Y, Z: LongInt): Integer;
    function SolveForY(X, Z: LongInt): Integer;
    procedure UpdateView(Progress: LongInt); virtual;
    end;

  { the same as a bar }
  TBarGauge = class(TPercentGauge)
    procedure Draw; override;
    end;
  TWhileView = class;

  TWhileView = class(TGroup)
    {Cat: this type is in the plugin model; change with extreme care!}
    Lines: TCollection;
    But: TButton;
    QuitNormal: Boolean;
    Top, Bottom: String[SizeOf(String)-1];
    constructor Create(const Bounds: TRect);
    procedure Write(N: Integer; S: String); overload;
    function GetPalette: TPalette; override;
    function Valid(C: Word): Boolean; override;
    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    destructor Destroy; override;
    procedure ClearInterior;
    { The copy window offers the second button "Background" (cmCopyBackground, dn#40 part 4); Value = False takes it away again,
      the window of a copy that is in the background has only "Stop". }
    procedure OfferBackground(Value: Boolean);
  private
    Side: (sdLeft, sdRight);
    BgBut: TButton;
    BackgroundOffered: Boolean;
    procedure InsBut;
    end;

procedure DispatchEvents(InfoView: TWhileView; var CancelParam: Boolean);

{ The same for a copy in the background (dn#40, part 4b-3): the event goes to the whole program, so that the panels work; Esc and
  the Cancel button still stop the copy, and a command that would change what the copy reads or writes is dropped
  (CopyJobs.BackgroundCopyBlocks). }
procedure DispatchEventsBackground(InfoView: TWhileView; var CancelParam: Boolean);

implementation
uses
  mainapp, Commands, CopyJobs, Dos, TitleSet, basics, strutil, fileutil, TvGlyphs, Messages
  ;

constructor TPercentGauge.Create(const Bounds: TRect; AMaxValue: LongInt);
  begin
  inherited Create(Bounds);
  CurValue := 0;
  MaxValue := AMaxValue;
  EventMask := EventMask or evBroadcast;
  end;

{ x is y per cent of z: the whole part of z * y / 100 }
function TPercentGauge.SolveForX(Y, Z: LongInt): Integer;
  begin
  Result := Trunc(Z * Y / 100);
  end;

{ y per cent is x of z }
function TPercentGauge.SolveForY(X, Z: LongInt): Integer;
  begin
  if Z <> 0 then
    Result := Trunc(X * 100 / Z)
  else
    Result := 0;
  end;

procedure TPercentGauge.UpdateView(Progress: LongInt);
  begin
  CurValue := Progress;
  DrawView;
  end;

procedure TPercentGauge.AddProgress(Progress: LongInt);
  begin
  UpdateView(CurValue + Progress);
  end;

procedure TPercentGauge.Draw;
  var
    Row: TDrawBuffer;
    Attr: Word;
    Text: String[10];
    Percent: LongInt;
  begin
  Attr := GetColorW(1);
  Percent := SolveForY(CurValue, MaxValue);
  FormatStr(Text, '%-3d%%', Percent);
  MoveChar(Row[0], ' ', Attr, Size.X);
  MoveStr(Row[0], Text, Attr);
  WriteLineC(0, 0, Size.X, Size.Y, Row);
  end;

procedure TPercentGauge.HandleEvent(var Event: TEvent);
  begin
  inherited HandleEvent(Event);
  if Event.What <> evBroadcast then
    Exit;
  if Event.Message.Command = cmUpdateGauge then
    UpdateView(Event.Message.InfoLong)
  else if Event.Message.Command = cmAddGauge then
    AddProgress(Event.Message.InfoLong)
  else if Event.Message.Command = cmResetGauge then
    begin
    MaxValue := Event.Message.InfoLong;
    UpdateView(0);
    end;
  end;

procedure TBarGauge.Draw;
  var
    Row: TDrawBuffer;
    Attr: Word;
    Filled: Integer;
  begin
  Attr := GetColorW(1);
  Filled := SolveForX(SolveForY(CurValue, MaxValue), Size.X);
  if Filled > Size.X then
    Filled := Size.X;
  MoveGlyph(Row[0], glShadeLight, Attr, Size.X);
  MoveGlyph(Row[0], glShadeDark, Attr, Filled);
  WriteLineC(0, 0, Size.X, Size.Y, Row);
  end;
procedure TWhileView.InsBut;
  var
    R: TRect;
    X: Integer;
  begin
  if BgBut <> nil then
    begin
    BgBut.Free;
    BgBut := nil;
    end;
  if BackgroundOffered then
    begin
    { "Stop" (12 columns), two spaces, "Background" (16 columns), together in the middle of the window }
    X := (Size.X-30) div 2;
    R := TRect.Create(X, Size.Y-3, X+12, Size.Y-1);
    But := TButton.Create(R, GetString(dlStop), cmCancel, bfDefault);
    Insert(But);
    R := TRect.Create(X+14, Size.Y-3, X+30, Size.Y-1);
    BgBut := TButton.Create(R, GetString(dlCopyBackground), cmCopyBackground, bfNormal);
    Insert(BgBut);
    Exit;
    end;
  R := TRect.Create(1, Size.Y-3, 13, Size.Y-1);
  But := TButton.Create(R, GetString(dlStop), cmCancel, bfDefault);
  But.Options := But.Options or ofCenterX;
  Insert(But);
  end;

procedure TWhileView.OfferBackground(Value: Boolean);
  begin
  if Value = BackgroundOffered then
    Exit;
  BackgroundOffered := Value;
  Lock;
  But.Free;
  But := nil;
  InsBut;
  UnLock;
  DrawView;
  end;

constructor TWhileView.Create(const Bounds: TRect);
  var
    I: Integer;
  begin
  inherited Create(Bounds);
  QuitNormal := False;
  BgBut := nil;
  BackgroundOffered := False;
  Options := (Options or ofCentered or ofTopSelect) and not ofSelectable;
  Lines := TLineCollection.Create(Bounds.B.Y-Bounds.A.Y, 10, False);
  for I := 0 to Bounds.B.Y-Bounds.A.Y-2 do
    Lines.Insert(NewStr(''));
  SetState(sfShadow, True);
  InsBut;
  Top := '';
  Bottom := '';
  end;

procedure TWhileView.Write(N: Integer; S: String);
  var
    R: TRect;
    B: TDrawBuffer;
    I: Integer;
    S1: String;
  begin
  if N < Lines.Count then
    begin
    if CnvString(Lines.At(N)) = S then
      Exit;
    Lines.AtFree(N);
    end
  else
    Exit;
  Lines.AtInsert(N, NewStr(S));
  if Length(S) > Size.X-4 then
    begin
    Lock;
    R.A.Y := Origin.Y;
    R.B.Y := R.A.Y+Size.Y;
    if Side = sdLeft then
      begin
      R.B.X := Origin.X+Size.X+(Length(S)-Size.X+4) div 2;
      R.A.X := R.B.X-Length(S)-4;
      end
    else
      begin
      R.A.X := Origin.X-(Length(S)-Size.X+4) div 2;
      R.B.X := R.A.X+Length(S)+4;
      end;
    Boolean(Side) := not Boolean(Side);
    Locate(R);
    But.Free;
    But := nil;
    InsBut;
    UnLock;
    DrawView;
    end
  else
    begin
    FillChar(S1[1], Size.X-2, ' '); {JO}
    SetLength(S1, Size.X-2);
    Move(S[1], S1[(Size.X-Length(S)) div 2], Length(S));
    WriteStr(1, N+1, S1, 7);
    end;
  end { TWhileView.Write };

procedure TWhileView.ClearInterior;
  var
    I, C: Integer;
  begin
  C := Lines.Count-1;
  Lines.FreeAll;
  for I := 0 to C do
    Lines.Insert(NewStr(''));
  DrawView;
  end;

procedure TWhileView.SetState(AState: Word; Enable: Boolean);
  var
    WindowCommands: TCommandSet;
  begin
  inherited SetState(AState, Enable);
  if AState = sfSelected then
    begin
    SetState(sfActive, Enable);
    if Top <> '' then
      SetTitle(Top);
    WindowCommands := CommandSetOf([cmNext, cmPrev]);
    if Enable then
      EnableCommands(WindowCommands)
    else
      DisableCommands(WindowCommands);
    end;
  end;

function TWhileView.GetPalette: TPalette;
  const
    P: String[Length(CDialog)] = CDialog;
  begin
  GetPalette := MakePalette(P);
  end;

procedure TWhileView.HandleEvent(var Event: TEvent);
  var
    P: TPoint;
    R: TRect;
    ToBg: Boolean;

  procedure MoveView;
    begin
    if Desktop = nil then
      begin
      ClearEvent(Event);
      Exit;
      end;
    R := Desktop.GetExtent;
    Inc(R.A.Y, Size.Y-1);
    SetState(sfDragging, True);
    DrawView;
    DragView(Event, dmDragMove, R, Size, Size);
    ClearEvent(Event);
    end;

  begin
  R := Owner.GetExtent;
  case Event.What of
    evKeyDown:
      case DNKeyCode(Event) of
        kbTab, kbShiftTab:
          { dn#40: while "Background" is offered, Tab moves the default button (Enter) between "Stop" and "Background" }
          if BackgroundOffered and (BgBut <> nil) and (But <> nil) then
            begin
            BgBut.AmDefault := not BgBut.AmDefault;
            But.AmDefault := not BgBut.AmDefault;
            But.DrawView;
            BgBut.DrawView;
            ClearEvent(Event);
            end;
        kbESC, kbEnter:
          begin
          ToBg := (DNKeyCode(Event) = kbEnter) and BackgroundOffered and (BgBut <> nil) and BgBut.AmDefault;
          Event.What := evCommand;
          if ToBg then
            begin
            Event.Message.Command := cmCopyBackground;
            Event.Message.InfoPtr := BgBut;
            end
          else
            begin
            Event.Message.Command := cmCancel;
            Event.Message.InfoPtr := But;
            end;
          if Application <> nil then
            Application.PutEvent(Event);
          ClearEvent(Event);
          end;
        kbLeft:
          begin
          if Origin.X+Size.X > 1 then
            MoveTo(Origin.X-1, Origin.Y);
          ClearEvent(Event);
          end;
        kbRight:
          begin
          if Origin.X < R.B.X-1 then
            MoveTo(Origin.X+1, Origin.Y);
          ClearEvent(Event);
          end;
        kbUp:
          begin
          if Origin.Y > 0 then
            MoveTo(Origin.X, Origin.Y-1);
          ClearEvent(Event);
          end;
        kbDown:
          begin
          if Origin.Y < R.B.Y-1 then
            MoveTo(Origin.X, Origin.Y+1);
          ClearEvent(Event);
          end;
      end {case};
    evMouseDown:
      begin
      P := MakeLocal(Event.Mouse.Where);
      if P.Y = 0 then
        MoveView;
      end;
    evCommand:
      case Event.Message.Command of
        cmGetName:
          PString(Event.Message.InfoPtr)^:= Top;
        cmResize:
          MoveView;
        cmClose, cmQuit:
          if not QuitNormal then
            ClearEvent(Event);
      end {case};
  end {case};
  inherited HandleEvent(Event);
  end { TWhileView.HandleEvent };

procedure TWhileView.Draw;
  var
    B: TDrawBuffer;
    C1, C2: Byte;
    I: Integer;
    PS: PString;
    R: TRect;
  begin
  if Length(Top) > Size.X-4 then
    begin
    Lock;
    R.A.Y := Origin.Y;
    R.B.Y := R.A.Y+Size.Y;
    if Side = sdLeft then
      begin
      R.B.X := Origin.X+Size.X+(Length(Top)-Size.X+4) div 2;
      R.A.X := R.B.X-Length(Top)-4;
      end
    else
      begin
      R.A.X := Origin.X-(Length(Top)-Size.X+4) div 2;
      R.B.X := R.A.X+Length(Top)+4;
      end;
    Boolean(Side) := not Boolean(Side);
    Locate(R);
    But.Free;
    But := nil;
    InsBut;
    UnLock;
    end;
  if Length(Bottom) > Size.X-4 then
    begin
    Lock;
    R.A.Y := Origin.Y;
    R.B.Y := R.A.Y+Size.Y;
    if Side = sdLeft then
      begin
      R.B.X := Origin.X+Size.X+(Length(Bottom)-Size.X+4) div 2;
      R.A.X := R.B.X-Length(Bottom)-4;
      end
    else
      begin
      R.A.X := Origin.X-(Length(Bottom)-Size.X+4) div 2;
      R.B.X := R.A.X+Length(Bottom)+4;
      end;
    Boolean(Side) := not Boolean(Side);
    Locate(R);
    But.Free;
    But := nil;
    InsBut;
    UnLock;
    end;
  C1 := GetColorW(2+Byte(GetState(sfDragging)));
  C2 := GetColorW(7);
  MoveGlyph(B[0], glDblH, C1, Size.X);
  if Top <> '' then
    MoveStr(B[(Size.X-Length(Top)) div 2-1], ' '+Top+' ', C1);
  SetCellGlyph(B[0], glDblDR);
  SetCellGlyph(B[Size.X-1], glDblDL);
  WriteLineC(0, 0, Size.X, 1, B);
  MoveGlyph(B[0], glDblH, C1, Size.X);
  if Bottom <> '' then
    MoveStr(B[(Size.X-Length(Bottom)) div 2-1], ' '+Bottom+' ', C1);
  SetCellGlyph(B[0], glDblUR);
  SetCellGlyph(B[Size.X-1], glDblUL);
  WriteLineC(0, Size.Y-1, Size.X, 1, B);

  SetCellGlyph(B[0], glDblV);
  SetCellGlyph(B[Size.X-1], glDblV);
  for I := 0 to Size.Y-5 do
    begin
    MoveChar(B[1], ' ', C2, Size.X-2);
    if I < Lines.Count then
      begin
      PS := Lines.At(I);
      if PS <> nil then
        MoveStr(B[(Size.X-Length(PS^)) div 2], PS^, C2);
      end;
    WriteLineC(0, I+1, Size.X, 1, B);
    end;
  MoveChar(B[1], ' ', C2, Size.X-2);
  WriteLineC(0, But.Origin.Y, But.Origin.X, 2, B);
  WriteLineC(But.Origin.X+But.Size.X, But.Origin.Y, Size.X, 2,
    B[But.Origin.X+But.Size.X]);
  But.Draw;
  end { TWhileView.Draw };

function TWhileView.Valid(C: Word): Boolean;
  begin
  Result := (C <> cmQuit) and (C <> cmClose) and inherited Valid(C);
  end;

destructor TWhileView.Destroy;
  begin
  Lines.Free;
  Lines := nil;
  inherited Destroy;
  end;

{ The "Background" button of the copy window: the running copy goes to the background (CopyJobs.JobSetBackground) and the window keeps
  only "Stop"; from the next call on the events go to the whole program (DispatchEventsBackground). }
procedure SendToBackground(InfoView: TWhileView; var Event: TEvent);
  begin
  if  (Event.What <> evCommand) or (Event.Message.Command <> cmCopyBackground) or (InfoView.BgBut = nil) or
      (Event.Message.InfoPtr <> InfoView.BgBut)
  then
    Exit;
  InfoView.ClearEvent(Event);
  if JobSetBackground(JobRunning, True) then
    InfoView.OfferBackground(False);
  end;

procedure DispatchEvents(InfoView: TWhileView; var CancelParam: Boolean);
  var
    Event: TEvent;
  begin
  Application.GetEvent(Event);
  SendToBackground(InfoView, Event);
  if  (Event.What = evCommand) and (Event.Message.Command = cmCancel) and
      (Event.Message.InfoPtr = InfoView.But) or
      (Event.What = evKeyDown) and (DNKeyCode(Event) = kbESC)
  then
    begin
    InfoView.ClearEvent(Event);
    CancelParam := True;
    end;
  if  (Event.What <> evNothing)
    { and not ((Event.What = evKeyDown) and
    (DNKeyCode(Event) = kbEnter))}
    then
    {and InfoView.MouseInView(Event.Mouse.Where)
    or (Event.What = evKeyDown) and ((Event.KeyDown.CharScan.ScanCode=kbAltS) or (Event.))
    then Application}InfoView.HandleEvent(Event);
  end;

var
  BlockedNoteShown: Boolean = False;

{ dn#88 step 4: a command held back while the copy runs in the background says why, instead of
  vanishing; a second press while the message is on the screen adds no second one. }
procedure ExplainBlocked;
  begin
  if BlockedNoteShown then
    Exit;
  BlockedNoteShown := True;
  MessageBox(^C + GetString(dlCopyBlocked), nil, mfInformation + mfOKButton);
  BlockedNoteShown := False;
  end;

procedure DispatchEventsBackground(InfoView: TWhileView; var CancelParam: Boolean);
  var
    Event: TEvent;
  begin
  Application.GetEvent(Event);
  { Panel function keys arrive here as evKeyDown; they have not yet become the
    evCommand checked below. Drop the direct copy/move/delete keys while the
    background job owns its source and destination. }
  if (Event.What = evKeyDown) and
    ((DNKeyCode(Event) = kbF5) or (DNKeyCode(Event) = kbF6) or
     (DNKeyCode(Event) = kbF8) or
     { Alt+X becomes cmQuit inside Application.HandleEvent, past the check of the commands below }
     (DNKeyCode(Event) = kbAltX)) then
    begin
    ClearEvent(Event);
    ExplainBlocked;
    end;
  if  (Event.What = evCommand) and (Event.Message.Command = cmCancel) and
      (Event.Message.InfoPtr = InfoView.But) or
      (Event.What = evKeyDown) and (DNKeyCode(Event) = kbESC)
  then
    begin
    InfoView.ClearEvent(Event);
    CancelParam := True;
    end;
  if  (Event.What = evCommand) and BackgroundCopyBlocks(Event.Message.Command) then
    begin
    InfoView.ClearEvent(Event);
    ExplainBlocked;
    end;
  if Event.What <> evNothing then
    Application.HandleEvent(Event);
  end;

end.
