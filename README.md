# Fox32 emulator but not done yet

## WIP emulator for [Fox32](https://github.com/fox32-arch)

> [!NOTE]
> It is recommended to build in a nix environment:
> ```console
> $ nix develop --impure
> ```

### todo:

- [x] Initial Gui
- [ ] Gui overlays
- [ ] Interrupts
- [ ] Any other things I can think of
- [ ] MMU (maybe, only used by [minita](https://github.com/xrarch/mintia))

### building:

```console
$ c3c build emulator <-D build flag> -O5
```

#### build flags:
 - DEBUG -> print almost too many debug logs
 - PERF -> print the time taken to execute 30M instructions (target <= 1 second for 30Mhz)
 - SHUTUP -> silence runtime warnings, mostly unimplemented methods
 - FOXLOG -> print debug logs in the exact same format as the fox32 reference emulator

### usage:

```console
$ ./build/emulator <input file> <cpu cycles before shutdown (optional)>
```
