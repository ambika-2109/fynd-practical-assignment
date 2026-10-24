#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
SECRET_DIR="$ROOT_DIR/.secrets"
WG_CONFIG="$SECRET_DIR/wg-lab.conf"
REGION="${AWS_REGION:-ap-southeast-2}"
PREFIX="${LAB_NAME_PREFIX:-fynd-lab}"
MODE="${1:-deploy}"
CUSTOM_STATE_BUCKET="${TF_STATE_BUCKET:-}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

for command in aws terraform wg curl openssl python3; do need "$command"; done
aws sts get-caller-identity >/dev/null || die "AWS credentials are not configured or lack STS access."
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${CUSTOM_STATE_BUCKET:-fynd-lab-tfstate-${ACCOUNT_ID}-${REGION}}"

ensure_state_bucket() {
  if [[ -n "$CUSTOM_STATE_BUCKET" ]]; then
    aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null \
      || die "TF_STATE_BUCKET '$STATE_BUCKET' must already exist and be accessible. Ask your AWS administrator to provision it."
    printf '%s\n' "$STATE_BUCKET" >"$ROOT_DIR/.lab-state-bucket"
    return
  fi

  if ! aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
    if [[ "$REGION" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION" >/dev/null
    else
      aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION" \
        --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
    fi
  fi

  aws s3api put-public-access-block --bucket "$STATE_BUCKET" --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
  aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-bucket-policy --bucket "$STATE_BUCKET" --policy "$(cat <<POLICY
{"Version":"2012-10-17","Statement":[{"Sid":"DenyInsecureTransport","Effect":"Deny","Principal":"*","Action":"s3:*","Resource":["arn:aws:s3:::$STATE_BUCKET","arn:aws:s3:::$STATE_BUCKET/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}
POLICY
)"
  printf '%s\n' "$STATE_BUCKET" >"$ROOT_DIR/.lab-state-bucket"
}

init_terraform() {
  ensure_state_bucket
  # Use the provisioned remote state; do not overwrite it with a local state copy.
  terraform -chdir="$TF_DIR" init -reconfigure \
    -backend-config="bucket=$STATE_BUCKET" -backend-config="region=$REGION"
}

ensure_secrets() {
  mkdir -p "$SECRET_DIR"
  chmod 0700 "$SECRET_DIR"
  [[ -s "$SECRET_DIR/wg-server.key" ]] || wg genkey >"$SECRET_DIR/wg-server.key"
  [[ -s "$SECRET_DIR/wg-client.key" ]] || wg genkey >"$SECRET_DIR/wg-client.key"
  [[ -s "$SECRET_DIR/wg-server.pub" ]] || wg pubkey <"$SECRET_DIR/wg-server.key" >"$SECRET_DIR/wg-server.pub"
  [[ -s "$SECRET_DIR/wg-client.pub" ]] || wg pubkey <"$SECRET_DIR/wg-client.key" >"$SECRET_DIR/wg-client.pub"
  [[ -s "$SECRET_DIR/indexer-password" ]] || printf 'Aa1!%s\n' "$(openssl rand -hex 20)" >"$SECRET_DIR/indexer-password"
  [[ -s "$SECRET_DIR/wazuh-api-password" ]] || printf 'Aa1!%s\n' "$(openssl rand -hex 20)" >"$SECRET_DIR/wazuh-api-password"
  chmod 0600 "$SECRET_DIR"/*

  export TF_VAR_wireguard_server_private_key="$(cat "$SECRET_DIR/wg-server.key")"
  export TF_VAR_wireguard_client_public_key="$(cat "$SECRET_DIR/wg-client.pub")"
  export TF_VAR_indexer_password="$(cat "$SECRET_DIR/indexer-password")"
  export TF_VAR_wazuh_api_password="$(cat "$SECRET_DIR/wazuh-api-password")"
  export TF_VAR_aws_region="$REGION"
  export TF_VAR_name_prefix="$PREFIX"
  export TF_VAR_operator_ip_cidr="${OPERATOR_IP_CIDR:-$(curl -4 -fsS https://checkip.amazonaws.com | tr -d '\n')/32}"
}

connect_vpn() {
  APP_PUBLIC_IP="$(terraform -chdir="$TF_DIR" output -raw app_public_ip)"
  APP_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw app_private_ip)"
  WAZUH_PRIVATE_IP="$(terraform -chdir="$TF_DIR" output -raw wazuh_private_ip)"
  VPC_CIDR="$(terraform -chdir="$TF_DIR" output -raw vpc_cidr)"
  CLIENT_KEY="$(cat "$SECRET_DIR/wg-client.key")"
  SERVER_KEY="$(cat "$SECRET_DIR/wg-server.pub")"

  cat >"$WG_CONFIG" <<CONFIG
[Interface]
PrivateKey = $CLIENT_KEY
Address = 10.77.0.2/32

[Peer]
PublicKey = $SERVER_KEY
Endpoint = $APP_PUBLIC_IP:51820
AllowedIPs = $VPC_CIDR
PersistentKeepalive = 25
CONFIG
  chmod 0600 "$WG_CONFIG"

  if ! sudo wg show interfaces 2>/dev/null | tr ' ' '\n' | grep -qx 'wg-lab'; then
    sudo wg-quick up "$WG_CONFIG"
  fi
  export LAB_APP_URL="http://$APP_PRIVATE_IP"
  export LAB_INDEXER_URL="https://$WAZUH_PRIVATE_IP:9200"
  export LAB_INDEXER_USER=admin
  export LAB_INDEXER_PASSWORD="$(cat "$SECRET_DIR/indexer-password")"
}

case "$MODE" in
  deploy)
    ensure_secrets
    init_terraform
    terraform -chdir="$TF_DIR" apply -input=false -auto-approve
    connect_vpn
    python3 "$ROOT_DIR/scripts/verify_lab.py"
    echo "DEPLOYMENT VERIFIED. VPN is active; Juice Shop: $LAB_APP_URL; Wazuh: https://$(terraform -chdir="$TF_DIR" output -raw wazuh_private_ip)"
    ;;
  verify)
    [[ -d "$SECRET_DIR" ]] || die "No local deployment secrets found; run ./lab.sh deploy first."
    init_terraform
    connect_vpn
    python3 "$ROOT_DIR/scripts/verify_lab.py"
    ;;
  destroy)
    [[ -d "$SECRET_DIR" ]] || die "No local deployment secrets found; nothing to destroy."
    init_terraform
    if sudo wg show interfaces 2>/dev/null | tr ' ' '\n' | grep -qx 'wg-lab'; then
      sudo wg-quick down "$WG_CONFIG" || true
    fi
    ensure_secrets
    terraform -chdir="$TF_DIR" destroy -input=false -auto-approve
    echo "Lab destroyed. Encrypted, versioned state bucket retained: $STATE_BUCKET"
    ;;
  *)
    echo "Usage: $0 [deploy|verify|destroy]" >&2
    exit 2
    ;;
esac
