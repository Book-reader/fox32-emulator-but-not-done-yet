# fox33: A WIP [fox32](https://github.com/fox32-arch) emulator written in c3

> [!NOTE]
> It is recommended to build in a nix environment:
> ```console
> $ nix develop --impure
> ```

> [!WARNING]
> Don't expect the code to be of great quality for now.
> I'll clean it up later

## todo:

- [x] Fix that `0x04000000` bug (so painful :()
- [x] Run fox32rom successfully
- [x] Initial Gui & see fox32rom framebuffer
- [x] Implement Gui overlays
- [ ] I/O stuff: mounting disks, mouse, rtc, etc
- [x] Interrupts/Exceptions
- [ ] Get fox32rom functioning completely
- [ ] Get fox32os functioning completely
- [ ] Implement all instructions fully
- [ ] Any other things I can think of

## building:

```console
$ c3c build -D <build flag> -O5
```

### build flags:
 - DEBUG -> print almost too many debug logs
 - PERF -> print the time taken to execute 30M instructions (target <= 1 second for 30Mhz)
 - SHUTUP -> silence runtime warnings, mostly unimplemented methods
 - FOXLOG -> print debug logs in the exact same format as the fox32 reference emulator

## usage:

```console
$ ./build/fox33 <boot rom> <cpu cycles before shutdown (optional)>
```
