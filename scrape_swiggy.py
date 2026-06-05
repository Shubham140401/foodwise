import requests
import json
import time

# HOW TO GET THIS:
# 1. Open Chrome, go to swiggy.com, log in
# 2. Press F12 -> Network tab -> go to Orders page on Swiggy
# 3. Click any request with "order" or "all" in the name
# 4. Scroll to "Request Headers" -> find the "cookie:" line
# 5. Copy the ENTIRE value and paste it below between the triple quotes
COOKIE_STRING = """__SW=qqmBIFw8JMBfnmFQZGJqNv40Lupaca40; _device_id=d1b37cd6-26fd-af10-ee06-b50c57da9e71; _gcl_au=1.1.959061029.1780557198; fontsLoaded=1; _gid=GA1.2.1311946781.1780557198; _is_logged_in=1; _session_tid=f3e95fbf7453de1e5059a3146c16f1e5939c614cda7f6d5311e39dc8f0ba6b7fd4efb1933ccd480a13f22698191cfda6aed1cf2fc79beb9bb2a9b8067c8e62b75bd59bff377519f7c6fde7a8d373748fa974403c9c20cc63aed0cd11f00d34dd7f75fde9356b346e07491f2d6fa437294ca8e8f9f295b94b3e62dfc0907ecc08cad20650cf44d5d01dde29ed28f9563d4f647666e4087c3194516c41d03b7f29b0cb9487980cbdfecfd9ec8c58987925fca3d842a38b0c8cbf9ab294d875b205cd3a3f354462e07c8abcab49867098f79d70a176cefa39f6a614fccd7be3991341c1252088a87b975c9313da077ce2317f8488a291a494baec6e5d11fa444c709082ee193be2fa52a61578c624d84d008c2d39bb585b12990a0df13308b64b114f94411613c7d2d43f295ecba0b66289de45934679e76f291f7b56331d1c6739b87e1f53fae18025285259c823fa492bd24a247ba4d934b01330bafda1e4304bfb35cb10877a916151c7eaa0deb0f27e6237f1bbfa8028cc2164b53b0bdefd65057761ad31704470246ed6caf4da225249af3b8ce63624ab3fcc2c0572314c2d440c5b7983e294777f40e0712c49fac31328188c985c9e37925523aefa617e3bc2999c73d8e10b2bbd80c42dd086cdf455d6c72512bfe6b01640601db5147765e2a92d1c9f22017e65f437958ab0d6f9788abd351177ed2a0697d8b52abd71bf7498ee8be0e5386adba35b5b04411f8188fb7da122010e8906b5d8dd1c3361e0d29523f170f3a729858a562e387067d08287d6fb09a3a3aeb27d6b171cba86f3183d82207e0bdf6bdf632e5c58445fd820df7096d368f3347eef2b7f9007b95d8f9939dcfac0678b55ddfb8adecd54981d290ca55b08921c30d0058ed2d37044e0386e3f4c70ee1a794cee3da06fa602a3693f7d3b9dcc8c94ca789153d7e4c9b283acf413584bc95b2e40af11f543c662e3871d5aa4321ff353761b25d5f774701c19546c35a7595e87023fd8a6a6126764b7f5b7e6fcec7e4a5777ccbef92e4ca636638b60ab0a7cd0a382215d4586665948fcd8efb289a655de780ea3e3f107be04bcebfd5c7b1357d3efe4ede1a9fe8042bf1e281a48ff851e75fe92eccd07068a1ba9c82ad03b26cb5926c25f90c1009e50ff1797ec1e2d2777a63d4580f91c07170dc5f58b6513ec675d968875eede3b06e6765139cd4c84c10b0f6b59800b0f561d1c9d7027e63100267d0062987428cdfe93a033852b05b01661f46547d12cb1f113ef06893d3eb358f3ef4ef1899cf09983025b2c0ea94385c6258f837d9d82dee5dc62e4da5d15ee17712e; _sid=rqdff7b8d50-fc11-49b8-8840-9a021a931; _ga_YE38MFJRBZ=GS2.1.s1780585530$o4$g1$t1780585898$j60$l0$h0; _ga_34JYJ0BCRN=GS2.1.s1780585530$o4$g1$t1780585898$j60$l0$h0; userLocation={%22lat%22:%2218.5508392%22%2C%22lng%22:%2273.8895519%22%2C%22address%22:%22Airport%20Road%2C%20Jayprakash%20Naga%2C%20Yerawada%2C%20Pune%2C%20Maharashtra%20411006%2C%20India%20(Business%20Bay)%22%2C%22area%22:%22%22%2C%22showUserDefaultAddressHint%22:false}; aws-waf-token=ebf5d4de-4e71-4ee2-909d-deae1d089c48:HgoAdzdqtHCDAAAA:Sk0M0hVFaBK+fvyjTuRXlU6rNrmltaC8HPmvvCHFoYOfyhIBp07UQYAetxlMgTeZHnWdi4skhF0zjbnZpwEY6bFqYBySmFUH13QIhHtY5Lnc2MiIztWx47dVp5Y/PTU1MZsU37nG+d9WD/BcZHQDtjYN30FZ89npx+c6rf5B5HeaUTaDpQHfyp91vhhf7QkvGkJVQ3ej+cJFv4QcqbmNvcIdgAGt4/wAnlGs5+7LuWNuJjqdOJUa; _ga=GA1.2.1045516560.1780557198; _gat_0=1"""

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
    "Referer": "https://www.swiggy.com/my-account/orders",
    "Accept": "application/json, text/plain, */*",
    "content-type": "application/json",
})

# Step 1: fetch csrfToken from Swiggy homepage
print("Fetching csrfToken...")
home = session.get("https://www.swiggy.com/dapi/restaurants/list/v5?lat=18.5508392&lng=73.8895519&is-seo-homepage-enabled=true&page_type=DESKTOP_WEB_LISTING")
csrf_token = session.cookies.get("csrfToken", "")
if not csrf_token:
    try:
        csrf_token = home.json().get("csrfToken", "")
    except Exception:
        pass
print(f"  csrfToken: {csrf_token[:30]}..." if csrf_token else "  csrfToken not found, trying anyway...")
session.headers.update({"csrfToken": csrf_token})

def fetch_orders(order_id=""):
    url = f"https://www.swiggy.com/dapi/order/all?order_id={order_id}"
    response = session.get(url)
    print(f"  Status: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        if data.get("statusCode") != 0:
            print(f"  API error: {json.dumps(data)[:300]}")
            return None
        return data
    else:
        print(f"  Error {response.status_code}: {response.text[:300]}")
        return None

all_orders = []
last_order_id = ""
page = 1

while True:
    print(f"Fetching page {page} (last order_id: {last_order_id or 'none'})...")
    data = fetch_orders(last_order_id)

    if not data:
        break

    orders = data.get("data", {}).get("orders", [])
    if not orders:
        print("No more orders found.")
        break

    all_orders.extend(orders)
    print(f"  Got {len(orders)} orders | Total so far: {len(all_orders)}")

    last_order_id = orders[-1].get("order_id", "")
    if not last_order_id:
        break

    page += 1
    time.sleep(1)

output = {"statusCode": 0, "data": {"orders": all_orders}}
output_path = r"c:\Users\SRUTHI\OneDrive - NATIONAL INSTITUTE OF TECHNOLOGY HAMIRPUR HP\Desktop\New folder\input.html"
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"\nDone! {len(all_orders)} total orders saved to input.html")
print("Now run convert_to_csv.py to generate the CSV.")
