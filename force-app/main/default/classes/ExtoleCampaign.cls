@NamespaceAccessible
public class ExtoleCampaign {
    public String       campaignId { get; set; }
    public String       name       { get; set; }
    public String       state      { get; set; }
    public List<String> eventNames { get; set; }

    public static ExtoleCampaign fromMap(Map<String, Object> m) {
        ExtoleCampaign c = new ExtoleCampaign();
        c.campaignId = m.get('campaign_id') != null ? String.valueOf(m.get('campaign_id')) : null;
        c.name       = (String) m.get('name');
        c.state      = (String) m.get('state');
        c.eventNames = new List<String>();

        try {
            List<Object> steps = (List<Object>) m.get('steps');
            if (steps != null) {
                for (Object stepObj : steps) {
                    extractEventNamesFromStep((Map<String, Object>) stepObj, c.eventNames);
                }
            }
        } catch (Exception e) { }
        return c;
    }

    public Boolean referencesEvent(String eventName) {
        return eventNames != null && eventNames.contains(eventName);
    }

    private static void extractEventNamesFromStep(Map<String, Object> step, List<String> out) {
        try {
            List<Object> triggers = (List<Object>) step.get('triggers');
            if (triggers == null) return;
            for (Object triggerObj : triggers) {
                Map<String, Object> trig = (Map<String, Object>) triggerObj;
                List<Object> names = (List<Object>) trig.get('event_names');
                if (names == null) continue;
                for (Object n : names) {
                    out.add((String) n);
                }
            }
        } catch (Exception e) { }
    }
}
