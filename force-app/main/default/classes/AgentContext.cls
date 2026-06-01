/**
 * Context handed to a parser for a turn. Currently just the page's Account (from the
 * LWC @api recordId on an Account page); empty from the utility bar.
 */
public class AgentContext {
    public Id accountId;

    public AgentContext() {}

    public AgentContext(Id accountId) {
        this.accountId = accountId;
    }
}
