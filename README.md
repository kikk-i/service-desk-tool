# Service Desk Tool

A local diagnostic and maintenance toolkit for **Windows 10/11** and **macOS**, designed for Service Desk and IT Support workflows.

It collects system information, logs, network diagnostics, application data, and FortiClient logs into a structured HTML report and ZIP archive.

Windows additionally supports selected cleanup and system-repair operations.

The tool works locally, does **not upload reports anywhere**, and requires **no additional packages or dependencies**.

## Features

- Windows 10/11 and macOS support
- One-click launchers
- Interactive terminal menu
- Full or section-based diagnostics
- Configurable log collection period: **1–168 hours**
- HTML diagnostic report
- Raw diagnostic files
- Automatic ZIP archive creation
- Network and VPN diagnostics
- FortiClient log collection
- Windows cleanup tools
- DISM and SFC repair workflow
- No telemetry
- No external uploads
- No additional software dependencies

---

## Quick Start

Copy or extract the **entire repository folder** to the target machine.

### Windows

| Mode | Launcher |
|---|---|
| Standard | `Start-Windows.cmd` |
| Administrator | `Start-Windows-Admin.cmd` |

The administrator version triggers a standard UAC prompt.

### macOS

| Mode | Launcher |
|---|---|
| Standard | `Start-macOS.command` |
| Administrator | `Start-macOS-Admin.command` |

The administrator version uses `sudo` and may request the password of a local administrator account.

The launchers open the interactive Service Desk Tool menu and attempt to resize the terminal window for the HUD interface.

If the terminal does not allow window resizing, the tool will continue working normally.

Navigation supports:

- Arrow keys
- Enter
- Number keys
- Esc

---

## macOS Notes

The `.command` launchers must retain executable permissions.

The provided ZIP package preserves these permissions.

If macOS blocks a downloaded script, open it through Finder using **Right Click → Open**, according to your organization's security policy.

Some diagnostic sources may require Terminal to have access to protected system data under:

`System Settings → Privacy & Security`

The administrator launcher automatically restores ownership of generated reports and ZIP archives to the user who started the tool.

---

## Windows Notes

The Windows launchers use:

```powershell
ExecutionPolicy Bypass
```

only for the PowerShell process running the tool.

Group Policy or other organization-level security policies may still prevent the script from executing.

Before using cleanup functionality for the first time, run the built-in self-test on a test workstation:

```powershell
./windows-service-desk.ps1 -SelfTest -Plain
```

The self-test only operates inside its own temporary directory under `%TEMP%`.

---

## Diagnostics

When starting a diagnostic section, you can select a time range between:

`1–168 hours`

The default is:

`24 hours`

The **Full Report** option runs all available diagnostic sections.

Running the tool with administrator privileges may provide access to additional logs and system information.

Not every operating system installation contains every supported log source.

---

## macOS Diagnostic Sections

| Section | Collected data |
|---|---|
| System & Hardware | System and hardware information from `system_profiler` |
| Network & VPN | Interfaces, DNS configuration, routes and up to 3000 recent network / Network Extension log entries |
| Disks & Performance | Disk usage, memory information and running processes |
| Applications & Updates | Installed applications, packages and update history |
| System Events | Up to 5000 recent errors and crashes, available `system.log`, `install.log` and diagnostic reports |
| FortiClient | Local Fortinet/FortiClient logs and up to 5000 recent FortiClient-related unified log entries |

Collected macOS logs are stored under:

```text
raw/mac-logs/
```

FortiClient files are stored under:

```text
raw/forticlient/
```

Each directory contains a `manifest.txt` file describing:

- collected sources
- number of copied files
- read errors
- unavailable sources

Additional macOS Unified Log extracts are saved as:

```text
network-events.txt
events.txt
forticlient-unified.txt
```

---

## FortiClient Diagnostics

On both Windows and macOS, the tool attempts to automatically collect available local FortiClient logs.

The following report types automatically include FortiClient data where available:

- Full Report
- Network & VPN
- FortiClient

No manual FortiClient log export is required.

### Collection limits

FortiClient:

- Maximum 80 files
- Maximum 50 MB per file
- Maximum 250 MB total

Other macOS logs:

- Maximum 100 files
- Maximum 50 MB per file
- Maximum 200 MB total

File-based filtering uses the file's **last modification time**.

Unified Log queries also have entry and execution-time limits. On systems generating a very high volume of logs, the collected data may therefore cover only part of the selected time range.

Automatically collected FortiClient files are **not equivalent to the complete Diagnostic Tool package exported from the Fortinet GUI**.

If a log source does not exist, logging is disabled, or access is denied, the generated report will indicate it.

The tool does not modify FortiClient configuration.

---

## Output

Every diagnostic session creates its own folder containing:

```text
report.html
raw/
<report>.zip
```

Reports are stored in:

```text
reports/
```

next to the main scripts.

The report location can be changed using the environment variable:

```text
SDT_REPORTS
```

Before attaching the generated archive to a support ticket, review its contents.

Diagnostic packages may contain sensitive information such as:

- usernames
- hostnames
- IP addresses
- DNS configuration
- network information
- installed applications
- log contents

---

## Windows Cleanup

Windows includes an interactive cleanup module.

Every cleanup operation must be selected individually.

Before execution, the final confirmation screen requires entering:

```text
USUN
```

Files currently used by Windows are skipped.

The tool can also launch:

```text
cleanmgr
```

where the technician manually selects Windows cleanup categories.

Downloaded Windows Update cleanup is skipped when an update operation is currently active.

The tool also attempts to restore services that were running before the cleanup process.

`Prefetch` cleanup is available as a separate option and is **disabled by default**.

---

## Windows System Repair

DISM and SFC are available from a separate repair menu.

Depending on the workstation, these operations may take several minutes or longer.

Do not close the terminal while they are running.

The repair workflow runs DISM before SFC.

If DISM fails, SFC is skipped and the failure reason is recorded in the report.

---

## Validation Status

### macOS

The following components have been tested:

- shell script syntax
- `log show` queries
- log file collection
- ZIP archive generation

The administrator workflow should still be validated on a test Mac using an administrator account before production deployment.

### Windows

The PowerShell script has passed syntax validation using PowerShell 7.

Windows-specific system operations should be validated on a Windows 10/11 test workstation before production use.

---

## Privacy

Service Desk Tool is designed to operate entirely on the local workstation.

It does not:

- send telemetry
- upload diagnostic data
- send reports to external services
- modify FortiClient settings
- require cloud connectivity

Generated diagnostic reports remain on the local machine until manually copied or attached to a ticket.

---

## Intended Use

This project is intended for:

- Service Desk teams
- Help Desk technicians
- IT Support engineers
- Desktop Support
- troubleshooting Windows and macOS workstations
- collecting diagnostic information before escalation

> Always review generated diagnostic packages before sharing them outside your organization.
