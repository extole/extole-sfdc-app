/**
 * ExtoleProgramDashboardController
 *
 * @AuraEnabled controller for the KPI Dashboard tab's program funnel widget.
 *
 * Flow:
 *   1. LWC calls getPrograms() to populate the program dropdown.
 *   2. LWC calls startDashboardReport(program, days, period) → POSTs to /v4/reports
 *      with summary type + dashboard tag filters → returns the new report's
 *      ExtoleReportInstance (pending state).
 *   3. LWC polls pollDashboardReport(reportId). When status is DONE, the
 *      controller downloads the result, parses it into a funnel structure
 *      (steps × periods), and returns it. Until then, returns just the status.
 */
public with sharing class ExtoleProgramDashboardController {

    private static final List<String> DEFAULT_INCLUDE_TAGS = new List<String>{
        'dashboard-graph', 'dashboard-rate'
    };
    private static final List<String> DEFAULT_EXCLUDE_TAGS = new List<String>{
        'dashboard-exclude'
    };
    private static final List<String> PROMOTION_INCLUDE_TAGS = new List<String>{
        'promotion-metric:*', 'promotion-bar:*', 'promotion:*', 'promotion-report*'
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Programs
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getPrograms() {
        ExtoleConfig config = new ExtoleConfig('Extole_API');
        ExtoleClient client = new ExtoleClient();
        HttpResponse res = client.send(config, new ExtoleListProgramsRequest().build(config));
        ExtoleListProgramsResponse parsed = ExtoleListProgramsResponse.fromResponse(res);

        // The campaign-summaries endpoint returns one row per campaign. Dedupe to
        // one entry per programLabel. Only MARKETING campaigns are real reporting
        // targets — INTEGRATION campaigns (Hubspot Advocate Sync, Internal
        // Extension/Integration, Self Service) are component holders with no
        // traffic, and CONFIGURATION (global) is account-level setup, not a program.
        Set<String> seen = new Set<String>();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (ExtoleProgram p : parsed.programs) {
            if (String.isBlank(p.programLabel)) continue;
            if (p.state != null && p.state != 'LIVE') continue;
            if (p.campaignType != null && p.campaignType != 'MARKETING') continue;
            if (seen.contains(p.programLabel)) continue;
            seen.add(p.programLabel);
            result.add(new Map<String, Object>{
                'label'       => p.programLabel,
                'displayName' => prettifyLabel(p.programLabel),
                'state'       => p.state
            });
        }
        return result;
    }

    /** "refer-a-member-flow" → "Refer A Member Flow" */
    private static String prettifyLabel(String label) {
        if (String.isBlank(label)) return label;
        List<String> parts = label.replace('_', '-').split('-');
        List<String> out = new List<String>();
        for (String p : parts) {
            if (p.length() == 0) continue;
            out.add(p.substring(0, 1).toUpperCase() + p.substring(1));
        }
        return String.join(out, ' ');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dashboard report lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Submit a new summary report for the given program. Returns the report
     * instance (id + initial status). Caller polls pollDashboardReport(id).
     */
    @AuraEnabled
    public static Map<String, Object> startDashboardReport(
        String program, Integer days, String period
    ) {
        if (String.isBlank(program)) throw new AuraHandledException('program is required');
        Integer effectiveDays   = (days != null && days > 0) ? days : 90;
        String  effectivePeriod = String.isNotBlank(period) ? period : 'WEEK';

        ExtoleConfig config = new ExtoleConfig('Extole_API');
        ExtoleClient client = new ExtoleClient();
        try {
            HttpRequest req = new ExtoleCreateSummaryReportRequest()
                .withProgram(program)
                .withDays(effectiveDays)
                .withPeriod(effectivePeriod)
                .withMetricTagsInclude(DEFAULT_INCLUDE_TAGS)
                .withMetricTagsExclude(DEFAULT_EXCLUDE_TAGS)
                .build(config);
            HttpResponse res = client.send(config, req);
            ExtoleCreateSummaryReportResponse parsed =
                ExtoleCreateSummaryReportResponse.fromResponse(res);
            return new Map<String, Object>{
                'reportId' => parsed.reportInstance.reportId,
                'status'   => parsed.reportInstance.status
            };
        } catch (Exception e) {
            throw new AuraHandledException('Failed to start dashboard report: ' + e.getMessage());
        }
    }

    /**
     * Poll a previously-submitted report. While pending, returns just the
     * status. When DONE, also returns the parsed funnel data.
     *
     * Returned shape:
     *   {
     *     "status": "PENDING|IN_PROGRESS|DONE|FAILED",
     *     "reportId": "...",
     *     "data": { ... funnel payload, only when DONE ... }
     *   }
     */
    @AuraEnabled
    public static Map<String, Object> pollDashboardReport(String reportId) {
        if (String.isBlank(reportId)) throw new AuraHandledException('reportId is required');

        ExtoleConfig config = new ExtoleConfig('Extole_API');
        ExtoleClient client = new ExtoleClient();
        try {
            HttpRequest statusReq = new ExtoleGetReportStatusRequest(reportId).build(config);
            HttpResponse statusRes = client.send(config, statusReq);
            ExtoleGetReportStatusResponse statusParsed =
                ExtoleGetReportStatusResponse.fromResponse(statusRes);

            Map<String, Object> out = new Map<String, Object>{
                'reportId' => reportId,
                'status'   => statusParsed.reportInstance.status
            };

            if (statusParsed.isComplete()) {
                HttpResponse dlRes = client.send(config,
                    new ExtoleDownloadReportRequest(reportId).build(config));
                if (dlRes.getStatusCode() >= 200 && dlRes.getStatusCode() < 300) {
                    out.put('data', parseDashboardPayload(dlRes.getBody()));
                } else {
                    out.put('status', 'FAILED');
                    out.put('error',
                        'Download failed: HTTP ' + dlRes.getStatusCode());
                }
            }
            return out;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to poll dashboard report: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Promotions lifecycle (separate /v4/reports run; different metric tag set
    // and dimensions=PROGRAM,SOURCE_TYPE,SOURCE so each row is one (promotion ×
    // period) data point).
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> startPromotionsReport(
        String program, Integer days, String period
    ) {
        if (String.isBlank(program)) throw new AuraHandledException('program is required');
        Integer effectiveDays   = (days != null && days > 0) ? days : 90;
        String  effectivePeriod = String.isNotBlank(period) ? period : 'WEEK';

        ExtoleConfig config = new ExtoleConfig('Extole_API');
        ExtoleClient client = new ExtoleClient();
        try {
            HttpRequest req = new ExtoleCreateSummaryReportRequest()
                .withProgram(program)
                .withDays(effectiveDays)
                .withPeriod(effectivePeriod)
                .withDimensions('PROGRAM,SOURCE_TYPE,SOURCE')
                .withMetricTagsInclude(PROMOTION_INCLUDE_TAGS)
                .withMetricTagsExclude(DEFAULT_EXCLUDE_TAGS)
                .build(config);
            HttpResponse res = client.send(config, req);
            ExtoleCreateSummaryReportResponse parsed =
                ExtoleCreateSummaryReportResponse.fromResponse(res);
            return new Map<String, Object>{
                'reportId' => parsed.reportInstance.reportId,
                'status'   => parsed.reportInstance.status
            };
        } catch (Exception e) {
            throw new AuraHandledException('Failed to start promotions report: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> pollPromotionsReport(String reportId) {
        if (String.isBlank(reportId)) throw new AuraHandledException('reportId is required');

        ExtoleConfig config = new ExtoleConfig('Extole_API');
        ExtoleClient client = new ExtoleClient();
        try {
            HttpRequest statusReq = new ExtoleGetReportStatusRequest(reportId).build(config);
            HttpResponse statusRes = client.send(config, statusReq);
            ExtoleGetReportStatusResponse statusParsed =
                ExtoleGetReportStatusResponse.fromResponse(statusRes);

            Map<String, Object> out = new Map<String, Object>{
                'reportId' => reportId,
                'status'   => statusParsed.reportInstance.status
            };

            if (statusParsed.isComplete()) {
                HttpResponse dlRes = client.send(config,
                    new ExtoleDownloadReportRequest(reportId).build(config));
                if (dlRes.getStatusCode() >= 200 && dlRes.getStatusCode() < 300) {
                    out.put('data', parsePromotionsPayload(dlRes.getBody()));
                } else {
                    out.put('status', 'FAILED');
                    out.put('error', 'Download failed: HTTP ' + dlRes.getStatusCode());
                }
            }
            return out;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to poll promotions report: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Parsing
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Parse the downloaded summary report into a UI-friendly funnel shape:
     *
     *   {
     *     "program": "account-openings",
     *     "periods": [
     *       { "start": "...", "end": "...", "timePeriod": "WEEK" }, ...
     *     ],
     *     "steps": [
     *       {
     *         "stepName": "member_invited",
     *         "displayName": "Member Invited",
     *         "graphMetric": { "name": "...", "unit": "#", "values": [n, n, n] },
     *         "rateMetric":  { "name": "...", "unit": "%", "values": [n, n, n] }
     *       }, ...
     *     ]
     *   }
     *
     * Values arrays are aligned with `periods` index.
     */
    private static Map<String, Object> parseDashboardPayload(String body) {
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(body);

        // 1. Establish stable period ordering from the first row's metadata,
        //    then collect every period seen across the response.
        List<Map<String, Object>> periods = new List<Map<String, Object>>();
        Map<String, Integer> periodIndex = new Map<String, Integer>();
        String programLabel = null;

        for (Object rawRow : rows) {
            Map<String, Object> row = (Map<String, Object>) rawRow;
            String key = String.valueOf(row.get('period_start')) + '|' +
                         String.valueOf(row.get('period_end'));
            if (programLabel == null) programLabel = (String) row.get('program');
            if (!periodIndex.containsKey(key)) {
                periodIndex.put(key, periods.size());
                periods.add(new Map<String, Object>{
                    'start'      => row.get('period_start'),
                    'end'        => row.get('period_end'),
                    'timePeriod' => row.get('time_period')
                });
            }
        }

        // 2. Walk every row, extracting one graph metric + one rate metric per
        //    step. Merge by stepName so multi-period rows produce values[] arrays.
        Map<String, Map<String, Object>> stepMap = new Map<String, Map<String, Object>>();
        List<String> stepOrder = new List<String>();

        for (Object rawRow : rows) {
            Map<String, Object> row = (Map<String, Object>) rawRow;
            String key = String.valueOf(row.get('period_start')) + '|' +
                         String.valueOf(row.get('period_end'));
            Integer idx = periodIndex.get(key);
            List<Object> steps = (List<Object>) row.get('steps');
            if (steps == null) continue;

            for (Object rawStep : steps) {
                Map<String, Object> s = (Map<String, Object>) rawStep;
                String stepName = (String) s.get('step_name');
                if (stepName == null) continue;

                Map<String, Object> stepRec = stepMap.get(stepName);
                if (stepRec == null) {
                    stepRec = new Map<String, Object>{
                        'stepName'    => stepName,
                        'displayName' => s.get('name'),
                        'graphMetric' => null,
                        'rateMetric'  => null
                    };
                    stepMap.put(stepName, stepRec);
                    stepOrder.add(stepName);
                }

                List<Object> metrics = (List<Object>) s.get('metrics');
                if (metrics == null) continue;
                for (Object rawM : metrics) {
                    Map<String, Object> m = (Map<String, Object>) rawM;
                    List<Object> tags = (List<Object>) m.get('tags');
                    Boolean isGraph = false, isRate = false;
                    if (tags != null) {
                        for (Object t : tags) {
                            if ('dashboard-graph'.equals(t)) isGraph = true;
                            if ('dashboard-rate'.equals(t))  isRate  = true;
                        }
                    }
                    if (!isGraph && !isRate) continue;
                    String slot = isGraph ? 'graphMetric' : 'rateMetric';
                    Map<String, Object> metricRec = (Map<String, Object>) stepRec.get(slot);
                    if (metricRec == null) {
                        List<Object> emptyValues = new List<Object>();
                        for (Integer i = 0; i < periods.size(); i++) emptyValues.add(null);
                        metricRec = new Map<String, Object>{
                            'name'        => m.get('name'),
                            'description' => m.get('description'),
                            'unit'        => m.get('unit'),
                            'values'      => emptyValues
                        };
                        stepRec.put(slot, metricRec);
                    }
                    ((List<Object>) metricRec.get('values'))[idx] = m.get('value');
                }
            }
        }

        List<Map<String, Object>> steps = new List<Map<String, Object>>();
        for (String name : stepOrder) steps.add(stepMap.get(name));

        return new Map<String, Object>{
            'program' => programLabel,
            'periods' => periods,
            'steps'   => steps
        };
    }

    /**
     * Parse the promotions report into:
     *   {
     *     "periods":    [{ "start": "...", "end": "...", "timePeriod": "WEEK" }, ...],
     *     "promotions": [
     *       {
     *         "sourceType":      "link",
     *         "source":          "global_footer",
     *         "displayName":     "Global Footer",
     *         "total":           53878,
     *         "sparklineValues": [120, 150, ...],
     *         "shareRate":       0.42
     *       }, ...
     *     ]
     *   }
     *
     * Each promotion is identified by (source_type, source). Values are summed
     * across periods to compute `total`; sparkline values are aligned to `periods`.
     */
    private static Map<String, Object> parsePromotionsPayload(String body) {
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(body);

        // 1. Collect unique periods in order of first appearance.
        List<Map<String, Object>> periods = new List<Map<String, Object>>();
        Map<String, Integer> periodIndex = new Map<String, Integer>();
        for (Object rawRow : rows) {
            Map<String, Object> row = (Map<String, Object>) rawRow;
            String key = String.valueOf(row.get('period_start')) + '|' +
                         String.valueOf(row.get('period_end'));
            if (!periodIndex.containsKey(key)) {
                periodIndex.put(key, periods.size());
                periods.add(new Map<String, Object>{
                    'start'      => row.get('period_start'),
                    'end'        => row.get('period_end'),
                    'timePeriod' => row.get('time_period')
                });
            }
        }

        // 2. Walk rows, grouping by (source_type, source).
        Map<String, Map<String, Object>> promoMap = new Map<String, Map<String, Object>>();
        List<String> promoOrder = new List<String>();

        for (Object rawRow : rows) {
            Map<String, Object> row = (Map<String, Object>) rawRow;
            String sourceType = (String) row.get('source_type');
            String source     = (String) row.get('source');
            if (String.isBlank(sourceType) && String.isBlank(source)) continue;

            String promoKey = String.valueOf(sourceType) + '|' + String.valueOf(source);
            Integer idx = periodIndex.get(
                String.valueOf(row.get('period_start')) + '|' +
                String.valueOf(row.get('period_end'))
            );

            Map<String, Object> promoRec = promoMap.get(promoKey);
            if (promoRec == null) {
                List<Object> emptyValues = new List<Object>();
                for (Integer i = 0; i < periods.size(); i++) emptyValues.add(0);
                promoRec = new Map<String, Object>{
                    'sourceType'      => sourceType,
                    'source'          => source,
                    'displayName'     => prettifyLabel(source),
                    'sparklineValues' => emptyValues,
                    'total'           => 0,
                    'shareRate'       => null
                };
                promoMap.put(promoKey, promoRec);
                promoOrder.add(promoKey);
            }

            // Pull the promotion-bar metric (the count) and the rate metric.
            List<Object> steps = (List<Object>) row.get('steps');
            if (steps == null) continue;
            for (Object rawStep : steps) {
                Map<String, Object> s = (Map<String, Object>) rawStep;
                List<Object> metrics = (List<Object>) s.get('metrics');
                if (metrics == null) continue;
                for (Object rawM : metrics) {
                    Map<String, Object> m = (Map<String, Object>) rawM;
                    List<Object> tags = (List<Object>) m.get('tags');
                    if (tags == null) continue;
                    Boolean isBar = false, isRate = false;
                    for (Object t : tags) {
                        String ts = String.valueOf(t);
                        if (ts.startsWith('promotion-bar:')) isBar = true;
                        // promotion:<step> is the rate metric on the corresponding step
                        if (ts == 'promotion:shares' || ts == 'promotion:share-rate') isRate = true;
                    }
                    Object val = m.get('value');
                    if (isBar && val instanceof Decimal) {
                        ((List<Object>) promoRec.get('sparklineValues'))[idx] = val;
                        promoRec.put('total', ((Decimal) promoRec.get('total')) + (Decimal) val);
                    } else if (isBar && val instanceof Integer) {
                        ((List<Object>) promoRec.get('sparklineValues'))[idx] = val;
                        promoRec.put('total', ((Decimal) promoRec.get('total')) + (Integer) val);
                    }
                    if (isRate && val != null && promoRec.get('shareRate') == null) {
                        // Use the most-recent non-null rate
                        promoRec.put('shareRate', val);
                    }
                }
            }
        }

        List<Map<String, Object>> promotions = new List<Map<String, Object>>();
        for (String key : promoOrder) promotions.add(promoMap.get(key));

        // Sort by total descending so highest-volume promotions render first
        promotions.sort(new PromoTotalComparator());

        return new Map<String, Object>{
            'periods'    => periods,
            'promotions' => promotions
        };
    }

    public class PromoTotalComparator implements System.Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            Decimal aT = (Decimal) a.get('total');
            Decimal bT = (Decimal) b.get('total');
            if (aT == null) aT = 0;
            if (bT == null) bT = 0;
            if (aT > bT) return -1;
            if (aT < bT) return 1;
            return 0;
        }
    }
}
