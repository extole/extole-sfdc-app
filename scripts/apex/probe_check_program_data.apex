// Probe: check data for refer-a-member-with-in-branch and small-business-deposits
// Run with: sf apex run --file scripts/apex/probe_check_program_data.apex --target-org extole-sandbox

String[] reportIds = new String[]{
    'tcvm5h1y8w7qn7vuxrto',  // refer-a-member-with-in-branch
    'tcvm5h3sh5pmon2ep0nw',  // small-business-deposits
    'tcvm5h4qtzv5pu3osmhn'   // reward-bank (for comparison)
};

String[] labels = new String[]{
    'refer-a-member-with-in-branch',
    'small-business-deposits',
    'reward-bank'
};

Http http = new Http();

for (Integer i = 0; i < reportIds.size(); i++) {
    String rId = reportIds[i];

    // Check status
    HttpRequest statusReq = new HttpRequest();
    statusReq.setEndpoint('callout:Extole_API/v4/reports/' + rId);
    statusReq.setMethod('GET');
    Map<String, Object> report = (Map<String, Object>) JSON.deserializeUntyped(http.send(statusReq).getBody());
    String status = (String) report.get('status');

    if (status != 'DONE') {
        System.debug(labels[i] + ': status=' + status + ' (not done yet)');
        continue;
    }

    // Download
    HttpRequest dl = new HttpRequest();
    dl.setEndpoint('callout:Extole_API/v4/reports/' + rId + '/download.json');
    dl.setMethod('GET');
    HttpResponse dlRes = http.send(dl);
    List<Object> rows = (List<Object>) JSON.deserializeUntyped(dlRes.getBody());

    // Count rows with non-zero metric values
    Integer nonZeroRows = 0;
    Integer totalRows = rows.size();
    for (Object row : rows) {
        Map<String, Object> r = (Map<String, Object>) row;
        List<Object> steps = (List<Object>) r.get('steps');
        if (steps != null) {
            for (Object step : steps) {
                List<Object> metrics = (List<Object>) ((Map<String, Object>)step).get('metrics');
                if (metrics != null) {
                    for (Object m : metrics) {
                        Object val = ((Map<String,Object>)m).get('value');
                        if (val != null && Decimal.valueOf(String.valueOf(val)) > 0) {
                            nonZeroRows++;
                            break;
                        }
                    }
                }
                break;
            }
        }
    }
    System.debug(labels[i] + ': totalRows=' + totalRows + ' rowsWithData=' + nonZeroRows);
}
