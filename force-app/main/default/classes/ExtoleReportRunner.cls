@NamespaceAccessible
public class ExtoleReportRunner {
    public String runnerId    { get; set; }
    public String name        { get; set; }
    public String description { get; set; }

    public static ExtoleReportRunner fromMap(Map<String, Object> m) {
        ExtoleReportRunner r = new ExtoleReportRunner();
        r.runnerId    = (String) m.get('id');
        r.name        = (String) m.get('name');
        r.description = (String) m.get('description');
        return r;
    }
}
