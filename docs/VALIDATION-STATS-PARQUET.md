# Validation Statistics Parquet Configuration

## Overview

The fact table implementation completely replaces the previous architecture based in spring data solr. This new architecture normalizes data into a fact table with 1 row per validation rule occurrence.

## Configuration Properties

### Parquet Files Location

```properties
store.basepath=/tmp/data/parquet
```

**Description**: Base directory where all Parquet data is stored (OAI catalog and validation statistics).

**Directory Structure**:
```
/tmp/data/parquet/
├── snapshot_{id}/
│   ├── catalog/
│   │   ├── oai_records_batch_1.parquet
│   │   └── oai_records_batch_2.parquet
│   └── validation/
│       ├── records_batch_1.parquet
│       ├── validation_index.parquet
│       └── validation-stats.json
```

**Recommendations**:
- In production, use a distributed file system (HDFS, S3, Azure Blob)
- Ensure sufficient disk space
- Configure appropriate read/write permissions

---

### Records Per File (Base)

```properties
parquet.validation.records-per-file=100000
```

**Description**: Base number of records per file when dynamic sizing is disabled or as fallback.

**Recommended Values**:
- **Development/Testing**: 1,000 - 10,000
- **Standard Production**: 100,000 - 500,000
- **Big Data**: 1,000,000 - 2,000,000

**Impact**:
- Very low values (< 10K): Too many small files, filesystem overhead
- Very high values (> 5M): Very large files, higher memory usage when reading

---

### Dynamic File Size Adjustment

```properties
parquet.validation.enable-dynamic-sizing=true
```

**Description**: Enables automatic file size adjustment based on snapshot size.

**Values**: `true` | `false`

**Dynamic Sizing Algorithm** (when enabled):

| Snapshot Size | Records/File | Expected Files | File Size     |
|---------------|--------------|----------------|---------------|
| < 100,000     | 50,000       | 1-2            | 1.5-4 MB      |
| 100K - 1M     | 500,000      | 2-20           | 15-40 MB      |
| 1M - 10M      | 1,000,000    | 1-10           | 30-80 MB      |
| > 10M         | 2,000,000    | 5+             | 60-160 MB     |

**Recommended**: `true` (automatically optimizes based on snapshot)

**Behavior**:
- Snapshot size is automatically registered during `initializeValidationForSnapshot()`
- Obtained from `NetworkSnapshot.size` via `IMetadataRecordStoreService.getSnapshotSize()`
- If size is not available, uses `parquet.validation.records-per-file` value

---

## Compression and Encoding Configuration

These values are hardcoded in `FactOccurrencesWriter` but can be externalized if needed:

### Compression

```java
CompressionCodecName.ZSTD  // Zstandard compression
```

**Characteristics**:
- Compression ratio: ~4:1 (better than Snappy)
- Read speed: ~450 MB/s
- Optimal balance between compression and speed

**Alternatives**:
- `SNAPPY`: Faster, less compression (ratio ~2:1)
- `GZIP`: Better compression (ratio ~6:1), slower
- `UNCOMPRESSED`: No compression (for debugging)

### Dictionary Encoding

```java
.withDictionaryEncoding(true)
```

**Description**: Enables dictionary encoding for repetitive fields.

**Benefits**:
- Reduces size of fields with repeated values (network, repository, institution)
- Improves query speed with filters on these fields
- ~30-50% additional size reduction

### Row Group Size

```java
.withRowGroupSize(128 * 1024 * 1024)  // 128 MB
```

**Description**: Row group size to optimize sequential reading.

**Recommended Values**:
- **HDFS/S3**: 128 MB - 256 MB (optimal for HDFS blocks)
- **Local disk**: 64 MB - 128 MB
- **Limited memory**: 32 MB - 64 MB

### Page Size

```java
.withPageSize(1024 * 1024)  // 1 MB
```

**Description**: Page size for balance between compression and seek efficiency.

**Typical Values**:
- **Standard**: 1 MB (optimal balance)
- **Frequent queries**: 512 KB (better seek)
- **Full scan**: 2 MB (better compression)

---

## Parquet/Hadoop Logging

To reduce log noise:

```properties
logging.level.org.apache.parquet.hadoop.InternalParquetRecordReader=WARN
logging.level.org.apache.hadoop.io.compress.CodecPool=WARN
logging.level.org.apache.parquet=WARN
logging.level.org.apache.hadoop=WARN
```

For detailed debugging:

```properties
logging.level.org.lareferencia.backend.repositories.parquet=DEBUG
logging.level.org.lareferencia.backend.validation=DEBUG
```

---

## Fact Table Schema

### Fields (14 columns)

| Field             | Type    | Required | Description                                  |
|-------------------|---------|----------|----------------------------------------------|
| id                | STRING  | Yes      | Unique record ID (MD5/XXHash)                |
| identifier        | STRING  | Yes      | OAI identifier                               |
| snapshot_id       | LONG    | Yes      | Snapshot ID (partition)                      |
| origin            | STRING  | Yes      | Origin URL                                   |
| network           | STRING  | No       | Network acronym (partition)                  |
| repository        | STRING  | No       | Repository name                              |
| institution       | STRING  | No       | Institution name                             |
| rule_id           | INT     | Yes      | Validation rule ID                           |
| value             | STRING  | No       | Occurrence value                             |
| is_valid          | BOOLEAN | Yes      | Valid occurrence (partition)                 |
| record_is_valid   | BOOLEAN | Yes      | Complete record valid                        |
| is_transformed    | BOOLEAN | Yes      | Record transformed                           |
| metadata_prefix   | STRING  | No       | Metadata prefix (e.g., "xoai")               |
| set_spec          | STRING  | No       | OAI set specification                        |

### Partitioning

**Strategy**: Hierarchical partitioning by 3 levels

```
snapshot_id={id}/network={acronym}/is_valid={true|false}
```

**Advantages**:
- Predicate pushdown: Skips entire partitions
- Snapshot queries: Reads only relevant directories
- Network queries: Filters at filesystem level
- Valid vs invalid: Physical separation for frequent queries

---

## Migration from Avro

### Migration Steps

1. **Backup existing data** (optional):
   ```bash
   mv /tmp/validation-stats-parquet /tmp/validation-stats-parquet.old
   ```

2. **Clean directories**:
   ```bash
   rm -rf /tmp/validation-stats-parquet
   mkdir -p /tmp/validation-stats-parquet
   ```

3. **Update configuration**: Use recommended values in `application.properties`

4. **Restart application**: Data will be regenerated on next validation

5. **Verify structure**:
   ```bash
   ls -la /tmp/validation-stats-parquet/snapshot_id=*/network=*/is_valid=*/*.parquet
   ```

### Compatibility

**No backward compatibility** with old Avro files. Parquet files must be completely regenerated.

---

## Performance Tuning

### For small snapshots (< 100K)

```properties
parquet.validation.enable-dynamic-sizing=true
parquet.validation.records-per-file=50000
```

### For large snapshots (> 10M)

```properties
parquet.validation.enable-dynamic-sizing=true
parquet.validation.records-per-file=2000000
```

### For systems with limited memory

Reduce row group size in code:
```java
.withRowGroupSize(64 * 1024 * 1024)  // 64 MB instead of 128 MB
```

### To improve write speed

Reduce compression (in code):
```java
.withCompressionCodec(CompressionCodecName.SNAPPY)  // Instead of ZSTD
```

---

## Troubleshooting

### Problem: Too many small files

**Cause**: `records-per-file` too low or dynamic sizing disabled

**Solution**:
```properties
parquet.validation.enable-dynamic-sizing=true
parquet.validation.records-per-file=100000  # Increase
```

### Problem: OutOfMemoryError when reading

**Cause**: Row group size too large or queries without filters

**Solution**:
1. Reduce row group size to 64 MB
2. Always use filters by snapshot_id
3. Increase heap: `-Xmx4g`

### Problem: Filters not working

**Verify**:
1. `BUILD PREDICATE` logs show the constructed predicate
2. Use compatible filters: `isValid`, `valid_rules`, `invalid_rules`, `identifier`
3. Correct format: `field:value` or `field@@"value"`

### Problem: Slow performance

**Diagnose**:
```properties
logging.level.org.lareferencia.backend.repositories.parquet=DEBUG
```

**Optimize**:
1. Verify predicate pushdown is active (logs show filters)
2. Use partitioning: Always filter by `snapshot_id`
3. Consider Parquet indexes if available in future version

---

## Monitoring

### Key Metrics

- **Number of files per snapshot**: Ideally < 20 files per partition
- **Average file size**: 30-80 MB is optimal
- **Records read**: Logs show `FactOccurrencesReader: Records read: X`
- **Records written**: Logs show `FactOccurrencesWriter: Records written: X`

### Useful Commands

**Count files**:
```bash
find /tmp/validation-stats-parquet -name "*.parquet" | wc -l
```

**Total size**:
```bash
du -sh /tmp/validation-stats-parquet
```

**Files per snapshot**:
```bash
ls -la /tmp/validation-stats-parquet/snapshot_id=8/network=*/is_valid=*/*.parquet
```

---

## References

- [Apache Parquet Documentation](https://parquet.apache.org/docs/)
- [Parquet File Format Specification](https://github.com/apache/parquet-format)
- [Hadoop Configuration](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/core-default.xml)
