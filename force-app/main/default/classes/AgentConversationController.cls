/**
 * Stateless turn state machine for the conversational sales agent.
 * The LWC holds the conversation state and passes it in/out each turn (stateJson).
 *
 * Phases:
 *   COLLECTING      - parse text -> merge -> preview -> NEEDS_INPUT (gaps) or NEEDS_CONFIRM.
 *   AWAITING_CONFIRM- user replies yes/no; yes -> commit the chain (transaction 1).
 *   PENDING_SUBMIT  - records exist; next turn submits for approval (transaction 2) and
 *                     returns the combined confirmation. Commit and submit are deliberately
 *                     separate transactions (the approval PDF can't render with uncommitted
 *                     inserts pending); TurnResult.autoContinue tells the LWC to call again.
 */
public with sharing class AgentConversationController {
  private static final String PHASE_COLLECTING = 'COLLECTING';
  private static final String PHASE_AWAITING_ACCOUNT = 'AWAITING_ACCOUNT';
  private static final String PHASE_AWAITING_ACCOUNT_SWITCH = 'AWAITING_ACCOUNT_SWITCH';
  private static final String PHASE_AWAITING_INSIGHT_ACCOUNT = 'AWAITING_INSIGHT_ACCOUNT';
  private static final String PHASE_AWAITING_CONFIRM = 'AWAITING_CONFIRM';
  private static final String PHASE_PENDING_SUBMIT = 'PENDING_SUBMIT';

  private static final Set<String> LINE_FIELDS = new Set<String>{
    'Customer_DKL__c',
    'CustomerType_DKL__c',
    'Location_DKL__c',
    'Product_DKL__c',
    'QuantityMT_DKL__c',
    'PricePerMT_DKL__c',
    'DeliveryMode_DKL__c',
    'PaymentTerm_DKL__c'
  };
  private static final Set<String> OPP_FIELDS = new Set<String>{
    'Name',
    'StageName',
    'CloseDate'
  };
  private static final Set<String> ORDER_FIELDS = new Set<String>{
    'EffectiveDate',
    'Status'
  };

  // ---- state & result shapes ----
  public class State {
    public String phase = PHASE_COLLECTING;
    public Id accountId;
    public String typeOfLoad;
    public Map<String, Object> oppFields = new Map<String, Object>();
    public Map<String, Object> orderFields = new Map<String, Object>();
    public Map<String, Object> laFields = new Map<String, Object>();
    public Map<String, Object> lineFields = new Map<String, Object>();
    public String confirmationToken;
    public Id loadingAdviceId;
    public String createdJson;
    // disambiguation: candidates offered for an ambiguous account term + the term itself
    public String accountCandidatesJson;
    public String requestedAccountTerm;
    public Id pendingSwitchAccountId; // a non-candidate account awaiting switch-confirm
  }

  public class TurnResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String status; // OK | NEEDS_INPUT | NEEDS_CONFIRM | ERROR
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<String> missingFields;
    @AuraEnabled
    public String summaryJson;
    @AuraEnabled
    public String recordId; // primary record (Loading Advice) on success
    @AuraEnabled
    public Boolean autoContinue; // LWC should immediately call advance again
    @AuraEnabled
    public String stateJson; // pass back next turn
  }

  @AuraEnabled
  public static TurnResult advance(
    String userText,
    String stateJson,
    Id pageAccountId
  ) {
    State st = parseState(stateJson);
    if (pageAccountId != null && st.accountId == null) {
      st.accountId = pageAccountId;
    }
    if (st.phase == PHASE_PENDING_SUBMIT) {
      return doSubmit(st);
    }
    if (st.phase == PHASE_AWAITING_CONFIRM) {
      return handleConfirm(userText, st);
    }
    if (st.phase == PHASE_AWAITING_ACCOUNT_SWITCH) {
      return handleAccountSwitch(userText, st);
    }
    if (st.phase == PHASE_AWAITING_ACCOUNT) {
      return handleAwaitingAccount(userText, st);
    }
    if (st.phase == PHASE_AWAITING_INSIGHT_ACCOUNT) {
      // a read-only insight is waiting for the account name; treat this reply as that answer
      return resolveInsightAccount(st, stripAccountLabel(userText));
    }
    // IDLE only: classify intent BEFORE the create parser touches the text, so a read-only
    // question ("list orders for X") is never hijacked by the create parser's "for <name>"
    // extractor. Mid-chain phases above are skipped, so an in-flight create is never broken.
    String intent = AgentIntentRouter.classify(userText);
    if (intent == AgentIntentRouter.INTENT_ACCOUNT_INSIGHT) {
      return handleAccountInsight(userText, st);
    }
    if (intent == AgentIntentRouter.INTENT_OBJECT_INFO) {
      return handleObjectInfo(userText, st);
    }
    return handleCollecting(userText, st);
  }

  // ---------------------------------------------------------------- INSIGHT (read-only)
  // These never enter or mutate the create state machine — they return the state unchanged
  // (a half-built create in COLLECTING is preserved) and create nothing.
  private static TurnResult handleAccountInsight(String userText, State st) {
    if (st.accountId != null) {
      return runAccountInsight(st, st.accountId); // Account-page context
    }
    String name = extractInsightAccount(userText);
    if (String.isBlank(name)) {
      // No account named — ask, and REMEMBER we're waiting for an insight account so the
      // bare-name follow-up resolves here (not the create flow's account question).
      return askForInsightAccount(
        st,
        'Which account? Tell me the account name (e.g. "orders for Acme"), or open this from an Account record.'
      );
    }
    return resolveInsightAccount(st, name);
  }

  // Resolve an account for a read-only insight; stay in AWAITING_INSIGHT_ACCOUNT until resolved.
  private static TurnResult resolveInsightAccount(State st, String name) {
    if (String.isBlank(name)) {
      return askForInsightAccount(
        st,
        'Which account? Tell me the account name.'
      );
    }
    AgentActionResult ar = resolveAccount(name);
    if (ar.success && ar.recordId != null) {
      return runAccountInsight(st, ar.recordId); // does NOT persist to create state
    }
    // not found / ambiguous -> stay waiting so the next reply is tried as the account
    return askForInsightAccount(st, accountAskMessage(ar, name));
  }

  // Runs the read-only account insight and returns conversation to idle (COLLECTING).
  // Never persists the account into create-chain state.
  private static TurnResult runAccountInsight(State st, Id acctId) {
    Agent_GetAccountInsight.Request rq = new Agent_GetAccountInsight.Request();
    rq.accountId = acctId;
    AgentActionResult insight = Agent_GetAccountInsight.getInsight(
      new List<Agent_GetAccountInsight.Request>{ rq }
    )[0];
    st.phase = PHASE_COLLECTING;
    return readOnly(
      st,
      insight.success ? formatInsight(insight.summaryJson) : insight.message
    );
  }

  private static TurnResult askForInsightAccount(State st, String message) {
    st.phase = PHASE_AWAITING_INSIGHT_ACCOUNT;
    TurnResult out = base(st);
    out.status = AgentActionResult.STATUS_NEEDS_INPUT;
    out.success = false;
    out.message = message;
    out.missingFields = new List<String>{ 'Account' };
    return out;
  }

  private static TurnResult handleObjectInfo(String userText, State st) {
    String t = userText.toLowerCase();
    if (t.contains('need') || t.contains('required')) {
      return readOnly(
        st,
        'To create a Loading Advice I need, on the line: Customer, Customer Type, Location, ' +
          'Product, Quantity (MT) and Price (N/MT); plus the Type of Load (Commercial or ' +
          'Stock Transfer), the Opportunity Close Date and the Order Start Date.'
      );
    }
    String objApi = detectObject(t);
    if (objApi != null) {
      Agent_DescribeObject.Request rq = new Agent_DescribeObject.Request();
      rq.objectApiName = objApi;
      AgentActionResult d = Agent_DescribeObject.describe(
        new List<Agent_DescribeObject.Request>{ rq }
      )[0];
      if (d.success) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(
          d.summaryJson
        );
        return readOnly(
          st,
          data.get('label') +
            ' (' +
            data.get('objectApiName') +
            ') has ' +
            data.get('fieldCount') +
            ' fields. (Read-only.)'
        );
      }
      return readOnly(st, d.message);
    }
    return readOnly(
      st,
      'I can describe Account, Opportunity, Order, Loading Advice or Loading ' +
      'Advice Line, or tell you what a Loading Advice needs.'
    );
  }

  private static String detectObject(String t) {
    if (t.contains('loading advice line') || t.contains('advice line')) {
      return 'Loading_Advice_Line__c';
    }
    if (t.contains('loading advice')) {
      return 'Loading_Advice__c';
    }
    if (t.contains('opportunit') || t.contains('opp')) {
      return 'Opportunity';
    }
    if (t.contains('order')) {
      return 'Order';
    }
    if (t.contains('account')) {
      return 'Account';
    }
    return null;
  }

  private static String extractInsightAccount(String text) {
    Matcher m = Pattern.compile(
        '(?i)(?:related to|for|on)\\s+(.+?)(?:\\s+account\\b|[.,]|$)'
      )
      .matcher(text);
    if (m.find()) {
      String n = m.group(1).trim();
      if (
        String.isNotBlank(n) &&
        !n.equalsIgnoreCase('this') &&
        !n.equalsIgnoreCase('this account')
      ) {
        return n;
      }
    }
    return null;
  }

  private static String formatInsight(String summaryJson) {
    try {
      Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(
        summaryJson
      );
      String cat = d.get('customerCategory') == null
        ? 'n/a'
        : String.valueOf(d.get('customerCategory'));
      return d.get('name') +
        ' — Orders: ' +
        d.get('orderCount') +
        ' · Open opportunities: ' +
        d.get('openOpportunityCount') +
        ' · Category: ' +
        cat +
        '. (Read-only; nothing was created.)';
    } catch (Exception e) {
      return 'Account summary ready. (Read-only; nothing was created.)';
    }
  }

  /**
   * Echo of the values currently captured, prepended to the "still needed" prompt so the
   * user can SEE every parse — making both silent-overwrite (last value wins) and
   * silent-retention (a non-parsing correction keeps the old value) visible. Reflects state,
   * so an unparsed "correction" shows the unchanged prior value.
   */
  private static String captureEcho(State st) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(st.typeOfLoad)) {
      parts.add(st.typeOfLoad);
    }
    Object prod = st.lineFields.get('Product_DKL__c');
    if (prod != null) {
      parts.add(productName((Id) String.valueOf(prod)));
    }
    Object qty = st.lineFields.get('QuantityMT_DKL__c');
    if (qty != null) {
      parts.add('Qty ' + String.valueOf(qty) + ' MT');
    }
    Object price = st.lineFields.get('PricePerMT_DKL__c');
    if (price != null) {
      parts.add('Price ₦' + groupThousands(price) + '/MT');
    }
    Object loc = st.lineFields.get('Location_DKL__c');
    if (loc != null) {
      parts.add('Location ' + String.valueOf(loc));
    }
    Object ct = st.lineFields.get('CustomerType_DKL__c');
    if (ct != null) {
      parts.add('Customer Type ' + String.valueOf(ct));
    }
    return parts.isEmpty()
      ? ''
      : 'Got it so far: ' + String.join(parts, ' · ') + '. ';
  }

  private static String productName(Id pid) {
    if (pid == null) {
      return 'product';
    }
    List<Product2> ps = [SELECT Name FROM Product2 WHERE Id = :pid LIMIT 1];
    return ps.isEmpty() ? 'product' : ps[0].Name;
  }

  /** Locale-independent thousands grouping for the price echo (display only). */
  private static String groupThousands(Object v) {
    Decimal d;
    try {
      d = Decimal.valueOf(String.valueOf(v));
    } catch (Exception e) {
      return String.valueOf(v);
    }
    String digits = String.valueOf(
      d.setScale(0, System.RoundingMode.DOWN).abs().longValue()
    );
    String out = '';
    Integer c = 0;
    for (Integer i = digits.length() - 1; i >= 0; i--) {
      out = digits.substring(i, i + 1) + out;
      if (Math.mod(++c, 3) == 0 && i > 0) {
        out = ',' + out;
      }
    }
    return (d < 0 ? '-' : '') + out;
  }

  /** Read-only reply that leaves conversation state (and any in-progress create) untouched. */
  private static TurnResult readOnly(State st, String message) {
    TurnResult out = base(st);
    out.status = AgentActionResult.STATUS_OK;
    out.success = true;
    out.message = message;
    return out;
  }

  // ---------------------------------------------------------------- COLLECTING
  private static TurnResult handleCollecting(String userText, State st) {
    AgentPromptParser parser = AgentParserFactory.getParser();
    AgentParseResult pr = parser.parse(
      userText,
      new AgentContext(st.accountId)
    );

    if (st.typeOfLoad == null && pr.typeOfLoad != null) {
      st.typeOfLoad = pr.typeOfLoad;
    }
    mergeFields(st, pr.fieldMap);

    // Resolve the account if we don't have one yet.
    if (st.accountId == null) {
      if (String.isNotBlank(pr.accountHint)) {
        AgentActionResult ar = resolveAccount(pr.accountHint);
        if (ar.success && ar.recordId != null) {
          st.accountId = ar.recordId;
        } else {
          // Hint was ambiguous / not found — enter AWAITING_ACCOUNT (storing the
          // candidate list when ambiguous) so the next reply is the account answer.
          return enterAwaitingAccount(st, pr.accountHint, ar);
        }
      } else {
        return enterAwaitingAccount(st, null, null);
      }
    }
    return continueAfterAccount(st);
  }

  // ---------------------------------------------------------------- AWAITING_ACCOUNT
  // The agent asked "which account?" — treat the WHOLE reply as the account name (after
  // stripping only a leading "account:"/"account -" label). We deliberately do NOT re-run
  // the "for <name>" hint extractor here, so an account named e.g. "Olam for Construction"
  // is passed through intact.
  //
  // Disambiguation mode (candidates stored from an ambiguous term): the answer is matched
  // AGAINST the candidate list. A non-candidate that resolves to a real account triggers an
  // explicit switch-confirm (never a silent switch); one that resolves to nothing re-lists
  // the candidates. The no-candidate path keeps the original global resolve (loop fix).
  private static TurnResult handleAwaitingAccount(String userText, State st) {
    String term = stripAccountLabel(userText);
    if (String.isBlank(term)) {
      return String.isNotBlank(st.accountCandidatesJson)
        ? askForAccount(
            st,
            'Please pick one of: ' + candidateNames(st.accountCandidatesJson)
          )
        : askForAccount(st, 'Which account is this Loading Advice for?');
    }

    if (String.isNotBlank(st.accountCandidatesJson)) {
      List<Id> matched = matchCandidates(term, st.accountCandidatesJson);
      if (matched.size() == 1) {
        return acceptAccount(st, matched[0]);
      }
      if (matched.size() > 1) {
        return askForAccount(
          st,
          'More than one option matches "' +
            term +
            '". Please narrow it down: ' +
            candidateNames(st.accountCandidatesJson)
        );
      }
      // No candidate matched — see if it's a different real account.
      AgentActionResult ar = resolveAccount(term);
      if (ar.success && ar.recordId != null) {
        st.pendingSwitchAccountId = ar.recordId;
        st.phase = PHASE_AWAITING_ACCOUNT_SWITCH;
        TurnResult out = base(st);
        out.status = AgentActionResult.STATUS_NEEDS_INPUT;
        out.success = false;
        out.message =
          'That\'s a different account from "' +
          st.requestedAccountTerm +
          '" — create this for ' +
          accountName(ar.recordId) +
          ' instead? (yes/no)';
        out.missingFields = new List<String>{ 'Account' };
        return out;
      }
      if (String.isNotBlank(ar.summaryJson)) {
        // the new term is itself ambiguous -> disambiguate against ITS candidates
        return enterAwaitingAccount(st, term, ar);
      }
      return askForAccount(
        st,
        '"' +
          term +
          '" isn\'t one of the options for "' +
          st.requestedAccountTerm +
          '". Please pick one of: ' +
          candidateNames(st.accountCandidatesJson)
      );
    }

    // No candidates stored: original global resolve (keeps the bare-name loop fix).
    AgentActionResult ar2 = resolveAccount(term);
    if (ar2.success && ar2.recordId != null) {
      return acceptAccount(st, ar2.recordId);
    }
    return enterAwaitingAccount(st, term, ar2);
  }

  // Explicit switch-confirm: user is changing to an account that wasn't among the candidates.
  private static TurnResult handleAccountSwitch(String userText, State st) {
    String ans = userText == null ? '' : userText.trim().toLowerCase();
    if (
      ans.startsWith('y') ||
      ans.startsWith('proceed') ||
      ans.startsWith('confirm')
    ) {
      return acceptAccount(st, st.pendingSwitchAccountId);
    }
    if (ans.startsWith('n') || ans.startsWith('cancel')) {
      st.pendingSwitchAccountId = null;
      st.phase = PHASE_AWAITING_ACCOUNT;
      return askForAccount(
        st,
        'OK — keeping "' +
          st.requestedAccountTerm +
          '". Please pick one of: ' +
          candidateNames(st.accountCandidatesJson)
      );
    }
    TurnResult out = base(st);
    out.status = AgentActionResult.STATUS_NEEDS_INPUT;
    out.success = false;
    out.message =
      'Please reply yes (use ' +
      accountName(st.pendingSwitchAccountId) +
      ') or no (keep the original options).';
    out.missingFields = new List<String>{ 'Account' };
    return out;
  }

  /** Enter AWAITING_ACCOUNT; persist candidates + term when the resolve was ambiguous. */
  private static TurnResult enterAwaitingAccount(
    State st,
    String term,
    AgentActionResult ar
  ) {
    st.phase = PHASE_AWAITING_ACCOUNT;
    Boolean ambiguous = ar != null && String.isNotBlank(ar.summaryJson);
    st.accountCandidatesJson = ambiguous ? ar.summaryJson : null;
    st.requestedAccountTerm = ambiguous ? term : null;
    String msg = ar == null
      ? 'Which account is this Loading Advice for?'
      : accountAskMessage(ar, term);
    return askForAccount(st, msg);
  }

  /** Commit the chosen account and continue; clears all disambiguation state. */
  private static TurnResult acceptAccount(State st, Id chosenAccountId) {
    st.accountId = chosenAccountId;
    st.accountCandidatesJson = null;
    st.requestedAccountTerm = null;
    st.pendingSwitchAccountId = null;
    st.phase = PHASE_COLLECTING;
    return continueAfterAccount(st);
  }

  /** Match an answer against the offered candidates: exact first, then contains. */
  private static List<Id> matchCandidates(String term, String candidatesJson) {
    List<Id> ids = new List<Id>();
    String tl = term.toLowerCase();
    try {
      List<Object> rows = (List<Object>) JSON.deserializeUntyped(
        candidatesJson
      );
      for (Object o : rows) {
        Map<String, Object> m = (Map<String, Object>) o;
        if (
          m.get('Name') != null &&
          String.valueOf(m.get('Name')).equalsIgnoreCase(term)
        ) {
          ids.add((Id) String.valueOf(m.get('Id')));
        }
      }
      if (!ids.isEmpty()) {
        return ids;
      }
      for (Object o : rows) {
        Map<String, Object> m = (Map<String, Object>) o;
        if (m.get('Name') == null) {
          continue;
        }
        String nl = String.valueOf(m.get('Name')).toLowerCase();
        if (nl.contains(tl) || tl.contains(nl)) {
          ids.add((Id) String.valueOf(m.get('Id')));
        }
      }
    } catch (Exception e) {
      // fall through with whatever matched
    }
    return ids;
  }

  private static String accountName(Id acctId) {
    if (acctId == null) {
      return 'that account';
    }
    List<Account> a = [SELECT Name FROM Account WHERE Id = :acctId LIMIT 1];
    return a.isEmpty() ? String.valueOf(acctId) : a[0].Name;
  }

  // ---- shared: account is known -> default, preview, confirm/ask ----
  private static TurnResult continueAfterAccount(State st) {
    if (!st.lineFields.containsKey('Customer_DKL__c')) {
      st.lineFields.put('Customer_DKL__c', st.accountId);
    }
    applyDefaults(st);

    // Normalize values to their JSON (untyped) form so the confirmation token computed
    // here matches the one recomputed next turn after state is reloaded from JSON.
    st = parseState(JSON.serialize(st));

    AgentChainRequest req = toRequest(st);
    AgentActionResult prev = AgentChainService.preview(req);

    if (prev.status == AgentActionResult.STATUS_NEEDS_CONFIRM) {
      st.phase = PHASE_AWAITING_CONFIRM;
      st.confirmationToken = AgentChainService.token(req);
      TurnResult out = base(st);
      out.status = AgentActionResult.STATUS_NEEDS_CONFIRM;
      out.success = false;
      out.summaryJson = prev.summaryJson;
      out.message = prev.message;
      return out;
    }
    if (prev.status == AgentActionResult.STATUS_NEEDS_INPUT) {
      return needInput(st, captureEcho(st) + prev.message, prev.missingFields);
    }
    TurnResult err = base(st);
    err.status = AgentActionResult.STATUS_ERROR;
    err.message = prev.message;
    return err;
  }

  // ---------------------------------------------------------------- AWAITING_CONFIRM
  private static TurnResult handleConfirm(String userText, State st) {
    String ans = userText == null ? '' : userText.trim().toLowerCase();
    if (
      ans.startsWith('y') ||
      ans.startsWith('proceed') ||
      ans.startsWith('confirm')
    ) {
      return doCommit(st);
    }
    if (ans.startsWith('n') || ans.startsWith('cancel')) {
      State fresh = new State();
      TurnResult out = base(fresh);
      out.status = AgentActionResult.STATUS_OK;
      out.success = true;
      out.message = 'Cancelled — nothing was created. Tell me what to change and we can try again.';
      return out;
    }
    TurnResult out = base(st);
    out.status = AgentActionResult.STATUS_NEEDS_CONFIRM;
    out.success = false;
    out.message = 'Please reply "yes" to create and submit, or "no" to cancel.';
    return out;
  }

  // ---------------------------------------------------------------- COMMIT (txn 1)
  private static TurnResult doCommit(State st) {
    AgentChainRequest req = toRequest(st);
    req.confirmationToken = st.confirmationToken;
    AgentActionResult commitRes = AgentChainService.commitChain(req);

    if (commitRes.status != AgentActionResult.STATUS_OK) {
      // validation/token failure — drop back to collecting so the user can fix it.
      st.phase = PHASE_COLLECTING;
      TurnResult out = base(st);
      out.status = commitRes.status;
      out.success = false;
      out.message = commitRes.message;
      out.missingFields = commitRes.missingFields;
      return out;
    }

    st.loadingAdviceId = commitRes.recordId;
    st.createdJson = commitRes.summaryJson;
    st.phase = PHASE_PENDING_SUBMIT;

    TurnResult out = base(st);
    out.status = AgentActionResult.STATUS_OK;
    out.success = true;
    out.recordId = commitRes.recordId;
    out.summaryJson = commitRes.summaryJson;
    out.message = 'Records created. Submitting for approval…';
    out.autoContinue = true; // LWC immediately calls advance() again -> doSubmit (txn 2)
    return out;
  }

  // ---------------------------------------------------------------- SUBMIT (txn 2)
  private static TurnResult doSubmit(State st) {
    AgentActionResult submitRes = AgentApprovalService.submit(
      st.loadingAdviceId
    );

    Map<String, Object> created = String.isBlank(st.createdJson)
      ? new Map<String, Object>()
      : (Map<String, Object>) JSON.deserializeUntyped(st.createdJson);
    created.put('submitted', submitRes.success);
    created.put('submitStatus', submitRes.status);
    created.put('submitMessage', submitRes.message);

    Id laId = st.loadingAdviceId;
    TurnResult out = base(new State()); // conversation complete -> reset state
    out.status = AgentActionResult.STATUS_OK;
    out.success = true;
    out.recordId = laId;
    out.summaryJson = JSON.serialize(created);
    out.message = submitRes.success
      ? 'Done. Created the Opportunity, Order, Loading Advice and Line, and submitted for approval. ' +
        submitRes.message
      : 'Created the records, but the approval submit did not complete: ' +
        submitRes.message;
    return out;
  }

  // ---------------------------------------------------------------- helpers
  private static void mergeFields(State st, Map<String, Object> fieldMap) {
    for (String k : fieldMap.keySet()) {
      Object v = fieldMap.get(k);
      if (OPP_FIELDS.contains(k)) {
        st.oppFields.put(k, v);
      } else if (ORDER_FIELDS.contains(k)) {
        st.orderFields.put(k, v);
      } else {
        st.lineFields.put(k, v); // line fields + default bucket
      }
    }
  }

  /** Operational defaults so the agent only asks for genuine business gaps. */
  private static void applyDefaults(State st) {
    if (!st.oppFields.containsKey('StageName')) {
      st.oppFields.put('StageName', 'Qualification');
    }
    if (!st.oppFields.containsKey('Name')) {
      st.oppFields.put('Name', buildOppName(st));
    }
    if (!st.orderFields.containsKey('Status')) {
      st.orderFields.put('Status', 'Draft');
    }
  }

  /** Report-friendly Opportunity name: "<Account> - <Product> LA (<date>)". */
  private static String buildOppName(State st) {
    String acctName;
    if (st.accountId != null) {
      List<Account> a = [
        SELECT Name
        FROM Account
        WHERE Id = :st.accountId
        LIMIT 1
      ];
      if (!a.isEmpty()) {
        acctName = a[0].Name;
      }
    }
    String prodName;
    Object pid = st.lineFields.get('Product_DKL__c');
    if (pid != null) {
      Id productId = (Id) String.valueOf(pid);
      List<Product2> p = [
        SELECT Name
        FROM Product2
        WHERE Id = :productId
        LIMIT 1
      ];
      if (!p.isEmpty()) {
        prodName = p[0].Name;
      }
    }
    String base = acctName != null ? acctName : 'Loading Advice';
    base += prodName != null ? ' - ' + prodName + ' LA' : ' - Loading Advice';
    return base + ' (' + String.valueOf(Date.today()) + ')';
  }

  private static AgentChainRequest toRequest(State st) {
    AgentChainRequest req = new AgentChainRequest();
    req.accountId = st.accountId;
    req.typeOfLoad = st.typeOfLoad;
    req.oppFields = st.oppFields;
    req.orderFields = st.orderFields;
    req.laFields = st.laFields;
    req.lineFields = st.lineFields;
    return req;
  }

  private static State parseState(String stateJson) {
    State st = new State();
    if (String.isBlank(stateJson)) {
      return st;
    }
    // Parsed untyped: State holds Map<String,Object> members, which the strict typed
    // deserializer rejects. Values arrive as Strings/numbers and are coerced at commit.
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(
      stateJson
    );
    if (m.get('phase') != null) {
      st.phase = (String) m.get('phase');
    }
    if (m.get('accountId') != null) {
      st.accountId = (Id) String.valueOf(m.get('accountId'));
    }
    st.typeOfLoad = (String) m.get('typeOfLoad');
    st.confirmationToken = (String) m.get('confirmationToken');
    if (m.get('loadingAdviceId') != null) {
      st.loadingAdviceId = (Id) String.valueOf(m.get('loadingAdviceId'));
    }
    st.createdJson = (String) m.get('createdJson');
    st.accountCandidatesJson = (String) m.get('accountCandidatesJson');
    st.requestedAccountTerm = (String) m.get('requestedAccountTerm');
    if (m.get('pendingSwitchAccountId') != null) {
      st.pendingSwitchAccountId = (Id) String.valueOf(
        m.get('pendingSwitchAccountId')
      );
    }
    st.oppFields = asMap(m.get('oppFields'));
    st.orderFields = asMap(m.get('orderFields'));
    st.laFields = asMap(m.get('laFields'));
    st.lineFields = asMap(m.get('lineFields'));
    return st;
  }

  private static Map<String, Object> asMap(Object o) {
    return o == null ? new Map<String, Object>() : (Map<String, Object>) o;
  }

  private static TurnResult base(State st) {
    TurnResult out = new TurnResult();
    out.missingFields = new List<String>();
    out.autoContinue = false;
    out.stateJson = JSON.serialize(st);
    return out;
  }

  private static TurnResult needInput(
    State st,
    String message,
    List<String> missing
  ) {
    st.phase = PHASE_COLLECTING;
    TurnResult out = base(st);
    out.status = AgentActionResult.STATUS_NEEDS_INPUT;
    out.success = false;
    out.message = message;
    out.missingFields = missing == null ? new List<String>() : missing;
    return out;
  }

  /** Ask for the account and enter AWAITING_ACCOUNT so the next reply is the account name. */
  private static TurnResult askForAccount(State st, String message) {
    st.phase = PHASE_AWAITING_ACCOUNT;
    TurnResult out = base(st);
    out.status = AgentActionResult.STATUS_NEEDS_INPUT;
    out.success = false;
    out.message = message;
    out.missingFields = new List<String>{ 'Account' };
    return out;
  }

  private static AgentActionResult resolveAccount(String searchTerm) {
    Agent_ResolveAccount.Request rq = new Agent_ResolveAccount.Request();
    rq.searchTerm = searchTerm;
    return Agent_ResolveAccount.resolve(
      new List<Agent_ResolveAccount.Request>{ rq }
    )[0];
  }

  /** Strip only a leading "account:" / "account -" label; keep the rest of the name verbatim. */
  private static String stripAccountLabel(String text) {
    if (text == null) {
      return '';
    }
    return text.trim().replaceFirst('(?i)^account\\s*[:\\-]\\s*', '').trim();
  }

  /** Builds the re-ask message: ambiguous -> list candidates; no match -> name the search. */
  private static String accountAskMessage(AgentActionResult ar, String term) {
    if (String.isNotBlank(ar.summaryJson)) {
      String names = candidateNames(ar.summaryJson);
      return ar.message + (String.isBlank(names) ? '' : ' Options: ' + names);
    }
    return 'I couldn\'t find an account called "' +
      term +
      '". Please check the name and try again.';
  }

  private static String candidateNames(String summaryJson) {
    try {
      List<Object> rows = (List<Object>) JSON.deserializeUntyped(summaryJson);
      List<String> names = new List<String>();
      for (Object o : rows) {
        Object nm = ((Map<String, Object>) o).get('Name');
        if (nm != null) {
          names.add(String.valueOf(nm));
        }
      }
      return String.join(names, '; ');
    } catch (Exception e) {
      return '';
    }
  }
}
