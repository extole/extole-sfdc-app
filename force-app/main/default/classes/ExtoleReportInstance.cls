@NamespaceAccessible
public class ExtoleReportInstance {
    public String reportId    { get; set; }
    public String status      { get; set; }
    public String createdDate { get; set; }
    public String downloadUri { get; set; }

    public static ExtoleReportInstance fromMap(Map<String, Object> m) {
        ExtoleReportInstance i = new ExtoleReportInstance();
        i.reportId    = (String) m.get('report_id');
        i.status      = (String) m.get('status');
        i.createdDate = (String) m.get('created_date');
        i.downloadUri = (String) m.get('download_uri');
        return i;
    }
}
