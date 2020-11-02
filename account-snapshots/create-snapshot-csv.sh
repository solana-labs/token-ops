#!/usr/bin/env bash

set -e

RPC_URL=https://api.mainnet-beta.solana.com
timestamp="$(date -u +"%Y-%m-%d_%H:%M:%S")"

usage() {
  exitcode=0
  if [[ -n "$1" ]]; then
    exitcode=1
    echo "Error: $*"
  fi
  cat <<EOF
usage: $0 [options]

 Writes two .csv files containing the addresses and balances for all system and
 stake accounts on the network.  Each file contains account information for each
 respective program.

 Optional arguments:
   --url [RPC_URL]             - RPC URL and port for a running Solana cluster (default: $RPC_URL)
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

output_dir="account_snapshot-${timestamp}"
mkdir -p $output_dir

system_account_output_file=$output_dir/system_accounts.csv
stake_account_output_file=$output_dir/stake_accounts.csv

"$(dirname "$0")"/write-all-system-accounts.sh --url $RPC_URL --output-csv $system_account_output_file
"$(dirname "$0")"/write-all-stake-accounts.sh --url $RPC_URL --output-csv $stake_account_output_file

echo "Wrote account snapshot to $output_dir"
