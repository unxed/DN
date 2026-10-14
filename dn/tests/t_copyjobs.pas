{ The model of the background copy jobs (copyjobs, dn#40 part 4): the states, the progress, the cancel and the clearing. }
{$mode objfpc}{$H-}
program t_copyjobs;
uses CopyJobs;
{$I dntest.inc}

var
  A, B, C, D, E, F: LongInt;
  J: TCopyJob;

begin
  Check((JobCount = 0) and (JobNextQueued = 0) and (JobsActive = 0), 'no jobs at the start');

  A := JobAdd('a.iso', 1000);
  B := JobAdd('b.log', 0);
  Check((A > 0) and (B > A), 'ids grow from the first and differ');
  Check(JobCount = 2, 'two jobs added');
  Check(JobGet(A, J) and (J.State = jsQueued) and (J.Title = 'a.iso') and (J.Total = 1000) and (J.Done = 0), 'a new job is queued');
  Check(not JobGet(A + B + 100, J), 'an unknown id is not found');
  Check(JobAt(0, J) and (J.Id = A) and JobAt(1, J) and (J.Id = B), 'JobAt lists the jobs from the oldest');
  Check(not JobAt(2, J) and not JobAt(-1, J), 'JobAt out of range is False');
  Check(JobNextQueued = A, 'the oldest queued job is next');

  Check(not JobProgress(A, 10), 'a queued job takes no progress');
  Check(not JobFinish(A) and not JobFail(A, 'x'), 'a queued job neither finishes nor fails');
  Check(JobStart(A), 'a queued job starts');
  Check(not JobStart(A), 'a running job does not start again');
  Check(JobNextQueued = B, 'the next queued job is B once A runs');

  Check(JobProgress(A, 250) and (JobPercent(A) = 25), 'progress 250 of 1000 is 25 percent');
  Check(JobProgress(A, 5000) and JobGet(A, J) and (J.Done = 1000) and (JobPercent(A) = 100), 'progress is kept at Total');
  Check(JobProgress(A, -5) and JobGet(A, J) and (J.Done = 0), 'progress is not below zero');

  Check(JobFinish(A) and JobGet(A, J) and (J.State = jsDone) and (J.Done = 1000) and (JobPercent(A) = 100), 'finish makes Done = Total');
  Check(not JobFinish(A) and not JobCancel(A) and not JobStart(A), 'a done job stays done');

  Check(JobStart(B) and JobProgress(B, 42) and JobGet(B, J) and (J.Done = 42) and (JobPercent(B) = 0), 'unknown Total: bytes kept, percent 0');
  Check(JobFail(B, 'disk full') and JobGet(B, J) and (J.State = jsFailed) and (J.Error = 'disk full'), 'a running job fails with a reason');
  Check(not JobFail(B, 'again') and not JobCancel(B) and not JobProgress(B, 1), 'a failed job stays failed');

  C := JobAdd('c', 10);
  Check(JobCancel(C) and JobIsCancelled(C) and JobGet(C, J) and (J.State = jsCancelled), 'a queued job can be cancelled');
  Check(not JobStart(C) and (JobNextQueued = 0), 'a cancelled job does not start and is not next');

  D := JobAdd('d', 10);
  Check(JobStart(D) and JobCancel(D) and JobIsCancelled(D), 'a running job can be cancelled');
  Check(not JobProgress(D, 5) and not JobFinish(D), 'a cancelled job takes no progress and does not finish');
  Check(not JobIsCancelled(A) and not JobIsCancelled(A + 1000), 'only a cancelled job is cancelled');

  E := JobAdd('e', 10);
  Check((JobCount = 5) and (JobsActive = 1), 'five jobs, one of them not ended');
  Check(JobsClearEnded = 4, 'four ended jobs are cleared');
  Check((JobCount = 1) and JobAt(0, J) and (J.Id = E) and not JobGet(A, J), 'only the queued job is left');
  Check(JobsClearEnded = 0, 'nothing more to clear');

  F := JobAdd('f', 1);
  Check(F > E, 'an id is not used twice after clearing');
  Finish;
end.
