/**
 * Shared test data builder for the sales-chain tests.
 * Builds an Account, a Product2, and valid AgentChainRequest objects.
 */
@isTest
public class AgentChainTestFactory {
  // The agent resolves only Gradient_Account records (client decision #2). Tests that rely on
  // an account being resolvable must create it with this record type.
  public static Id gradientAccountRtId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Gradient_Account')
      .getRecordTypeId();
  }

  public static Id greenvilleAccountRtId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('GreenVilleIndustrialAccount')
      .getRecordTypeId();
  }

  public static Account account() {
    Account a = new Account(
      Name = 'Chain Test Co',
      RecordTypeId = gradientAccountRtId()
    );
    insert a;
    return a;
  }

  public static Product2 product() {
    Product2 p = new Product2(
      Name = 'Bitumen 60/70',
      Family = 'Bitumen 60/70',
      IsActive = true
    );
    insert p;
    return p;
  }

  /** A fully-populated request for the given load type ('Commercial' / 'Stock Transfer'). */
  public static AgentChainRequest validRequest(
    String typeOfLoad,
    Id accountId,
    Id productId
  ) {
    AgentChainRequest req = new AgentChainRequest();
    req.accountId = accountId;
    req.typeOfLoad = typeOfLoad;
    req.oppFields = new Map<String, Object>{
      'Name' => 'Auto Opp - ' + typeOfLoad,
      'StageName' => 'Qualification',
      'CloseDate' => Date.today().addDays(30)
    };
    req.orderFields = new Map<String, Object>{
      'EffectiveDate' => Date.today(),
      'Status' => 'Draft'
    };
    req.laFields = new Map<String, Object>();
    req.lineFields = new Map<String, Object>{
      'Customer_DKL__c' => accountId,
      'CustomerType_DKL__c' => 'Credit',
      'Location_DKL__c' => 'Kano',
      'Product_DKL__c' => productId,
      'QuantityMT_DKL__c' => 30,
      'PricePerMT_DKL__c' => 450000
    };
    return req;
  }

  /** Computes and stamps the confirmation token (as the agent would after preview). */
  public static AgentChainRequest withToken(AgentChainRequest req) {
    req.confirmationToken = AgentChainService.token(req);
    return req;
  }

  /** Level 1 routing record so the headless approval flow resolves an approver. */
  public static void approvalRouting() {
    insert new Approvver_Availability__c(
      ApprovalStage_DKL__c = 'Level 1',
      Available_DKL__c = true,
      Approver_DKL__c = UserInfo.getUserId()
    );
  }

  private static Id commercialRtId() {
    return Schema.SObjectType.Loading_Advice__c.getRecordTypeInfosByDeveloperName()
      .get('Commercial_DKL')
      .getRecordTypeId();
  }

  /** Builds an Order → Loading Advice (Commercial) [→ Line], directly (no chain), for approval tests. */
  public static Loading_Advice__c loadingAdvice(
    Id accountId,
    Id productId,
    Boolean withLine
  ) {
    Order ord = new Order(
      AccountId = accountId,
      EffectiveDate = Date.today(),
      Status = 'Draft'
    );
    insert ord;
    Loading_Advice__c la = new Loading_Advice__c(
      Order_DKL__c = ord.Id,
      Account_DKL__c = accountId,
      RecordTypeId = commercialRtId()
    );
    insert la;
    if (withLine) {
      insert new Loading_Advice_Line__c(
        LoadingAdvice_DKL__c = la.Id,
        Customer_DKL__c = accountId,
        CustomerType_DKL__c = 'Credit',
        Location_DKL__c = 'Kano',
        Product_DKL__c = productId,
        QuantityMT_DKL__c = 30,
        PricePerMT_DKL__c = 450000
      );
    }
    return la;
  }
}
