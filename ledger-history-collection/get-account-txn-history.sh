#!/usr/bin/env bash

# Provide an account address, and return the following
# A list of all txn signatures involving this account, from genesis to present
# Oldest transactions at the top of the list
# Parse transaction details for each signature to csv, with fields:
# txn_sig, error_status, slot, pre_balance, post_balance

set -e

usage() {
  exitcode=0
  if [[ -n "$1" ]]; then
    exitcode=1
    echo "Error: $*"
  fi
  cat <<EOF
usage: $0 [options] --address [address] | --address-file [address file]
 Mandatory agruments:
    Provide either --address OR --address-file
    --address [address]                - A single account address for which you want the detailed transaction history
    --address-file [address file]      - A newline-separated text file containing a list of all addresses for which the history will be pulled.

 Optional arguments:
    --url [RPC_URL]                    - RPC URL and port for a running Solana cluster (default: $RPC_URL)
EOF
  exit $exitcode
}

get_all_transaction_signatures() {
  address="$1"
  output_file="$2"

  signature_list="$(RUST_LOG=solana=warn solana-ledger-tool -l . bigtable transaction-history $address)"

  reversed_sig_list=()
  while IFS=, read -r sig; do
    reversed_sig_list="${sig}"$'\n'"${reversed_sig_list}"
  done <<<"${signature_list}"

  echo "$reversed_sig_list" > $output_file
  total_txns=$(cat $output_file | wc -l | awk '{print $1}')
  echo "Found $total_txns transactions for $address"
}

write_transaction_details_to_file() {
  input_file="$1"
  output_csv="$2"

  header="slot,signature,err,target_addr,target_pre,target_post,target_change,"
  header="${header}0_addr,0_pre,0_post,0_change,1_addr,1_pre,1_post,1_change,"
  header="${header}2_addr,2_pre,2_post,2_change,3_addr,3_pre,3_post,3_change,"
  header="${header}4_addr,4_pre,4_post,4_change,5_addr,5_pre,5_post,5_change,"
  header="${header}6_addr,6_pre,6_post,6_change,7_addr,7_pre,7_post,7_change,"

  echo "$header" > "$output_csv"
  {
  while IFS=, read -r signature; do
    [[ -n $signature ]] || break

    txn_details="$(curl -sX POST -H "Content-Type: application/json" -d '{"jsonrpc": "2.0","id":1,"method":"getConfirmedTransaction","params":["'$signature'", "json"]}' $RPC_URL)"
    slot=$(echo $txn_details | jq -r '.result | .slot')
    err=$(echo $txn_details | jq -r '.result | .meta | .err | @text')
    [[ $err = "null" ]] || err="error"

    accounts="$(echo $txn_details | jq -r '.result | .transaction | .message | .accountKeys | .[]')"
    pre_balances="$(echo $txn_details | jq -r '.result | .meta | .preBalances? | .[]?')"
    post_balances="$(echo $txn_details | jq -r '.result | .meta | .postBalances? | .[]?')"

    accounts_array=(${accounts})
    pre_balances_array=(${pre_balances})
    post_balances_array=(${post_balances})

    output_string="$slot,$signature,$err,$address,"
    additional_account_balances_string=""

    len=${#accounts_array[*]}
    for (( i=0; i<${len} ; i++ )); do
      if [[ "${accounts_array[$i]}" = "$address" ]]; then
        target_pre_balance_lamports=${pre_balances_array[$i]}
        target_post_balance_lamports=${post_balances_array[$i]}
        target_pre_balance=$((target_pre_balance_lamports / 1000000000))
        target_post_balance=$((target_post_balance_lamports / 1000000000))
        target_change=$((target_post_balance - target_pre_balance))
      else
        other_pre_balance_lamports=${pre_balances_array[$i]}
        other_post_balance_lamports=${post_balances_array[$i]}
        other_pre_balance=$((other_pre_balance_lamports / 1000000000))
        other_post_balance=$((other_post_balance_lamports / 1000000000))
        other_change=$((other_post_balance - other_pre_balance))
        additional_account_balances_string="${additional_account_balances_string}${accounts_array[$i]},${other_pre_balance},${other_post_balance},${other_change},"
      fi
    done

    if [[ len > 0 ]]; then
      output_string="${output_string}${target_pre_balance},${target_post_balance},${target_change},${additional_account_balances_string}"
    fi

    echo "$output_string" >> $output_csv
  done
  } < "$input_file"
}

get_account_txn_history() {
  out_dir="$1"
  addr="$2"

  signature_file=$out_dir/txn_sigs_$addr.csv
  account_history_csv=$out_dir/account_history_$addr.csv

  echo "Finding all transaction signatures for $address"
  get_all_transaction_signatures $addr $signature_file

  echo "Parsing all transaction details for $address"
  write_transaction_details_to_file $signature_file $account_history_csv
}

export GOOGLE_APPLICATION_CREDENTIALS=~/mainnet-beta-bigtable-ro.json
RPC_URL=https://api.mainnet-beta.solana.com
timestamp="$(date -u +"%Y-%m-%d_%H:%M:%S")"

address=
address_file=

while [[ -n $1 ]]; do
  if [[ ${1:0:2} = -- ]]; then
    if [[ $1 = --url ]]; then
      RPC_URL="$2"
      shift 2
    elif [[ $1 = --address ]]; then
      address="$2"
      shift 2
    elif [[ $1 = --address-file ]]; then
      address_file="$2"
      shift 2
    else
      usage "Unknown option: $1"
    fi
  else
    usage "Unknown option: $1"
  fi
done

if [[ -n $address && -n $address_file ]]; then
  usage "Cannot provide both --address AND --address-file"
elif [[ -z $address && -z $address_file ]]; then
  usage "Must provide --address OR --address-file"
fi

output_dir="account_histories-${timestamp}"
mkdir -p $output_dir

if [[ -n $address_file ]]; then
  {
  while IFS=, read -r address; do
    get_account_txn_history "$output_dir" "$address"
  done
  } < "$address_file"
else
  get_account_txn_history "$output_dir" "$address"
fi
