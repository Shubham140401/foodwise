import json
import csv
import sys

input_path = r"c:\Users\SRUTHI\OneDrive - NATIONAL INSTITUTE OF TECHNOLOGY HAMIRPUR HP\Desktop\New folder\input.html"
output_path = r"c:\Users\SRUTHI\OneDrive - NATIONAL INSTITUTE OF TECHNOLOGY HAMIRPUR HP\Desktop\New folder\orders.csv"

with open(input_path, "r", encoding="utf-8") as f:
    data = json.load(f)

orders = data.get("data", {}).get("orders", [])
print(f"Total orders found: {len(orders)}")

fieldnames = [
    "order_id",
    "order_time",
    "order_status",
    "restaurant_name",
    "restaurant_locality",
    "restaurant_city",
    "items",
    "item_total",
    "packing_charges",
    "delivery_charges",
    "order_discount",
    "coupon_applied",
    "order_tax",
    "order_total",
    "payment_method",
    "delivery_person",
    "delivery_time_mins",
    "sla_time_mins",
    "on_time",
]

with open(output_path, "w", newline="", encoding="utf-8") as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()

    for order in orders:
        items_list = []
        for item in order.get("order_items", []):
            name = item.get("name", "")
            qty = item.get("quantity", "1")
            price = item.get("total", "")
            variant = ""
            variants = item.get("variants", [])
            if variants:
                variant = variants[0].get("name", "")
            if variant:
                items_list.append(f"{name} ({variant}) x{qty} @{price}")
            else:
                items_list.append(f"{name} x{qty} @{price}")

        delivery_secs = order.get("delivery_time_in_seconds", 0)
        try:
            delivery_mins = round(int(delivery_secs) / 60, 1)
        except (ValueError, TypeError):
            delivery_mins = ""

        delivery_boy = order.get("delivery_boy", {})
        delivery_name = delivery_boy.get("name", "") if delivery_boy else ""

        charges = order.get("charges", {})
        packing = charges.get("Packing Charges", "0")
        delivery = charges.get("Delivery Charges", "0")

        row = {
            "order_id": order.get("order_id", ""),
            "order_time": order.get("order_time", ""),
            "order_status": order.get("order_status", ""),
            "restaurant_name": order.get("restaurant_name", ""),
            "restaurant_locality": order.get("restaurant_locality", ""),
            "restaurant_city": order.get("restaurant_city_name", ""),
            "items": " | ".join(items_list),
            "item_total": order.get("item_total", ""),
            "packing_charges": packing,
            "delivery_charges": delivery,
            "order_discount": order.get("order_discount", ""),
            "coupon_applied": order.get("coupon_applied", ""),
            "order_tax": order.get("order_tax", ""),
            "order_total": order.get("order_total", ""),
            "payment_method": order.get("payment_method", ""),
            "delivery_person": delivery_name,
            "delivery_time_mins": delivery_mins,
            "sla_time_mins": order.get("sla_time", ""),
            "on_time": order.get("on_time", ""),
        }
        writer.writerow(row)

print(f"CSV saved to: {output_path}")
