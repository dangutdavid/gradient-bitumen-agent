/**
 * Invocable wrapper over AgentChainService.commit.
 * Takes the chain request as JSON (must include a confirmationToken matching the preview),
 * creates Opp→Order→LA→Line in one all-or-nothing transaction, and returns the record links.
 */
public with sharing class Agent_CommitSalesChain {

    public class Request {
        @InvocableVariable(label='Chain request (JSON, incl. confirmationToken)' required=true)
        public String requestJson;
    }

    @InvocableMethod(label='Commit Sales Chain' description='Create the confirmed Opp→Order→LA→Line chain in one transaction (rolls back on any failure).')
    public static List<AgentActionResult> commitChain(List<Request> requests) {
        List<AgentActionResult> results = new List<AgentActionResult>();
        for (Request req : requests) {
            try {
                AgentChainRequest chainReq = AgentChainRequest.fromJson(req == null ? null : req.requestJson);
                results.add(AgentChainService.commitChain(chainReq));
            } catch (Exception e) {
                results.add(AgentActionResult.error('Could not parse chain request: ' + e.getMessage()));
            }
        }
        return results;
    }
}
