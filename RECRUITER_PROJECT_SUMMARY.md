# DevOps Practical Assignment — Project Summary

**Project:** Terraform-automated AWS lab for OWASP Juice Shop, ModSecurity/OWASP CRS, WireGuard, and Wazuh  
**Repository:** [ambika-2109/fynd-practical-assignment](https://github.com/ambika-2109/fynd-practical-assignment)  
**Region configured:** AWS ap-southeast-2 (Sydney)  
**Status:** Infrastructure code, automation, verifier, and CI are implemented. The latest AWS deployment and end-to-end acceptance checks have not been completed or evidenced, so the live lab should not be described as fully verified.

## Assignment expectations and delivery status

| Expected | Implemented | Status / qualification |
|---|---|---|
| One documented Terraform-based command deploys the lab without manual server or Wazuh setup. | `bash ./lab.sh deploy` initializes remote state, generates/reuses local credentials, applies Terraform, connects WireGuard, and runs the verifier. Cloud-init bootstraps both VMs and services. | **Implemented; current AWS run pending.** AWS credentials, eligible instance capacity, and local macOS WireGuard/sudo access are prerequisites. |
| Run Juice Shop on Kubernetes where practical; Docker on a VM is accepted. | Juice Shop v17.1.1 runs in Docker Compose on the app VM. Its container port is not published; requests pass through the WAF. | **Implemented using the explicitly accepted Docker option.** K3s was not selected to keep the short-lived lab smaller and simpler. |
| Run Wazuh server, Indexer, dashboard, agent enrollment and app/ingress log collection on a separate VM; persist data. | Wazuh Docker single-node stack (pinned to v4.12.0) is provisioned on a second VM. Bootstrap configures credentials, agent enrollment, Docker JSON log collection, and a custom marker alert rule. Wazuh data is held in Docker volumes on an encrypted 80 GiB root disk. | **Automation implemented; runtime not verified.** Normal reruns preserve the instance/volumes, but replacing the Wazuh VM deletes its root disk and data unless it is snapshotted. |
| Provide private access for Wazuh and administration. | WireGuard gateway on the app VM routes the operator into the VPC; Wazuh services are security-group restricted to the gateway. SSM is enabled for host administration; no public SSH rule is configured. | **Configured; tunnel not yet evidenced.** Local macOS requires WireGuard tools and permission to create the interface. |
| Put Juice Shop behind a WAF; demonstrate allowed and deterministic blocked traffic; prevent origin bypass. | ModSecurity with OWASP CRS is the reverse proxy. A custom rule blocks `lab_block=1` with HTTP 403. The app is reachable through VPN/private routing, and the origin's HTTP security-group ingress is restricted to the app security group. | **Implemented; live request results pending.** The verifier checks a normal request and expects the explicit test request to return 403. |
| Restrict network access and identities; protect secrets/state; document TLS. | Terraform defines a VPC, subnet, routing, security groups, EC2 role/profile, SecureString parameters, encrypted EBS, IMDSv2, and encrypted/versioned S3 state with native lock files. Generated secrets/state are git-ignored. | **Implemented for a disposable lab, not production.** Both VMs currently share an instance role that can read all three lab parameters; this should be split into per-instance least-privilege roles before production reuse. |
| Verify readiness, a unique request marker, and marker search in Wazuh; fail on errors/timeouts. | Python verifier waits for app and authenticated Indexer readiness, sends a UUID marker request, checks allowed and blocked responses, and polls the Indexer API for the matching Wazuh alert. It has bounded waits and nonzero failure exits. | **Code and unit tests implemented; end-to-end result pending.** |
| CI validates Terraform, tests verifier, scans IaC/source and secrets; deploy is gated and controlled. | GitHub Actions runs Terraform format/validation, Python unit tests, Trivy IaC/source scanning, and Gitleaks. A separate manual deployment workflow gates deployment on these checks and is designed for OIDC, a protected environment, and a dedicated Mac runner. | **Workflows implemented.** A prior CI run is recorded as passing in the checklist. GitHub OIDC role/environment protections and runner registration are still pending; GitHub deployment is optional if deploying locally. |
| Estimate short-run cloud cost, record actual effort, and tear down after testing. | The resource inventory and teardown command are documented. | **Not yet complete.** No verified Sydney estimate, actual billing total, measured focused-work time, or teardown evidence is recorded. See Cost and effort below. |

## What I built

- **Terraform infrastructure:** provisions the VPC, public subnet and route, security groups, two Ubuntu EC2 instances, IAM instance profile, Systems Manager SecureString parameters, encrypted disks, and outputs used by the VPN/verifier. Provider and Wazuh versions are pinned/configured in the Terraform files.
- **Application and WAF bootstrap:** installs WireGuard, Docker, Juice Shop, ModSecurity/OWASP CRS, and the Wazuh agent; configures VPN forwarding/NAT, a deterministic block rule, and Docker JSON log collection.
- **Wazuh bootstrap:** deploys the official Wazuh Docker single-node stack, configures passwords and the custom marker rule, and waits for agent enrollment readiness.
- **Lifecycle automation:** [lab.sh](lab.sh) provides `deploy`, `verify`, and `destroy` modes. Existing generated credentials are reused to keep reruns aligned with the deployed services. Destroy removes lab infrastructure but deliberately retains the remote state bucket.
- **Verification and tests:** [scripts/verify_lab.py](scripts/verify_lab.py) enforces application/Indexer readiness, an allowed request, HTTP 403 for the deterministic WAF test, and searchability of a fresh marker in Wazuh. [tests/test_verify_lab.py](tests/test_verify_lab.py) tests marker generation, URL construction, and event matching.
- **Security and operations documentation:** [README.md](README.md) documents prerequisites, architecture, controls, deployment, verification, teardown, TLS caveats, evidence, and limitations. [CHANGES_AND_OWNER_CHECKLIST.md](CHANGES_AND_OWNER_CHECKLIST.md) records implementation history and remaining owner actions.

## Cloud components and design choices

| Component | Purpose / configured footprint |
|---|---|
| Amazon VPC, subnet, internet gateway, route table | Isolated `10.42.0.0/16` lab network; controlled outbound access for bootstrap downloads. |
| EC2 app/VPN VM | Default `t3.small`, Ubuntu, 30 GiB encrypted gp3 root disk; WireGuard, Docker, Juice Shop, ModSecurity/CRS, and Wazuh agent. |
| EC2 Wazuh VM | Configured default `m7i-flex.large` (2 vCPU/8 GiB), Ubuntu, 80 GiB encrypted gp3 root disk; Wazuh manager, Indexer, and dashboard in Docker. |
| Security groups | VPN UDP 51820 limited to the operator IPv4 CIDR; app HTTP is private to the gateway path; Wazuh service ports accept traffic from the gateway security group. Egress is limited to required HTTP/HTTPS, DNS, and lab service paths. |
| IAM / Systems Manager | EC2 instance profile supports SSM administration and retrieval of lab SecureString values. No public SSH ingress is configured. |
| S3 Terraform backend | Runtime-selected bucket and region, encryption, versioning, public access blocks, TLS-only policy when the script creates the bucket, and S3 native lock files. Terraform state contains sensitive values and must remain protected. |
| GitHub Actions (optional deployment) | Linux-hosted checks; manual deployment workflow uses GitHub OIDC and a protected environment, then a dedicated Apple Silicon Mac runner for local WireGuard interface management. This setup is not yet fully configured. |

**TLS note:** Wazuh's lab deployment generates self-signed certificates. The verifier disables certificate validation for its private Indexer connection; traffic remains inside WireGuard. The app/WAF HTTP hop is also private to the VPN path. These choices are documented for a disposable assessment lab and are not production TLS practices.

## Cost and effort

### Costing status

A reliable dollar figure is **not available yet**. The README explicitly says the earlier estimate was for a different region and must not be reused for Sydney. I have not completed a current AWS Pricing Calculator estimate or captured actual billing for this run, so I am not presenting an invented amount as an estimate or actual cost.

The cost estimate must use ap-southeast-2 pricing and account for:

- Two instances and their running hours: app `t3.small` and planned Wazuh `m7i-flex.large`.
- 110 GiB total gp3 root storage (30 GiB app + 80 GiB Wazuh), prorated for the run duration.
- Two public IPv4 addresses while allocated, outbound data transfer, and small S3 state storage/requests/version history.
- Any applicable trial/free-plan credits, verified against this AWS account and its eligibility; credits should not be assumed.

The Wazuh type is an attempted cost-conscious compromise: `m7i-flex.large` has 2 vCPU/8 GiB and is listed as Free Plan eligible only for qualifying accounts created on/after July 15, 2025. Its account eligibility and quota are unconfirmed, and 2 vCPU is below Wazuh's 4-vCPU starting recommendation. A previous attempt to resize to `t3.xlarge` was rejected under the account's Free plan restriction. Before quoting a total, calculate the short-run duration in the AWS Pricing Calculator and confirm actual usage in billing after the run; the lab should be destroyed after evidence capture to limit continued compute/IP charges. The versioned state bucket is intentionally retained and can continue to incur small storage charges.

### Effort

The assignment timebox was 1–2 hours of focused work. **My actual focused time was not measured**, so this document does not claim a measured duration or assert that all implementation/testing fit within the timebox. Record the actual elapsed focused time before submission/interview.

## AI use

AI assistance was used to draft and refine Terraform, cloud-init/bootstrap scripts, the Python verifier and its unit tests, GitHub Actions workflows, and project documentation. I reviewed and integrated the generated material and used the repository's formatting, validation, unit-test, and CI checks where recorded. AI assistance does not substitute for the pending live AWS deployment, review of account-specific permissions/costs, or the remaining end-to-end evidence.

## Limitations and why they remain

1. **No current end-to-end proof:** the source patch has not been applied to AWS. The VPN, WAF behavior, fresh Wazuh alert delivery, direct-origin rejection, and final verifier success remain unverified. The deployment intentionally reports success only if the verifier passes; running `terraform apply` alone is insufficient. The local VPN step also requires macOS WireGuard permissions and `sudo`.
2. **Instance eligibility and sizing:** the account rejected a prior larger Wazuh resize under its Free plan restriction. The configured `m7i-flex.large` is not yet applied or confirmed eligible/quota-approved; even if available, it is below the Wazuh 4-vCPU starting recommendation. The existing AWS instance may still be `t3.small`. This is a cost/account-capacity tradeoff, not a claim that the recommended Wazuh size has been met.
3. **GitHub deployment setup:** IAM OIDC provider/role, protected `lab-deploy` environment settings/reviewer, and the dedicated self-hosted Mac runner are pending. The deployment workflow is present, but a local deployment is an alternative and GitHub Actions deployment must not be claimed as run.
4. **Lab-only identity scope:** both instances share a role capable of reading all lab SecureString parameters. This simplifies a disposable lab but violates the desired production separation; split the permissions before production use.
5. **Data on replacement:** Wazuh data persists across normal reruns on its encrypted root disk, but Terraform instance replacement deletes that disk/volumes unless backed up or snapshotted.
6. **Open deliverables:** redacted VPN/WAF/Wazuh evidence, numeric regional cost estimate, actual billing cost, measured effort, and confirmed teardown are still outstanding.

## Completion checklist before representing the lab as fully delivered

- Confirm AWS credentials, S3 backend access, `m7i-flex.large` eligibility/quota, and review a fresh Terraform plan.
- Run the documented deploy command on the Mac and reach `DEPLOYMENT VERIFIED`.
- Save redacted evidence of active WireGuard, allowed traffic, deterministic HTTP 403, fresh marker and matching Wazuh event; verify the public app origin cannot bypass the WAF.
- Calculate the short-run Sydney estimate and record actual billing/effort and outcomes in the README.
- Run the documented destroy command after evidence capture and confirm lab compute/network resources are removed. Retain or remove the state bucket only after considering state history.

## Useful repository references

- Deployment, verification, and teardown: [README.md](README.md)
- Current status and owner checklist: [CHANGES_AND_OWNER_CHECKLIST.md](CHANGES_AND_OWNER_CHECKLIST.md)
- Terraform infrastructure: [terraform/main.tf](terraform/main.tf)
- App bootstrap: [terraform/app-bootstrap.sh.tftpl](terraform/app-bootstrap.sh.tftpl)
- Wazuh bootstrap: [terraform/wazuh-bootstrap.sh.tftpl](terraform/wazuh-bootstrap.sh.tftpl)
- End-to-end verifier: [scripts/verify_lab.py](scripts/verify_lab.py)
- CI and protected deployment workflows: [.github/workflows/ci.yml](.github/workflows/ci.yml), [.github/workflows/deploy.yml](.github/workflows/deploy.yml)