<h1 align="center">IT Admin Toolkit</h1>

<p align="center">
  Field-tested PowerShell scripts from running IT for a multi-branch clinic network —
  SQL Server backups, Microsoft 365 / Exchange Online, Windows Update and Outlook fixes, networking and endpoint support.
  <br/>
  <sub>Every script is parameterized, documented with comment-based help, and safe by default (<code>-WhatIf</code>, dry runs, backups before changes).</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 5.1 | 7"/>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/SQL%20Server-backups-CC2927?style=for-the-badge&logo=microsoftsqlserver&logoColor=white" alt="SQL Server"/>
  <img src="https://img.shields.io/badge/Microsoft%20365-Exchange%20Online-D83B01?style=for-the-badge&logo=microsoft&logoColor=white" alt="Microsoft 365"/>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/scripts-27-555555?style=flat" alt="27 scripts"/>
  <img src="https://img.shields.io/badge/safe%20by%20default-WhatIf%20%2F%20dry--run-2E7D32?style=flat" alt="safe by default"/>
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat" alt="MIT"/>
  <img src="https://img.shields.io/badge/status-maintained-brightgreen?style=flat" alt="status"/>
</p>

<p align="center"><a href="https://galasulin.github.io/it-admin-toolkit/"><img src="docs/screenshots/app-home.png" alt="IT Toolkit app - home screen (demo data)" width="100%"/></a><br/><b><a href="https://galasulin.github.io/it-admin-toolkit/">Live page: all 67 tools and 27 scripts →</a></b></p>

<p align="center"><a href="README.he.md">🇮🇱 קראו בעברית</a></p>

---

## Why this exists

Most admin scripts live as one-off `.bat` files on a desktop, full of hard-coded server names and shares.
This repository is my own collection — written over years of supporting branches, servers and users —
cleaned up so anyone can run it: **no hard-coded environment, every value is a parameter, every change is
previewable**. Old batch files were rewritten in PowerShell where it made them safer or simpler.

## The app (`app/`)

A local Hebrew web UI that runs **67 admin tools in 11 categories** (workstation diagnostics, fixes, printers, network, servers & SQL, AD users, Microsoft 365, security, setup, reports) on this PC or on a target server.

- `Start-Toolkit.ps1` starts a PowerShell HTTP server **bound to 127.0.0.1 only**, with a random per-run token and a Host-header check, and opens the UI in an app window. `Run-Classic.cmd` is a WPF fallback.
- Every tool is declared in `catalog.json` with a risk level (read-only / changes settings / sensitive); changing tools ask for confirmation and every run is logged.
- Copy `config.example.json` to `config.json` (git-ignored) and fill in your servers. The screenshots use demo data (Contoso, example servers).

| Home | A tool page |
|---|---|
| ![home](docs/screenshots/app-home.png) | ![tool](docs/screenshots/app-tool.png) |

## Scripts

### 🗄️ SQL Server — [`sql/`](sql)

| Script | What it does |
|---|---|
| [`Backup-SqlDatabases.ps1`](sql/Backup-SqlDatabases.ps1) | FULL / DIFF / LOG backups with `CHECKSUM`, compression and optional `COPY_ONLY`, `RESTORE VERIFYONLY` on every file, retention that only removes its own verified file pattern, log file. |
| [`New-SqlBackupJob.sql`](sql/New-SqlBackupJob.sql) | T-SQL: a generic backup procedure (compressed, checksummed, `RESTORE VERIFYONLY`, retention) plus a daily SQL Server Agent job - for servers where backups should run inside SQL Server. |
| [`Invoke-BackupRetention.ps1`](sql/Invoke-BackupRetention.ps1) | Grandfather-father-son retention (10 daily / 4 weekly / 3 monthly) per database. Dry run by default; **never touches log backups**. |
| [`Invoke-SqlFile.ps1`](sql/Invoke-SqlFile.ps1) | Runs a `.sql` file (splits on `GO`) with Windows auth and writes every message and result set to an evidence log — no `sqlcmd` needed. |

### ☁️ Microsoft 365 / Exchange Online — [`m365/`](m365)

| Script | What it does |
|---|---|
| [`Export-DistributionLists.ps1`](m365/Export-DistributionLists.ps1) | Exports all distribution lists (and optionally Microsoft 365 groups) with members, owners and settings to **Excel** (ImportExcel) — or CSV when the module is missing. Nested lists can be expanded. |
| [`Set-AppMailSendScope.ps1`](m365/Set-AppMailSendScope.ps1) | Restricts an Entra app to send mail **only** as chosen mailboxes using RBAC for Applications, then proves it with a positive and a negative test. |
| [`Watch-AppSecretExpiry.ps1`](m365/Watch-AppSecretExpiry.ps1) | Daily tripwire before an app client secret expires (log, event log, pop-up) — integrations otherwise fail silently. |
| [`Set-OneDrivePolicies.ps1`](m365/Set-OneDrivePolicies.ps1) | OneDrive silent sign-in, Files On-Demand and download-size prompt via policy keys, for unmanaged PCs. |

### 🔄 Windows Update — [`windows-update/`](windows-update)

| Script | What it does |
|---|---|
| [`Reset-WindowsUpdate.ps1`](windows-update/Reset-WindowsUpdate.ps1) | The classic repair: stop services, rename `SoftwareDistribution` / `catroot2`, restart, optional DISM + SFC and a new scan. `-StopOnly` just stops the service. |
| [`Remove-WindowsUpdatePackage.ps1`](windows-update/Remove-WindowsUpdatePackage.ps1) | Removes a bad update by KB **or DISM package name** (works for cumulative "RollupFix" packages that `wusa` cannot remove), optional pause. |

### 📧 Outlook — [`outlook/`](outlook)

| Script | What it does |
|---|---|
| [`Backup-OutlookData.ps1`](outlook/Backup-OutlookData.ps1) | Copies a user's signatures, Outlook settings and PST (optionally OST) files with robocopy, plus a restore guide. |
| [`Set-OutlookRegistryFixes.ps1`](outlook/Set-OutlookRegistryFixes.ps1) | Per-version Outlook fixes: disable `winmail.dat` (TNEF), legacy GAL properties dialog, more Exchange accounts per profile — with `.reg` backups and `-Revert`. |
| [`Remove-OfficeMsiPatch.ps1`](outlook/Remove-OfficeMsiPatch.ps1) | Removes a single MSI Office patch (default: the update that made Outlook 2010 start in safe mode). |

### 🌐 Network — [`network/`](network)

| Script | What it does |
|---|---|
| [`Add-FirewallPortRule.ps1`](network/Add-FirewallPortRule.ps1) | Firewall rules from presets (SQL Server, SSAS, RDP, ping) or custom ports, idempotent, scoped by profile and source. |
| [`Export-FirewallConfig.ps1`](network/Export-FirewallConfig.ps1) | Exports the firewall policy (`.wfw`) and a CSV of all rules; import / reset with an automatic backup first. |
| [`Set-DnsServers.ps1`](network/Set-DnsServers.ps1) | Sets static DNS servers or back to DHCP, then flushes and re-registers DNS. |
| [`Repair-TimeSync.ps1`](network/Repair-TimeSync.ps1) | Fixes Windows Time: domain hierarchy or manual NTP peers, backup of the settings, forced resync. |
| [`Connect-NetworkDrives.ps1`](network/Connect-NetworkDrives.ps1) | Maps drives from a CSV, persistently, with an optional prompted credential — no passwords in files. |

### 💻 Endpoint — [`endpoint/`](endpoint)

| Script | What it does |
|---|---|
| [`Get-EndpointInfo.ps1`](endpoint/Get-EndpointInfo.ps1) | One-file helpdesk report: user & groups, network, OS, serial / service tag, disks, GPU, installed programs. |
| [`Get-LocalAdmins.ps1`](endpoint/Get-LocalAdmins.ps1) | Audits local Administrators group members on one or many PCs (language-independent SID) to CSV. |
| [`Clear-PrintSpooler.ps1`](endpoint/Clear-PrintSpooler.ps1) | Clears stuck print jobs locally or remotely. |
| [`New-ShadowCopy.ps1`](endpoint/New-ShadowCopy.ps1) | Creates "Previous Versions" shadow copies and optionally sizes shadow storage. |
| [`Repair-RdpClientLicenseStore.ps1`](endpoint/Repair-RdpClientLicenseStore.ps1) | Fixes the RDP client "licensing protocol" error for standard users, with ACL backup and restore. |
| [`audio/Get-AudioDiagnostics.ps1`](endpoint/audio/Get-AudioDiagnostics.ps1) | Read-only deep diagnosis of choppy audio: endpoint formats, APO chain, drivers, power, live DPC latency, event logs. |
| [`audio/Repair-AudioStutter.ps1`](endpoint/audio/Repair-AudioStutter.ps1) | Report / `-Apply` / `-Rollback` fix for Nahimic-related stutter, Fast Startup and battery CPU floor. |
| [`audio/Test-AudioFix.ps1`](endpoint/audio/Test-AudioFix.ps1) | PASS / FAIL verification after the fix. |

### 👥 Active Directory — [`ad/`](ad)

| Script | What it does |
|---|---|
| [`Move-StaleComputers.ps1`](ad/Move-StaleComputers.ps1) | Reports computers inactive for N days; optionally disables them (with a description stamp) and moves them to an OU. |

## How to run

```powershell
# 1. Read the help first - every script documents its parameters, requirements and risks
Get-Help .\sql\Backup-SqlDatabases.ps1 -Full

# 2. Allow local scripts for this session only (no machine-wide change)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# 3. Preview, then run
.\windows-update\Reset-WindowsUpdate.ps1 -WhatIf
.\windows-update\Reset-WindowsUpdate.ps1
```

- Scripts are saved as **UTF-8 with BOM**, so Windows PowerShell 5.1 reads them correctly.
- Most system-changing scripts need an **elevated** PowerShell (stated in each script's `.NOTES`).
- Optional modules: `ExchangeOnlineManagement`, `ImportExcel`, RSAT `ActiveDirectory`.
- Values in angle brackets such as `<FILE_SERVER>`, `<ADMIN_UPN>` or `<TENANT_ID_GUID>` are placeholders — replace them with your own.

## ⚠️ Safety

These scripts change servers, services, registry, firewall and backups. They are built to be careful —
`-WhatIf` / `-Confirm` everywhere a change is made, dry runs by default for anything that deletes,
backups (`.reg`, `.wfw`, ACL) before modifications, and rollback switches where possible — but they are
provided **as is**. Test in a lab or on one machine first, read the help, and keep backups.

## Stack

PowerShell 5.1 / 7 · Windows 10 / 11 / Server · SQL Server (T-SQL, System.Data.SqlClient) ·
Exchange Online PowerShell (ExchangeOnlineManagement) · ImportExcel · Active Directory module ·
NetSecurity / DnsClient · DISM · robocopy · WMI / CIM

## My role

I am the IT manager of a physiotherapy clinic network with several branches. I wrote these scripts
for real incidents and recurring chores — server backups, Microsoft 365 administration, broken updates,
Outlook problems, branch networking and helpdesk work — and later cleaned them up, generalized them and
documented them for publication. Some of the newer ones were written together with an AI coding assistant
under my direction and reviewed and tested by me.

## Status

Actively used and maintained. Issues and pull requests are welcome.

## Privacy

Everything environment-specific was removed before publishing: server and computer names, domains,
user names, mailboxes, shares, IP addresses, tenant and app IDs, and credentials are now parameters or
neutral placeholders (`contoso.local`, `<SQL_SERVER>`, `\\<FILE_SERVER>\<SHARE>`). No real organization
data, logs or exports are included, and `.gitignore` keeps script output (`logs/`, `exports/`, CSV/XLSX)
out of the repository.

---

**Built by [Gal Asulin](https://github.com/galasulin), IT Manager**
