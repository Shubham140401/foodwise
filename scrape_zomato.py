import json
import time
import os

try:
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
except ImportError:
    print("Installing selenium...")
    os.system("pip install selenium")
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options

folder = r"c:\Users\SRUTHI\OneDrive - NATIONAL INSTITUTE OF TECHNOLOGY HAMIRPUR HP\Desktop\New folder"

options = Options()
options.add_argument("--start-maximized")

print("Opening a new Chrome window...")
driver = webdriver.Chrome(options=options)
driver.get("https://www.zomato.com")

print("\nPlease log into Zomato in the browser that just opened.")
input("Press ENTER here once you are logged in...\n")

all_orders = {}
total_pages = None
page = 1

try:
    while True:
        url = f"https://www.zomato.com/webroutes/user/orders?page={page}"
        print(f"Fetching page {page}{f' of {total_pages}' if total_pages else ''}...")
        driver.get(url)
        time.sleep(2)

        # Get the raw JSON text from the page
        raw = driver.execute_script("return document.body.innerText")

        try:
            data = json.loads(raw)
        except Exception:
            print(f"  Could not parse JSON on page {page}. Raw: {raw[:200]}")
            break

        section = data.get("sections", {}).get("SECTION_USER_ORDER_HISTORY", {})
        order_entities = data.get("entities", {}).get("ORDER", {})

        if total_pages is None:
            total_pages = section.get("totalPages", 1)
            print(f"  Total pages: {total_pages}")

        if not order_entities:
            print("  No orders on this page.")
            break

        all_orders.update(order_entities)
        print(f"  Got {len(order_entities)} orders | Total so far: {len(all_orders)}")

        if page >= total_pages:
            print("All pages fetched.")
            break

        page += 1
        time.sleep(1)

finally:
    driver.quit()

output = {
    "sections": {
        "SECTION_USER_ORDER_HISTORY": {
            "count": len(all_orders),
            "totalPages": total_pages,
        }
    },
    "entities": {
        "ORDER": all_orders
    }
}

output_path = os.path.join(folder, "zomato.html")
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"\nDone! {len(all_orders)} total orders saved to zomato.html")
print("Now run zomato_to_csv.py to generate the CSV.")
