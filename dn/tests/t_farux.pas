{ Far UX mode flag: off by default, the accessor follows the setting. }
{$mode delphi}{$H+}
program t_farux;
uses DnIni, farux, Commands;
{$I dntest.inc}

begin
  Check(FarUxMode = False, 'FarUxMode is off by default');
  Check(FarUxEnabled = False, 'the accessor reports off by default');
  FarUxMode := True;
  Check(FarUxEnabled = True, 'the accessor follows the setting');
  FarUxMode := False;
  Check(FarUxEnabled = False, 'the setting can be switched back');
  Check(FarFastFindChar(kbAltA) = #0, 'no fast-find letter while the mode is off');
  FarUxMode := True;
  Check(FarFastFindChar(kbAltA) = 'A', 'Alt+A gives its letter in Far mode');
  Check(FarFastFindChar(kbAltZ) = 'Z', 'Alt+Z gives its letter in Far mode');
  Check(FarFastFindChar(kbAlt1) = '1', 'Alt+1 gives its character in Far mode');
  Check(FarFastFindChar(kbAltF1) = #0, 'Alt+F1 is not a fast-find letter');
  Check(FarFastFindChar(kbAltEnter) = #0, 'Alt+Enter is not a fast-find letter');
  Check(FarFastFindChar(kbAltSpace) = #0, 'Alt+Space is not a fast-find letter');
  Check(FarFastFindChar(kbF3) = #0, 'a plain F-key is not a fast-find letter');
  Check(FarCtrlGrayKey(kbCtrlGPlus, 0) = '+', 'the BIOS Ctrl+Gray+ is a Ctrl gray key');
  Check(FarCtrlGrayKey(kbCtrlGMinus, 0) = '-', 'the BIOS Ctrl+Gray- is a Ctrl gray key');
  Check(FarCtrlGrayKey(kbCtrlGAst, 0) = '*', 'the BIOS Ctrl+Gray* is a Ctrl gray key');
  Check(FarCtrlGrayKey($04002B, $6B) = '+', 'Ctrl and + of the numpad (win32 input) is Ctrl+Gray+');
  Check(FarCtrlGrayKey($04002D, 0) = '-', 'Ctrl and - from a terminal that gives no key is Ctrl+Gray-');
  Check(FarCtrlGrayKey($04002A, $6A) = '*', 'Ctrl and * of the numpad is Ctrl+Gray*');
  Check(FarCtrlGrayKey($04002D, $BD) = #0, 'Ctrl and - of the main keyboard is not a gray key');
  Check(FarCtrlGrayKey($03002B, $6B) = #0, 'Shift with + of the numpad is not a Ctrl gray key');
  Check(FarCtrlGrayKey($0C002B, $6B) = #0, 'Ctrl+Alt with + is not a Ctrl gray key');
  Check(FarCtrlGrayKey(kbCtrlA, 0) = #0, 'Ctrl+A is not a gray key');
  Check(FarAltGrayKey(kbAltGPlus, 0) = kbAltGPlus, 'the BIOS Alt+Gray+ keeps its key code');
  Check(FarAltGrayKey($08002B, $6B) = kbAltGPlus, 'terminal Alt+numpad + maps to Alt+Gray+');
  Check(FarAltGrayKey($08002D, $6D) = kbAltGMinus, 'terminal Alt+numpad - maps to Alt+Gray-');
  Check(FarAltGrayKey(kbAltMinus, $6D) = kbAltGMinus, 'Alt and - of the numpad, as tv/ names it (kbAltMinus), is Alt+Gray-');
  Check(FarAltGrayKey(kbAltMinus, $BD) = 0, 'kbAltMinus of the main keyboard stays Alt+-');
  Check(FarAltGrayKey(kbAltMinus, 0) = 0, 'kbAltMinus without a VirtualKey stays Alt+-');
  Check(FarAltGrayKey($08002D, $BD) = 0, 'Alt and - on the main keyboard is not Alt+Gray-');
  Check(FarAltGrayKey($08002D, 0) = 0, 'an unknown terminal key is not guessed to be a gray key');
  Check(FarAltGrayKey($0C002B, $6B) = 0, 'Ctrl+Alt+numpad + is not Alt+Gray+');
  Check(FarAltGrayKey($0B002B, $6B) = 0, 'Shift+Alt+numpad + is not Alt+Gray+');
  FarUxMode := False;
  Check(FarCtrlGrayKey(kbCtrlGPlus, 0) = #0, 'no Ctrl gray key while the mode is off');
  Check(FarCtrlGrayKey($04002B, $6B) = #0, 'no terminal Ctrl gray key while the mode is off');
  Check(FarAltGrayKey(kbAltGPlus, 0) = 0, 'no Alt gray key while the mode is off');
  Check(FarAltGrayKey($08002B, $6B) = 0, 'no terminal Alt gray key while the mode is off');
  Finish;
end.
