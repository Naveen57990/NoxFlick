#!/usr/bin/env python3
import sys
import os
import time
import urllib.request
import urllib.parse
import json

SERVER_PORT = 52840
BASE_URL = f"http://127.0.0.1:{SERVER_PORT}"

def check_server():
    print(f"🔍 Pinging Flik Connector at {BASE_URL}/ping...")
    try:
        req = urllib.request.Request(f"{BASE_URL}/ping")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode())
            print(f"✅ Connected to: {data.get('deviceName')} (Status: {data.get('status')})")
            return True
    except Exception as e:
        print(f"⚠️ Server not reachable on port {SERVER_PORT}: {e}")
        return False

def send_test_file(file_path, angle=0.0, velocity=1.5):
    if not os.path.exists(file_path):
        print(f"❌ File not found: {file_path}")
        return
    
    file_name = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    
    print(f"🚀 Flicking '{file_name}' ({file_size} bytes) at angle {angle}°...")
    
    with open(file_path, 'rb') as f:
        file_bytes = f.read()
    
    req = urllib.request.Request(f"{BASE_URL}/transfer", data=file_bytes, method='POST')
    req.add_header('X-File-Name', urllib.parse.quote(file_name))
    req.add_header('X-File-Size', str(file_size))
    req.add_header('X-Mime-Type', 'image/png' if file_name.endswith('.png') else 'application/octet-stream')
    req.add_header('X-Flick-Angle', str(angle))
    req.add_header('X-Flick-Velocity', str(velocity))
    req.add_header('X-Sender-Name', "Android Device")
    req.add_header('Content-Type', 'application/octet-stream')
    req.add_header('Content-Length', str(file_size))
    
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode())
            print(f"🎉 Delivery complete! Server response: {result}")
    except Exception as e:
        print(f"❌ Transfer failed: {e}")

def send_test_link(url):
    print(f"🔗 Flicking link: {url}...")
    payload = json.dumps({"url": url, "senderName": "Android Device"}).encode()
    req = urllib.request.Request(f"{BASE_URL}/link", data=payload, method='POST')
    req.add_header('Content-Type', 'application/json')
    req.add_header('Content-Length', str(len(payload)))
    
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            result = json.loads(resp.read().decode())
            print(f"🎉 Link delivered! Browser opened.")
    except Exception as e:
        print(f"❌ Link transfer failed: {e}")

if __name__ == '__main__':
    # Create sample image if needed
    sample_img = "/tmp/flik_demo_polaroid.png"
    import subprocess
    subprocess.run([
        'python3', '-c', 
        '''
import os
# create a simple PNG
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 300), color=(30, 144, 255))
draw = ImageDraw.Draw(img)
draw.rectangle([20, 20, 380, 280], outline=(255, 255, 255), width=4)
img.save('/tmp/flik_demo_polaroid.png')
'''
    ], stderr=subprocess.DEVNULL)
    
    if not os.path.exists(sample_img):
        # fallback create dummy file
        with open(sample_img, 'wb') as f:
            f.write(b'Demo file content')
            
    if check_server():
        send_test_file(sample_img, angle=12.5, velocity=1.8)
    else:
        print("💡 Launch 'Flik Connector.app' first, then re-run this script!")
