# Supported Capabilities Detection

We save the screen and cursor before detection and restore after,
overwriting the saved screen and cursor state.

Should be fine, since detection should be done before anything else.

## [DECRQM](https://vt100.net/docs/vt510-rm/DECRQM.html)
**Response Format:** [DECRPM](https://vt100.net/docs/vt510-rm/DECRPM.html)
- **Ansi:** CSI - ``{Pa};{Ps}$y``
- **DEC:** CSI - ``?{Pd};{Ps}$y``

**Pa:**
[Table 5–6](https://vt100.net/docs/vt510-rm/DECRPM.html#T5-6) lists the values for Pa.

**Pd:**
indicates which DEC mode the terminal is reporting on. [Table 5–6](https://vt100.net/docs/vt510-rm/DECRPM.html#T5-6) lists the values for Pd.

**Ps:**
indicates the setting of the mode. The Ps values are the same for the ANSI and DEC versions.

| Ps | Mode Setting        |
|----|---------------------|
| 0  | Mode not recognized |
| 1  | Set                 |
| 2  | Reset               |
| 3  | Permanently set     |
| 4  | Permanently reset   |

### Focus Events
**Pd:** ``1004``

**Query:** CSI - ``?1004$p``

### SGR Pixels
**Pd:** ``1016``

**Query:** CSI - ``?1016$p``

### [Synchronized Output](https://github.com/contour-terminal/vt-extensions/blob/master/synchronized-output.md)
**Pd:** ``2026``

**Query:** CSI - ``?2026$p``

### [Unicode Core](https://github.com/contour-terminal/terminal-unicode-core)
**Pd:** ``2027``

**Query:** CSI - ``?2027$p``

### [Color scheme Updates](https://github.com/contour-terminal/contour/blob/master/docs/vt-extensions/color-palette-update-notifications.md)
**Pd:** ``2031``

**Query:** CSI - ``?2031$p``

### [In-Band Window Resize Notifications](https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83)
**Pd:** ``2048``

**Query:** CSI - ``?2048$p``

## [Explicit Width](https://sw.kovidgoyal.net/kitty/text-sizing-protocol)
**Query:** OSC - ``66;w=1; `` - ST followed by [CPR](https://vt100.net/docs/vt510-rm/CPR.html)

**Supported Response:** [CPR](https://vt100.net/docs/vt510-rm/CPR.html) Response with ``column == 2``

## [Scaled Text](https://sw.kovidgoyal.net/kitty/text-sizing-protocol)
**Query:** OSC - ``66;s=2; `` - ST followed by [CPR](https://vt100.net/docs/vt510-rm/CPR.html)

**Supported Response:** [CPR](https://vt100.net/docs/vt510-rm/CPR.html) Response with ``column == 3``

## [Kitty Keyboard Protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol)
**Query:** CSI - ``?u``

**Supported Response:** CSI - ``? {flags} u``

## [Kitty Multi Cursor](https://sw.kovidgoyal.net/kitty/multiple-cursors-protocol)
**Query:** CSI - ``> q``

**Supported Response:** CSI - ``> {supported cursor shape};{supported cursor shape};... q``

## [Kitty Graphics Protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol)
**Query:** APC - ``Gi=1,s=1,v=1,a=q,t=d,f=24;AAAA`` - ST

**Supported Response:** APC - ``Gi=1;{error message or OK}`` - ST

## RGB
**Query:** environment variable lookup ``COLORTERM``

**Supported:** ``truecolor``; ``24bit``
