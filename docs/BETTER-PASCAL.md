# Better Pascal in DN: the integration contract

The rules by which DN takes Better Pascal ([unxed/bp](https://github.com/unxed/bp): the safe memory model `Safe`, and `BP` with UTF-8
defaults and goroutines). The plan of the migration, step by step, is [unxed/dn#87](https://github.com/unxed/dn/issues/87); this page is
its step 2. The specification of the language layer is `bp/safe/SPEC.md` (v0.6 at the pinned commit).

State: the sources of Better Pascal are in the tree (the submodule `bp/`), **no unit of DN uses them yet**, and the switch `DN_BP` is
off by default. Every build of DN gives the same program as before.

## 1. Which unit

| | `Safe` (`bp/safe/safe.pas`) | `BP` (`bp/bp.pas`) |
|---|---|---|
| What it gives | ownership (`TOwned`, `TShared`, `TWeak`, `TSlice`, `TArena`), `TDefer`, the leak counter `SafeCheckNoLeaks`, `TCResource`, the poisoned primitives | the same, plus UTF-8 defaults, goroutines (`TGroup`, `TChan`, `Select`) and the thread manager `BPThreads` |
| Global effects | none | its `initialization` sets the code pages of the RTL to UTF-8 (off with `-dSAFE_NO_UTF8`); on Linux it installs `fpwidestring` and `BPThreads` (no libc) |
| Where in `uses` | last, in every unit that adopts it | first in the program file (`dn/src/dn.pas`), last in the other units |
| Targets | all the targets of DN, DOS included (verified by unxed/bp on go32v2) | Linux; on DOS `TGroup.Go` raises R8 (no threads); Windows builds, its run is not verified yet (unxed/bp#56, step 15) |

Decisions:

1. **A unit of DN adopts `Safe`.** DN sets the code pages itself (`dn/compat/osdep.pas`: the UTF-8 conversion pages on Windows, `NameConv`
   on Unix, the code page builds of DOS), and the same units are built for DOS. `Safe` leaves all of that as it is.
2. **`BP` is used only where goroutines are needed** (step 9 of the plan and later), only in the program file, and always with
   `-dSAFE_NO_UTF8`, so that the encodings stay DN's. DN links no libc units today (no `cwstring`, `cthreads` or `external 'c'` in `dn/`,
   `tv/`, `tve/`), so the default Linux mode of `BP` (static, without libc) fits the static i386 and aarch64 builds; `-dSAFE_LIBC` is not used.
3. **DOS keeps a synchronous path.** A unit that starts tasks has the same interface on DOS and runs the work in the calling thread there
   (step 9).

## 2. How the sources come in

`bp/` is a git submodule of [unxed/bp](https://github.com/unxed/bp), like `tv/` and `tve/`:

- **Pinned commit: `83dee43cac209882b8caf74b7f8651aa53fdbc0f`** (unxed/bp `main` after unxed/bp#57). `git submodule status bp` shows it;
  `tools/tests/test_better_pascal.py` checks that this page names the commit the tree points to.
- Only `bp/bp.pas`, `bp/safe/` and `bp/ext/` are put on the unit path. They are MIT (`bp/LICENSE`). `bp/fpide/` (the Free Pascal IDE, GPL)
  is never on a path of a DN build, and its own submodules (`bp/fpide/tv`, `bp/fpide/tve`) are not fetched by the CI of DN (the checkouts
  are not recursive); `git clone --recurse-submodules` fetches them too, which only costs disk space.
- Why a submodule and not a copy in `dn/third-party/`: the Pascal libraries of the sibling projects come in this way (`tv/`, `tve/`); the
  checks of the tracked sources of this repository (`tools/class-gate.py`, `tools/tests/test_text_policy.py`) cover DN's own files, and
  the library holds names and texts that those checks do not allow in DN's files (the root class, method pointer types, a non-English
  example in a comment); the pin is the commit of the submodule; and the linter `bpvet` (unxed/bp#56) comes from the same commit.
- An update is a pull request of its own: `git -C bp fetch origin && git -C bp checkout <commit> && git add bp`, the commit on this page
  changed to the same value, and the required CI green. A change to Better Pascal is made in unxed/bp first, never in the checkout.
- The licence in the release archives: none yet, because no code of `bp/` is in the program. The step that first compiles a unit with
  `Safe` into DN (step 4) adds `copy bp/LICENSE LICENSE-BP.TXT` to `tools/dn-notices.sh` and names it in its list of licences.

## 3. The build switch

`DN_BP=1` (`tools/dn-env.sh`, so `tools/build.sh` and the scripts that source it) adds `-Fu bp -Fu bp/safe -Fu bp/ext`; `DN_BP_DIR=/path`
takes another checkout of unxed/bp. With `DN_BP=1` and an empty `bp/` the submodule is fetched, as `tools/need-tv.sh` does for `tv/`.
No `-Fi` is needed: `bp.pas` and `safe.pas` include their files by paths relative to themselves.

- Step 3 (the probe in `dn/tests`) gives `tools/dn-test.sh` the same paths.
- Step 4 (the first unit of `dn/src` with `Safe`) turns the switch on for every target, because that unit does not compile without it.
- `tools/check-layout.sh` stops a unit of `dn/`, `tv/` or `tve/` that has the name of a unit of `bp/` (`bp`, `safe`, `bpthreads`).

## 4. Compiler modes

DN is built with `-Mdelphi -Sh-` (`dn/build.env`: `String` is `ShortString`); 47 of the 163 units of `dn/src` and `dn/compat` say
`{$mode objfpc}` themselves (`renmask.pas` says `{$mode objfpc}{$H-}`, `cfgdir.pas` `{$mode objfpc}`), the others are in Delphi mode.
The units of `bp/` say `{$mode objfpc}{$H+}` in their own source, and a directive in a unit wins over the command line: they compile
the same in a DN build.

A unit of DN that adopts `Safe`:

- keeps its mode and `{$H-}` by default. `Safe` works in a `{$H-}` unit (unxed/bp#3, step 3d, `bp/safe/FPIDE-ADOPTION.md` section 5): a
  `ShortString` passes to the `String` parameters of `Safe`, and a string that comes back is cut at 255 bytes;
- moves to `{$H+}` only by a decision of its own, with its tests: it changes the records that DN writes as files with `String[N]`
  (`dn.ini`, the `.dlg` resources, the histories, `dn.dsk`), so a unit with such records gets a file format layer first (step 6);
- writes the generics in the syntax of its mode: `TOwned<TFoo>` in Delphi mode, `specialize TOwned<TFoo>` in objfpc mode. That the
  generics of `Safe` specialize in a Delphi mode unit is **not verified yet**: the probe of step 3 checks it. If they do not, the unit
  says `{$mode objfpc}` and keeps `{$H-}`;
- lists `Safe` last in `uses` and, once nothing poisoned is left in it, adds `{$WARN SYMBOL_DEPRECATED ERROR}`, so that a poisoned primitive
  stops the build (SPEC section 6). An unavoidable primitive is written with its full name (`System.Move`) under a `// UNSAFE:` comment;
- stays under the rules of `dn/src`: the class gate (`tools/class-gate.py`) still holds, and the API of `Safe` does not need the names it
  forbids.

## 5. Checks that come with later steps

| What | When | Step of unxed/dn#87 |
|---|---|---|
| `-dSAFE_DEBUG` in the test builds that use `Safe` or `BP` (`dn/tests`, the probes and pilots); release builds without it | when the pinned commit has the debug checks of unxed/bp#56 (steps 6, 8, 9) | rule 7 |
| `{$R+}{$Q+}` in the debug builds of the units with `Safe` | by the rule of unxed/bp#56, step 12 | A |
| `bpvet --report` over `dn/src`, `bpvet --strict` for the units of `tools/safe-units.txt` | after the pin moves to a commit of unxed/bp with `tools/bpvet/` (unxed/bp#56, step 2); built in the CI of DN from `bp/tools/bpvet`, not copied | 5b |
| The size of the mini build with `Safe` linked in (budget: unxed/dn#40) | the probe | 3 |

The mini build is not changed by this step: nothing of `bp/` is compiled.
