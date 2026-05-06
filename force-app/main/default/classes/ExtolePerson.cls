@NamespaceAccessible
public class ExtolePerson {
    public String       id            { get; set; }
    public String       email         { get; set; }
    public String       partnerUserId { get; set; }
    public String       firstName     { get; set; }
    public String       lastName      { get; set; }
    public String       shareLink     { get; set; }
    public List<String> tags          { get; set; }

    // Maps the main /v5/persons response. Only id and email are populated here;
    // call applyData() with the /v5/persons/{id}/data response to fill the rest.
    public static ExtolePerson fromMap(Map<String, Object> m) {
        ExtolePerson p = new ExtolePerson();
        p.id    = (String) m.get('id');
        p.tags  = new List<String>();
        // email is only reliably available when identity_key is "email"
        if ('email'.equals(m.get('identity_key'))) {
            p.email = (String) m.get('identity_key_value');
        }
        return p;
    }

    // Applies fields from the /v5/persons/{id}/data endpoint response.
    // Each entry is a data-attribute object: {"name":"email","value":"...","scope":"PRIVATE",...}
    public void applyData(Map<String, Object> dataMap) {
        email         = dataValue(dataMap, 'email');
        firstName     = dataValue(dataMap, 'first_name');
        lastName      = dataValue(dataMap, 'last_name');
        partnerUserId = dataValue(dataMap, 'partner_user_id');
        shareLink     = dataValue(dataMap, 'share_link');
    }

    private static String dataValue(Map<String, Object> dataMap, String key) {
        Object entry = dataMap.get(key);
        if (entry == null) return null;
        try {
            return (String) ((Map<String, Object>) entry).get('value');
        } catch (TypeException e) {
            return null;
        }
    }
}
