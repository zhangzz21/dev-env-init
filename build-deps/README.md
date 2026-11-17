# build-deps

Development packages needed to build Git from source in `init.sh`. The nodes
ship only the runtime libraries, and we are not root, so these `.deb` files are
unpacked into `$WORK_DIR/.bin/.sysroot` and the build is pointed at that.

Only headers and static archives are used from them:

| package                  | used for                                  |
| ------------------------ | ----------------------------------------- |
| `zlib1g-dev`             | `zlib.h` + `libz.a` (linked statically)   |
| `libexpat1-dev`          | `expat.h` + `libexpat.a` (statically)     |
| `libcurl4-openssl-dev`   | `curl/*.h` only                           |

libcurl itself is linked dynamically against the node's own `libcurl.so.4`
(vendoring it would mean vendoring its whole dependency chain), so the headers
here are deliberately from an older Ubuntu than the nodes run: building against
older headers and linking a newer `libcurl.so.4` is the safe direction. OpenSSL
is not needed at all — libcurl does the TLS and Git is built with `NO_OPENSSL`.

Current files are Ubuntu 20.04 (focal) amd64, from the Ubuntu archive:

```
http://archive.ubuntu.com/ubuntu/pool/main/z/zlib/zlib1g-dev_1.2.11.dfsg-2ubuntu1.5_amd64.deb
http://archive.ubuntu.com/ubuntu/pool/main/e/expat/libexpat1-dev_2.2.9-1ubuntu0.8_amd64.deb
http://archive.ubuntu.com/ubuntu/pool/main/c/curl/libcurl4-openssl-dev_7.68.0-1ubuntu2.25_amd64.deb
```

These are the same files https://pkgs.org/ links to for those packages. To
refresh or switch distro, drop the new `.deb` files in here — `init.sh` unpacks
whatever it finds.
