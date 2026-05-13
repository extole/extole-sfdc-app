/**
 * ExtolePersonCard — composite payload returned by ExtolePersonCardController
 * to drive the per-person LWC on Lead/Contact record pages.
 *
 * Shape is data-driven: each section self-hides in the LWC when its slice is
 * empty, so the card renders zero-height when there's no Extole activity for
 * the host record.
 */
public with sharing class ExtolePersonCard {

    @AuraEnabled public String personId;
    @AuraEnabled public String email;
    @AuraEnabled public String displayName;
    @AuraEnabled public List<ShareLink> shareLinks = new List<ShareLink>();
    @AuraEnabled public List<Friend> friends = new List<Friend>();
    @AuraEnabled public List<RewardSummary> rewards = new List<RewardSummary>();
    @AuraEnabled public IncomingReferral referredBy;   // populated when this person is a friend of someone else
    @AuraEnabled public Boolean hasAnyData = false;
    @AuraEnabled public String totalEarnedLabel;       // pre-formatted summary, e.g. "$235 across 3 friends"

    public class ShareLink {
        @AuraEnabled public String program;
        @AuraEnabled public String code;
        @AuraEnabled public String link;
        @AuraEnabled public String createdDate;
    }

    /** A person this advocate referred (outgoing relationship). One entry per
     *  unique friend identity, regardless of how many campaigns they've
     *  engaged with. Per-campaign detail lives in `engagements`. */
    public class Friend {
        @AuraEnabled public String friendPersonId;
        @AuraEnabled public String email;              // primary display + cross-record key
        @AuraEnabled public String displayName;        // name if known, else email
        @AuraEnabled public String sfdcRecordId;       // Lead.Id or Contact.Id when email matches, else null
        @AuraEnabled public String sfdcObjectType;     // 'Lead' | 'Contact' | null
        @AuraEnabled public List<CampaignEngagement> engagements = new List<CampaignEngagement>();
    }

    /** A friend's activity within one specific campaign. A friend can have
     *  multiple of these when they've engaged with more than one program. */
    public class CampaignEngagement {
        @AuraEnabled public String program;
        @AuraEnabled public String campaignId;
        @AuraEnabled public String shareableCode;      // which of advocate's links they used
        @AuraEnabled public String createdDate;
        @AuraEnabled public RewardSummary reward;      // null if no reward attributed in this campaign
        @AuraEnabled public List<Milestone> milestones = new List<Milestone>();
    }

    /** A journey milestone — may be completed (event fired) or pending
     *  (campaign expects this event but the friend hasn't fired it yet). */
    public class Milestone {
        @AuraEnabled public String name;               // step event name, e.g. "register"
        @AuraEnabled public String displayName;        // humanized: "Register"
        @AuraEnabled public String eventDate;          // populated only when completed=true
        @AuraEnabled public String quality;            // HIGH/...
        @AuraEnabled public Boolean completed;         // true if friend has fired this event
    }

    /** An advocate this person was referred by (incoming relationship). */
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
        @AuraEnabled public String state;              // PAID, EARNED, PENDING, CANCELED
        @AuraEnabled public String amountLabel;        // formatted, e.g. "$50"
        @AuraEnabled public String program;
        @AuraEnabled public String earnedDate;
        @AuraEnabled public String causeEventId;       // ties to a Friend.friendPersonId via cause chain
    }
}
