FYND DEVOPS PRACTICAL ASSIGNMENT
CHANGES SUMMARY, STATUS, AND OWNER CHECKLIST
============================================

STATUS SNAPSHOT
---------------
Updated: 2026-10-25
Repository: ambika-2109/fynd-practical-assignment, branch main
Current branch: main (see GitHub for latest commit SHA)
AWS region: ap-southeast-2 (Sydney)
Terraform state bucket: fynd-lab-tfstate-328064416305-ap-southeast-2

The supplied source patch is applied locally. Check GitHub Actions for the latest CI result. The deployment workflow now
uses OIDC, is limited to workflow_dispatch on main, and targets the owner's
Apple Silicon Mac runner. AWS OIDC role setup, GitHub environment protections,
and runner registration remain pending. The patch has NOT been applied in AWS.
AWS infrastructure was previously observed with Wazuh at t3.small. End-to-end
VPN/verifier checks, evidence, cost, and teardown are not complete.

COMPLETED WORK
--------------
[x] Configured the S3 Terraform backend to accept the bucket and region at init.
[x] Selected the owner-provided, pre-existing Sydney state bucket. Remote state
    was checked against the existing local lab state before reconfiguration.
[x] Updated defaults and instructions to use ap-southeast-2.
[x] Restricted public subnet auto-assigned public IPs and tightened the app and
    Wazuh security-group egress to the lab's required destinations/ports.
[x] Added dated, resource-scoped Trivy suppressions with rationale for required
    dynamic upstream package/container downloads.
[x] An attempted resize from t3.small to t3.xlarge was rejected by the account's
    Free plan restriction; the instance was restarted and observed at t3.small.
[x] Patch changes the Wazuh code default to m7i-flex.large (2 vCPU/8 GiB). AWS
    lists it as Free plan eligible only for accounts created on or after
    2025-07-15. The family is offered in Sydney, but this account's eligibility
    and quota are unverified. It remains below Wazuh's 4-vCPU recommendation.
[ ] Confirm account eligibility and review a fresh Terraform plan. No plan or
    apply has been run; AWS may still be running t3.small.
[x] Earlier revision passed Terraform formatting/validation, verifier unit
    tests, shell syntax/whitespace, and secret/IaC scans.
[x] Pushed commit 7db6bf2 to main. GitHub CI run 40101133282 passed Terraform,
    verifier, Trivy, and Gitleaks checks. Its protected deployment job was
    skipped; no GitHub Actions deployment was performed.
[x] Confirmed generated secrets and Terraform state were excluded from Git.
[x] Removed the incomplete self-hosted runner package/extraction from the repo
    directory and added ignore rules for credentials, state, runner artifacts,
    and local editor settings.
[x] Updated the deployment workflow to use job-scoped GitHub OIDC, run only for
    manual dispatches from main, and serialize deployments instead of using
    long-lived AWS access-key secrets.
[x] Applied the supplied patch's bootstrap changes: AWS CLI v2 installation,
    Wazuh 4.12.0 and agent version pinning, enrollment wait, password setup, and
    custom-rule mount. Bootstrap changes are ignored for existing instances to
    prevent automatic replacement.
[x] Kept the newer OIDC workflow and security changes. The supplied ZIP is an
    older full-repository snapshot with static AWS key references, so it was not
    used.

FILES ADDED OR CHANGED
----------------------
1. terraform/versions.tf
   Pins the supported Terraform/provider configuration and configures the AWS
   provider, region, and standard tags.

2. terraform/backend.tf
   Configures encrypted S3 remote state with native S3 lock files. Bucket name
   and region are supplied during initialization by lab.sh.

3. terraform/variables.tf
   Declares AWS region, resource prefix, operator CIDR, generated WireGuard keys,
   Wazuh passwords, and EC2 sizes. Secret inputs are marked sensitive. The
   Wazuh default is m7i-flex.large per the supplied patch; Free Plan eligibility
   and quota depend on the account and remain unverified.

4. terraform/main.tf
   Provisions VPC, subnet, internet gateway/routes, security groups, Ubuntu EC2
   instances, encrypted disks, SSM role/profile, SecureString parameters, and a
   restricted parameter-read policy. App/VPN and Wazuh are separate VMs; only
   the VPN endpoint is intended to accept public inbound traffic.

5. terraform/outputs.tf
   Exposes addresses required by the local VPN connection and verifier.

6. terraform/app-bootstrap.sh.tftpl
   Installs WireGuard, Docker, ModSecurity/OWASP CRS, Juice Shop, the Wazuh
   agent, and Docker JSON log collection. A deterministic ModSecurity rule
   blocks lab_block=1 with HTTP 403; the Juice Shop container port is not
   published directly.

7. terraform/wazuh-bootstrap.sh.tftpl
   Installs the Wazuh Docker single-node deployment, configures credentials and
   a lab marker alert rule, and stores Docker volumes on the encrypted disk.

8. lab.sh
   Implements deploy, verify, and destroy; uses the configured remote state,
   generates local WireGuard/Wazuh credentials, runs Terraform, establishes the
   local VPN, and invokes the verifier. Destroy removes lab infrastructure but
   intentionally retains the state bucket.

9. scripts/verify_lab.py and tests/test_verify_lab.py
   Verify readiness, an allowed app request, a deterministic blocked request,
   and delivery/searchability of a fresh unique marker in Wazuh. Unit tests
   cover marker generation, URL construction, and event matching.

10. .github/workflows/ci.yml
    Runs Terraform format/validation, verifier tests, Trivy, and Gitleaks on
    pull requests and pushes to main. It has no deployment job, so routine CI
    runs do not show an intentional deployment skip.

11. .github/workflows/deploy.yml
    Manual protected deployment workflow. It repeats the checks, gates the
    deploy job on their success, and requires the protected environment and
    trusted self-hosted Apple Silicon Mac VPN-capable runner.

12. README.md and .gitignore
    Document usage, architecture, controls, costs, limitations, evidence, and
    CI setup; ignore Terraform state/plans and generated credentials.

OWNER CHECKLIST — REMAINING BEFORE SUBMISSION
---------------------------------------------

A. Local end-to-end deployment verification
[ ] From the repository directory on the owner's Mac, run:

    eval "$(/opt/homebrew/bin/brew shellenv)"
    AWS_REGION=ap-southeast-2 \
    TF_STATE_BUCKET=fynd-lab-tfstate-328064416305-ap-southeast-2 \
    bash ./lab.sh deploy

[ ] Enter the Mac sudo password only in the local terminal if WireGuard prompts.
    Do not send the password through chat or add it to repository files.
[ ] Wait for the final DEPLOYMENT VERIFIED message. A successful Terraform apply
    alone does not count as end-to-end verification.
[ ] If deployment fails, capture the error (redacting secrets) and inspect
    bootstrap/service logs through AWS Systems Manager Session Manager; do not
    expose public SSH to troubleshoot.
[ ] Confirm `sudo wg show` reports the tunnel active.
[ ] Confirm the normal Juice Shop request is allowed and `?lab_block=1` returns
    HTTP 403 through the VPN.
[ ] Confirm a fresh unique verifier marker is searchable in Wazuh and record
    both the marker and matching event (redacted).
[ ] Check that direct public HTTP/HTTPS access to the app origin is rejected and
    UDP 51820 is limited to the intended operator CIDR.
[ ] Record the date, command outcome, and any failures in README.md.

B. Evidence and submission details
[ ] Save redacted evidence of: active VPN; allowed WAF request; blocked request
    with HTTP 403; and the fresh marker in Wazuh.
[ ] Record actual effort/time spent; it was not measured during implementation.
[ ] Record actual AWS usage/cost for this run from billing. The README does not
    contain a verified Sydney cost. Include app t3.small, Wazuh m7i-flex.large,
    110 GiB gp3,
    two public IPv4 addresses, transfer, and S3 state storage in any estimate.
[ ] Update README.md with actual outcomes, effort, cost, and remaining issues.
[x] Code changes are pushed to the public repository at
    https://github.com/ambika-2109/fynd-practical-assignment. GitHub CI passed.
[ ] Configure an AWS IAM OIDC provider and a dedicated least-privilege role
    using the trust subject and example in README.md. Set AWS_ROLE_ARN in the
    GitHub lab-deploy environment. Do not attach AdministratorAccess.
[ ] To deploy from GitHub after setup, open Actions, choose “Protected lab
    deployment,” select “Run workflow” on main, and start it. The dedicated
    workflow runs its checks first and starts deployment only if they pass.
[ ] In GitHub, restrict lab-deploy deployments to main and require an approval
    reviewer. Once OIDC works, remove old static access-key environment secrets
    and deactivate/delete their IAM access keys.
[ ] For GitHub deployment, configure AWS_REGION, TF_STATE_BUCKET,
    OPERATOR_IP_CIDR, and a trusted isolated self-hosted Apple
    Silicon Mac runner labeled self-hosted, macOS, ARM64, and lab-vpn. Install
    Terraform, AWS CLI, WireGuard tools (wg, wg-quick, wireguard-go), curl,
    OpenSSL, and Python 3; configure
    non-interactive sudo for WireGuard. The workflow now targets this Mac runner;
    the runner still must be registered and online. Local deployment is an
    alternative.
[ ] Before any final commit, confirm `git status` has no .secrets/, Terraform
    state/plans, AWS credentials, WireGuard private key, or passwords staged.
[ ] Before production reuse, split the shared EC2 instance profile: app should
    read only the WireGuard server key; Wazuh should read only its own passwords.

C. Teardown after collecting evidence
[ ] When finished, run:

    AWS_REGION=ap-southeast-2 \
    TF_STATE_BUCKET=fynd-lab-tfstate-328064416305-ap-southeast-2 \
    bash ./lab.sh destroy

[ ] Confirm the EC2 instances and lab networking are gone in AWS.
[ ] The S3 state bucket is intentionally retained. Delete it only after
    confirming infrastructure is destroyed and deciding state history is no
    longer needed; remove object versions before deleting a versioned bucket.
[ ] Remove local .secrets/ only after no further verify/destroy operation is
    needed. Keep credentials, private keys, passwords, and Terraform state out
    of source control and evidence.

KNOWN LIMITATIONS / NOT YET VERIFIED
------------------------------------
- End-to-end local VPN, WAF, and Wazuh event verification remains pending; local
  macOS sudo is required to create the WireGuard interface.
- The patch sets the Wazuh default to m7i-flex.large, but no AWS apply has
  occurred; the instance may still be t3.small. m7i-flex.large has 2 vCPU/8 GiB,
  so it meets the memory recommendation but remains below Wazuh's 4-vCPU
  recommendation. Eligibility and quota in this account are not confirmed.
- Both EC2 instances still share one instance profile that can read all three
  lab SSM parameters. Separate profiles/policies before production use.
- No screenshots/evidence, measured effort, or actual billing cost have been
  recorded yet.
- The prior combined CI workflow showed its deployment job as skipped on normal
    push events by design. CI and manual deployment have now been separated into
    ci.yml and deploy.yml; confirm the updated checks and use Actions → Protected
    lab deployment → Run workflow for a deployment. Protected environment/runner
    configuration is not confirmed and is optional when using local deployment.
- The state bucket is retained and may incur small storage charges. The EC2
  instances and public IPs may continue incurring charges until teardown.
- The dashboard uses generated self-signed certificates; that arrangement is
  only suitable for this private disposable lab, not production.
-----------------------
# The assignment in plain words

## The big picture

They want to see whether you can build a small, secure, monitored system **entirely with code**, so that anyone can type one command and get the same result. Nothing should be clicked in a console or set up by hand.

Think of a small office building with a locked front door:
- **A shop** that is deliberately full of security holes (Juice Shop).
- **A security guard** standing in front of the shop (the WAF).
- **A VPN tunnel**, so only you can reach the building.
- **A security camera room** that records everything (Wazuh).
- **A test** that proves the guard blocks bad visitors and the cameras recorded the visit (the verifier).
- **An automated checker** that inspects your blueprints before building anything (CI/CD).

## What is given

- A checklist of 7 things to build.
- A time budget (1 to 2 hours) and permission to use AI and existing modules.
- A cost limit: two small VMs and free tools, using trial credits.
- Suggested tools, which you may swap for others.

## What is expected, piece by piece

**1. Terraform and one command.** Terraform is a tool where you describe infrastructure in text files ("I want 2 servers, this network, these firewall rules") and it creates them. "One command" means a reviewer runs something like `./lab.sh deploy` and the whole lab appears.

**2. Application: OWASP Juice Shop.** This is a web shop built to be hacked, used for practice. You run it on Kubernetes (K3s is a light version) or just in Docker. Docker is accepted.

**3. Wazuh on a separate VM.** Wazuh is a free security monitoring system with three parts:
- **Manager** receives and analyses events.
- **Indexer** is the searchable database (the "camera recordings").
- **Dashboard** is the web UI.

On the app VM you also install a Wazuh **agent**. It reads the app's logs and sends them to the manager ("enrollment" means registering the agent with the manager). "Persist data" means the recordings survive restarts and reruns.

**4. VPN.** WireGuard creates an encrypted private tunnel from your laptop into the cloud network. Wazuh and the app are reachable only through it, not from the open internet.

**5. WAF (Web Application Firewall).** It sits between visitors and Juice Shop and inspects each request. You must show:
- one **normal** request that passes (HTTP 200);
- one **attack** request that is always blocked (HTTP 403). "Deterministic" means it blocks every time, not by chance.

"No direct-origin bypass" means you must not be able to skip the guard and talk to Juice Shop directly. Juice Shop's port must be private.

**6. Cloud security.**
- Open only the firewall ports you need.
- Give each server only the permissions it needs (least privilege).
- Never commit passwords, keys or Terraform **state** (the file recording what Terraform built, which may contain secrets). Keep state in a locked, encrypted bucket.
- Document **TLS** (encryption in transit): where traffic is encrypted, where it isn't, and why.

**7. The verifier.** This is a script that proves it all works end to end:
1. Check everything is ready, with timeouts so it can't hang forever.
2. Send a request containing a new random **marker** (such as `fyndlab-8f3a…`).
3. Ask Wazuh's Indexer API: "did you record this exact marker?"
4. Exit with an error code if anything fails.

It proves the whole chain: request, WAF, app log, agent, manager, indexer. To make Wazuh turn that log line into a searchable alert, you add a small **custom rule** ("if a log contains `lab_marker=`, raise an alert"). The deploy only counts as successful if the verifier passes. Reruns must not wipe Wazuh's data.

**8. CI/CD.** This is an automatic pipeline (GitHub Actions) that runs on every push:
- **Validate** the Terraform and **test** the verifier.
- **Scan** with Trivy (misconfigurations in the infrastructure code) and Gitleaks (accidentally committed secrets).
- **Gate** the deploy job: it only runs if all checks pass, only when triggered by hand, and with protected credentials. OIDC lets GitHub get temporary AWS access without stored keys.
- Don't turn off checks just because Juice Shop is vulnerable. Scanning the app itself is optional.

**9. Cost.** Use trial credits, estimate the cost of a short run (VMs, disks, public IPs), and tear everything down afterwards.

**10. Submission.** Hand in a repo or zip with Terraform, scripts, the CI workflow and a short README. The README needs these sections:
- prerequisites;
- deploy, verify and teardown commands;
- architecture;
- estimated cost;
- actual effort;
- AI use (be honest: AI is allowed, hiding it isn't);
- incomplete items (be honest here too).

It also needs redacted evidence: VPN connected, WAF blocking, and a fresh Wazuh event.

## The flow in one line

`you → VPN → WAF → Juice Shop → logs → Wazuh agent → Wazuh → verifier finds the marker`

## What they are really grading

- **Does it work end to end?** The proof is the evidence. Code that "looks right" but was never run is the biggest risk.
- **Is it secure by design?** Closed ports, private origin, no secrets in git, locked-down state.
- **Is it repeatable?** One command, safe reruns, clean teardown.
- **Are you honest?** Real effort, real cost, real gaps.
- **Can you explain and change it live?** This matters as much as the code. Expect questions like "why this firewall rule?" or "change the blocked payload to SQL injection".

## Key terms to know cold

- **VPC and security group:** your private cloud network and its per-server firewall.
- **IAM role and instance profile:** the permissions a server holds, with no stored passwords.
- **SSM Parameter Store:** AWS's safe place for secrets that servers fetch at boot.
- **Cloud-init and user data:** the startup script a VM runs on first boot.
- **NAT or masquerade:** how VPN traffic reaches other machines in the network through the VPN server.
- **Idempotent:** running it twice gives the same result with no damage.

## Where you are now

Your repo covers almost every item above, but it has never run successfully end to end. I found several bugs that would stop Wazuh starting, and I gave you a patch for them. What's left is to redeploy, collect evidence, write the README sections (effort, cost, AI use), tear everything down, and study your own code. That is the part that matters most for the follow-up call.

I can walk through any one piece in more depth, for example the WAF and VPN flow, or the verifier line by line.
