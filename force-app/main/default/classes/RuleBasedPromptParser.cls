/**
 * v1 rule-based parser: regex for quantity+unit and price, keyword match for load type,
 * fuzzy match against Account / Product2 names, picklist matching from describe, and light
 * date parsing (close / start). Anything not confidently extracted is left out (and noted in
 * `unresolved`) for the controller's ask-loop — it never guesses.
 *
 * Honest scope: this is structured extraction with smart pre-fill, not true NLU. The
 * AgentPromptParser seam lets an LLM parser replace it later with no other change.
 */
public with sharing class RuleBasedPromptParser implements AgentPromptParser {

    public AgentParseResult parse(String text, AgentContext ctx) {
        AgentParseResult res = new AgentParseResult();
        if (String.isBlank(text)) {
            return res;
        }
        String lower = text.toLowerCase();

        // Customer comes from the Account page context when present.
        if (ctx != null && ctx.accountId != null) {
            res.fieldMap.put('Customer_DKL__c', ctx.accountId);
        }

        // --- Load type ---
        if (lower.contains('stock transfer')) {
            res.typeOfLoad = 'Stock Transfer';
        } else if (lower.contains('commercial')) {
            res.typeOfLoad = 'Commercial';
        }

        // --- Quantity + unit -> QuantityMT_DKL__c ---
        Matcher mQty = Pattern.compile('(?i)(\\d+(?:\\.\\d+)?)\\s*(?:mt|metric\\s*tonnes?|tonnes?|tons?)\\b').matcher(text);
        if (mQty.find()) {
            res.fieldMap.put('QuantityMT_DKL__c', Decimal.valueOf(mQty.group(1)));
        }

        // --- Price -> PricePerMT_DKL__c (currency-prefixed or after price/at/@; >= 1000) ---
        Matcher mPrice = Pattern.compile('(?i)(?:ngn|n|₦|=n=|price|@|at)\\s*:?\\s*([0-9][0-9,]{2,}(?:\\.[0-9]+)?)\\s*(?:/\\s*mt|per\\s*mt|/mt)?').matcher(text);
        while (mPrice.find()) {
            Decimal val = Decimal.valueOf(mPrice.group(1).replace(',', ''));
            if (val >= 1000) {
                res.fieldMap.put('PricePerMT_DKL__c', val);
                break;
            }
        }

        // --- Location -> Location_DKL__c (requires an explicit delivery/location cue) ---
        Matcher mLoc = Pattern.compile('(?i)(?:deliver(?:ed)?\\s+to|delivery\\s+to|location\\s*[:]?)\\s+([A-Z][A-Za-z]+)').matcher(text);
        if (mLoc.find()) {
            res.fieldMap.put('Location_DKL__c', mLoc.group(1).trim());
        }

        // --- Customer Type (picklist match from describe) ---
        String custType = matchPicklist('Loading_Advice_Line__c', 'CustomerType_DKL__c', lower);
        if (custType != null) {
            res.fieldMap.put('CustomerType_DKL__c', custType);
        }

        // --- Dates: close -> CloseDate, start -> EffectiveDate ---
        Date closeDate = dateAfter(text, '(?i)close\\w*\\D{0,12}?');
        if (closeDate != null) {
            res.fieldMap.put('CloseDate', closeDate);
        }
        Date startDate = dateAfter(text, '(?i)start\\w*\\D{0,12}?');
        if (startDate != null) {
            res.fieldMap.put('EffectiveDate', startDate);
        }

        // --- Product (fuzzy match against Product2) ---
        matchProduct(lower, res);

        // --- Account hint (utility-bar case only) ---
        if (ctx == null || ctx.accountId == null) {
            Matcher mAcc = Pattern.compile('(?i)\\bfor\\s+(.+?)(?:\\s+[-–—]|,|\\.|$)').matcher(text);
            if (mAcc.find()) {
                String candidate = mAcc.group(1).trim();
                // ignore trivially short / verb-like candidates
                if (candidate.length() >= 3 && !candidate.toLowerCase().startsWith('approval')) {
                    res.accountHint = candidate;
                }
            }
        }

        return res;
    }

    /** Returns the first active picklist value whose label appears in the (lowercased) text. */
    private static String matchPicklist(String objApi, String fieldApi, String lower) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objApi);
        if (sot == null) {
            return null;
        }
        Schema.SObjectField f = sot.getDescribe().fields.getMap().get(fieldApi);
        if (f == null) {
            return null;
        }
        for (Schema.PicklistEntry pe : f.getDescribe().getPicklistValues()) {
            if (pe.isActive() && lower.contains(pe.getValue().toLowerCase())) {
                return pe.getValue();
            }
        }
        return null;
    }

    /**
     * Fuzzy product match. Prefers a full-name containment; otherwise a first-token match.
     * Exactly one candidate -> resolved; more than one -> left unresolved (never guess).
     */
    private static void matchProduct(String lower, AgentParseResult res) {
        List<Product2> prods = [SELECT Id, Name FROM Product2 WHERE IsActive = true LIMIT 200];
        Set<Id> full = new Set<Id>();
        Map<Id, Product2> byId = new Map<Id, Product2>();
        for (Product2 p : prods) {
            byId.put(p.Id, p);
            if (String.isNotBlank(p.Name) && lower.contains(p.Name.toLowerCase())) {
                full.add(p.Id);
            }
        }
        Set<Id> candidates = full;
        if (candidates.isEmpty()) {
            for (Product2 p : prods) {
                String token = firstToken(p.Name);
                if (token != null && token.length() >= 4 && lower.contains(token)) {
                    candidates.add(p.Id);
                }
            }
        }
        if (candidates.size() == 1) {
            res.fieldMap.put('Product_DKL__c', new List<Id>(candidates)[0]);
        } else if (candidates.size() > 1) {
            res.unresolved.add('Product (matched ' + candidates.size() + ' products — please specify which)');
        }
    }

    private static String firstToken(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        return name.toLowerCase().trim().split('\\s+')[0];
    }

    /** Finds a date (dd/MM[/yyyy] or "today") following a cue regex; null if none. */
    private static Date dateAfter(String text, String cueRegex) {
        Matcher m = Pattern.compile(cueRegex + '(today|\\d{1,2}/\\d{1,2}(?:/\\d{2,4})?)').matcher(text);
        if (m.find()) {
            return parseDateToken(m.group(1));
        }
        return null;
    }

    private static Date parseDateToken(String tok) {
        if (String.isBlank(tok)) {
            return null;
        }
        String t = tok.trim().toLowerCase();
        if (t == 'today') {
            return Date.today();
        }
        List<String> parts = t.split('/');
        if (parts.size() >= 2) {
            Integer d = Integer.valueOf(parts[0]);
            Integer mo = Integer.valueOf(parts[1]);
            Integer yr = parts.size() >= 3 ? normYear(parts[2]) : Date.today().year();
            return Date.newInstance(yr, mo, d);
        }
        return null;
    }

    private static Integer normYear(String y) {
        Integer n = Integer.valueOf(y);
        return n < 100 ? 2000 + n : n;
    }
}
