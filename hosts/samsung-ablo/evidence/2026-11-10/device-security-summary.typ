#set document(title: "Ablo laptop — security evidence", author: "Erik Frankling")
#set page(paper: "a4", margin: 21mm, footer: context align(right)[#counter(page).display()])
#set text(font: "DejaVu Sans", size: 9.5pt)
#set par(leading: 0.6em)
#let blue = rgb("184968")
#show heading: set text(fill: blue)
#text(size: 23pt, weight: "bold", fill: blue)[Ablo laptop]
#linebreak()
#text(size: 16pt)[Security evidence · 10 November 2026]

*Interim evidence — validation and policy review outstanding*

Samsung Galaxy Book6 Pro 14 · hostname `samsung-ablo` \
Erik Frankling · erik\@abloatai.com \
NixOS 26.11.20261107.f4a03c0 · Linux installation only

= Management overview
The laptop has encrypted Linux storage, Secure Boot, an active firewall, automatic locking, ClamAV and Vanta Device Monitor. These are observed endpoint controls, not a SOC 2 certification or an assertion that Ablo's policy has been met. This summary accompanies the detailed Markdown report and dated technical evidence.

#table(columns: (30%, 70%), inset: 8pt, stroke: 0.4pt + rgb("ccd6df"),
  table.header([*Control*], [*Evidence / current status*]),
  [Disk encryption], [Verified LUKS2 root storage; Vanta's encryption query independently reports encrypted storage. RAM-only zram swap.],
  [Secure Boot], [Enabled in user mode; TPM2, measured UKI and measured OS reported.],
  [Screen lock], [300-second idle lock and before-sleep lock configured. Password and physical fingerprint unlocks observed. Simultaneous 1Password contention remains unverified.],
  [Anti-malware], [ClamAV 1.5.4, hourly signature checks, quarantine and scheduled scans configured. Engine detection and quarantine demonstrated. Recursive client repaired; application-data exclusions documented. Baseline scan incomplete.],
  [Firewall / SSH], [Firewall active for IPv4 and IPv6 with explicit service allowances. SSH ordinary passwords disabled; keyboard-interactive setting under review.],
  [Password manager], [1Password 8.12.44 installed. Company sign-in, MFA and use not established by installation.],
  [Vanta], [EU enrollment and agent communication verified. Linux encryption queried separately from agent health.],
)

= What Vanta can establish
Vanta documents Linux disk-encryption monitoring. Its Linux Device Monitor does not detect antivirus, screen lock or password managers. These require supplementary evidence. NixOS is outside Vanta's published Ubuntu/Debian support list; observed operation does not change that support boundary.

#pagebreak()
= Antivirus evidence and limits
ClamAV 1.5.4 provides the scanning engine and signature updates. The cached stable 1.4.3 on-access client is used because it correctly watches existing subdirectories; benign fd-passing scans confirm compatibility with the current engine. Hot application databases and caches are excluded from on-access scanning and retained in scheduled-scan scope.

The engine detected and quarantined harmless EICAR tests, including a nested test under an earlier configuration. All test artifacts were removed at the user’s request. Final checks confirmed 77,847 directory watches, including Downloads and dynamically created nested folders, with only five open descriptors and no startup errors. Signature update at 18:00 CET succeeded: daily 28179, main 63, bytecode 339.

The baseline scan of 18:11:23–18:17:43 CET was interrupted by daemon reconfiguration, with zero infected files and seven errors. No clean-scan claim is made. The weekly schedule is Monday at 12:00 with missed-run persistence.

Detection and quarantine are asynchronous: opening or executing a file is not synchronously blocked. On-access scanning has a 100 MiB file limit and covers the home directory and /tmp, with explicit application-data exclusions. Root and the isolated Executor service are excluded from on-access events; scheduled scanning still covers their files. ClamAV is not equivalent to managed EDR or a staffed incident-response service.

= Administration and updates
Passwordless sudo and Docker-group access are intentionally retained for unattended development agents. Both grant broad local authority. SOC 2 does not impose one universal sudo-password setting; suitability depends on Ablo's approved access controls and risk treatment.

Daily NixOS updates are configured. The home-network restriction was removed; updates still require mains power and network/cache availability. A future successful unattended update away from home has not yet been observed.

= Outstanding validation
- Monitor final on-access queue behavior and obtain a completed baseline scan.
- Retest simultaneous 1Password fingerprint use and actual token saving.
- Verify final SSH authentication settings after activation.
- Obtain Ablo policy and compare endpoint protection, patching, privilege and incident requirements.
- Confirm company password-manager use and any required management approvals.

= Local credential storage
A Secret Service dependency needed by 1Password was restored. A dummy credential store/read/delete test passed without prompts; a real 1Password token save remains unverified. The keyring has no separate encryption or unlock password. User-only file permissions and full-disk encryption protect it at rest; it remains available while the screen is locked.

= Evidence handling
This report contains no credentials, recovery keys, mailbox content or browser history. Windows is outside scope: its partition has a BitLocker signature, but its running security state was not checked. Reports have been prepared locally; they have not been sent to a manager or uploaded to Vanta.

= Sources
#text(size: 8pt)[
Vanta: #link("https://help.vanta.com/en/articles/11346064-troubleshooting-the-vanta-device-monitor-on-linux-machines")[Linux Device Monitor limitations]; #link("https://help.vanta.com/en/articles/11346109-antivirus-solutions-detected-by-vanta")[antivirus detection]; #link("https://help.vanta.com/en/articles/11345596-evidence-collection-for-unmonitored-laptops")[manual evidence]. \
Local sources: `hosts/samsung-ablo/` Nix configuration, selected command results and journal events. See `device-security-report.md` for detailed scope and limitations.
]
