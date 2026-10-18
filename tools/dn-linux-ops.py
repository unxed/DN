#!/usr/bin/env python3
"""The file operations of the Linux build of DN in a pty, checked on the file system: make a directory, copy, move, delete, edit and
save a file, rename a group of files by a mask (File -> Group rename). usage: tools/dn-linux-ops.py OUTDIR   (OUTDIR: the result of tools/build.sh linux|linux64)"""
import base64
import os
import platform
import re
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dn_wait import DnTerm, side_by_side

F = {'F1': '\x1bOP', 'F2': '\x1bOQ', 'F3': '\x1bOR', 'F4': '\x1bOS', 'F5': '\x1b[15~', 'F6': '\x1b[17~', 'F7': '\x1b[18~', 'F8': '\x1b[19~', 'F10': '\x1b[21~',
     'DOWN': '\x1b[B', 'UP': '\x1b[A', 'ENTER': '\r', 'HOME': '\x1b[H', 'END': '\x1b[F', 'ESC': '\x1b', 'ALT-X': '\x1bx', 'TAB': '\t', 'CTRL-R': '\x12', 'INS': '\x1b[2~'}
fails = count = 0


def check(cond, name, info=''):
    global fails, count
    count += 1
    print(('PASS ' if cond else 'FAIL ') + name)
    if not cond:
        fails += 1
        if info:
            print(info)


def install(out):
    """a directory of its own with the program"""
    d = tempfile.mkdtemp(prefix='dnops-')
    for f in os.listdir(out):
        if f == 'dn' or f.upper().endswith(('.LNG', '.DLG', '.HLP')):
            shutil.copy(os.path.join(out, f), d)
        elif f == 'xlt':
            shutil.copytree(os.path.join(out, f), os.path.join(d, f))
    return d


def session(out, d):
    """the main session: the file operations one after another in one start of DN"""
    w = os.path.join(d, 'work')
    os.makedirs(w)
    open(os.path.join(w, 'a.txt'), 'w').write('first\n')
    open(os.path.join(w, 'b.txt'), 'w').write('other\n')
    open(os.path.join(w, 'c.txt'), 'w').write('third\n')
    payload = os.urandom(3 * 1024 * 1024 + 123)       # more than 64K: the copy buffer (Word was 16 bits)
    open(os.path.join(w, 'z.txt'), 'wb').write(payload)
    t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'))
    t.started()
    check(b'Error in country' not in t.raw, 'start: no country setup error (xlt next to the program)')
    t.send(F['ESC'], 0.5)

    def key(k, settle=0.6):
        t.send(F.get(k, k), settle)

    # the order of the panel: .., newdir, a, b, c (the default sort is by extension, then by name)
    key('F7'); key('newdir'); key('ENTER', 1.0)
    check(os.path.isdir(os.path.join(w, 'newdir')), 'F7: the directory is made')

    # the cursor moves: only the two lines of the panel are redrawn, they must be the same as in the other panel (the same directory)
    key('HOME'); key('DOWN')
    rows = [l for l in t.text().split('\n') if ('newdir' in l or ' txt' in l) and '\u2502' in l]   # the lines of the files, not the line under the panel
    halves = [(l[1:20].strip(), l[51:70].strip()) for l in rows]
    check(rows and all(a_ == b_ for a_, b_ in halves) and '\u2642' not in t.text(), 'Down: the redrawn lines of the panel are not garbage (the same as in the other panel)', t.text())

    # copy a.txt into newdir: the cursor on a.txt (.., newdir, a.txt; DN puts the cursor on the new directory)
    key('HOME'); key('DOWN'); key('DOWN')
    key('F5'); key('newdir'); key('ENTER', 1.2)
    check(os.path.isfile(os.path.join(w, 'newdir', 'a.txt')) and os.path.isfile(os.path.join(w, 'a.txt')),
          'F5: a.txt is copied into newdir, the original stays', t.text())
    check(t.alive() and 'Access violation' not in t.text() and 'Fatal' not in t.text(),
          'F5: copy returns without a fatal error', t.text())
    if os.path.isfile(os.path.join(w, 'newdir', 'a.txt')):
        check(open(os.path.join(w, 'newdir', 'a.txt')).read() == 'first\n', 'F5: the copy has the same content')

    # move b.txt into newdir
    key('DOWN')
    key('F6'); key('newdir'); key('ENTER', 1.2)
    check(os.path.isfile(os.path.join(w, 'newdir', 'b.txt')) and not os.path.exists(os.path.join(w, 'b.txt')),
          'F6: b.txt is moved into newdir', t.text())

    # delete c.txt (the cursor is on the next file after the moved one)
    key('F8'); key('ENTER', 1.2)
    gone = not os.path.exists(os.path.join(w, 'c.txt'))
    check(gone, 'F8: the file under the cursor is deleted (c.txt)', t.text())

    # a big file (the last one in the list): the copy must be the same bytes
    key('END')
    key('F5'); key('newdir'); key('ENTER', 2.5)
    got = os.path.join(w, 'newdir', 'z.txt')
    check(os.path.isfile(got) and open(got, 'rb').read() == payload, 'F5: a file of 3 MB is copied byte by byte', t.text())

    # edit a.txt: the cursor on a.txt; F4, a line at the top, F2 saves, Esc leaves
    key('HOME'); key('DOWN'); key('DOWN')
    key('F4', 1.0)
    key('hello ')
    key('F2', 0.8)
    key('ESC', 0.8)
    txt = open(os.path.join(w, 'a.txt')).read() if os.path.exists(os.path.join(w, 'a.txt')) else None
    check(txt is not None and txt.startswith('hello first'), 'F4: the edited text is saved (%r)' % (txt,), t.text())

    # into a directory and back
    key('HOME'); key('DOWN'); key('ENTER', 1.0)
    title = t.text().split('\n')[1]
    check('NEWDIR' in title.upper() and 'a' in t.text().split('\n')[3] + t.text().split('\n')[4],
          'Enter on a directory shows it (the title has newdir)', t.text())
    key('HOME'); key('ENTER', 1.0)
    check('NEWDIR' not in t.text().split('\n')[1].upper(), 'Enter on .. goes back up', t.text())

    # the help, several times: the window of the help is kept between the calls and was used after it was freed
    for _ in range(4):
        key('F1', 1.0)
        for _ in range(6):                       # Esc until the window of the help is gone (a slow machine needs time)
            if '\u2550 Help \u2550' not in t.text():
                break
            key('ESC', 0.8)
    check(t.alive() and 'Fatal' not in t.text() and 'Name' in t.text() and '\u2550 Help \u2550' not in t.text(), 'F1 and Esc four times: no crash', t.text())

    # Russian names: a directory made by F7 has the name in UTF-8 in the file system and is shown as Russian
    key('F7'); key('\u0442\u0435\u0441\u0442'); key('ENTER', 1.0)
    check(os.path.isdir(os.path.join(w, '\u0442\u0435\u0441\u0442')), 'F7: a Russian name is a UTF-8 name in the file system', t.text())
    check('\u0442\u0435\u0441\u0442' in t.text(), 'the Russian name is shown as Russian', t.text())
    os.makedirs(os.path.join(w, '\u043f\u0430\u043f\u043a\u0430'))
    open(os.path.join(w, '\u043f\u0430\u043f\u043a\u0430', 'x.txt'), 'w').write('x')
    key('HOME'); key('DOWN'); key('ENTER', 1.0); key('HOME'); key('ENTER', 1.0)     # into newdir and back: the directory is read again
    check('\u043f\u0430\u043f\u043a\u0430' in t.text(), 'a directory with a Russian name made outside is shown as Russian', t.text())

    # a long Russian name typed into the dialog: the letters were drawn as other characters (the bytes of "ров", "рка" of CP866 are valid UTF-8)
    key('F7'); key('\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430 \u0434\u043b\u0438\u043d\u043d\u044b\u0445 \u0438\u043c\u0451\u043d', 0.8)
    check('\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430 \u0434\u043b\u0438\u043d\u043d\u044b\u0445 \u0438\u043c\u0451\u043d' in t.text(), 'the typed Russian text is drawn as typed in the input line', t.text())
    key('ENTER', 1.0)
    check(os.path.isdir(os.path.join(w, '\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430 \u0434\u043b\u0438\u043d\u043d\u044b\u0445 \u0438\u043c\u0451\u043d')), 'the directory with the long Russian name is made')

    # Alt-F1, the drive menu, TEMP: (a temporary drive; the panel info was drawn with an empty list: collection error 213)
    key('\x1b[1;3P'); key('END'); key('ENTER', 1.0)
    check('TEMP:' in t.text().split('\n')[1] and t.alive(), 'Alt-F1: the drive TEMP: opens without an error', t.text())

    # a command of the command line: the terminal is given to the shell, Enter returns to DN (it hung before)
    key('echo ran-ok > ran.txt; echo shown-ok'); key('ENTER', 1.5)
    check('shown-ok' in t.text() and 'Press Enter' in t.text(), 'a command: its output is on the screen and DN waits for Enter', t.text())
    key('ENTER', 1.5)
    check(os.path.isfile(os.path.join(w, 'ran.txt')) and open(os.path.join(w, 'ran.txt')).read() == 'ran-ok\n', 'the command was run in the directory of the panel')
    check('Name' in t.text() and t.alive(), 'DN is back with its panels', t.text())

    # the Info panel is on at the end: quitting disposes the windows (TGroup.Done followed a view that had been disposed: Access violation)
    # no Esc before F10: on an empty command line Esc shows the screen of the user
    key('F10'); [key('\x1b[C', 0.2) for _ in range(5)]; [key('DOWN', 0.2) for _ in range(3)]; key('ENTER', 1.0)
    check(t.alive() and 'Current directory' in t.text(), 'the Info panel is on', t.text())

    # the screen of the user: Ctrl-O shows what the commands drew (the emulator of tv/), a key leaves it; the mini build (DN_MINI=1,
    # dn/build.env) has no emulator: the commands draw on the terminal itself
    if os.environ.get('DN_MINI') == '1':
        print('SKIP Ctrl-O, the screen of the commands: the mini build (DN_MINI=1) has no embedded terminal', flush=True)
    else:
        key('\x0f', 1.0)
        check('shown-ok' in t.text() and 'ran-ok' in t.text(), 'Ctrl-O: the screen of the commands (the command line and its output)', t.text())
        key('x', 1.0)
        check('Name' in t.text() and t.alive(), 'a key leaves the screen of the user: the panels are back', t.text())

    key('ALT-X'); key('ENTER', 1.5)
    scr = t.text()
    status = t.close(4)
    check(status == 0, 'Alt-X ends the program (status %r)' % (status,), scr)


def blocked_note(screen):
    """the message of dn#88 step 4: a command held back by a background copy (the box may wrap the words)"""
    return 'background copy' in screen.replace('\n', ' ') or ('background' in screen and 'running' in screen)


def panel_half(screen, side):
    """one panel of the 100-column screen (dn#88 step 3b)"""
    if side == 'left':
        return '\n'.join(line[:50] for line in screen.split('\n'))
    return '\n'.join(line[50:] for line in screen.split('\n'))


def destination_panel(screen, dst):
    """Return the screen half showing the receiving destination panel."""
    for side in ('left', 'right'):
        half = panel_half(screen, side)
        if dst in half:
            return half
    return ''


def background_copy(out, d):
    """A background copy leaves the panels responsive and finishes every file."""
    w = os.path.join(d, 'background')
    src = os.path.join(w, 'source')
    dst = os.path.join(w, 'destination')
    os.makedirs(src)
    os.makedirs(dst)
    os.makedirs(os.path.join(w, 'waiting'))        # where the copy asked for during the background one goes (dn#88 step 5b)
    os.makedirs(os.path.join(w, 'zcancelled'))     # where a third one would go; it is cancelled from the list (step 5c)
    # Many small files, not few big ones: the progress window is redrawn between files, and a window of 64 files of 8 MB was not
    # on the screen for 10 s on any runner ("the progress window offers Background" failed in all six jobs of dn-linux #714, while
    # 512 files of 256 KB passed it in five). 4096 files of 64 KB keep the copy running longer than 512 of 256 KB did; whether it
    # is still running when the keys are pressed is checked, not assumed.
    nfiles = 4096
    payload = os.urandom(64 * 1024)
    for i in range(nfiles):
        with open(os.path.join(src, 'file%03d.dat' % i), 'wb') as f:
            f.write(payload)

    t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'))
    closed = False                                   # Alt-X at the end has already closed the terminal
    t.started()
    try:
        t.send(F['ESC'], 0.3)
        # dn#88 step 3b: the other panel shows the destination before the copy starts, so the end of the copy has to refresh it
        t.send(F['TAB'], 0.3)
        t.send(F['HOME'], 0.2)
        t.send(F['DOWN'], 0.2)                           # .., destination, source
        t.send(F['ENTER'], 0.6)                          # into destination
        other_panel_screen = t.text()
        receiving_panel_before = destination_panel(other_panel_screen, dst)
        other_panel_ready = bool(receiving_panel_before) and 'source' not in receiving_panel_before   # only ".." is listed before the copy
        t.send(F['TAB'], 0.3)
        t.send(F['HOME'], 0.2)
        t.send(F['DOWN'], 0.2)                           # .., destination, source
        t.send(F['DOWN'], 0.2)
        t.send(F['F5'], 0.2)
        t.send('destination', 0.2)
        t.send(F['ENTER'], 0.2)
        offered = t.wait_text('Background', timeout=10.0)
        check(offered, 'F5: the progress window offers Background', t.text())
        went_background = False                          # the copy was sent to the background (the panels came back)
        f5_queued = False                                # F5 during that copy left a waiting job (dn#88 step 5b)
        list_met_end = False                             # the copy ended while the keys of that list of jobs were pressed
        cancel_tried = False                             # a third copy was queued and then cancelled from the list
        third_cancelled = False                          # the list showed it as "[cancelled]"
        if offered:
            t.send(F['TAB'], 0.5)                       # Stop -> Background (the copy takes one event per 300 ms)
            t.send(F['ENTER'], 0.8)
            after_enter = t.text()
            # dn-linux #720 (head 84a1f05): "Abort operation?" was already open when F5/F8 were pressed, and the copy stood at 681
            # of 4096 files behind that modal question; show the screen right after Enter to see who opened it
            if 'Abort operation' in after_enter:
                print('--- the screen right after Enter on Background: the copy asks "Abort operation?" (Stop was pressed?):\n' + after_enter, flush=True)
                t.send(F['ESC'], 0.8)
            returned = t.until(lambda: 'Name' in t.text() and 'Background' not in t.text(), 5.0)
            still_copying = not all(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i))
                                    for i in range(nfiles))
            check(returned, 'Background: the panels return', t.text())
            went_background = bool(returned)
            if still_copying:
                t.send(F['UP'], 0.3)                    # the panel moves; back on source, which the waiting copy copies again
                t.send(F['DOWN'], 0.5)
                t.send(F['F5'], 0.5)
                # dn#88 step 5b: F5 during the background copy opens the Copy dialog, and OK puts the copy in the job list as a
                # waiting job instead of starting a second one. The Copy dialog is the only screen with a Cancel button (the
                # progress window has Stop); the F-key bar and the title of the progress window both contain "Copy", so that word
                # proves nothing
                f5_screen = t.text()
                f5_note = blocked_note(f5_screen)
                if f5_note:
                    t.send(F['ENTER'], 0.5)
                # only a copy that still runs when the screen is read proves anything, as for F8 below
                copy_ran_f5 = not all(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i)) for i in range(nfiles))
                f5_dialog_visible = 'Cancel' in f5_screen
                if f5_dialog_visible:
                    t.send('waiting', 0.2)
                    t.send(F['ENTER'], 1.0)
                    after_ok = t.text()
                    f5_queued = 'Background' not in after_ok and 'Cancel' not in after_ok and not blocked_note(after_ok)
                    if not f5_queued:
                        print('--- the screen after OK in the Copy dialog during the background copy (a waiting job expected):\n' +
                              after_ok, flush=True)
                        t.send(F['ESC'], 0.5)
                    else:
                        # the list of jobs is read at once: later on the copy may be over (the check of "[run N%]" below
                        # is skipped on most runners for that reason)
                        t.send('\x1bu', 0.8)            # Alt-U: Utilities
                        t.send('j', 1.0)                # Copy ~j~obs...
                        f5_jobs_screen = t.text()
                        copy_ran_list = not all(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i)) for i in range(nfiles))
                        list_met_end = not copy_ran_list
                        t.send(F['ESC'], 0.5)           # Esc closes the list; Enter would press the default button, Cancel job
                        if copy_ran_list:
                            check('[wait]' in f5_jobs_screen and '[run' in f5_jobs_screen,
                                  'Background: Utilities, Copy jobs shows the running copy and the one asked for during it as "[wait]"',
                                  f5_jobs_screen)
                            # dn#88 step 5c: a third copy, cancelled from the list while it waits, never starts
                            t.send(F['F5'], 0.5)
                            third_dialog = 'Cancel' in t.text()
                            copy_ran_third = not all(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i)) for i in range(nfiles))
                            if third_dialog and copy_ran_third:
                                t.send('zcancelled', 0.2)
                                t.send(F['ENTER'], 1.0)
                                t.send('\x1bu', 0.8)        # Alt-U: Utilities
                                t.send('j', 1.0)            # Copy ~j~obs...
                                t.send(F['END'], 0.3)       # the newest job, the third copy
                                t.send(F['ENTER'], 1.0)     # Cancel job, the default button; the list is built again
                                cancel_screen = t.text()
                                t.send(F['ESC'], 0.5)
                                cancel_tried = True
                                third_cancelled = '[cancelled]' in cancel_screen
                                if not third_cancelled:
                                    print('--- the list of jobs after Cancel job on the third copy:\n' + cancel_screen, flush=True)
                            elif third_dialog:
                                t.send(F['ESC'], 0.5)       # the first copy is over: this would be a plain copy, not a waiting one
                                print('SKIP Background: the copy finished before the third copy was asked for, its cancel is not checked', flush=True)
                            # the copy may have ended during these keys, and Esc may have closed its message
                            list_met_end = list_met_end or all(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i))
                                                               for i in range(nfiles))
                        else:
                            print('SKIP Background: the copy finished before the list of jobs was read, "[wait]" is not checked', flush=True)
                if copy_ran_f5:
                    check(f5_dialog_visible and f5_queued and not f5_note,
                          'Background: F5 opens the Copy dialog and OK leaves the panels (dialog %r, waiting job %r, blocked note %r)' % (
                              f5_dialog_visible, f5_queued, f5_note), f5_screen)
                else:
                    print('SKIP Background: the copy finished before F5 was pressed, the waiting copy is not checked', flush=True)
                f5_opened_dialog = False
                t.send(F['F8'], 0.5)
                f8_screen = t.text()
                f8_note = blocked_note(f8_screen)
                if f8_note:
                    t.send(F['ENTER'], 0.5)
                # F8 on a copy that has just finished is a real delete dialog: only a copy that still runs when the screen is read proves anything
                copy_ran_on = not all(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i)) for i in range(nfiles))
                f8_dialog_visible = 'Confirm' in f8_screen or 'wish to delete' in f8_screen
                f8_opened_dialog = f8_dialog_visible and copy_ran_on
                if f8_opened_dialog:
                    print('--- the screen right after F8 (a dialog is expected to be absent):\n' + f8_screen, flush=True)
                if f8_dialog_visible:
                    t.send(F['ESC'], 0.2)
                t.send(F['ALT-X'], 0.5)
                quit_screen = t.text()
                copy_ran_quit = not all(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i)) for i in range(nfiles))
                quit_note = blocked_note(quit_screen)
                if quit_note:
                    t.send(F['ENTER'], 0.5)
                elif 'wish to quit' in quit_screen:
                    t.send(F['ESC'], 0.5)               # No: a quit question left open would hold the copy and the checks below
                if copy_ran_on and copy_ran_quit:
                    check(f8_note and quit_note and t.alive(),
                          'Background: F8 and Alt-X say that a background copy is running, Enter closes it, dn goes on '
                          '(F8 %r, Alt-X %r)' % (f8_note, quit_note), quit_screen)
                else:
                    print('SKIP Background: the copy finished before F8/Alt-X were both pressed, the message is not checked', flush=True)
                check(not f5_opened_dialog and not f8_opened_dialog and os.path.isdir(src),
                      'Background: panel navigation works and F5/F8 do not start foreground operations '
                      '(F5 dialog %r, F8 dialog %r, source is a directory %r, %d of %d files copied)' % (
                          f5_opened_dialog, f8_opened_dialog, os.path.isdir(src),
                          sum(os.path.isfile(os.path.join(dst, 'source', 'file%03d.dat' % i)) for i in range(nfiles)), nfiles),
                      t.text())
            else:
                print('SKIP Background: the copy finished before F5/F8 could be pressed, nothing is left to block', flush=True)

        expected = [os.path.join(dst, 'source', 'file%03d.dat' % i) for i in range(nfiles)]
        # the speed of the copy in the background: files copied after 0, 3 and 6 seconds (a copy waiting for events for 100 ms per file
        # does about 10 files a second)
        counts = []
        for _ in range(3):
            counts.append(sum(os.path.isfile(p) for p in expected))
            t.until(lambda: False, 3.0)
        print('background copy: files copied at 0, 3 and 6 seconds: %r of %d' % (counts, nfiles), flush=True)
        # the state of the background copy stands in the place of the clock, on the top line (dn#88 step 2b); only a copy that
        # still runs when the screen is read proves anything, as for F5/F8 above
        top = t.text().split('\n')[0]
        if not all(os.path.isfile(p) for p in expected):
            check(re.search(r'\bCopy \d+%', top) is not None,
                  'Background: the place of the clock shows "Copy N%%" while the copy runs (%r)' % top.strip()[-24:], t.text())
        else:
            print('SKIP clock: the copy finished before the top line was read', flush=True)
        # Utilities, Copy jobs shows how far the running copy is (dn#88 step 1). The percent is whole, and in the background the copy
        # does about 10 files a second, so the list is opened only when 2% of the files are there.
        keys_met_end = False                             # the keys of the list were pressed after the copy had ended
        two_percent = t.until(lambda: sum(os.path.isfile(p) for p in expected) >= nfiles // 50, 30.0)
        if two_percent and not all(os.path.isfile(p) for p in expected):
            t.send('\x1bu', 0.8)                        # Alt-U: Utilities
            t.send('j', 1.0)                            # Copy ~j~obs...
            jobs_screen = t.text()
            # a copy that has just finished leaves an empty list (dn-linux #38749777724: 3963 of 4096 files at 6 seconds, then 1.8 seconds
            # of keys before the screen was read): only a copy that still runs when the screen is read proves anything, as for F5/F8 above
            copy_ran_jobs = not all(os.path.isfile(p) for p in expected)
            run = re.search(r'\[run (\d+)%\]', jobs_screen)
            if run is not None or copy_ran_jobs:
                check(run is not None and int(run.group(1)) > 0,
                      'Background: Utilities, Copy jobs shows the running copy with a percent above 0 (%s)' % (
                          run.group(0) if run else 'no "[run N%]" on the screen'), jobs_screen)
            else:
                print('SKIP Copy jobs: the copy finished before the list was read, nothing is left to show', flush=True)
            keys_met_end = not copy_ran_jobs
            t.send(F['ESC'], 0.5)                       # Esc closes the list; Enter would press the default button, Cancel job
        else:
            print('SKIP Copy jobs: the copy finished (or did not reach 2%) before the list could be opened', flush=True)
        finished = t.until(lambda: all(os.path.isfile(p) for p in expected), 60.0)
        copied = [p for p in expected if os.path.isfile(p)]
        wrong = [p for p in copied if open(p, 'rb').read() != payload]
        check(finished and not wrong,
              'Background: every source file finishes with the same contents '
              '(finished %r, %d of %d files exist, %d with other contents, source is a directory %r)' % (
                  finished, len(copied), nfiles, len(wrong), os.path.isdir(src)), t.text())
        # dn#88 step 5c: the copy that waited in the list starts by itself when the first one ends, in the background too, and
        # only the last copy says that it is done
        if f5_queued:
            queued_expected = [os.path.join(w, 'waiting', 'source', 'file%03d.dat' % i) for i in range(nfiles)]
            queued_finished = t.until(lambda: all(os.path.isfile(p) for p in queued_expected), 120.0)
            queued_copied = [p for p in queued_expected if os.path.isfile(p)]
            queued_wrong = [p for p in queued_copied if open(p, 'rb').read() != payload]
            check(queued_finished and not queued_wrong,
                  'Background: the waiting copy starts after the first one and finishes every file with the same contents '
                  '(finished %r, %d of %d files exist, %d with other contents)' % (
                      queued_finished, len(queued_copied), nfiles, len(queued_wrong)), t.text())
            if cancel_tried:
                t.until(lambda: False, 2.0)             # time for a wrongly started third copy to make its first files
                check(third_cancelled and not os.path.exists(os.path.join(w, 'zcancelled', 'source')),
                      'Background: a waiting copy cancelled from the list does not start (shown as "[cancelled]" %r, '
                      'its folder made %r)' % (third_cancelled, os.path.exists(os.path.join(w, 'zcancelled', 'source'))), t.text())
        if went_background and (keys_met_end or list_met_end):
            # the message waits for a key and the Esc that closed the list of jobs can have closed it (dn-linux #781, head 14f7f94, both jobs with this check:
            # 3963 of 4096 files at 6 seconds, the copy ended while Alt-U, j and Esc were pressed): only a copy that still runs when the
            # last key is pressed proves anything, as for the list of jobs above
            print('SKIP Background: the end of the copy is announced: the copy ended while the keys of the list of jobs were pressed', flush=True)
            # the message of a copy that waited in the list comes when that copy ends, so it is waited for; the Esc of the
            # list may have closed a message of the first copy, and then none comes
            if t.wait_text('Copy finished', timeout=5.0):
                t.send(F['ENTER'], 0.5)
        elif went_background:
            # dn#88 step 3: a copy that ran in the background says that it is done; the message waits for Enter
            announced = t.wait_text('Copy finished', timeout=15.0)
            check(announced, 'Background: the end of the copy is announced ("Copy finished")', t.text())
            if announced:
                t.send(F['ENTER'], 0.5)
                # dn#88 step 3b: the other panel shows the destination; the copied directory appears there without a re-read by hand
                if other_panel_ready:
                    shown = t.until(lambda: 'source' in destination_panel(t.text(), dst), 5.0)
                    check(shown, 'Background: the receiving panel lists the copied directory after the copy ends', t.text())
                else:
                    print('SKIP receiving panel: the other panel did not show the empty destination before the copy', flush=True)
                    print('--- screen before the background copy (left and right panels):\n' + other_panel_screen, flush=True)
                    print('--- receiving panel before the background copy:\n' + receiving_panel_before, flush=True)
        clock_back = t.until(lambda: re.search(r'\bCopy\b', t.text().split('\n')[0]) is None, 5.0)
        check(clock_back, 'Background: the clock comes back when the copy ends (%r)' % t.text().split('\n')[0].strip()[-24:],
              t.text())
        check(t.alive() and 'Fatal' not in t.text(), 'Background: DN remains alive', t.text())
        # dn#88 step 4: Alt-X, held back while the copy ran, ends the program once the copy is over
        t.send(F['ALT-X'], 0.5)
        quit_screen = t.text()
        t.send(F['ENTER'], 1.5)
        status = t.close(4)
        closed = True
        check(status == 0 and not blocked_note(quit_screen),
              'Background: Alt-X ends the program after the copy (status %r)' % (status,), quit_screen)
    finally:
        if not closed:
            if t.alive():
                t.send(F['ALT-X'], 0.3)
                t.send(F['ENTER'], 0.3)
            t.close(3)
        # a crash report of DN (Fatal Error ... crash001.txt) names the call chain: put it in the log, the file is lost with the runner
        crash = os.path.join(d, 'crash')
        if os.path.isdir(crash):
            for name in sorted(os.listdir(crash)):
                print('--- ' + name, flush=True)
                print(open(os.path.join(crash, name), errors='replace').read()[:6000], flush=True)


def background_start(out, d):
    """dn#88 step 6: "Start in background" in the Copy dialog sends the copy to the background at once."""
    w = os.path.join(d, 'bgstart')
    src = os.path.join(w, 'source')
    dst = os.path.join(w, 'destination')
    os.makedirs(src)
    os.makedirs(dst)
    nfiles = 2048
    payload = os.urandom(64 * 1024)
    for i in range(nfiles):
        with open(os.path.join(src, 'file%03d.dat' % i), 'wb') as f:
            f.write(payload)
    expected = [os.path.join(dst, 'source', 'file%03d.dat' % i) for i in range(nfiles)]
    t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'))
    t.started()
    try:
        t.send(F['ESC'], 0.3)
        t.send(F['HOME'], 0.2)
        t.send(F['DOWN'], 0.2)                           # .., destination, source
        t.send(F['DOWN'], 0.2)
        t.send(F['F5'], 0.5)
        dialog = t.text()
        check('Start in background' in dialog, 'Copy dialog: the box "Start in background" is there', dialog)
        t.send('destination', 0.2)
        t.send('\x1bb', 0.3)                           # Alt-B: Start in ~b~ackground
        t.send(F['ENTER'], 0.2)
        # the panels come back while the copy runs: no progress window with a Background button, the place of the clock
        # tells how far the copy is
        # (the window of a copy in the background keeps only "Stop"; the clock place is redrawn once a second)
        back = t.until(lambda: 'Name' in t.text() and 'Background' not in t.text() and 'Cancel' not in t.text()
                       and re.search(r'\bCopy\b', t.text().split('\n')[0]) is not None, 5.0)
        top = t.text().split('\n')[0]
        running = not all(os.path.isfile(p) for p in expected)
        if running:
            check(back,
                  'Start in background: the panels come back at once and the clock place shows the copy (%r)' % top.strip()[-24:],
                  t.text())
        else:
            print('SKIP Start in background: the copy finished before the screen was read', flush=True)
        finished = t.until(lambda: all(os.path.isfile(p) for p in expected), 120.0)
        wrong = [p for p in expected if os.path.isfile(p) and open(p, 'rb').read() != payload]
        check(finished and not wrong,
              'Start in background: every file is copied with the same contents (finished %r, %d with other contents)' % (
                  finished, len(wrong)), t.text())
        if t.wait_text('Copy finished', timeout=15.0):
            t.send(F['ENTER'], 0.5)
        # dn#88 step 7: F1 in Utilities, Copy jobs opens the topic of the list (the ended copy is still on it)
        t.send('\x1bu', 0.8)                            # Alt-U: Utilities
        t.send('j', 1.0)                                # Copy ~j~obs...
        t.send(F['F1'], 1.5)
        help_screen = t.text()
        check('Utilities|Copy jobs lists' in help_screen,
              'F1 in Copy jobs opens the help topic "Copy jobs"', help_screen)
        t.send(F['ESC'], 0.5)                           # the help
        t.send(F['ESC'], 0.5)                           # the list
        check(t.alive() and 'Fatal' not in t.text(), 'Start in background: DN remains alive', t.text())
    finally:
        if t.alive():
            t.send(F['ALT-X'], 0.3)
            t.send(F['ENTER'], 0.3)
        t.close(3)


def utf8(out, d):
    """the build with -dDNUTF8 (UTF-8 inside): what the legacy build cannot show"""
    u = os.path.join(d, 'u8')
    os.makedirs(u)
    for n in ('\u042f\u0431\u043b\u043e\u043a\u043e', '\u0430\u0440\u0431\u0443\u0437', '\u0410\u043b\u044c\u0444\u0430', '\u0431\u0435\u0442\u0430', 'Zeta'):
        open(os.path.join(u, n), 'w').write('x')
    open(os.path.join(u, '\u0444\u0430\u0439\u043b.txt'), 'w').write('\u041f\u0440\u0438\u0432\u0435\u0442, \u043c\u0438\u0440\nsecond\n')
    t = DnTerm(['./dn'], 100, 30, cwd=u, exe=os.path.join(d, 'dn'))
    t.started()
    t.send(F['ESC'], 0.5)
    lines = [l for l in t.text().split('\n')]
    order = [n for n in ('Zeta', '\u0410\u043b\u044c\u0444\u0430', '\u0430\u0440\u0431\u0443\u0437', '\u0431\u0435\u0442\u0430', '\u042f\u0431\u043b\u043e\u043a\u043e')]
    pos = [next((i for i, l in enumerate(lines) if n in l), -1) for n in order]
    check(all(p >= 0 for p in pos) and pos == sorted(pos), 'UTF-8: the names are sorted ignoring the case (Zeta, \u0410\u043b\u044c\u0444\u0430, \u0430\u0440\u0431\u0443\u0437, \u0431\u0435\u0442\u0430, \u042f\u0431\u043b\u043e\u043a\u043e)', t.text())
    t.send(F['END'], 0.5)
    t.send(F['F3'], 1.2)
    check('\u041f\u0440\u0438\u0432\u0435\u0442, \u043c\u0438\u0440' in t.text(), 'UTF-8: F3 shows a Russian text file', t.text())
    t.send(F['ESC'], 0.5)
    t.send(F['ALT-X'], 0.8)
    t.send(F['ENTER'], 1.0)
    t.close(3)

    # the columns: a name with wide (CJK) letters takes two columns each, the next column stays in its place
    cj = os.path.join(d, 'u8cjk')
    os.makedirs(cj)
    for n in ('abc.txt', '\u65e5\u672c\u8a9e.txt', 'e\u0301x.txt'):
        open(os.path.join(cj, n), 'w').write('x')
    t = DnTerm(['./dn'], 100, 30, cwd=cj, exe=os.path.join(d, 'dn'))
    t.started()
    t.send(F['ESC'], 0.5)
    # only the lines of the files (the name, the extension and the column line): the frame title shows the random
    # temporary path (dnops-ey4beexn holds 'ex'), so a bare substring may find the title instead of the file
    files = [l for l in t.text().split('\n') if 'txt' in l and '\u2502' in l]
    rows = {k: next((l for l in files if k in l), '') for k in ('abc', '\u65e5\u672c\u8a9e', 'ex')}     # the screen of the test has no cell for a combining mark
    ok = all(rows.values())
    col = {k: v.find('txt') for k, v in rows.items()}
    check(ok and col['abc'] == col['\u65e5\u672c\u8a9e'] + 3 and col['abc'] == col['ex'], 'UTF-8: wide letters take two columns and a combining mark none (the extension stays in its column)', t.text())
    t.send(F['ALT-X'], 0.8)
    t.send(F['ENTER'], 1.0)
    t.close(3)

    # the Russian interface: Alt and a Cyrillic letter (the keyboard sends Esc and the letter in UTF-8)
    ru = os.path.join(d, 'u8ru')                                   # a new copy of the program: DN.INI of the first session keeps its language
    os.makedirs(os.path.join(ru, 'w'))
    for f in os.listdir(out):
        if f == 'dn' or f.upper().endswith(('.LNG', '.DLG', '.HLP')):
            shutil.copy(os.path.join(out, f), ru)
        elif f == 'xlt':
            shutil.copytree(os.path.join(out, f), os.path.join(ru, f))
    t = DnTerm(['./dn'], 100, 30, env={'DNLNG': 'Russian'}, cwd=os.path.join(ru, 'w'), exe=os.path.join(ru, 'dn'))
    t.started()
    t.send(F['ESC'], 0.5)
    t.send('\x1b\u0444', 1.0)                                   # Alt-\u0444: the menu "\u0424\u0430\u0439\u043b"
    check('\u0421\u043c\u043e\u0442\u0440\u0435\u0442\u044c' in t.text(), 'UTF-8: Alt and a Cyrillic letter opens the menu', t.text())
    t.send(F['ESC'], 0.5)
    t.send(F['F7'], 1.0)
    t.send('\u0442\u0435\u0441\u0442\u0032', 0.5)
    t.send('\x1b\u043a', 1.2)                                   # Alt-\u043a: the button "\u041e~\u041a~"
    check(os.path.isdir(os.path.join(ru, 'w', '\u0442\u0435\u0441\u0442\u0032')), 'UTF-8: Alt and a Cyrillic letter presses the button of a dialog', t.text())
    t.send('\x13', 0.6)                                          # Ctrl-S: the quick search of the panel, Cyrillic letters
    t.send('\u0442\u0435', 0.8)
    check('\u041f\u043e\u0438\u0441\u043a: \u0442\u0435' in t.text(), 'UTF-8: Ctrl-S and Cyrillic letters make the mask of the quick search', t.text())
    t.send(F['ESC'], 0.5)
    t.send(F['ALT-X'], 0.8)
    t.send(F['ENTER'], 1.0)
    t.close(3)

    # the system clipboard: Edit/Copy of the editor puts the text on the clipboard of the terminal (OSC 52, UTF-8)
    t = DnTerm(['./dn'], 100, 30, env={'TERM': 'xterm-256color'}, cwd=u, exe=os.path.join(d, 'dn'))
    t.started()
    t.send(F['ESC'], 0.5)
    t.send(F['END'], 0.5)
    t.send(F['F4'], 1.2)
    for _ in range(6):
        t.send('\x1b[1;2C', 0.5)                                   # Shift-Right: select
    t.send(F['F10'], 0.5)
    t.send('\x1b[C', 0.5)
    t.send(F['ENTER'], 0.8)
    t.send('c', 1.0)                                             # Copy
    got = [base64.b64decode(x).decode('utf-8', 'replace') for x in re.findall(rb'\x1b\]52;c;([A-Za-z0-9+/=]*)\x07', t.raw)]
    check(got and got[-1] == '\u041f\u0440\u0438\u0432\u0435\u0442', 'UTF-8: Edit/Copy puts the selected Russian text on the clipboard (OSC 52)', repr(got))
    t.send(F['ESC'], 0.5)
    t.send(F['ALT-X'], 0.8)
    t.send(F['ENTER'], 1.0)
    t.close(3)

    # the editor works by characters: typing, Backspace, the dash and the quotes of the text stay, the file is saved as UTF-8
    ed = os.path.join(d, 'u8ed')
    os.makedirs(ed)
    fn = os.path.join(ed, 'f.txt')
    open(fn, 'w', encoding='utf-8').write('\u041f\u0440\u0438\u0432\u0435\u0442, \u043c\u0438\u0440\n\u0432\u0442\u043e\u0440\u0430\u044f \u2014 \u0441\u0442\u0440\u043e\u043a\u0430 \u00abx\u00bb\n')
    t = DnTerm(['./dn'], 100, 30, env={'TERM': 'xterm-256color'}, cwd=ed, exe=os.path.join(d, 'dn'))
    t.started()
    t.send(F['ESC'], 0.5)
    t.send(F['DOWN'], 0.3)
    t.send(F['DOWN'], 0.3)
    t.send(F['F4'], 1.2)
    t.send(F['HOME'], 0.4)
    t.send('\u0416', 0.5)
    t.send(F['END'], 0.4)
    t.send('!', 0.4)
    t.send(F['DOWN'], 0.4)
    t.send(F['END'], 0.4)
    t.send('\x7f', 0.4)
    t.send('\x7f', 0.4)
    scr = t.text()
    check('\u0416\u041f\u0440\u0438\u0432\u0435\u0442, \u043c\u0438\u0440!' in scr and '\u0432\u0442\u043e\u0440\u0430\u044f \u2014 \u0441\u0442\u0440\u043e\u043a\u0430 \u00ab' in scr, 'UTF-8 editor: the typed text is on the screen, Backspace removes characters', scr)
    t.send(F['F2'], 1.0)
    check(open(fn, encoding='utf-8').read() == '\u0416\u041f\u0440\u0438\u0432\u0435\u0442, \u043c\u0438\u0440!\n\u0432\u0442\u043e\u0440\u0430\u044f \u2014 \u0441\u0442\u0440\u043e\u043a\u0430 \u00ab\n', 'UTF-8 editor: the file is saved as UTF-8 (the dash and the quotes are kept)')
    t.send(F['UP'], 0.4)
    t.send(F['END'], 0.4)
    for ch in '\u03b1\u03b2\u2502\u2026':                 # Greek letters (the code page has none), a frame character (a cell of the table), the ellipsis
        t.send(ch, 0.4)
    t.send(F['F2'], 1.0)
    check(open(fn, encoding='utf-8').read() == '\u0416\u041f\u0440\u0438\u0432\u0435\u0442, \u043c\u0438\u0440!\u03b1\u03b2\u2502\u2026\n\u0432\u0442\u043e\u0440\u0430\u044f \u2014 \u0441\u0442\u0440\u043e\u043a\u0430 \u00ab\n', 'UTF-8 editor: characters outside the code page are typed and saved', open(fn, encoding='utf-8').read())
    t.send(F['ESC'], 0.5)
    t.send(F['ALT-X'], 0.8)
    t.send(F['ENTER'], 1.0)
    t.close(3)


def desktop(out, d):
    # Options -> Startup -> "Autosave Desktop" + "Preserve directory": the desktop is saved at Alt-X (DN.DSK next to the program) and comes back
    # at the next start (the active panel's directory is stored only with "Preserve directory": that is how TFilePanelRoot.Store is written)
    dd = os.path.join(d, 'dskrun')
    os.makedirs(os.path.join(dd, 'work', 'sub'))
    for f in os.listdir(out):
        if f == 'dn' or f.upper().endswith(('.LNG', '.DLG', '.HLP')):
            shutil.copy(os.path.join(out, f), dd)
        elif f == 'xlt':
            shutil.copytree(os.path.join(out, f), os.path.join(dd, 'xlt'))
    dw = os.path.join(dd, 'work')

    def dsk_start():
        tt = DnTerm(['./dn'], 100, 30, cwd=dw, exe=os.path.join(dd, 'dn'))
        tt.started()
        tt.send(F['ESC'], 0.5)
        return tt

    def dsk_cwd(tt):                                   # the directory of the active panel: the end of the command line prompt
        return [l for l in tt.text().split('\n') if l.rstrip().endswith('>')][-1].strip()

    def dsk_quit(tt):
        tt.send(F['ALT-X'], 0.8)
        tt.send(F['ENTER'], 1.0)
        tt.close(3)

    t = dsk_start()
    t.send(F['F10'], 0.4)
    for _ in range(6):
        t.send('\x1b[C', 0.2)                          # ... Panel Manager Options
    t.send(F['ENTER'], 0.6)                            # Options: Configuration >
    t.send(F['ENTER'], 0.6)
    t.send(F['DOWN'], 0.2)                             # Startup...
    t.send(F['ENTER'], 0.8)
    t.send(F['TAB'], 0.3)                              # the "Shutdown options" cluster: Inactivity, Autosave Desktop, blinking, Preserve directory
    t.send(F['DOWN'], 0.3)
    t.send(' ', 0.3)
    t.send(F['DOWN'], 0.3)
    t.send(F['DOWN'], 0.3)
    t.send(' ', 0.3)
    scr = t.text()
    check('[X] Autosave Desktop' in scr and '[X] Preserve directory' in scr, 'Startup dialog: both shutdown options are switched on', scr)
    t.send(F['ENTER'], 0.8)
    t.send(F['DOWN'], 0.3)
    t.send(F['ENTER'], 1.0)                            # into sub
    check(dsk_cwd(t).endswith('sub>'), 'autosave desktop: the panel is in sub before the exit', t.text())
    dsk_quit(t)
    check(os.path.isfile(os.path.join(dd, 'dn.dsk')), 'autosave desktop: dn.dsk is written at Alt-X')
    ini = os.path.join(dd, 'dn.ini')
    check(os.path.isfile(ini) and '[Saved]' in open(ini, errors='replace').read() and 'Size=' in open(ini, errors='replace').read(),
          'autosave desktop: the option itself is saved (the section [Saved] of dn.ini)')
    check(not os.path.isfile(os.path.join(dd, 'dn.cfg')), 'there is no separate dn.cfg any more')
    t = dsk_start()
    check(dsk_cwd(t).endswith('sub>'), 'autosave desktop: the next start restores the panel directory (sub)', t.text())
    dsk_quit(t)


def group_rename(out, d):
    # File -> Group rename (dn#40 part 3b): Ins marks apple.jpg and berry.jpg, the mask img_[C2].[E] from 1 renames them to img_01.jpg
    # and img_02.jpg; cherry.txt, not marked, keeps its name
    w = os.path.join(d, 'grp')
    os.makedirs(w)
    for n in ('apple.jpg', 'berry.jpg', 'cherry.txt'):
        open(os.path.join(w, n), 'w').write(n)
    t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'))
    t.started()
    t.send(F['ESC'], 0.5)
    t.send(F['HOME'], 0.3)
    t.send(F['DOWN'], 0.3)                             # .., apple.jpg, berry.jpg, cherry.txt (sorted by the extension)
    t.send(F['INS'], 0.3)                              # marks apple.jpg, the cursor goes to berry.jpg
    t.send(F['INS'], 0.3)                              # marks berry.jpg
    t.send(F['F10'], 0.5)
    t.send('f', 0.5)                                   # File
    t.send('n', 0.8)                                   # Group re~n~ame...
    scr = t.text()
    check('Group rename' in scr and '[N].[E]' in scr, 'File -> Group rename opens its dialog with the mask [N].[E]', scr)
    t.send('img_[C2].[E]', 0.5)                        # the typed mask replaces the selected [N].[E]
    t.send(F['ENTER'], 1.5)
    names = sorted(os.listdir(w))
    check(names == ['cherry.txt', 'img_01.jpg', 'img_02.jpg'], 'Group rename: img_[C2].[E] renames the marked files: %r' % names, t.text())
    check(t.alive() and 'Fatal' not in t.text(), 'Group rename: DN is alive')
    t.send(F['ALT-X'], 0.8)
    t.send(F['ENTER'], 1.0)
    t.close(3)


def part(out, fn):
    d = install(out)
    try:
        fn(out, d)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main():
    out = os.path.abspath(sys.argv[1])
    parts = [session, background_copy, background_start, desktop, group_rename] + ([utf8] if os.environ.get('DN_OPS_UTF8') == '1' else [])
    side_by_side([lambda fn=fn: part(out, fn) for fn in parts])          # each in a directory of its own, all at once
    print('ALL OK (%d checks)' % count if not fails else '%d of %d checks FAILED' % (fails, count))
    sys.exit(1 if fails else 0)


main()
