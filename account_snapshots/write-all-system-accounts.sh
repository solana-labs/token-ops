#!/usr/bin/env bash

set -e
#set -x

source get_program_accounts.sh

#rpc_url=http://api.mainnet-beta.solana.com
rpc_url=http://testnet.solana.com

timestamp="$(date -u +"%Y-%m-%d_%H:%M:%S")"

json_file=system_account_data-${timestamp}.json
csv_file=system_account_balances-${timestamp}.csv

slot="$(solana slot)"

echo "Checking system accounts at $timestamp, and slot: $slot"

get_program_accounts SYSTEM $SYSTEM_PROGRAM_PUBKEY $rpc_url $json_file
write_program_account_data_csv SYSTEM $json_file $csv_file
