#!/usr/bin/env python3
"""Local repository validation that can run even when PowerShell is unavailable.

This does not replace Pester or a real Microsoft Graph test-tenant run. It validates
repository contracts, script structure, expected Graph endpoints/scopes, Git safety,
and balanced PowerShell delimiters while CI/Pester handle runtime behavior.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"PASS  {name}")
    else:
        FAIL += 1
        print(f"FAIL  {name}: {detail}")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def balanced_powershell(text: str) -> tuple[bool, str]:
    stack: list[tuple[str, int]] = []
    pairs = {')': '(', ']': '[', '}': '{'}
    state = 'code'
    block_depth = 0
    lines = text.splitlines(True)
    offset = 0

    for line in lines:
        stripped = line.rstrip('\r\n')
        if state == 'here_single':
            if stripped.strip() == "'@":
                state = 'code'
            offset += len(line)
            continue
        if state == 'here_double':
            if stripped.strip() == '"@':
                state = 'code'
            offset += len(line)
            continue

        i = 0
        while i < len(line):
            ch = line[i]
            nxt = line[i + 1] if i + 1 < len(line) else ''
            pos = offset + i

            if state == 'line_comment':
                break
            if state == 'block_comment':
                if ch == '#' and nxt == '>':
                    state = 'code'
                    i += 2
                    continue
                i += 1
                continue
            if state == 'single':
                if ch == "'":
                    if nxt == "'":
                        i += 2
                        continue
                    state = 'code'
                i += 1
                continue
            if state == 'double':
                if ch == '`':
                    i += 2
                    continue
                if ch == '"':
                    state = 'code'
                    i += 1
                    continue
                # Delimiters inside $() in interpolated strings are real PowerShell syntax,
                # but this lightweight checker intentionally ignores string internals. Pester's
                # AST parser is the authoritative syntax test in CI.
                i += 1
                continue

            if ch == '<' and nxt == '#':
                state = 'block_comment'
                i += 2
                continue
            if ch == '#':
                state = 'line_comment'
                break
            if ch == '@' and nxt in ("'", '"'):
                state = 'here_single' if nxt == "'" else 'here_double'
                i += 2
                continue
            if ch == "'":
                state = 'single'
                i += 1
                continue
            if ch == '"':
                state = 'double'
                i += 1
                continue
            if ch in '([{':
                stack.append((ch, pos))
            elif ch in ')]}':
                if not stack or stack[-1][0] != pairs[ch]:
                    return False, f"unexpected {ch!r} at offset {pos}"
                stack.pop()
            i += 1
        if state == 'line_comment':
            state = 'code'
        offset += len(line)

    if state in {'single', 'double', 'block_comment', 'here_single', 'here_double'}:
        return False, f"unterminated lexical state: {state}"
    if stack:
        return False, f"unclosed delimiters: {stack[-5:]}"
    return True, ''


required_files = [
    'README.md', 'START-HERE.md', '.gitignore', 'SECURITY.md', 'LICENSE',
    'module/HelpDeskAutomation.psm1', 'module/HelpDeskAutomation.psd1',
    'scripts/New-Employee.ps1', 'scripts/Offboard-Employee.ps1',
    'scripts/Get-UserSupportSnapshot.ps1', 'scripts/Reset-UserAccess.ps1',
    'scripts/Export-HelpDeskAudit.ps1', 'scripts/Test-GraphConnection.ps1',
    'tests/HelpDeskAutomation.Tests.ps1', 'tests/SyntaxAndContracts.Tests.ps1',
    'tests/WorkflowScripts.Tests.ps1', 'tests/Invoke-TestTenantValidation.ps1', 'docs/TESTING.md',
    '.github/workflows/powershell-quality.yml'
]
for rel in required_files:
    check(f"required file {rel}", (ROOT / rel).is_file(), "missing")

operational = {
    'scripts/New-Employee.ps1': [
        'Connect-HdaGraph', 'User.Create', 'graph.microsoft.com/v1.0/users',
        'GroupMember.ReadWrite.All', 'LicenseAssignment.ReadWrite.All', 'Write-HdaAuditEvent'
    ],
    'scripts/Offboard-Employee.ps1': [
        'Connect-HdaGraph', 'User.EnableDisableAccount.All', 'User.RevokeSessions.All',
        'revokeSignInSessions', 'accountEnabled = $false', 'licenseAssignmentStates',
        'assignedByGroup', 'Write-HdaAuditEvent'
    ],
    'scripts/Get-UserSupportSnapshot.ps1': [
        'Connect-HdaGraph', 'AuditLog.Read.All', 'DeviceManagementManagedDevices.Read.All',
        'Get-HdaGraphUserSnapshot', 'Write-HdaAuditEvent'
    ],
    'scripts/Reset-UserAccess.ps1': [
        'Connect-HdaGraph', 'User-PasswordProfile.ReadWrite.All', 'passwordProfile',
        'revokeSignInSessions', 'Write-HdaAuditEvent'
    ],
    'scripts/Export-HelpDeskAudit.ps1': [
        'Connect-HdaGraph', 'Get-HdaGraphUserSnapshot', 'Get-HdaAuditEvents',
        'IT Support Operations Report', 'Microsoft Graph'
    ],
    'scripts/Test-GraphConnection.ps1': [
        'Connect-HdaGraph', 'Organization.Read.All', 'LicenseAssignment.Read.All',
        'graph.microsoft.com/v1.0/me'
    ],
}

for rel, needles in operational.items():
    content = read(rel)
    for needle in needles:
        check(f"{rel} contains {needle}", needle in content, f"missing {needle!r}")
    check(f"{rel} has no demo execution mode", not re.search(r'(?i)DemoMode|UseDemoTenant|sample-users\.json|fake tenant', content), 'demo path found')

for rel in ['scripts/New-Employee.ps1', 'scripts/Offboard-Employee.ps1', 'scripts/Reset-UserAccess.ps1']:
    content = read(rel)
    check(f"{rel} SupportsShouldProcess", 'SupportsShouldProcess = $true' in content, 'missing SupportsShouldProcess')
    check(f"{rel} calls ShouldProcess", '$PSCmdlet.ShouldProcess(' in content, 'missing ShouldProcess call')

for path in list((ROOT / 'scripts').glob('*.ps1')) + list((ROOT / 'module').glob('*.psm1')) + list((ROOT / 'tests').glob('*.ps1')):
    ok, detail = balanced_powershell(path.read_text(encoding='utf-8'))
    check(f"balanced PowerShell delimiters {path.relative_to(ROOT)}", ok, detail)

manifest = read('module/HelpDeskAutomation.psd1')
module = read('module/HelpDeskAutomation.psm1')
exported = re.findall(r"'([A-Za-z][A-Za-z0-9-]+)'", manifest.split('FunctionsToExport', 1)[1].split(')', 1)[0])
for fn in exported:
    check(f"module defines exported function {fn}", re.search(rf'function\s+{re.escape(fn)}\s*\{{', module, re.I) is not None, 'missing implementation')

ignore = read('.gitignore')
for pattern in ['data/audit-log.jsonl', 'data/snapshots/', 'data/offboarding/', 'reports/', '*.private.csv', 'tests/results/']:
    check(f".gitignore protects {pattern}", pattern in ignore, 'missing ignore rule')

readme = read('README.md')
for phrase in ['Microsoft Graph', 'Invoke-Pester', 'Invoke-ScriptAnalyzer', 'WhatIf', 'test/developer tenant']:
    check(f"README documents {phrase}", phrase.lower() in readme.lower(), f"missing {phrase!r}")

csv_path = ROOT / 'config/sample-new-hires.csv'
with csv_path.open(newline='', encoding='utf-8-sig') as fh:
    rows = list(csv.DictReader(fh))
check('sample onboarding CSV has at least one row', bool(rows), 'empty sample')
if rows:
    joined = json.dumps(rows).lower()
    check('sample onboarding CSV uses placeholder tenant values', 'contoso' in joined or 'example' in joined, 'sample may contain non-placeholder tenant data')

preview = read('docs/assets/report-preview.html')
check('sanitized report preview is an HTML document', '<html' in preview.lower() and '</html>' in preview.lower(), 'invalid preview')

print(f"\nLocal validation summary: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
