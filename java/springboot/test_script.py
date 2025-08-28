#!/usr/bin/env python3
"""
Test script for Spring Boot OpenTelemetry Demo
This script will run all endpoints in a loop to generate telemetry data
"""

import requests
import time
import random
import json
from typing import Dict, Any, Optional
import sys

class SpringBootTester:
    def __init__(self, base_url: str = "http://localhost:8080", delay: int = 2, loop_count: int = 10):
        self.base_url = base_url
        self.delay = delay
        self.loop_count = loop_count
        self.session = requests.Session()
        
    def make_request(self, method: str, endpoint: str, data: Optional[Dict] = None, description: str = "") -> bool:
        """Make HTTP request and display result"""
        url = f"{self.base_url}{endpoint}"
        
        print(f"🔄 Testing: {description}")
        print(f"   Endpoint: {method} {endpoint}")
        
        try:
            if method.upper() == "GET":
                response = self.session.get(url, timeout=10)
            elif method.upper() == "POST":
                response = self.session.post(url, json=data, timeout=10)
            else:
                print(f"❌ Unsupported method: {method}")
                return False
            
            if 200 <= response.status_code < 300:
                print(f"✅ Success ({response.status_code})")
                try:
                    response_data = response.json()
                    print(f"   Response: {json.dumps(response_data, indent=2)}")
                except:
                    print(f"   Response: {response.text[:200]}...")
            else:
                print(f"❌ Failed ({response.status_code})")
                print(f"   Response: {response.text[:200]}...")
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Request failed: {e}")
            return False
        
        print()
        return True
    
    def run_test_cycle(self, cycle: int) -> None:
        """Run one complete test cycle"""
        print(f"🔄 === Test Cycle {cycle}/{self.loop_count} ===")
        print()
        
        # Test GET endpoints
        self.make_request("GET", "/api/hello", description="Hello World Endpoint")
        time.sleep(self.delay)
        
        self.make_request("GET", "/api/health", description="Health Check Endpoint")
        time.sleep(self.delay)
        
        self.make_request("GET", "/api/products", description="Get Products Endpoint")
        time.sleep(self.delay)
        
        self.make_request("GET", "/api/products?limit=5", description="Get Products with Limit")
        time.sleep(self.delay)
        
        # Test user endpoints with different IDs
        user_id = random.randint(1, 100)
        self.make_request("GET", f"/api/users/{user_id}", description=f"Get User by ID ({user_id})")
        time.sleep(self.delay)
        
        # Test POST endpoint
        user_name = f"TestUser{cycle}"
        user_email = f"testuser{cycle}@example.com"
        post_data = {"name": user_name, "email": user_email}
        self.make_request("POST", "/api/users", data=post_data, description="Create User")
        time.sleep(self.delay)
        
        # Test error endpoint (this will fail, which is expected)
        self.make_request("GET", "/api/error-demo", description="Error Demo Endpoint (Expected to fail)")
        time.sleep(self.delay)
        
        # Test actuator endpoints
        self.make_request("GET", "/actuator/health", description="Actuator Health")
        time.sleep(self.delay)
        
        self.make_request("GET", "/actuator/metrics", description="Actuator Metrics")
        time.sleep(self.delay)
        
        print(f"✅ Completed Test Cycle {cycle}")
        print()
    
    def check_application_running(self) -> bool:
        """Check if the application is running"""
        print("🔍 Checking if application is running...")
        try:
            response = self.session.get(f"{self.base_url}/api/health", timeout=5)
            if response.status_code == 200:
                print("✅ Application is running")
                return True
            else:
                print("❌ Application is not responding correctly")
                return False
        except requests.exceptions.RequestException:
            print("❌ Application is not running. Please start the Spring Boot application first.")
            print("   You can start it with: ./start_app.sh")
            return False
    
    def run(self) -> None:
        """Run the complete test suite"""
        print("🚀 Starting Spring Boot Application Test Script")
        print(f"   Base URL: {self.base_url}")
        print(f"   Loop Count: {self.loop_count}")
        print(f"   Delay between requests: {self.delay}s")
        print()
        
        # Check if application is running
        if not self.check_application_running():
            sys.exit(1)
        
        print()
        
        # Run test cycles
        for i in range(1, self.loop_count + 1):
            self.run_test_cycle(i)
            
            # Add a longer delay between cycles
            if i < self.loop_count:
                print("⏳ Waiting 5 seconds before next cycle...")
                time.sleep(5)
                print()
        
        print("🎉 All test cycles completed!")
        print("📊 Check your OpenTelemetry collector/backend for telemetry data.")

def main():
    """Main function"""
    # Parse command line arguments
    base_url = "http://localhost:8080"
    delay = 2
    loop_count = 10
    
    if len(sys.argv) > 1:
        base_url = sys.argv[1]
    if len(sys.argv) > 2:
        delay = int(sys.argv[2])
    if len(sys.argv) > 3:
        loop_count = int(sys.argv[3])
    
    # Create and run tester
    tester = SpringBootTester(base_url, delay, loop_count)
    tester.run()

if __name__ == "__main__":
    main() 