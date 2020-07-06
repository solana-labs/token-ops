#!/usr/bin/env bash

# Writes a .csv file with the current list of all stake accounts on the network,
# including their balance, authorities, delegation and lockup

set -e
#set -x

timestamp="$(date -u +"%Y-%m-%d_%H:%M:%S")"

#rpc_url=http://api.mainnet-beta.solana.com
rpc_url=http://testnet.solana.com

results_file="stake_accounts_and_signers-${timestamp}.csv"
echo "stake_account_address,balance,stake_authority,withdraw_authority,delegated_to,lockup_timestamp,checked_at_slot" > $results_file

stake_address_file="all_stake_addresses-${timestamp}.csv"
solana stakes | grep Pubkey | awk '{ print $3 }' > "$stake_address_file"

{
while IFS=, read -r stake_account_address; do
  stake_account_info="$(solana stake-account "$stake_account_address")"
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
