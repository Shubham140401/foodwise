import requests
import json
import time

# HOW TO GET THIS:
# 1. Open Chrome, go to zomato.com, log in
# 2. Press F12 -> Network tab -> go to Orders page on Zomato
# 3. Click any request with "orders" in the name
# 4. Scroll to "Request Headers" -> find the "cookie:" line
# 5. Copy the ENTIRE value and paste it below between the triple quotes
COOKIE_STRING = """PASTE_ENTIRE_COOKIE_STRING_HERE"""

def parse_cookie_string(cookie_str):
    cookies = {}
    for part in cookie_str.strip().split(";"):
        part = part.strip()
        if "=" in part:
            key, _, value = part.partition("=")
            cookies[key.strip()] = value.strip()
    return cookies

COOKIES = parse_cookie_string(COOKIE_STRING)

session = requests.Session()
session.cookies.update(COOKIES)
session.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Referer": "https://www.zomato.com/orders",
    "Accept": "application/json, text/plain, */*",
    "x-zomato-csrft": COOKIES.get("csrf", ""),
})

def fetch_orders(page=1):
    url = f"https://www.zomato.com/webroutes/user/orders?page={page}"
    response = session.get(url)
    print(f"  Status: {response.status_code}")
    if response.status_code == 200:
        try:
            return response.json()
        except Exception:
            print(f"  Could not parse JSON: {response.text[:300]}")
            return None
    else:
        print(f"  Error {response.status_code}: {response.text[:300]}")
        return None

all_orders = []
page = 1

while True:
    print(f"Fetching page {page}...")
    data = fetch_orders(page)

    if not data:
        break

    # Zomato wraps orders in sections
    section = data.get("sections", {}).get("SECTION_USER_ORDER_HISTORY", {})
    order_entities = section.get("entities", {}).get("ORDER", {})
    order_history = section.get("orderHistory", [])

    if not order_history:
        print("No more orders found.")
        break

    # Attach full order details from entities
    for entry in order_history:
        order_id = str(entry.get("entityId", ""))
        order_detail = order_entities.get(order_id, {})
        merged = {**entry, **order_detail}
        all_orders.append(merged)

    print(f"  Got {len(order_history)} orders | Total so far: {len(all_orders)}")

    if len(order_history) < 10:
        print("Last page reached.")
        break

    page += 1
    time.sleep(1)

output = {"orders": all_orders}
output_path = r"c:\Users\SRUTHI\OneDrive - NATIONAL INSTITUTE OF TECHNOLOGY HAMIRPUR HP\Desktop\New folder\zomato_input.json"
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"\nDone! {len(all_orders)} total orders saved to zomato_input.json")
print("Now run zomato_to_csv.py to generate the CSV.")
