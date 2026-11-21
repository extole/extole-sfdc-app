public with sharing class ExtolePersonCard {
    public class ShareLink {
        @AuraEnabled
        public String program;
        @AuraEnabled
        public String code;
        @AuraEnabled
        public String link;
    }

    public class Reward {
        @AuraEnabled
        public String state;
        @AuraEnabled
        public String amountLabel;
        @AuraEnabled
        public String dateEarned;
    }

    public class JourneyStep {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String dateCompleted;
    }

    public class Friend {
        @AuraEnabled
        public String personId;
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String displayName;
        @AuraEnabled
        public String program;
        @AuraEnabled
        public Reward reward;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String sfdcRecordId;
        @AuraEnabled
        public String sfdcObjectType;
        @AuraEnabled
        public List<JourneyStep> steps = new List<JourneyStep>();
    }

    public class FriendRef {
        @AuraEnabled
        public String personId;
        @AuraEnabled
        public String program;
        @AuraEnabled
        public Reward reward;
        // 'rewarded', 'declined' or 'pending'; null when it can't be known
        @AuraEnabled
        public String status;
    }

    public class ReferredBy {
        @AuraEnabled
        public String personId;
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String displayName;
        @AuraEnabled
        public String program;
        @AuraEnabled
        public String sfdcRecordId;
        @AuraEnabled
        public String sfdcObjectType;
    }

    public class CardData {
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String firstName;
        @AuraEnabled
        public String lastName;
        @AuraEnabled
        public List<ShareLink> shareLinks = new List<ShareLink>();
        @AuraEnabled
        public List<Friend> friends = new List<Friend>();
        @AuraEnabled
        public List<FriendRef> friendRefs = new List<FriendRef>();
        @AuraEnabled
        public Integer totalFriends = 0;
        @AuraEnabled
        public Boolean friendsTruncated = false;
        @AuraEnabled
        public Boolean rewardsTruncated = false;
        @AuraEnabled
        public Map<String, String> advocateAmounts = new Map<String, String>();
        @AuraEnabled
        public ReferredBy referredBy;
        @AuraEnabled
        public Boolean hasAnyData = false;
    }

    public class SfdcLink {
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String objectType;
    }
}
