# Ablo work laptop — security evidence

**Device:** samsung-ablo · Samsung Galaxy Book6 Pro 14  
**Assigned user:** Erik Frankling · erik@abloatai.com  
**Operating system:** NixOS 26.11.20261107.f4a03c0 (Linux)  
**Assessment date:** 10 November 2026 · Europe/Stockholm (CET, UTC+01:00)  
**Status:** Interim evidence report — verified observations with outstanding validation and company-policy review explicitly listed.

## Purpose and scope

This report records observable security controls on the Linux installation of this work laptop. It supports management review and evidence collection; it is not a SOC 2 certification, audit opinion, or declaration that all organizational requirements are met. The Windows installation is present but was not booted or assessed during this review. Facts observed live, configuration intent, and unverified requirements are distinguished below.

No company security policy was available to the assessor at the time of drafting. Ablo's approved policy and the auditor's evidence requirements take precedence over suggested control mappings. Credentials, recovery keys, browser history, mail and document contents are excluded from this report.

## 1. Storage encryption and Secure Boot

**Verified:** Linux root storage is an active LUKS2 mapping named `cryptroot`, backed by `/dev/nvme0n1p5`. `cryptsetup status cryptroot` reports `aes-xts-plain64` with a 512-bit combined XTS key. Root `/` and the read-only `/nix/store` bind mount resolve to this encrypted mapping. Swap currently uses zram in RAM; no disk-backed swap was listed.

**Verified independently by the Vanta agent:** `vanta-cli list encryption --json` reports `/dev/dm-0` with `encrypted: "1"` and maps `/dev/mapper/cryptroot` to `/`. This is encryption evidence from the dedicated encryption query, not a conclusion drawn from `doctor`.

**Verified:** firmware Secure Boot is enabled in user mode. `bootctl status` also reports TPM2 support, a measured UKI and a measured OS.

**Scope boundaries:** the EFI boot partition is a separate unencrypted FAT filesystem. Windows' main partition is identified as BitLocker, but Windows protection state, recovery-key custody and recovery testing were not established in this Linux-only check. TPM-bound automatic unlock is configured; this assessment does not re-enroll or disclose recovery material, nor does it perform a reboot or recovery exercise.

## 2. Screen locking and local authentication

**Verified configuration:** hypridle is active, requests a lock after 300 seconds of idle time and before sleep. A startup lock is configured because the graphical session starts automatically after disk unlock. The password authentication path remains enabled.

**Observed event evidence:** the journal records an idle lock at 17:14:55 CET, successful password authentication at 17:15:52, and unlock at 17:15:53 on 10 November 2026. This supports one observed idle-lock/password-unlock cycle; it does not demonstrate every sleep, lid and docking condition.

**Verified unlock evidence:** journal events at 17:55:30–31, 17:55:36–37 and 17:55:43–44 CET record fingerprint `verify-match` followed by session unlock. The crash-prone LXQt authentication agent has been replaced by active polkit-gnome. Fingerprint support and password fallback remain enabled. Simultaneous fingerprint-reader contention with a 1Password request has not yet been proven resolved. The separate missing Secret Service dependency affecting 1Password 2FA persistence was repaired: gnome-keyring is active and a dummy store/read/delete test passed without prompts. A real 1Password token save still requires an application retry. The keyring has no separate encryption or unlock password; user-only file permissions and LUKS protect it at rest, and it remains available during screen lock.

Lock-screen animation was disabled declaratively at the user's request. This is a usability change, not a separate security control.

## 3. Anti-malware

The current scanning engine and signature updater are ClamAV 1.5.4. The on-access client uses the cached stable ClamAV 1.4.3 package because it correctly registers existing subdirectories on this system; the 1.5.4 client did not. The older client sends files to the current scanning engine. The configuration uses ClamAV's own quarantine option and a root-owned `0700` quarantine directory, `/var/lib/clamav/quarantine`. Quarantine is reversible and does not delete source files permanently. The graphical ClamTk application is also installed.

**Automatic signature checks:** scheduled hourly. The 18:00 CET run on 10 November completed successfully and reported daily database 28179, main database 63, and bytecode database 339 up to date. Earlier checks encountered a CDN cooldown; successful operation was verified after it expired.

**Detection evidence:** the current engine detected standard harmless EICAR tests and moved them into quarantine, including a nested Downloads test at 18:19:18 CET. That test used an earlier mount-wide monitoring configuration and took 56 seconds under startup load. Whole-mount monitoring was subsequently replaced because application database events accumulated. All test originals and quarantined copies were removed at the user’s request; no further malware-signature testing was performed. The final directory-client configuration is validated using actual inode watch registrations and benign file scanning, not a new malware test.

**Final watch validation (18:33 CET):** 77,847 inotify watches and 77,847 fanotify marks were registered, below the kernel quota of 524,288. Inode matching confirmed coverage of Downloads and ordinary dotfiles, plus a newly created Downloads directory and its nested child. The process had five open descriptors, with no accumulated scan-event backlog in that snapshot and no startup errors. A short observation does not guarantee performance under every workload.

**Client compatibility:** in an isolated, pre-existing three-directory tree, the 1.5.4 client registered only one directory, while the cached 1.4.3 client registered all three. Its fd-passing client successfully scanned a harmless nested text file through the active 1.5.4 daemon in 0.003 seconds. This verifies client/daemon compatibility without requiring an engine downgrade.

**Periodic scan:** baseline attempts were interrupted by configuration activation. The 18:11:23–18:17:43 attempt ended with zero infected files and seven errors when the scanning daemon restarted; this is not a completed clean scan. It scans `/home`, `/var/lib`, `/tmp`, `/etc`, and `/var/tmp`; the quarantine directory is excluded. The recurring schedule is Mondays at 12:00 with missed-run persistence. A completed baseline result has not yet been recorded. Unix sockets are unsupported scan objects and produced warnings; these are not malware findings.

**Practical limits:** on-access prevention is disabled, so detection and quarantine occur asynchronously and do not guarantee that a file cannot be opened or executed before response. The directory configuration covers the user home directory and /tmp recursively, with a 100 MiB on-access file limit. Hot application data is excluded from on-access scanning: .cache, .codex, .t3, Firefox and Chromium-family profiles, and the 1Password profile. Ordinary dotfiles, projects and downloads are intended to remain watched. Excluded data remains within the scheduled scan scope. On-access scanning excludes the ClamAV account to avoid recursive scanning. Files accessed only by root or the isolated Executor service rely on explicit scheduled scans rather than on-access events. The scanner does not provide commercial EDR, tamper protection, a staffed monitoring function, or a guarantee that every malware family can be detected.

**Performance controls:** the ClamAV service slice is capped at one CPU equivalent, has low I/O weight, and the daemon uses at most two scan threads. These controls protect desktop usability but can lengthen large scans.

**Response workflow for review:** a detection is quarantined and logged; the local desktop notification draws the user's attention. Erik should stop using the suspected file, review the detection and affected device, and follow Ablo's incident-reporting process. Only a reviewed false positive should be restored. This proposed workflow needs to be reconciled with Ablo's existing incident policy; the report does not invent an approved response SLA or claim that a central security team has acknowledged alerts.

## 4. Password manager

**Verified installation:** 1Password 8.12.44 is present in the active system. System authentication is configured through the upstream NixOS 1Password module.

**Not established by installation:** signed-in company membership, account MFA enforcement, daily use, vault policy, and compliance with Ablo's password-management requirements. No vault contents or credentials were opened for this assessment. The reported system-authentication conflict is covered in section 2.

## 5. Network protection, updates and administrator access

**Firewall:** the NixOS firewall service is active. Both IPv4 and IPv6 filter chains end in refusal/drop rules. This is not a blanket closure of inbound services: SSH, developer port 4096, Syncthing, KDE Connect and Mosh have configured allowances, with additional Tailscale and local virtual-network rules. Their business need and allowed network scope should be reviewed against Ablo's policy before describing exposure as approved.

**SSH:** the inspected daemon configuration disables ordinary password authentication and sets root login to `prohibit-password`. Keyboard-interactive authentication remained enabled in the initial evidence snapshot; a key-only claim requires that setting to be disabled or its authentication path otherwise justified and tested.

**Updates:** the configuration enables daily cached NixOS updates. The work laptop's former home-network-only restriction has been removed, allowing updates away from home when the cache and network are reachable. The job still requires mains power. The current system has been rebuilt during this work; a future successful unattended away-from-home run has not yet been observed. No vulnerability scan or patch-SLA assessment was performed.

**Developer administration:** Erik intentionally retains passwordless sudo and Docker-group access so coding agents can run unattended. Docker-group access is itself root-equivalent. SOC 2 does not prescribe a universal sudo-password setting. This report records the access model for policy review; it is neither proof of a control failure nor proof that Ablo has approved it. Agents and user-run code with this access can alter local security controls.

## 6. Vanta enrollment and evidence submission

**Verified:** Vanta Device Monitor is registered to the EU region for the assigned user; osquery responds and the Vanta extension is registered. Registration and doctor checks succeeded, including communication with Vanta servers. Device identity: `7cf9de00-474d-11f1-8dbe-013b1bbd2101`.

Vanta documents that its Linux Device Monitor checks disk encryption, but does not detect Linux antivirus, screen lock or password managers. Agent health is not a compliance verdict. NixOS is outside the vendor's stated Ubuntu/Debian supported operating systems; the official Linux binaries are deployed declaratively and their observed functionality is recorded here.

Vanta's manual-evidence guidance supports custom documents and common evidence such as screenshots. Suggested mappings include **Anti-malware technology utilized**, **Portable media encrypted**, and **Password policy enforced**, subject to Ablo's actual control definitions. The report does not claim that uploading it automatically passes Vanta tests or that a document replaces an MDM where Ablo requires one.

## Outstanding validation and policy decisions

- Continue observing on-access queue behavior under normal development workloads; a short check cannot establish long-term performance.
- Record a completed baseline malware scan and assess any errors or detections.
- Retest simultaneous fingerprint-reader use with 1Password and confirm a real 1Password token save after the Secret Service repair.
- Verify the intended SSH authentication setting after activation.
- Retrieve Ablo's security policy and compare endpoint, anti-malware, patching, privileged-access and incident-response requirements.
- Confirm company password-manager use and any required management approval; keep unsupported claims out of the final evidence.

## References

1. Vanta, *Troubleshooting the Vanta Device Monitor on Linux Machines*: https://help.vanta.com/en/articles/11346064-troubleshooting-the-vanta-device-monitor-on-linux-machines
2. Vanta, *Antivirus Solutions Detected by Vanta*: https://help.vanta.com/en/articles/11346109-antivirus-solutions-detected-by-vanta (ClamAV appears in the Windows detection list; that is not an approved Linux product list.)
3. Vanta, *Evidence Collection for Unmonitored Laptops*: https://help.vanta.com/en/articles/11345596-evidence-collection-for-unmonitored-laptops
4. ClamAV configuration reference: https://github.com/Cisco-Talos/clamav/blob/main/docs/man/clamd.conf.5.in
5. Local declarative sources: `hosts/samsung-ablo/{antivirus,screen-lock,fingerprint,disk-encryption,vanta,configuration}.nix` and shared NixOS modules.

Prepared from local configuration, selected command results and dated journal entries. No communication to third parties has been performed.
