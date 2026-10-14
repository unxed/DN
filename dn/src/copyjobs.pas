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

  TCopyJob = record
    Id: LongInt;          { 1, 2, 3 ... in the order of JobAdd; never used twice }
    State: TJobState;
    Title: String;        { what is copied, as the list shows it }
    Total: Int64;         { bytes to copy; 0 when unknown }
    Done: Int64;          { bytes copied so far }
    Error: String;        { why the job failed (jsFailed only) }
  end;

{ Adds a job in the state jsQueued and returns its Id. }
function JobAdd(const Title: String; Total: Int64): LongInt;

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

{ Removes the jobs that have ended (done, failed, cancelled) and returns how many. The order of the others is kept. }
function JobsClearEnded: Integer;

implementation

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
  Result := NextId;
  Inc(NextId);
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

end.
