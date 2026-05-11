@NamespaceAccessible
public class ExtoleAudience {
    public String       audienceId   { get; set; }
    public String       name         { get; set; }
    public Boolean      enabled      { get; set; }
    public List<String> tags         { get; set; }
    public List<String> componentIds { get; set; }

    public static ExtoleAudience fromMap(Map<String, Object> m) {
        ExtoleAudience a = new ExtoleAudience();
        a.audienceId = m.get('id') != null ? String.valueOf(m.get('id')) : null;
        a.name       = (String) m.get('name');
        a.enabled    = (Boolean) m.get('enabled');
        a.tags       = stringList(m.get('tags'));
        a.componentIds = stringList(m.get('component_ids'));
        return a;
    }

    private static List<String> stringList(Object raw) {
        List<String> out = new List<String>();
        if (raw == null) return out;
        for (Object o : (List<Object>) raw) {
            if (o != null) out.add(String.valueOf(o));
        }
        return out;
    }
}
