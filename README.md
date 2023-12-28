# ld_preload_tutorial
Overview of how to use LD_PRELOAD using ZLIB wrapper for ZSTD compression

Current version works for ZSTD v1.3.4 and most versions of Tabix/bgzip (tested with 1.19).

Warning: this is very prototype code, meant for example purposes only, use at your own risk!

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
*also includes the code in the ZSTD  ZLIBWrapper

Then run your *unmodified* command(s) (e.g. `bgzip` for block-gzipping and `tabix` for indexing/querying):

```
export LD_PRELOAD=/path/to/zstd_preload.so
bgzip tabular_data.tsv
tabix -s<seq_col> -b<start_col> -e<end_col> tabular_data.tsv.gz
tabix tabular_data.tsv.gz chromosome:start-end
```

you can also use it inline with a single command:
`LD_PRELOAD=/path/to/zstd_preload.so bgzip tabular_data.tsv`

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

### [htslib specific] Tabix checks for exact format by reading ahead

In later versions (post 1.2) of htslib, Tabix's `decompress_peek(_gz)` function opens the bgzipped file just to determine file format.
This fails under the `LD_PRELOAD=zstd_preload.so` scheme for not entirely clear reasons (probably header vs. payload differentiation).
Though one problem appears to be `decompress_peek` harcodes the header type to be gzip (31) rather than bgzip (-15) in its call to `inflateInit2`.

My workaround here is to flag when the gzip header type is passed in (31) as a signal that `decompress_peek` is being called just to determine file type.
I then hard code a stub BED file formatted string that most recent versions of Tabix will accept as a BED file.
In addition, I adjust the stream buffer sizes to signal a successful stream read/decompression while not actually doing one:


```
    typedef int (*orig_inflateInit2)(z_streamp strm, int  windowBits,
                                    const char *version, int stream_size);
    static orig_inflateInit2 zlib_inflateInit2;
    static int peek_gz_call = 0;
    ZEXTERN int ZEXPORT inflateInit2_ OF((z_streamp strm, int  windowBits,
                          const char *version, int stream_size))
    {
        if(!zlib_inflateInit2) {
            //31 byte header is gzip, this will never be the case for bgzip (15 byte header) applications
            if(windowBits == 31) {
                windowBits = -15;
                peek_gz_call = 1;
            }
            ...
    }
```

and then within the `ZEXTERN int ZEXPORT inflate OF((z_streamp strm, int flush))` function in my modified version of FB/Meta's `zlibWrapper/zstd_zlibwrapper.c`:

```
if(peek_gz_call == 1) {
    //reset to avoid coming here once the file is really being inflated
    peek_gz_call = 0;
    //hack the dest buffer (had the header in it previously)
    //to force htslib to choose BED format
    //according to htslib's tabix.c:284
    //vcf, sam, bed, and text_format are handled the same way for querying regions
    //ONLY FOR FILE TYPE DETERMINATION!
    strm->next_out[0]='c';
    strm->next_out[1]='\t';
    strm->next_out[2]='1';
    strm->next_out[3]='\t';
    strm->next_out[4]='1';
    strm->next_out[5]='\t';
    strm->next_out[6]='1';
    //for > hts lib 1.13 (e.g. 1.19)
    strm->next_out++;
    //for <= hts lib 1.13 (e.g. 1.11)
    strm->total_out = 1;
    return Z_STREAM_END;
}
```
## A Very Janky Benchmark

Supermouse junctions (818,763) in Snaptron format 969,176,980 bytes (~1 GB), tabix query is all of chr2, 67346 junctions, ~80 MBs uncompressed

BGZip compression: 57.215s, 378,339,449 bytes, 2.56 ratio

* decompression: 3.463s
* tabix indexing: 4.343s
* tabix query: 0.527s

BGZstd compression: 10.568s, 339,276,637 bytes, 2.86 ratio

* decompression: 2.924s
* tabix indexing: 3.474s
* tabix query: 0.540s

BGZstd has 5.4x faster compression, a slightly better compression ratio, slightly faster decompression, slightly faster tabix indexing but not querying.

## Acknowlegements

Thanks to Brian Craft for the insight on the LD_PRELOAD trick.
Obviously, big thanks to FB/Meta for the excellent, open source ZSTD as well as going the extra mile with the zlibWrapper code!

## Legal

All ZSTD-related code (including the zlibWrapper) is owned by FB/Meta (see zstd/LICENSE).
