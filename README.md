# fox33: A WIP [fox32](https://github.com/fox32-arch) emulator written in c3

> [!NOTE]
> It is recommended to build in a nix environment:
> ```console
> $ nix develop --impure
> ```

## todo:

- [x] Fix that `0x04000000` bug (so painful :()
- [x] Initial Gui
- [ ] Gui overlays
- [ ] I/O stuff: mounting disks, mouse, rtc, etc
- [ ] Interrupts: vblank, moving the mouse
- [ ] Any other things I can think of
- [ ] MMU (maybe, only used by [minita](https://github.com/xrarch/mintia))

## building:

```console
$ c3c build emulator -D <build flag> -O5
```

### build flags:
 - DEBUG -> print almost too many debug logs
 - PERF -> print the time taken to execute 30M instructions (target <= 1 second for 30Mhz)
 - SHUTUP -> silence runtime warnings, mostly unimplemented methods
 - FOXLOG -> print debug logs in the exact same format as the fox32 reference emulator

## usage:

```console
$ ./build/emulator <boot rom> <cpu cycles before shutdown (optional)>
```
