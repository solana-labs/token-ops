#!/usr/bin/env bash

source "$(dirname "$0")"/get_program_accounts.sh

usage() {
  exitcode=0
  if [[ -n "$1" ]]; then
    exitcode=1
    echo "Error: $*"
  fi
  cat <<EOF
usage: $0 [options]

 Report total token distribution of a running cluster owned by the following programs:
   STAKE
   SYSTEM
   VOTE
   STORAGE
   CONFIG

 Optional arguments:
   --url [cluster_rpc_url] - RPC URL for a running Solana cluster (Default: $RPC_URL)
   --quiet                 - If set, do not print individual program account totals, only cluster-wide totals
EOF
  exit $exitcode
}

function get_cluster_version {
  url="$1"
  clusterVersion="$(curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1, "method":"getVersion"}' $url | jq '.result | ."solana-core" ')"
  echo Cluster software version: $clusterVersion
}

function get_token_capitalization {
  url="$1"

  totalSupplyLamports="$(curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1, "method":"getTotalSupply"}' $url | cut -d , -f 2 | cut -d : -f 2)"
  totalSupplySol=$((totalSupplyLamports / LAMPORTS_PER_SOL))

  printf "\n--- Token Capitalization ---\n"
  printf "Total token capitalization %'d SOL\n" "$totalSupplySol"
  printf "Total token capitalization %'d Lamports\n" "$totalSupplyLamports"

  tokenCapitalizationLamports="$totalSupplyLamports"
  tokenCapitalizationSol="$totalSupplySol"
}

function get_program_account_balance_totals {
  PROGRAM_NAME="$1"
  quiet="$2"

  accountBalancesLamports="$(cat "${PROGRAM_NAME}_account_data.json" | \
    jq '.result | .[] | .account | .lamports')"

  totalAccountBalancesLamports=0
  numberOfAccounts=0

  for account in ${accountBalancesLamports[@]}; do
    totalAccountBalancesLamports=$((totalAccountBalancesLamports + account))
    numberOfAccounts=$((numberOfAccounts + 1))
  done

  totalAccountBalancesSol=$((totalAccountBalancesLamports / LAMPORTS_PER_SOL))

  if [[ -z $quiet ]]; then
    printf "\n--- %s Account Balance Totals ---\n" "$PROGRAM_NAME"
    printf "Number of %s Program accounts: %'.f\n" "$PROGRAM_NAME" "$numberOfAccounts"
    printf "Total token balance in all %s accounts: %'d SOL\n" "$PROGRAM_NAME" "$totalAccountBalancesSol"
    printf "Total token balance in all %s accounts: %'d Lamports\n" "$PROGRAM_NAME" "$totalAccountBalancesLamports"
  fi

  case $PROGRAM_NAME in
    SYSTEM)
      systemAccountBalanceTotalSol=$totalAccountBalancesSol
      systemAccountBalanceTotalLamports=$totalAccountBalancesLamports
      ;;
    STAKE)
      stakeAccountBalanceTotalSol=$totalAccountBalancesSol
      stakeAccountBalanceTotalLamports=$totalAccountBalancesLamports
      ;;
    VOTE)
      voteAccountBalanceTotalSol=$totalAccountBalancesSol
      voteAccountBalanceTotalLamports=$totalAccountBalancesLamports
      ;;
    CONFIG)
      configAccountBalanceTotalSol=$totalAccountBalancesSol
      configAccountBalanceTotalLamports=$totalAccountBalancesLamports
      ;;
    STORAGE)
      storageAccountBalanceTotalSol=$totalAccountBalancesSol
      storageAccountBalanceTotalLamports=$totalAccountBalancesLamports
      ;;
    *)
      echo "Unknown program: $PROGRAM_NAME"
      exit 1
      ;;
  esac
}

function sum_account_balances_totals {
  grandTotalAccountBalancesLamports=$((systemAccountBalanceTotalLamports + stakeAccountBalanceTotalLamports + voteAccountBalanceTotalLamports + configAccountBalanceTotalLamports + storageAccountBalanceTotalLamports))
  grandTotalAccountBalancesSol=$((grandTotalAccountBalancesLamports / LAMPORTS_PER_SOL))

  printf "\n--- Total Token Distribution in all Account Balances ---\n"
  printf "Total SOL in all Account Balances: %'d\n" "$grandTotalAccountBalancesSol"
  printf "Total Lamports in all Account Balances: %'d\n" "$grandTotalAccountBalancesLamports"
}

RPC_URL=https://api.mainnet-beta.solana.com
QUIET=

while [[ -n $1 ]]; do
  if [[ ${1:0:2} = -- ]]; then
    if [[ $1 = --url ]]; then
      RPC_URL="$2"
      shift 2
    elif [[ $1 = --quiet ]]; then
      QUIET=true
      shift 1
    else
      usage "Unknown option: $1"
    fi
  else
    usage "Unknown option: $1"
  fi
done

LAMPORTS_PER_SOL=1000000000 # 1 billion

stakeAccountBalanceTotalSol=
systemAccountBalanceTotalSol=
voteAccountBalanceTotalSol=
configAccountBalanceTotalSol=
storageAccountBalanceTotalSol=

stakeAccountBalanceTotalLamports=
systemAccountBalanceTotalLamports=
voteAccountBalanceTotalLamports=
configAccountBalanceTotalLamports=
storageAccountBalanceTotalLamports=

tokenCapitalizationSol=
tokenCapitalizationLamports=

echo "--- Querying RPC URL: $RPC_URL ---"
get_cluster_version $RPC_URL

get_program_accounts STAKE $STAKE_PROGRAM_PUBKEY $RPC_URL
get_program_accounts SYSTEM $SYSTEM_PROGRAM_PUBKEY $RPC_URL
get_program_accounts VOTE $VOTE_PROGRAM_PUBKEY $RPC_URL
get_program_accounts CONFIG $CONFIG_PROGRAM_PUBKEY $RPC_URL
get_program_accounts STORAGE $STORAGE_PROGRAM_PUBKEY $RPC_URL

write_program_account_data_csv STAKE
write_program_account_data_csv SYSTEM
write_program_account_data_csv VOTE
write_program_account_data_csv CONFIG
write_program_account_data_csv STORAGE

get_program_account_balance_totals STAKE $QUIET
get_program_account_balance_totals SYSTEM $QUIET
get_program_account_balance_totals VOTE $QUIET
get_program_account_balance_totals CONFIG $QUIET
get_program_account_balance_totals STORAGE $QUIET

sum_account_balances_totals

get_token_capitalization $RPC_URL
