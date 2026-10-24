# Terraform WAF + Wazuh practical lab

[![CI](https://github.com/ambika-2109/fynd-practical-assignment/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ambika-2109/fynd-practical-assignment/actions/workflows/ci.yml)

An AWS-based, two-VM lab provisioned by Terraform. It is designed for a short assessment run and is **not a production deployment**. The deployment command returns success only after the VPN is connected, the application and Indexer are ready, the WAF allows a normal request and blocks a deterministic test, and the fresh request marker is searchable in Wazuh.

## Prerequisites

- AWS account/eligible trial credit and credentials configured with AWS CLI (`aws configure` or environment credentials).
- Terraform 1.10+, AWS CLI v2, WireGuard tools (`wg`, `wg-quick`, and `wireguard-go` on macOS), `curl`, `openssl`, and Python 3.10+.
- IAM permissions to create the listed EC2/VPC/IGW/route/security-group/IAM instance-profile resources, and S3 access to the Terraform state bucket. The script can create/configure its default bucket, or use a dedicated bucket provisioned by an administrator with `TF_STATE_BUCKET`. Do not use root credentials.
- On macOS, install WireGuard tools and allow `sudo` to create the VPN interface. The generated peer file is also importable in the WireGuard GUI.
- An internet connection from both VMs for package/image downloads. The lab creates two public IPv4 addresses; only the VPN listener is reachable from the internet.

## Deploy, verify, tear down

Credentials must already be available to AWS CLI. The script detects your current public IPv4 address and restricts the WireGuard listener to that `/32`. If your egress IP is different, set `OPERATOR_IP_CIDR` (for example `203.0.113.7/32`); choose a short unique `LAB_NAME_PREFIX` if the default name is already in use. Region defaults to `ap-southeast-2` (Sydney) and can be changed with `AWS_REGION`.

```sh
AWS_REGION=ap-southeast-2 TF_STATE_BUCKET=fynd-lab-tfstate-328064416305-ap-southeast-2 bash ./lab.sh deploy
```

The supplied state bucket is in Sydney. With `TF_STATE_BUCKET` set, the script checks that it exists and skips bucket creation/configuration; the administrator must ensure it is dedicated, encrypted, versioned, and has Block Public Access enabled. The configured identity needs access to the bucket and Terraform state key, including S3 lock-file operations. The backend bucket and region are supplied at runtime, and the backend key is fixed in `terraform/backend.tf`. The script selects the provisioned S3 backend without migrating a local state over it. If the remote key is absent or does not represent this lab, stop and reconcile state before deploying. The deploy command also generates local WireGuard/Wazuh credentials under `.secrets/`, initializes remote Terraform state, provisions the lab, brings up the VPN using `sudo`, and runs the end-to-end verifier. `sudo` may prompt for the local account password. Re-running deploy applies in place, reuses the same generated secrets and remote state, and preserves the Wazuh Docker volumes.

```sh
AWS_REGION=ap-southeast-2 TF_STATE_BUCKET=fynd-lab-tfstate-328064416305-ap-southeast-2 bash ./lab.sh verify
AWS_REGION=ap-southeast-2 TF_STATE_BUCKET=fynd-lab-tfstate-328064416305-ap-southeast-2 bash ./lab.sh destroy
```

`verify` reruns the checks on an existing lab. `destroy` first disconnects the local VPN and deletes the two VMs and lab network. It intentionally retains the encrypted/versioned state bucket so state history and recovery remain available; delete the bucket later only after confirming no deployment state is needed. Cloud-init installs Docker and starts the application, WAF, Wazuh stack and agent automatically—no VM login or console setup is required.

## Architecture and controls

```text
Operator ── WireGuard/UDP 51820 (operator /32 only) ──> App VM (Ubuntu)
                                                        ├─ ModSecurity + OWASP CRS reverse proxy :80
                                                        ├─ custom deterministic lab_block=1 → 403 rule
                                                        ├─ Juice Shop (container-only port 3000)
                                                        ├─ Wazuh agent (Docker JSON access logs)
                                                        └─ VPN forwarding/NAT to VPC 10.42.0.0/16
                                                              │
                                                              └── Wazuh VM (Ubuntu, private SG access)
                                                                  ├─ Wazuh manager + enrollment
                                                                  ├─ Wazuh Indexer :9200
                                                                  └─ Wazuh dashboard :443
```

- Juice Shop is behind the ModSecurity/CRS Nginx container; its port is not published. The host's port 80 accepts only traffic from the app security group, so the public address cannot bypass the WAF. Access traverses the VPN and is source-NATed by the gateway.
- Wazuh dashboard, Indexer, and enrollment/event ports are security-group restricted to the VPN gateway security group. No inbound SSH is exposed publicly; use AWS Systems Manager Session Manager for host administration. EC2 uses IMDSv2 and an instance profile limited to the AWS-managed SSM core policy plus read access to the three lab-specific SecureString parameters.
- EBS root disks are encrypted; the Wazuh all-in-one Docker deployment stores its manager/indexer/dashboard data in persistent Docker volumes on an 80 GiB disk. Normal reruns do not replace the Wazuh instance or its volumes.
- Terraform state is remote in an automatically bootstrapped S3 bucket with server-side encryption, versioning, public-access blocks, a TLS-only bucket policy, and native S3 lock files. Secrets are passed to the instances at boot through AWS Systems Manager SecureString parameters and fetched with their instance role; Terraform state contains secret values and is protected by the encrypted backend. The locally generated secrets directory and state are excluded by `.gitignore`; never commit `.secrets/`, Terraform state, plans, or credentials.
- Wazuh dashboard and Indexer use the official deployment's generated self-signed TLS certificates. The verifier currently disables certificate verification for the private lab Indexer connection; the client connection remains encrypted inside WireGuard. The Juice Shop/WAF HTTP hop is also carried only inside the encrypted VPN. This certificate arrangement is for a disposable private lab, not production.

## WAF and log-delivery evidence

The verifier makes a normal request with a newly generated `fyndlab-<uuid>` query marker (expected 2xx/3xx), then requests `?lab_block=1` (expected HTTP 403). The custom ModSecurity rule is deterministic and independent of CRS anomaly scoring. Docker's JSON logs are collected by the enrolled Wazuh agent; a local Wazuh rule turns `lab_marker=` events into alerts, and the verifier polls `wazuh-alerts-*` through the authenticated Indexer API. Readiness and delivery waits are bounded; any failed condition exits nonzero.

For assessment evidence, capture and redact:

1. A successful tunnel status (`sudo wg show`) and an application request through the VPN.
2. A normal request response and the `?lab_block=1` response showing HTTP 403.
3. The verifier's final `Verified marker: ...` line and the matching Wazuh alert in the dashboard/Indexer.

Do not include private keys, generated passwords, authorization headers, AWS credentials, or Terraform state in evidence.

## CI/CD

`.github/workflows/ci.yml` runs Terraform formatting/validation, verifier unit tests, Trivy filesystem IaC/source checks, and Gitleaks. Deployment is limited to `workflow_dispatch` on `main`, waits for checks, uses a protected GitHub environment named `lab-deploy`, and serializes deploys. It uses GitHub OIDC to obtain short-lived AWS credentials; it does not read AWS access keys from GitHub Secrets.

To enable OIDC, an AWS administrator must configure the IAM OIDC provider `https://token.actions.githubusercontent.com`, create a dedicated role with a reviewed least-privilege permissions policy for this lab, and set the GitHub environment variable `AWS_ROLE_ARN`. The role trust should require audience `sts.amazonaws.com` and this repository's `lab-deploy` environment subject. This repository was created after GitHub's immutable subject claim rollout, so its default subject is:

```text
repo:ambika-2109@59207745/fynd-practical-assignment@1432098598:environment:lab-deploy
```

Example trust relationship for AWS account `328064416305`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::328064416305:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:ambika-2109@59207745/fynd-practical-assignment@1432098598:environment:lab-deploy"
      }
    }
  }]
}
```

In GitHub, configure `AWS_ROLE_ARN`, `TF_STATE_BUCKET`, `AWS_REGION`, and `OPERATOR_IP_CIDR` in `lab-deploy`; restrict its deployment branches to `main` and require an approval reviewer. The trust policy scopes which repository environment can assume the role; the environment branch rule further restricts which branch may use it. Give the AWS role only the permissions needed to manage this lab and state bucket; do not attach `AdministratorAccess`. After OIDC authentication succeeds, remove any old `LAB_AWS_ACCESS_KEY_ID` and `LAB_AWS_SECRET_ACCESS_KEY` environment secrets and deactivate/delete their IAM access keys.

The deploy job requires a trusted self-hosted Apple Silicon Mac runner labeled `lab-vpn`, with the default `self-hosted`, `macOS`, and `ARM64` labels, Terraform, AWS CLI, WireGuard tools (`wg`, `wg-quick`, and `wireguard-go`), and non-interactive sudo permission to manage a WireGuard interface. Download the macOS ARM64 runner package shown by GitHub, not the Linux x64 package. Keep this runner dedicated to trusted workflows because it receives temporary AWS credentials and can manage the local VPN interface. See [GitHub's AWS OIDC guide](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [GitHub's OIDC subject claim reference](https://docs.github.com/en/actions/reference/security/oidc), and [AWS IAM's GitHub OIDC guidance](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html).

Juice Shop is intentionally vulnerable and is not scanned as a built image. Trivy and Gitleaks checks remain enabled for the candidate repository and IaC.

## Estimated cost and effort

The previous cost estimate was for `us-east-1` and does not apply to this Sydney deployment. Recalculate with the AWS Pricing Calculator for `ap-southeast-2` before submission, including the two `t3.small` VMs, 110 GiB of gp3 disks, two public IPv4 addresses, data transfer, and S3 state storage. The Wazuh VM is currently `t3.small` because this account's Free plan rejected an upgrade to `t3.xlarge`; this is below Wazuh's 4-vCPU/8-GiB starting recommendation and may limit reliability. Record actual usage from billing after the run. Pricing and trial eligibility vary by region and account; see [AWS EC2 pricing](https://aws.amazon.com/ec2/pricing/), [EBS pricing](https://aws.amazon.com/ebs/pricing/), and [public IPv4 pricing](https://aws.amazon.com/blogs/aws/new-aws-public-ipv4-address-charge-public-ip-insights/). Keep instances stopped or destroy the lab after testing.

- Actual focused implementation effort: not measured in this authoring session; record the submitter's elapsed time before submission.
- AI use: AI assistance generated the Terraform, bootstrap scripts, verifier, tests, workflow, and documentation; review and test all resources and provider/image versions before use.
- Incomplete/unverified: the AWS resources exist in `ap-southeast-2`, but the deploy script has not completed end-to-end verification because local macOS sudo is required to bring up WireGuard. The Wazuh VM remains at `t3.small`, below the upstream starting recommendation, due to the AWS Free plan restriction. VPN access, WAF outcomes, fresh Wazuh event delivery, actual cost, and effort are not yet evidenced. Capture redacted evidence after running `bash ./lab.sh deploy` locally; confirm upstream Wazuh v4.12.0 and container image availability before submission.

## Notes / cleanup

The S3 state bucket is retained by `destroy` intentionally; it is protected, but may incur small storage charges. Delete old state versions and the bucket only after successful teardown and after deciding that recovery/audit history is no longer required. Never remove the backend while Terraform-managed infrastructure still exists.
