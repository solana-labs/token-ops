#!/usr/bin/env python3
import requests
import csv
import time
import logging
import json
import argparse
import pathlib
import os


def write_balances_to_file(balances, filename):
    with open(filename, 'w') as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(['address', 'balance'])
        for key, value in balances.items():
            writer.writerow([key, value])


def read_balances_from_file(filename):
    with open(filename) as infile:
        reader = csv.DictReader(infile)
        data = {}
        for row in reader:
            key = row["address"]
            val = float(row["balance"])
            data[key] = val
    return data


def get_latest_balances(addresses, rpc_url, webhook_url):
    try:
        balances = []
        max_addrs_per_request = 100
        i = 0
        last_iter = False

        while True:
            if len(addresses) <= max_addrs_per_request * (i + 1):
                addr_list_slice = addresses[max_addrs_per_request * i:]
                last_iter = True
            else:
                addr_list_slice = addresses[max_addrs_per_request * i:
                                            max_addrs_per_request * (i + 1)]

            payload = {
                "method": "getMultipleAccounts",
                "params": [
                    addr_list_slice,
                    {
                        "encoding": "base64"
                    },
                ],
                "jsonrpc": "2.0",
                "id": 0,
            }

            response = requests.post(rpc_url, json=payload, timeout=60).json()

            for entry in response['result']['value']:
                if entry is None:
                    balances.append(0)
                else:
                    balances.append(entry['lamports']/1000000000)

            if last_iter:
                break
            else:
                i += 1

        return {k: v for k, v in zip(addresses, balances)}

    except Exception as e:
        logging.error(str(e))
        send_message_to_slack(str(e), webhook_url)
        return None


# Read a csv file and return a dict with the addresses as keys,
# and dicts with any subsequent column headers:data as values
def get_dict_from_csv(filename):
    with open(filename) as infile:
        reader = csv.DictReader(infile)
        data = {}
        for row in reader:
            key = row.pop('address')
            data[key] = dict(row)
    return data


def compare_balances(old_balances,
                     new_balances,
                     account_info,
                     webhook_url=None):
    for address, new_balance in new_balances.items():
        send_message = False
        if address in old_balances:
            if new_balance < old_balances[address]:
                message = "Balance of %s has decreased from %d to %d SOL" % \
                          (address, old_balances[address], new_balance)
                logging.warning(message)
                send_message = True
            elif new_balance > old_balances[address]:
                message = "Balance of %s has increased from %d to %d SOL" % \
                          (address, old_balances[address], new_balance)
                logging.info(message)
            else:
                message = "Balance of %s has not changed" % address
                logging.debug(message)
        else:
            message = "%s not found in prior balance data" % address
            logging.info(message)

        if webhook_url is not None and send_message is True:
            send_message_to_slack(message,
                                  webhook_url)
            publish_account_info_to_slack(address,
                                          account_info,
                                          webhook_url)


def send_message_to_slack(payload, webhook_url):
    slack_data = {"text": payload}

    response = requests.post(
        webhook_url, data=json.dumps(slack_data),
        headers={'Content-Type': 'application/json'}
    )
    if response.status_code != 200:
        raise ValueError(
            'Request to slack returned an error %s, the response is:\n%s'
            % (response.status_code, response.text)
        )


def publish_account_info_to_slack(address, account_info, webhook_url):
    payload = "```address: %s" % address
    for k, v in account_info[address].items():
        payload += "\n%s: %s" % (k, v)
    payload += "```"
    logging.info(payload)
    send_message_to_slack(payload, webhook_url)


def publish_all_balances_to_slack(balances, webhook_url):
    payload = "\n"
    for k, v in balances.items():
        payload += "`%s: %.2f`\n" % (k, v)
    logging.info(payload)
    send_message_to_slack(payload, webhook_url)


def main():
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-u', '--rpc-url',
                        type=str,
                        default="http://api.mainnet-beta.solana.com",
                        help="RPC endpoint to target",
                        dest="rpc_url")
    parser.add_argument('-w', '--slack-webhook-url',
                        type=str,
                        dest="slack_webhook_url",
                        help="Webhook URL to receive monitoring alerts")
    parser.add_argument('-i', '--input-file',
                        type=str,
                        default="accounts.csv",
                        dest="input_file",
                        help="Input .csv file that contains at a minimum, "
                             "a single column containing a list of addresses"
                             " to monitor")
    parser.add_argument('-o', '--output-file', type=str,
                        default="latest_balances.csv",
                        dest="balances_file",
                        help="Output .csv file that will contain columns of "
                             "account addresses and their latest balances in"
                             " SOL")
    parser.add_argument('--balance-check-interval',
                        type=int,
                        default=60,
                        dest="balance_check_interval",
                        help="Number of seconds between balance checks")
    parser.add_argument('--liveness-check-interval',
                        type=int,
                        default=3600,
                        dest="liveness_check_interval",
                        help="Number of seconds between liveness checks")

    args = parser.parse_args()

    account_info = get_dict_from_csv(args.input_file)
    addresses = list(account_info.keys())

    old_balances = {}
    if os.path.isfile(args.balances_file):
        old_balances = read_balances_from_file(args.balances_file)

    if args.slack_webhook_url is not None:
        send_message_to_slack("Starting account monitoring "
                              "with the following known balances:",
                              args.slack_webhook_url)
        publish_all_balances_to_slack(old_balances, args.slack_webhook_url)

    liveness_time = time.time()

    while True:
        if time.time() - liveness_time >= args.liveness_check_interval:
            message = "Liveness Check interval: %d seconds\n" \
                      "Balance check interval: %d seconds\n" \
                      "Time since last balance update: %d seconds" % \
                      (args.liveness_check_interval,
                       args.balance_check_interval,
                       time.time() -
                       pathlib.Path(args.balances_file).stat().st_mtime)
            logging.info(message)
            if args.slack_webhook_url is not None:
                send_message_to_slack(message, args.slack_webhook_url)
            liveness_time = time.time()

        latest_balances = get_latest_balances(addresses,
                                              args.rpc_url,
                                              args.slack_webhook_url)
        if latest_balances is not None:
            compare_balances(old_balances,
                             latest_balances,
                             account_info,
                             webhook_url=args.slack_webhook_url)

            write_balances_to_file(latest_balances, args.balances_file)
            old_balances = latest_balances
        else:
            message = "Unable to retrieve latest balances from RPC node"
            logging.warning(message)
            send_message_to_slack(message, args.slack_webhook_url)

        time.sleep(args.balance_check_interval)


if __name__ == "__main__":
    main()
