# Lambda function for Interactive Data Analytics with Bedrock AgentCore Code Interpreter
# This function orchestrates analytics workflows using natural language queries

import json
import boto3
import os
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Main Lambda handler for processing analytics requests through Bedrock AgentCore Code Interpreter
    
    Args:
        event: Lambda event containing the analytics query
        context: Lambda context object
        
    Returns:
        dict: Response with analysis results or error information
    """
    
    # Initialize AWS clients
    try:
        bedrock_agentcore = boto3.client('bedrock-agentcore')
        s3_client = boto3.client('s3')
        cloudwatch = boto3.client('cloudwatch')
    except Exception as e:
        logger.error(f"Failed to initialize AWS clients: {str(e)}")
        return create_error_response(500, f"Client initialization failed: {str(e)}")
    
    # Extract configuration from environment variables
    code_interpreter_id = os.environ.get('CODE_INTERPRETER_ID', '${code_interpreter_id}')
    bucket_raw_data = os.environ.get('BUCKET_RAW_DATA', '${bucket_raw_data}')
    bucket_results = os.environ.get('BUCKET_RESULTS', '${bucket_results}')
    bedrock_model_id = os.environ.get('BEDROCK_MODEL_ID', 'anthropic.claude-3-5-sonnet-20241022-v2:0')
    
    logger.info(f"Processing request with Code Interpreter: {code_interpreter_id}")
    
    try:
        # Parse the incoming event
        if isinstance(event, str):
            event = json.loads(event)
        
        # Handle API Gateway event format
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
            user_query = body.get('query', 'Analyze the available data and provide insights')
        else:
            # Direct Lambda invocation
            user_query = event.get('query', 'Analyze the available data and provide insights')
        
        logger.info(f"Processing query: {user_query}")
        
        # Validate query
        if not user_query or len(user_query.strip()) == 0:
            return create_error_response(400, "Query cannot be empty")
        
        # Create a unique session name
        session_name = f"analytics-session-{int(datetime.now().timestamp())}"
        
        # Start Code Interpreter session
        session_response = bedrock_agentcore.start_code_interpreter_session(
            codeInterpreterIdentifier=code_interpreter_id,
            name=session_name,
            sessionTimeoutSeconds=3600
        )
        
        session_id = session_response['sessionId']
        logger.info(f"Started Code Interpreter session: {session_id}")
        
        # Generate Python code for data analysis based on user query
        analysis_code = generate_analysis_code(user_query, bucket_raw_data, bucket_results)
        
        # Execute code through Bedrock AgentCore
        execution_response = bedrock_agentcore.invoke_code_interpreter(
            codeInterpreterIdentifier=code_interpreter_id,
            sessionId=session_id,
            name="executeAnalysis",
            arguments={
                "language": "python",
                "code": analysis_code
            }
        )
        
        # Process the response stream
        results = []
        execution_output = ""
        
        try:
            for event_item in execution_response.get('stream', []):
                if 'result' in event_item:
                    result = event_item['result']
                    if 'content' in result:
                        for content_item in result['content']:
                            if content_item['type'] == 'text':
                                text_content = content_item['text']
                                results.append(text_content)
                                execution_output += text_content + "\n"
                elif 'error' in event_item:
                    error_msg = event_item['error'].get('message', 'Unknown execution error')
                    logger.error(f"Code execution error: {error_msg}")
                    raise Exception(f"Code execution failed: {error_msg}")
        except Exception as e:
            logger.error(f"Error processing execution stream: {str(e)}")
            raise e
        
        # Log success metrics to CloudWatch
        put_metric_data(cloudwatch, 'ExecutionCount', 1, 'Count')
        
        # Prepare successful response
        response_data = {
            'statusCode': 200,
            'message': 'Analysis completed successfully',
            'session_id': session_id,
            'query': user_query,
            'execution_output': execution_output,
            'results_summary': results[:3] if results else ["Analysis completed but no output captured"],
            'results_bucket': bucket_results,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        logger.info("Analysis completed successfully")
        return response_data
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS service error: {error_code} - {error_message}")
        
        # Log error metrics
        put_metric_data(cloudwatch, 'ExecutionErrors', 1, 'Count')
        
        return create_error_response(500, f"AWS service error: {error_code} - {error_message}")
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        
        # Log error metrics
        put_metric_data(cloudwatch, 'ExecutionErrors', 1, 'Count')
        
        return create_error_response(500, f"Unexpected error: {str(e)}")

def generate_analysis_code(user_query, bucket_raw_data, bucket_results):
    """
    Generate Python code for data analysis based on user query
    
    Args:
        user_query: Natural language query from user
        bucket_raw_data: S3 bucket name for raw data
        bucket_results: S3 bucket name for results
        
    Returns:
        str: Python code for execution
    """
    
    code_template = f'''
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import boto3
import json
from datetime import datetime
import warnings
warnings.filterwarnings('ignore')

# Initialize S3 client
s3 = boto3.client('s3')

print("=== Interactive Data Analytics Session ===")
print(f"Query: {user_query}")
print(f"Timestamp: {{datetime.now().isoformat()}}")
print("=" * 50)

try:
    # List available datasets
    response = s3.list_objects_v2(Bucket='{bucket_raw_data}', Prefix='datasets/')
    
    if 'Contents' in response:
        print("Available datasets:")
        for obj in response['Contents']:
            print(f"  - {{obj['Key']}}")
        print()
    
    # Try to download and analyze available data files
    datasets = {{}}
    
    # Download sales data if available
    try:
        s3.download_file('{bucket_raw_data}', 'datasets/sample_sales_data.csv', 'sales_data.csv')
        sales_df = pd.read_csv('sales_data.csv')
        datasets['sales'] = sales_df
        print("✅ Loaded sales data successfully")
        print(f"Sales data shape: {{sales_df.shape}}")
        print(f"Sales data columns: {{list(sales_df.columns)}}")
        print()
    except Exception as e:
        print(f"⚠️  Could not load sales data: {{str(e)}}")
    
    # Download customer data if available
    try:
        s3.download_file('{bucket_raw_data}', 'datasets/sample_customer_data.json', 'customer_data.json')
        with open('customer_data.json', 'r') as f:
            customer_data = json.load(f)
        customer_df = pd.DataFrame(customer_data)
        datasets['customers'] = customer_df
        print("✅ Loaded customer data successfully")
        print(f"Customer data shape: {{customer_df.shape}}")
        print(f"Customer data columns: {{list(customer_df.columns)}}")
        print()
    except Exception as e:
        print(f"⚠️  Could not load customer data: {{str(e)}}")
    
    if not datasets:
        print("❌ No datasets available for analysis")
        print("Please upload data to the S3 bucket: {bucket_raw_data}")
    else:
        print("🔍 Starting data analysis based on query...")
        print()
        
        # Perform analysis based on query content
        query_lower = "{user_query}".lower()
        
        if 'sales' in datasets:
            sales_df = datasets['sales']
            
            # Basic sales analysis
            print("📊 SALES ANALYSIS RESULTS:")
            print("-" * 30)
            
            total_sales = sales_df['sales_amount'].sum()
            avg_sales = sales_df['sales_amount'].mean()
            total_quantity = sales_df['quantity'].sum()
            
            print(f"Total Sales Amount: ${{total_sales:,.2f}}")
            print(f"Average Sales per Transaction: ${{avg_sales:,.2f}}")
            print(f"Total Quantity Sold: {{total_quantity:,}} units")
            print()
            
            # Regional analysis
            if 'region' in sales_df.columns:
                print("🗺️  SALES BY REGION:")
                region_sales = sales_df.groupby('region')['sales_amount'].sum().sort_values(ascending=False)
                for region, amount in region_sales.items():
                    print(f"  {{region}}: ${{amount:,.2f}}")
                print()
            
            # Product analysis
            if 'product' in sales_df.columns:
                print("📦 SALES BY PRODUCT:")
                product_sales = sales_df.groupby('product')['sales_amount'].sum().sort_values(ascending=False)
                for product, amount in product_sales.items():
                    print(f"  {{product}}: ${{amount:,.2f}}")
                print()
            
            # Customer segment analysis
            if 'customer_segment' in sales_df.columns:
                print("👥 SALES BY CUSTOMER SEGMENT:")
                segment_sales = sales_df.groupby('customer_segment')['sales_amount'].sum().sort_values(ascending=False)
                for segment, amount in segment_sales.items():
                    print(f"  {{segment}}: ${{amount:,.2f}}")
                print()
            
            # Time-based analysis if date column exists
            if 'date' in sales_df.columns:
                try:
                    sales_df['date'] = pd.to_datetime(sales_df['date'])
                    print("📅 TIME-BASED ANALYSIS:")
                    daily_sales = sales_df.groupby('date')['sales_amount'].sum()
                    print(f"Best performing day: {{daily_sales.idxmax()}} (${{daily_sales.max():,.2f}})")
                    print(f"Average daily sales: ${{daily_sales.mean():,.2f}}")
                    print()
                except Exception as e:
                    print(f"Could not perform time analysis: {{str(e)}}")
            
            # Advanced analytics based on query keywords
            if any(keyword in query_lower for keyword in ['correlation', 'relationship', 'statistical']):
                print("📈 STATISTICAL ANALYSIS:")
                if 'sales_amount' in sales_df.columns and 'quantity' in sales_df.columns:
                    correlation = sales_df['sales_amount'].corr(sales_df['quantity'])
                    print(f"Correlation between Sales Amount and Quantity: {{correlation:.3f}}")
                
                print("Statistical Summary:")
                print(sales_df.describe())
                print()
            
            # Create visualization
            try:
                plt.figure(figsize=(12, 8))
                
                if 'region' in sales_df.columns:
                    plt.subplot(2, 2, 1)
                    region_sales = sales_df.groupby('region')['sales_amount'].sum()
                    region_sales.plot(kind='bar', title='Sales by Region')
                    plt.xticks(rotation=45)
                    plt.ylabel('Sales Amount ($)')
                
                if 'product' in sales_df.columns:
                    plt.subplot(2, 2, 2)
                    product_sales = sales_df.groupby('product')['sales_amount'].sum()
                    product_sales.plot(kind='bar', title='Sales by Product', color='orange')
                    plt.xticks(rotation=45)
                    plt.ylabel('Sales Amount ($)')
                
                if 'customer_segment' in sales_df.columns:
                    plt.subplot(2, 2, 3)
                    segment_sales = sales_df.groupby('customer_segment')['sales_amount'].sum()
                    segment_sales.plot(kind='pie', title='Sales Distribution by Segment', autopct='%1.1f%%')
                
                if 'date' in sales_df.columns:
                    plt.subplot(2, 2, 4)
                    try:
                        daily_sales = sales_df.groupby('date')['sales_amount'].sum()
                        daily_sales.plot(title='Daily Sales Trend', color='green')
                        plt.ylabel('Sales Amount ($)')
                        plt.xticks(rotation=45)
                    except:
                        pass
                
                plt.tight_layout()
                plt.savefig('comprehensive_analysis.png', dpi=300, bbox_inches='tight')
                
                # Upload visualization to S3
                s3.upload_file('comprehensive_analysis.png', '{bucket_results}', 'analysis_results/comprehensive_analysis.png')
                print("📊 Visualization saved to S3: analysis_results/comprehensive_analysis.png")
                
            except Exception as e:
                print(f"Could not create visualization: {{str(e)}}")
        
        # Customer analysis if available
        if 'customers' in datasets:
            customer_df = datasets['customers']
            print("👥 CUSTOMER ANALYSIS:")
            print("-" * 20)
            
            if 'annual_value' in customer_df.columns:
                total_customer_value = customer_df['annual_value'].sum()
                avg_customer_value = customer_df['annual_value'].mean()
                print(f"Total Customer Annual Value: ${{total_customer_value:,.2f}}")
                print(f"Average Customer Annual Value: ${{avg_customer_value:,.2f}}")
            
            if 'segment' in customer_df.columns:
                print("Customer Distribution by Segment:")
                segment_counts = customer_df['segment'].value_counts()
                for segment, count in segment_counts.items():
                    print(f"  {{segment}}: {{count}} customers")
            print()
        
        # Generate insights and recommendations
        print("🎯 KEY INSIGHTS AND RECOMMENDATIONS:")
        print("-" * 40)
        
        if 'sales' in datasets:
            sales_df = datasets['sales']
            
            # Top performing region
            if 'region' in sales_df.columns:
                top_region = sales_df.groupby('region')['sales_amount'].sum().idxmax()
                print(f"• {{top_region}} is the top-performing region")
            
            # Top performing product
            if 'product' in sales_df.columns:
                top_product = sales_df.groupby('product')['sales_amount'].sum().idxmax()
                print(f"• {{top_product}} is the best-selling product")
            
            # Customer segment insights
            if 'customer_segment' in sales_df.columns:
                top_segment = sales_df.groupby('customer_segment')['sales_amount'].sum().idxmax()
                print(f"• {{top_segment}} segment generates the most revenue")
            
            print("• Consider focusing marketing efforts on top-performing segments")
            print("• Analyze underperforming areas for improvement opportunities")
        
        print()
        print("✅ Analysis completed successfully!")
        
        # Save summary report
        with open('analysis_summary.txt', 'w') as f:
            f.write(f"Analysis Summary\\n")
            f.write(f"Query: {user_query}\\n")
            f.write(f"Timestamp: {{datetime.now().isoformat()}}\\n")
            f.write(f"Datasets analyzed: {{', '.join(datasets.keys())}}\\n")
            if 'sales' in datasets:
                f.write(f"Total sales: ${{total_sales:,.2f}}\\n")
                f.write(f"Total transactions: {{len(sales_df)}}\\n")
        
        s3.upload_file('analysis_summary.txt', '{bucket_results}', 'analysis_results/analysis_summary.txt')
        print("📄 Summary report saved to S3: analysis_results/analysis_summary.txt")

except Exception as e:
    print(f"❌ Error during analysis: {{str(e)}}")
    print("Please check your data format and try again.")

print("\\n" + "=" * 50)
print("Analysis session completed.")
'''

    return code_template

def put_metric_data(cloudwatch_client, metric_name, value, unit):
    """
    Put custom metric data to CloudWatch
    
    Args:
        cloudwatch_client: CloudWatch client
        metric_name: Name of the metric
        value: Metric value
        unit: Unit of measurement
    """
    try:
        cloudwatch_client.put_metric_data(
            Namespace='Analytics/CodeInterpreter',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        logger.error(f"Failed to put metric data: {str(e)}")

def create_error_response(status_code, message):
    """
    Create standardized error response
    
    Args:
        status_code: HTTP status code
        message: Error message
        
    Returns:
        dict: Formatted error response
    """
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'error': message,
            'timestamp': datetime.utcnow().isoformat()
        }),
        'headers': {
            'Content-Type': 'application/json'
        }
    }