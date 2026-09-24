## SEV1 payments runbook (example)

1. Confirm affected merchant and region.
2. Call `payments-incident-playbook__get_incident`.
3. Correlate with Last9 error rate and traces for the same service and time window.
4. Call `payments-incident-playbook__add_comment` with findings.
5. Call `payments-incident-playbook__close_incident` only after a human approves.
