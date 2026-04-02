# Extole SFDC App – v2 Pre-flight & Launch Guide

Everything needed before handing off the Event Configurator build to Claude Code agents. Assumes v1 is already built and deployed to the developer org. See the v1 Pre-flight doc for base environment setup.

---

## 1. Prerequisites

### Salesforce Org
The v1 developer org is used for v2 development. Confirm:
- [ ] v1 package components are deployed and working
- [ ] Admin user has **Author Apex** permission — required for Tooling API access
- [ ] Admin user has **Customize Application** permission — required for Flow deployment
- [ ] Dev Hub is enabled

### Permissions Check
Run this SOQL in the org to confirm the admin user has the required permissions:
```sql
SELECT Id, Name, PermissionsAuthorApex, PermissionsCustomizeApplication
FROM Profile
WHERE Id IN (SELECT ProfileId FROM User WHERE Username = 'YOUR_ADMIN_USERNAME')
```
Both should return `true`. If not, update the profile before proceeding.

---

## 2. Pre-Build Spike: Validate Test Coverage Approach

**This must complete before the main build starts.** It validates the highest-risk technical assumption in the v2 spec — whether a generic test class using `Type.forName()` can cover dynamically named Apex classes for Salesforce code coverage purposes.

### What to run

In the developer org, create this Apex class manually via the Developer Console:

```apex
public with sharing class Extole_Handler_spike_test {
  @InvocableMethod
  public static void invoke(List<String> recordIds) {
    makeCallout(recordIds);
  }

  @future(callout=true)
  public static void makeCallout(List<String> recordIds) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Extole_API/v5/events');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setBody('{"event_name":"spike_test","data":{"app_type":"salesforce_crm"}}');
    Http h = new Http();
    HttpResponse res = h.send(req);
  }
}
```

Then create this test class:

```apex
@isTest
private class ExtoleEventHandlerTest {
  @isTest
  static void testHandlerViaTypeForName() {
    Test.setMock(HttpCalloutMock.class, new ExtoleMockCallout());
    Type handlerType = Type.forName('Extole_Handler_spike_test');
    if (handlerType != null) {
      Object handler = handlerType.newInstance();
    }
    Test.startTest();
    Extole_Handler_spike_test.invoke(new List<String>{'001000000000001'});
    Test.stopTest();
  }

  private class ExtoleMockCallout implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody('{}');
      return res;
    }
  }
}
```

### Run the test and check coverage

1. Run `ExtoleEventHandlerTest` via the Developer Console or CLI:
```bash
sf apex run test --class-names ExtoleEventHandlerTest --target-org extole-sandbox --result-format human
```

2. Check code coverage for `Extole_Handler_spike_test`:
```bash
sf apex get test --test-run-id YOUR_TEST_RUN_ID --target-org extole-sandbox --code-coverage
```

### Interpret the result

| Result | Meaning | Action |
|---|---|---|
| Coverage > 0% on `Extole_Handler_spike_test` | `Type.forName()` works for coverage | Proceed with generic test harness approach |
| Coverage = 0% on `Extole_Handler_spike_test` | Static reference required | Use fallback: generate test class per handler at deploy time |
| Coverage = 0% but tests pass and deployment succeeds | Dynamic classes may be exempt from coverage | Proceed but verify with a production org deployment |

**Do not start the main build until this result is known and recorded.**

---

## 3. Verify Tooling API Access

Confirm the admin user can call the Tooling API from Apex. Run this anonymous Apex in the Developer Console:

```apex
HttpRequest req = new HttpRequest();
req.setEndpoint(URL.getSalesforceBaseUrl().toExternalForm() +
  '/services/data/v59.0/tooling/query/?q=SELECT+Id,Name+FROM+ApexClass+LIMIT+1');
req.setMethod('GET');
req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
req.setHeader('Content-Type', 'application/json');
Http h = new Http();
HttpResponse res = h.send(req);
System.debug(res.getStatusCode());
System.debug(res.getBody());
```

**Expected:** status 200, JSON response with an ApexClass record.

**If 403:** admin user lacks Author Apex or View All Data permission. Fix before proceeding.

**If callout error:** add `URL.getSalesforceBaseUrl().toExternalForm()` to Remote Site Settings in the org.

---

## 4. Verify Metadata API Access for Flow Deployment

Confirm Flow deployment via Metadata API works. This is a lighter check — if the org has Dev Hub enabled and the admin has Customize Application permission, it should work. Verify by deploying a minimal test Flow via CLI:

```bash
sf project deploy start --target-org extole-sandbox --metadata Flow:Extole_Spike_Flow
```

A successful deploy (or a "no changes" response) confirms the path is open.

---

## 5. Pre-flight Checklist

- [ ] v1 package deployed and working in dev org
- [ ] Admin user has Author Apex permission (verified via SOQL)
- [ ] Admin user has Customize Application permission (verified via SOQL)
- [ ] Tooling API accessible from Apex (verified via anonymous Apex)
- [ ] Spike test run and result recorded (see section 2)
- [ ] Spike result documented in PROGRESS.md in the project root
- [ ] Spike result documented in PROGRESS.md

---

## 6. Lead Agent Starting Prompt

```bash
cd ~/extole-sfdc-app
claude
```

Then paste:

---

> You are the lead agent for building the Extole SFDC App v2 — the Event Configurator. The full v2 spec is in extole_sfdc_v2_spec.md in this directory. The v1 app is already deployed to the org at alias `extole-sandbox`.
>
> **Before spawning any teammates, complete the pre-build spike:**
>
> **Spike task:** The spike test has already been run manually per the pre-flight doc. Read PROGRESS.md to find the recorded spike result. Based on that result:
> - If coverage > 0%: use the generic test harness approach (single `ExtoleEventHandlerTest` class using `Type.forName()`)
> - If coverage = 0%: use the fallback approach (generate a minimal test class per handler at deploy time)
> Record which approach you are using in PROGRESS.md before proceeding.
>
> **Build sequence — follow this order strictly:**
>
> **Phase 1 (you, before spawning teammates):** Extend the data model.
> - Deploy `Extole_Event_Config__mdt` Custom Metadata Type with all fields per v2 spec
> - Confirm deployment and queryability before proceeding
>
> **Phase 2 (spawn two teammates in parallel once Phase 1 is confirmed):**
>
> Teammate A — Apex/backend:
> - Tooling API service class for generating and deploying Apex handler classes
> - Metadata API service class for generating and deploying Flows
> - Edit/redeploy sequence per spec (version suffix, FlowDefinition deactivation, new class deploy, Flow update)
> - Delete sequence per spec (Flow deactivation only, orphan class retained)
> - `@AuraEnabled` controller methods for all LWC data access
> - Generic test harness OR per-handler test generation — per spike result in PROGRESS.md
> - All debug logging per v1 patterns
>
> Teammate B — LWC/frontend:
> - Event Configurator tab LWC
> - Object picker (Metadata API enumeration)
> - Three-step configuration modal: trigger selection, field mapping, review & deploy
> - Field picker with one-hop relationship traversal
> - Required field validation (email and partner_user_id blocking save if unmapped)
> - Test with sample record preview (payload preview without sending)
> - Deploy progress indicator with polling
> - Orphaned class cleanup action in Settings tab
> - All UI strings as Custom Labels
>
> **Phase 3 (you, after both teammates complete):**
> - Integrate Teammate A's Apex with Teammate B's LWC
> - End-to-end test: configure a Lead Created event, deploy, create a test Lead in the org, confirm the event fires and appears in Extole Event Streams
> - Confirm code coverage stays above 75% after deployment of a generated handler class
>
> **Rules:**
> - Do not start Phase 2 until Phase 1 metadata is confirmed deployed
> - Naming convention: `Extole_Handler_[ConfigKey]` and `Extole_Flow_[ConfigKey]` — never raw event name
> - Session-based auth (`UserInfo.getSessionId()`) for all Tooling API calls — no Connected App
> - Named Credential for Extole API calls only — never expose token in generated code
> - `app_type: salesforce_crm` always injected by generated Apex — not configurable
> - Null field values omitted from payload at runtime
> - Related object traversal: one hop only, queryable fields only, no polymorphic relationships
> - Write PROGRESS.md checkpoint after each phase

---

## 7. If Things Go Wrong

**Tooling API returns 403 mid-build:** Admin session may have expired or permissions changed. Re-authenticate and confirm Author Apex permission is still active.

**Flow deployment fails with CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY:** A flow with that name already exists and is active. The deactivation step may have failed. Manually deactivate the Flow in Setup → Flows before retrying.

**Code coverage drops below 75% after handler deployment:** The test harness approach may not be working as expected. Switch to the per-handler test class fallback and redeploy.

**Generated class name collision:** Two configs produced the same ConfigKey. Check `Extole_Event_Config__mdt` for duplicate developer names and rename one before redeploying.
