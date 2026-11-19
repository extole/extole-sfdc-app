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
        public String rewardId;
        @AuraEnabled
        public String state;
        @AuraEnabled
        public Decimal faceValue;
        @AuraEnabled
        public String faceValueType;
        @AuraEnabled
        public String amountLabel;
        @AuraEnabled
        public String dateEarned;
        @AuraEnabled
        public String programLabel;
        @AuraEnabled
        public String campaignId;
        // Who the reward is for, when it was earned for a referral.
        @AuraEnabled
        public String referrerId;
    }

    public class JourneyStep {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String dateCompleted;
        // True when the event happened but failed Extole's quality checks.
        @AuraEnabled
        public Boolean failed = false;
    }

    public class Friend {
        @AuraEnabled
        public String personId;
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String displayName;
        @AuraEnabled
        public String identityValue;
        @AuraEnabled
        public String program;
        @AuraEnabled
        public Reward reward;
        // 'rewarded', 'declined' or 'pending'
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
        public String identityKey;
        @AuraEnabled
        public String identityValue;
        @AuraEnabled
        public Reward reward;
        // 'rewarded', 'declined' or 'pending'
        @AuraEnabled
        public String status;
    }

    // One program the person is in themselves, with their steps and reward.
    public class OwnProgram {
        @AuraEnabled
        public String program;
        @AuraEnabled
        public List<JourneyStep> steps = new List<JourneyStep>();
        // 'rewarded', 'declined' or 'pending'
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Reward reward;
        // The referrer this program's reward or decision belongs to, when
        // Extole says so. Blank when it cannot tell.
        @AuraEnabled
        public String rewardReferrerId;
    }

    public class ReferredBy {
        @AuraEnabled
        public String personId;
        // When they were referred, from the relationship.
        @AuraEnabled
        public String referredDate;
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String displayName;
        @AuraEnabled
        public String identityValue;
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
        public ReferredBy referredBy;
        @AuraEnabled
        public Boolean hasAnyData = false;
        // Link to this person's profile in My Extole. Null when unknown.
        @AuraEnabled
        public String profileUrl;
        // Everyone this person was referred by, one per program. referredBy is the first.
        @AuraEnabled
        public List<ReferredBy> referrers = new List<ReferredBy>();
        // This person's own offers: one per program they are in themselves.
        @AuraEnabled
        public List<OwnProgram> ownPrograms = new List<OwnProgram>();
        // What each program pays, by program, so a reward with no row yet can
        // still show an amount: the advocate's reward for a friend, and this
        // person's own reward.
        @AuraEnabled
        public Map<String, String> advocateAmounts = new Map<String, String>();
        @AuraEnabled
        public Map<String, String> ownAmounts = new Map<String, String>();
        // A program's one unnamed reward, shown only on a declined friend
        // whose own amount is unknown.
        @AuraEnabled
        public Map<String, String> onlyAmounts = new Map<String, String>();
    }

    // What the offers card shows: the offers a person is in that aren't a referral.
    public class OffersData {
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String profileUrl;
        @AuraEnabled
        public List<OwnProgram> programs = new List<OwnProgram>();
        @AuraEnabled
        public Map<String, String> ownAmounts = new Map<String, String>();
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
