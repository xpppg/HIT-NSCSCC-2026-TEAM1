# LA32R con2fbmap

用于在运行时修改 Linux 虚拟终端与 framebuffer 的映射关系。

```sh
con2fbmap <VT编号>                 # 查询
con2fbmap <VT编号> <framebuffer号> # 设置
```

例如将 `tty1` 映射到 LCD（`fb0`）：

```sh
con2fbmap 1 0
chvt 1
```

将 `tty1` 映射到 VGA（`fb1`）：

```sh
con2fbmap 1 1
chvt 1
```

`VT编号` 从 1 开始，`framebuffer号` 从 0 开始。映射只影响 fbcon 文本虚拟
终端，不会迁移直接操作 `/dev/fb0` 或 `/dev/fb1` 的 LVGL 程序。
