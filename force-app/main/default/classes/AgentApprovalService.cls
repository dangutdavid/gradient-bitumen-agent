/**
 * Phase 3 — headless approval submit.
 * Runs the autolaunched flow LA_Submit_For_Approval_Headless (a screen-free clone of the
 * manual "Loading Advice - Submit for Approval" flow) via Flow.Interview, reads its output
 * variables (resultStatus / resultMessage), and returns a uniform AgentActionResult.
 *
 * The flow does the real work in the same run mode as the manual path
 * (SystemModeWithoutSharing): updates Status/Approval_Status, generates the internal PDF,
 * builds attachments, and fires the bell alert + approver email.
 */
public with sharing class AgentApprovalService {

    private static final String HEADLESS_FLOW = 'LA_Submit_For_Approval_Headless';

    public static AgentActionResult submit(Id loadingAdviceId) {
        if (loadingAdviceId == null) {
            return AgentActionResult.needsInput('No Loading Advice Id provided.', new List<String>{ 'loadingAdviceId' });
        }
        try {
            Flow.Interview flow = Flow.Interview.createInterview(
                HEADLESS_FLOW,
                new Map<String, Object>{ 'recordId' => String.valueOf(loadingAdviceId) });
            flow.start();

            String status = (String) flow.getVariableValue('resultStatus');
            String message = (String) flow.getVariableValue('resultMessage');

            if (status == 'ERROR') {
                return AgentActionResult.error(
                    String.isNotBlank(message) ? message : 'Submit for approval failed.')
                    .withRecord(loadingAdviceId);
            }
            return AgentActionResult.ok(
                String.isNotBlank(message) ? message : 'Submitted for approval (Pending 1st Approver).', null)
                .withRecord(loadingAdviceId);
        } catch (Exception e) {
            return AgentActionResult.error('Submit for approval failed: ' + e.getMessage())
                .withRecord(loadingAdviceId);
        }
    }
}
