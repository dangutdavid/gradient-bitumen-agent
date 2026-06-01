# Gradient Bitumen — Conversational Sales Agent

A Salesforce agent that turns ONE natural-language prompt into a complete sales chain —
**Opportunity → Order → Loading Advice → Loading Advice Line** — and submits it for approval.
The agent resolves the account, asks once for any missing required fields, confirms before
writing, creates everything in a single all-or-nothing transaction, then runs the headless
approval path (internal PDF + bell alert + approver email).

Built **pure Apex + (future) LWC**, with no Agentforce/Einstein license, and designed so an
LLM parser can be added later without touching the action library.

- **Org:** `salesgvgr` — PartialSB sandbox (`gb-partialsb`), API 66.0
- **Status:** Phases 1–3 complete (read-only services, transactional sales chain, headless
  auto-approval). All Agent test classes pass 100%.

> Private repo — contains client IP (schema, approver routing, email addresses). Do not share.

## Architecture (4 layers, LLM-ready)

| Layer | What it is | Notes |
|---|---|---|
| 1 · Chat UI | LWC `gbSalesAgent` (utility bar + Account page) — *Phase 5* | Transcript, missing-field prompts, summary card with Proceed/Cancel, result links; holds conversation state client-side. |
| 2 · Conversation controller | Apex `@AuraEnabled`, stateless — *Phase 4* | Turn state machine: parse → merge → preview → ask/confirm/commit → submit. |
| 3 · Parser (pluggable) | `AgentPromptParser` interface — *Phase 4* | v1 `RuleBasedPromptParser`; swappable to an LLM parser via Custom Metadata with no other change. |
| 4 · Action services | Plain Apex + thin `@InvocableMethod` wrappers | Resolve / insight / describe / preview-chain / commit-chain / submit. Flow/Agentforce-ready. |

All actions return a shared `AgentActionResult`:
`success`, `status` (`OK` \| `NEEDS_INPUT` \| `NEEDS_CONFIRM` \| `ERROR`), `recordId`,
`recordUrl`, `missingFields`, `summaryJson`, `message`.

## What's built (Phases 1–3)

- **Phase 1 — read-only services:** `Agent_ResolveAccount`, `Agent_GetAccountInsight`,
  `Agent_DescribeObject`.
- **Phase 2 — single-prompt sales chain:** `AgentChainService.preview` (consolidated
  `missingFields` + summary + confirmation token) and `commitChain` (savepoint →
  Opportunity → Order → Loading Advice → Line in one transaction, rollback on any failure,
  record type set from load type). Invocable wrappers `Agent_PreviewSalesChain` /
  `Agent_CommitSalesChain`.
- **Phase 3 — headless auto-approval:** autolaunched flow `LA_Submit_For_Approval_Headless`
  (screen-free clone of the manual Submit-for-Approval flow) run via
  `AgentApprovalService.submit(Id)` / `Agent_SubmitLAForApproval`. Sets
  `Status_DKL__c='Draft'` / `Approval_Status_DKL__c='Pending 1st Approver'`, generates the
  internal PDF, builds attachments, and notifies the approver by bell alert + email.

### ⚠️ Commit and submit are SEPARATE transactions

The approval flow renders the PDF via `PageReference.getContentAsPDF()`, which throws
"uncommitted work pending" if called while the chain inserts are still uncommitted. So
`commitChain` only **creates** the chain (`submitted=false`, `readyToSubmit=true`); the
orchestration layer calls `AgentApprovalService.submit(laId)` as the **next** call/transaction
(this is how the Phase 5 LWC invokes them). Tests pass commit→submit in one transaction only
because `LoadingAdvicePDFGenerator` returns a dummy blob under `Test.isRunningTest()`.

## Key schema facts (verified from the org)

- `Loading_Advice__c.Order_DKL__c` → Order is **Master-Detail**;
  `Loading_Advice_Line__c.LoadingAdvice_DKL__c` → Loading Advice is **Master-Detail**
  (both non-reparentable → create parent-first).
- Load type → Record Type: Commercial → `Commercial_DKL`, Stock Transfer → `StockTransfer_DKL`.
- **Required = curated business list**, NOT the DB nillable flag: Customer, Customer Type,
  Location, Product, Quantity (MT), Price (N/MT) (all on the Line).

Full detail: [docs/schema.md](docs/schema.md). Design docs: [docs/design/](docs/design/).
Working context for future sessions: [CLAUDE.md](CLAUDE.md).

## Develop / test

```bash
# Deploy to the sandbox (legacy PDF classes are at 0% coverage — tracked in CLAUDE.md —
# so deploy without the org-wide test gate, then run the Agent tests separately)
sf project deploy start -o gb-partialsb --test-level NoTestRun
sf apex run test -o gb-partialsb \
  --tests AgentActionResultTest --tests Agent_ResolveAccountTest \
  --tests Agent_GetAccountInsightTest --tests Agent_DescribeObjectTest \
  --tests Agent_PreviewSalesChainTest --tests Agent_CommitSalesChainTest \
  --tests AgentApprovalServiceTest --code-coverage --result-format human
```
