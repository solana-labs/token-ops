#!/usr/bin/env bash

set -e

RPC_URL=https://api.mainnet-beta.solana.com
stake_address_file=
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
   --stake-address-file [FILEPATH]  - Path to a newline-separated file containing a list of stake account addresses of interest to collect.
                                      If not provided, query and record all stake accounts on the cluster.  This takes a few minutes.
EOF
  exit $exitcode
}

while [[ -n $1 ]]; do
  if [[ ${1:0:2} = -- ]]; then
    if [[ $1 = --url ]]; then
      RPC_URL="$2"
      shift 2
    elif [[ $1 = --stake-address-file ]]; then
      stake_address_file="$2"
      shift 2
    else
      usage "Unknown option: $1"
    fi
  else
    usage "Unknown option: $1"
  fi
done

results_file="stake_accounts_and_signers-${timestamp}.csv"
echo "stake_account_address,balance,stake_authority,withdraw_authority,delegated_to,lockup_timestamp,checked_at_slot" > $results_file

if [[ -z $stake_address_file ]]; then
  stake_address_file="all_stake_addresses-${timestamp}.csv"
  solana stakes --url $RPC_URL | grep Pubkey | awk '{ print $3 }' > "$stake_address_file"
fi

echo "Looking for all stake accounts in $stake_address_file"
echo "Writing results to $results_file.  Depending on the number of accounts in $stake_address_file, this might take a few minutes."

{
while IFS=, read -r stake_account_address; do
  stake_account_info="$(solana stake-account "$stake_account_address" --url $RPC_URL)"
  slot="$(solana slot)"
  stake_authority="$(echo "$stake_account_info" | grep "Stake Authority" | awk '{ print $3 }')"
  withdraw_authority="$(echo "$stake_account_info" | grep "Withdraw Authority" | awk '{ print $3 }')"
  balance="$(echo "$stake_account_info" | grep "Balance" | awk '{ print $2 }')"

  delegated_to=
  [[ -n "$(echo "$stake_account_info" | grep "Stake deactivates starting from epoch")" ]] || {
    delegated_to="$(echo "$stake_account_info" | grep "Delegated Vote Account Address" | awk '{ print $5 }')"
  }

  lockup_timestamp="$(echo "$stake_account_info" | grep "Lockup Timestamp" | awk -F '[ )]' '{ print $5 }')"

  echo "$stake_account_address,$balance,$stake_authority,$withdraw_authority,$delegated_to,$lockup_timestamp,$slot" >> $results_file
done
} < "$stake_address_file"

echo "Finished"
