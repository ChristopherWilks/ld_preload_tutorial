# ld_preload_tutorial
Overview of how to use LD_PRELOAD using ZLIB wrapper for ZSTD compression

Current version works for ZSTD v1.3.4 and most versions of Tabix/bgzip (tested with 1.19).

# How it works

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

