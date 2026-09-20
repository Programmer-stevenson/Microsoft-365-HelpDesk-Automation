[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserId,
    [string]$OutputPath,
    [string]$ReportTitle = 'IT Support Operations Report',
    [switch]$IncludeSignInActivity,
    [switch]$IncludeIntuneDevices,
    [string]$TenantId,
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../module/HelpDeskAutomation.psm1') -Force
Initialize-HdaDataStore

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-HdaProjectRoot) 'reports/IT-Support-Operations-Report.html'
}

$scopes = @(
    'User.Read',
    'User.Read.All',
    'Organization.Read.All',
    'GroupMember.Read.All',
    'LicenseAssignment.Read.All',
    'Device.Read.All'
)

if ($IncludeSignInActivity) {
    $scopes += 'AuditLog.Read.All'
}

if ($IncludeIntuneDevices) {
    $scopes += 'DeviceManagementManagedDevices.Read.All'
}

Connect-HdaGraph -Scopes $scopes -TenantId $TenantId -UseDeviceCode:$UseDeviceCode | Out-Null

$me = Invoke-HdaGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName'
$org = Get-HdaGraphOrganization
$events = @(Get-HdaAuditEvents | Sort-Object timestamp -Descending)
$snapshot = Get-HdaGraphUserSnapshot `
    -Identity $UserId `
    -IncludeSignInActivity:$IncludeSignInActivity `
    -IncludeIntuneDevices:$IncludeIntuneDevices

function H {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Format-HdaDate {
    param($Value)
    if (-not $Value) { return '—' }

    try {
        return ([datetime]$Value).ToLocalTime().ToString('MMM d, yyyy h:mm tt')
    }
    catch {
        return [string]$Value
    }
}

$total = $events.Count
$success = @($events | Where-Object status -eq 'Success').Count
$warnings = @($events | Where-Object status -eq 'Warning').Count
$failed = @($events | Where-Object status -eq 'Failed').Count
$users = @($events | Where-Object targetUser | Select-Object -ExpandProperty targetUser -Unique).Count
$successRate = if ($total -gt 0) { [math]::Round(($success / $total) * 100) } else { 0 }
$generated = Get-Date

$eventRows = if ($events.Count -eq 0) {
    '<tr><td colspan="6" class="empty">No local audit events yet. Run one of the Microsoft Graph automation scripts first.</td></tr>'
}
else {
    ($events | ForEach-Object {
        $detailPairs = @()

        if ($_.details) {
            foreach ($property in $_.details.PSObject.Properties) {
                if ($null -eq $property.Value) { continue }

                $value = if ($property.Value -is [System.Array]) {
                    ($property.Value -join '; ')
                }
                else {
                    [string]$property.Value
                }

                if ($value.Length -gt 180) {
                    $value = $value.Substring(0, 180) + '…'
                }

                $detailPairs += ('{0}: {1}' -f $property.Name, $value)
            }
        }

        $details = H ($detailPairs -join ' · ')
        $statusClass = ([string]$_.status).ToLowerInvariant()

        "<tr data-status='$(H $_.status)'><td>$(H (Format-HdaDate $_.timestamp))</td><td>$(H $_.targetUser)</td><td>$(H $_.action)</td><td><span class='badge $statusClass'>$(H $_.status)</span></td><td>$(H $_.ticketId)</td><td class='details'>$details</td></tr>"
    }) -join "`n"
}


    $initials = (($snapshot.user.displayName -split '\s+' | Where-Object { $_ } | ForEach-Object { $_[0] }) -join '')
    if ($initials.Length -gt 2) {
        $initials = $initials.Substring(0, 2)
    }

    $accountState = if ($snapshot.user.accountEnabled) { 'Enabled' } else { 'Disabled' }
    $accountClass = if ($snapshot.user.accountEnabled) { 'success' } else { 'failed' }
    $managerName = if ($snapshot.manager) { $snapshot.manager.displayName } else { '—' }

    $department = if ($snapshot.user.department) { $snapshot.user.department } else { '—' }
    $jobTitle = if ($snapshot.user.jobTitle) { $snapshot.user.jobTitle } else { '—' }

    $userPanel = @"
<div class="identity">
  <div class="avatar">$(H $initials)</div>
  <div><h3>$(H $snapshot.user.displayName)</h3><p>$(H $snapshot.user.userPrincipalName)</p></div>
  <span class="badge $accountClass account-badge">$(H $accountState)</span>
</div>
<div class="user-grid">
  <div><span>Department</span><strong>$(H $department)</strong></div>
  <div><span>Job title</span><strong>$(H $jobTitle)</strong></div>
  <div><span>Manager</span><strong>$(H $managerName)</strong></div>
  <div><span>Last sign-in</span><strong>$(H (Format-HdaDate $snapshot.lastSignInDateTime))</strong></div>
</div>
"@

    $groupChips = if (@($snapshot.groups).Count -eq 0) {
        '<span class="chip muted">No group data returned</span>'
    }
    else {
        (@($snapshot.groups) | Sort-Object displayName | ForEach-Object {
            "<span class='chip'>$(H $_.displayName)</span>"
        }) -join ''
    }

    $licenseChips = if (@($snapshot.licenses).Count -eq 0) {
        '<span class="chip muted">No direct license details returned</span>'
    }
    else {
        (@($snapshot.licenses) | Sort-Object skuPartNumber | ForEach-Object {
            "<span class='chip license'>$(H $_.skuPartNumber)</span>"
        }) -join ''
    }

    $allDevices = @()

    foreach ($device in @($snapshot.managedDevices)) {
        $allDevices += [pscustomobject]@{
            name       = if ($device.deviceName) { $device.deviceName } else { $device.managedDeviceName }
            os         = $device.operatingSystem
            version    = $device.osVersion
            state      = $device.complianceState
            lastSeen   = $device.lastSyncDateTime
            sourceType = 'Intune'
        }
    }

    foreach ($device in @($snapshot.registeredDevices)) {
        $allDevices += [pscustomobject]@{
            name       = $device.displayName
            os         = $device.operatingSystem
            version    = $device.operatingSystemVersion
            state      = $device.trustType
            lastSeen   = $device.approximateLastSignInDateTime
            sourceType = 'Entra'
        }
    }

    $deviceRows = if ($allDevices.Count -eq 0) {
        '<tr><td colspan="6" class="empty">No device data returned.</td></tr>'
    }
    else {
        ($allDevices | ForEach-Object {
            "<tr><td>$(H $_.name)</td><td>$(H $_.sourceType)</td><td>$(H $_.os)</td><td>$(H $_.version)</td><td>$(H $_.state)</td><td>$(H (Format-HdaDate $_.lastSeen))</td></tr>"
        }) -join "`n"
    }

$verifiedDomains = @($org.verifiedDomains | Where-Object { $_.isVerified } | Select-Object -ExpandProperty name)
$domainText = if ($verifiedDomains.Count -gt 0) { $verifiedDomains -join ', ' } else { '—' }

$template = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>__TITLE__</title>
<style>
:root{--bg:#07111f;--panel:#0c1728;--line:#21334d;--text:#eef5ff;--muted:#8fa4bf;--accent:#64d2ff;--accent2:#7c8cff;--success:#42d392;--warn:#f7c65f;--danger:#ff6b7a;--shadow:0 20px 60px rgba(0,0,0,.3)}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 85% -10%,rgba(100,210,255,.13),transparent 34%),radial-gradient(circle at -5% 0,rgba(124,140,255,.14),transparent 30%),var(--bg);color:var(--text);font-family:Inter,Segoe UI,Arial,sans-serif;line-height:1.5}.wrap{max-width:1320px;margin:0 auto;padding:42px 28px 70px}.top{display:flex;align-items:flex-start;justify-content:space-between;gap:24px;margin-bottom:28px}.eyebrow{font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--accent);font-weight:800}.top h1{font-size:clamp(30px,4vw,52px);line-height:1.04;margin:8px 0 8px;letter-spacing:-.035em}.top p{margin:0;color:var(--muted);max-width:760px}.top-actions{display:flex;gap:10px;flex-wrap:wrap}.button,select,input{border:1px solid var(--line);background:#0a1526;color:var(--text);border-radius:10px;padding:10px 12px}.button{cursor:pointer;font-weight:700}.button:hover{border-color:var(--accent)}.tenant{display:flex;gap:9px;flex-wrap:wrap;margin-top:12px}.tenant span{font-size:11px;color:#cfe5ff;background:#0b192b;border:1px solid #29415f;border-radius:999px;padding:6px 9px}.metrics{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;margin:22px 0}.metric,.card{background:linear-gradient(180deg,rgba(17,31,52,.94),rgba(10,23,40,.94));border:1px solid var(--line);border-radius:18px;box-shadow:var(--shadow)}.metric{padding:18px}.metric span{display:block;color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.08em;font-weight:700}.metric strong{display:block;margin-top:6px;font-size:30px;letter-spacing:-.03em}.metric small{color:var(--muted)}.grid{display:grid;grid-template-columns:1.08fr .92fr;gap:16px;margin-top:16px}.card{padding:20px;overflow:hidden}.card h2{font-size:17px;margin:0 0 16px}.identity{display:flex;align-items:center;gap:13px}.avatar{width:48px;height:48px;border-radius:14px;display:grid;place-items:center;background:linear-gradient(135deg,var(--accent2),var(--accent));font-size:21px;font-weight:900;color:#06111c}.identity h3{margin:0;font-size:20px}.identity p{margin:2px 0 0;color:var(--muted);font-size:13px}.account-badge{margin-left:auto}.user-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:18px}.user-grid div{padding:12px;background:#091524;border:1px solid #172a43;border-radius:12px}.user-grid span{display:block;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.08em}.user-grid strong{font-size:13px}.section-label{font-size:11px;text-transform:uppercase;letter-spacing:.1em;color:var(--muted);font-weight:800;margin:16px 0 9px}.chips{display:flex;gap:8px;flex-wrap:wrap}.chip{padding:6px 9px;border:1px solid #29415f;border-radius:999px;background:#0b192b;color:#cfe5ff;font-size:12px}.chip.license{border-color:#3b3f75;background:#141837}.chip.muted{opacity:.65}.badge{display:inline-flex;align-items:center;border-radius:999px;padding:5px 8px;font-size:11px;font-weight:800;border:1px solid transparent}.badge.success{color:#9df2c9;background:rgba(66,211,146,.1);border-color:rgba(66,211,146,.25)}.badge.warning{color:#ffe19a;background:rgba(247,198,95,.1);border-color:rgba(247,198,95,.24)}.badge.failed{color:#ffb0b9;background:rgba(255,107,122,.1);border-color:rgba(255,107,122,.24)}.badge.info{color:#b5eaff;background:rgba(100,210,255,.08);border-color:rgba(100,210,255,.22)}.table-card{margin-top:16px;padding:0}.table-head{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:18px 20px;border-bottom:1px solid var(--line)}.table-head h2{margin:0}.filters{display:flex;gap:8px;flex-wrap:wrap}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;font-size:12.5px}th{text-align:left;color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.08em;padding:12px 14px;background:#091423;position:sticky;top:0}td{padding:13px 14px;border-top:1px solid #172740;vertical-align:top}tr:hover td{background:rgba(100,210,255,.025)}td.details{max-width:420px;color:#afc1d8}.empty,.empty-card{color:var(--muted);text-align:center;padding:30px}.device-table th,.device-table td{padding:10px 9px}.footer{display:flex;justify-content:space-between;gap:18px;color:var(--muted);font-size:11px;margin-top:18px;padding:0 4px}.signal{height:7px;border-radius:999px;background:#13253d;overflow:hidden;margin-top:12px}.signal i{display:block;height:100%;width:__SUCCESS_RATE__%;background:linear-gradient(90deg,var(--accent2),var(--success));border-radius:999px}code{color:#b5eaff}@media(max-width:900px){.metrics{grid-template-columns:repeat(2,1fr)}.grid{grid-template-columns:1fr}.top{flex-direction:column}.user-grid{grid-template-columns:1fr}.wrap{padding:26px 16px 50px}}@media print{body{background:#fff;color:#111}.wrap{max-width:none;padding:16px}.metric,.card{box-shadow:none;background:#fff;border-color:#ccd4df}.top-actions{display:none}.top p,.metric small,.metric span,.identity p,.user-grid span,.section-label,.footer{color:#536170}th{background:#eef2f6;color:#344050}td{border-color:#dde3ea}.user-grid div{background:#f6f8fa;border-color:#dde3ea}.table-wrap{overflow:visible}}
</style>
</head>
<body>
<div class="wrap">
  <header class="top">
    <div>
      <div class="eyebrow">Microsoft Graph · Entra ID · Intune · Automation</div>
      <h1>__TITLE__</h1>
      <p>Operational evidence generated from real Microsoft Graph workflows plus the toolkit's local JSONL audit trail.</p>
      <div class="tenant"><span>Tenant: __TENANT__</span><span>Signed in: __ACCOUNT__</span><span>Domains: __DOMAINS__</span></div>
    </div>
    <div class="top-actions"><button class="button" onclick="window.print()">Print / Save PDF</button><button class="button" onclick="clearFilters()">Clear filters</button></div>
  </header>

  <section class="metrics">
    <div class="metric"><span>Total Graph actions</span><strong>__TOTAL__</strong><small>Locally audited operations</small></div>
    <div class="metric"><span>Successful</span><strong>__SUCCESS__</strong><div class="signal"><i></i></div></div>
    <div class="metric"><span>Warnings</span><strong>__WARNINGS__</strong><small>Review recommended</small></div>
    <div class="metric"><span>Failed</span><strong>__FAILED__</strong><small>Requires follow-up</small></div>
    <div class="metric"><span>Users touched</span><strong>__USERS__</strong><small>Unique target identities</small></div>
  </section>

  <section class="grid">
    <div class="card"><h2>Current Microsoft Graph user snapshot</h2>__USER_PANEL__<div class="section-label">Direct group memberships</div><div class="chips">__GROUP_CHIPS__</div><div class="section-label">License details</div><div class="chips">__LICENSE_CHIPS__</div></div>
    <div class="card"><h2>Endpoint inventory</h2><div class="table-wrap"><table class="device-table"><thead><tr><th>Device</th><th>Source</th><th>OS</th><th>Version</th><th>State</th><th>Last activity</th></tr></thead><tbody>__DEVICE_ROWS__</tbody></table></div></div>
  </section>

  <section class="card table-card">
    <div class="table-head"><h2>Operations timeline</h2><div class="filters"><input id="search" type="search" placeholder="Search user, action, ticket…" oninput="filterRows()"/><select id="status" onchange="filterRows()"><option value="">All statuses</option><option>Success</option><option>Warning</option><option>Failed</option><option>Info</option></select></div></div>
    <div class="table-wrap"><table id="events"><thead><tr><th>Time</th><th>User</th><th>Action</th><th>Status</th><th>Ticket</th><th>Details</th></tr></thead><tbody>__EVENT_ROWS__</tbody></table></div>
  </section>

  <footer class="footer"><span>Generated __GENERATED__</span><span>Microsoft 365 Help Desk Automation Toolkit</span></footer>
</div>
<script>
function filterRows(){const q=document.getElementById('search').value.toLowerCase();const status=document.getElementById('status').value;document.querySelectorAll('#events tbody tr').forEach(r=>{const text=r.innerText.toLowerCase();const okQ=!q||text.includes(q);const okS=!status||r.dataset.status===status;r.style.display=(okQ&&okS)?'':'none';});}
function clearFilters(){document.getElementById('search').value='';document.getElementById('status').value='';filterRows();}
</script>
</body>
</html>
'@

$replacements = [ordered]@{
    '__TITLE__'         = (H $ReportTitle)
    '__TENANT__'        = (H $org.displayName)
    '__ACCOUNT__'       = (H $me.userPrincipalName)
    '__DOMAINS__'       = (H $domainText)
    '__TOTAL__'         = [string]$total
    '__SUCCESS__'       = [string]$success
    '__WARNINGS__'      = [string]$warnings
    '__FAILED__'        = [string]$failed
    '__USERS__'         = [string]$users
    '__SUCCESS_RATE__'  = [string]$successRate
    '__USER_PANEL__'    = $userPanel
    '__GROUP_CHIPS__'   = $groupChips
    '__LICENSE_CHIPS__' = $licenseChips
    '__DEVICE_ROWS__'   = $deviceRows
    '__EVENT_ROWS__'    = $eventRows
    '__GENERATED__'     = (H ($generated.ToString('MMM d, yyyy h:mm tt')))
}

$html = $template
foreach ($key in $replacements.Keys) {
    $html = $html.Replace($key, [string]$replacements[$key])
}

$html | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Microsoft Graph operations report written to: $OutputPath" -ForegroundColor Green
