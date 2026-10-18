{ CopyJobs: the model of the background copy jobs (dn#40, part 4). A job is one copy that the user sent to the background:
  it is queued, runs, and ends done, failed or cancelled. This unit only keeps the list and the rules of the states:
    queued -> running -> done | failed          a job that has not ended can also be cancelled (queued or running -> cancelled)
  It copies nothing and shows nothing: the copy loop reports into it (JobProgress), asks it whether to stop (JobIsCancelled),
  and the list window (part 4b) reads it (JobAt). Every call that cannot be done in the current state returns False and changes
  nothing. Not thread-safe: whoever runs the copy in the background serialises the calls.
  MIT, see LICENSE. }
unit CopyJobs;
{$mode objfpc}{$H-}

interface

type
  TJobState = (jsQueued, jsRunning, jsDone, jsFailed, jsCancelled);

  { What a queued copy needs to start later without the dialog and without the panels (dn#88 step 5a). Only strings and numbers:
    by the time the job starts the panel may show another directory. Names are the names inside SrcDir, in the order of the panel. }
  TCopyRequest = record
    SrcDir: AnsiString;
    DstDir: AnsiString;
    Mask: AnsiString;
    Names: array of AnsiString;
    Mode: Word;           { CopyMode of FilesCopy }
    Options: Word;        { CopyOptions of FilesCopy }
  end;

  TCopyJob = record
    Id: LongInt;          { 1, 2, 3 ... in the order of JobAdd; never used twice }
    State: TJobState;
    Title: String;        { what is copied, as the list shows it }
    Total: Int64;         { bytes to copy; 0 when unknown }
    Done: Int64;          { bytes copied so far }
    Error: String;        { why the job failed (jsFailed only) }
    Background: Boolean;  { the user sent the copy to the background: the panels work while it runs (JobSetBackground) }
    HasRequest: Boolean;  { Request is filled: the job comes from JobAddRequest }
    Request: TCopyRequest; { read-only for the readers of JobGet and JobAt: Names is shared with the stored job }
  end;

{ Adds a job in the state jsQueued and returns its Id. }
function JobAdd(const Title: String; Total: Int64): LongInt;

{ Like JobAdd, and keeps a copy of Request for the job (HasRequest is True). The caller may change its own Request afterwards. }
function JobAddRequest(const Title: String; Total: Int64; const Request: TCopyRequest): LongInt;

{ The job with this Id, or False when there is none (a cleared job too). }
function JobGet(Id: LongInt; var Job: TCopyJob): Boolean;

{ The job at the place Index (0 is the oldest) for a list; False when Index is out of 0..JobCount - 1. }
function JobAt(Index: Integer; var Job: TCopyJob): Boolean;

function JobCount: Integer;

{ Id of the oldest queued job, 0 when no job waits. }
function JobNextQueued: LongInt;

{ jsQueued -> jsRunning. }
function JobStart(Id: LongInt): Boolean;

{ Records how many bytes are copied; only for a running job. Done is kept between 0 and Total (when Total is known). }
function JobProgress(Id: LongInt; Done: Int64): Boolean;

{ Sets the number of bytes to copy, which is known only after the files are counted; for a queued or running job. A smaller Total
  than Done brings Done down to it; a negative Total is 0 (unknown). }
function JobSetTotal(Id: LongInt; Total: Int64): Boolean;

{ jsRunning -> jsDone; Done becomes Total. }
function JobFinish(Id: LongInt): Boolean;

{ jsRunning -> jsFailed with the reason Msg. }
function JobFail(Id: LongInt; const Msg: String): Boolean;

{ jsQueued or jsRunning -> jsCancelled. The copy loop sees it with JobIsCancelled and stops; a job that has ended stays as it is. }
function JobCancel(Id: LongInt): Boolean;

{ True for a cancelled job; False for any other and for an unknown Id. }
function JobIsCancelled(Id: LongInt): Boolean;

{ Closes a running job by the way its copy ended: not Stopped -> JobFinish; Stopped by the user (ByUser) -> JobCancel; Stopped
  otherwise (an error) -> JobFail with Msg. True when the state changed; a job that has ended already (cancelled from the list
  while it was running, say) stays as it is. }
function JobEnd(Id: LongInt; Stopped, ByUser: Boolean; const Msg: String): Boolean;

{ 0..100: the share of Total that is copied; 100 for a done job; 0 while Total is unknown. }
function JobPercent(Id: LongInt): Integer;

{ The number of jobs that have not ended (queued or running). }
function JobsActive: Integer;

{ Marks a queued or running job as a background one, or takes the mark off; False for an unknown job and for one that has ended.
  The copy loop reads the mark (JobGet) to decide whether it passes the events to the panels. }
function JobSetBackground(Id: LongInt; Value: Boolean): Boolean;

{ Id of the job that runs now (jsRunning), 0 when none. There is one copy at a time: whoever starts a copy while this is not 0
  adds a queued job (JobAdd) instead of copying at once, because a copy in the background keeps its file list and its source
  panel in use. }
function JobRunning: LongInt;

{ Removes the jobs that have ended (done, failed, cancelled) and returns how many. The order of the others is kept. }
function JobsClearEnded: Integer;

{ The row of the jobs list (part 4b-5) for a job: its state in brackets (running with the percent when Total is known), the title,
  and for a failed job the reason after a colon. "[wait] a.iso", "[run 25%] a.iso", "[run] b.log", "[done] a.iso", "[cancelled] a.iso",
  "[failed] b.log: disk full". The window shows the rows in the order of JobAt. }
function JobLine(const Job: TCopyJob): String;

{ The short state of the background copy for a place that is always on the screen (dn#88 step 2a): '' when no copy runs in the
  background; otherwise Name with the percent ("Copy 37%"; Name alone while Total is unknown) and "+N" when N more jobs wait
  ("Copy 37% +2"). A copy that was not sent to the background and the jobs that have ended give ''. Name comes from the caller, so
  that the word is translated. }
function JobsStatusText(const Name: String): String;

{ True for a command that must not run while a background copy runs: it would change the files the copy reads or writes (a new copy,
  move, delete, make directory, attributes, rename, archive, a change of the directory or a re-read of a panel), or quit before the
  user can cancel the copy from the jobs list. The copy loop clears such a command instead of passing it to the panels. Navigation,
  the viewer, the menus and the rest pass. }
function BackgroundCopyBlocks(Command: Word): Boolean;

{ True for the copy commands that do not wait for the copy in the background to end but put the new copy in the job list after
  it (dn#88 step 5b): F5, F6, Shift+F5. The other commands of BackgroundCopyBlocks stay blocked. }
function BackgroundCopyQueues(Command: Word): Boolean;

{ True while the running copy (JobRunning) is in the background. }
function BackgroundCopyRunning: Boolean;

implementation

uses Commands;

var
  Jobs: array of TCopyJob;
  NextId: LongInt = 1;

function Find(Id: LongInt): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Jobs) do
    if Jobs[I].Id = Id then
    begin
      Result := I;
      Exit;
    end;
end;

function JobAdd(const Title: String; Total: Int64): LongInt;
var
  N: Integer;
begin
  N := Length(Jobs);
  SetLength(Jobs, N + 1);
  Jobs[N].Id := NextId;
  Jobs[N].State := jsQueued;
  Jobs[N].Title := Title;
  if Total < 0 then
    Total := 0;
  Jobs[N].Total := Total;
  Jobs[N].Done := 0;
  Jobs[N].Error := '';
  Jobs[N].Background := False;
  Jobs[N].HasRequest := False;
  Result := NextId;
  Inc(NextId);
end;

function JobAddRequest(const Title: String; Total: Int64; const Request: TCopyRequest): LongInt;
var
  N: Integer;
begin
  Result := JobAdd(Title, Total);
  N := High(Jobs);
  Jobs[N].HasRequest := True;
  Jobs[N].Request := Request;
  Jobs[N].Request.Names := Copy(Request.Names, 0, Length(Request.Names));
end;

function JobGet(Id: LongInt; var Job: TCopyJob): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := I >= 0;
  if Result then
    Job := Jobs[I];
end;

function JobAt(Index: Integer; var Job: TCopyJob): Boolean;
begin
  Result := (Index >= 0) and (Index < Length(Jobs));
  if Result then
    Job := Jobs[Index];
end;

function JobCount: Integer;
begin
  Result := Length(Jobs);
end;

function JobNextQueued: LongInt;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Jobs) do
    if Jobs[I].State = jsQueued then
    begin
      Result := Jobs[I].Id;
      Exit;
    end;
end;

function JobStart(Id: LongInt): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State = jsQueued);
  if Result then
    Jobs[I].State := jsRunning;
end;

function JobProgress(Id: LongInt; Done: Int64): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State = jsRunning);
  if not Result then
    Exit;
  if Done < 0 then
    Done := 0;
  if (Jobs[I].Total > 0) and (Done > Jobs[I].Total) then
    Done := Jobs[I].Total;
  Jobs[I].Done := Done;
end;

function JobSetTotal(Id: LongInt; Total: Int64): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State in [jsQueued, jsRunning]);
  if not Result then
    Exit;
  if Total < 0 then
    Total := 0;
  Jobs[I].Total := Total;
  if (Total > 0) and (Jobs[I].Done > Total) then
    Jobs[I].Done := Total;
end;

function JobFinish(Id: LongInt): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State = jsRunning);
  if not Result then
    Exit;
  Jobs[I].State := jsDone;
  Jobs[I].Done := Jobs[I].Total;
end;

function JobFail(Id: LongInt; const Msg: String): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State = jsRunning);
  if not Result then
    Exit;
  Jobs[I].State := jsFailed;
  Jobs[I].Error := Msg;
end;

function JobCancel(Id: LongInt): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State in [jsQueued, jsRunning]);
  if Result then
    Jobs[I].State := jsCancelled;
end;

function JobEnd(Id: LongInt; Stopped, ByUser: Boolean; const Msg: String): Boolean;
begin
  if not Stopped then
    Result := JobFinish(Id)
  else if ByUser then
    Result := JobCancel(Id)
  else
    Result := JobFail(Id, Msg);
end;

function JobIsCancelled(Id: LongInt): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State = jsCancelled);
end;

function JobPercent(Id: LongInt): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := Find(Id);
  if I < 0 then
    Exit;
  if Jobs[I].State = jsDone then
    Result := 100
  else if Jobs[I].Total > 0 then
    Result := Integer((Jobs[I].Done * 100) div Jobs[I].Total);
end;

function JobsActive: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Jobs) do
    if Jobs[I].State in [jsQueued, jsRunning] then
      Inc(Result);
end;

function JobSetBackground(Id: LongInt; Value: Boolean): Boolean;
var
  I: Integer;
begin
  I := Find(Id);
  Result := (I >= 0) and (Jobs[I].State in [jsQueued, jsRunning]);
  if Result then
    Jobs[I].Background := Value;
end;

function JobRunning: LongInt;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Jobs) do
    if Jobs[I].State = jsRunning then
    begin
      Result := Jobs[I].Id;
      Exit;
    end;
end;

function JobsClearEnded: Integer;
var
  I, K: Integer;
begin
  K := 0;
  for I := 0 to High(Jobs) do
    if Jobs[I].State in [jsQueued, jsRunning] then
    begin
      Jobs[K] := Jobs[I];
      Inc(K);
    end;
  Result := Length(Jobs) - K;
  SetLength(Jobs, K);
end;

function JobLine(const Job: TCopyJob): String;
var
  P: String;
begin
  case Job.State of
    jsQueued: Result := '[wait] ';
    jsRunning:
      if Job.Total > 0 then
      begin
        Str(JobPercent(Job.Id), P);
        Result := '[run ' + P + '%] ';
      end
      else
        Result := '[run] ';
    jsDone: Result := '[done] ';
    jsFailed: Result := '[failed] ';
    jsCancelled: Result := '[cancelled] ';
  end;
  Result := Result + Job.Title;
  if (Job.State = jsFailed) and (Job.Error <> '') then
    Result := Result + ': ' + Job.Error;
end;

function JobsStatusText(const Name: String): String;
var
  Id: LongInt;
  Job: TCopyJob;
  N: String;
begin
  Result := '';
  Id := JobRunning;
  if (Id = 0) or not JobGet(Id, Job) or not Job.Background then
    Exit;
  Result := Name;
  if Job.Total > 0 then
  begin
    Str(JobPercent(Id), N);
    Result := Result + ' ' + N + '%';
  end;
  if JobsActive > 1 then
  begin
    Str(JobsActive - 1, N);
    Result := Result + ' +' + N;
  end;
end;

const
  BlockedCommands: array[0..24] of Word = (
    cmForceRescan, cmCopyFiles, cmTempCopyFiles, cmPanelLongCopy, cmMoveFiles, cmPanelMkDir, cmPanelErase, cmSetFAttr,
    cmPanelReread, cmChangeDrive, cmChangeDir, cmPanelArcFiles, cmExtractArchive, cmSingleCopy, cmSingleRename, cmGroupRename,
    cmFastRename, cmRereadDir, cmRereadInfo, cmRereadTree, cmRereadForced, cmArchiveFiles, cmTouchFile, cmChangeDirectory,
    cmQuit);

function BackgroundCopyRunning: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Jobs) do
    if (Jobs[I].State = jsRunning) and Jobs[I].Background then
    begin
      Result := True;
      Exit;
    end;
end;

function BackgroundCopyQueues(Command: Word): Boolean;
begin
  Result := (Command = cmCopyFiles) or (Command = cmMoveFiles) or (Command = cmSingleCopy);
end;

function BackgroundCopyBlocks(Command: Word): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(BlockedCommands) to High(BlockedCommands) do
    if BlockedCommands[I] = Command then
    begin
      Result := True;
      Exit;
    end;
end;

end.
