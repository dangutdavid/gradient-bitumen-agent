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
- `Loading_Advice_Line__c.LoadingAdvice_DKL__c` → Loading_Advice\_\_c — **MASTER-DETAIL** (non-reparentable)
- LA also: `Account_DKL__c` → Account, `Opportunity_DKL__c` → Opportunity (lookups)
- Create **parent-first**: Order → Loading_Advice**c → Loading_Advice_Line**c.

### Master-detail field API names (must supply at insert)

- `Loading_Advice__c.Order_DKL__c`
- `Loading_Advice_Line__c.LoadingAdvice_DKL__c`

### Loading_Advice\_\_c record types (Type of Load → DeveloperName)

- Commercial → `Commercial_DKL`
- Stock Transfer → `StockTransfer_DKL`
- `Agent_CommitLoadingAdvice` (Phase 2) sets `RecordTypeId` from this; default `Commercial_DKL`.

### Opportunity record type (confirmed by Aramy 2026-06-02)

- Agent-created Opportunities are set to **`GradientOpportunity_DKL`** ("Gradient Opportunity")
  in `AgentChainService.commitChain` (resolved by DeveloperName, cached). NOT the legacy
  `Gradient_Opportunity` ("…Old"). Before this fix the Opp inherited the profile default and
  was mis-typed `Greenville_Industrial`. Creators are admins (target-user=no), who have the RT.
- **Account record type:** **CLOSED — option (1) Gradient-only by design, implemented.** Aramy
  confirmed the agent should work ONLY with `Gradient_Account` records. `Agent_ResolveAccount`
  now filters **both** the exact-match resolve AND the disambiguation candidate list by
  `RecordType.DeveloperName = 'Gradient_Account'`; a name matching only a non-Gradient
  (Greenville) account returns a clear NOT-FOUND (never a silent wrong-account resolve, never an
  error). By design the agent **declines ~64% of accounts** (Greenville) — accepted by Aramy.
  Tests: Gradient resolves; non-Gradient excluded → not-found; candidate list excludes
  non-Gradient. (Org reality at decision time: 289 active accounts = 36% Gradient / 64%
  Greenville.)
- ⚠️ **Handover meta-note:** twice now a "use Gradient X" requirement collided with org
  record-type reality (Opportunity RT defaulted to `Greenville_Industrial`; Account RTs are 64%
  Greenville). In this org, **check the record-type distribution before implementing any
  "Gradient-only" requirement** — the labels don't match the data by default.

### Curated business-required fields (SOURCE OF TRUTH for `missingFields` — NOT DB nillable)

All on `Loading_Advice_Line__c`:

1. `Customer_DKL__c` (→ Account) — _only this + master-detail are DB `nillable=false`_
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
    - submit status. On failure: roll back everything, create nothing, return the error.
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
  - `SubmittedOn_DKL__c`/`Submittedby_DKL__c`). Invoked by `Agent_CommitSalesChain` on success.
    NOT the approval-time Commercial/Stock-Transfer dispatch routing (that lives in
    `LA_Approve_Reject` and fires later at approval off `RecordType`).

## Conventions

- Apex actions exposed via `@InvocableMethod` where they are agent-callable.
- Keep each action's logic in its own class with a matching `*Test` class.
- Use `AgentActionResult` as the uniform return shape across actions.

## Security posture & sharing (deliberate, v1)

- **FLS = option (a), permissive insert (DELIBERATE).** `AgentChainService.commitChain` uses
  plain Apex `insert` (no `Security.stripInaccessible`). The agent is a **trusted, gated
  action**; the protections are **panel visibility** (who can see/run `gbSalesAgent`) + the
  **confirm gate**, NOT per-field FLS. Consequence: a user can create a chain even if their
  profile lacks FLS on some Line fields (e.g. `Customer_DKL__c`/`CustomerType`/`Quantity` are
  missing for the **Gradient Sales Team** profile and the **Loading Advice - Sales User**
  permset). Option (b) `stripInaccessible` is **deferred to a security review** because a
  stripped _required_ field would read back as "missing" and break the ask-loop — and (b)
  would require fixing the Sales-User permset FLS at the same time.
- **`Agent_ResolveAccount` runs `with sharing`**, and **Account OWD = Private**. So a sales rep
  only resolves accounts **shared to them**; for a non-admin UAT pass, test with an account the
  rep **owns**. (Not a code change — handover note.)
- Object/field access for non-admin sales users comes via the **Loading Advice - Sales User**
  permission set (grants LA/Line/Opp/Order CRUD; assign it before any non-admin pass).

## Intent routing (Phase 5.1)

- `AgentIntentRouter.classify(text)` runs at the **top of `advance()`, idle-only
  (`phase==COLLECTING`), BEFORE the create parser**, so read-only questions ("list orders for
  X", "what does a loading advice need") are never hijacked by the parser's `for <name>`
  extractor. Pluggable seam: `AgentIntentClassifier` interface + `RuleBasedIntentClassifier`,
  selected via `Agent_Setting__mdt.Default.Active_Intent_Classifier` (LLM-swappable, mirrors
  the parser seam). `ACCOUNT_INSIGHT` → `Agent_GetAccountInsight`; `OBJECT_INFO` →
  `Agent_DescribeObject`/curated list. Insight handlers are read-only and never mutate
  create-chain state. (Post-submit state already resets to fresh `COLLECTING` — verified, not a bug.)

### Known v1 limitation: intent-in-context follow-ups

- **4th data point — RESOLVED (implemented, not deferred to Phase 6):** the utility-bar
  insight-account follow-up. Originally: `how many orders on Test Olam account` classified as
  `ACCOUNT_INSIGHT` but `extractInsightAccount()` only matched `for`/`related to`, so `on …
account` was missed and the read-only `Which account?` left state at `COLLECTING` → the bare
  `Test Olam` follow-up fell into the create `AWAITING_ACCOUNT`. **Fix shipped:** new phase
  `PHASE_AWAITING_INSIGHT_ACCOUNT` (routed before the intent gate) so the bare-name reply is
  resolved as the insight account and run through `Agent_GetAccountInsight` (read-only, never
  persisted into create state, returns to `COLLECTING`); `extractInsightAccount()` widened to
  `on <name>` too. Not-found/ambiguous re-asks and stays in the insight wait. Regression tests
  added; 95 Agent tests green. (Same root pattern as `AWAITING_ACCOUNT` / disambiguation — the
  reply's meaning depends on what the agent just asked, now persisted for the insight path.)
- **5th-7th data points: capture-echo replay surfaced the same root pattern on create turns**
  (rule parser misses natural phrasing / controller does not treat corrections as contextual
  edits). Replayed 2026-06-01, no build/deploy:
  - **Echo gap, fix-priority:** after the agent asks for account, `Test o` resolves to
    `Test Olam` via `Agent_ResolveAccount`'s partial `LIKE '%Test o%'` fallback
    (`Resolved account "Test Olam" (partial match).`). The next echo showed
    `Commercial · BITUMEN 60/70 · Qty 50 MT · Price ₦450,000/MT · Location Kano` but did
    **not** show the resolved account, even though state had `accountId=Test Olam`. This is
    risky because short fragments can win silently. Small v1-safe proposed fix: prepend the
    resolved account name in `captureEcho()` (for example `Account Test Olam`) whenever
    `st.accountId` is set.
  - **Silent load-type retention:** replayed turn 1 `commercial`, then later
    `stock transfer, 50 MT to Kaduna`. Quantity changed to `50`, but `typeOfLoad` stayed
    `Commercial` because `handleCollecting()` only sets load type when `st.typeOfLoad == null`.
    The echo correctly exposed the retained value (`Commercial`), but the user correction was
    ignored. Small v1-safe proposed fix: allow explicit later `Commercial`/`Stock Transfer`
    mentions to overwrite `st.typeOfLoad` (ideally with the echo making the new value visible).
  - **Parser phrasing gaps to keep for Phase 6, not regex-widen tonight:** `2 weeks from now`
    did not parse as a date; field-label-shaped answers copied from the missing list
    (`Order: today`, `Loading Advice Line: Lagos`) did not parse; bare `to Kaduna` did not
    parse as location (same as earlier `to Warri`); `xx` was correctly rejected as an invalid
    Customer Type picklist value.

## Rule-based parser — verified v1 limits (Phase-6 candidates)

Confirmed by replay (a value not echoed earlier made some forms look like they "didn't parse"
— corrected here):

- **Price** accepted forms: `NGN…`/`N…`/`₦…`-prefixed, `price <n>`, `at <n>`, `@ <n>`, optional
  `/MT`; value must be **≥1000**. NOT accepted: bare number (`450000`, `450,000`), `…k`
  shorthand (`470k`). Widening these → Phase 6 (regex-widening now risks false matches).
- **Quantity**: both `30 MT` and `30MT` parse (space optional); decimals ok (`1.5 MT`).
- **Location**: needs a cue (`deliver to` / `delivery to` / `location:`); bare `to X` is
  ignored; a second place after a valid one (`deliver to Kano via Lago`) is correctly ignored.
- **Transparency (fixed):** parsed values were merged silently → silent-overwrite (last value
  wins) and silent-retention (a non-parsing correction keeps the prior value). Fixed by the
  **capture-echo** (controller prepends "Got it so far: …" to every "still needed" prompt so
  each parse is visible). Richer NL formats remain a Phase-6 (LLM parser) item.

## TODO / known debt

- **Legacy PDF classes now have tests** (commit `8cf1f92`): `LoadingAdvicePDFGenerator` 97%,
  `GenerateStockTransferPDF` 97%, `LoadingAdvicePDFExtension` 94%; org-wide 75%→79%, every class
  ≥75% so a validated/production deploy is no longer blocked by them. Sandbox deploys still use
  `--test-level NoTestRun` by **deliberate** choice; switching to `RunLocalTests`/`RunSpecifiedTests`
  is now possible (a conscious decision, not automatic).
- **Optional follow-up — Customer Type not on the LA PDF (template-only, NOT agent/code):**
  the agent captures + stores Customer Type on the Line (`CustomerType_DKL__c`, verified e.g.
  LA 0456 = `Credit`), but `LoadingAdvicePDFTemplate` (VF) has no column for it. If the client
  wants it on the printed LA, that's a one-column VF template change — separate from the agent,
  which sets the field correctly. Client's call; do not build unless asked.
- **Optional follow-up — header `ProductFamily_DKL__c` blank (client design call, do not build):**
  the agent leaves the LA header `ProductFamily_DKL__c` blank (value is on the Line via
  `Product2.Family`, and the PDF derives it from the Line — verified LA 0456: header null, line
  "Bitumen 60/70"). It's an editable picklist (no formula/rollup), so it only fills if written.
  Populate the header ONLY if the client reports/filters Loading Advices by Product Family on
  the header object — then either the agent sets `laFields.ProductFamily_DKL__c` from the
  product's family at commit, or a client flow mirrors it from the line. If family is only ever
  needed via Line/PDF, blank is fine.

## Status

- Step 2 (schema) ✅ · Phase 1 (read-only services) ✅ · Phase 2 (sales chain) ✅ ·
  Phase 3 (headless auto-approval) ✅ · Phase 4 (NL parser + stateless conversation
  controller) ✅ — all deployed to gb-partialsb; 58 Agent tests pass, new code ≥90%.
  Next: Phase 5 (LWC `gbSalesAgent` on utility bar + Account page).
- **Phase 4 pieces:** `AgentPromptParser` interface + `AgentContext`/`AgentParseResult`;
  `Agent_Setting__mdt.Default.Active_Parser` + `AgentParserFactory` (LLM-swappable seam,
  defaults to rule-based); `RuleBasedPromptParser` (qty/price regex, load-type keywords,
  fuzzy Account/Product, picklist + light date parsing; ambiguous → `unresolved`, never
  guesses); `AgentConversationController.advance(text, stateJson, pageAccountId)` — stateless
  turn machine (COLLECTING → AWAITING_CONFIRM → PENDING_SUBMIT). The confirm turn commits
  (txn 1) and sets `autoContinue`; the LWC calls `advance` again to submit (txn 2) — honoring
  the separate-transaction PDF constraint.
