# Supported Escape Sequences

> Undocumented escape sequences with the same introducer (e.g.``ESC [``) are ignored.

## SS2
**Introducer:** ``ESC N``

_completely ignored_

## SS3
**Introducer:** ``ESC O``

- ``A`` -> ``up``
- ``B`` -> ``down``
- ``C`` -> ``right``
- ``D`` -> ``left``
- ``E`` -> ``keypad_begin``
- ``F`` -> ``end``
- ``H`` -> ``home``
- ``P`` -> ``f1``
- ``Q`` -> ``f2``
- ``R`` -> ``f3``
- ``S`` -> ``f4``

## DCS
**Introducer:** ``ESC P``

_completely ignored_

## CSI
**Introducer:** ``ESC [``

### Legacy Keys
- ``2...~`` -> key event of ``insert``
- ``3...~`` -> key event of ``delete``
- ``5...~`` -> key event of ``page_up``
- ``6...~`` -> key event op ``page_down``
- ``...A`` -> key event of ``up``
- ``...B`` -> key event of ``down``
- ``...C`` -> key event of ``right``
- ``...D`` -> key event of ``left``
- ``...E`` -> key event of ``keypad_begin``
- ``7...~``; ``...H`` -> key event of ``home``
- ``8...~``; ``...F`` -> key event of ``end``
- ``11...~``; ``...P`` -> key event of ``f1``
- ``12...~``; ``...Q`` -> key event of ``f2``
- ``13...~``; ``...R`` -> key event of ``f3``
- ``14...~``; ``...S`` -> key event of ``f4``
- ``15...~`` -> key event of ``f5``
- ``17...~`` -> key event of ``f6``
- ``18...~`` -> key event of ``f7``
- ``19...~`` -> key event of ``f8``
- ``20...~`` -> key event of ``f9``
- ``21...~`` -> key event of ``f10``
- ``23...~`` -> key event of ``f11``
- ``24...~`` -> key event of ``f12``
- ``57427...~`` -> key event of ``keypad_begin``

### Bracketed Paste
- ``200...~`` -> ``paste_start``
- ``201...~`` -> ``paste_end``

### Focus
- ``...I`` -> focus ``in``
- ``...O`` -> focus ``out``

### Mouse
- ``M...`` (X10)
- ``<...M``; ``<...m`` (SGR)
- not supported: ``...M``; ``...m`` (URXVT)

### [Color scheme](https://github.com/contour-terminal/contour/blob/master/docs/vt-extensions/color-palette-update-notifications.md)
- ``...n``
    - ``?...n``
      - ``?997;1n`` -> ``dark``
      - ``?997;2n`` -> ``light``

### [In-Band Resize Events](https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83)
- ``...t``

### [Kitty Keyboard Protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
- ``...u``
  - ``?...u`` -> capability response ignored 
  - ``...u`` -> key event

### [Kitty Multi Cursor](https://sw.kovidgoyal.net/kitty/multiple-cursors-protocol)
- ``>... q``
  - ``>100... q`` -> ``multi cursors report``
  - ``>101... q`` -> ``multi cursor color report``

## OSC
**Introducer:** ``ESC ]``

- ``4...`` -> ``color_report``
- ``10...`` -> foreground ``color_report``
- ``11...`` -> background ``color_report``
- ``12...`` -> cursor ``color_report``
- ``52...`` -> ``paste``

## SOS
**Introducer:** ``ESC X``

_completely ignored_

## PM
**Introducer:** `` ESC ^``

_completely ignored_

## APC
**Introducer:** ``ESC _``

_completely ignored_
