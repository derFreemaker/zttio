# zttio

TTY interface with main focus on making it easy to get input
from the terminal like key presses and mouse interactions.

Inspired by the tty handling
from [libvaxis](https://github.com/rockorager/libvaxis/tree/11f53c701ae6b5633582d957d57e1683de7b568a).

### [Project Overview](https://www.notion.so/2c97f91634e5800e8c9cfb75af5e8474?v=2c97f91634e581d7898f000c9df3a935&source=copy_link)

### [Supported Escape Sequences](escape_sequences.md)

### [Supported Capabilities Detection](capabilities_detection.md)

## Features

- RGB
- [Hyperlinks](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda) (OSC 8)
- Bracketed Paste
- [Kitty Keyboard Protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
- [Fancy underlines](https://sw.kovidgoyal.net/kitty/underlines/) (undercurl, etc)
- Mouse Shapes (OSC 22)
- Progress (OSC 9;4)
- System Clipboard (OSC 52)
- System Notifications (OSC 9; OSC 777)
- [Unicode Core](https://github.com/contour-terminal/terminal-unicode-core) (Mode 2027)
- Color Mode Updates (Mode 2031)
- [In-Band Resize Events](https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83) (Mode 2048)
- Synchronized Output (Mode 2026)
- [Scaled Text](https://sw.kovidgoyal.net/kitty/text-sizing-protocol) (OSC 66)
- [Explicit Width](https://sw.kovidgoyal.net/kitty/text-sizing-protocol) (OSC 66)
- [Kitty Multi Cursor](https://sw.kovidgoyal.net/kitty/multiple-cursors-protocol)

[//]: # (- Images &#40;kitty, sixel, ...&#41;)

## Dependencies

- [zigwin32](https://github.com/marlersoft/zigwin32)
- [uucode](https://github.com/jacobsandlund/uucode)

[//]: # (- [zigimg]&#40;https://github.com/zigimg/zigimg&#41;)
