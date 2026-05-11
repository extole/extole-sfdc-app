@NamespaceAccessible
public class ExtoleAudienceOperation {
    public String operationId { get; set; }
    public String audienceId  { get; set; }
    public String operationType { get; set; }
    public String state       { get; set; }
    public List<String> tags  { get; set; }

    public static ExtoleAudienceOperation fromMap(Map<String, Object> m) {
        ExtoleAudienceOperation op = new ExtoleAudienceOperation();
        op.operationId   = m.get('id') != null ? String.valueOf(m.get('id')) : null;
        op.audienceId    = m.get('audience_id') != null ? String.valueOf(m.get('audience_id')) : null;
        op.operationType = (String) m.get('type');
        // Extole's POST returns the operation envelope (often without state) — state lives on
        // the dedicated /state endpoint. Accept both shapes: top-level `state` or `status`.
        op.state         = (String) m.get('state');
        if (String.isBlank(op.state)) op.state = (String) m.get('status');
        op.tags          = new List<String>();
        Object rawTags = m.get('tags');
        if (rawTags != null) {
            for (Object t : (List<Object>) rawTags) {
                if (t != null) op.tags.add(String.valueOf(t));
            }
        }
        return op;
    }
}
