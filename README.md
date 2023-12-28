# ld_preload_tutorial
Overview of how to use LD_PRELOAD using ZLIB wrapper for ZSTD compression

Current version works for ZSTD v1.3.4 and most versions of Tabix/bgzip (tested with 1.19).

## How it works

Example function: `inflate(compressed_stream)`
In the ZLIB shared library:
```
int inflate(compressed_stream) {
    //do normal ZLIB decompression
}
```

In the ZSTD ZLIBWrapper (compiled into the target application, e.g. Samtools):

```
int z_inflate(z_compressed_stream) {
    //do ZSTD decompression
}
```

In the LD_PRELOAD library*:
```
int inflate(z_compressed_stream) {
    return z_inflate(z_compressed_stream);
}
```

Then run your *unmodified* command (e.g. `bgzip`):

`LD_PRELOAD=/path/to/zstd_preload.so bgzip tabular_data.tsv`

*also includes the code in the ZSTD  ZLIBWrapper

## Pitfalls

### Function name collisions

* FB/Meta provided ZSTD ZLIB wrapper renames API with a “z_” prefix, e.g. “z_inflate” vs. “inflate”
* I added another layer of wrapper (hook) functions with exact ZLIB names, which call the ZSTD versions

### Recursive calls to ZLIB functions within ZSTD functions

* ZSTD functions may call ZLIB functions depending on the characteristics of a compressed stream (at least during decompression)
* I now keep a reference to the original ZLIB function(s) around in the hooked wrapper and swap them depending on context:

Example function redux: `inflate(compressed_stream)`
In the ZSTD ZLIBWrapper:
```
int z_inflate(z_compressed_stream) {
    //do ZSTD decompression,
    //but also ZLIB decompression
    //if input stream has ZLIB compressed elements
}
```

In the (new) LD_PRELOAD library:
```
typedef int (*orig_inflate)(z_compressed_stream);
static orig_inflate zlib_inflate;
int inflate(z_compressed_stream) {
    if(!zlib_inflate) {
         zlib_inflate = dlsym(RTLD_NEXT,"inflate");
         int r = z_inflate(z_compressed_stream);
         zlib_inflate = NULL;
         return r;
    }
    return zlib_inflate(z_compressed_stream);
}
```
