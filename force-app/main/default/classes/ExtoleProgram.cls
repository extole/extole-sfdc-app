@NamespaceAccessible
public class ExtoleProgram {
    public String campaignId    { get; set; }
    public String name          { get; set; }
    public String state         { get; set; }
    public String programLabel  { get; set; }

    public static ExtoleProgram fromMap(Map<String, Object> m) {
        ExtoleProgram p = new ExtoleProgram();
        p.campaignId   = m.get('campaign_id') != null ? String.valueOf(m.get('campaign_id')) : null;
        p.name         = (String) m.get('name');
        p.state        = (String) m.get('state');
        p.programLabel = (String) m.get('program_label');
        return p;
    }
}
