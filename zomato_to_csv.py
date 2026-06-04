import json
import csv
import glob
import os

folder = r"c:\Users\SRUTHI\OneDrive - NATIONAL INSTITUTE OF TECHNOLOGY HAMIRPUR HP\Desktop\New folder"
output_path = os.path.join(folder, "zomato_orders.csv")

# Reads zomato.html and any additional pages: zomato2.html, zomato3.html etc.
input_files = sorted(glob.glob(os.path.join(folder, "zomato*.html")))
print(f"Found input files: {[os.path.basename(f) for f in input_files]}")

STATUS_MAP = {
    1: "Payment Incomplete",
    3: "Cancelled",
    4: "Cancelled",
    6: "Delivered",
    8: "Cancelled / Refund",
}

all_orders = []

for filepath in input_files:
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)

    section = data.get("sections", {}).get("SECTION_USER_ORDER_HISTORY", {})
    order_entities = data.get("entities", {}).get("ORDER", {})

    for order_id_str, order in order_entities.items():
        all_orders.append(order)

print(f"Total orders found: {len(all_orders)}")

fieldnames = [
    "order_id",
    "order_date",
    "order_status",
    "restaurant_name",
    "locality",
    "city",
    "items",
    "order_total",
    "delivery_address",
    "rating",
]

with open(output_path, "w", newline="", encoding="utf-8") as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()

    for order in all_orders:
        status_code = order.get("status", 0)
        status_label = order.get("deliveryDetails", {}).get("deliveryLabel", "")
        if not status_label:
            status_label = STATUS_MAP.get(status_code, str(status_code))

        res = order.get("resInfo", {})
        locality_info = res.get("locality", {})

        total_cost = order.get("totalCost", "")
        total_cost = total_cost.replace("₹", "").strip()  # remove ₹ symbol

        rating = order.get("ratingV2", "")
        if rating == "-":
            rating = ""

        row = {
            "order_id": order.get("orderId", ""),
            "order_date": order.get("orderDate", ""),
            "order_status": status_label,
            "restaurant_name": res.get("name", ""),
            "locality": locality_info.get("localityName", ""),
            "city": locality_info.get("addressString", "").split(",")[-1].strip(),
            "items": order.get("dishString", ""),
            "order_total": total_cost,
            "delivery_address": order.get("deliveryDetails", {}).get("deliveryAddress", ""),
            "rating": rating,
        }
        writer.writerow(row)

print(f"CSV saved to: {output_path}")
