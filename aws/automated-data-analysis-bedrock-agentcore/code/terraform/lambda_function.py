import json
import boto3
import logging
import os
import time
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
s3 = boto3.client('s3')
bedrock_agentcore = boto3.client('bedrock-agentcore')

def lambda_handler(event, context):
    """
    Orchestrates automated data analysis using Bedrock AgentCore
    Triggered by S3 object creation events and processes uploaded datasets
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket_name = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])
            object_size = record['s3']['object']['size']
            
            logger.info(f"Processing file: {object_key} from bucket: {bucket_name} (size: {object_size} bytes)")
            
            # Skip processing if file is too small (likely empty)
            if object_size < 10:
                logger.warning(f"Skipping file {object_key} - file too small ({object_size} bytes)")
                continue
            
            # Generate analysis based on file type
            file_extension = object_key.split('.')[-1].lower()
            analysis_code = generate_analysis_code(file_extension, bucket_name, object_key)
            
            # Create AgentCore session and execute analysis
            session_name = f'DataAnalysis-{int(time.time())}-{file_extension}'
            
            try:
                session_response = bedrock_agentcore.start_code_interpreter_session(
                    codeInterpreterIdentifier='aws.codeinterpreter.v1',
                    name=session_name,
                    sessionTimeoutSeconds=900
                )
                session_id = session_response['sessionId']
                
                logger.info(f"Started AgentCore session: {session_id} for file: {object_key}")
                
                # Execute the analysis code
                execution_response = bedrock_agentcore.invoke_code_interpreter(
                    codeInterpreterIdentifier='aws.codeinterpreter.v1',
                    sessionId=session_id,
                    name='executeAnalysis',
                    arguments={
                        'language': 'python',
                        'code': analysis_code
                    }
                )
                
                logger.info(f"Analysis execution completed for {object_key}")
                
                # Extract execution results
                execution_status = execution_response.get('status', 'unknown')
                execution_output = execution_response.get('output', {})
                
                # Store results metadata
                results_key = f"analysis-results/{object_key.replace('.', '_')}_analysis_{int(time.time())}.json"
                result_metadata = {
                    'source_file': object_key,
                    'source_bucket': bucket_name,
                    'file_size_bytes': object_size,
                    'file_type': file_extension,
                    'session_id': session_id,
                    'session_name': session_name,
                    'analysis_timestamp': time.time(),
                    'execution_status': execution_status,
                    'lambda_request_id': context.aws_request_id,
                    'execution_output': execution_output,
                    'analysis_summary': {
                        'processing_time_seconds': time.time() - float(session_name.split('-')[1]),
                        'success': execution_status == 'completed'
                    }
                }
                
                # Store results in S3
                s3.put_object(
                    Bucket=os.environ['RESULTS_BUCKET_NAME'],
                    Key=results_key,
                    Body=json.dumps(result_metadata, indent=2, default=str),
                    ContentType='application/json',
                    Metadata={
                        'source-file': object_key,
                        'session-id': session_id,
                        'analysis-status': execution_status
                    }
                )
                
                logger.info(f"Results stored at: s3://{os.environ['RESULTS_BUCKET_NAME']}/{results_key}")
                
            except Exception as session_error:
                logger.error(f"AgentCore session error for {object_key}: {str(session_error)}")
                
                # Store error information
                error_key = f"analysis-errors/{object_key.replace('.', '_')}_error_{int(time.time())}.json"
                error_metadata = {
                    'source_file': object_key,
                    'error_timestamp': time.time(),
                    'error_message': str(session_error),
                    'lambda_request_id': context.aws_request_id
                }
                
                s3.put_object(
                    Bucket=os.environ['RESULTS_BUCKET_NAME'],
                    Key=error_key,
                    Body=json.dumps(error_metadata, indent=2),
                    ContentType='application/json'
                )
                
            finally:
                # Clean up session if it was created
                try:
                    if 'session_id' in locals():
                        bedrock_agentcore.stop_code_interpreter_session(
                            codeInterpreterIdentifier='aws.codeinterpreter.v1',
                            sessionId=session_id
                        )
                        logger.info(f"Cleaned up session: {session_id}")
                except Exception as cleanup_error:
                    logger.warning(f"Session cleanup warning: {str(cleanup_error)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Analysis completed successfully',
                'processed_files': len(event['Records']),
                'timestamp': time.time()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': time.time()
            })
        }

def generate_analysis_code(file_type, bucket_name, object_key):
    """
    Generate appropriate analysis code based on file type
    Returns Python code as a string for execution in AgentCore
    """
    base_code = f'''
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
import boto3
import io
import json
from datetime import datetime

# Set up plotting style
plt.style.use('default')
sns.set_palette("husl")

# Download the file from S3
s3 = boto3.client('s3')
try:
    obj = s3.get_object(Bucket='{bucket_name}', Key='{object_key}')
    print(f"Successfully downloaded file: {object_key}")
    print(f"File size: {{obj['ContentLength']}} bytes")
    print(f"Last modified: {{obj['LastModified']}}")
    print("=" * 50)
except Exception as e:
    print(f"Error downloading file: {{e}}")
    raise
'''
    
    if file_type in ['csv']:
        analysis_code = base_code + '''
try:
    # Read CSV file
    df = pd.read_csv(io.BytesIO(obj['Body'].read()))
    
    print("📊 DATASET OVERVIEW")
    print("=" * 50)
    print(f"Dataset shape: {df.shape[0]:,} rows × {df.shape[1]} columns")
    print(f"Column names: {list(df.columns)}")
    print(f"Memory usage: {df.memory_usage(deep=True).sum() / 1024**2:.2f} MB")
    
    print("\\n📋 COLUMN INFORMATION")
    print("=" * 50)
    print(df.info())
    
    print("\\n📈 STATISTICAL SUMMARY")
    print("=" * 50)
    print(df.describe(include='all'))
    
    print("\\n🔍 DATA QUALITY ASSESSMENT")
    print("=" * 50)
    missing_data = df.isnull().sum()
    print("Missing values per column:")
    for col, missing in missing_data.items():
        percentage = (missing / len(df)) * 100
        print(f"  {col}: {missing} ({percentage:.1f}%)")
    
    # Check for duplicates
    duplicates = df.duplicated().sum()
    print(f"\\nDuplicate rows: {duplicates} ({duplicates/len(df)*100:.1f}%)")
    
    # Data type analysis
    print("\\nData types:")
    for dtype_name, dtype_group in df.dtypes.groupby(df.dtypes):
        print(f"  {dtype_name}: {len(dtype_group)} columns")
    
    # Generate visualizations for numeric columns
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    if len(numeric_cols) > 0:
        print(f"\\n📊 GENERATING VISUALIZATIONS FOR {len(numeric_cols)} NUMERIC COLUMNS")
        print("=" * 50)
        
        # Create distribution plots
        n_plots = min(len(numeric_cols), 6)  # Limit to 6 plots
        fig, axes = plt.subplots(2, 3, figsize=(15, 10))
        fig.suptitle('Distribution Analysis', fontsize=16, fontweight='bold')
        
        for i, col in enumerate(numeric_cols[:n_plots]):
            row, col_idx = divmod(i, 3)
            ax = axes[row, col_idx] if n_plots > 3 else axes[i] if n_plots > 1 else axes
            
            # Handle different types of numeric data
            if df[col].nunique() < 20:  # Categorical-like numeric data
                df[col].value_counts().plot(kind='bar', ax=ax, color='skyblue')
                ax.set_title(f'{col} (Value Counts)')
            else:  # Continuous numeric data
                df[col].hist(bins=20, ax=ax, alpha=0.7, color='lightcoral')
                ax.set_title(f'{col} (Distribution)')
            
            ax.tick_params(axis='x', rotation=45)
            ax.grid(True, alpha=0.3)
        
        # Hide unused subplots
        for i in range(n_plots, 6):
            row, col_idx = divmod(i, 3)
            axes[row, col_idx].set_visible(False)
        
        plt.tight_layout()
        plt.savefig('/tmp/distributions.png', dpi=150, bbox_inches='tight')
        print("✅ Distribution plots saved as distributions.png")
        
        # Correlation analysis if multiple numeric columns
        if len(numeric_cols) > 1:
            plt.figure(figsize=(10, 8))
            correlation_matrix = df[numeric_cols].corr()
            sns.heatmap(correlation_matrix, annot=True, cmap='coolwarm', center=0,
                       square=True, linewidths=0.5)
            plt.title('Correlation Matrix', fontsize=14, fontweight='bold')
            plt.tight_layout()
            plt.savefig('/tmp/correlation.png', dpi=150, bbox_inches='tight')
            print("✅ Correlation heatmap saved as correlation.png")
    
    # Analyze categorical columns
    categorical_cols = df.select_dtypes(include=['object']).columns
    if len(categorical_cols) > 0:
        print(f"\\n🏷️  CATEGORICAL ANALYSIS FOR {len(categorical_cols)} COLUMNS")
        print("=" * 50)
        
        for col in categorical_cols[:5]:  # Limit to first 5 categorical columns
            unique_vals = df[col].nunique()
            print(f"\\n{col}:")
            print(f"  Unique values: {unique_vals}")
            if unique_vals <= 10:
                print("  Value counts:")
                for val, count in df[col].value_counts().head().items():
                    print(f"    {val}: {count}")
            else:
                print("  Top 5 values:")
                for val, count in df[col].value_counts().head().items():
                    print(f"    {val}: {count}")
    
    print("\\n✅ CSV ANALYSIS COMPLETED SUCCESSFULLY!")
    print(f"Analysis timestamp: {datetime.now().isoformat()}")
    
except Exception as e:
    print(f"❌ Error analyzing CSV file: {e}")
    raise
'''
    
    elif file_type in ['json']:
        analysis_code = base_code + '''
try:
    # Read JSON file
    data = json.loads(obj['Body'].read().decode('utf-8'))
    
    print("📄 JSON DATA ANALYSIS")
    print("=" * 50)
    print(f"Root data type: {type(data).__name__}")
    
    def analyze_json_structure(obj, path="root", max_depth=3, current_depth=0):
        """Recursively analyze JSON structure"""
        if current_depth > max_depth:
            return {"truncated": True, "reason": "max_depth_reached"}
        
        if isinstance(obj, dict):
            result = {
                "type": "object",
                "keys": list(obj.keys()),
                "key_count": len(obj),
                "properties": {}
            }
            
            for key, value in list(obj.items())[:10]:  # Limit to first 10 keys
                result["properties"][key] = analyze_json_structure(
                    value, f"{path}.{key}", max_depth, current_depth + 1
                )
            
            return result
            
        elif isinstance(obj, list):
            result = {
                "type": "array",
                "length": len(obj),
                "element_types": {}
            }
            
            # Analyze first few elements
            for i, item in enumerate(obj[:5]):
                item_type = type(item).__name__
                if item_type not in result["element_types"]:
                    result["element_types"][item_type] = {
                        "count": 0,
                        "sample": analyze_json_structure(item, f"{path}[{i}]", max_depth, current_depth + 1)
                    }
                result["element_types"][item_type]["count"] += 1
            
            return result
            
        else:
            return {
                "type": type(obj).__name__,
                "value": str(obj)[:100] + "..." if len(str(obj)) > 100 else str(obj)
            }
    
    # Perform structure analysis
    structure = analyze_json_structure(data)
    
    print("🏗️  JSON STRUCTURE ANALYSIS")
    print("=" * 50)
    
    def print_structure(struct, indent=0):
        """Pretty print JSON structure"""
        prefix = "  " * indent
        
        if struct["type"] == "object":
            print(f"{prefix}Object with {struct['key_count']} keys:")
            for key, prop in struct["properties"].items():
                print(f"{prefix}  {key}: ", end="")
                if prop["type"] in ["object", "array"]:
                    print(f"{prop['type']}")
                    print_structure(prop, indent + 2)
                else:
                    print(f"{prop['type']} = {prop.get('value', 'N/A')}")
        
        elif struct["type"] == "array":
            print(f"{prefix}Array with {struct['length']} elements:")
            for elem_type, info in struct["element_types"].items():
                print(f"{prefix}  {elem_type} ({info['count']} items)")
                if info["sample"]["type"] in ["object", "array"]:
                    print_structure(info["sample"], indent + 2)
    
    print_structure(structure)
    
    # Additional analysis for common JSON patterns
    if isinstance(data, list) and len(data) > 0:
        print("\\n📊 ARRAY ANALYSIS")
        print("=" * 50)
        print(f"Array length: {len(data):,} elements")
        
        # Check if it's an array of objects (common pattern)
        if isinstance(data[0], dict):
            print("Array contains objects - analyzing as tabular data...")
            
            # Try to convert to DataFrame for analysis
            try:
                df = pd.DataFrame(data)
                print(f"Successfully converted to DataFrame: {df.shape[0]:,} rows × {df.shape[1]} columns")
                print(f"Columns: {list(df.columns)}")
                
                # Basic statistics
                print("\\nColumn info:")
                for col in df.columns:
                    dtype = df[col].dtype
                    null_count = df[col].isnull().sum()
                    unique_count = df[col].nunique()
                    print(f"  {col}: {dtype}, {null_count} nulls, {unique_count} unique values")
                
            except Exception as df_error:
                print(f"Could not convert to DataFrame: {df_error}")
    
    elif isinstance(data, dict):
        print("\\n🔍 OBJECT ANALYSIS")
        print("=" * 50)
        
        # Analyze top-level keys
        for key, value in list(data.items())[:20]:  # First 20 keys
            value_type = type(value).__name__
            if isinstance(value, (list, dict)):
                size = len(value)
                print(f"  {key}: {value_type} (size: {size})")
            else:
                print(f"  {key}: {value_type} = {str(value)[:50]}...")
    
    print("\\n✅ JSON ANALYSIS COMPLETED SUCCESSFULLY!")
    print(f"Analysis timestamp: {datetime.now().isoformat()}")
    
except json.JSONDecodeError as e:
    print(f"❌ Invalid JSON format: {e}")
    raise
except Exception as e:
    print(f"❌ Error analyzing JSON file: {e}")
    raise
'''
    
    elif file_type in ['xlsx', 'xls']:
        analysis_code = base_code + '''
try:
    # Read Excel file
    excel_data = pd.read_excel(io.BytesIO(obj['Body'].read()), sheet_name=None)
    
    print("📊 EXCEL FILE ANALYSIS")
    print("=" * 50)
    print(f"Number of sheets: {len(excel_data)}")
    print(f"Sheet names: {list(excel_data.keys())}")
    
    for sheet_name, df in excel_data.items():
        print(f"\\n📋 SHEET: {sheet_name}")
        print("=" * 30)
        print(f"Shape: {df.shape[0]:,} rows × {df.shape[1]} columns")
        print(f"Columns: {list(df.columns)}")
        
        # Basic statistics for each sheet
        if not df.empty:
            print(f"Memory usage: {df.memory_usage(deep=True).sum() / 1024**2:.2f} MB")
            
            # Missing data analysis
            missing_data = df.isnull().sum()
            missing_percent = (missing_data / len(df)) * 100
            print("Missing data summary:")
            for col, missing in missing_data.items():
                if missing > 0:
                    print(f"  {col}: {missing} ({missing_percent[col]:.1f}%)")
            
            # Data types
            numeric_cols = df.select_dtypes(include=[np.number]).columns
            categorical_cols = df.select_dtypes(include=['object']).columns
            datetime_cols = df.select_dtypes(include=['datetime']).columns
            
            print(f"Numeric columns: {len(numeric_cols)}")
            print(f"Text columns: {len(categorical_cols)}")
            print(f"DateTime columns: {len(datetime_cols)}")
        
        # Analyze only the first sheet in detail to avoid complexity
        if sheet_name == list(excel_data.keys())[0] and not df.empty:
            print(f"\\n📈 DETAILED ANALYSIS FOR FIRST SHEET: {sheet_name}")
            print("=" * 50)
            print(df.describe(include='all'))
    
    print("\\n✅ EXCEL ANALYSIS COMPLETED SUCCESSFULLY!")
    print(f"Analysis timestamp: {datetime.now().isoformat()}")
    
except Exception as e:
    print(f"❌ Error analyzing Excel file: {e}")
    raise
'''
    
    else:
        # Generic file analysis for unsupported formats
        analysis_code = base_code + f'''
try:
    # Generic file analysis
    file_content = obj['Body'].read()
    
    print("📄 GENERIC FILE ANALYSIS")
    print("=" * 50)
    print(f"File extension: {file_type}")
    print(f"File size: {{obj['ContentLength']:,}} bytes")
    print(f"Content type: {{obj.get('ContentType', 'Unknown')}}")
    
    # Try to determine if it's text-based
    try:
        content_preview = file_content[:1000].decode('utf-8')
        print("\\n📝 TEXT CONTENT PREVIEW (first 1000 characters):")
        print("=" * 50)
        print(content_preview)
        
        # Basic text analysis
        lines = content_preview.split('\\n')
        print(f"\\nEstimated lines in preview: {{len(lines)}}")
        print(f"Average line length: {{sum(len(line) for line in lines) / len(lines):.1f}} characters")
        
    except UnicodeDecodeError:
        print("\\n📁 BINARY FILE DETECTED")
        print("=" * 50)
        print("File appears to be binary - cannot preview content")
        
        # Analyze file signature
        signature = file_content[:16].hex()
        print(f"File signature (first 16 bytes): {{signature}}")
        
        # Common file signatures
        signatures = {{
            '89504e47': 'PNG Image',
            'ffd8ffe0': 'JPEG Image', 
            '504b0304': 'ZIP Archive',
            'd0cf11e0': 'Microsoft Office Document',
            '25504446': 'PDF Document'
        }}
        
        for sig, description in signatures.items():
            if signature.startswith(sig):
                print(f"Detected file type: {{description}}")
                break
    
    print("\\n✅ GENERIC FILE ANALYSIS COMPLETED!")
    print(f"Analysis timestamp: {{datetime.now().isoformat()}}")
    
except Exception as e:
    print(f"❌ Error analyzing file: {{e}}")
    raise
'''
    
    return analysis_code