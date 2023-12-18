# customerrors
This is a sketch for a library that implements custom errors with payloads for zig (without special language support).
This is an exploration in what is possible in userspace without changing the language.

## run
```bash
git clone https://github.com/SimonLSchlee/customerrors-sketch.git
cd customerrors-sketch
zig build run
```

To "disable" customerrors use `zig build run -Dcustomerrors=false`.
The example fails with different errors randomly you can pass the rng seed with `zig build run -- <seed>`

