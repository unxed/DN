# Far UX mode + mini build — Handoff Status (2026-10-13)

Repo: `/home/ivan/dn` (branch `main`, 23 commits ahead of origin)

## Current HEAD
```
ae58190 Foreign WIP: rename batch (asciitab→asciitable, dnstddlg→filedlg, listmakr→strlistmaker)
7196f46 M1-pilot: tetris out of the mini build ({$IFNDEF DN_MINI})
5fc96eb M0-measure: -Os -XX -CX -Xs gives -28% with flags alone
c2686d0 I3b: Far clipboard/cmdline name insertions + pty
ac123af I3a: Shift+Gray selects all / deselects all behind FarUxMode
3502acc I2b: Alt fast-find panel wiring behind FarUxMode + pty test
... (I2a, I1, I0)
```

## Far UX Mode — Completed (I0–I3b)
All behind `FarUxMode = False` (`[FilePanels]` in `dn.ini`, ini-only, no dialog checkbox yet):
- **I1** `FarUxMode` flag + `FarUxEnabled` accessor (`farux.pas`) + `t_farux` (12 checks)
- **I2a** `FarFastFindChar` classifier + 12 unit tests
- **I2b** Alt+letter fast find in panel (`filepanel.pas:1982`), Ctrl+Enter/Shift+Enter next/prev, Esc exit; `dn-linux-farux.py` 15/15
- **I3a** Shift+Gray+ / Shift+Gray- select all / deselect all (`panelroot.pas`, `paneldlgs.pas`) + pty
- **I3b** kbCtrlIns with text → cmdline (`_CtrlInsToCmdLine`); kbCtrlAltIns → full names clipboard (`_CtrlInsFull`); off-mode byte-identical

## Mini Build — Completed (M0, M1-pilot)
- **M0-shell** `DN_MINI=1` → `-dDN_MINI`, object suffix `-mini` (isolated from `-utf8`)
- **M0-measure** `-Os -XX -CX -Xs` = **2,071,312** vs 2,887,952 default (−28%, −816K)
- **M1-pilot** tetris cut via `{$IFNDEF DN_MINI}` (dn.pas, dnutil.pas, regall.pas) + cmGame stub; full + mini builds green; tour passes on mini binary; mini −16K vs full

## Next Work (in priority order)
1. **M1 first wave** (leaf extras — `{$IFNDEF DN_MINI}` around uses + cm stubs):
   - calc cluster: `calcwin`, `evaluator`, `calcline`, `cellscol`
   - `uucode` + `decoder`
   - `arvid` + `arvidavt` + `arvidtdr` (wide blast radius — second wave if needed)
   - `phones`, `calendar`, `printman`, `dbview` + `dbwatch`, `idlers`, `os2sess`
   - Pattern: IFDEF uses in `dn.pas`/`dnutil.pas`/`regall.pas`/`cmdline`/etc., cm stubs in `dnutil.pas`, regall bodies IFDEF

2. **M2** rare archives: 16 `fmt*` in `archdet.pas:62-72` (keep 10 base: zip/tar/tgz/bz2/xz/7z/rar/cab/lha/zoo)

3. **I3c/I4** remaining Far key map (I3c: drive changes, history, F-keys; I4: dialogs, file ops)

4. **I5** `dlgFMSetup` checkbox for FarUxMode (3 langs + `setups.pas` plumbing)

5. **M3** mc.gap features within budget (mc.ext-style assoc, background jobs)

## Verification Commands (run locally, no CI wait)
```bash
export PATH=$HOME/fpc-local/bin:$PATH
cd /home/ivan/dn

# Full test suite
bash tools/dn-test.sh          # 13/13 green (incl. t_farux 12/12)

# Far UX pty test
python3 tools/dn-linux-farux.py out/linux64   # 15/15 green

# Mini build
DN_MINI=1 tools/build.sh linux64 out/mini
python3 tools/dn-linux-tour.py out/mini       # all ok

# Size check
ls -l out/mini/dn /usr/bin/mc
```

## Key Files
- Plan: `dn/docs/FARUX-PLAN.md` (detailed RUP iterations)
- Key map: `dn/docs/FARKEYS-MAP.md` (far2l→DN)
- Mini cuts: `dn/docs/MINI-CUTS.md` (first/second wave)
- MC gap: `dn/docs/MC-GAP.md` (what mc has, DN lacks)
- Design: `dn/docs/FARFIND-DESIGN.md` (I2b), `dn/docs/FARUX-STATUS.md` (this)

## Blockers / Notes
- **CI push blocked** by `.ci-push-secret` hook (parent serializes pushes). Work locally; parent pushes.
- **tv/ submodule** has local changes (uncommitted) — don't touch unless needed.
- **Foreign rename** (ae58190) is committed but `tv/` submodule pointer not updated.
- **ASCIITable clash** fixed in 6f36432 (qualified calls `asciitable.ASCIITable`).

## Handoff Checklist for Next Model
- [ ] Run `tools/dn-test.sh` and `dn-linux-farux.py` to verify baseline
- [ ] Pick up M1 first wave (calc cluster or phones)
- [ ] Keep `-Os -XX -CX -Xs` measurements running on each M1 cut
- [ ] All code behind `FarUxMode` / `DN_MINI` — default builds unchanged
