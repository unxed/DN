# I2b: дизайн проводки Alt-поиска в панель (писать код, когда дерево зелёное)

## Точка вставки (реализовано в I2b, коммит ниже)

`TFilePanel.HandleEvent`, ветка `evKeyDown`, перед if-цепочкой триггеров
(`filepanel.pas:1982`), после блока делегирования в комстроку (`:1874-1895`,
он Alt+буквы не ест — они падают сквозь него к `:1942`):

```pascal
if FarUxEnabled and (Event.What = evKeyDown) and not QuickSearch then
  begin
  C := FarFastFindChar(DNKeyCode(Event)); { farux.pas, I2a готов и покрыт }
  if C <> #0 then
    begin
    InitQuickSearch(Self);
    QSLastSuccessPos := LastSuccessPos;
    DoQuickSearch(Ord(C)); { как существующий ввод маски }
    if not MaskSearch(0) then DoQuickSearch(kbBack);
    DrawView; CE; Exit;
    end;
  end;
```

Почему здесь: раньше `CommandHandle` (`:2148` через `GotoKb`) и раньше
всплытия `Alt` в меню (`apploop.pas:237` → `StatusLine.HandleEvent`).
За флагом поведение по умолчанию не меняется ни на байт.
`Alt+1..0` пресетов (`panelwin.pas:892`, только при `fmoAltDifference`)
в Far-режиме уступают поиску — как в Far; вне режима всё по-старому.

## Назад по совпадениям (`Ctrl+Shift+Enter`)

Существует `kbCtrlShiftEnter=$071C00` (`commands.pas:203`), вперёд уже есть
(`MaskSearch(1)` по `kbCtrlEnter`, `filepanel.pas:1953`). Назад — новый малый
цикл рядом с `MaskSearch` (`filepanel.pas:1819`, тот же `InMask` из
`fileutil.pas:719` + `QSMaskPlusStar`): идти от `CurPos-1` вниз с wrap.
`Shift+Enter` (`kbShiftEnter=$031C0D`) в поиске не трогаем — у него своё
значение вне поиска.

## Маска и отображение

`*?` работают через существующий `InMask` (как сейчас). Показ маски —
существующий `InfoView` (`filepanel.pas:1124-1130`, `QuickSearchString`).
Выход — существующий `Esc` (`:1946`). Вставка из clipboard в набор
(`Ctrl+V/Shift+Ins` продолжают поиск — так в Far): проверить при
реализации, отдельным подпунктом; если требует разводки ввода — вынести
в I2c, не раздувать I2b.

## Тесты I2b (писать вместе с кодом, запускать на зелёном дереве)

- unit: уже есть (I2a, 12 проверок) + проверки backward-цикла, если его
  вынести в чистую функцию (матчинг по списку имён без UI).
- pty в `tools/dn-linux-ops.py`: `Alt+a` (ESC-префикс терминала) → курсор на
  файле, меню не открылось; кириллица `Alt+б`; `Ctrl+Enter`/`Ctrl+Shift+Enter`
  вперёд/назад; `Esc` выход; вне режима `Alt+e` открывает меню как раньше
  (регрессия по `ops.py:204-210`).
