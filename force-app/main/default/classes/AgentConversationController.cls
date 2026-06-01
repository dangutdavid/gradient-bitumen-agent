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
    private static final String PHASE_AWAITING_CONFIRM = 'AWAITING_CONFIRM';
    private static final String PHASE_PENDING_SUBMIT = 'PENDING_SUBMIT';

    private static final Set<String> LINE_FIELDS = new Set<String>{
        'Customer_DKL__c', 'CustomerType_DKL__c', 'Location_DKL__c', 'Product_DKL__c',
        'QuantityMT_DKL__c', 'PricePerMT_DKL__c', 'DeliveryMode_DKL__c', 'PaymentTerm_DKL__c'
    };
    private static final Set<String> OPP_FIELDS = new Set<String>{ 'Name', 'StageName', 'CloseDate' };
    private static final Set<String> ORDER_FIELDS = new Set<String>{ 'EffectiveDate', 'Status' };

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
    }

    public class TurnResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String status;        // OK | NEEDS_INPUT | NEEDS_CONFIRM | ERROR
        @AuraEnabled public String message;
        @AuraEnabled public List<String> missingFields;
        @AuraEnabled public String summaryJson;
        @AuraEnabled public String recordId;      // primary record (Loading Advice) on success
        @AuraEnabled public Boolean autoContinue; // LWC should immediately call advance again
        @AuraEnabled public String stateJson;     // pass back next turn
    }

    @AuraEnabled
    public static TurnResult advance(String userText, String stateJson, Id pageAccountId) {
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
        return handleCollecting(userText, st);
    }

    // ---------------------------------------------------------------- COLLECTING
    private static TurnResult handleCollecting(String userText, State st) {
        AgentPromptParser parser = AgentParserFactory.getParser();
        AgentParseResult pr = parser.parse(userText, new AgentContext(st.accountId));

        if (st.typeOfLoad == null && pr.typeOfLoad != null) {
            st.typeOfLoad = pr.typeOfLoad;
        }
        mergeFields(st, pr.fieldMap);

        // Resolve the account if we don't have one yet.
        if (st.accountId == null) {
            if (String.isNotBlank(pr.accountHint)) {
                Agent_ResolveAccount.Request rq = new Agent_ResolveAccount.Request();
                rq.searchTerm = pr.accountHint;
                AgentActionResult ar = Agent_ResolveAccount.resolve(new List<Agent_ResolveAccount.Request>{ rq })[0];
                if (ar.success && ar.recordId != null) {
                    st.accountId = ar.recordId;
                } else {
                    return needInput(st, ar.message, new List<String>{ 'Account' });
                }
            } else {
                return needInput(st, 'Which account is this Loading Advice for?', new List<String>{ 'Account' });
            }
        }
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
            return needInput(st, prev.message, prev.missingFields);
        }
        TurnResult err = base(st);
        err.status = AgentActionResult.STATUS_ERROR;
        err.message = prev.message;
        return err;
    }

    // ---------------------------------------------------------------- AWAITING_CONFIRM
    private static TurnResult handleConfirm(String userText, State st) {
        String ans = userText == null ? '' : userText.trim().toLowerCase();
        if (ans.startsWith('y') || ans.startsWith('proceed') || ans.startsWith('confirm')) {
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
        AgentActionResult submitRes = AgentApprovalService.submit(st.loadingAdviceId);

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
            ? 'Done. Created the Opportunity, Order, Loading Advice and Line, and submitted for approval. ' + submitRes.message
            : 'Created the records, but the approval submit did not complete: ' + submitRes.message;
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
            List<Account> a = [SELECT Name FROM Account WHERE Id = :st.accountId LIMIT 1];
            if (!a.isEmpty()) {
                acctName = a[0].Name;
            }
        }
        String prodName;
        Object pid = st.lineFields.get('Product_DKL__c');
        if (pid != null) {
            Id productId = (Id) String.valueOf(pid);
            List<Product2> p = [SELECT Name FROM Product2 WHERE Id = :productId LIMIT 1];
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
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(stateJson);
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

    private static TurnResult needInput(State st, String message, List<String> missing) {
        st.phase = PHASE_COLLECTING;
        TurnResult out = base(st);
        out.status = AgentActionResult.STATUS_NEEDS_INPUT;
        out.success = false;
        out.message = message;
        out.missingFields = missing == null ? new List<String>() : missing;
        return out;
    }
}
