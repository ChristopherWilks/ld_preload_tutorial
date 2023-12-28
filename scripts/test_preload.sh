#!/bin/bash
#assumes vanilla $TABIX and $BGZIP (htslib >=1.2) are in the path
BGZIP=bgzip
TABIX=tabix
dir=$(dirname $0)
DATA_DIR=$dir/../data

#where libzstd.so.1.3.4 is
export LD_LIBRARY_PATH=/path/to/zstd/lib
#where the preload library is, e.g. /path/to/zstd/lib/zstd_preload.so
export LD_PRELOAD=/path/to/zstd_preload.so

echo "ZSTD timings:"
time cat $DATA_DIR/h1_intervals.tsv | $BGZIP -f > ./h1k.intervals.tsv.bgzs
time $TABIX -f -s2 -b3 -e4 ./h1k.intervals.tsv.bgzs
time $TABIX ./h1k.intervals.tsv.bgzs chr1:11845-12009

export LD_LIBRARY_PATH=
export LD_PRELOAD=

echo "ZLIB timings:"
time cat $DATA_DIR/h1k_intervals.tsv | $BGZIP -f > ./h1k.intervals.tsv.bgz
time $TABIX -f -s2 -b3 -e4 ./h1k.intervals.tsv.bgz
time $TABIX ./h1k.intervals.tsv.bgz chr1:11845-12009
