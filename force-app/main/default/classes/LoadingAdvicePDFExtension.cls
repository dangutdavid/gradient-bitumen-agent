public class LoadingAdvicePDFExtension {
    public Loading_Advice__c loadingAdvice { get; set; }
    public List<Loading_Advice_Line__c> lines { get; set; }
    public String productFamily { get; set; }
    public String recordTypeName { get; set; } 

    public LoadingAdvicePDFExtension(ApexPages.StandardController stdController) {
        Id recordId = stdController.getId();
        
        
        loadingAdvice = [SELECT Id, Name, RecordTypeId, RecordType.DeveloperName, 
                         X1ApprovedBy_DKL__c, X1stApprovedOn_DKL__c, 
                         X2ndApprovedBy_DKL__c, X2ndApprovedOn_DKL__c, 
                         Account_DKL__c, Approval_Status_DKL__c, Comments_DKL__c, 
                         CreatedById, CurrencyIsoCode, CurrentApprover_DKL__c, 
                         DeliveredlAmount_DKL__c, DeliveredQuantity_DKL__c, 
                         DispatchPDFContentDocumentId_DKL__c, DiversionReason_DKL__c, 
                         DivertedFrom_DKL__c, DriverName_DKL__c, DriverPhoneNo_DKL__c, 
                         FinanceApprovedBy_DKL__c, FinanceApprovedOn_DKL__c, 
                         LastModifiedById, LoadingAdviceNumber_DKL__c, 
                         LogisticsEmailSent_DKL__c, Opportunity_DKL__c, Order_DKL__c, 
                         ProductFamily_DKL__c, RevisedDocumentNeeded_DKL__c, 
                         RollUpAmount_DKL__c, RollUpQuantity_DKL__c, Status_DKL__c, 
                         Submittedby_DKL__c, SubmittedOn_DKL__c, SupersededBy_DKL__c, 
                         TruckPlateNo_DKL__c, VersionNumber_DKL__c, WaybillNumber_DKL__c 
                         FROM Loading_Advice__c 
                         WHERE Id = :recordId LIMIT 1];      
                         
        if (loadingAdvice.RecordType != null) {
            recordTypeName = loadingAdvice.RecordType.DeveloperName;
        } else {
            recordTypeName = 'Commercial_DKL'; 
        }
        
        
        lines = [SELECT Id, Customer_DKL__r.Name, Location_DKL__c, Product_DKL__r.Name, 
                        Product_DKL__r.Family, QuantityMT_DKL__c, LPO_Number__c, 
                        DeliveryMode_DKL__c, PaymentTerm_DKL__c, PaymentStatusText_DKL__c,  
                        PricePerMT_DKL__c, TransportationPerMT_DKL__c, HeatingPerTruck_DKL__c,  
                        SprayerRate_DKL__c, NumberofSprayerDays_DKL__c, ProductSubtotal_DKL__c, 
                        PlantLocation_DKL__c, GrandTotal_DKL__c
                 FROM Loading_Advice_Line__c
                 WHERE LoadingAdvice_DKL__c = :recordId];
                 
        if (!lines.isEmpty() && lines[0].Product_DKL__r != null) {
            productFamily = lines[0].Product_DKL__r.Family;
        } else {
            productFamily = 'N/A';
        }
    }
}