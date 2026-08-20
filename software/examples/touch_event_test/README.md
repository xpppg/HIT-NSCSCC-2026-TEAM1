# Touch event test

This small `evtest` replacement prints Goodix multitouch coordinates and
tracking events from a Linux evdev node.

```sh
make
./touch_event_test /dev/input/event0
```

If the Goodix device is assigned another event number, pass that path as the
first argument.  `TRACKING_ID = -1` marks finger release.
