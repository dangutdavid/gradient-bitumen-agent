/**
 * Invocable wrapper over AgentApprovalService.submit.
 * Submits a Loading Advice for approval headlessly (runs the autolaunched flow).
 */
public with sharing class Agent_SubmitLAForApproval {

    public class Request {
        @InvocableVariable(label='Loading Advice Id' required=true)
        public Id loadingAdviceId;
    }

    @InvocableMethod(label='Submit Loading Advice for Approval' description='Headlessly submit a Loading Advice for approval (PDF + bell + email; status → Pending 1st Approver).')
    public static List<AgentActionResult> submit(List<Request> requests) {
        List<AgentActionResult> results = new List<AgentActionResult>();
        for (Request req : requests) {
            results.add(AgentApprovalService.submit(req == null ? null : req.loadingAdviceId));
        }
        return results;
    }
}
