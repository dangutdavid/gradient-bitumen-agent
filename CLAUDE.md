# CLAUDE.md — Gradient Bitumen Agent

Project context for the Gradient Bitumen (GB) Salesforce agent. Full schema detail in
[docs/schema.md](docs/schema.md). This file is the quick-reference for confirmed API names,
relationships, and the phase plan.

## Org
- Target sandbox alias: **`gb-partialsb`** (`maren@dkloudconsulting.compartialsb`, Org Id `00Dct000004upaDEAQ`).
- SFDX source format under `force-app/main/default/`. API version **66.0**.
- Deploy/test: `sf project deploy start -o gb-partialsb`, `sf apex run test -o gb-partialsb`.

## What we're building
An agent (Agentforce / invocable-Apex actions) that resolves an account, reports account
insight, describes objects, then creates and submits a **Loading Advice** headlessly —
mirroring the existing UI screens/flows.

## Confirmed schema facts (verified from org describe + metadata XML — not memory)

### Objects in scope
`Account`, `Opportunity`, `Order`, `Loading_Advice__c`, `Loading_Advice_Line__c`.

### Relationships
- `Opportunity.AccountId` → Account (lookup)
- `Order.AccountId` → Account (lookup); `Order.OpportunityId` → Opportunity (lookup)
- `Loading_Advice__c.Order_DKL__c` → Order — **MASTER-DETAIL** (non-reparentable)
- `Loading_Advice_Line__c.LoadingAdvice_DKL__c` → Loading_Advice__c — **MASTER-DETAIL** (non-reparentable)
- LA also: `Account_DKL__c` → Account, `Opportunity_DKL__c` → Opportunity (lookups)
- Create **parent-first**: Order → Loading_Advice__c → Loading_Advice_Line__c.

### Master-detail field API names (must supply at insert)
- `Loading_Advice__c.Order_DKL__c`
- `Loading_Advice_Line__c.LoadingAdvice_DKL__c`

### Loading_Advice__c record types (Type of Load → DeveloperName)
- Commercial → `Commercial_DKL`
- Stock Transfer → `StockTransfer_DKL`
- `Agent_CommitLoadingAdvice` (Phase 2) sets `RecordTypeId` from this; default `Commercial_DKL`.

### Curated business-required fields (SOURCE OF TRUTH for `missingFields` — NOT DB nillable)
All on `Loading_Advice_Line__c`:
1. `Customer_DKL__c` (→ Account)  — *only this + master-detail are DB `nillable=false`*
2. `CustomerType_DKL__c` (picklist: Advance; Credit)
3. `Location_DKL__c` (text)
4. `Product_DKL__c` (→ Product2)
5. `QuantityMT_DKL__c` (double)
6. `PricePerMT_DKL__c` (currency — not meaningful for Stock Transfer)

The agent validates against this list, **not** the schema nillable flags.

### Order — truly mandatory at create
- `EffectiveDate` (Order Start Date), `Status` (Draft|Activated|Hold|Fulfilled/Closed|Cancelled).
- `AccountId`: describe says nillable=true but platform enforces it at insert → **treat as mandatory**.
- Auto-defaulted (don't supply): `OwnerId`, `CurrencyIsoCode` (NGN default), `IsReductionOrder`.

### PDF generation (Commercial vs Stock Transfer)
- Commercial (`Commercial_DKL`) → `LoadingAdvicePDFGenerator` (VF `LoadingAdvicePDFTemplate`)
- Stock Transfer (`StockTransfer_DKL`) → `GenerateStockTransferPDF` (VF `StockTransferDispatchPDF`)
- `LoadingAdvicePDFExtension` = shared VF controller (defaults to Commercial if RecordType null).
- Type-based routing lives in flow **`LA_Approve_Reject`** (decision `Commercial_Or_Stock_Transfer`),
  firing at **approval/dispatch**, NOT at submit.

### Submit-for-Approval (flow `Loading Advice - Submit for Approval`, screen flow)
Sets on the LA header: `Approval_Status_DKL__c='Pending 1st Approver'`, `Status_DKL__c='Draft'`,
`SubmittedOn_DKL__c=now`, `Submittedby_DKL__c=running user`. Generates internal PDF via
`LoadingAdvicePDFGenerator`, builds attachments via subflow `LA_Build_Email_Attachments`,
emails the approver (OWA `aramy@dkloudconsulting.com`) and sends a custom bell notification.
Approver routing via custom object `Approvver_Availability__c` (note spelling) filtered by
`ApprovalStage_DKL__c='Level 1'` → `Approver_DKL__c` / `BackupApprover_DKL__c`.

## Confirmed agent contract (single-prompt, ask-then-confirm)
The user sends ONE natural-language prompt containing the values. The agent then:
1. Parses it and resolves the Account (recordId on the Account page; else ask for the name
   from the utility bar; if ambiguous, ask which one).
2. If any REQUIRED field is missing, asks for ALL gaps in ONE follow-up (not one at a time).
   Loops until complete.
3. Shows a single summary and asks "Proceed? (yes/no)" — confirm BEFORE writing.
4. On yes: creates Opportunity → Order → Loading Advice → Line, then auto-submits.
5. Sends a confirmation listing the 4 created records (with links) + submission status.

"Required" = the curated business list, NOT DB nillable. Always set `Order.AccountId` and the
LA `RecordTypeId` (Commercial → `Commercial_DKL`, Stock Transfer → `StockTransfer_DKL`).

### AgentActionResult (shared wrapper) shape
`success` (Boolean), `status` (`OK`|`NEEDS_INPUT`|`NEEDS_CONFIRM`|`ERROR`), `recordId`,
`recordUrl`, `missingFields` (List<String>), `summaryJson`, `message`. Factory helpers:
`ok()`, `needsInput()`, `needsConfirm()`, `error()`, plus `withRecord(Id)` for recordId/URL.

## Phase plan
- **Phase 1 (current):** read-only agent actions + shared wrapper.
  - `AgentActionResult` — shared result wrapper (success flag, message, data, errors).
  - `Agent_ResolveAccount` — resolve an Account by name/identifier.
  - `Agent_GetAccountInsight` — summarise account (orders, opps, permits, etc.).
  - `Agent_DescribeObject` — return field/relationship metadata for an object.
  - Each with its own `@isTest` class. Deploy to `gb-partialsb`, run tests, show coverage.
- **Phase 2 (single-prompt, transactional sales chain):** the agent extracts ALL field
  values for the WHOLE chain from ONE natural-language prompt and creates
  Opportunity → Order → Loading Advice → Line, then auto-submits. It is NOT a multi-turn
  conversation. Components:
  - **Per-object PREVIEW methods** — validate parsed fields + report `missingFields` using
    the **curated business-required list** (see above), not DB nillable.
  - **`Agent_PreviewSalesChain`** — takes parsed fields for all four records, runs every
    preview, returns ONE combined result: a single summary of what will be created across
    all four + a **consolidated `missingFields`** spanning all records. If anything is
    missing, the agent asks for all gaps in ONE follow-up. Returns a confirmation token.
  - **`Agent_CommitSalesChain`** — requires the confirmation token; creates
    Opportunity → Order → Loading Advice → Line in order inside a SINGLE transaction using
    `Database.setSavepoint()` + rollback on ANY failure (no orphaned records), threading each
    parent Id into the next child. Sets `RecordTypeId` on the LA from the Type of Load in the
    same step. On success calls `Agent_SubmitLAForApproval` and returns the four record links
    + submit status. On failure: roll back everything, create nothing, return the error.
  - Tests cover: full happy path (4 created + submitted), missing-field-in-prompt branch
    (consolidated ask, nothing created), commit-without-confirmation rejection, and a
    mid-chain insert failure that rolls the whole chain back cleanly.
- **Phase 3 (DONE — headless auto-approval):** autolaunched flow
  `LA_Submit_For_Approval_Headless` (screen-free clone of the manual flow, same
  `SystemModeWithoutSharing` run mode; empty-lines → output `resultStatus='ERROR'`; success
  sets `Status_DKL__c='Draft'`/`Approval_Status_DKL__c='Pending 1st Approver'` +
  `SubmittedOn`/`Submittedby`, generates internal PDF, builds attachments via
  `LA_Build_Email_Attachments`, bell alert + approver email). `AgentApprovalService.submit(Id)`
  runs it via `Flow.Interview` and returns an `AgentActionResult`; invocable wrapper
  `Agent_SubmitLAForApproval`.
  - **⚠️ Commit and submit are SEPARATE transactions (platform constraint).** The flow renders
    the PDF via `PageReference.getContentAsPDF()`, which throws "uncommitted work pending" if
    called while the chain inserts are uncommitted. So `commitChain` only creates the chain
    (`submitted=false`, `readyToSubmit=true`); the orchestration layer (Phase 4 controller /
    Phase 5 LWC) calls `AgentApprovalService.submit(laId)` as the next call/transaction. Tests
    pass commit→submit in one transaction only because `LoadingAdvicePDFGenerator` returns a
    dummy blob under `Test.isRunningTest()` (skips `getContentAsPDF`).
- **(superseded) earlier Phase 3 note:** mirror the Submit-for-Approval screen flow ONLY
  (internal PDF via `LoadingAdvicePDFGenerator` + `LA_Build_Email_Attachments` subflow +
  notification + email + `Status_DKL__c='Draft'`/`Approval_Status_DKL__c='Pending 1st Approver'`
  + `SubmittedOn_DKL__c`/`Submittedby_DKL__c`). Invoked by `Agent_CommitSalesChain` on success.
  NOT the approval-time Commercial/Stock-Transfer dispatch routing (that lives in
  `LA_Approve_Reject` and fires later at approval off `RecordType`).

## Conventions
- Apex actions exposed via `@InvocableMethod` where they are agent-callable.
- Keep each action's logic in its own class with a matching `*Test` class.
- Use `AgentActionResult` as the uniform return shape across actions.

## TODO / known debt
- **Legacy PDF classes are at 0% coverage** (`LoadingAdvicePDFGenerator`,
  `LoadingAdvicePDFExtension`, `GenerateStockTransferPDF`). They MUST get test classes before
  any validated/production deploy (org-wide 75% gate). Until then, deploy to the sandbox with
  `--test-level NoTestRun` and run the new test classes separately with `sf apex run test`.

## Status
- Step 2 (schema) ✅ · Phase 1 (read-only services) ✅ · Phase 2 (sales chain) ✅ ·
  Phase 3 (headless auto-approval) ✅ — all deployed to gb-partialsb. Next: Phase 4
  (parser + stateless conversation controller).
