public with sharing class ExtolePersonCardController {

    private static final String ZONES_PATH = ExtoleConstants.ZONES_PATH + '/sfdc_person_card';

    @AuraEnabled(cacheable=true)
    public static ExtolePersonCard.CardData getCardData(String email) {
        ExtolePersonCard.CardData result = new ExtolePersonCard.CardData();
        result.email = email;
        if (String.isBlank(email)) return result;

        try {
            ExtoleConfig config = new ExtoleConfig('Extole_API');
            ExtoleClient client = new ExtoleClient();

            HttpRequest req = new HttpRequest();
            req.setEndpoint(config.getEndpoint() + ZONES_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            if (!config.isNamedCredentialMode()) {
                req.setHeader('Authorization', config.getAuthHeader());
            }
            req.setTimeout(config.timeoutMs);
            req.setBody(JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{ 'email' => email }
            }));

            HttpResponse res = client.send(config, req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) return result;

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            result = parseCardData(body, email);

            List<String> emails = collectEmails(result);
            if (!emails.isEmpty()) {
                applySfdcLinks(result, attachSfdcLinks(emails));
            }
        } catch (Exception e) {
            System.debug('ExtolePersonCardController.getCardData ERROR: ' + e.getMessage());
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<ExtolePersonCard.SfdcLink> attachSfdcLinks(List<String> emails) {
        List<ExtolePersonCard.SfdcLink> out = new List<ExtolePersonCard.SfdcLink>();
        if (emails == null || emails.isEmpty()) return out;

        Set<String> emailSet = new Set<String>();
        for (String e : emails) {
            if (String.isNotBlank(e)) emailSet.add(e.toLowerCase());
        }
        if (emailSet.isEmpty()) return out;

        Map<String, Map<String, String>> match = new Map<String, Map<String, String>>();
        for (Lead l : [SELECT Id, Email FROM Lead WHERE Email IN :emailSet WITH SECURITY_ENFORCED LIMIT 200]) {
            if (l.Email == null) continue;
            String key = l.Email.toLowerCase();
            if (!match.containsKey(key)) {
                match.put(key, new Map<String, String>{ 'id' => l.Id, 'type' => 'Lead' });
            }
        }
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :emailSet WITH SECURITY_ENFORCED LIMIT 200]) {
            if (c.Email == null) continue;
            match.put(c.Email.toLowerCase(), new Map<String, String>{ 'id' => c.Id, 'type' => 'Contact' });
        }
        for (String k : match.keySet()) {
            ExtolePersonCard.SfdcLink link = new ExtolePersonCard.SfdcLink();
            link.email      = k;
            link.recordId   = match.get(k).get('id');
            link.objectType = match.get(k).get('type');
            out.add(link);
        }
        return out;
    }

    // ── Private helpers ───────────────────────────────────────────────────

    private static ExtolePersonCard.CardData parseCardData(Map<String, Object> body, String fallbackEmail) {
        ExtolePersonCard.CardData d = new ExtolePersonCard.CardData();
        d.email     = getString(body, 'email') != null ? getString(body, 'email') : fallbackEmail;
        d.firstName = getString(body, 'firstName');
        d.lastName  = getString(body, 'lastName');
        Object hasAny = body.get('hasAnyData');
        d.hasAnyData = (hasAny instanceof Boolean) ? (Boolean) hasAny : false;

        Object slRaw = body.get('shareLinks');
        if (slRaw instanceof List<Object>) {
            for (Object o : (List<Object>) slRaw) {
                Map<String, Object> m = (Map<String, Object>) o;
                ExtolePersonCard.ShareLink sl = new ExtolePersonCard.ShareLink();
                sl.program = getString(m, 'program');
                sl.code    = getString(m, 'code');
                sl.link    = getString(m, 'link');
                d.shareLinks.add(sl);
            }
        }

        Object friendsRaw = body.get('friends');
        if (friendsRaw instanceof List<Object>) {
            for (Object o : (List<Object>) friendsRaw) {
                Map<String, Object> m = (Map<String, Object>) o;
                ExtolePersonCard.Friend f = new ExtolePersonCard.Friend();
                f.personId    = getString(m, 'personId');
                f.email       = getString(m, 'email');
                f.displayName = getString(m, 'displayName');
                f.program     = getString(m, 'program');
                Object rRaw = m.get('reward');
                if (rRaw instanceof Map<String, Object>) {
                    f.reward = parseReward((Map<String, Object>) rRaw);
                }
                d.friends.add(f);
            }
        }

        Object rbRaw = body.get('referredBy');
        if (rbRaw instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) rbRaw;
            ExtolePersonCard.ReferredBy rb = new ExtolePersonCard.ReferredBy();
            rb.personId    = getString(m, 'personId');
            rb.email       = getString(m, 'email');
            rb.displayName = getString(m, 'displayName');
            rb.program     = getString(m, 'program');
            d.referredBy = rb;
        }

        return d;
    }

    private static ExtolePersonCard.Reward parseReward(Map<String, Object> m) {
        ExtolePersonCard.Reward r = new ExtolePersonCard.Reward();
        r.rewardId      = getString(m, 'rewardId');
        r.state         = getString(m, 'state');
        r.faceValueType = getString(m, 'faceValueType');
        r.amountLabel   = getString(m, 'amountLabel');
        r.dateEarned    = getString(m, 'dateEarned');
        r.programLabel  = getString(m, 'programLabel');
        r.campaignId    = getString(m, 'campaignId');
        Object fv = m.get('faceValue');
        if (fv != null) {
            try { r.faceValue = Decimal.valueOf(String.valueOf(fv)); } catch (Exception ignored) {}
        }
        return r;
    }

    private static List<String> collectEmails(ExtolePersonCard.CardData data) {
        List<String> emails = new List<String>();
        if (data.friends != null) {
            for (ExtolePersonCard.Friend f : data.friends) {
                if (String.isNotBlank(f.email)) emails.add(f.email);
            }
        }
        if (data.referredBy != null && String.isNotBlank(data.referredBy.email)) {
            emails.add(data.referredBy.email);
        }
        return emails;
    }

    private static void applySfdcLinks(ExtolePersonCard.CardData data, List<ExtolePersonCard.SfdcLink> links) {
        if (links == null || links.isEmpty()) return;
        Map<String, ExtolePersonCard.SfdcLink> byEmail = new Map<String, ExtolePersonCard.SfdcLink>();
        for (ExtolePersonCard.SfdcLink l : links) {
            if (l.email != null) byEmail.put(l.email.toLowerCase(), l);
        }
        if (data.friends != null) {
            for (ExtolePersonCard.Friend f : data.friends) {
                if (f.email == null) continue;
                ExtolePersonCard.SfdcLink l = byEmail.get(f.email.toLowerCase());
                if (l != null) { f.sfdcRecordId = l.recordId; f.sfdcObjectType = l.objectType; }
            }
        }
        if (data.referredBy != null && data.referredBy.email != null) {
            ExtolePersonCard.SfdcLink l = byEmail.get(data.referredBy.email.toLowerCase());
            if (l != null) { data.referredBy.sfdcRecordId = l.recordId; data.referredBy.sfdcObjectType = l.objectType; }
        }
    }

    private static String getString(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v instanceof String ? (String) v : null;
    }
}
