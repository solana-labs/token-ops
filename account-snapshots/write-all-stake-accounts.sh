#!/usr/bin/env bash

set -e

RPC_URL=https://api.mainnet-beta.solana.com
timestamp="$(date -u +"%Y-%m-%d_%H:%M:%S")"
output_csv="stake_accounts-${timestamp}.csv"

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
   --url [RPC_URL]                        - RPC URL and port for a running Solana cluster (default: $RPC_URL)
   -o | --output-csv [FILEPATH]           - Path to desired output CSV file.  (default: $output_csv)
EOF
  exit $exitcode
}

function write_stake_info_to_csv {
  stake_account_info="$1"
  output_csv="$2"

  stake_account_address="$(echo "$stake_account_info" | grep "Stake Pubkey" | awk '{ print $3 }')"
  stake_authority="$(echo "$stake_account_info" | grep "Stake Authority" | awk '{ print $3 }')"
  withdraw_authority="$(echo "$stake_account_info" | grep "Withdraw Authority" | awk '{ print $3 }')"
  balance="$(echo "$stake_account_info" | grep "Balance" | awk '{ print $2 }')"
  delegated_to="$(echo "$stake_account_info" | grep "Delegated Vote Account Address" | awk '{ print $5 }')"
  lockup_timestamp="$(echo "$stake_account_info" | grep "Lockup Timestamp" | awk -F '[ )]' '{ print $5 }')"

  echo "STAKE,$stake_account_address,$balance,$stake_authority,$withdraw_authority,$delegated_to,$lockup_timestamp,$slot" >> $output_csv
}

shortArgs=()
while [[ -n $1 ]]; do
  if [[ ${1:0:2} = -- ]]; then
    if [[ $1 = --url ]]; then
      RPC_URL="$2"
      shift 2
    elif [[ $1 = --output-csv ]]; then
      output_csv="$2"
      shift 2
    else
      usage "Unknown option: $1"
    fi
  else
    shortArgs+=("$1")
    shift
  fi
done

while getopts "o:" opt "${shortArgs[@]}"; do
  case $opt in
  o)
    output_csv=$OPTARG
    ;;
  *)
    usage "Error: unhandled option: $opt"
    ;;
  esac
done

echo "Writing stake account data to $output_csv..."

all_stake_accounts_file="all_stake_accounts-${timestamp}"
solana stakes --url $RPC_URL > "$all_stake_accounts_file"
slot="$(solana slot --url $RPC_URL)"

echo "program,account_address,balance,stake_authority,withdraw_authority,delegated_to,lockup_timestamp,checked_at_slot" > $output_csv

stake_account_info=()
{
read
while IFS=, read -r line; do
  if [[ -n $line ]]; then
    stake_account_info+="${line}
"
  else
    write_stake_info_to_csv "$stake_account_info" "$output_csv"
    stake_account_info=()
  fi
done
} < "$all_stake_accounts_file"

echo "Finished"
