# Chunking in Semantic Indexing

This document describes the current chunking implementation used by `SemanticIndexerWorker` to generate embeddings during semantic indexing in Solr.

## Where It Happens

The flow is concentrated in these classes:

- `org.lareferencia.core.worker.indexing.SemanticIndexerWorker`: integrates embedding generation into the indexing process.
- `org.lareferencia.core.embedding.chunks.ChunkingService`: normalizes text and splits abstracts into chunks.
- `org.lareferencia.core.embedding.chunks.CustomTokenCountEstimator`: estimates the token count used by the splitter.

## Library Used

Chunking uses LangChain4j through this Maven dependency:

```xml
<dependency>
  <groupId>dev.langchain4j</groupId>
  <artifactId>langchain4j-spring-boot-starter</artifactId>
  <version>1.15.0-beta25</version>
</dependency>
```

The directly used APIs are:

- `dev.langchain4j.data.document.Document`
- `dev.langchain4j.data.document.DocumentSplitter`
- `dev.langchain4j.data.document.splitter.DocumentSplitters`
- `dev.langchain4j.data.segment.TextSegment`
- `dev.langchain4j.model.TokenCountEstimator`

The splitter is created with `DocumentSplitters.recursive(maxChunkSize, maxOverlapSize, customTokenCountEstimator)`. This splitter tries to preserve larger text units and progressively falls back to smaller divisions when needed to respect the estimated token limit.

## When Chunking Is Used

Chunking is only part of the flow when `embedding.use.multivalued.vector=true`.

In this mode, the worker builds a list of texts for embedding:

1. Extracts the title from the field configured in `embedding.title.field`.
2. If the title is empty, no embedding is generated for the record.
3. If the title has at least `embedding.title.standalone.indexing.min.words`, adds the title as a standalone text for embedding.
4. Extracts the abstract from the field configured in `embedding.abstract.field`.
5. Generates chunks as `title + abstract_fragment` using `ChunkingService`.
6. Sends the complete list to `embeddingService.embed(List<String>)`.
7. Writes the returned vectors to the Solr field configured in `embedding.vector.field.name`.

When `embedding.use.multivalued.vector=false`, the worker does not use chunks. It only generates one embedding from the normalized title and writes a single vector to the configured field.

## Field Extraction

The title and abstract fields are configurable:

```properties
embedding.title.field=dc.title.*
embedding.abstract.field=dc.description.*
```

The worker calls `OAIRecordMetadata.getFieldOcurrences(metadataField)`. That function converts the field expression to XPath through `XOAIXPATHHelper` and returns all matching occurrences. The worker then:

- removes null occurrences;
- discards blank values;
- concatenates multiple occurrences with a space.

The expressions follow the format used by the XOAI metadata store. For example, `dc.title.*` is processed by `XOAIXPATHHelper` and uses `*` as an element wildcard inside the hierarchy.

## Normalization

Before splitting the abstract, `ChunkingService.normalizeText` applies lightweight normalization:

1. Returns an empty string for `null` or blank text.
2. Normalizes Unicode to NFC.
3. Joins words split by hyphen + line break, as commonly seen in PDF/OCR extraction.
4. Collapses whitespace, tabs, and line breaks into a single space.
5. Trims leading and trailing spaces.

This normalization is applied to both title and abstract inside `chunkTitleAndAbstract`. In single-vector mode, it is also applied to the title before embedding.

## Chunk Format

Each chunk returned by `ChunkingService.chunkTitleAndAbstract(title, abstractText)` has two lines:

```text
normalized_title
abstract_fragment
```

The title is repeated in every chunk to preserve the document's semantic context. The abstract is the part actually split by the splitter.

If either title or abstract is empty after normalization, the service returns an empty list.

## Configurable Limits

The main properties are:

```properties
# Maximum estimated token limit per abstract fragment.
embedding.max.segment.size.tokens=128

# Maximum estimated overlap between consecutive chunks.
embedding.max.overlap.size.tokens=0

# Maximum number of chunks returned per document.
embedding.max.chunks.size=5

# Uses a multivalued vector field and enables abstract chunking.
embedding.use.multivalued.vector=false

# Source field for the title.
embedding.title.field=dc.title.*

# Source field for the abstract.
embedding.abstract.field=dc.description.*

# Solr field where vectors are written.
embedding.vector.field.name=vector_multivalued

# Minimum number of words required to index the title as a standalone embedding.
embedding.title.standalone.indexing.min.words=5
```

The code defaults for chunking are:

- `embedding.max.segment.size.tokens`: `128`
- `embedding.max.overlap.size.tokens`: `0`
- `embedding.max.chunks.size`: `5`

The Docker files in `Docker/config-overrides/*/99-docker.properties` also configure `128`, `0`, and `5`.

## Token Estimation

The project does not use a tokenizer specific to the embedding model. Instead, it uses `CustomTokenCountEstimator`, a custom implementation of LangChain4j's `TokenCountEstimator` interface.

The estimate combines:

- words and numbers, counted with a Unicode regex;
- punctuation, with partial weight;
- CJK characters, with specific handling by Unicode block.

The current formula is:

```text
ceil((words_and_numbers * 1.10) + (punctuation * 0.35) + (cjk_characters * 0.65))
```

The minimum result for non-empty text is `1`. For `null` or blank text, it returns `0`.

This count is approximate. It guides splitter decisions, but it does not guarantee equality with the embedding model's real tokenizer.

## Solr Output

In multivalued mode, the worker expects the Solr vector field to accept a list of vectors:

```text
[
  [title_vector],
  [chunk_1_vector],
  [chunk_2_vector]
]
```

In single-vector mode, it writes only:

```text
[title_vector]
```

Therefore, `embedding.use.multivalued.vector` must be aligned with the Solr schema for the field configured in `embedding.vector.field.name`.

## Existing Tests

`ChunkingServiceTest` covers:

- keeping a short abstract in a single chunk;
- splitting a long abstract into multiple chunks;
- preserving the `title + "\n" + fragment` format;
- respecting the maximum chunk limit;
- behavior with null or blank title/abstract values;
- overlap expectations when overlap is configured as zero.

## Points To Watch

- The token limit only considers the estimated fragment generated by the splitter. The title is prefixed afterward, so the final text sent to embedding may exceed `embedding.max.segment.size.tokens`.
- `embedding.max.chunks.size` truncates the final list of abstract chunks. Long texts may have part of the abstract ignored for embeddings.
- With `embedding.use.multivalued.vector=true`, a record can generate more than one embedding: one for the standalone title and up to `embedding.max.chunks.size` chunk embeddings.
- Titles with fewer words than `embedding.title.standalone.indexing.min.words` do not generate a standalone embedding, but they can still appear as context in abstract chunks.
- Token estimation is independent from the model configured in `embedding.model.name`; if the model changes to a substantially different tokenizer, `CustomTokenCountEstimator` may need recalibration or replacement with a model-specific estimator.
