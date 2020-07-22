#!/usr/bin/env bash

set -e

source "$(dirname "$0")"/get_program_accounts.sh

RPC_URL=http://api.mainnet-beta.solana.com
timestamp="$(date -u +"%Y-%m-%d_%H:%M:%S")"

usage() {
  exitcode=0
  if [[ -n "$1" ]]; then
    exitcode=1
    echo "Error: $*"
  fi
  cat <<EOF
usage: $0 [options]

 Writes a .csv file with the current list of all stake accounts on the network,
 including their balance, authorities, delegation and lockup

 Optional arguments:
   --url [RPC_URL]                  - RPC URL and port for a running Solana cluster (default: $RPC_URL)
EOF
  exit $exitcode
}

while [[ -n $1 ]]; do
  if [[ ${1:0:2} = -- ]]; then
    if [[ $1 = --url ]]; then
      RPC_URL="$2"
      shift 2
    else
      usage "Unknown option: $1"
    fi
  else
    usage "Unknown option: $1"
  fi
done


json_file=system_account_data-${timestamp}.json
csv_file=system_account_balances-${timestamp}.csv

slot="$(solana slot)"

echo "Checking system accounts at $timestamp, and slot: $slot"
get_program_accounts SYSTEM $SYSTEM_PROGRAM_PUBKEY $RPC_URL $json_file

echo "Writing all system account data to: $csv_file"
write_program_account_data_csv SYSTEM $json_file $csv_file
