import json
import requests
import sys
import re


def get_token_id(token_symbol):
    # Send the request to get the token ID
    token_symbol = re.findall(r'[A-Za-z0-9]+',token_symbol)[0]

    url = f'https://hermes.pyth.network/v2/price_feeds?query={token_symbol}&asset_type=crypto'
    headers = {'accept': 'application/json'}
    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        data = response.json()
        if len(data) > 0:
            return data[0]['id']
        else:
            print(f"Token {token_symbol} not found.")
            exit(1)
    else:
        print(f"Failed to fetch token ID. Status code: {response.status_code}")
        exit(1)

def get_token_price(response_body):
    # Parse the response body (assuming it's a JSON string)
    data = json.loads(response_body)
    
    # Extract the price and exponent
    price = int(data['parsed'][0]['price']['price'])
    expo = int(data['parsed'][0]['price']['expo'])
    
    # Calculate the token price in USD
    token_usd_price = price * (10 ** expo)
    
    return token_usd_price

def fetch_token_price(token0_symbol, token1_symbol):
    # Get the token ID from the token name
    token0_id = get_token_id(token0_symbol)
    token1_id = get_token_id(token1_symbol)
    if token0_id is None or token1_id is None:
        return
    
    # Send the request to get the price feed
    url0 = f'https://hermes.pyth.network/v2/updates/price/latest?ids%5B%5D={token0_id}'
    url1 = f'https://hermes.pyth.network/v2/updates/price/latest?ids%5B%5D={token1_id}'
    headers = {'accept': 'application/json'}
    response0 = requests.get(url0, headers=headers)
    response1 = requests.get(url1, headers=headers)

    if (response0.status_code != 200 or response1.status_code != 200):
        print("Failed to fetch token price.")
        return

    # Get the token price in USD
    response0_body = response0.text
    token0_price = get_token_price(response0_body)

    response1_body = response1.text
    token1_price = get_token_price(response1_body)

    print(token1_price / token0_price)

def get_token_symbol_from_rpc(rpc_url, token_address):
    # Send a request to the RPC URL to get the token symbol from the token address
    payload = {
        "jsonrpc": "2.0",
        "method": "eth_call",
        "params": [
            {
                "to": token_address,
                "data": "0x95d89b41"  # function selector for symbol()
            },
            "latest"
        ],
        "id": 1
    }
    headers = {'Content-Type': 'application/json'}
    response = requests.post(rpc_url, headers=headers, json=payload)
    
    if response.status_code == 200:
        data = response.json()
        if 'result' in data:
            hex_symbol = data['result']
            symbol = bytes.fromhex(hex_symbol[2:]).decode('ascii').strip('\x00')
            
            return symbol
        else:
            print("Failed to get token symbol from RPC.")
            exit(1)
    else:
        print(f"Failed to fetch token symbol. Status code: {response.status_code}")
        exit(1)

if __name__ == '__main__':
    if (len(sys.argv) != 4):
        print("Usage: python getBalance.py <rpc_url> <token0_address> <token1_address>")
        exit(1)
    
    rpc_url = sys.argv[1]
    token0_address = sys.argv[2]
    token1_address = sys.argv[3]
    
    token0_symbol = get_token_symbol_from_rpc(rpc_url, token0_address).strip()
    token1_symbol = get_token_symbol_from_rpc(rpc_url, token1_address).strip()
    
    fetch_token_price(token0_symbol, token1_symbol)