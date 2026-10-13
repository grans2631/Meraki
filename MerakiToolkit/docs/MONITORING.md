# MerakiToolkit monitoring contract (Round 3)

**Mode:** read-only Meraki API polling plus local availability snapshot comparisons. This module does NOT register Dashboard alert destinations, push webhooks, take actions in Automate, schedule jobs, or automatically remediate devices.

## Example: one polling run

~~~powershell
Import-Module .\MerakiToolkit\MerakiToolkit.psd1 -Force
Connect-Meraki # masked key prompt, or use -UseEnvironment with secrets from a secure runner
$result = Get-MerakiHealthDiff -OrganizationId 'ORG_ID' -StatePath 'C:\ProgramData\MerakiToolkit\state\ORG_ID.json' -OutJsonPath 'C:\ProgramData\MerakiToolkit\alerts\latest.json'
$result.changes | Format-Table
$result | ConvertTo-Json -Depth 12 -Compress
~~~

The first run creates a baseline: zero change events. Subsequent runs emit changed device state only. Sample schema (illustrative):

~~~json
{
  "schemaVersion": "1.0",
  "source": "MerakiToolkit",
  "eventType": "meraki.device.availability.diff",
  "organizationId": "ORG_ID",
  "observedAtUtc": "2026-10-13T18:00:00Z",
  "baselineCreated": false,
  "changeCount": 1,
  "changes": [
    {"serial":"QXXX-XXXX-XXXX","networkId":"N_123","name":"Lab-AP","previousStatus":"online","currentStatus":"offline","severity":"critical","eventType":"offline"}
  ],
  "missingSerials": [],
  "note": "Missing serials are NOT classified as offline. Assess monitoring coverage separately."
}
~~~

## ConnectWise Automate adapter workflow

Run an approved **read-only** polling task at your desired interval, using an API key from a secrets manager. Parse JSON in ConnectWise Automate or a trusted intermediary. Trigger a ticket/monitor when changeCount > 0, classifying from eventType and severity. Deduplicate by organizationId + serial + currentStatus. After recovery, use your documented PSA resolution workflow. **No webhook is sent by MerakiToolkit.**

The command writes the new state before emitting the JSON file; failed downstream delivery requires adapter-managed replay/queuing. For a local read-only preview, pass -NoSave. A missing baseline generates no changes. Serial numbers, network IDs and device names are customer data: lock down state/JSON file permissions and use separate state paths per organization.

Missing device records are NOT treated as offline because API permission, pagination, or inventory changes can cause omissions. The caller should separately detect coverage drops and API errors. An initial cadence of 5–15 minutes may be reasonable, subject to API limits and monitoring requirements.