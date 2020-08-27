#!/usr/bin/env bash

# Provide an account address, and return the following
# A list of all txn signatures involving this account, from genesis to present
# Oldest transactions at the top of the list
# Parse transaction details for each signature to csv, with fields:
# txn_sig, slot, pre_balance, post_balance

set -e

RPC_URL=https://api.mainnet-beta.solana.com

usage() {
  exitcode=0
  if [[ -n "$1" ]]; then
    exitcode=1
    echo "Error: $*"
  fi
  cat <<EOF
usage: $0 [options] [address]

 Optional arguments:
    --url [RPC_URL]            - RPC URL and port for a running Solana cluster (default: $RPC_URL)
EOF
  exit $exitcode
}

get_all_transaction_signatures() {
  address="$1"
  output_file="$2"

  new_signature_list=$(curl -sX POST -H "Content-Type: application/json" -d \
  '{"jsonrpc": "2.0","id":1,"method":"getConfirmedSignaturesForAddress2","params":["'$address'", {"limit": 1000}]}' $RPC_URL \
  | jq -r '(.result | .[]) | .signature'
  )
  signature_list=$new_signature_list

  while [[ "$(echo $new_signature_list | wc -w)" -eq 1000 ]]; do
    echo "there are 1000 transactions"
    earliest_txn=$(echo $new_signature_list | awk '{print $NF}')

    echo "earliest txn is $earliest_txn"

    new_signature_list=$(curl -sX POST -H "Content-Type: application/json" -d \
    '{"jsonrpc": "2.0","id":1,"method":"getConfirmedSignaturesForAddress2","params":["'$address'", {"limit": 1000, "before": "'$earliest_txn'"}]}' $RPC_URL \
    | jq -r '(.result | .[]) | .signature'
    )
    signature_list+=$'\n'
    signature_list+=$new_signature_list
  done

  reversed_sig_list=()
  while IFS=, read -r sig; do
    reversed_sig_list="${sig}"$'\n'"${reversed_sig_list}"
  done <<<"${signature_list}"

  echo "$reversed_sig_list" > $output_file
  total_txns=$(cat $output_file | wc -l | awk '{print $1}')
  echo "There are $total_txns transactions for $address"
}

write_transaction_details_to_file() {
  input_file="$1"
  output_csv="$2"

  echo "slot,signature,err,pre_balance,post_balance" > "$output_csv"
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

    len=${#accounts_array[*]}
    for (( i=0; i<${len} ; i++ )); do
      if [[ "${accounts_array[$i]}" = "$address" ]]; then
        pre_balance_lamports=${pre_balances_array[$i]}
        post_balance_lamports=${post_balances_array[$i]}
        break
      fi
    done

    pre_balance=$((pre_balance_lamports / 1000000000))
    post_balance=$((post_balance_lamports / 1000000000))

    echo "$slot,$signature,$err,$pre_balance,$post_balance" >> $output_csv
  done
  } < "$input_file"
}

address="$1"
[[ -n $address ]] || usage "Must provide an address"

signature_file=txn_sigs_$address
account_history_csv=account_history_$address.csv

get_all_transaction_signatures $address $signature_file
write_transaction_details_to_file $signature_file $account_history_csv
