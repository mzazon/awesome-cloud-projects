#!/usr/bin/env python3
"""
Test Data Producer for Real-Time Event Processing Pipeline

This script generates realistic retail event data and sends it to a Kinesis Data Stream
for testing the real-time processing pipeline.

Usage:
    python3 test_data_producer.py <stream_name> [event_count] [delay_seconds]

Examples:
    python3 test_data_producer.py ${kinesis_stream_name} 100 0.1
    python3 test_data_producer.py ${kinesis_stream_name} 1000 0.05
"""

import boto3
import json
import uuid
import time
import random
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional

# Initialize Kinesis client
kinesis = boto3.client('kinesis', region_name='${aws_region}')

# Sample data for realistic event generation
EVENT_TYPES = [
    'view',         # 60% of events
    'add_to_cart',  # 20% of events
    'purchase',     # 10% of events
    'wishlist',     # 5% of events
    'share',        # 3% of events
    'review'        # 2% of events
]

EVENT_WEIGHTS = [60, 20, 10, 5, 3, 2]

# Sample product catalog
PRODUCT_CATEGORIES = {
    'electronics': ['smartphone', 'laptop', 'tablet', 'headphones', 'smartwatch'],
    'clothing': ['shirt', 'pants', 'dress', 'shoes', 'jacket'],
    'home': ['furniture', 'kitchen', 'garden', 'decor', 'appliances'],
    'books': ['fiction', 'non-fiction', 'textbook', 'cookbook', 'biography'],
    'sports': ['equipment', 'apparel', 'supplements', 'accessories', 'footwear']
}

PRODUCT_IDS = []
for category, subcategories in PRODUCT_CATEGORIES.items():
    for subcategory in subcategories:
        for i in range(1, 21):  # 20 products per subcategory
            PRODUCT_IDS.append(f"{category}-{subcategory}-{i:03d}")

# Generate realistic user base
USER_PROFILES = []
for i in range(100):
    profile = {
        'userId': f'user-{uuid.uuid4()}',
        'userType': random.choice(['new', 'returning', 'premium']),
        'location': random.choice(['US', 'CA', 'UK', 'DE', 'FR', 'AU', 'JP']),
        'ageGroup': random.choice(['18-25', '26-35', '36-45', '46-55', '55+']),
        'preferredCategory': random.choice(list(PRODUCT_CATEGORIES.keys()))
    }
    USER_PROFILES.append(profile)

# User agents for realistic traffic simulation
USER_AGENTS = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15',
    'Mozilla/5.0 (Android 11; Mobile; rv:91.0) Gecko/91.0 Firefox/91.0',
    'Mozilla/5.0 (iPad; CPU OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15'
]

class RetailEventGenerator:
    """Generates realistic retail events for testing the data pipeline."""
    
    def __init__(self):
        self.session_cache = {}  # Cache sessions for users
        self.product_trends = {}  # Track trending products
        
    def generate_event(self, user_profile: Optional[Dict] = None) -> Dict:
        """
        Generate a single realistic retail event.
        
        Args:
            user_profile: Optional user profile to generate event for
            
        Returns:
            Dictionary containing event data
        """
        # Select user profile
        if not user_profile:
            user_profile = random.choice(USER_PROFILES)
        
        user_id = user_profile['userId']
        
        # Get or create session for user
        session_id = self._get_or_create_session(user_id)
        
        # Select event type based on weights (more views than purchases)
        event_type = random.choices(EVENT_TYPES, weights=EVENT_WEIGHTS)[0]
        
        # Select product based on user preferences and trends
        product_id = self._select_product(user_profile, event_type)
        
        # Generate realistic timestamp (recent events)
        timestamp = int(time.time() * 1000) - random.randint(0, 3600000)  # Within last hour
        
        # Create the event
        event = {
            'userId': user_id,
            'eventType': event_type,
            'productId': product_id,
            'timestamp': timestamp,
            'sessionId': session_id,
            'userAgent': random.choice(USER_AGENTS),
            'ipAddress': self._generate_ip_address(),
            'metadata': {
                'userType': user_profile['userType'],
                'location': user_profile['location'],
                'ageGroup': user_profile['ageGroup'],
                'referrer': self._generate_referrer(),
                'platform': self._extract_platform(random.choice(USER_AGENTS))
            }
        }
        
        # Add event-specific data
        if event_type == 'purchase':
            event['price'] = round(random.uniform(10.0, 500.0), 2)
            event['currency'] = 'USD'
            event['quantity'] = random.randint(1, 3)
            
        elif event_type == 'add_to_cart':
            event['quantity'] = random.randint(1, 5)
            
        elif event_type == 'review':
            event['rating'] = random.randint(1, 5)
            
        return event
    
    def _get_or_create_session(self, user_id: str) -> str:
        """Get existing session or create new one for user."""
        now = time.time()
        
        # Check if user has active session (within 30 minutes)
        if user_id in self.session_cache:
            session_data = self.session_cache[user_id]
            if now - session_data['created'] < 1800:  # 30 minutes
                return session_data['session_id']
        
        # Create new session
        session_id = str(uuid.uuid4())
        self.session_cache[user_id] = {
            'session_id': session_id,
            'created': now
        }
        
        return session_id
    
    def _select_product(self, user_profile: Dict, event_type: str) -> str:
        """Select product based on user preferences and event type."""
        # 70% chance to select from preferred category
        if random.random() < 0.7:
            preferred_category = user_profile['preferredCategory']
            category_products = [p for p in PRODUCT_IDS if p.startswith(preferred_category)]
            if category_products:
                return random.choice(category_products)
        
        # Random product selection
        return random.choice(PRODUCT_IDS)
    
    def _generate_ip_address(self) -> str:
        """Generate a realistic IP address."""
        return f"{random.randint(1, 223)}.{random.randint(1, 255)}.{random.randint(1, 255)}.{random.randint(1, 255)}"
    
    def _generate_referrer(self) -> str:
        """Generate a realistic referrer URL."""
        referrers = [
            'https://www.google.com/search',
            'https://www.facebook.com/',
            'https://www.instagram.com/',
            'https://www.youtube.com/',
            'https://direct',
            'https://newsletter.email/',
            'https://partner-site.com/'
        ]
        return random.choice(referrers)
    
    def _extract_platform(self, user_agent: str) -> str:
        """Extract platform from user agent string."""
        if 'iPhone' in user_agent or 'iPad' in user_agent:
            return 'iOS'
        elif 'Android' in user_agent:
            return 'Android'
        elif 'Windows' in user_agent:
            return 'Windows'
        elif 'Macintosh' in user_agent:
            return 'macOS'
        else:
            return 'Unknown'

def put_record_to_stream(stream_name: str, record: Dict) -> Dict:
    """
    Send a single record to the Kinesis stream.
    
    Args:
        stream_name: Name of the Kinesis stream
        record: Event record to send
        
    Returns:
        Kinesis put_record response
    """
    try:
        result = kinesis.put_record(
            StreamName=stream_name,
            Data=json.dumps(record),
            PartitionKey=record['userId']  # Distribute by user for even sharding
        )
        return result
    except Exception as e:
        print(f"Error sending record to Kinesis: {e}")
        raise

def put_records_batch(stream_name: str, records: List[Dict]) -> Dict:
    """
    Send multiple records to Kinesis in a batch for better performance.
    
    Args:
        stream_name: Name of the Kinesis stream
        records: List of event records to send
        
    Returns:
        Kinesis put_records response
    """
    kinesis_records = []
    for record in records:
        kinesis_records.append({
            'Data': json.dumps(record),
            'PartitionKey': record['userId']
        })
    
    try:
        result = kinesis.put_records(
            StreamName=stream_name,
            Records=kinesis_records
        )
        return result
    except Exception as e:
        print(f"Error sending batch to Kinesis: {e}")
        raise

def generate_burst_traffic(stream_name: str, generator: RetailEventGenerator, duration_seconds: int = 30):
    """
    Generate burst traffic to test auto-scaling capabilities.
    
    Args:
        stream_name: Name of the Kinesis stream
        generator: Event generator instance
        duration_seconds: Duration of burst traffic
    """
    print(f"Generating burst traffic for {duration_seconds} seconds...")
    start_time = time.time()
    total_sent = 0
    
    while time.time() - start_time < duration_seconds:
        # Send batch of events every 0.1 seconds
        batch = []
        for _ in range(10):  # 10 events per batch
            event = generator.generate_event()
            batch.append(event)
        
        result = put_records_batch(stream_name, batch)
        total_sent += len(batch)
        
        # Check for failed records
        if result.get('FailedRecordCount', 0) > 0:
            print(f"Warning: {result['FailedRecordCount']} records failed in batch")
        
        time.sleep(0.1)
    
    print(f"Burst traffic complete. Sent {total_sent} events in {duration_seconds} seconds")

def main(stream_name: str, count: int = 100, delay: float = 0.1, burst_mode: bool = False):
    """
    Main function to generate and send events to Kinesis.
    
    Args:
        stream_name: Name of the Kinesis stream
        count: Number of events to generate
        delay: Delay between events in seconds
        burst_mode: Whether to use burst mode for testing
    """
    print(f"Starting event generation...")
    print(f"Stream: {stream_name}")
    print(f"Events: {count}")
    print(f"Delay: {delay} seconds")
    print(f"Burst mode: {burst_mode}")
    print("-" * 50)
    
    generator = RetailEventGenerator()
    
    if burst_mode:
        generate_burst_traffic(stream_name, generator, duration_seconds=30)
        return
    
    # Generate and send events
    success_count = 0
    error_count = 0
    
    for i in range(count):
        try:
            event = generator.generate_event()
            result = put_record_to_stream(stream_name, event)
            success_count += 1
            
            # Print progress every 10 events
            if (i + 1) % 10 == 0 or i == count - 1:
                print(f"Sent {i + 1}/{count} events (Success: {success_count}, Errors: {error_count})")
            
            # Add delay to prevent throttling
            if delay > 0:
                time.sleep(delay)
                
        except Exception as e:
            error_count += 1
            print(f"Error sending event {i + 1}: {e}")
    
    print("-" * 50)
    print(f"Event generation complete!")
    print(f"Total events: {count}")
    print(f"Successful: {success_count}")
    print(f"Failed: {error_count}")
    print(f"Success rate: {(success_count / count * 100):.1f}%")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 test_data_producer.py <stream_name> [event_count] [delay_seconds] [--burst]")
        print("Examples:")
        print("  python3 test_data_producer.py my-stream 100 0.1")
        print("  python3 test_data_producer.py my-stream 1000 0.05")
        print("  python3 test_data_producer.py my-stream 0 0 --burst")
        sys.exit(1)
    
    stream_name = sys.argv[1]
    event_count = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    delay_seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 0.1
    burst_mode = '--burst' in sys.argv
    
    try:
        main(stream_name, event_count, delay_seconds, burst_mode)
    except KeyboardInterrupt:
        print("\nEvent generation interrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)