"""
Automated Expense Report Generator
Cloud Function for generating weekly/monthly expense reports
"""

import json
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List
import functions_framework
from google.cloud import storage
from google.cloud import sql
import io

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
BUCKET_NAME = "${bucket_name}"

def calculate_expense_metrics(expenses: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate comprehensive expense metrics and analytics"""
    
    if not expenses:
        return {
            "total_expenses": 0.0,
            "total_count": 0,
            "average_expense": 0.0,
            "categories": {},
            "approval_rate": 0.0,
            "policy_violations": 0
        }
    
    total_amount = sum(float(expense.get('total_amount', 0)) for expense in expenses)
    total_count = len(expenses)
    
    # Category breakdown
    categories = {}
    for expense in expenses:
        category = expense.get('category', 'uncategorized')
        if category not in categories:
            categories[category] = {'count': 0, 'amount': 0.0}
        categories[category]['count'] += 1
        categories[category]['amount'] += float(expense.get('total_amount', 0))
    
    # Approval rate
    approved_count = sum(1 for expense in expenses if expense.get('approval_status') == 'approved')
    approval_rate = (approved_count / total_count) if total_count > 0 else 0.0
    
    # Policy violations
    violation_count = sum(1 for expense in expenses if expense.get('policy_violations', 0) > 0)
    
    return {
        "total_expenses": round(total_amount, 2),
        "total_count": total_count,
        "average_expense": round(total_amount / total_count if total_count > 0 else 0, 2),
        "categories": categories,
        "approval_rate": round(approval_rate, 3),
        "policy_violations": violation_count,
        "approved_count": approved_count,
        "pending_count": total_count - approved_count
    }

def generate_expense_insights(metrics: Dict[str, Any]) -> List[str]:
    """Generate actionable insights from expense data"""
    
    insights = []
    
    # Category insights
    if metrics.get('categories'):
        top_category = max(metrics['categories'].items(), key=lambda x: x[1]['amount'])
        insights.append(f"Highest spending category: {top_category[0]} (${top_category[1]['amount']:.2f})")
        
        if len(metrics['categories']) > 1:
            category_amounts = [cat['amount'] for cat in metrics['categories'].values()]
            if max(category_amounts) > sum(category_amounts) * 0.6:
                insights.append("Spending is heavily concentrated in one category - consider budget rebalancing")
    
    # Approval rate insights
    approval_rate = metrics.get('approval_rate', 0)
    if approval_rate < 0.8:
        insights.append(f"Low approval rate ({approval_rate:.1%}) - review policy compliance training")
    elif approval_rate > 0.95:
        insights.append("High approval rate indicates good policy compliance")
    
    # Volume insights
    total_count = metrics.get('total_count', 0)
    if total_count > 100:
        insights.append("High expense volume - consider automation opportunities")
    
    # Average expense insights
    avg_expense = metrics.get('average_expense', 0)
    if avg_expense > 200:
        insights.append("High average expense amount - monitor for policy compliance")
    
    # Policy violation insights
    violation_rate = metrics.get('policy_violations', 0) / max(total_count, 1)
    if violation_rate > 0.1:
        insights.append(f"Policy violation rate ({violation_rate:.1%}) exceeds threshold - review training")
    
    return insights

def create_detailed_report(metrics: Dict[str, Any], insights: List[str]) -> Dict[str, Any]:
    """Create a comprehensive expense report"""
    
    report_date = datetime.now()
    period_start = report_date - timedelta(days=7)  # Weekly report
    
    report = {
        "report_metadata": {
            "generated_at": report_date.isoformat(),
            "report_type": "weekly_summary",
            "period_start": period_start.isoformat(),
            "period_end": report_date.isoformat(),
            "version": "1.1"
        },
        "executive_summary": {
            "total_expenses": metrics.get('total_expenses', 0),
            "total_transactions": metrics.get('total_count', 0),
            "average_transaction": metrics.get('average_expense', 0),
            "approval_rate": metrics.get('approval_rate', 0),
            "policy_compliance_rate": 1 - (metrics.get('policy_violations', 0) / max(metrics.get('total_count', 1), 1))
        },
        "category_breakdown": metrics.get('categories', {}),
        "key_insights": insights,
        "recommendations": [
            "Implement automated policy checks for high-risk categories",
            "Provide additional training for employees with multiple violations",
            "Consider raising approval thresholds for frequently approved categories",
            "Review vendor relationships for top spending categories"
        ],
        "compliance_metrics": {
            "total_violations": metrics.get('policy_violations', 0),
            "violation_rate": metrics.get('policy_violations', 0) / max(metrics.get('total_count', 1), 1),
            "pending_approvals": metrics.get('pending_count', 0),
            "auto_approved": metrics.get('approved_count', 0)
        }
    }
    
    return report

def mock_expense_data() -> List[Dict[str, Any]]:
    """Generate mock expense data for demonstration purposes"""
    
    # In a real implementation, this would query Cloud SQL
    mock_expenses = [
        {
            "id": 1,
            "employee_email": "john.doe@company.com",
            "vendor_name": "Business Hotel",
            "total_amount": 250.00,
            "category": "hotels",
            "approval_status": "approved",
            "policy_violations": 0
        },
        {
            "id": 2,
            "employee_email": "jane.smith@company.com",
            "vendor_name": "Client Lunch Restaurant",
            "total_amount": 85.50,
            "category": "meals",
            "approval_status": "pending",
            "policy_violations": 1  # Over daily limit
        },
        {
            "id": 3,
            "employee_email": "mike.johnson@company.com",
            "vendor_name": "Office Supply Store",
            "total_amount": 150.75,
            "category": "equipment",
            "approval_status": "approved",
            "policy_violations": 0
        },
        {
            "id": 4,
            "employee_email": "sarah.wilson@company.com",
            "vendor_name": "Taxi Service",
            "total_amount": 45.00,
            "category": "transportation",
            "approval_status": "approved",
            "policy_violations": 0
        },
        {
            "id": 5,
            "employee_email": "david.brown@company.com",
            "vendor_name": "Conference Dinner",
            "total_amount": 120.00,
            "category": "entertainment",
            "approval_status": "approved",
            "policy_violations": 0
        }
    ]
    
    return mock_expenses

def upload_report_to_storage(report: Dict[str, Any], bucket_name: str) -> str:
    """Upload the generated report to Cloud Storage"""
    
    try:
        # Initialize Cloud Storage client
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        
        # Generate report filename
        report_date = datetime.now().strftime('%Y-%m-%d')
        report_filename = f"reports/expense-report-{report_date}.json"
        
        # Create blob and upload report
        blob = bucket.blob(report_filename)
        report_json = json.dumps(report, indent=2, default=str)
        blob.upload_from_string(report_json, content_type='application/json')
        
        logger.info(f"Report uploaded successfully: gs://{bucket_name}/{report_filename}")
        return report_filename
        
    except Exception as e:
        logger.error(f"Failed to upload report to storage: {str(e)}")
        raise

@functions_framework.http
def generate_expense_report(request):
    """HTTP Cloud Function to generate automated expense reports"""
    
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        logger.info("Starting expense report generation...")
        
        # Get request parameters
        request_json = request.get_json(silent=True) or {}
        report_type = request_json.get('report_type', 'weekly')
        
        # Fetch expense data (using mock data for this example)
        # In production, this would query the Cloud SQL database
        logger.info("Fetching expense data...")
        expense_data = mock_expense_data()
        
        # Calculate metrics
        logger.info("Calculating expense metrics...")
        metrics = calculate_expense_metrics(expense_data)
        
        # Generate insights
        logger.info("Generating insights...")
        insights = generate_expense_insights(metrics)
        
        # Create comprehensive report
        logger.info("Creating detailed report...")
        detailed_report = create_detailed_report(metrics, insights)
        
        # Upload report to Cloud Storage
        logger.info("Uploading report to storage...")
        report_filename = upload_report_to_storage(detailed_report, BUCKET_NAME)
        
        # Prepare response
        response = {
            "status": "success",
            "report_filename": report_filename,
            "report_url": f"gs://{BUCKET_NAME}/{report_filename}",
            "summary": {
                "total_expenses": detailed_report["executive_summary"]["total_expenses"],
                "total_transactions": detailed_report["executive_summary"]["total_transactions"],
                "approval_rate": detailed_report["executive_summary"]["approval_rate"],
                "key_insights_count": len(insights)
            },
            "generated_at": detailed_report["report_metadata"]["generated_at"],
            "report_type": report_type
        }
        
        logger.info(f"Report generation completed successfully: {report_filename}")
        return json.dumps(response), 200, headers
        
    except Exception as e:
        logger.error(f"Error generating expense report: {str(e)}")
        error_response = {
            "status": "error",
            "message": str(e),
            "timestamp": datetime.now().isoformat()
        }
        return json.dumps(error_response), 500, headers

def health_check():
    """Health check function for monitoring"""
    try:
        # Test Cloud Storage access
        storage_client = storage.Client()
        bucket = storage_client.bucket(BUCKET_NAME)
        
        return {
            "status": "healthy",
            "storage_access": "available",
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

# Entry point for testing
if __name__ == "__main__":
    print("Testing expense report generation...")
    
    # Mock request for testing
    class MockRequest:
        def __init__(self):
            self.method = 'POST'
        
        def get_json(self, silent=True):
            return {"report_type": "weekly"}
    
    mock_request = MockRequest()
    result = generate_expense_report(mock_request)
    print("Report generation test completed")