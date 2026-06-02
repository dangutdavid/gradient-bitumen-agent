/**
 * Phase 1 agent action: resolve a single Account from a free-text search term.
 * Strategy: exact Name match first, then a contains (LIKE) fallback.
 * Returns a clear disambiguation message (with candidate list in dataJson) when
 * the term is ambiguous, so the agent can ask the user to narrow it down.
 *
 * SCOPE (client decision #2, option 1): the agent is Gradient-only — BOTH the single-match
 * resolve and the disambiguation candidate list are constrained to the Gradient_Account record
 * type. A name matching only a non-Gradient (Greenville) account returns a clear NOT-FOUND,
 * never a silent wrong-account resolve and never an error.
 */
public with sharing class Agent_ResolveAccount {
  @TestVisible
  private static final String GRADIENT_ACCOUNT_RT = 'Gradient_Account';

  public class Request {
    @InvocableVariable(
      label='Account search term'
      description='Account name or partial name'
      required=true
    )
    public String searchTerm;
  }

  @InvocableMethod(
    label='Resolve Account'
    description='Find a single Account by name or partial name.'
  )
  public static List<AgentActionResult> resolve(List<Request> requests) {
    List<AgentActionResult> results = new List<AgentActionResult>();
    for (Request req : requests) {
      results.add(resolveOne(req == null ? null : req.searchTerm));
    }
    return results;
  }

  private static AgentActionResult resolveOne(String term) {
    if (String.isBlank(term)) {
      return AgentActionResult.needsInput(
        'No account name provided. What account is this for?',
        new List<String>{ 'account' }
      );
    }
    String trimmed = term.trim();

    // 1. Exact name match (Gradient accounts only)
    List<Account> exact = [
      SELECT Id, Name
      FROM Account
      WHERE Name = :trimmed AND RecordType.DeveloperName = :GRADIENT_ACCOUNT_RT
      LIMIT 5
    ];
    if (exact.size() == 1) {
      return AgentActionResult.ok(
          'Resolved account "' + exact[0].Name + '".',
          toMap(exact[0])
        )
        .withRecord(exact[0].Id);
    }
    if (exact.size() > 1) {
      AgentActionResult dup = AgentActionResult.needsInput(
        exact.size() +
          ' accounts are named exactly "' +
          trimmed +
          '". Which one?',
        new List<String>{ 'account' }
      );
      dup.summaryJson = JSON.serialize(toMaps(exact));
      return dup;
    }

    // 2. Contains fallback (Gradient accounts only — candidate list must not show Greenville)
    String likeTerm = '%' + trimmed + '%';
    List<Account> fuzzy = [
      SELECT Id, Name
      FROM Account
      WHERE
        Name LIKE :likeTerm
        AND RecordType.DeveloperName = :GRADIENT_ACCOUNT_RT
      ORDER BY Name
      LIMIT 10
    ];
    if (fuzzy.isEmpty()) {
      return AgentActionResult.needsInput(
        'No account found matching "' +
          trimmed +
          '". What is the account name?',
        new List<String>{ 'account' }
      );
    }
    if (fuzzy.size() == 1) {
      return AgentActionResult.ok(
          'Resolved account "' + fuzzy[0].Name + '" (partial match).',
          toMap(fuzzy[0])
        )
        .withRecord(fuzzy[0].Id);
    }
    AgentActionResult ambiguous = AgentActionResult.needsInput(
      fuzzy.size() + ' accounts match "' + trimmed + '". Which one?',
      new List<String>{ 'account' }
    );
    ambiguous.summaryJson = JSON.serialize(toMaps(fuzzy));
    return ambiguous;
  }

  private static Map<String, Object> toMap(Account a) {
    return new Map<String, Object>{ 'Id' => a.Id, 'Name' => a.Name };
  }

  private static List<Map<String, Object>> toMaps(List<Account> accounts) {
    List<Map<String, Object>> out = new List<Map<String, Object>>();
    for (Account a : accounts) {
      out.add(toMap(a));
    }
    return out;
  }
}
