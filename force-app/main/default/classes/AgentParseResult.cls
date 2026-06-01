/**
 * Structured output of a parser turn.
 *  fieldMap    - confidently-extracted values keyed by sObject API name (across all objects);
 *                the conversation controller routes them into the right record bucket.
 *  unresolved  - notes about things the parser could NOT confidently resolve (e.g. an
 *                ambiguous product). Left for the ask-loop; the parser never guesses.
 *  typeOfLoad  - 'Commercial' | 'Stock Transfer' | null.
 *  accountHint - a candidate account name lifted from the text (utility-bar case), for the
 *                controller to resolve via Agent_ResolveAccount.
 */
public class AgentParseResult {
    public Map<String, Object> fieldMap;
    public List<String> unresolved;
    public String typeOfLoad;
    public String accountHint;

    public AgentParseResult() {
        this.fieldMap = new Map<String, Object>();
        this.unresolved = new List<String>();
    }
}
