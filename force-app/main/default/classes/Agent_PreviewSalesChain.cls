/**
 * Invocable wrapper over AgentChainService.preview.
 * Takes the chain request as JSON (Flow/Agentforce-friendly), returns the consolidated
 * preview result (NEEDS_INPUT with missingFields, or NEEDS_CONFIRM with summary + token).
 */
public with sharing class Agent_PreviewSalesChain {

    public class Request {
        @InvocableVariable(label='Chain request (JSON)' required=true)
        public String requestJson;
    }

    @InvocableMethod(label='Preview Sales Chain' description='Validate the whole Opp→Order→LA→Line chain and return consolidated missing fields or a confirmation summary.')
    public static List<AgentActionResult> preview(List<Request> requests) {
        List<AgentActionResult> results = new List<AgentActionResult>();
        for (Request req : requests) {
            try {
                AgentChainRequest chainReq = AgentChainRequest.fromJson(req == null ? null : req.requestJson);
                results.add(AgentChainService.preview(chainReq));
            } catch (Exception e) {
                results.add(AgentActionResult.error('Could not parse chain request: ' + e.getMessage()));
            }
        }
        return results;
    }
}
