# Gradient Bitumen — Org Schema (Step 2)

**Source org:** `gb-partialsb` (sandbox, `maren@dkloudconsulting.compartialsb`, Org Id `00Dct000004upaDEAQ`)
**Captured:** 2026-06-01 via `sf sobject describe` (raw JSON in [docs/raw/](raw/)) + `sf project retrieve start` for field/object/recordType/flow XML (in [force-app/main/default/](../force-app/main/default/)). API v66.0.
**Not from memory** — every field, type, picklist, and relationship below is read directly from the org describe and metadata XML.

## Legend for the "Required" column
- **Yes** = must be supplied at create (`nillable=false`, `createable=true`, no default). Insert fails without it.
- **Auto** = `nillable=false` but auto-defaulted at create (e.g. OwnerId, CurrencyIsoCode) — you don't need to supply it.
- **No** = optional at the API/DB level (`nillable=true`). *May still be enforced by a UI screen/flow* — see notes.
- **—(sys)** = system/read-only field (not createable).

Picklist column lists the active values; for lookups it shows `→ Target`.

---

## 1. Relationship map

```
Account ◄──(lookup, AccountId)── Opportunity
Account ◄──(lookup, AccountId)── Order
Opportunity ◄──(lookup, OpportunityId)── Order
Order ◄══(MASTER-DETAIL, Order_DKL__c)══ Loading_Advice__c
Loading_Advice__c ◄══(MASTER-DETAIL, LoadingAdvice_DKL__c)══ Loading_Advice_Line__c

Loading_Advice__c also has lookups: Account_DKL__c → Account, Opportunity_DKL__c → Opportunity
Loading_Advice_Line__c also has lookups: Customer_DKL__c → Account, Product_DKL__c → Product2,
                                         OrderProduct_DKL__c → OrderItem
```

### Confirmation of the proposed relationships

| Proposed | Verdict | Evidence |
|---|---|---|
| Opportunity → Account (lookup) | ✅ **Confirmed — lookup** | `Opportunity.AccountId` type=reference, `nillable=true`, standard lookup |
| Order → Opportunity (lookup) | ✅ **Confirmed — lookup** | `Order.OpportunityId` type=reference, `nillable=true` |
| Order → Account (lookup) | ✅ **Confirmed — lookup** | `Order.AccountId` type=reference, `nillable=true` *(but see Q1 note — platform-enforced at insert)* |
| Loading_Advice__c → Order = **MASTER-DETAIL?** | ✅ **Confirmed — MASTER-DETAIL** | Field XML `Order_DKL__c`: `<type>MasterDetail</type>`, `reparentableMasterDetail=false`, parent child-rel `cascadeDelete=true`. Field is `nillable=false`, `createable=true`, `updateable=false` (cannot reparent). |
| Loading_Advice_Line__c → Loading_Advice__c = **MASTER-DETAIL?** | ✅ **Confirmed — MASTER-DETAIL** | Field XML `LoadingAdvice_DKL__c`: `<type>MasterDetail</type>`, `reparentableMasterDetail=false`, `cascadeDelete=true`, `nillable=false`, `updateable=false`. |

**Consequence for Phase 1 (headless create order):** because both links are master-detail and non-reparentable, records must be created **parent-first** and the master Id supplied at insert: `Order` → `Loading_Advice__c` (with `Order_DKL__c`) → `Loading_Advice_Line__c` (with `LoadingAdvice_DKL__c`). You cannot insert a child first or move it later.

> Note: `Account → Opportunity` and `Account → Order` show `cascadeDelete=true` on the Account child-relationships. That is standard Account delete-cascade behaviour, **not** master-detail — the FK fields themselves are nillable lookups.

---

## 1a. Curated business-required fields — SOURCE OF TRUTH for `missingFields`

**These are the fields the agent must treat as required when validating / reporting `missingFields` — NOT the DB `nillable` flag.** The DB only enforces `Customer_DKL__c` + the master-detail link; everything else below is a *business* requirement carried over from the "Create Loading Advice" screen. Phase 1/2 validation logic keys off this list, not off describe.

| # | Business field | Object.API name | Type | DB `nillable=false`? |
|---|---|---|---|---|
| 1 | Customer | `Loading_Advice_Line__c.Customer_DKL__c` (→ Account) | reference | ✅ **Yes** |
| 2 | Customer Type | `Loading_Advice_Line__c.CustomerType_DKL__c` | picklist (Advance; Credit) | No |
| 3 | Location | `Loading_Advice_Line__c.Location_DKL__c` | text | No |
| 4 | Product | `Loading_Advice_Line__c.Product_DKL__c` (→ Product2) | reference | No |
| 5 | Quantity (MT) | `Loading_Advice_Line__c.QuantityMT_DKL__c` | double | No |
| 6 | Price (N/MT) | `Loading_Advice_Line__c.PricePerMT_DKL__c` | currency | No |

Plus the structural must-supply (master-detail, always required at insert):
- `Loading_Advice__c.Order_DKL__c` → Order (master-detail, `nillable=false`)
- `Loading_Advice_Line__c.LoadingAdvice_DKL__c` → Loading_Advice__c (master-detail, `nillable=false`)
- `Loading_Advice__c.RecordTypeId` (set from the Type of Load mapping in §1b)

> **Key point:** at the DB level only `Customer_DKL__c` and the two master-detail fields are `nillable=false`. Items 2–6 are DB-optional but **business-required**, so the agent's `missingFields` check must use *this curated list*, not the schema's nillable flags. (Price is not meaningful for Stock Transfer loads — see §1b.)

## 1b. Type of Load → RecordType mapping (used by `Agent_CommitLoadingAdvice` in Phase 2)

`Loading_Advice__c` has two record types. Phase 2 sets `RecordTypeId` by resolving the developer name from the user-supplied "Type of Load":

| Type of Load (input) | RecordType DeveloperName | RecordType Label | Pricing relevant? |
|---|---|---|---|
| Commercial | `Commercial_DKL` | Commercial | Yes (Price N/MT required) |
| Stock Transfer | `StockTransfer_DKL` | StockTransfer | No (internal movement, no pricing/revenue) |

`Agent_CommitLoadingAdvice` will look up `RecordType` where `SObjectType='Loading_Advice__c'` and `DeveloperName` = the mapped value, and set `RecordTypeId` on the header. Default to `Commercial_DKL` if unspecified (matches `LoadingAdvicePDFExtension` fallback).

---

## 2. The two answers you asked for up front

### Q1 — Which Order fields are truly mandatory at creation?
Only **two** Order fields are must-supply at insert (nillable=false, createable, no default):

| Field | Label | Type | Notes |
|---|---|---|---|
| `EffectiveDate` | **Order Start Date** | date | Required. (Note: it's *Start Date*, labelled accordingly; there is also an optional `EndDate`.) |
| `Status` | Status | picklist | Required. Values: Draft; Activated; Hold; Fulfilled/Closed; Cancelled. New orders start as **Draft**. |

Auto-defaulted (don't supply): `OwnerId`, `CurrencyIsoCode` (defaults NGN), `IsReductionOrder`.

**`AccountId` caveat (important):** the describe reports `Order.AccountId` as `nillable=true`, i.e. the *metadata* does not mark it required. **However**, the standard Order object enforces an Account at the platform level — inserting an Order with no `AccountId` (and no `ContractId`) raises `REQUIRED_FIELD_MISSING`. **Treat `AccountId` as mandatory in Phase 1.** I'll verify the exact insert contract empirically when we build (the instruction was no Apex yet, so this is flagged rather than tested).

**`OrderQuantity_DKL__c` (custom "Order Quantity"):** `nillable=true` at the DB level — *not* enforced by metadata. If the business rule is "quantity required on an order", that is currently a UI/screen rule, not a schema constraint. Worth confirming whether we must populate it for the downstream rollups (`RemainingQuantity_DKL__c`, `TotalQuantityDispatched_DKL__c` are formula/rollup, read-only).

There is **no** standard `Quantity` field on Order itself (quantity lives on OrderItems / on the Loading Advice Line `QuantityMT_DKL__c`).

### Q2 — Commercial vs Stock Transfer: which PDF / Apex class fires?

`Loading_Advice__c` has two **record types**: `Commercial_DKL` (label "Commercial") and `StockTransfer_DKL` (label "Stock Transfer"). The routing is **not** inside the Apex — it's a decision in the **`LA_Approve_Reject`** flow named `Commercial_Or_Stock_Transfer`:

```
IF  Get_LA_Header.RecordType.DeveloperName == 'Commercial_DKL'
        → invocable Apex  LoadingAdvicePDFGenerator   (VF page: LoadingAdvicePDFTemplate)
ELSE (StockTransfer_DKL / default)
        → invocable Apex  GenerateStockTransferPDF    (VF page: StockTransferDispatchPDF)
```

| Record type | Apex invocable | Visualforce page | Output title / file |
|---|---|---|---|
| **Commercial** (`Commercial_DKL`) | `LoadingAdvicePDFGenerator.generatePDFAndAttach` | `LoadingAdvicePDFTemplate` | "`<Product>` Loading Advice - `<Name>` - `<dd.MM.yyyy>`" |
| **Stock Transfer** (`StockTransfer_DKL`) | `GenerateStockTransferPDF.generatePDF` | `StockTransferDispatchPDF` | "`<Product>` Stock Transfer Dispatch - `<Name>` - `<dd.MM.yyyy>`" |

- `LoadingAdvicePDFExtension` is the **VF controller extension** used by the PDF pages (queries the LA header + lines; reads `RecordType.DeveloperName`, **defaults to `Commercial_DKL`** if null). It is not record-type-routed itself.
- The **Submit-for-Approval** flow (initial submission) always calls `LoadingAdvicePDFGenerator` (Commercial template) for the review email; the Commercial-vs-StockTransfer split happens later in `LA_Approve_Reject` at final approval/dispatch.
- Both classes attach the result as a `ContentVersion` with `FirstPublishLocationId = <LA Id>`.

---

## 3. Field tables


### 3.1 Loading_Advice__c (header)

| API name | Label | Type | Required | Picklist values / lookup |
|---|---|---|---|---|
| `Id` | Record ID | id | —(sys) |  |
| `IsDeleted` | Deleted | boolean | —(sys) |  |
| `Name` | Loading Advice Name | string(80) | —(sys) |  |
| `CurrencyIsoCode` | Currency ISO Code | picklist | No | NGN; USD |
| `RecordTypeId` | Record Type ID | reference | No | → RecordType |
| `CreatedDate` | Created Date | datetime | —(sys) |  |
| `CreatedById` | Created By ID | reference | —(sys) | → User |
| `LastModifiedDate` | Last Modified Date | datetime | —(sys) |  |
| `LastModifiedById` | Last Modified By ID | reference | —(sys) | → User |
| `SystemModstamp` | System Modstamp | datetime | —(sys) |  |
| `LastViewedDate` | Last Viewed Date | datetime | No |  |
| `LastReferencedDate` | Last Referenced Date | datetime | No |  |
| `Order_DKL__c` | Order | reference | **Yes** | → Order |
| `Account_DKL__c` | Account | reference | No | → Account |
| `Approval_Status_DKL__c` | Approval Status | picklist | No | Draft; Approved; Rejected; Not Submitted; Pending 1st Approver; Pending 2nd Approver; Pending 3rd Approver |
| `CurrentApprover_DKL__c` | Current Approver | reference | No | → User |
| `DeliveredQuantity_DKL__c` | Delivered Quantity | double | No |  |
| `DeliveredlAmount_DKL__c` | Delivered Amount | currency | No |  |
| `DispatchPDFContentDocumentId_DKL__c` | Dispatch PDF ContentDocumentId | string(18) | No |  |
| `DiversionReason_DKL__c` | Diversion Reason | textarea(32768) | No |  |
| `DivertedFrom_DKL__c` | Diverted From | reference | No | → Loading_Advice__c |
| `DriverName_DKL__c` | Driver Name | string(255) | No |  |
| `DriverPhoneNo_DKL__c` | Driver Phone No | phone(40) | No |  |
| `FinanceApprovedBy_DKL__c` | Finance Approved By | reference | No | → User |
| `FinanceApprovedOn_DKL__c` | Finance Approved On | datetime | No |  |
| `LoadingAdviceNumber_DKL__c` | Loading Advice Number | string(50) | No |  |
| `LogisticsEmailSent_DKL__c` | Logistics Email Sent | boolean | Auto |  |
| `Opportunity_DKL__c` | Opportunity | reference | No | → Opportunity |
| `ProductFamily_DKL__c` | Product Family | picklist | No | Bitumen 60/70; Bituminous Emulsion |
| `RevisedDocumentNeeded_DKL__c` | Revised Document Needed | boolean | Auto |  |
| `Status_DKL__c` | Status | picklist | No | Draft; Active; Diverted; Superseded; Cancelled |
| `SubmittedOn_DKL__c` | Submitted On | datetime | No |  |
| `Submittedby_DKL__c` | Submitted by | reference | No | → User |
| `SupersededBy_DKL__c` | Superseded By | reference | No | → Loading_Advice__c |
| `TruckPlateNo_DKL__c` | Truck Plate No | string(8) | No |  |
| `VersionNumber_DKL__c` | Version Number | double | No |  |
| `WaybillNumber_DKL__c` | Waybill Number | string(50) | No |  |
| `X1ApprovedBy_DKL__c` | 1st Approved By | reference | No | → User |
| `X1stApprovedOn_DKL__c` | 1st Approved On | datetime | No |  |
| `X2ndApprovedBy_DKL__c` | 2nd Approved By | reference | No | → User |
| `X2ndApprovedOn_DKL__c` | 2nd Approved On | datetime | No |  |
| `RollUpAmount_DKL__c` | Roll Up Amount | currency | No |  |
| `RollUpQuantity_DKL__c` | Roll Up Quantity | double | No |  |
| `Comments_DKL__c` | Comments | textarea(32768) | No |  |

> **Create-time required:** only `Order_DKL__c` (master-detail) is must-supply. `RecordTypeId` is not flagged required by describe but **must be set** to pick Commercial vs Stock Transfer behaviour. `Name` is an auto-number/standard Name. Approval/audit fields (`Approval_Status_DKL__c`, `Status_DKL__c`, `Submitted*`, `X1/X2/Finance Approved*`, `LoadingAdviceNumber_DKL__c`) are populated by the flows, not at create.

### 3.2 Loading_Advice_Line__c

| API name | Label | Type | Required | Picklist values / lookup |
|---|---|---|---|---|
| `Id` | Record ID | id | —(sys) |  |
| `IsDeleted` | Deleted | boolean | —(sys) |  |
| `Name` | Loading Advice Line Name | string(80) | —(sys) |  |
| `CurrencyIsoCode` | Currency ISO Code | picklist | No | NGN; USD |
| `CreatedDate` | Created Date | datetime | —(sys) |  |
| `CreatedById` | Created By ID | reference | —(sys) | → User |
| `LastModifiedDate` | Last Modified Date | datetime | —(sys) |  |
| `LastModifiedById` | Last Modified By ID | reference | —(sys) | → User |
| `SystemModstamp` | System Modstamp | datetime | —(sys) |  |
| `LastActivityDate` | Last Activity Date | date | No |  |
| `LastViewedDate` | Last Viewed Date | datetime | No |  |
| `LastReferencedDate` | Last Referenced Date | datetime | No |  |
| `LoadingAdvice_DKL__c` | Loading Advice | reference | **Yes** | → Loading_Advice__c |
| `CustomerType_DKL__c` | Customer Type | picklist | No | Advance; Credit |
| `Customer_DKL__c` | Customer | reference | **Yes** | → Account |
| `DeliveredAmount_DKL__c` | Delivered Amount | currency | No |  |
| `DeliveredQuantity_DKL__c` | Delivered Quantity | double | No |  |
| `DeliveryMode_DKL__c` | Delivery Mode | picklist | No | Gradient Delivery; Self Collection; 3rd Party Transport; Other |
| `HeatingPerTruck_DKL__c` | Heating Charge (N/Truck) | currency | No |  |
| `LPO_Number__c` | LPO Number | string(80) | No |  |
| `Location_DKL__c` | Location | string(255) | No |  |
| `NumberofSprayerDays_DKL__c` | Number of Sprayer Days | double | No |  |
| `OrderProduct_DKL__c` | Order Product | reference | No | → OrderItem |
| `PaymentStatusText_DKL__c` | Payment Status | string(255) | No |  |
| `PaymentTerm_DKL__c` | Payment Term | picklist | No | Advance; Credit; Free Supply |
| `PricePerMT_DKL__c` | Price (N/MT) | currency | No |  |
| `Product_DKL__c` | Product | reference | No | → Product2 |
| `QuantityMT_DKL__c` | Quantity (MT) | double | No |  |
| `Site_DKL__c` | Site | string(255) | No |  |
| `SprayerRate_DKL__c` | Sprayer Rate (N/MT) | currency | No |  |
| `State_DKL__c` | State | string(80) | No |  |
| `TransportationPerMT_DKL__c` | Transportation (N/MT) | currency | No |  |
| `ActualQuantity_DKL__c` | Actual Quantity | double | No |  |
| `CreditPeriod_DKL__c` | Credit Period | string(1300) | No |  |
| `CustomerCal_DKL__c` | Customer Cal | string(1300) | No |  |
| `GrandTotal_DKL__c` | Total Invoice Value | currency | No |  |
| `ProductCalc_DKL__c` | Product Calc | string(1300) | No |  |
| `ProductSubtotal_DKL__c` | Product Subtotal | currency | No |  |
| `ProductTotal_DKL__c` | Product Total | currency | No |  |
| `SignedActualAmount_DKL__c` | Signed Actual Amount | currency | No |  |
| `SignedActualQuantity_DKL__c` | Signed Actual Quantity | double | No |  |
| `PlantLocation_DKL__c` | Plant Location | picklist | No | Kaduna; Warri |

> **Create-time required (DB):** `LoadingAdvice_DKL__c` (master-detail) and `Customer_DKL__c` (nillable=false). **Screen-required but DB-optional** (the "Create Loading Advice" screen forces these, the schema does not): `CustomerType_DKL__c`, `Location_DKL__c`, `Product_DKL__c`, `QuantityMT_DKL__c`, `PricePerMT_DKL__c`. See §3.5 cross-check.

### 3.3 Order

| API name | Label | Type | Required | Picklist values / lookup |
|---|---|---|---|---|
| `Id` | Order ID | id | —(sys) |  |
| `OwnerId` | Owner ID | reference | Auto | → Group,User |
| `ContractId` | Contract ID | reference | No | → Contract |
| `AccountId` | Account ID | reference | No | → Account |
| `Pricebook2Id` | Price Book ID | reference | No | → Pricebook2 |
| `OriginalOrderId` | Order ID | reference | No | → Order |
| `OpportunityId` | Opportunity ID | reference | No | → Opportunity |
| `EffectiveDate` | Order Start Date | date | **Yes** |  |
| `EndDate` | Order End Date | date | No |  |
| `IsReductionOrder` | Reduction Order | boolean | Auto |  |
| `Status` | Status | picklist | **Yes** | Draft; Activated; Hold; Fulfilled/Closed; Cancelled |
| `Description` | Description | textarea(32000) | No |  |
| `CustomerAuthorizedById` | Customer Authorized By ID | reference | No | → Contact |
| `CompanyAuthorizedById` | Company Authorized By ID | reference | No | → User |
| `Type` | Order Type | picklist | No |  |
| `BillingStreet` | Billing Street | textarea(255) | No |  |
| `BillingCity` | Billing City | string(40) | No |  |
| `BillingState` | Billing State/Province | string(80) | No |  |
| `BillingPostalCode` | Billing Zip/Postal Code | string(20) | No |  |
| `BillingCountry` | Billing Country | string(80) | No |  |
| `BillingStateCode` | Billing State Code | picklist | No | NGAB; CMAD; NGAD; NGAK; NGAN; CDBU; NGBA; NGBY; NGBE; NGBO; CMCN; NGCR; NGDE; CMES; NGEB; NGED; NGEK; NGEN; CDEQ; CMFN; NGFCT; NGGO; CDHK; CDHL; CDHU; NGIM; CDIT; NGJG; NGKD; NGKN; CDKA; CDKC; CDKO; NGKT; NGKB; CDKI; NGKO; CDKCEN; CDKW; NGKW; CDKWI; NGLA; CMLT; CDLO; CDMN; CDMA; CDMO; NGNA; NGNI; CDNK; CDNU; CMNO; CMNW; NGOG; NGON; NGOS; NGOY; NGPL; NGRI; CDSA; NGSO; CMSO; CMSW; CDSK; CDSU; CDTA; NGTA; CDTS; CDTP; CMWE; NGYO; NGZA |
| `BillingCountryCode` | Billing Country Code | picklist | No | CM; CD; NG |
| `BillingLatitude` | Billing Latitude | double | No |  |
| `BillingLongitude` | Billing Longitude | double | No |  |
| `BillingGeocodeAccuracy` | Billing Geocode Accuracy | picklist | No | Address; NearAddress; Block; Street; ExtendedZip; Zip; Neighborhood; City; County; State; Unknown |
| `BillingAddress` | Billing Address | address | No |  |
| `ShippingStreet` | Shipping Street | textarea(255) | No |  |
| `ShippingCity` | Shipping City | string(40) | No |  |
| `ShippingState` | Shipping State/Province | string(80) | No |  |
| `ShippingPostalCode` | Shipping Zip/Postal Code | string(20) | No |  |
| `ShippingCountry` | Shipping Country | string(80) | No |  |
| `ShippingStateCode` | Shipping State Code | picklist | No | NGAB; CMAD; NGAD; NGAK; NGAN; CDBU; NGBA; NGBY; NGBE; NGBO; CMCN; NGCR; NGDE; CMES; NGEB; NGED; NGEK; NGEN; CDEQ; CMFN; NGFCT; NGGO; CDHK; CDHL; CDHU; NGIM; CDIT; NGJG; NGKD; NGKN; CDKA; CDKC; CDKO; NGKT; NGKB; CDKI; NGKO; CDKCEN; CDKW; NGKW; CDKWI; NGLA; CMLT; CDLO; CDMN; CDMA; CDMO; NGNA; NGNI; CDNK; CDNU; CMNO; CMNW; NGOG; NGON; NGOS; NGOY; NGPL; NGRI; CDSA; NGSO; CMSO; CMSW; CDSK; CDSU; CDTA; NGTA; CDTS; CDTP; CMWE; NGYO; NGZA |
| `ShippingCountryCode` | Shipping Country Code | picklist | No | CM; CD; NG |
| `ShippingLatitude` | Shipping Latitude | double | No |  |
| `ShippingLongitude` | Shipping Longitude | double | No |  |
| `ShippingGeocodeAccuracy` | Shipping Geocode Accuracy | picklist | No | Address; NearAddress; Block; Street; ExtendedZip; Zip; Neighborhood; City; County; State; Unknown |
| `ShippingAddress` | Shipping Address | address | No |  |
| `ActivatedDate` | Activated Date | datetime | No |  |
| `ActivatedById` | Activated By ID | reference | No | → User |
| `StatusCode` | Status Category | picklist | —(sys) | Draft; Activated; Canceled; Expired; Superseded |
| `CurrencyIsoCode` | Currency ISO Code | picklist | Auto | NGN; USD |
| `OrderNumber` | Order Number | string(30) | —(sys) |  |
| `TotalAmount` | Order Amount | currency | —(sys) |  |
| `CreatedDate` | Created Date | datetime | —(sys) |  |
| `CreatedById` | Created By ID | reference | —(sys) | → User |
| `LastModifiedDate` | Last Modified Date | datetime | —(sys) |  |
| `LastModifiedById` | Last Modified By ID | reference | —(sys) | → User |
| `IsDeleted` | Deleted | boolean | —(sys) |  |
| `SystemModstamp` | System Modstamp | datetime | —(sys) |  |
| `LastViewedDate` | Last Viewed Date | datetime | No |  |
| `LastReferencedDate` | Last Referenced Date | datetime | No |  |
| `OrderQuantity_DKL__c` | Order Quantity | double | No |  |
| `TotalDispatchedValue_DKL__c` | Total Dispatched Value | currency | No |  |
| `TotalOrderDispatched_DKL__c` | Total Order Dispatched | double | No |  |
| `RemainingQuantity_DKL__c` | Remaining Quantity | double | No |  |
| `TotalDispatchedAmount_DKL__c` | Total Dispatched Amount | currency | No |  |
| `TotalQuantityDispatched_DKL__c` | Total Quantity Dispatched | double | No |  |

### 3.4 Opportunity

| API name | Label | Type | Required | Picklist values / lookup |
|---|---|---|---|---|
| `Id` | Opportunity ID | id | —(sys) |  |
| `IsDeleted` | Deleted | boolean | —(sys) |  |
| `AccountId` | Account ID | reference | No | → Account |
| `RecordTypeId` | Record Type ID | reference | No | → RecordType |
| `IsPrivate` | Private | boolean | Auto |  |
| `Name` | Name | string(120) | **Yes** |  |
| `Description` | Description | textarea(32000) | No |  |
| `StageName` | Stage | picklist | **Yes** | Qualification; Site visit done; Data collected; In progress; Proposal submitted; LNGSPA Submitted; Negotiation; Closed Won; Under construction; Equipments ordered; Work in progress; Operational; Closed Lost |
| `Amount` | Amount | currency | No |  |
| `Probability` | Probability (%) | percent | No |  |
| `ExpectedRevenue` | Expected Amount | currency | No |  |
| `TotalOpportunityQuantity` | Quantity | double | No |  |
| `CloseDate` | Close Date | date | **Yes** |  |
| `Type` | Opportunity Type | picklist | No | Existing Business; New Business |
| `NextStep` | Next Step | string(255) | No |  |
| `LeadSource` | Lead Source | picklist | No | Cold Calls; Site Visit; References; Customer Event; Employee Referral; External Referral; Google AdWords; Other; Partner; Purchased List; Trade Show; Webinar; Website |
| `IsClosed` | Closed | boolean | —(sys) |  |
| `IsWon` | Won | boolean | —(sys) |  |
| `ForecastCategory` | Forecast Category | picklist | —(sys) | Omitted; Pipeline; BestCase; MostLikely; Forecast; Closed |
| `ForecastCategoryName` | Forecast Category | picklist | No | Omitted; Pipeline; Best Case; Commit; Closed |
| `CurrencyIsoCode` | Opportunity Currency | picklist | No | NGN; USD |
| `CampaignId` | Campaign ID | reference | No | → Campaign |
| `HasOpportunityLineItem` | Has Line Item | boolean | —(sys) |  |
| `Pricebook2Id` | Price Book ID | reference | No | → Pricebook2 |
| `OwnerId` | Owner ID | reference | Auto | → User |
| `CreatedDate` | Created Date | datetime | —(sys) |  |
| `AgeInDays` | Age | int | No |  |
| `CreatedById` | Created By ID | reference | —(sys) | → User |
| `LastModifiedDate` | Last Modified Date | datetime | —(sys) |  |
| `LastModifiedById` | Last Modified By ID | reference | —(sys) | → User |
| `SystemModstamp` | System Modstamp | datetime | —(sys) |  |
| `LastActivityDate` | Last Activity | date | No |  |
| `LastActivityInDays` | Recent Activity | int | No |  |
| `PushCount` | Push Count | int | No |  |
| `LastStageChangeDate` | Last Stage Change Date | datetime | No |  |
| `LastStageChangeInDays` | Days In Stage | int | No |  |
| `FiscalQuarter` | Fiscal Quarter | int | No |  |
| `FiscalYear` | Fiscal Year | int | No |  |
| `Fiscal` | Fiscal Period | string(6) | No |  |
| `ContactId` | Contact ID | reference | No | → Contact |
| `LastViewedDate` | Last Viewed Date | datetime | No |  |
| `LastReferencedDate` | Last Referenced Date | datetime | No |  |
| `SyncedQuoteId` | Quote ID | reference | No | → Quote |
| `ContractId` | Contract ID | reference | No | → Contract |
| `HasOpenActivity` | Has Open Activity | boolean | —(sys) |  |
| `HasOverdueTask` | Has Overdue Task | boolean | —(sys) |  |
| `LastAmountChangedHistoryId` | Opportunity History ID | reference | No | → OpportunityHistory |
| `LastCloseDateChangedHistoryId` | Opportunity History ID | reference | No | → OpportunityHistory |
| `IsPriorityRecord` | Important | boolean | —(sys) |  |
| `ContractDaysYear_DKL__c` | Contract Days/Year | double | No |  |
| `DiscoveryCompleted_DKL__c` | Discovery Completed | boolean | Auto |  |
| `ROIAnalysisCompleted_DKL__c` | ROI Analysis Completed | boolean | Auto |  |
| `Business_Unit_DKL__c` | Business Unit | picklist | No | Greenville LNG; Gradient |
| `LossReason_DKL__c` | Loss Reason | picklist | No | Lost to Competitor; No Budget / Lost Funding; No Decision / Non-Responsive; Price; CAPEX concern; Delayed decision; Cheaper alternative; Other |
| `DaysSinceLastActivity_DKL__c` | Days Since Last Activity | double | No |  |
| `ProposalType_DKL__c` | Proposal Type | picklist | No | RE; Firm |
| `Primary_Contact_DKL__c` | Primary Contact | reference | No | → Contact |
| `TankCapacityM_DKL__c` | Tank Capacity (m³) | double | No |  |
| `SiteVisitDate_DKL__c` | Site Visit Date | date | No |  |
| `ExchangeRateNairaperUS_DKL__c` | Exchange Rate (Naira per USD) | string(80) | No |  |
| `Industry_DKL__c` | Industry | string(1300) | No |  |
| `EstimatedLNGVolume_DKL__c` | Estimated LNG Quantity (MT/day) | double | No |  |
| `Service_DKL__c` | Service | reference | No | → Service_Catalog__c |
| `ShipTo_DKL__c` | Delivery Address | reference | No | → Delivery_Address__c |
| `DCQ_DKL__c` | DCQ(MT) | double | No |  |
| `EquipmentScope_DKL__c` | Equipment Scope | picklist | No | Greenville; Customer |
| `Contract_Duration_yr__c` | Contract Duration (yr) | double | No |  |
| `Contract_Duration_Unit__c` | Contract Duration (UOM) | picklist | No | Year; Months |
| `PotentialDailyRevenue_DKL__c` | Potential Daily Revenue | currency | No |  |
| `ExistingOrProposedCapacityOfHeating_DKL__c` | Existing or Proposed Capacity of Heating | double | No |  |
| `HighPriorityFlag_DKL__c` | High Priority Flag | boolean | —(sys) |  |
| `RegulatoryApproval_DKL__c` | Regulatory Approvals | picklist | No | Greenville; Customer |
| `CivilWorks_DKL__c` | Civil Works | picklist | No | Greenville; Customer |
| `CompetitorSupplierName_DKL__c` | Competitor Supplier(Name) | textarea(1000) | No |  |
| `CompetitorSupplierLocation_DKL__c` | Competitor Supplier(Location) | textarea(1000) | No |  |
| `ApplicationType_DKL__c` | Application Type | picklist | No | Heating; Transport; CPP; Power and Heating; Fuel |
| `EarthingandRelatedWorks_DKL__c` | Earthing and Related Works | picklist | No | Greenville; Customer |
| `AverageLoadHeating_DKL__c` | Average Load Heating (MJ/day) | double | No |  |
| `InstallationandCommissioning_DKL__c` | Installation and Commissioning | picklist | No | Greenville; Customer |
| `NoofTanks_DKL__c` | No of Tanks | double | No |  |
| `TOP_DKL__c` | TOP(% OF DCQ) | double | No |  |
| `MDQ_DKL__c` | MDQ(% of DCQ) | double | No |  |
| `Custom_Amount__c` | Amount | currency | No |  |
| `ContractDuration_DKL__c` | Contract Duration (yr) | string(226) | No |  |
| `PaymentSecurity_DKL__c` | Payment Security (Days) | string(226) | No |  |
| `Stage_Start_Date__c` | Stage Start Date | datetime | No |  |
| `InvoicingCycle_DKL__c` | Invoicing Cycle | string(226) | No |  |
| `VAT_DKL__c` | VAT (%) | string(226) | No |  |
| `AverageLoadPower_DKL__c` | Average Load Power (kWe) | double | No |  |
| `ExistingorProposedCapPower_DKL__c` | Existing/Proposed Cap Power (kWe) | double | No |  |
| `RegasCapacity_DKL__c` | Regas Capacity(Nm³/hr) | double | No |  |
| `ExistingorProposedCapacityheating_DKL__c` | Existing or Proposed Cap heating(MJ/day) | double | No |  |
| `HeatingEquipments_DKL__c` | Heating Equipments | textarea(255) | No |  |
| `Product_DKL__c` | Product | string(226) | No |  |
| `ProductionCapacity_DKL__c` | Production Capacity(TPD) | string(226) | No |  |
| `PlantArea_DKL__c` | Plant Area(m²) | string(226) | No |  |
| `PeakLoadHeating_DKL__c` | Peak Load Heating (MJ/hr) | double | No |  |
| `DCQ_UOM__c` | DCQ (UOM) | picklist | No | MT; MMBTU; kWh; SCM |
| `Projectduration_DKL__c` | Project duration (Months) | string(15) | No |  |
| `Capacityincrement_DKL__c` | Capacity Increment | double | No |  |
| `PeakLoadPower_DKL__c` | Peak Load Power(kWe) | double | No |  |
| `GoogleCoordinates_DKL__Latitude__s` | Google Coordinates (Latitude) | double | No |  |
| `GoogleCoordinates_DKL__Longitude__s` | Google Coordinates (Longitude) | double | No |  |
| `GoogleCoordinates_DKL__c` | Google Coordinates | location | No |  |
| `PlantRunning_DKL__c` | Plant Running(hrs/day) | string(226) | No |  |
| `MinTemperature_DKL__c` | Min Temperature(°C) | double | No |  |
| `ExistingAndInstalledCapacityGG_DKL__c` | Existing or Proposed Cap Power (kWe) | string(226) | No |  |
| `PeakLoadkW_DKL__c` | Peak Load (kW) | string(226) | No |  |
| `AverageLoadkW_DKL__c` | Average Load (kW) | double | No |  |
| `LeanLoadkW_DKL__c` | Lean Load (kWe) | double | No |  |
| `MaximumSpikeCurrentAmps_DKL__c` | Maximum Spike Current (amps) | double | No |  |
| `AveragekWh_DKL__c` | Average kWh req per month | double | No |  |
| `OperationalDGSetsCapacity_DKL__c` | Operational DG Sets (kVA) | string(18) | No |  |
| `Make_DKL__c` | Make | textarea(255) | No |  |
| `Seasonality_DKL__c` | Seasonality | string(226) | No |  |
| `RatedCap_DKL__c` | Rated Cap | string(226) | No |  |
| `MaxTemperature_DKL__c` | Max Temperature(°C) | double | No |  |
| `EquipmentDetails_DKL__c` | Equipment Details | picklist | No | Furnace; Kiln; Generator; Boiler; Chillers & HVAC; Turbine-Single/Combined; Ovens; Others - pls specify below |
| `TotalFuelDetails_DKL__c` | Total Fuel Details | double | No |  |
| `Other_DKL__c` | Other | string(226) | No |  |
| `RelativeHumidity_DKL__c` | Relative Humidity(%) | double | No |  |
| `AltitudeMetres_DKL__c` | Altitude (m) | double | No |  |
| `AverageWindSpeed_DKL__c` | Average Wind Speed (km/h) | double | No |  |
| `Breadthmetres_DKL__c` | Breadth (m) | double | No |  |
| `Lengthmetres_DKL__c` | Length (m) | double | No |  |
| `Reconciliationcycle_DKL__c` | Reconciliation Cycle | picklist | No | Fortnightly; Monthly; Quarterly; Half Yearly; Yearly |
| `Contract_Price_Unit__c` | Contract Price (Unit) | picklist | No | USD/MMBTU; USD/MT; USD/kWh; USD/SCM; NGN/SCM |
| `ContractPrice_DKL__c` | Contract Price | double | No |  |
| `MinimumDeliverableQuantity_DKL__c` | Minimum Deliverable Quantity (%) | double | No |  |
| `ExpectedPeriod_DKL__c` | Expected Time Of Start (MM/YYYY) | string(7) | No |  |
| `Payment_Option__c` | Payment Option | picklist | No | Advance; Arrears |
| `ContractStartDate_DKL__c` | Contract Start Date | date | No |  |
| `ContractEndDate_DKL__c` | Contract End Date | date | No |  |
| `City_DKL__c` | City | multipicklist | No | Abia; Adamawa; Anambra; Bauchi; Benue; Borno; Cross River; Delta; Edo; Enugu; Gombe; Jigawa; Kaduna; Kano; Katsina; Kebbi; Kogi; Kwara; Nasarawa; Niger; Ogun; Plateau; Rivers; Sokoto; Taraba; Yobe; Zamfara; New |
| `GVDeliveryHub_DKL__c` | GV Delivery Hub | multipicklist | No | Aba City; Numan; Yola Hub Station; Onistha Hub Station; Azare City Station; Bauchi Hub Station; Makurdi; BIU; Baga Road; Maiduguri City Station 1; Maiduguri City Station 2; Maiduguri Kano Road Hub Station; Akampa Hub Station; Asaba City Station; Benin Hub Station; Enugu Hub Station; Simplicity; Gombe Hub Station; Dutse; Command Junction; Kafanchan; Kakau; Kasu; Yuhassibu (Mando); Zaria; Kano Zaria road Hub Station; Airport Rd - Nomansland; Around Kwari Market; Ashamco; Bompai; Club Rd; Galaxy Station; Hadeja Rd; Independence Avenue; Kamaras; Katsina Rd; Mohibo; Sabon Gari; Sabon Gari - Nassarawa; Sharada Industrial Area Rd; Katsina Hub Station; Birnin Kebbi; City Station; Al Asad Koton Karfe; Koton Karfe Hub Station; Illorin Hub Station; Keffi City Station; Lafia Hub Station; Maikanti (Lafia) DBS; Kontagora Hub Station; Muripet Minna; Suleja City Station; Shagamu; Jos City Station; Jos Hub Station; Rumuji Hub Station; PHC (Trans Amadi) City Station; PHC (Portharcourt Aba Rd - Umurolu, Elelenwa) City Station; PHC (Rumuola Rd or Rumucheta Rd) City Station; Binjabal Station; Sokoto Bypass Hub Station; Wurno City Station; Jalingo Hub Station; Wukari; Potiskum City Station; Gummi City Station; Gusau City Station; New |
| `New_DKL__c` | New | string(226) | No |  |
| `NewCity_DKL__c` | New City | string(226) | No |  |
| `SalesType_DKL__c` | Sales Type | picklist | No | Retail Direct Sales; Cascade - Industrial Supply; Cascade - Third Party Retail Station |
| `UseLocation_DKL__c` | Use Location | textarea(255) | No |  |
| `OtherLossReason_DKL__c` | Other (Loss Reason) | string(255) | No |  |
| `Phase_DKL__c` | Phase | double | No |  |
| `Frequency_DKL__c` | Frequency(Hz) | double | No |  |
| `Voltage_DKL__c` | Voltage(V-AC) | double | No |  |
| `MaximumPermissibleLoading_DKL__c` | Maximum Permissible Loading(kWe) | double | No |  |
| `ExcessConsumptionprice_DKL__c` | Excess Consumption price(%) | double | No |  |
| `PaymentTerms_DKL__c` | Payment Terms (days) | double | No |  |
| `Days_in_Qualification__c` | Days in Qualification | double | No |  |
| `Days_in_Site_visit_done__c` | Days in Site visit done | double | No |  |
| `Days_in_Data_collected__c` | Days in Data collected | double | No |  |
| `Days_in_Proposal_submitted__c` | Days in Proposal submitted | double | No |  |
| `EstimatedCNGQuantitySCMDay_DKL__c` | Estimated CNG Quantity (SCM/Day) | double | No |  |
| `FirstFuelSupplyDate_DKL__c` | Supply Start Date | date | No |  |
| `First_Day_Of_Next_Month__c` | First Day Of Next Month | date | No |  |

### 3.5 Account

| API name | Label | Type | Required | Picklist values / lookup |
|---|---|---|---|---|
| `Id` | Account ID | id | —(sys) |  |
| `IsDeleted` | Deleted | boolean | —(sys) |  |
| `MasterRecordId` | Master Record ID | reference | No | → Account |
| `Name` | Account Name | string(255) | **Yes** |  |
| `Type` | Account Type | picklist | No | Customer; Prospect; Competitor; Other |
| `RecordTypeId` | Record Type ID | reference | No | → RecordType |
| `ParentId` | Parent Account ID | reference | No | → Account |
| `BillingStreet` | Billing Street | textarea(255) | No |  |
| `BillingCity` | Billing City | string(40) | No |  |
| `BillingState` | Billing State/Province | string(80) | No |  |
| `BillingPostalCode` | Billing Zip/Postal Code | string(20) | No |  |
| `BillingCountry` | Billing Country | string(80) | No |  |
| `BillingStateCode` | Billing State/Province Code | picklist | No | NGAB; CMAD; NGAD; NGAK; NGAN; CDBU; NGBA; NGBY; NGBE; NGBO; CMCN; NGCR; NGDE; CMES; NGEB; NGED; NGEK; NGEN; CDEQ; CMFN; NGFCT; NGGO; CDHK; CDHL; CDHU; NGIM; CDIT; NGJG; NGKD; NGKN; CDKA; CDKC; CDKO; NGKT; NGKB; CDKI; NGKO; CDKCEN; CDKW; NGKW; CDKWI; NGLA; CMLT; CDLO; CDMN; CDMA; CDMO; NGNA; NGNI; CDNK; CDNU; CMNO; CMNW; NGOG; NGON; NGOS; NGOY; NGPL; NGRI; CDSA; NGSO; CMSO; CMSW; CDSK; CDSU; CDTA; NGTA; CDTS; CDTP; CMWE; NGYO; NGZA |
| `BillingCountryCode` | Billing Country Code | picklist | No | CM; CD; NG |
| `BillingLatitude` | Billing Latitude | double | No |  |
| `BillingLongitude` | Billing Longitude | double | No |  |
| `BillingGeocodeAccuracy` | Billing Geocode Accuracy | picklist | No | Address; NearAddress; Block; Street; ExtendedZip; Zip; Neighborhood; City; County; State; Unknown |
| `BillingAddress` | Billing Address | address | No |  |
| `ShippingStreet` | Shipping Street | textarea(255) | No |  |
| `ShippingCity` | Shipping City | string(40) | No |  |
| `ShippingState` | Shipping State/Province | string(80) | No |  |
| `ShippingPostalCode` | Shipping Zip/Postal Code | string(20) | No |  |
| `ShippingCountry` | Shipping Country | string(80) | No |  |
| `ShippingStateCode` | Shipping State/Province Code | picklist | No | NGAB; CMAD; NGAD; NGAK; NGAN; CDBU; NGBA; NGBY; NGBE; NGBO; CMCN; NGCR; NGDE; CMES; NGEB; NGED; NGEK; NGEN; CDEQ; CMFN; NGFCT; NGGO; CDHK; CDHL; CDHU; NGIM; CDIT; NGJG; NGKD; NGKN; CDKA; CDKC; CDKO; NGKT; NGKB; CDKI; NGKO; CDKCEN; CDKW; NGKW; CDKWI; NGLA; CMLT; CDLO; CDMN; CDMA; CDMO; NGNA; NGNI; CDNK; CDNU; CMNO; CMNW; NGOG; NGON; NGOS; NGOY; NGPL; NGRI; CDSA; NGSO; CMSO; CMSW; CDSK; CDSU; CDTA; NGTA; CDTS; CDTP; CMWE; NGYO; NGZA |
| `ShippingCountryCode` | Shipping Country Code | picklist | No | CM; CD; NG |
| `ShippingLatitude` | Shipping Latitude | double | No |  |
| `ShippingLongitude` | Shipping Longitude | double | No |  |
| `ShippingGeocodeAccuracy` | Shipping Geocode Accuracy | picklist | No | Address; NearAddress; Block; Street; ExtendedZip; Zip; Neighborhood; City; County; State; Unknown |
| `ShippingAddress` | Shipping Address | address | No |  |
| `Phone` | Account Phone | phone(40) | No |  |
| `Fax` | Account Fax | phone(40) | No |  |
| `AccountNumber` | Account Number | string(40) | No |  |
| `Website` | Website | url | No |  |
| `PhotoUrl` | Photo URL | url | No |  |
| `Sic` | SIC Code | string(20) | No |  |
| `Industry` | Industry | picklist | No | Cement; Ceramic; Construction; Food & Beverages; Glass; Textile; Agro Products; IPP; Chemicals & Detergents; Iron & Steel; Educational Institutions; Commercial Establishments; Hospitals; Mining; Pharmaceuticals; Plastics; Haulage; Captive Customers (Haulage); Ecommerce; State Transport; School Transport; State Associations; Cascade Filling – Industry; Cascade Filling – Retail Station; Other |
| `AnnualRevenue` | Annual Revenue | currency | No |  |
| `NumberOfEmployees` | Employees | int | No |  |
| `Ownership` | Ownership | picklist | No | Public; Private; Subsidiary; Other |
| `TickerSymbol` | Ticker Symbol | string(20) | No |  |
| `Description` | Account Description | textarea(32000) | No |  |
| `Rating` | Account Rating | picklist | No | Hot; Warm; Cold |
| `Site` | Account Site | string(80) | No |  |
| `CurrencyIsoCode` | Account Currency | picklist | No | NGN; USD |
| `OwnerId` | Sales Champion | reference | Auto | → User |
| `CreatedDate` | Created Date | datetime | —(sys) |  |
| `CreatedById` | Created By ID | reference | —(sys) | → User |
| `LastModifiedDate` | Last Modified Date | datetime | —(sys) |  |
| `LastModifiedById` | Last Modified By ID | reference | —(sys) | → User |
| `SystemModstamp` | System Modstamp | datetime | —(sys) |  |
| `LastActivityDate` | Last Activity | date | No |  |
| `LastViewedDate` | Last Viewed Date | datetime | No |  |
| `LastReferencedDate` | Last Referenced Date | datetime | No |  |
| `Jigsaw` | Data.com Key | string(20) | No |  |
| `JigsawCompanyId` | Jigsaw Company ID | string(20) | No |  |
| `AccountSource` | Account Source | picklist | No | Cold Calls; Site Visit; References; Customer Event; Employee Referral; External Referral; Google AdWords; Other; Partner; Purchased List; Trade Show; Webinar; Website |
| `SicDesc` | SIC Description | string(80) | No |  |
| `IsPriorityRecord` | Important | boolean | —(sys) |  |
| `BusinessUnitDKL__c` | Business Unit | picklist | No | Greenville LNG; Gradient |
| `CustomerCategory_DKL__c` | Customer Category | picklist | No | Off-takers |
| `EstimatedQuantityMTMonth_DKL__c` | Estimated Quantity (MT/Month) | double | No |  |
| `SAPAccountCode_DKL__c` | SAP Account Code | string(18) | No |  |
| `CustomerProjectStatusDKL__c` | Customer Project Status | picklist | No | Proposed; FDI Approved; Under Construction; Operational; On Ground |
| `HaulagePermitOrMOUExpiryDate_DKL__c` | Haulage Permit or MOU Expiry Date | date | No |  |
| `HaulagePermitOrMOU_DKL__c` | Haulage Permit or MOU | boolean | Auto |  |
| `Non_LNG__c` | Non LNG | picklist | No | LPG; Propane; Condensate; LIN |
| `OffTakePermitExpiryDate_DKL__c` | Off-Take Permit Expiry Date | date | No |  |
| `OffTakePermitValidity_DKL__c` | Off-Take Permit Validity | boolean | Auto |  |
| `Quantity__c` | Quantity | double | No |  |
| `StoragePermitOrMOUExpiryDate_DKL__c` | Storage Permit or MOU Expiry Date | date | No |  |
| `StoragePermitOrMOU_DKL__c` | Storage Permit or MOU | boolean | Auto |  |
| `DaysTillHaulagePermitExpires_DKL__c` | Days Till Haulage permit Expires | double | No |  |
| `DaysTillOffTakePermitExpires_DKL__c` | Days Till Off-Take Permit Expires | double | No |  |
| `DaysTillStoragePermitOrMOUExpires_DKL__c` | DaysTillStoragePermitOrMOUExpires | double | No |  |
| `PermitExpiryStatus_DKL__c` | Permit Expiry Status | string(1300) | No |  |
| `StateAssociationDKL__c` | State Association | picklist | No | ACTMO; TOAKAN; KASMOTRAN; NACTOMORAS; ACOMORAN; TOAN; SHARP; GDN; Fleet Owners |
| `IfOtherPleaseSpecify__c` | If Other, Please Specify | string(80) | No |  |
| `UnitOfMeasurement__c` | Unit of Measurement | picklist | No | MT; KL |
| `TypeofBusiness_DKL__c` | Type of Business | multipicklist | No | Road Construction; Asphalt Production; Others |
| `CreditPeriod_DKL__c` | Credit Period | string(255) | No |  |
| `FleetSize_DKL__c` | Fleet Size | double | No |  |
| `FuelType_DKL__c` | Fuel Type | picklist | No | CNG; LNG |
| `Greenfield_DKL__c` | Greenfield | picklist | No | New; Expansion |
| `NoofTrucks_DKL__c` | No of Trucks | double | No |  |
| `IndustryStatus_DKL__c` | Industry Status | picklist | No | Greenfield; Brownfield; Expansion |
| `CACNumberRCNumber__c` | CAC Number/RC Number | string(18) | No |  |
| `DateofIncorporation_DKL__c` | Date of Incorporation | date | No |  |
| `OwnershipType_DKL__c` | Ownership Type | picklist | No | Limited; PLC; Enterprise; Sole Proprietor |
| `DealsIn_DKL__c` | Deals In | string(226) | No |  |
| `AuditorName_DKL__c` | Auditor Name | string(26) | No |  |
| `AuditorAddress_DKL__c` | Auditor Address | string(226) | No |  |
| `VATNumber_DKL__c` | VAT Number | string(18) | No |  |
| `TINNumber_DKL__c` | TIN Number | string(18) | No |  |
| `ListofDirectors_DKL__c` | List of Directors | textarea(32768) | No |  |
| `ProjectsContractswithValue_DKL__c` | Projects/Contracts with Value | textarea(32768) | No |  |
| `BusinessAddress_DKL__c` | Business Address | string(226) | No |  |
| `NumberofDirectEmployees__c` | Number of Direct Employees | double | No |  |
| `Email_DKL__c` | Email | string(100) | No |  |
| `Brownfield_DKL__c` | Brownfield | picklist | No | Expansion |

---

## 4. Loading Advice creation — required fields cross-check (vs the "Create Loading Advice" screen)

The screen you described requires: **Customer, Customer Type, Location, Product, Quantity (MT), Price (N/MT)**. All six live on **`Loading_Advice_Line__c`** (not the header). Against the org schema:

| Screen field | Object.field | DB-required? (`nillable=false`) | Notes for headless create |
|---|---|---|---|
| Customer | `Loading_Advice_Line__c.Customer_DKL__c` (→ Account) | **Yes** | Hard requirement at insert. |
| Customer Type | `Loading_Advice_Line__c.CustomerType_DKL__c` (Advance; Credit) | No | Screen-enforced only. Populate to mirror UI. |
| Location | `Loading_Advice_Line__c.Location_DKL__c` (text) | No | Screen-enforced only. |
| Product | `Loading_Advice_Line__c.Product_DKL__c` (→ Product2) | No | Screen-enforced only. Drives PDF product name + `ProductFamily`. |
| Quantity (MT) | `Loading_Advice_Line__c.QuantityMT_DKL__c` (double) | No | Screen-enforced only; needed for rollups/PDF. |
| Price (N/MT) | `Loading_Advice_Line__c.PricePerMT_DKL__c` (currency) | No | Screen-enforced only; Stock Transfer has no pricing. |

Plus the structural must-supply: `Loading_Advice_Line__c.LoadingAdvice_DKL__c` (master) and `Loading_Advice__c.Order_DKL__c` (master) + `Loading_Advice__c.RecordTypeId`.

> **Headless-create takeaway:** to faithfully mirror the screen in Phase 1 we should set all six screen fields even though only Customer is DB-required, otherwise we'd create records the UI considers invalid. We should also confirm whether any **Validation Rules** (e.g. `Loading_Advice__c.Lock_When_Approved`, retrieved) or required-field page-layout settings add constraints — to be reviewed before Phase 1 build.

---

## 5. Approval flow — `Loading Advice - Submit for Approval`

**File:** [Loading_Advice_Submit_for_Approval.flow-meta.xml](../force-app/main/default/flows/Loading_Advice_Submit_for_Approval.flow-meta.xml) · **Type:** Screen Flow (`processType=Flow`), launched from the LA record (not record-triggered).

> **⚠️ Phase 3 scope — submit only.** The headless Phase 3 action mirrors **only this Submit-for-Approval screen flow**:
> 1. generate the **internal** PDF via `LoadingAdvicePDFGenerator` (Commercial template, always — regardless of record type at submit time),
> 2. build attachments via the `LA_Build_Email_Attachments` subflow,
> 3. send the approver email + custom (bell) notification,
> 4. set `Status_DKL__c='Draft'` and `Approval_Status_DKL__c='Pending 1st Approver'` (+ `SubmittedOn_DKL__c`, `Submittedby_DKL__c`).
>
> The **Type-of-Load (Commercial vs Stock Transfer) dispatch-PDF routing is NOT part of submit.** That decision (`Commercial_Or_Stock_Transfer` → `LoadingAdvicePDFGenerator` vs `GenerateStockTransferPDF`) lives in `LA_Approve_Reject` and fires **later, at final approval/dispatch**, off `RecordType.DeveloperName`. Phase 3 must not invoke it.

### Fields it sets (single `Update Records 1` element on the LA header)
| Field | Value set |
|---|---|
| `Approval_Status_DKL__c` | `"Pending 1st Approver"` (literal string) |
| `Status_DKL__c` | `"Draft"` (literal string) |
| `SubmittedOn_DKL__c` | `{!$Flow.CurrentDateTime}` |
| `Submittedby_DKL__c` | `{!$User.Id}` (running user) |

These four are exactly the set to replicate headlessly in Phase 3.

### Step order
1. **Get_Loading_Advice_Header** — load LA by recordId.
2. **Get_the_Loading_Advice_Lines** → decisions **Ensure_Loading_Lines_are_present / Has_Line** — guard: must have ≥1 line.
3. **Call_the_Apex_Generate_PDF** — invocable `LoadingAdvicePDFGenerator` (Commercial template) → returns ContentVersion Id, stored via assignment **Add_LA_PDF_to_Envelope**.
4. **Subflow `LA_Build_Email_Attachments`** — collects the LA PDF + any LPO files into `col_FinalAttachmentsToJoy` (see §6).
5. **Get_Level_1_Routing_Record** — query `Approvver_Availability__c` where `ApprovalStage_DKL__c = "Level 1"`.
6. **Is_Level_1_Primary_Available** decision → assign approver = `Approver_DKL__c` (primary) **or** `BackupApprover_DKL__c` (backup).
7. **Get_Approver_User** — load the approver User (for email + notification).
8. **Update_Records_1** — set the four fields above.
9. **Email_Joy_for_Approval** — `emailSimple`:
   - Sender: **OrgWideEmailAddress** `aramy@dkloudconsulting.com`
   - To: approver's `Email`
   - Subject: `Loading Advice Review Required: {!...Name}`
   - Body: rich HTML + record URL link; attachments = `col_FinalAttachmentsToJoy`.
10. **Send_Level_1_Bell_Alert** — `customNotificationAction` (custom notification type from `Get_Notification_Type`):
    - Title `Approval Needed: {!...Name}`, body `... is awaiting your approval.`, targetId = the LA record.

### Notification / routing dependencies (needed for Phase 3 headless mirror)
- Custom object **`Approvver_Availability__c`** (note the spelling) with fields `ApprovalStage_DKL__c`, `Approver_DKL__c`, `BackupApprover_DKL__c` drives approver selection per level.
- A **Custom Notification Type** (looked up at runtime) for the bell alert.
- An **Org-Wide Email Address** `aramy@dkloudconsulting.com` must exist/be verified.

### Downstream (for context — handled in `LA_Approve_Reject`, not this flow)
Multi-stage approve/reject sets, by stage:
- 1st approver → `X1ApprovedBy_DKL__c`, `X1stApprovedOn_DKL__c`, `Approval_Status_DKL__c`, `Comments_DKL__c`.
- 2nd approver → `X2ndApprovedBy_DKL__c`, `X2ndApprovedOn_DKL__c`, `Approval_Status_DKL__c`.
- Finance → `FinanceApprovedBy_DKL__c`, `FinanceApprovedOn_DKL__c`, `Status_DKL__c`, `CurrentApprover_DKL__c`.
- Final dispatch → `DispatchPDFContentDocumentId_DKL__c`, `LogisticsEmailSent_DKL__c`; and the **Commercial vs Stock Transfer PDF** decision (see Q2).

---

## 6. Subflow — `LA_Build_Email_Attachments`
**File:** [LA_Build_Email_Attachments.flow-meta.xml](../force-app/main/default/flows/LA_Build_Email_Attachments.flow-meta.xml)
Builds the email attachment collection for the LA: loops the LA lines, finds related files/LPOs (`Get_Content_Document_Links`, `Find_the_Files_LPOs`), fetches the latest `ContentVersion` of the generated PDF (`Get_the_Latest_Version_of_the_File` / `Version_Found?`), and returns `col_EmailAttachments` (the email-ready ContentVersion Ids). Inputs: `recordId`, `var_InternalPDF_ID`.

---

## 7. Raw artefacts captured
- Describe JSON: [docs/raw/Account.json](raw/Account.json), [Opportunity.json](raw/Opportunity.json), [Order.json](raw/Order.json), [Loading_Advice__c.json](raw/Loading_Advice__c.json), [Loading_Advice_Line__c.json](raw/Loading_Advice_Line__c.json)
- Object/field/recordType XML: [force-app/main/default/objects/](../force-app/main/default/objects/)
- Flows: `Loading_Advice_Submit_for_Approval`, `LA_Approve_Reject`, `LA_Build_Email_Attachments`
- Apex: `LoadingAdvicePDFGenerator`, `LoadingAdvicePDFExtension`, `GenerateStockTransferPDF`
