/**
 * DTO carrying the parsed field values for the whole sales chain
 * (Opportunity → Order → Loading Advice → Line) from a single prompt.
 *
 * Field maps are keyed by sObject API name so the (future, Phase 4) parser can emit them
 * directly and preview/commit can build records generically. accountId and typeOfLoad are
 * controlled by the agent (resolved account + chosen load type), not parsed into the maps.
 * confirmationToken is supplied on commit and must match the previewed summary.
 */
public class AgentChainRequest {
    public Id accountId;
    public String typeOfLoad;          // 'Commercial' | 'Stock Transfer'
    public String confirmationToken;   // required by commit; ignored by preview

    public Map<String, Object> oppFields;
    public Map<String, Object> orderFields;
    public Map<String, Object> laFields;
    public Map<String, Object> lineFields;

    public AgentChainRequest() {
        this.oppFields = new Map<String, Object>();
        this.orderFields = new Map<String, Object>();
        this.laFields = new Map<String, Object>();
        this.lineFields = new Map<String, Object>();
    }

    /**
     * Builds the DTO from a JSON payload. We parse untyped (not JSON.deserialize into the
     * typed class) because the field maps are Map<String,Object>, which the strict typed
     * deserializer rejects. Values arrive as Strings/numbers and are coerced to field types
     * at commit time.
     */
    public static AgentChainRequest fromJson(String payload) {
        AgentChainRequest req = new AgentChainRequest();
        if (String.isBlank(payload)) {
            return req;
        }
        Map<String, Object> top = (Map<String, Object>) JSON.deserializeUntyped(payload);
        if (top.get('accountId') != null) {
            req.accountId = (Id) String.valueOf(top.get('accountId'));
        }
        req.typeOfLoad = (String) top.get('typeOfLoad');
        req.confirmationToken = (String) top.get('confirmationToken');
        req.oppFields = asMap(top.get('oppFields'));
        req.orderFields = asMap(top.get('orderFields'));
        req.laFields = asMap(top.get('laFields'));
        req.lineFields = asMap(top.get('lineFields'));
        return req;
    }

    private static Map<String, Object> asMap(Object o) {
        return o == null ? new Map<String, Object>() : (Map<String, Object>) o;
    }
}
