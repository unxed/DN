{ NetProc: a child process with its three pipes, the transport under the file systems that talk to a remote side through a program
  (a shell on this machine, a client program of the system). NetProc only starts the program, sends bytes to it, takes bytes from it with a
  time limit and ends it; what the bytes mean is for the layer above.

  Read never blocks longer than the time it is given: it answers at once when bytes are there, otherwise waits in short steps up to the
  limit. The answers of Read: more than 0 - that many bytes; 0 - nothing came in time (the program may still run); -1 - the program has
  ended and its pipe is empty. The standard error is read the same way with ReadErr, so a program that fills it cannot stop itself.

  The unit is empty in the DOS build and in DN_MINI, where there is no child process with pipes to start.

  MIT, see LICENSE. }
unit NetProc;

{$mode objfpc}
{$H+}

interface

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}
uses
  SysUtils, Classes, Pipes, Process;

type
  TNetProc = class
  private
    FProc: TProcess;
    FLastError: AnsiString;
    function ReadFrom(Stream: TStream; var Buf; Size, TimeoutMs: Integer): Integer;
  public
    destructor Destroy; override;
    { Starts Exe (a path, or a name that is searched for in PATH) with Args. False and LastError when it cannot be started. }
    function Start(const Exe: AnsiString; const Args: array of AnsiString): Boolean;
    { Sends Data to the standard input; False when the program does not take it any more. }
    function Write(const Data: AnsiString): Boolean;
    { Ends the input: the program sees the end of its standard input. }
    procedure CloseInput;
    { Up to Size bytes of the standard output, waiting at most TimeoutMs milliseconds for the first one (see the head of the unit). }
    function Read(var Buf; Size, TimeoutMs: Integer): Integer;
    { The same for the standard error. }
    function ReadErr(var Buf; Size, TimeoutMs: Integer): Integer;
    { Ends the program if it still runs, and waits for it. Safe to call again. }
    procedure Stop;
    function Running: Boolean;
    { What the program answered when it ended; -1 while it runs or before Start. }
    function ExitCode: Integer;
    property LastError: AnsiString read FLastError;
  end;
{$ENDIF}

implementation

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}

const
  PollStepMs = 5;

destructor TNetProc.Destroy;
begin
  Stop;
  FreeAndNil(FProc);
  inherited Destroy;
end;

function TNetProc.Start(const Exe: AnsiString; const Args: array of AnsiString): Boolean;
var
  I: Integer;
begin
  Result := False;
  Stop;
  FreeAndNil(FProc);
  FLastError := '';
  FProc := TProcess.Create(nil);
  FProc.Executable := Exe;
  for I := 0 to High(Args) do
    FProc.Parameters.Add(Args[I]);
  FProc.Options := [poUsePipes, poNoConsole];
  try
    FProc.Execute;
    Result := True;
  except
    on E: Exception do
    begin
      FLastError := 'cannot start ' + Exe + ': ' + E.Message;
      FreeAndNil(FProc);
    end;
  end;
end;

function TNetProc.Write(const Data: AnsiString): Boolean;
begin
  Result := False;
  if (FProc = nil) or (not FProc.Running) then
    Exit;
  if Data = '' then
    Exit(True);
  try
    FProc.Input.WriteBuffer(Data[1], Length(Data));
    Result := True;
  except
    on E: Exception do
      FLastError := 'cannot write to the program: ' + E.Message;
  end;
end;

procedure TNetProc.CloseInput;
begin
  if FProc <> nil then
    FProc.CloseInput;
end;

function TNetProc.ReadFrom(Stream: TStream; var Buf; Size, TimeoutMs: Integer): Integer;
var
  Waited, Avail: Integer;
  Alive: Boolean;
begin
  Result := 0;
  if (FProc = nil) or (Size <= 0) then
    Exit(-1);
  Waited := 0;
  while True do
  begin
    { Alive is read before the pipe: bytes written just before the program ended are still counted below }
    Alive := FProc.Running;
    Avail := TInputPipeStream(Stream).NumBytesAvailable;
    if Avail > 0 then
    begin
      if Avail > Size then
        Avail := Size;
      Exit(Stream.Read(Buf, Avail));
    end;
    if not Alive then
      Exit(-1);
    if Waited >= TimeoutMs then
      Exit(0);
    Sleep(PollStepMs);
    Inc(Waited, PollStepMs);
  end;
end;

function TNetProc.Read(var Buf; Size, TimeoutMs: Integer): Integer;
begin
  if FProc = nil then
    Exit(-1);
  Result := ReadFrom(FProc.Output, Buf, Size, TimeoutMs);
end;

function TNetProc.ReadErr(var Buf; Size, TimeoutMs: Integer): Integer;
begin
  if FProc = nil then
    Exit(-1);
  Result := ReadFrom(FProc.Stderr, Buf, Size, TimeoutMs);
end;

procedure TNetProc.Stop;
begin
  if FProc = nil then
    Exit;
  try
    if FProc.Running then
      FProc.Terminate(1);
    FProc.WaitOnExit;
  except
    on E: Exception do
      FLastError := 'cannot end the program: ' + E.Message;
  end;
end;

function TNetProc.Running: Boolean;
begin
  Result := (FProc <> nil) and FProc.Running;
end;

function TNetProc.ExitCode: Integer;
begin
  if (FProc = nil) or FProc.Running then
    Result := -1
  else
    Result := FProc.ExitCode;
end;

{$ENDIF}

end.
