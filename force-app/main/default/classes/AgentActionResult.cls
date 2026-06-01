/**
 * Shared result wrapper for all Gradient Bitumen agent actions.
 * Uniform return shape so the agent (and tests) consume every action consistently.
 *
 * status drives the agent's next move:
 *   OK            - action succeeded, proceed.
 *   NEEDS_INPUT   - required field(s) missing / ambiguous; ask the user (see missingFields).
 *   NEEDS_CONFIRM - a summary is ready; ask "Proceed? (yes/no)" before writing.
 *   ERROR         - the action failed; surface the message.
 */
public class AgentActionResult {

    public static final String STATUS_OK = 'OK';
    public static final String STATUS_NEEDS_INPUT = 'NEEDS_INPUT';
    public static final String STATUS_NEEDS_CONFIRM = 'NEEDS_CONFIRM';
    public static final String STATUS_ERROR = 'ERROR';

    @InvocableVariable(label='Success')
    public Boolean success;

    @InvocableVariable(label='Status')
    public String status;

    @InvocableVariable(label='Record Id')
    public String recordId;

    @InvocableVariable(label='Record URL')
    public String recordUrl;

    @InvocableVariable(label='Missing Fields')
    public List<String> missingFields;

    @InvocableVariable(label='Summary (JSON)')
    public String summaryJson;

    @InvocableVariable(label='Message')
    public String message;

    public AgentActionResult() {
        this.success = true;
        this.status = STATUS_OK;
        this.missingFields = new List<String>();
    }

    public AgentActionResult(Boolean success, String status, String message) {
        this();
        this.success = success;
        this.status = status;
        this.message = message;
    }

    /** Success; optional payload serialized into summaryJson. */
    public static AgentActionResult ok(String message, Object summary) {
        AgentActionResult r = new AgentActionResult(true, STATUS_OK, message);
        if (summary != null) {
            r.summaryJson = JSON.serialize(summary);
        }
        return r;
    }

    /** Required input missing or ambiguous; report all gaps in missingFields. */
    public static AgentActionResult needsInput(String message, List<String> missing) {
        AgentActionResult r = new AgentActionResult(false, STATUS_NEEDS_INPUT, message);
        if (missing != null) {
            r.missingFields = missing;
        }
        return r;
    }

    /** A summary is ready; caller should confirm before any write. */
    public static AgentActionResult needsConfirm(String message, Object summary) {
        AgentActionResult r = new AgentActionResult(false, STATUS_NEEDS_CONFIRM, message);
        if (summary != null) {
            r.summaryJson = JSON.serialize(summary);
        }
        return r;
    }

    /** The action failed. */
    public static AgentActionResult error(String message) {
        return new AgentActionResult(false, STATUS_ERROR, message);
    }

    /** Attach a record Id and a best-effort Lightning URL. Chainable. */
    public AgentActionResult withRecord(Id rid) {
        if (rid != null) {
            this.recordId = String.valueOf(rid);
            try {
                this.recordUrl = URL.getOrgDomainUrl().toExternalForm() + '/' + rid;
            } catch (Exception e) {
                this.recordUrl = '/' + rid;
            }
        }
        return this;
    }
}
