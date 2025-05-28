# Fox32 emulator but not done yet

## emulator for [Fox32](https://github.com/fox32-arch) except it doesn't work :O

> [!NOTE]
> Program doesn't compile?
> try this:
> ```console
> $ nix develop --impure
> ```

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
