/**
 * ExtolePersonCard — composite payload driving the per-person LWC on
 * Lead/Contact record pages.
 *
 * Two-phase load:
 *   1. getCardSkeleton(email) — base data (advocate identity, share links,
 *      rewards, referred-by, friend stubs with default-pending milestones).
 *      Heavy /v1/components milestone-allowlist fetch happens here so the
 *      result is reusable across all friend-detail calls.
 *   2. getFriendDetail(friendPersonId, ...) — one friend's identity + step
 *      progress + reward attribution. The LWC fires these in parallel for all
 *      friend stubs.
 *
 * The card self-hides in the LWC when Skeleton.hasAnyData is false.
 */
public with sharing class ExtolePersonCard {

    public class ShareLink {
        @AuraEnabled public String program;
        @AuraEnabled public String code;
        @AuraEnabled public String link;
        @AuraEnabled public String createdDate;
    }

    /** A person this advocate referred (outgoing relationship). */
    public class Friend {
        @AuraEnabled public String friendPersonId;
        @AuraEnabled public String email;
        @AuraEnabled public String displayName;
        @AuraEnabled public String sfdcRecordId;
        @AuraEnabled public String sfdcObjectType;
        @AuraEnabled public List<CampaignEngagement> engagements = new List<CampaignEngagement>();
    }

    public class CampaignEngagement {
        @AuraEnabled public String program;
        @AuraEnabled public String campaignId;
        @AuraEnabled public String shareableCode;
        @AuraEnabled public String createdDate;
        @AuraEnabled public RewardSummary reward;
        @AuraEnabled public List<Milestone> milestones = new List<Milestone>();
    }

    public class Milestone {
        @AuraEnabled public String name;
        @AuraEnabled public String displayName;
        @AuraEnabled public String eventDate;
        @AuraEnabled public String quality;
        @AuraEnabled public Boolean completed;
    }

    public class IncomingReferral {
        @AuraEnabled public String advocatePersonId;
        @AuraEnabled public String email;
        @AuraEnabled public String displayName;
        @AuraEnabled public String sfdcRecordId;
        @AuraEnabled public String sfdcObjectType;
        @AuraEnabled public String program;
        @AuraEnabled public String shareableCode;
        @AuraEnabled public String createdDate;
    }

    public class RewardSummary {
        @AuraEnabled public String state;
        @AuraEnabled public String amountLabel;
        @AuraEnabled public String program;
        @AuraEnabled public String earnedDate;
        @AuraEnabled public String causeEventId;
    }

    /** Phase-1 payload. Friend stubs in `friends` have placeholders for
     *  identity (no email/name yet) and milestones default to all-pending so
     *  the LWC can render the structure immediately. */
    public class Skeleton {
        @AuraEnabled public String personId;
        @AuraEnabled public String email;
        @AuraEnabled public String displayName;
        @AuraEnabled public List<ShareLink> shareLinks = new List<ShareLink>();
        @AuraEnabled public List<RewardSummary> rewards = new List<RewardSummary>();
        @AuraEnabled public IncomingReferral referredBy;
        @AuraEnabled public List<Friend> friends = new List<Friend>();
        @AuraEnabled public List<FriendDetailRequest> friendRequests = new List<FriendDetailRequest>();
        @AuraEnabled public Boolean hasAnyData = false;
        @AuraEnabled public String totalEarnedLabel;
        @AuraEnabled public Integer totalFriendCount = 0;
    }

    /** Opaque-ish blob the LWC passes back when invoking getFriendDetail.
     *  Holds the slice of skeleton state needed to resolve this one friend. */
    public class FriendDetailRequest {
        @AuraEnabled public String friendPersonId;
        @AuraEnabled public String relsJson;        // relationship records for this friend
        @AuraEnabled public String milestonesJson;  // map campaignId -> allowlist
        @AuraEnabled public String rewardsJson;     // advocate rewards (for cause_event attribution)
    }

    public class SfdcLink {
        @AuraEnabled public String email;       // lowercased
        @AuraEnabled public String recordId;
        @AuraEnabled public String objectType;  // 'Lead' | 'Contact'
    }
}
