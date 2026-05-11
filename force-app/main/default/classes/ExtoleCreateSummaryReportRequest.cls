/**
 * Create an on-demand summary report via POST /v4/reports.
 *
 * The summary report aggregates funnel-step metrics across one or more
 * programs, filtered by metric tags (e.g. dashboard-graph + dashboard-rate
 * for the program dashboard view).
 *
 * Asynchronous: the response carries a report_id with status=PENDING. Poll
 * via ExtoleGetReportStatusRequest until status=DONE, then download with
 * ExtoleDownloadReportRequest.
 */
@NamespaceAccessible
public class ExtoleCreateSummaryReportRequest {
    private String       program;
    private List<String> metricTagsToInclude;
    private List<String> metricTagsToExclude;
    private String       period;
    private Integer      days;
    private String       container;
    private String       dimensions;
    private Boolean      includeTotals;
    private String       flowFilter;
    private String       flows;

    public ExtoleCreateSummaryReportRequest() {
        this.metricTagsToInclude = new List<String>{ 'dashboard-graph', 'dashboard-rate' };
        this.metricTagsToExclude = new List<String>{ 'dashboard-exclude' };
        this.period              = 'WEEK';
        this.days                = 90;
        this.container           = 'production';
        this.dimensions          = 'PROGRAM';
        this.includeTotals       = false;
        // Match Extole UI's program-dashboard view — attribute each event to its
        // best-fit flow path and restrict to business events + email flows.
        this.flowFilter          = 'BEST_FLOW';
        this.flows               = '/business-events,/emails/*';
    }

    public ExtoleCreateSummaryReportRequest withFlowFilter(String flowFilter) { this.flowFilter = flowFilter; return this; }
    public ExtoleCreateSummaryReportRequest withFlows(String flows)           { this.flows = flows; return this; }

    public ExtoleCreateSummaryReportRequest withProgram(String program)         { this.program = program; return this; }
    public ExtoleCreateSummaryReportRequest withPeriod(String period)           { this.period = period; return this; }
    public ExtoleCreateSummaryReportRequest withDays(Integer days)              { this.days = days; return this; }
    public ExtoleCreateSummaryReportRequest withContainer(String container)     { this.container = container; return this; }
    public ExtoleCreateSummaryReportRequest withDimensions(String dimensions)   { this.dimensions = dimensions; return this; }
    public ExtoleCreateSummaryReportRequest withMetricTagsInclude(List<String> tags) { this.metricTagsToInclude = tags; return this; }
    public ExtoleCreateSummaryReportRequest withMetricTagsExclude(List<String> tags) { this.metricTagsToExclude = tags; return this; }

    public HttpRequest build(ExtoleConfig config) {
        Map<String, Object> parameters = new Map<String, Object>{
            'container'              => container,
            'period'                 => period,
            'dimensions'             => dimensions,
            'include_totals'         => String.valueOf(includeTotals),
            'metric_tags_to_include' => String.join(metricTagsToInclude, ','),
            'metric_tags_to_exclude' => String.join(metricTagsToExclude, ',')
        };
        if (String.isNotBlank(program))    parameters.put('program', program);
        if (String.isNotBlank(flowFilter)) parameters.put('flow_filter', flowFilter);
        if (String.isNotBlank(flows))      parameters.put('flows', flows);
        if (days != null) {
            // Extole's summary report buckets by local-tz day boundaries. Send
            // day-aligned, LA-anchored ISO 8601 with bracket-tz annotation —
            // matches the format the Extole UI uses. With UTC mid-day timestamps
            // the server collapses all data into the first period.
            String tz = 'America/Los_Angeles';
            DateTime today = DateTime.now();
            DateTime startDt = today.addDays(-days);
            String startDate = startDt.format('yyyy-MM-dd', tz);
            String endDate   = today.format('yyyy-MM-dd', tz);
            String offset    = today.format('XXX', tz); // e.g. -07:00 / -08:00
            String startStr  = startDate + 'T00:00:00.000' + offset + '[' + tz + ']';
            String endStr    = endDate   + 'T23:59:59.000' + offset + '[' + tz + ']';
            parameters.put('time_range', startStr + '/' + endStr);
        }

        Map<String, Object> body = new Map<String, Object>{
            'name'         => 'summary',
            'report_type'  => 'summary',
            'display_name' => 'summary',
            'formats'      => new List<String>{ 'JSON' },
            'parameters'   => parameters
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.getEndpoint() + ExtoleConstants.REPORT_V4_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        if (!config.isNamedCredentialMode()) {
            req.setHeader('Authorization', config.getAuthHeader());
        }
        req.setBody(JSON.serialize(body));
        req.setTimeout(config.timeoutMs);
        return req;
    }
}
