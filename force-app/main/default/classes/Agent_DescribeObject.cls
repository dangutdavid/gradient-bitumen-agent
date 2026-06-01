/**
 * Phase 1 agent action: describe an sObject's fields and relationships.
 * Returns, per field: API name, label, type, required (create-time), nillable,
 * createable, picklist values, and referenceTo targets. Read-only metadata.
 */
public with sharing class Agent_DescribeObject {

    public class Request {
        @InvocableVariable(label='Object API name' required=true)
        public String objectApiName;
    }

    @InvocableMethod(label='Describe Object' description='Return field and relationship metadata for an sObject.')
    public static List<AgentActionResult> describe(List<Request> requests) {
        List<AgentActionResult> results = new List<AgentActionResult>();
        for (Request req : requests) {
            results.add(describeOne(req == null ? null : req.objectApiName));
        }
        return results;
    }

    private static AgentActionResult describeOne(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return AgentActionResult.needsInput('No object API name provided.', new List<String>{ 'objectApiName' });
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) {
            return AgentActionResult.error('Object "' + objectApiName + '" was not found.');
        }
        Schema.DescribeSObjectResult dsr = sot.getDescribe();

        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        for (Schema.SObjectField f : dsr.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            Map<String, Object> fm = new Map<String, Object>{
                'apiName' => dfr.getName(),
                'label' => dfr.getLabel(),
                'type' => String.valueOf(dfr.getType()),
                // create-time required: not nillable, creatable, and not auto-defaulted
                'required' => (!dfr.isNillable() && dfr.isCreateable() && !dfr.isDefaultedOnCreate()),
                'createable' => dfr.isCreateable(),
                'nillable' => dfr.isNillable()
            };
            if (dfr.getType() == Schema.DisplayType.PICKLIST || dfr.getType() == Schema.DisplayType.MULTIPICKLIST) {
                List<String> vals = new List<String>();
                for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                    if (pe.isActive()) {
                        vals.add(pe.getValue());
                    }
                }
                fm.put('picklistValues', vals);
            }
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                List<String> refs = new List<String>();
                for (Schema.SObjectType r : dfr.getReferenceTo()) {
                    refs.add(r.getDescribe().getName());
                }
                fm.put('referenceTo', refs);
            }
            fields.add(fm);
        }

        Map<String, Object> data = new Map<String, Object>{
            'objectApiName' => dsr.getName(),
            'label' => dsr.getLabel(),
            'custom' => dsr.isCustom(),
            'createable' => dsr.isCreateable(),
            'fieldCount' => fields.size(),
            'fields' => fields
        };
        return AgentActionResult.ok('Described "' + dsr.getName() + '" (' + fields.size() + ' fields).', data);
    }
}
