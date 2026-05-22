public with sharing class ExtolePersonCard {

    public class ShareLink {
        @AuraEnabled public String program;
        @AuraEnabled public String code;
        @AuraEnabled public String link;
    }

    public class Reward {
        @AuraEnabled public String  rewardId;
        @AuraEnabled public String  state;
        @AuraEnabled public Decimal faceValue;
        @AuraEnabled public String  faceValueType;
        @AuraEnabled public String  amountLabel;
        @AuraEnabled public String  dateEarned;
        @AuraEnabled public String  programLabel;
        @AuraEnabled public String  campaignId;
    }

    public class JourneyStep {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String dateCompleted;
    }

    public class Friend {
        @AuraEnabled public String personId;
        @AuraEnabled public String email;
        @AuraEnabled public String displayName;
        @AuraEnabled public String program;
        @AuraEnabled public Reward reward;
        @AuraEnabled public String sfdcRecordId;
        @AuraEnabled public String sfdcObjectType;
        @AuraEnabled public List<JourneyStep> steps = new List<JourneyStep>();
    }

    public class ReferredBy {
        @AuraEnabled public String personId;
        @AuraEnabled public String email;
        @AuraEnabled public String displayName;
        @AuraEnabled public String program;
        @AuraEnabled public String sfdcRecordId;
        @AuraEnabled public String sfdcObjectType;
    }

    public class CardData {
        @AuraEnabled public String      email;
        @AuraEnabled public String      firstName;
        @AuraEnabled public String      lastName;
        @AuraEnabled public List<ShareLink> shareLinks = new List<ShareLink>();
        @AuraEnabled public List<Friend>    friends    = new List<Friend>();
        @AuraEnabled public ReferredBy      referredBy;
        @AuraEnabled public Boolean         hasAnyData = false;
    }

    public class SfdcLink {
        @AuraEnabled public String email;
        @AuraEnabled public String recordId;
        @AuraEnabled public String objectType;
    }
}
