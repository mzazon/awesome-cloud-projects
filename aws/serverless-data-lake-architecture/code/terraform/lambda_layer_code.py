import json
import boto3
import uuid
import hashlib
from datetime import datetime
from typing import Dict, Any, List, Optional

class DataProcessor:
    def __init__(self):
        self.s3_client = boto3.client('s3')
        self.dynamodb = boto3.resource('dynamodb')
        self.events_client = boto3.client('events')

    def generate_process_id(self, source: str, timestamp: str) -> str:
        """Generate unique process ID"""
        data = f"{source}-{timestamp}-{uuid.uuid4()}"
        return hashlib.md5(data.encode()).hexdigest()

    def validate_json_structure(self, data: Dict[str, Any], 
                              required_fields: List[str]) -> bool:
        """Validate JSON data structure"""
        return all(field in data for field in required_fields)

    def calculate_data_quality_score(self, data: Dict[str, Any]) -> float:
        """Calculate data quality score based on completeness"""
        total_fields = len(data)
        non_null_fields = sum(1 for v in data.values() if v is not None and v != "")
        return (non_null_fields / total_fields) * 100 if total_fields > 0 else 0

    def publish_custom_event(self, event_bus: str, source: str, 
                           detail_type: str, detail: Dict[str, Any]):
        """Publish custom event to EventBridge"""
        self.events_client.put_events(
            Entries=[
                {
                    'Source': source,
                    'DetailType': detail_type,
                    'Detail': json.dumps(detail),
                    'EventBusName': event_bus
                }
            ]
        )

    def store_metadata(self, table_name: str, process_id: str, metadata: Dict[str, Any]):
        """Store processing metadata in DynamoDB"""
        table = self.dynamodb.Table(table_name)
        item = {
            'ProcessId': process_id,
            'Timestamp': datetime.utcnow().isoformat(),
            **metadata
        }
        table.put_item(Item=item)

class DataValidator:
    @staticmethod
    def is_valid_email(email: str) -> bool:
        import re
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None

    @staticmethod
    def is_valid_phone(phone: str) -> bool:
        import re
        pattern = r'^\+?1?[2-9]\d{2}[2-9]\d{2}\d{4}$'
        return re.match(pattern, phone.replace('-', '').replace(' ', '')) is not None

    @staticmethod
    def is_valid_date_format(date_str: str, format: str = '%Y-%m-%d') -> bool:
        try:
            datetime.strptime(date_str, format)
            return True
        except ValueError:
            return False