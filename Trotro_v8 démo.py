import cv2
import csv
import os
import sys
from datetime import datetime

def scan_qr_ticket(image_path):
    """Scans QR using OpenCV - no zbar needed"""
    try:
        img = cv2.imread(image_path)
        detector = cv2.QRCodeDetector()
        
        data, bbox, _ = detector.detectAndDecode(img)
        
        if data:
            parts = data.split('|') # REALME|T33377|A24|Ho-Accra|60.0|time
            ticket_id = parts[1]
            seat = parts[2]
            route = parts[3]
            fare = parts[4]
            time = parts[5]
            return [ticket_id, seat, route, fare, time]
        else:
            print("No QR code found in image")
            return None
    except Exception as e:
        print(f"Scan error: {e}")
        return None

def save_to_csv(data, csv_file='trotro_report.csv'):
    file_exists = os.path.isfile(csv_file)
    with open(csv_file, 'a', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(['Ticket ID', 'Seat', 'Route', 'Fare', 'Time'])
        writer.writerow(data)
    print(f"Saved to {csv_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scanner.py path/to/qr_image.jpg")
        sys.exit(1)

    image_path = sys.argv[1]
    result = scan_qr_ticket(image_path)

    if result:
        print(f"Scanned: {result}")
        save_to_csv(result)
        print("Done boss! ✅")
    else:
        print("Scan failed ❌")