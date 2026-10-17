program t_netproc;
{ Tests of src/netproc.pas: a child process with pipes. The program on the other side is /bin/sh of this machine. }
{$mode objfpc}{$H+}
uses SysUtils, DateUtils, NetProc;
{$I dntest.inc}

{ Reads from the standard output until Want is in what came, the program ends, or Ms milliseconds are over. }
function ReadUntil(P: TNetProc; const Want: AnsiString; Ms: Integer; out Got: AnsiString): Boolean;
var
  Buf: array[0..255] of Char;
  N: Integer;
  Start: TDateTime;
begin
  Got := '';
  Start := Now;
  repeat
    N := P.Read(Buf, SizeOf(Buf), 100);
    if N > 0 then
    begin
      SetLength(Got, Length(Got) + N);
      Move(Buf, Got[Length(Got) - N + 1], N);
    end;
  until (Pos(Want, Got) > 0) or (N < 0) or (MilliSecondsBetween(Now, Start) > Ms);
  Result := Pos(Want, Got) > 0;
end;

var
  P: TNetProc;
  Got: AnsiString;
  Buf: array[0..63] of Char;
  Start: TDateTime;
  N: Integer;
begin
  { the program that cannot be started is told in words, and nothing runs }
  P := TNetProc.Create;
  Check(not P.Start('/nonexistent-dir/no-such-program', []), 'a program that is not there is not started');
  Check((P.LastError <> '') and not P.Running, 'the failure is told and nothing runs');
  Check(P.Read(Buf, SizeOf(Buf), 10) = -1, 'Read with no program says that it has ended');
  P.Free;

  { send a line, take the answer }
  P := TNetProc.Create;
  Check(P.Start('/bin/sh', []), 'sh is started');
  Check(P.Running and (P.ExitCode = -1), 'it runs, and has no exit code yet');
  Check(P.Write('echo A' + #10), 'a line is sent');
  Check(ReadUntil(P, 'A' + #10, 5000, Got) and (Got = 'A' + #10), 'the answer "A" comes back');

  { the standard error is a pipe of its own }
  Check(P.Write('echo E 1>&2' + #10), 'a line for the standard error is sent');
  N := P.ReadErr(Buf, SizeOf(Buf), 5000);
  Check((N = 2) and (Buf[0] = 'E'), 'the standard error is read apart from the standard output');

  { nothing to read: Read returns 0 after about the time it was given, the program runs on }
  Start := Now;
  N := P.Read(Buf, SizeOf(Buf), 300);
  Check(N = 0, 'no bytes: Read answers 0');
  Check((MilliSecondsBetween(Now, Start) >= 250) and (MilliSecondsBetween(Now, Start) < 3000), 'Read waited about the time it was given');
  Check(P.Running, 'a program that is silent still runs');

  { the end: exit, the pipe is drained, then -1 }
  Check(P.Write('echo B; exit 3' + #10), 'the last line is sent');
  Check(ReadUntil(P, 'B' + #10, 5000, Got), 'the last answer comes before the end');
  Start := Now;
  repeat
    N := P.Read(Buf, SizeOf(Buf), 100);
  until (N < 0) or (MilliSecondsBetween(Now, Start) > 5000);
  Check(N = -1, 'after the end Read answers -1');
  Check(not P.Running and (P.ExitCode = 3), 'the exit code is kept');
  Check(not P.Write('x' + #10), 'nothing is sent to an ended program');
  P.Free;

  { a program that does not answer is ended by Stop, and Stop may come twice }
  P := TNetProc.Create;
  Check(P.Start('/bin/sh', ['-c', 'sleep 5']), 'sh with sleep is started');
  Start := Now;
  Check(P.Read(Buf, SizeOf(Buf), 300) = 0, 'sleep gives no bytes within the limit');
  P.Stop;
  Check(not P.Running, 'Stop ends the program');
  Check(MilliSecondsBetween(Now, Start) < 4000, 'Stop does not wait for sleep to finish');
  P.Stop;
  P.Free;

  { the end of the input reaches the program }
  P := TNetProc.Create;
  Check(P.Start('/bin/cat', []), 'cat is started');
  Check(P.Write('abc'), 'bytes are sent to cat');
  P.CloseInput;
  Check(ReadUntil(P, 'abc', 5000, Got), 'cat sends the bytes back and, with the input closed, ends');
  P.Free;

  Finish;
end.
