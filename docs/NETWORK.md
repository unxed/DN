# Network file systems: where they plug into DN

Design note for unxed/dn#90 (step 2). No code is changed by this note. It answers two questions:
which places of the code read directories and move files today, and which scheme lets FTP, SFTP and
FISH (`sh://`) panels sit next to them. The state described is `main` at the time of writing
(`ef9a7f0`); step 3 of the plan starts from this list.

## 1. How a panel reads files today

A file panel (`TFilePanelRoot`, `dn/src/panelroot.pas`) does not read the disk itself. It owns a
helper object of the class `TDrive` (`dn/src/drives.pas`, "Helper class inserted into a file panel").
The helper is the existing abstraction that decides what the panel shows and what the file commands do.
`TDrive` is marked as part of the plugin model ("change with extreme care"), and it already has three
descendants that are not local directories:

| Class | Unit | What it shows |
|---|---|---|
| `TArcDrive` | `arcview.pas` | the contents of an archive |
| `TArvidDrive` | `arvid.pas` | Arvid catalogues (`TAvtHeader`) |
| `TFindDrive`, `TTempDrive` | `filefind.pas` | the result of a file search, the temporary panel |

The virtual methods of `TDrive` that a remote file system has to answer:

| Method | Meaning for a remote panel |
|---|---|
| `GetDirectory(FileMask, TotalInfo)` | list the current directory: returns the `TFilesCollection` the panel draws |
| `OpenDirectory(Dir, PutDirs)` | builds the helper for a directory branch (`cmDirBranch`/`cmDirBranchFull` in `panelroot.pas`); not the way a panel enters a directory, see below |
| `lChDir`, `GetDir`, `GetRealDir`, `ChangeUp`, `ChangeRoot`, `isUp` | the current path and moving up (`..`) |
| `CopyFiles` (F5/F6 from this panel), `CopyFilesInto` (F5/F6 into this panel) | copy and move; the archive drive extracts to a temporary directory and then copies |
| `EraseFiles` | F8 |
| `UseFile(P, Command)` | F3 view and F4 edit (the archive drive extracts a temporary copy) |
| `MakeDir` | F7 |
| `GetFreeSpace`, `GetDirInfo`, `GetDirLength` | free space, directory size |
| `GetFull`, `GetDown`, `MakeTop`, `ColAllowed` | how a row, the footer and the column header look |
| `Disposable`, `KillUse`, `Destroy` | lifetime (the connection is closed here) |

A panel switches to another kind of content by creating a `TDrive` descendant and sending it with
`Message(Panel, evCommand, cmInsertDrive, Drv)`; `TFilePanelRoot.InsertDrive` puts it in place of the
current helper (examples: `TFindDrive` in `filefind.pas`, `TArcDrive` in `arcview.pas`, `TArvidDrive` and `TTempDrive`
in `panelroot.pas`). `TDriveType` (`panelsetup.pas`) names the kinds: `dtDisk`, `dtFind`, `dtTemp`, `dtList`,
`dtArcFind`, `dtArc`, `dtNet`, `dtLink`, `dtArvid`. `dtNet` and `dtLink` are tested in `panelroot.pas`
(lines about 700, 966-990, 1144, 1589, 1845) but no class of this tree sets them: they are a free
slot for the remote drive (step 3 checks what the tests of `dtNet`/`dtLink` do before it reuses one).

Typing a path goes through `TFilePanelRoot` `_ChangeDrv`/`DoChange` (`panelroot.pas`); `TFilePanelRoot.ChDir`
returns at once unless the drive is `dtDisk`. A typed `sh://...` path is therefore recognised in `DoChange`
(step 7), before the text is treated as a local name.

So the panel side needs no new hook: a new descendant of `TDrive` is enough. What is missing is the layer
below it (the thing that talks to a server), and the places that bypass `TDrive` and go to local files
directly. Those are the list in section 2.

## 2. Places that touch local files directly

Everything in DN reads directories through one pair of wrappers: `lFindFirst`/`lFindNext`/`lFindClose`
(`dn/src/lfn.pas`, long file names, then `SysFindFirst`/`SysFindNext` of `dn/compat/osdep.pas` and
`osnamesunix.pas`), and opens files through `lAssignFile`/`lResetFile`/`lReWriteFile` and the other `l*`
routines of the same unit (`SysFileOpen`, `SysFileCreate` in `osdep.pas`). Nothing in the code base calls the
RTL `FindFirst` directly except these wrappers.

The list below (29 sources and 2 notes, `dn/TODO-later.md` and `dn/TODO-refactoring.md`, which only talk about `FindFirst`) was produced with

    git grep -lE 'lFindFirst|lFindNext|FindFirst|FindNext' -- dn tv

and sorted by what the caller does. A remote panel must not break them, and some of them must learn to
work through `TRemoteFS`.

### 2.1 Panel and file commands (must learn about `TRemoteFS`)

| Unit | Place | Why it matters |
|---|---|---|
| `drives.pas` | `TDrive.GetDirectory` (`lFindFirst`/`lFindNext` loop), `TDrive.OpenDirectory` | the local drive: stays as is; the remote drive is a sibling class |
| `filescol.pas` | `CreateFileRec`: `lFindFirst` for one name when a `TFileRec` is built | builds file records from a path: a remote drive builds them from `TRemoteFS.List` |
| `filecopy.pas` | `CopyFiles` (implementation near line 2909), the directory recursion (`lFindFirst(Source+DnSep+'*.*', ...)`), the name-clash checks | the copy engine walks the source tree with `lFindFirst` and reads/writes with `l*` routines: for a remote side the walk and the read/write go through `TRemoteFS` |
| `copyio.pas` | `LongCopy` | one-file copy by blocks: needs a stream-like source and target |
| `copyjobs.pas`, `progress.pas` | the progress dialog and the job queue | stay as is (owned by unxed/dn#88); remote copy reports progress through the same calls |
| `eraser.pas` | `EraseFiles`, the recursive delete | F8 on a remote panel: `TRemoteFS.Remove` |
| `fileutil.pas` | `lFindFirst` for "does it exist", "is it a directory", `MkDir` helpers | the checks used by every dialog: need a path-aware variant |

### 2.2 Navigation and search (read only, can follow later)

| Unit | Place | Note |
|---|---|---|
| `panelroot.pas` | `_ChangeDrv`, `DoChange`, `ChDir`, `cmInsertDrive`/`InsertDrive` | where a typed `sh://...` path is recognised and a remote drive is inserted (step 7) |
| `tree.pas` | the directory tree reads sub-directories with `lFindFirst` | the tree shows local directories only in the first versions |
| `filefind.pas` | the file search, the temporary panel | search in a remote panel is out of scope of the first versions |
| `findspf.pas`, `diskinfo.pas`, `cfgdir.pas` | search and system helpers | local only |

### 2.3 Local only, not affected

`archiver.pas`, `arcview.pas`, `arvid.pas` (archives are read through their own path), `dnutil.pas` (swap
files, `*.lng` lookup), `editcore.pas`, `iniengine.pas`, `langid.pas`, `menus.pas`, `setups.pas`, `usermenu.pas`,
`uucode.pas`, `pktview.pas`, and the platform units `osdep.pas`, `osnamesunix.pas`,
`ossystemdos.pas`. They keep using the local wrappers. `dn/tests/t_osdep.pas` tests the wrappers.

## 3. The scheme

Two layers, both new and both optional (no network code in the `DN_MINI` and DOS builds, see the plan):

1. **`TRemoteFS`** (`dn/src/remotefs.pas`, step 3) is an abstract class with no user interface:
   `List`, `Stat`, `OpenRead`, `OpenWrite`, `MkDir`, `Remove`, `Rename`, `SetMode`. It knows nothing about
   panels. `TLocalFS` is the first implementation (used by the tests; the real local panel keeps its
   `lFindFirst` path). Later: `TFishFS` (step 6), `TSftpFS` (step 9), `TFtpFS` (step 11).
2. **`TRemoteDrive = class(TDrive)`** adapts a `TRemoteFS` to the panel: `GetDirectory` calls `List` and builds
   the `TFilesCollection`; `OpenDirectory`/`ChangeUp` change the path; `CopyFiles`/`CopyFilesInto`/`EraseFiles`/
   `UseFile`/`MakeDir` call the corresponding methods, copy through a temporary file at first (as `TArcDrive`
   does), and later stream. One class for all protocols: the protocol is the `TRemoteFS` it holds.

A **registry** by URL prefix maps `sh://`, `sftp://`, `ftp://` to a factory that makes the `TRemoteFS`.
`netsplit.pas` splits `proto://user@host:port/path` (step 3). The panel asks the registry in
`panelroot.pas` before it treats the typed text as a local path. A typed path that no prefix claims is local,
exactly as now, so nothing changes for a user who does not use the feature.

### Why not a hook at the `lFindFirst` level

`lFindFirst` has a fixed record (`lSearchRec`), works on local paths, is called from about 25 units of `dn/src`;
to make it protocol-aware every one of those callers would have to carry a connection. Panels already route every command through the `TDrive` object, so the number
of places that must change is the three groups of section 2.1 (copy, erase, existence checks), not every caller.
The price: the copy engine in `filecopy.pas` (about 3000 lines) gets a second kind of source and target.
Step 8 does it in the smallest way: a remote side is copied through a temporary local file, so the engine
itself is not rewritten.

### Why not the extfs or archive path

`TArcDrive` is the closest model (a read/write panel that is not a directory), but it is tied to archive
formats: file lists come from a wrapper process and a whole archive is unpacked or repacked. A server has
random access and needs no repack. `TArcDrive` is a pattern to copy (temporary file for view/edit/copy), not
a class to inherit from.

## 4. Rules for the new code

- No procedure nested on two levels that reads variables of the outer procedure: FPC 3.2.2 gives wrong values
  on linux-aarch64 (unxed/dn#80).
- All network units are under `{$IFNDEF DN_MINI}` and absent from the DOS targets.
- Do not change the copy dialog or the sub-shell (unxed/dn#88, unxed/dn#40); look at the open pull requests for
  `copyio.pas`/`copyjobs.pas` before step 8.
- Third-party scripts (the FISH helper from unxed/f4, BSD-3-Clause) live in `dn/third-party/f4-fish/` with
  their licence (step 5).

## 5. How to check this note

    git grep -lE 'lFindFirst|lFindNext|FindFirst|FindNext' -- dn tv   # the list of section 2 (31 files: 2 are notes)
    git grep -nE '= *class\((TDrive|TArcDrive|TFindDrive)\)' -- dn/src  # the drive classes of section 1

If a file appears in the first command but not in section 2, the note is out of date: add it.
