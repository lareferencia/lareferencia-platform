# Single Accepted Vocabulary Validator

## Purpose

`SingleAcceptedVocabularyValidatorRule` checks that a metadata field contains exactly one occurrence from a complete controlled vocabulary, and that this term is accepted by LA Referencia.

Vocabulary membership and acceptance are separate criteria. A recognized term that LA Referencia does not accept still counts when detecting concurrent vocabulary values.

This is a separate rule. It does not change `ControlledValueFieldContentValidatorRule`.

## Configuration

The rule has three configuration properties:

- `fieldname`: the metadata field to evaluate.
- `vocabulary`: the complete main vocabulary, with a `value` and an `accepted` flag for each term.
- `otherVocabularyValues`: an optional list of exact values from other vocabularies that legitimately share the field. These values are excluded from unmatched-value diagnostics.

In the Admin UI, users maintain one list of terms and mark each accepted term with the **Accepted by LA Referencia** checkbox.

Example configuration:

```json
{
  "fieldname": "dc.type",
  "vocabulary": [
    { "value": "article", "accepted": true },
    { "value": "thesis", "accepted": true },
    { "value": "book", "accepted": false }
  ]
}
```

The configuration requires a nonblank field name, a nonempty vocabulary, unique nonblank term values, and at least one accepted term. An omitted acceptance flag is treated as `false`.

Use the actual field name and complete vocabulary values for the metadata format being processed. The values above are illustrative.

## Validation algorithm

1. Read the occurrences of the configured field.
2. Select every occurrence whose value belongs to the complete vocabulary.
3. Count the selected occurrences, including repeated occurrences of the same term.
4. Pass the rule only if there is exactly one selected occurrence and its term is marked as accepted.

Matching is exact and case sensitive. The rule does not trim whitespace, translate values, or normalize case.

The cardinality requirement is fixed. The inherited quantifier does not change this rule's behavior; the Admin UI displays **Exactly one** and disables the quantifier selector for this rule.

Values outside the vocabulary do not affect the count. For example, `article` together with an unrelated free-text value passes, whereas `article` together with `book` fails.

The rule validates the metadata it receives. Transformations applied before validation can change the outcome. In particular, a transformation that removes concurrent vocabulary occurrences may remove the conflict before this rule evaluates it.

## Agreed results strategy

The overall validation decision and the values included in `results` serve different purposes. The decision enforces the policy above. The results retain the values that explain the decision or help identify values that could be transformed.

| Situation | Rule validity | Values included in `results` |
| --- | --- | --- |
| Exactly one recognized, accepted occurrence | Valid | One valid result containing that term. |
| Exactly one recognized, unaccepted occurrence | Invalid | One invalid result containing that term. |
| Multiple recognized occurrences | Invalid | One invalid result containing all recognized occurrences joined with ` · `. |
| No recognized occurrences, but the field contains values | Invalid | One invalid result per original value outside `otherVocabularyValues`, to support mapping analysis; if all values are excluded, report the missing main vocabulary term. |
| No field values are available | Invalid | One invalid result indicating the absence of values. |

Whenever at least one vocabulary occurrence is found, values outside the vocabulary are omitted from `results`.

For multiple matches, the joined result includes accepted and unaccepted terms, preserves the original occurrence order, and preserves repetitions. Thus `article · article` exposes two occurrences, and `article · book` exposes concurrent terms even though only one is accepted.

When no main vocabulary match is found, original values are retained without normalization or deduplication, except those listed in `otherVocabularyValues`. These remaining values can reveal candidate mappings to an accepted term. If the field contains only values from the other-vocabulary list, the rule remains invalid and emits `no_vocabulary_occurrences_found`. This differs from `no_occurrences_found`, which means no field values were available.

The additional list defaults to empty when omitted or null, preserving existing configurations. Its values must be unique and nonblank and must not overlap with the main vocabulary. Matching is exact; no prefix exclusion is performed. This list does not count toward cardinality, grant acceptance, or validate the secondary vocabulary itself.

## Examples

Using the example vocabulary above:

| Field occurrences | Rule validity | Agreed result contents |
| --- | --- | --- |
| `article` | Valid | `article` |
| `article`, `free text` | Valid | `article` |
| `book`, `free text` | Invalid | `book` |
| `article`, `book`, `free text` | Invalid | `article · book` |
| `article`, `thesis` | Invalid | `article · thesis` |
| `article`, `article` | Invalid | `article · article` |
| `Scientific article`, `Publication` | Invalid | Two separate invalid results: `Scientific article` and `Publication`. |
| No values | Invalid | An absence-of-values result. |

## Record validity and reporting

The rule stores occurrence details for reporting. Each result uses `ContentValidatorResult`, which contains `valid` and `receivedValue`.

A failed rule makes the record invalid when the rule is configured as mandatory. If it is optional, its failure is reported but does not by itself invalidate the record.

## Implementation status

The configuration, validation algorithm, and results strategy described above are implemented. Concurrent vocabulary matches produce one joined result. If there are no matches, original field values produce separate invalid results; values in `otherVocabularyValues` are excluded from these unmatched results. If all values are excluded, the rule emits `no_vocabulary_occurrences_found`; if no values are available, it emits `no_occurrences_found`.

## Source files

- [SingleAcceptedVocabularyValidatorRule.java](../lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/validation/validator/SingleAcceptedVocabularyValidatorRule.java)
- [VocabularyTerm.java](../lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/validation/validator/VocabularyTerm.java)
- [ValidatorImpl.java](../lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/validation/ValidatorImpl.java)

## OpenAIRE 3.0 example: publication type and version

OpenAIRE 3.0 uses `dc:type` for both the mandatory publication type and the recommended publication version. A local publication subtype is also optional. See the official [publication type guideline](https://guidelines.readthedocs.io/en/v3.0/literature/field_publicationtype.html) and [publication version guideline](https://guidelines.readthedocs.io/en/v3.0/literature/field_publicationversion.html).

For a rule evaluating publication types, configure the full type vocabulary as the main list, with LA Referencia acceptance flags, and place these five version terms in `otherVocabularyValues`:

```json
[
  "info:eu-repo/semantics/draft",
  "info:eu-repo/semantics/submittedVersion",
  "info:eu-repo/semantics/acceptedVersion",
  "info:eu-repo/semantics/publishedVersion",
  "info:eu-repo/semantics/updatedVersion"
]
```

Do not exclude by the `info:eu-repo/semantics/` prefix: publication types and versions share it.

The following examples abbreviate that prefix. Assume `article` is an accepted main term and `book` is a recognized main term:

| Field values | Validity | Results |
| --- | --- | --- |
| `article`, `publishedVersion` | Valid | `article` |
| `article`, `book`, `publishedVersion` | Invalid | `article · book` |
| `Scientific article`, `publishedVersion` | Invalid | `Scientific article` |
| `publishedVersion` only | Invalid | `no_vocabulary_occurrences_found` |
| No field values | Invalid | `no_occurrences_found` |

The concurrent version does not become a second publication type or a candidate for type transformation. A separate rule can validate versions if required. This rule implements LA Referencia's acceptance and cardinality policy; it does not check OpenAIRE's instruction about the position of the publication type occurrence.
