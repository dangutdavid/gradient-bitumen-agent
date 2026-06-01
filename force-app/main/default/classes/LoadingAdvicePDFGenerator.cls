public class LoadingAdvicePDFGenerator {
    
    @InvocableMethod(label='Generate Loading Advice PDF' description='Generates PDF and returns ContentVersion ID for Email')
    public static List<Id> generatePDFAndAttach(List<Id> loadingAdviceIds) {
        
        List<Id> contentVersionIds = new List<Id>();
        List<ContentVersion> cvListToInsert = new List<ContentVersion>();
        
        // FIXED: Restored the bulkified query to properly map the Loading Advice IDs
        Map<Id, Loading_Advice__c> laMap = new Map<Id, Loading_Advice__c>(
            [SELECT Id, Name FROM Loading_Advice__c WHERE Id IN :loadingAdviceIds]
        );
        
        List<Loading_Advice_Line__c> lines = [
            SELECT LoadingAdvice_DKL__c, Product_DKL__r.Name 
            FROM Loading_Advice_Line__c 
            WHERE LoadingAdvice_DKL__c IN :loadingAdviceIds
        ];
        
        Map<Id, String> productMap = new Map<Id, String>();
        for(Loading_Advice_Line__c line : lines) {
            if(!productMap.containsKey(line.LoadingAdvice_DKL__c) && line.Product_DKL__r != null) {
                // Keep the standard product name for the Title
                String originalProdName = line.Product_DKL__r.Name;
                productMap.put(line.LoadingAdvice_DKL__c, originalProdName);
            }
        }
        
        // Get today's date in the format Namana requested (e.g., 30.04.2026)
        String dateStr = Datetime.now().format('dd.MM.yyyy');
        
        for (Id recordId : loadingAdviceIds) {
            PageReference pdfPage = Page.LoadingAdvicePDFTemplate; 
            pdfPage.getParameters().put('id', recordId);
            
            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Mock PDF Data for Testing');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }
            
            String laNumber = laMap.containsKey(recordId) ? laMap.get(recordId).Name : 'LA';
            String prodName = productMap.containsKey(recordId) ? productMap.get(recordId) : 'Unknown_Product';
            
            // NEW FORMAT: [Product Name] Loading Advice - [Number] - [Date]
            String displayTitle = prodName + ' Loading Advice - ' + laNumber + ' - ' + dateStr;
            
            // Clean file name for actual download
            String safeProdName = prodName.replaceAll('[^a-zA-Z0-9\\s]', '_').replaceAll('\\s+', '_');
            String safeDateStr = dateStr.replaceAll('\\.', '_');
            String downloadName = safeProdName + '_Loading_Advice_' + laNumber + '_' + safeDateStr + '.pdf';
            
            ContentVersion cv = new ContentVersion();
            cv.Title = displayTitle;
            cv.PathOnClient = downloadName; 
            cv.VersionData = pdfBlob;
            
            cv.FirstPublishLocationId = recordId; 
            cvListToInsert.add(cv);
        }
        
        if (!cvListToInsert.isEmpty()) {
            insert cvListToInsert;
            for (ContentVersion cv : cvListToInsert) {
                contentVersionIds.add(cv.Id);
            }
        }
        
        return contentVersionIds;
    }
}