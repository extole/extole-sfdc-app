/**
 * ExtoleSafetyCheckService
 *
 * Before deleting an event configuration, calls the Extole API to check whether
 * the event name is referenced by any active/published campaign.
 *
 * Result shape:
 *   { "status": "FOUND" | "NOT_FOUND" | "UNKNOWN",
 *     "campaignName": "<first matching campaign name>",
 *     "campaignId":   "<first matching campaign id>" }
 *
 * Timeout: 10 seconds. On timeout, network error, or any API error → UNKNOWN.
 * Only active/published campaigns count as FOUND — drafts, paused, archived excluded.
 *
 * Named Credential: callout:Extole_API  (same credential as v1 reporting)
 */
public with sharing class ExtoleSafetyCheckService {

    // Extole API endpoint for campaign trigger information
    // v4/campaigns returns campaigns with their trigger event_names
    private static final String CAMPAIGNS_ENDPOINT = 'callout:Extole_API/v4/campaigns?state=PUBLISHED,ACTIVE';

    // Statuses that count as "in active use"
    private static final Set<String> ACTIVE_STATES = new Set<String>{ 'PUBLISHED', 'ACTIVE' };

    /**
     * Check whether the given Extole event name is referenced by an active/published campaign.
     *
     * @param eventName  The Extole event_name to search for (e.g. 'lead_created')
     * @return Map with keys: status (FOUND/NOT_FOUND/UNKNOWN), campaignName, campaignId
     */
    public static Map<String, Object> checkEventUsage(String eventName) {
        Map<String, Object> result = new Map<String, Object>{
            'status'       => 'UNKNOWN',
            'campaignName' => null,
            'campaignId'   => null
        };

        if (String.isBlank(eventName)) {
            result.put('status', 'NOT_FOUND');
            return result;
        }

        DateTime startTime = DateTime.now();
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(CAMPAIGNS_ENDPOINT);
            req.setMethod('GET');
            req.setTimeout(10000); // 10 second timeout per spec
            req.setHeader('Accept', 'application/json');

            HttpResponse res = new Http().send(req);

            // Log the check to Extole_Event_Log__c
            Long durationMs = DateTime.now().getTime() - startTime.getTime();
            System.debug('ExtoleSafetyCheckService.checkEventUsage: HTTP '
                + res.getStatusCode() + ' in ' + durationMs + 'ms');

            if (res.getStatusCode() != 200) {
                System.debug('ExtoleSafetyCheckService: non-200 response: ' + res.getBody());
                return result; // UNKNOWN
            }

            // Parse campaign list and scan for the event name
            return scanCampaigns(res.getBody(), eventName);

        } catch (System.CalloutException e) {
            // Covers timeout, network errors
            System.debug('ExtoleSafetyCheckService.checkEventUsage CalloutException: ' + e.getMessage());
            return result; // UNKNOWN
        } catch (Exception e) {
            System.debug('ExtoleSafetyCheckService.checkEventUsage Exception: ' + e.getMessage());
            return result; // UNKNOWN
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Campaign JSON scanning
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Parse the campaigns API response body and look for the given event name.
     * Short-circuits on first match (boolean check — not exhaustive).
     */
    @TestVisible
    static Map<String, Object> scanCampaigns(String responseBody, String eventName) {
        Map<String, Object> result = new Map<String, Object>{
            'status'       => 'NOT_FOUND',
            'campaignName' => null,
            'campaignId'   => null
        };

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(responseBody);
        } catch (Exception e) {
            System.debug('ExtoleSafetyCheckService.scanCampaigns: JSON parse error ' + e.getMessage());
            result.put('status', 'UNKNOWN');
            return result;
        }

        // The Extole campaigns API returns either a list at root or { campaigns: [...] }
        List<Object> campaigns = new List<Object>();
        if (parsed instanceof List<Object>) {
            campaigns = (List<Object>) parsed;
        } else if (parsed instanceof Map<String, Object>) {
            Map<String, Object> wrapper = (Map<String, Object>) parsed;
            Object campaignsRaw = wrapper.get('campaigns');
            if (campaignsRaw instanceof List<Object>) {
                campaigns = (List<Object>) campaignsRaw;
            }
        }

        for (Object rawCampaign : campaigns) {
            if (!(rawCampaign instanceof Map<String, Object>)) continue;
            Map<String, Object> campaign = (Map<String, Object>) rawCampaign;

            // Only flag active/published campaigns
            String state = (String) campaign.get('state');
            if (state == null || !ACTIVE_STATES.contains(state.toUpperCase())) continue;

            // Look in trigger event_names — structure varies by Extole API version.
            // Check common locations: triggers[], event_names[], builds[].triggers[].event_names[]
            if (campaignReferencesEvent(campaign, eventName)) {
                result.put('status', 'FOUND');
                result.put('campaignName', campaign.get('name'));
                result.put('campaignId',   campaign.get('id'));
                return result; // Short-circuit on first match
            }
        }

        return result; // NOT_FOUND
    }

    /**
     * Check whether a single campaign object references the given event name.
     * Checks multiple known response shapes from the Extole API.
     */
    private static Boolean campaignReferencesEvent(Map<String, Object> campaign, String eventName) {
        // Shape 1: campaign.event_names = ["lead_created", ...]
        Object eventNamesRaw = campaign.get('event_names');
        if (eventNamesRaw instanceof List<Object>) {
            for (Object en : (List<Object>) eventNamesRaw) {
                if (eventName.equalsIgnoreCase(String.valueOf(en))) return true;
            }
        }

        // Shape 2: campaign.triggers = [{event_name: "..."}, ...]
        Object triggersRaw = campaign.get('triggers');
        if (triggersRaw instanceof List<Object>) {
            for (Object t : (List<Object>) triggersRaw) {
                if (!(t instanceof Map<String, Object>)) continue;
                Map<String, Object> trig = (Map<String, Object>) t;
                Object en = trig.get('event_name');
                if (en != null && eventName.equalsIgnoreCase(String.valueOf(en))) return true;
                // Also check event_names array within each trigger
                Object innerEventNames = trig.get('event_names');
                if (innerEventNames instanceof List<Object>) {
                    for (Object ien : (List<Object>) innerEventNames) {
                        if (eventName.equalsIgnoreCase(String.valueOf(ien))) return true;
                    }
                }
            }
        }

        // Shape 3: campaign.builds[].triggers[].event_names[]
        Object buildsRaw = campaign.get('builds');
        if (buildsRaw instanceof List<Object>) {
            for (Object b : (List<Object>) buildsRaw) {
                if (!(b instanceof Map<String, Object>)) continue;
                Map<String, Object> build = (Map<String, Object>) b;
                Object buildTriggersRaw = build.get('triggers');
                if (buildTriggersRaw instanceof List<Object>) {
                    for (Object bt : (List<Object>) buildTriggersRaw) {
                        if (!(bt instanceof Map<String, Object>)) continue;
                        Map<String, Object> buildTrigger = (Map<String, Object>) bt;
                        Object en = buildTrigger.get('event_name');
                        if (en != null && eventName.equalsIgnoreCase(String.valueOf(en))) return true;
                        Object innerNames = buildTrigger.get('event_names');
                        if (innerNames instanceof List<Object>) {
                            for (Object ien : (List<Object>) innerNames) {
                                if (eventName.equalsIgnoreCase(String.valueOf(ien))) return true;
                            }
                        }
                    }
                }
            }
        }

        return false;
    }
}
