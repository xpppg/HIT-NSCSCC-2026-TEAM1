# LCD row-address wrap test

The generated 480x864 RGB565 image uses distinctive colors for the possible
wrap boundaries:

- rows 800..839: green
- rows 840..853: magenta
- rows 854..863: yellow

If these colors appear at the physical top of the panel, the controller's
address counter wrapped before logical row 864.

Regenerate the files with:

```sh
python3 make_lcd_row_test.py
```
