{ The model of the background copy jobs (copyjobs, dn#40 part 4): the states, the progress, the cancel and the clearing. }
{$mode objfpc}{$H-}
program t_copyjobs;
uses CopyJobs;
{$I dntest.inc}

var
  A, B, C, D, E, F, G, H, K, L, M, N: LongInt;
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

  { the total is set after the files are counted }
  Check(JobSetTotal(F, 200) and JobGet(F, J) and (J.Total = 200), 'the total of a queued job can be set');
  Check(JobStart(F) and JobProgress(F, 150) and JobSetTotal(F, 100) and JobGet(F, J) and (J.Total = 100) and (J.Done = 100), 'a smaller total brings Done down to it');
  Check(JobSetTotal(F, -3) and JobGet(F, J) and (J.Total = 0) and (J.Done = 100), 'a negative total is 0 and Done stays');
  Check(not JobSetTotal(F + 1000, 5), 'the total of an unknown job is not set');
  Check(JobEnd(F, False, False, '') and JobGet(F, J) and (J.State = jsDone), 'JobEnd without a stop finishes the job');
  Check(not JobSetTotal(F, 5), 'the total of a done job is not set');

  { the sequences that FilesCopy writes: add, start, total, progress, end }
  G := JobAdd('copy to /x/', 0);
  Check(JobStart(G) and JobSetTotal(G, 100) and JobProgress(G, 40) and (JobPercent(G) = 40), 'a copy in progress');
  Check(JobEnd(G, False, False, 'unused') and JobGet(G, J) and (J.State = jsDone) and (J.Done = 100) and (J.Error = ''), 'a copy that ran to the end is done');
  Check(not JobEnd(G, True, True, '') and not JobEnd(G, True, False, 'late') and JobGet(G, J) and (J.State = jsDone) and (J.Error = ''), 'a done job is not ended again');

  H := JobAdd('copy to /y/', 0);
  Check(JobStart(H) and JobSetTotal(H, 100) and JobProgress(H, 10), 'a second copy in progress');
  Check(JobEnd(H, True, True, 'unused') and JobGet(H, J) and (J.State = jsCancelled) and (J.Done = 10) and (J.Error = ''), 'a copy stopped by the user is cancelled');

  K := JobAdd('copy to /z/', 0);
  Check(JobStart(K) and JobProgress(K, 7), 'a third copy in progress');
  Check(JobEnd(K, True, False, 'copy stopped by an error') and JobGet(K, J) and (J.State = jsFailed) and (J.Error = 'copy stopped by an error') and (J.Done = 7), 'a copy stopped by an error fails with the reason');

  L := JobAdd('copy to /w/', 0);
  Check(JobStart(L) and JobCancel(L), 'a running job is cancelled from outside');
  Check(not JobEnd(L, False, False, '') and not JobEnd(L, True, False, 'x') and JobGet(L, J) and (J.State = jsCancelled) and (J.Error = ''), 'JobEnd does not change a job cancelled from outside');
  Check(JobsClearEnded = 5, 'the ended jobs of this part are cleared');

  { the background mark and the one running copy (part 4b-3) }
  M := JobAdd('copy to /bg/', 0);
  N := JobAdd('copy to /bg2/', 0);
  Check(JobGet(M, J) and not J.Background, 'a new job is not a background one');
  Check(JobRunning = 0, 'no job runs while all are queued');
  Check(JobStart(M) and (JobRunning = M), 'the running job is found');
  Check(JobSetBackground(M, True) and JobGet(M, J) and J.Background, 'a running job goes to the background');
  Check(JobSetBackground(N, True) and JobGet(N, J) and J.Background and (J.State = jsQueued), 'a queued job can carry the mark');
  Check(JobSetBackground(N, False) and JobGet(N, J) and not J.Background, 'the mark is taken off');
  Check(not JobSetBackground(M + N + 1000, True), 'an unknown job takes no mark');
  Check((JobRunning = M) and (JobNextQueued = N), 'one copy runs, the second waits in the queue');
  Check(JobEnd(M, False, False, '') and (JobRunning = 0), 'no job runs after the copy ends');
  Check(not JobSetBackground(M, False) and JobGet(M, J) and J.Background, 'the mark of a done job stays as it was');
  Check(JobStart(N) and (JobRunning = N) and JobCancel(N) and (JobRunning = 0), 'a cancelled job does not run');
  Check(JobsClearEnded = 2, 'the jobs of the background part are cleared');
  Finish;
end.
