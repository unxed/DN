# Far UX mode + mini-сборка: план (исследование 2026-10-13, RUP итерация I0)

Статус: исследовательская итерация. Кода не меняет, только план.
Правило DN-3.0 соблюдено: Far-режим — разрешённое исключение, строго за флагом,
по умолчанию выключен (`docs/DN-3.0.md`, таблица исключений).

## 0. Что выяснено

### 0.1 DN: где живут клавиши (подробно — отчёт сабагента, сверено с деревом)

| Место | Роль |
|---|---|
| `dn/src/commands.pas:61-692` | коды `kb*` (`kbF1..kbF12`, `kbAlt*`, `kbCtrl*`), `pqsAlt/pqsCtrl/pqsCaps` (`:910-913`), команды `cm*` |
| `dn/src/apploop.pas:97-269` | глобальные перехваты до панелей; `Alt` всплывает в меню через `StatusLine.HandleEvent` (`:237-248`) |
| `dn/src/filepanel.pas:1760-2214` | `TFilePanel.HandleEvent`; quick search `:1944-2052`, триггер `:1982-1993` |
| `dn/src/panelroot.pas:838-3040` | `TFilePanelRoot.CommandHandle`; `Alt`-таблица `:1988-2307` |
| `dn/src/panelwin.pas:871-1134` | `TDoubleWindow`; `Alt-1..0`, `Alt-Left/Right`, `Ctrl-Left/Right` |
| `dn/src/cmdline.pas:389-866` | комстрока; конфликт за `kbCtrlS` (`:~750`) |
| `dn/src/menus.pas:864-1151,1585-1909` | меню/статусбар, Alt-хоткеи `GetAltChar` |
| `dn/src/dnutil.pas:119,1817-2940` | верхний диспетчер `cm*`, `InitMenuBar/InitStatusLine` |
| `dn/src/fileutil.pas:1236-1300` + `panelroot.pas:196-199` | `DoQuickSearch`, глобалы `QuickSearch/QSMask/QSPanel` |

Сейчас: quick search включается double-Alt / double-Ctrl / `Ctrl-S` при пустой
комстроке (`filepanel.pas:1982-1993`, настройка `Quick` в `dlgFMSetup`,
`dn/src/resource/english/dn.dnr:3426-3432`). Образец pty-проверки —
`tools/dn-linux-ops.py:211-214` (`Ctrl-S` + кириллица → `Поиск:`).
`Alt+буквы` в фокусе панели частично съедаются панелью/статусбаром
(`Alt-B/C/S/L/R/X`, `Alt-1..0`, `Alt-Enter/Ins/Del/Up/Down`), остальные
всплывают в меню (`menus.pas`, Alt-кириллица покрыта `tools/dn-linux-ops.py:204-210`).
Вывод: Far-режиму нужен явный перехват в `TFilePanel.HandleEvent` до
`CommandHandle`/всплытия.

Точка флага (без ломки бинарного `[Saved]`): новая `Boolean`-переменная в конце
блока `{FilePanels}` (`dn/src/dnini.pas:166-168`, append перед `iniparamblock_END`
`:249-250`, требование коммента `:69-72`), регистрация
`RegisterVar(CSFilePanels,'FarUxMode',ikBool,...)` в `dn/src/iniengine.pas:344-348`,
чекбокс в `dlgFMSetup` трёх `dn.dnr` + `DoFMSetup` (`dn/src/setups.pas:375-401`).
Бит в `TFMSetup.Options` не использовать (размер в `cfgFMSetup=56`,
`dn/src/dnutil.pas:196` через `dn/src/cfgstate.pas` — ломает совместимость десктопа).

Тесты-образцы: unit `tools/dn-test.sh` + `dn/tests/t_*.pas` (`dntest.inc`);
pty `tools/dn-linux-tour.py:13-29` (матрица `SCEN`), `tools/dn-linux-ops.py`.

### 0.2 Far: эталон (приоритет far2l)

Первичный источник — help-исходники (читаются напрямую, CHM для этого не обязателен):
far2l `far2l/bootstrap/scripts/FarEng.hlf.m4` (5328 строк, форк Far v2 — эталон),
сверка Far3 `far/FarEng.hlf.m4` (6901 строка, разделы `@KeyRef/@PanelCmd/@FastFind/
@CmdLineCmd/@FuncCmd/@SelectFiles/@History*`). Копии для сверки — только в
`/tmp/opencode/`, в репо не класть.

Быстрый поиск (`@FastFind`, в обоих help совпадает по смыслу): удерживать `Alt`
(или `Alt+Shift`) и набирать начало имени; `Ctrl+Enter` — следующий совпадающий,
`Ctrl+Shift+Enter` — предыдущий (в этом режиме `Ctrl+Enter` не вставляет имя!);
маски `*?` прямо в наборе; вставка из clipboard продолжает поиск; есть
транслитерация набираемого. `Shift+Enter` к fast find не относится — это семантика
историй (выбор без перемещения в конец / новое окно).

Ключевые расхождения (брать far2l): `Ctrl+,` компоновка панелей — только far2l;
`Ctrl+Alt+D/L/M/N`, `Ctrl+C` копировать файлы, `Ctrl+`` home, `Ctrl+Alt+\`
mount-point — только far2l; `Alt+Gray*` (инверсия только файлов) — только Far3,
вычеркнуть; `Ctrl+Alt+Ins` — в far2l полные имена, в Far3 реальные/UNC;
`Ctrl+\` — `/` в far2l; истории в far2l шире (`Ctrl+T` 3 вида, `Ctrl+F10`
quick-jump). Полная таблица — в отчёте сабагента (источники выше).
Новых функций не добавляем: маппим только то, что уже есть в DN.

Лицензионная граница: из Far/far2l (GPL) кода не берём, только таблицы поведения
из документации; реализация — свой код в `dn/src`.

### 0.3 Far Encyclopedia CHM: как извлекать (вопрос из задачи закрыт)

Исходники CHM — `FarGroup/FarManager` `enc/` (`enc_eng/pluginse.hhp` →
`FarEncyclopedia.en.chm`, `enc_rus/pluginsr.hhp` → `FarEncyclopedia.ru.chm`,
контент `enc_{eng,rus}/meta/**`, сборка `enc/tools/tool.make_*.bat` + `.py`,
требует Windows `hhc.exe`). В git исходники уже UTF-8 (rus с BOM); предупреждение
про однобайтную кириллицу относится к скомпилированным legacy-CHM: русский HTML
внутри — `windows-1251`.

```bash
mkdir -p /tmp/opencode/chm && cd /tmp/opencode/chm
7z x FarEncyclopedia.ru.chm -oenc_ru   # 7z есть: /usr/bin/7z 23.01
file enc_ru/*.html | head              # проверить каждый <meta charset>
iconv -f WINDOWS-1251 -t UTF-8 enc_ru/<page>.html | head -20
for f in enc_ru/*.html; do iconv -f WINDOWS-1251 -t UTF-8 "$f" > "$f.utf8"; done
# eng legacy-CHM: cp1252 или utf-8 — смотреть <meta> каждого файла
```

Запасной источник по Plugin API — `https://documentation.help/Far-Manager/`
(та же энциклопедия; панельных клавиш пользователя там нет — клавиши брать
только из `.hlf.m4` п. 0.2).

### 0.4 Mini: замеры (подробно — отчёт сабагента)

| Метрика | DN `out/linux64/dn` | mc `/usr/bin/mc` |
|---|---|---|
| `ls -l` | 2 879 584 (2.8M) | 1 140 880 (1.1M) |
| `size text/data/bss` | 2342568 / 529744 / 1158464 | 1089717 / 39988 / 241464 |
| `file`/`ldd` | ELF64 static, stripped, секций 8, `strings` 17991 | ELF64 PIE dynamic, stripped; +slang 2.1M + glib 1.3M — реальный футпринт mc ~5–8M с `.so` |

Сборка сейчас: `DN_FPC_COMMON="-Mdelphi -Sh- -Rintel -Se300"` (`dn/build.env`) —
нет `-O*` (дефолт FPC), нет `-XX -CX -Xs`; `DN_EXTRA` по умолчанию только
`-dDNUTF8` (`tools/build.sh`, `tools/dn-env.sh`). Снять ~1.7M до файла mc надо
комбинацией оптимизаций и вырезаний.

Пожиратели `.o` (топ): `regall` 244K (тянет extras), `calcwin` 146K,
`uucode` 136K, `archiver+arcview+archdet` ~265K + 26×`fmt*` ~619K суммарно,
extras-кластер (db/phones/arvid/decoder/evaluator/printman/tetris/calendar/
idlers/gadgets/...) ~900K–1M. Арифметика: extras ~900K + редкие `fmt*` ~300K
после линка и `-Os -XX` реалистично −0.8…−1.3M → ~1.5–2.0M static.

## 1. RUP-план: Far UX mode (каждая итерация — атомарный коммит в main + тесты)

- I1 Флаг. `FarUxMode: Boolean=False` в `dnini.pas` (append в конце блока —
  требование совместимости плагинов) + `RegisterVar(...'FarUxMode',ikBool...)`
  в `iniengine.pas` + accessor `FarUxEnabled` в новом MIT-юните `farux.pas`.
  Поведение не меняется; настройка пока только ini-only (прецедент:
  `QuickRenameInDialog`/`UpperCaseSorting` тоже без чекбокса — `dlgFMSetup`
  правит запись `Startup.FMSetup`, а не глобалы `dnini`, привязка чекбокса
  требует отдельной разводки и уезжает в I5). Тест: новый
  `dn/tests/t_farux.pas` (дефолт False, accessor следует настройке).
- I2 Быстрый поиск Alt+буквы. **I2a (готово): чистый классификатор
  `FarFastFindChar` в `farux.pas` + unit-тесты (12 проверок).** I2b (ждёт
  зелёного дерева): перехват в `TFilePanel.HandleEvent` до меню
  (за флагом): удержание `Alt`/`Alt+Shift` + набор, `Ctrl+Enter`/
  `Ctrl+Shift+Enter` следующий/предыдущий, `*?` в наборе, показ маски в
  `InfoView`. Старый `Ctrl-S`/double-мод остаётся. Тесты: unit на чистую
  функцию матчинга + pty `tour-far-*` в `tools/dn-linux-ops.py`
  (голые/Alt+буквы не открывают меню, кириллица тоже).
- I3 Таблица панелей (только существующие функции DN): `Tab/Ctrl-U/R/L/Q/T/O/P`,
  `Ctrl+F1/F2`, `Ctrl+стрелки`, `Gray+/-/*` + `Ctrl/Alt/Shift` варианты по матрице
  far2l минус `Alt+Gray*`, `Ctrl+M`, `Ctrl+H/N`, `Ctrl+F3..F12`, вставки имён
  `Ctrl+Ins/Shift+Ins/Alt+Shift+Ins/Ctrl+Alt+Ins` по far2l-столбцу, `Ctrl+\`.
  Тесты: pty-матрица по `dn-linux-tour.py:SCEN`.
- I4 Сервисные F и истории за флагом: `F3/F4/F5/F6/F7/F8(+Shift)`, `Alt+F1/F2/F7/
  F8/F10/F11/F12`, `Alt+Del`, `Shift+F4/F5/F6`, `Enter/Shift+Enter` в историях
  (без перемещения), `Ctrl+Enter` имени в комстроку. Тесты: pty `check()` в ops.
- I5 Финиш: `F1/F2/F9/F10/F11`, чекбокс `dlgFMSetup` (3 языка + разводка
  `setups.pas`), доки (`dn/README`, help), accept `dn-linux-accept.py`.
  Критерий: функции DN доступны как в Far там, где они есть; нового функционала нет.

## 2. RUP-план: mini (параллельная ветка, существующий код не трогать)

- M0 Механика + замеры без резки: `DN_MINI=1 tools/build.sh linux64 out/mini` →
  `-dDN_MINI`, суффикс объектов `-mini` в `dn-env.sh` (рядом с `-utf8`), замеры
  `DN_EXTRA="-Os -XX -CX -Xs"` (`-Os` vs `-O2`), CI-job замера `ls -l/size`
  + `tour` (гейт сначала наблюдательный: `mini ≤ mc+30%`).
- M1 Вырезание extras за `{$IFDEF DN_MINI}` (первый эшелон): `calcwin+evaluator+
  calcline+cellscol`, `uucode+decoder`, `arvid+arvidavt+arvidtdr`, `tetris`,
  `phones`, `calendar`, `printman`, `dbview+dbwatch`, `pktview`, `idlers`,
  `os2sess`. Точки: `dn.pas`/`dnutil.pas` uses, `archdet/arcview/regall`,
  заглушки `cm* → MsgBox('Not in mini')`, скрытие пунктов меню. Полные сборки —
  ноль диффа поведения.
- M2 Редкие `fmt*` (~15 шт: `fmtarc/fmtbsa/fmtbs2/fmthyp/fmtlim/fmthpk/fmtzxz/
  fmtqrk/fmtufa/fmtis3/fmtsqz/fmthap/fmtchz/fmtuc2/fmtain`): оставить базовые
  `zip/tar/tgz/bz2/xz/7z/rar/cab/lha/zoo` (как покрытие mc через `tarfs/extfs.d`).
- M3 Добор в пределах лимита (как-в-mc ветки): ассоциации `mc.ext`-стиля поверх
  `filetype.pas`, фоновые операции поверх `filecopy.pas/LongCopy` — только если
  лимит держится.

Конечная цель: набор функций mc размером ≤ бинарника mc + выключенная по
умолчанию галка «Far UX mode» в настройках (I1).
