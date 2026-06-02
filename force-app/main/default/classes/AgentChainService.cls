/**
 * Core of the single-prompt sales chain.
 *
 *  preview(req) - validates all four records against the CURATED business-required list
 *                 (NOT DB nillable), returns ONE consolidated missingFields list + a single
 *                 combined summaryJson + a confirmationToken. Status NEEDS_INPUT if anything
 *                 is missing, else NEEDS_CONFIRM. Creates nothing.
 *  commit(req)  - requires a confirmationToken matching the previewed summary, then creates
 *                 Opportunity → Order → Loading Advice → Line in ONE transaction
 *                 (savepoint + rollback on any failure). Returns the four record links.
 *
 * The action classes Agent_PreviewSalesChain / Agent_CommitSalesChain are thin invocable
 * wrappers over these two methods (kept Flow/Agentforce-ready).
 */
public with sharing class AgentChainService {
  // ---- Curated business-required fields (source of truth for missingFields) ----
  // Line fields: API name -> friendly label.
  private static final Map<String, String> LINE_REQUIRED = new Map<String, String>{
    'Customer_DKL__c' => 'Customer',
    'CustomerType_DKL__c' => 'Customer Type',
    'Location_DKL__c' => 'Location',
    'Product_DKL__c' => 'Product',
    'QuantityMT_DKL__c' => 'Quantity (MT)',
    'PricePerMT_DKL__c' => 'Price (N/MT)'
  };
  private static final Map<String, String> OPP_REQUIRED = new Map<String, String>{
    'Name' => 'Name',
    'StageName' => 'Stage',
    'CloseDate' => 'Close Date'
  };
  private static final Map<String, String> ORDER_REQUIRED = new Map<String, String>{
    'EffectiveDate' => 'Start Date',
    'Status' => 'Status'
  };

  // ============================================================== PREVIEW
  public static AgentActionResult preview(AgentChainRequest req) {
    if (req == null) {
      return AgentActionResult.error('No request supplied.');
    }
    List<String> missing = consolidatedMissing(req);
    if (!missing.isEmpty()) {
      AgentActionResult r = AgentActionResult.needsInput(
        'Before I can create this I need: ' + String.join(missing, ', ') + '.',
        missing
      );
      r.summaryJson = JSON.serialize(buildSummary(req, null));
      return r;
    }
    String token = token(req);
    Map<String, Object> summary = buildSummary(req, token);
    AgentActionResult ok = AgentActionResult.needsConfirm(
      'Here is what I will create. Proceed? (yes/no)',
      summary
    );
    return ok;
  }

  /** Runs every per-object validator and returns ONE consolidated list. */
  public static List<String> consolidatedMissing(AgentChainRequest req) {
    List<String> missing = new List<String>();
    if (req.accountId == null) {
      missing.add('Account');
    }
    missing.addAll(validateOpportunity(req));
    missing.addAll(validateOrder(req));
    missing.addAll(validateLoadingAdvice(req));
    missing.addAll(validateLine(req));
    return missing;
  }

  // ---- Per-object validators (curated rules) ----
  public static List<String> validateOpportunity(AgentChainRequest req) {
    return missingFrom('Opportunity', OPP_REQUIRED, req.oppFields);
  }
  public static List<String> validateOrder(AgentChainRequest req) {
    // AccountId + OpportunityId are threaded at commit, not user-supplied.
    return missingFrom('Order', ORDER_REQUIRED, req.orderFields);
  }
  public static List<String> validateLoadingAdvice(AgentChainRequest req) {
    // Order_DKL__c, RecordTypeId, Account/Opportunity lookups are threaded at commit.
    // The only user-required input is a valid Type of Load (drives RecordTypeId).
    List<String> missing = new List<String>();
    if (recordTypeDevName(req.typeOfLoad) == null) {
      missing.add(
        'Loading Advice: Type of Load (Commercial or Stock Transfer)'
      );
    }
    return missing;
  }
  public static List<String> validateLine(AgentChainRequest req) {
    return missingFrom('Loading Advice Line', LINE_REQUIRED, req.lineFields);
  }

  private static List<String> missingFrom(
    String objLabel,
    Map<String, String> required,
    Map<String, Object> provided
  ) {
    List<String> missing = new List<String>();
    for (String api : required.keySet()) {
      if (!hasValue(provided, api)) {
        missing.add(objLabel + ': ' + required.get(api));
      }
    }
    return missing;
  }

  private static Boolean hasValue(Map<String, Object> m, String key) {
    if (m == null || !m.containsKey(key)) {
      return false;
    }
    Object v = m.get(key);
    if (v == null) {
      return false;
    }
    return !(v instanceof String) || String.isNotBlank((String) v);
  }

  // ============================================================== COMMIT
  public static AgentActionResult commitChain(AgentChainRequest req) {
    if (req == null) {
      return AgentActionResult.error('No request supplied.');
    }
    // Re-validate so commit can never write an incomplete chain.
    List<String> missing = consolidatedMissing(req);
    if (!missing.isEmpty()) {
      return AgentActionResult.needsInput(
        'Cannot create yet — still missing: ' +
          String.join(missing, ', ') +
          '.',
        missing
      );
    }
    // Confirmation gate: token must match the previewed summary.
    String expected = token(req);
    if (
      String.isBlank(req.confirmationToken) || req.confirmationToken != expected
    ) {
      return AgentActionResult.error(
        'Confirmation required: the confirmation token is missing or does not match the previewed summary. Nothing was created.'
      );
    }

    Savepoint sp = Database.setSavepoint();
    try {
      // 1. Opportunity (Gradient record type — was inheriting the profile default,
      //    which mis-typed agent deals as Greenville_Industrial)
      Opportunity opp = new Opportunity();
      applyFields(opp, req.oppFields);
      opp.AccountId = req.accountId;
      opp.RecordTypeId = opportunityRecordTypeId;
      insert opp;

      // 2. Order (link to the Account + the Opp just created)
      Order ord = new Order();
      applyFields(ord, req.orderFields);
      ord.AccountId = req.accountId;
      ord.OpportunityId = opp.Id;
      insert ord;

      // 3. Loading Advice (master = Order; record type from load type; lookups threaded)
      Loading_Advice__c la = new Loading_Advice__c();
      applyFields(la, req.laFields);
      la.Order_DKL__c = ord.Id;
      la.Account_DKL__c = req.accountId;
      la.Opportunity_DKL__c = opp.Id;
      la.RecordTypeId = recordTypeId(req.typeOfLoad);
      if (la.Status_DKL__c == null) {
        la.Status_DKL__c = 'Draft'; // create-time default
      }
      insert la;

      // 4. Line (master = Loading Advice)
      Loading_Advice_Line__c line = new Loading_Advice_Line__c();
      applyFields(line, req.lineFields);
      line.LoadingAdvice_DKL__c = la.Id;
      insert line;

      // SUBMIT SEAM — intentionally a SEPARATE transaction.
      // The headless approval flow renders the internal PDF via getContentAsPDF(), which
      // cannot run while the inserts above are uncommitted in this transaction. So commit
      // only creates the chain; the orchestration layer (controller / agent) calls
      // AgentApprovalService.submit(loadingAdvice Id) as the next step once these commit.
      Map<String, Object> created = new Map<String, Object>{
        'opportunity' => recordLink(opp.Id),
        'order' => recordLink(ord.Id),
        'loadingAdvice' => recordLink(la.Id),
        'line' => recordLink(line.Id),
        'submitted' => false,
        'readyToSubmit' => true
      };
      AgentActionResult r = AgentActionResult.ok(
          'Created Opportunity, Order, Loading Advice and Line. Ready to submit for approval.',
          created
        )
        .withRecord(la.Id);
      return r;
    } catch (Exception e) {
      Database.rollback(sp);
      return AgentActionResult.error(
        'Failed to create the sales chain: ' +
          e.getMessage() +
          '. Nothing was created.'
      );
    }
  }

  // ============================================================== HELPERS

  /** Map the user-facing load type to the Loading Advice RecordType developer name. */
  public static String recordTypeDevName(String typeOfLoad) {
    if (String.isBlank(typeOfLoad)) {
      return null;
    }
    String t = typeOfLoad.trim().toLowerCase().replace(' ', '');
    if (t == 'commercial') {
      return 'Commercial_DKL';
    }
    if (t == 'stocktransfer') {
      return 'StockTransfer_DKL';
    }
    return null;
  }

  private static Map<String, Id> recordTypeIdsByDevName {
    get {
      if (recordTypeIdsByDevName == null) {
        recordTypeIdsByDevName = new Map<String, Id>();
        for (RecordType rt : [
          SELECT Id, DeveloperName
          FROM RecordType
          WHERE SobjectType = 'Loading_Advice__c' AND IsActive = TRUE
        ]) {
          recordTypeIdsByDevName.put(rt.DeveloperName, rt.Id);
        }
      }
      return recordTypeIdsByDevName;
    }
    set;
  }

  private static Id recordTypeId(String typeOfLoad) {
    return recordTypeIdsByDevName.get(recordTypeDevName(typeOfLoad));
  }

  // Gradient Opportunity record type (confirmed by Aramy: the current one, not the "Old").
  @TestVisible
  private static final String OPPORTUNITY_RECORD_TYPE = 'GradientOpportunity_DKL';

  private static Id opportunityRecordTypeId {
    get {
      if (opportunityRecordTypeId == null) {
        for (RecordType rt : [
          SELECT Id, DeveloperName
          FROM RecordType
          WHERE
            SobjectType = 'Opportunity'
            AND DeveloperName = :OPPORTUNITY_RECORD_TYPE
            AND IsActive = TRUE
          LIMIT 1
        ]) {
          opportunityRecordTypeId = rt.Id;
        }
      }
      return opportunityRecordTypeId;
    }
    set;
  }

  /** Deterministic token over the request content (excludes confirmationToken itself). */
  public static String token(AgentChainRequest req) {
    Blob digest = Crypto.generateDigest(
      'SHA-256',
      Blob.valueOf(canonical(req))
    );
    return EncodingUtil.convertToHex(digest);
  }

  private static String canonical(AgentChainRequest req) {
    List<String> parts = new List<String>{
      'account=' + req.accountId,
      'type=' + recordTypeDevName(req.typeOfLoad),
      'opp:' + canonMap(req.oppFields),
      'order:' + canonMap(req.orderFields),
      'la:' + canonMap(req.laFields),
      'line:' + canonMap(req.lineFields)
    };
    return String.join(parts, '|');
  }

  private static String canonMap(Map<String, Object> m) {
    if (m == null || m.isEmpty()) {
      return '';
    }
    List<String> keys = new List<String>(m.keySet());
    keys.sort();
    List<String> kv = new List<String>();
    for (String k : keys) {
      kv.add(k + '=' + String.valueOf(m.get(k)));
    }
    return String.join(kv, ',');
  }

  /** Builds the human-readable summary for the confirm card. */
  private static Map<String, Object> buildSummary(
    AgentChainRequest req,
    String token
  ) {
    String accountName;
    if (req.accountId != null) {
      List<Account> a = [
        SELECT Name
        FROM Account
        WHERE Id = :req.accountId
        LIMIT 1
      ];
      if (!a.isEmpty()) {
        accountName = a[0].Name;
      }
    }
    Map<String, Object> summary = new Map<String, Object>{
      'accountId' => req.accountId,
      'accountName' => accountName,
      'typeOfLoad' => req.typeOfLoad,
      'recordTypeDeveloperName' => recordTypeDevName(req.typeOfLoad),
      'opportunity' => req.oppFields,
      'order' => req.orderFields,
      'loadingAdvice' => req.laFields,
      'line' => req.lineFields
    };
    if (token != null) {
      summary.put('confirmationToken', token);
    }
    return summary;
  }

  /** Applies a field map to a record, coercing JSON-sourced strings to the field's type. */
  private static void applyFields(SObject rec, Map<String, Object> fields) {
    if (fields == null) {
      return;
    }
    Map<String, Schema.SObjectField> fmap = rec.getSObjectType()
      .getDescribe()
      .fields.getMap();
    for (String key : fields.keySet()) {
      Schema.SObjectField sf = fmap.get(key);
      if (sf == null) {
        continue; // ignore unknown keys
      }
      rec.put(key, coerce(sf.getDescribe().getType(), fields.get(key)));
    }
  }

  /** Coerce a (possibly JSON string) value to the target field type. Typed values pass through. */
  private static Object coerce(Schema.DisplayType t, Object v) {
    if (v == null || !(v instanceof String)) {
      return v;
    }
    String s = (String) v;
    switch on t {
      when DATE {
        return Date.valueOf(s);
      }
      when DOUBLE, CURRENCY, PERCENT {
        return Decimal.valueOf(s);
      }
      when INTEGER, LONG {
        return Integer.valueOf(s);
      }
      when BOOLEAN {
        return Boolean.valueOf(s);
      }
      when else {
        return s;
      }
    }
  }

  private static Map<String, String> recordLink(Id rid) {
    String recUrl;
    try {
      recUrl = URL.getOrgDomainUrl().toExternalForm() + '/' + rid;
    } catch (Exception e) {
      recUrl = '/' + rid;
    }
    return new Map<String, String>{
      'id' => String.valueOf(rid),
      'url' => recUrl
    };
  }
}
