#!/usr/bin/env bash
# Box://Stream Helper: one-step setup in Oracle Cloud Shell.
#
# Run it in Cloud Shell (the >_ icon at the top right of the Oracle Cloud console):
#   bash boxstream-setup.sh            create your helper server (or show its details again)
#   bash boxstream-setup.sh --remove   delete the helper server and everything this script made
#   bash boxstream-setup.sh --remove NAME   the same for a server by name (e.g. cedar-4821)
#
# It creates an Always Free server (VM.Standard.E2.1.Micro, Ubuntu 22.04) in your home
# region, under a plain random name (like cedar-4821, kept in ~/.boxstream-helper), with
# its own network that only accepts HTTPS (ports 80/443; no SSH), installs the
# helper on it, waits until it answers, and prints the address and pairing code to enter
# in Box://Stream (Settings > Helper). Nothing is sent anywhere else.
set -uo pipefail

LEGACY="boxstream-helper"   # the name versions before 1.2 used
SHAPE="VM.Standard.E2.1.Micro"
STATE_FILE="$HOME/.boxstream-helper"

say()  { printf '\n== %s\n' "$*"; }
fail() { printf '\nSetup stopped: %s\n' "$*" >&2; exit 1; }

command -v oci >/dev/null || fail "run this in Oracle Cloud Shell (the >_ icon at the top right of the Oracle console)."
command -v jq  >/dev/null || fail "jq is missing (Cloud Shell normally has it)."

TENANCY="${OCI_TENANCY:-}"
[ -n "$TENANCY" ] || TENANCY="$(oci iam compartment list --all --compartment-id-in-subtree false --query 'data[0]."compartment-id"' --raw-output 2>/dev/null)"
[ -n "$TENANCY" ] || fail "couldn't read your tenancy (are you in Cloud Shell?)."
C="$TENANCY"   # everything goes in the root compartment

HOME_REGION="$(oci iam region-subscription list --query 'data[?"is-home-region"]|[0]."region-name"' --raw-output 2>/dev/null)"
[ -n "$HOME_REGION" ] || HOME_REGION="${OCI_REGION:-}"
[ -n "$HOME_REGION" ] || fail "couldn't find your home region."
O() { oci --region "$HOME_REGION" "$@"; }

# What this Cloud Shell remembers: the pairing code and the server's name.
TOKEN=""
NAME=""
if [ -f "$STATE_FILE" ]; then
  TOKEN="$(jq -r '.token // empty' "$STATE_FILE" 2>/dev/null)"
  NAME="$(jq -r '.name // empty' "$STATE_FILE" 2>/dev/null)"
fi

# Lookups: a list Oracle refuses must never read as "nothing there" (that once made
# --remove skip a running server), so its message is kept and `checked` stops the script.
LOOKUP_ERR="$(mktemp)"
find_one() { # find_one <list command...>: id of the first live item named like ours
  local out
  if ! out="$("$@" --all 2>&1)"; then
    printf '%s\n' "$out" | grep -i '"message"' | head -n 1 > "$LOOKUP_ERR"
    [ -s "$LOOKUP_ERR" ] || printf '%s\n' "$out" | tail -n 2 > "$LOOKUP_ERR"
    return 1
  fi
  [ -n "$out" ] || return 0
  printf '%s' "$out" | jq -r '[.data[]? | select(."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING")][0].id // empty'
}

instance_id() { # instance_id <name>
  find_one O compute instance list -c "$C" --display-name "$1"
}

checked() {
  if [ -s "$LOOKUP_ERR" ]; then
    fail "couldn't read your Oracle resources: $(tr -s ' ' < "$LOOKUP_ERR"). Run the same command again in a minute."
  fi
}

public_ip() {
  O compute instance list-vnics --instance-id "$1" 2>/dev/null | jq -r '.data[0]."public-ip" // empty'
}

# ---- Remove ---------------------------------------------------------------------------
# Waits until a resource is gone: its "get" fails or says TERMINATED. Newer OCI CLIs
# changed what --wait-for-state accepts on deletes, so the script checks for itself.
wait_gone() { # wait_gone <seconds> <get command...>
  local limit=$1
  shift
  local waited=0
  while [ "$waited" -lt "$limit" ]; do
    local state
    state="$("$@" 2>/dev/null | jq -r '.data."lifecycle-state" // empty' 2>/dev/null)"
    if [ -z "$state" ] || [ "$state" = "TERMINATED" ]; then return 0; fi
    sleep 5
    waited=$((waited + 5))
  done
  return 1
}

# Sends a delete and waits for it; prints Oracle's message if it is refused.
delete_and_wait() { # delete_and_wait <label> <seconds> <get command...> -- <delete command...>
  local label=$1 limit=$2
  shift 2
  local get=()
  while [ "$1" != "--" ]; do get+=("$1"); shift; done
  shift
  local out
  if ! out="$("$@" 2>&1)"; then
    echo "Couldn't delete $label. Oracle said:"
    printf '%s\n' "$out" | grep -i '"message"\|error' | head -n 4
    return 1
  fi
  if ! wait_gone "$limit" "${get[@]}"; then
    echo "$label is still being deleted after $((limit / 60)) minutes; run --remove again in a little while."
    return 1
  fi
  return 0
}

remove_set() { # remove_set <server> <network> <subnet> <firewall> <gateway>
  ID="$(instance_id "$1")"
  checked
  if [ -n "$ID" ]; then
    echo "Deleting server $1 (this takes a minute or two)..."
    if delete_and_wait "the server $1" 900 O compute instance get --instance-id "$ID" -- \
        O compute instance terminate --instance-id "$ID" --preserve-boot-volume false --force; then
      echo "Server $1 deleted."
    else
      echo "Its network is left alone while the server is there. Run --remove again once it's gone."
      return 1
    fi
  fi
  VCN="$(find_one O network vcn list -c "$C" --display-name "$2")"
  checked
  [ -n "$VCN" ] || return 0
  echo "Deleting network $2..."
  SUB="$(find_one O network subnet list -c "$C" --vcn-id "$VCN" --display-name "$3")"
  checked
  if [ -n "$SUB" ]; then
    delete_and_wait "the subnet $3" 300 O network subnet get --subnet-id "$SUB" -- \
      O network subnet delete --subnet-id "$SUB" --force || return 1
  fi
  SL="$(find_one O network security-list list -c "$C" --vcn-id "$VCN" --display-name "$4")"
  checked
  if [ -n "$SL" ]; then
    delete_and_wait "the firewall rules $4" 300 O network security-list get --security-list-id "$SL" -- \
      O network security-list delete --security-list-id "$SL" --force || return 1
  fi
  RT="$(O network vcn get --vcn-id "$VCN" | jq -r '.data."default-route-table-id"')"
  O network route-table update --rt-id "$RT" --route-rules '[]' --force >/dev/null 2>&1
  IGW="$(find_one O network internet-gateway list -c "$C" --vcn-id "$VCN" --display-name "$5")"
  checked
  if [ -n "$IGW" ]; then
    delete_and_wait "the gateway $5" 300 O network internet-gateway get --ig-id "$IGW" -- \
      O network internet-gateway delete --ig-id "$IGW" --force || return 1
  fi
  delete_and_wait "the network $2" 300 O network vcn get --vcn-id "$VCN" -- \
    O network vcn delete --vcn-id "$VCN" --force || return 1
  echo "Network $2 deleted."
}

if [ "${1:-}" = "--remove" ]; then
  [ -n "${2:-}" ] && NAME="$2"
  say "Removing the Box://Stream helper server from $HOME_REGION"
  if [ -z "$NAME" ]; then
    echo "This Cloud Shell doesn't know your helper server's name, so it can't remove it."
    echo "Find the name in the Oracle console (Compute > Instances, e.g. cedar-4821) and run:"
    echo "  bash $0 --remove NAME"
    echo "(Older servers named boxstream-helper are still removed now.)"
  fi
  OK=1
  if [ -n "$NAME" ]; then remove_set "$NAME" "$NAME-net" "$NAME-sub" "$NAME-fw" "$NAME-gw" || OK=0; fi
  remove_set "$LEGACY" boxstream-vcn boxstream-subnet boxstream-web boxstream-igw || OK=0
  # Keep the saved name and code until everything is gone, so a re-run finds it.
  [ "$OK" = 1 ] || fail "not everything was removed (see above)."
  rm -f "$STATE_FILE"
  echo "Done. Remember to clear Settings > Helper in Box://Stream."
  exit 0
fi

# ---- Already set up? ----------------------------------------------------------------------
if [ -z "$NAME" ]; then
  LEG="$(instance_id "$LEGACY")"
  checked
  if [ -n "$LEG" ]; then
    fail "an older helper server ($LEGACY) is still there. Run: bash $0 --remove   then run this again."
  fi
  # A plain name with a number, for the server and its network.
  WORDS=(atlas birch cedar delta ember fjord harbor juniper maple nova orbit pine quartz river summit willow)
  NAME="${WORDS[RANDOM % ${#WORDS[@]}]}-$(( RANDOM % 9000 + 1000 ))"
fi
EXISTING="$(instance_id "$NAME")"
checked
if [ -n "$EXISTING" ] && [ -z "$TOKEN" ]; then
  fail "a server named $NAME already exists, but its pairing code isn't saved in this Cloud Shell. Run: bash $0 --remove   then run this again."
fi
if [ -z "$TOKEN" ]; then
  # 8 characters, no look-alikes (0/O, 1/I/L): easy to type with a TV remote.
  TOKEN="$(python3 -c "import secrets; print(''.join(secrets.choice('ABCDEFGHJKMNPQRSTUVWXYZ23456789') for _ in range(8)))")"
fi
printf '{"token": "%s", "name": "%s"}\n' "$TOKEN" "$NAME" > "$STATE_FILE"
chmod 600 "$STATE_FILE"

if [ -n "$EXISTING" ]; then
  say "Your helper server already exists"
  ID="$EXISTING"
else
  # ---- Network (HTTPS in, anything out) ---------------------------------------------------
  say "Creating the network in $HOME_REGION"
  VCN="$(find_one O network vcn list -c "$C" --display-name "$NAME-net")"
  checked
  if [ -z "$VCN" ]; then
    VCN="$(O network vcn create -c "$C" --cidr-blocks '["10.77.0.0/16"]' --display-name "$NAME-net" \
      --dns-label "$(echo "$NAME" | tr -d -)" --wait-for-state AVAILABLE 2>/dev/null | jq -r '.data.id // empty')"
  fi
  [ -n "$VCN" ] || fail "couldn't create the network (your account may have reached its network limit)."
  IGW="$(find_one O network internet-gateway list -c "$C" --vcn-id "$VCN" --display-name "$NAME-gw")"
  checked
  if [ -z "$IGW" ]; then
    IGW="$(O network internet-gateway create -c "$C" --vcn-id "$VCN" --is-enabled true --display-name "$NAME-gw" \
      --wait-for-state AVAILABLE 2>/dev/null | jq -r '.data.id // empty')"
  fi
  [ -n "$IGW" ] || fail "couldn't create the internet gateway."
  RT="$(O network vcn get --vcn-id "$VCN" | jq -r '.data."default-route-table-id"')"
  O network route-table update --rt-id "$RT" --force --wait-for-state AVAILABLE \
    --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$IGW\"}]" >/dev/null \
    || fail "couldn't set the network's route."
  SL="$(find_one O network security-list list -c "$C" --vcn-id "$VCN" --display-name "$NAME-fw")"
  checked
  if [ -z "$SL" ]; then
    SL="$(O network security-list create -c "$C" --vcn-id "$VCN" --display-name "$NAME-fw" --wait-for-state AVAILABLE \
      --egress-security-rules '[{"destination":"0.0.0.0/0","protocol":"all","isStateless":false}]' \
      --ingress-security-rules '[{"source":"0.0.0.0/0","protocol":"6","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":80,"max":80}}},{"source":"0.0.0.0/0","protocol":"6","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":443,"max":443}}}]' \
      2>/dev/null | jq -r '.data.id // empty')"
  fi
  [ -n "$SL" ] || fail "couldn't create the firewall rules."
  SUB="$(find_one O network subnet list -c "$C" --vcn-id "$VCN" --display-name "$NAME-sub")"
  checked
  if [ -z "$SUB" ]; then
    SUB="$(O network subnet create -c "$C" --vcn-id "$VCN" --cidr-block 10.77.1.0/24 --display-name "$NAME-sub" \
      --dns-label web --route-table-id "$RT" --security-list-ids "[\"$SL\"]" --wait-for-state AVAILABLE \
      2>/dev/null | jq -r '.data.id // empty')"
  fi
  [ -n "$SUB" ] || fail "couldn't create the subnet."

  # ---- Server -------------------------------------------------------------------------
  say "Finding the Ubuntu 22.04 image"
  IMG="$(O compute image list -c "$C" --operating-system "Canonical Ubuntu" --operating-system-version "22.04" \
    --shape "$SHAPE" --sort-by TIMECREATED --sort-order DESC --limit 1 2>/dev/null | jq -r '.data[0].id // empty')"
  [ -n "$IMG" ] || fail "couldn't find an Ubuntu 22.04 image for $SHAPE in $HOME_REGION."

  # What the server runs at first boot: the helper and its installer (packed below), then
  # the installer with this pairing code.
  USERDATA="$(mktemp)"
  {
    echo '#!/bin/bash'
    echo 'mkdir -p /opt/boxstream && cd /opt/boxstream'
    echo "printf '{\"token\": \"%s\", \"port\": 8090}\n' '$TOKEN' > /etc/boxstream-helper.json"
    echo 'chmod 640 /etc/boxstream-helper.json'
    echo 'base64 -d <<'"'"'PAYLOAD'"'"' | tar -xz'
    echo '__PAYLOAD__'
    echo 'PAYLOAD'
    echo 'bash /opt/boxstream/install.sh > /var/log/boxstream-install.log 2>&1'
  } > "$USERDATA"

  say "Creating the server (Always Free $SHAPE)"
  ID=""
  ERR=""
  for AD in $(O iam availability-domain list -c "$C" 2>/dev/null | jq -r '.data[].name'); do
    echo "Trying $AD..."
    OUT="$(O compute instance launch -c "$C" --availability-domain "$AD" --shape "$SHAPE" --image-id "$IMG" \
      --subnet-id "$SUB" --assign-public-ip true --display-name "$NAME" --user-data-file "$USERDATA" \
      --wait-for-state RUNNING 2>&1)"
    ID="$(printf '%s' "$OUT" | sed -n '/^{/,$p' | jq -r '.data.id // empty' 2>/dev/null)"
    [ -n "$ID" ] && break
    ERR="$OUT"
  done
  rm -f "$USERDATA"
  if [ -z "$ID" ]; then
    if printf '%s' "$ERR" | grep -qi "capacity"; then
      fail "Oracle has no free $SHAPE servers left in $HOME_REGION right now. Try again later (often within hours)."
    elif printf '%s' "$ERR" | grep -qi "limit"; then
      fail "your account is at its Always Free limit for $SHAPE (2 servers). Delete one you don't use, then run this again."
    fi
    printf '%s\n' "$ERR" | tail -n 5 >&2
    fail "couldn't create the server."
  fi
fi

IP="$(public_ip "$ID")"
[ -n "$IP" ] || fail "the server has no public address."
HOST="$(echo "$IP" | tr . -).sslip.io"

# ---- Wait for it ----------------------------------------------------------------------
say "Installing on the server (about 5-10 minutes on a free server)"
READY=""
for i in $(seq 1 120); do
  if curl -fs -m 8 -H "X-Helper-Token: $TOKEN" "https://$HOST/ping" 2>/dev/null | grep -q '"ok": *true'; then
    READY=1
    break
  fi
  printf '.'
  sleep 10
done
echo
[ -n "$READY" ] || fail "the server didn't answer within 20 minutes. Run this script again to keep waiting; if it still doesn't answer, run it with --remove and start over."

cat <<DONE

  Box://Stream Helper is ready

  Address:       https://$HOST
  Pairing code:  $TOKEN
  Server name:   $NAME

  On your Roku: Box://Stream > Settings > Helper > enter both, then Test.
  (Run this script again any time to see these again.)

  Keep the server name. To delete this server later, run:
    bash boxstream-setup.sh --remove $NAME

DONE
