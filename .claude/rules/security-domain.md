# Security Domain Knowledge

Be precise with security and pentest terminology. Incorrect characterizations in security reports can lead to wrong conclusions and wasted effort.

## Common Mistakes to Avoid

- **SMB signing**: Signing *disabled* means the host can be relayed **TO** (it's a target for relay attacks), not relayed **FROM**
- **NTLM vs NTLMv1 vs NTLMv2**: These are distinct. Don't conflate them. NTLMv1 hashes are crackable; NTLMv2 are relay-or-crack
- **Null sessions vs guest access**: Null session = anonymous (no creds). Guest access = server maps failed auth to Guest account. Different attack surfaces
- **CVE descriptions**: Quote the exact CVE description when referencing vulnerabilities. Don't paraphrase in ways that change the severity or attack vector

When uncertain about security-specific terminology or attack semantics, ask rather than guess.
