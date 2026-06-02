# Phase 6 — LLM Parser: Build Plan (design only)

**Status: NOT started. Gated on DKloud's data-egress decision (see the Phase 6 Decision Brief,
commit `41cfbc4`).** v1 is banked at `93d589d` and stays untouched. This document + the
non-deployed skeleton `phase6-skeleton/LLMPromptParser.cls.txt` are reviewable design only —
nothing here is deployed and nothing calls an LLM.

## What Phase 6 is

Replace the rule-based natural-language parser with an LLM that reads free text, **behind the
parser seam that already exists**. The LLM returns the **same `AgentParseResult` shape**
(`fieldMap` of sObject API names, `typeOfLoad`, `accountHint`, `unresolved[]`) that
`RuleBasedPromptParser` returns today — so everything downstream is unchanged.

## Scope — Layer 3 ONLY

| Layer                                                                      | Change in Phase 6?                                            |
| -------------------------------------------------------------------------- | ------------------------------------------------------------- |
| LWC `gbSalesAgent` (chat UI)                                               | **No change**                                                 |
| `AgentConversationController` (turn state machine)                         | **No change**                                                 |
| Parser (Layer 3)                                                           | **+1 class** `LLMPromptParser`; flip `Active_Parser` metadata |
| Action services (resolve / insight / describe / preview / commit / submit) | **No change**                                                 |
| Existing 84 Agent tests                                                    | **No change** — must still pass as-is                         |

**Explicitly:** no controller, LWC, action, or existing-test changes. The only code added is
`LLMPromptParser` (+ its tests). The on-switch is one Custom Metadata value.

## Two independent fallbacks (both already designed)

1. **Class-missing fallback** — `AgentParserFactory` already returns `RuleBasedPromptParser`
   when the configured `Active_Parser` class can't be instantiated (misconfiguration).
2. **Per-turn runtime fallback** — INSIDE `LLMPromptParser.parse()`: any callout error /
   timeout / empty / wrong-shape response degrades to `new RuleBasedPromptParser().parse()`
   for that turn. A model outage never breaks a conversation; it silently reverts to guided
   creation.

## Deliverable 2 — Metadata design (describe only; NOT deployed)

New fields on **`Agent_Setting__mdt`** (mirrors the existing `Active_Parser` / `Active_Intent_Classifier` pattern):

| Field               | Type            | Purpose                                      | Example                                       |
| ------------------- | --------------- | -------------------------------------------- | --------------------------------------------- |
| `LLM_Provider__c`   | Text/Picklist   | Which provider the parser calls              | `SalesforceModels` \| `Anthropic` \| `OpenAI` |
| `LLM_Timeout_Ms__c` | Number          | Callout timeout (ms); fallback fires past it | `10000`                                       |
| `LLM_Model_Name__c` | Text (optional) | Specific model id                            | e.g. an Anthropic/OpenAI/Models model name    |

`Active_Parser` stays **`RuleBasedPromptParser`** until egress is approved. Flipping it to
**`LLMPromptParser`** is the entire on-switch (no deploy needed once the class exists).

**Named Credentials** (one per provider; the parser picks by `LLM_Provider__c`):

- `callout:Salesforce_Models_API` — **recommended** (in-trust-boundary; see Privacy)
- `callout:Anthropic_LLM` — requires API key + DPA
- `callout:OpenAI_LLM` — requires API key + DPA

Keys live in the Named Credential / a protected metadata, never in source.

## Deliverable 3 — Test plan

All new tests; **the existing 84 must stay green unchanged** (proves the seam is transparent).

- **`HttpCalloutMock` per provider** — feed a canned well-formed JSON response, assert it maps
  to the correct `AgentParseResult` (`fieldMap` API names, `typeOfLoad`, `accountHint`,
  `unresolved`).
- **Forced-failure → per-turn fallback** — mock a `CalloutException` / timeout / empty body /
  malformed JSON; assert `parse()` returns the **rule-based** result (no exception escapes).
- **Shape-guard** — mock a response with unknown/garbage fields; assert unknown fields are
  dropped (validated against Schema describe) and bad shape triggers fallback.
- **Regression** — run the full existing suite with `Active_Parser` still rule-based: 84/84
  green (Phase 6 adds capability without altering v1 behaviour).
- **Coverage** — `LLMPromptParser` ≥90% via the mocks (the live callout line is covered by the
  mock path; the per-turn fallback by the failure tests).

## Deliverable 4 — Privacy / egress flags (THE gate)

Every turn sends the user's prompt — **account names, pricing, volumes** — to the model.

- **Salesforce Models API — RECOMMENDED.** Stays inside the Salesforce trust boundary; no new
  third-party data-processor; keeps the privacy approval short. Commercial pricing does not
  leave the platform.
- **Anthropic / OpenAI direct.** A **new third-party data-processor relationship** — sends
  account/price/volume data **off-platform**. Requires explicit DKloud sign-off (DPA), API-key
  management, and an egress review before any build.

**Decision owed by DKloud:** (1) is per-turn egress of account/price/volume acceptable at all?
(2) if yes, via Salesforce Models API (recommended) or a third party? Until answered, Phase 6
is not built and `Active_Parser` stays rule-based.

## Honest scope note

v1 is guided creation with smart pre-fill + capture-echo, and degrades safely (asks again,
never guesses). Phase 6 upgrades it to true free-text understanding. It is a **value-add behind
a config flag**, not a fix — v1 is production-shaped today.
