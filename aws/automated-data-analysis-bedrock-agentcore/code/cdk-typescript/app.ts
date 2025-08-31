#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy, CfnOutput } from 'aws-cdk-lib';

/**
 * Stack for automated data analysis using AWS Bedrock AgentCore Runtime
 * This stack creates the infrastructure needed for AI-powered data analysis
 * triggered by S3 file uploads and orchestrated by Lambda functions.
 */
class AutomatedDataAnalysisStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for input datasets
    const dataBucket = new s3.Bucket(this, 'DataAnalysisInputBucket', {
      bucketName: `data-analysis-input-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
      eventBridgeEnabled: false,
      lifecycleRules: [
        {
          id: 'delete-incomplete-uploads',
          abortIncompleteMultipartUploadAfter: Duration.days(1),
          enabled: true,
        },
      ],
    });

    // Create S3 bucket for analysis results
    const resultsBucket = new s3.Bucket(this, 'DataAnalysisResultsBucket', {
      bucketName: `data-analysis-results-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
      eventBridgeEnabled: false,
      lifecycleRules: [
        {
          id: 'transition-to-ia',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            },
          ],
          enabled: true,
        },
      ],
    });

    // Create IAM role for Lambda function with comprehensive permissions
    const lambdaExecutionRole = new iam.Role(this, 'DataAnalysisOrchestratorRole', {
      roleName: `DataAnalysisOrchestratorRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda function to orchestrate data analysis with Bedrock AgentCore',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        BedrockAgentCorePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock-agentcore:CreateCodeInterpreter',
                'bedrock-agentcore:StartCodeInterpreterSession',
                'bedrock-agentcore:InvokeCodeInterpreter',
                'bedrock-agentcore:StopCodeInterpreterSession',
                'bedrock-agentcore:DeleteCodeInterpreter',
                'bedrock-agentcore:ListCodeInterpreters',
                'bedrock-agentcore:GetCodeInterpreter',
                'bedrock-agentcore:GetCodeInterpreterSession',
              ],
              resources: ['*'], // AgentCore resources are region-scoped
            }),
          ],
        }),
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [
                dataBucket.arnForObjects('*'),
                resultsBucket.arnForObjects('*'),
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [dataBucket.bucketArn, resultsBucket.bucketArn],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Lambda function with retention policy
    const lambdaLogGroup = new logs.LogGroup(this, 'DataAnalysisOrchestratorLogGroup', {
      logGroupName: `/aws/lambda/data-analysis-orchestrator-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create Lambda function for orchestrating data analysis workflow
    const orchestratorFunction = new lambda.Function(this, 'DataAnalysisOrchestratorFunction', {
      functionName: `data-analysis-orchestrator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        DATA_BUCKET_NAME: dataBucket.bucketName,
        RESULTS_BUCKET_NAME: resultsBucket.bucketName,
        LOG_LEVEL: 'INFO',
      },
      description: 'Orchestrates automated data analysis using AWS Bedrock AgentCore Runtime',
      logGroup: lambdaLogGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
import time
from urllib.parse import unquote_plus
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients with error handling
try:
    s3 = boto3.client('s3')
    bedrock_agentcore = boto3.client('bedrock-agentcore')
except Exception as e:
    logger.error(f"Failed to initialize AWS clients: {str(e)}")
    raise

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Orchestrates automated data analysis using Bedrock AgentCore
    
    Args:
        event: S3 event notification containing file upload details
        context: Lambda runtime context
    
    Returns:
        Dictionary containing execution status and results
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse S3 event records
        processed_files = []
        for record in event.get('Records', []):
            try:
                bucket_name = record['s3']['bucket']['name']
                object_key = unquote_plus(record['s3']['object']['key'])
                
                logger.info(f"Processing file: {object_key} from bucket: {bucket_name}")
                
                # Validate file is in the correct prefix (datasets/)
                if not object_key.startswith('datasets/'):
                    logger.warning(f"Skipping file {object_key} - not in datasets/ prefix")
                    continue
                
                # Analyze file and generate appropriate analysis code
                file_extension = object_key.split('.')[-1].lower() if '.' in object_key else 'unknown'
                analysis_code = generate_analysis_code(file_extension, bucket_name, object_key)
                
                # Create AgentCore session for analysis
                session_response = create_agentcore_session(object_key)
                session_id = session_response['sessionId']
                
                logger.info(f"Created AgentCore session: {session_id} for file: {object_key}")
                
                # Execute analysis code in AgentCore environment
                execution_response = execute_analysis(session_id, analysis_code)
                
                # Store analysis results and metadata
                results_stored = store_analysis_results(
                    object_key, session_id, execution_response, context.aws_request_id
                )
                
                # Clean up AgentCore session
                cleanup_session(session_id)
                
                processed_files.append({
                    'file': object_key,
                    'session_id': session_id,
                    'status': 'completed',
                    'results_location': results_stored
                })
                
                logger.info(f"Successfully processed {object_key}")
                
            except Exception as file_error:
                logger.error(f"Error processing file {object_key}: {str(file_error)}")
                processed_files.append({
                    'file': object_key,
                    'status': 'failed',
                    'error': str(file_error)
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data analysis workflow completed',
                'processed_files': processed_files,
                'total_files': len(processed_files)
            })
        }
        
    except Exception as e:
        logger.error(f"Critical error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Data analysis workflow failed',
                'error': str(e)
            })
        }

def generate_analysis_code(file_type: str, bucket_name: str, object_key: str) -> str:
    """
    Generate appropriate Python analysis code based on file type
    
    Args:
        file_type: File extension (csv, json, etc.)
        bucket_name: S3 bucket containing the file
        object_key: S3 object key
    
    Returns:
        Python code string for data analysis
    """
    base_code = f'''
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import boto3
import io
import json
import numpy as np
from datetime import datetime

# Configure plotting style
plt.style.use('default')
sns.set_palette("husl")

# Download file from S3
s3 = boto3.client('s3')
print(f"Downloading {{bucket_name}}/{{object_key}} for analysis...")
obj = s3.get_object(Bucket='{bucket_name}', Key='{object_key}')
print("File downloaded successfully!")
'''
    
    if file_type == 'csv':
        return base_code + '''
# Read and analyze CSV file
try:
    df = pd.read_csv(io.BytesIO(obj['Body'].read()))
    print("\\n" + "="*60)
    print("COMPREHENSIVE DATA ANALYSIS REPORT")
    print("="*60)
    
    # Dataset Overview
    print(f"\\n📊 DATASET OVERVIEW")
    print(f"├─ Shape: {df.shape[0]:,} rows × {df.shape[1]} columns")
    print(f"├─ Memory Usage: {df.memory_usage(deep=True).sum() / 1024**2:.2f} MB")
    print(f"└─ Columns: {', '.join(df.columns.tolist())}")
    
    # Data Types and Quality
    print(f"\\n🔍 DATA QUALITY ASSESSMENT")
    print(f"├─ Data Types:")
    for dtype, count in df.dtypes.value_counts().items():
        print(f"│   ├─ {dtype}: {count} columns")
    
    missing_data = df.isnull().sum()
    if missing_data.sum() > 0:
        print(f"├─ Missing Values Found:")
        for col, missing in missing_data[missing_data > 0].items():
            pct = (missing / len(df)) * 100
            print(f"│   ├─ {col}: {missing:,} ({pct:.1f}%)")
    else:
        print(f"└─ ✅ No missing values detected")
    
    # Statistical Summary for Numeric Columns
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    if len(numeric_cols) > 0:
        print(f"\\n📈 STATISTICAL SUMMARY")
        print(df[numeric_cols].describe().round(2))
        
        # Correlation Analysis
        if len(numeric_cols) > 1:
            print(f"\\n🔗 CORRELATION ANALYSIS")
            corr_matrix = df[numeric_cols].corr()
            
            # Find strong correlations
            strong_corr = []
            for i in range(len(corr_matrix.columns)):
                for j in range(i+1, len(corr_matrix.columns)):
                    corr_val = corr_matrix.iloc[i, j]
                    if abs(corr_val) > 0.7:
                        strong_corr.append((corr_matrix.columns[i], corr_matrix.columns[j], corr_val))
            
            if strong_corr:
                print("Strong correlations found (|r| > 0.7):")
                for col1, col2, corr in strong_corr:
                    print(f"├─ {col1} ↔ {col2}: {corr:.3f}")
            else:
                print("└─ No strong correlations detected")
    
    # Categorical Analysis
    categorical_cols = df.select_dtypes(include=['object', 'category']).columns
    if len(categorical_cols) > 0:
        print(f"\\n📋 CATEGORICAL DATA ANALYSIS")
        for col in categorical_cols[:3]:  # Limit to first 3 categorical columns
            unique_count = df[col].nunique()
            print(f"├─ {col}: {unique_count} unique values")
            if unique_count <= 10:
                value_counts = df[col].value_counts().head(5)
                for val, count in value_counts.items():
                    pct = (count / len(df)) * 100
                    print(f"│   ├─ '{val}': {count:,} ({pct:.1f}%)")
    
    # Generate Visualizations
    if len(numeric_cols) > 0:
        print(f"\\n📊 GENERATING VISUALIZATIONS")
        
        # Create comprehensive visualization
        fig_rows = min(2, (len(numeric_cols) + 1) // 2)
        fig_cols = min(2, len(numeric_cols))
        
        if fig_rows > 0 and fig_cols > 0:
            fig, axes = plt.subplots(fig_rows, fig_cols, figsize=(15, 6*fig_rows))
            if fig_rows == 1 and fig_cols == 1:
                axes = [axes]
            elif fig_rows == 1 or fig_cols == 1:
                axes = axes.flatten()
            else:
                axes = axes.flatten()
            
            for i, col in enumerate(numeric_cols[:4]):
                ax = axes[i] if len(numeric_cols) > 1 else axes[0]
                
                # Create histogram with statistical info
                data = df[col].dropna()
                ax.hist(data, bins=min(30, len(data.unique())), alpha=0.7, color='skyblue', edgecolor='black')
                ax.set_title(f'Distribution of {col}\\n(Mean: {data.mean():.2f}, Std: {data.std():.2f})', fontsize=10)
                ax.set_xlabel(col)
                ax.set_ylabel('Frequency')
                ax.grid(True, alpha=0.3)
            
            # Hide unused subplots
            for i in range(len(numeric_cols), len(axes)):
                axes[i].set_visible(False)
            
            plt.tight_layout()
            plt.savefig('/tmp/data_analysis_report.png', dpi=300, bbox_inches='tight', 
                       facecolor='white', edgecolor='none')
            print("└─ ✅ Visualization saved as 'data_analysis_report.png'")
    
    # Key Insights and Recommendations
    print(f"\\n💡 KEY INSIGHTS")
    insights = []
    
    # Data quality insights
    if missing_data.sum() == 0:
        insights.append("✅ Dataset has excellent data quality with no missing values")
    elif missing_data.sum() > len(df) * 0.1:
        insights.append("⚠️  Significant missing data detected - consider data cleaning")
    
    # Size insights
    if len(df) > 10000:
        insights.append(f"📈 Large dataset ({len(df):,} records) suitable for statistical analysis")
    elif len(df) < 100:
        insights.append(f"⚠️  Small dataset ({len(df)} records) - results may not be statistically significant")
    
    # Numeric insights
    if len(numeric_cols) > 0:
        skewed_cols = []
        for col in numeric_cols:
            skewness = df[col].skew()
            if abs(skewness) > 1:
                skewed_cols.append(f"{col} (skew: {skewness:.2f})")
        
        if skewed_cols:
            insights.append(f"📊 Skewed distributions detected: {', '.join(skewed_cols)}")
    
    if insights:
        for insight in insights:
            print(f"├─ {insight}")
    else:
        print("├─ 📋 Standard dataset structure detected")
    
    print(f"\\n🎯 RECOMMENDATIONS")
    recommendations = [
        "Consider performing outlier analysis for numeric variables",
        "Explore time-series patterns if date columns are present",
        "Apply feature engineering for machine learning applications",
        "Validate data quality rules specific to your domain"
    ]
    
    for rec in recommendations:
        print(f"├─ {rec}")
    
    print("\\n" + "="*60)
    print("ANALYSIS COMPLETED SUCCESSFULLY!")
    print("="*60)
    
except Exception as e:
    print(f"❌ Error analyzing CSV file: {str(e)}")
    import traceback
    traceback.print_exc()
'''
    
    elif file_type == 'json':
        return base_code + '''
# Read and analyze JSON file
try:
    json_content = obj['Body'].read().decode('utf-8')
    data = json.loads(json_content)
    
    print("\\n" + "="*60)
    print("JSON DATA STRUCTURE ANALYSIS")
    print("="*60)
    
    def analyze_json_structure(obj, path="root", level=0):
        """Recursively analyze JSON structure"""
        indent = "  " * level
        
        if isinstance(obj, dict):
            print(f"{indent}📁 {path} (dict with {len(obj)} keys)")
            for key, value in obj.items():
                analyze_json_structure(value, f"{path}.{key}", level + 1)
        
        elif isinstance(obj, list):
            print(f"{indent}📋 {path} (list with {len(obj)} items)")
            if len(obj) > 0:
                # Analyze first few items to understand structure
                unique_types = set(type(item).__name__ for item in obj[:10])
                print(f"{indent}  └─ Item types: {', '.join(unique_types)}")
                if len(obj) > 0:
                    analyze_json_structure(obj[0], f"{path}[0]", level + 1)
        
        elif isinstance(obj, str):
            print(f"{indent}📝 {path} (string, length: {len(obj)})")
        
        elif isinstance(obj, (int, float)):
            print(f"{indent}🔢 {path} ({type(obj).__name__}: {obj})")
        
        elif isinstance(obj, bool):
            print(f"{indent}✓ {path} (boolean: {obj})")
        
        else:
            print(f"{indent}❓ {path} ({type(obj).__name__})")
    
    # Perform structure analysis
    print(f"\\n🔍 JSON STRUCTURE OVERVIEW")
    analyze_json_structure(data)
    
    # Convert to DataFrame if possible for statistical analysis
    if isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict):
        print(f"\\n📊 CONVERTING TO DATAFRAME FOR ANALYSIS")
        try:
            df = pd.json_normalize(data)
            print(f"✅ Successfully converted to DataFrame: {df.shape[0]} rows × {df.shape[1]} columns")
            
            # Basic statistical analysis
            numeric_cols = df.select_dtypes(include=[np.number]).columns
            if len(numeric_cols) > 0:
                print(f"\\n📈 NUMERIC COLUMNS ANALYSIS")
                print(df[numeric_cols].describe().round(2))
            
            # Show sample data
            print(f"\\n📋 SAMPLE DATA (first 3 rows)")
            print(df.head(3).to_string())
            
        except Exception as e:
            print(f"⚠️  Could not convert to DataFrame: {str(e)}")
    
    # Memory usage and file size analysis
    file_size_mb = len(json_content) / (1024 * 1024)
    print(f"\\n💾 FILE METRICS")
    print(f"├─ File size: {file_size_mb:.2f} MB")
    print(f"├─ Character count: {len(json_content):,}")
    print(f"└─ Estimated memory usage: {file_size_mb * 2:.2f} MB")
    
    print(f"\\n✅ JSON ANALYSIS COMPLETED SUCCESSFULLY!")
    
except json.JSONDecodeError as e:
    print(f"❌ Invalid JSON format: {str(e)}")
except Exception as e:
    print(f"❌ Error analyzing JSON file: {str(e)}")
    import traceback
    traceback.print_exc()
'''
    
    else:
        return base_code + f'''
# Generic file analysis for {file_type} files
try:
    content = obj['Body'].read()
    
    print("\\n" + "="*50)
    print("GENERIC FILE ANALYSIS")
    print("="*50)
    
    print(f"\\n📁 FILE INFORMATION")
    print(f"├─ File name: {object_key}")
    print(f"├─ File type: {file_type}")
    print(f"├─ File size: {{obj['ContentLength']:,}} bytes ({obj['ContentLength']/1024/1024:.2f} MB)")
    print(f"├─ Content type: {{obj.get('ContentType', 'Unknown')}}")
    print(f"└─ Last modified: {{obj.get('LastModified', 'Unknown')}}")
    
    # Try to detect if it's text-based
    try:
        text_content = content.decode('utf-8')
        print(f"\\n📝 TEXT CONTENT PREVIEW")
        print(f"├─ Character count: {{len(text_content):,}}")
        print(f"├─ Line count: {{text_content.count(chr(10)) + 1:,}}")
        print(f"└─ First 200 characters:")
        print(f"   {{repr(text_content[:200])}}")
        
    except UnicodeDecodeError:
        print(f"\\n🔒 BINARY FILE DETECTED")
        print(f"├─ Cannot display content as text")
        print(f"├─ File may contain images, documents, or other binary data")
        print(f"└─ Consider using appropriate tools for this file type")
    
    print(f"\\n✅ GENERIC ANALYSIS COMPLETED!")
    
except Exception as e:
    print(f"❌ Error in generic file analysis: {{str(e)}}")
    import traceback
    traceback.print_exc()
'''

def create_agentcore_session(object_key: str) -> Dict[str, Any]:
    """
    Create a new Bedrock AgentCore session for code interpretation
    
    Args:
        object_key: S3 object key for session naming
    
    Returns:
        AgentCore session response
    """
    try:
        session_name = f"DataAnalysis-{object_key.replace('/', '-').replace('.', '_')}-{int(time.time())}"
        
        session_response = bedrock_agentcore.start_code_interpreter_session(
            codeInterpreterIdentifier='aws.codeinterpreter.v1',
            name=session_name[:100],  # Ensure name length compliance
            sessionTimeoutSeconds=900  # 15 minutes timeout
        )
        
        return session_response
        
    except Exception as e:
        logger.error(f"Failed to create AgentCore session: {str(e)}")
        raise

def execute_analysis(session_id: str, analysis_code: str) -> Dict[str, Any]:
    """
    Execute analysis code in AgentCore environment
    
    Args:
        session_id: AgentCore session identifier
        analysis_code: Python code to execute
    
    Returns:
        Execution response from AgentCore
    """
    try:
        execution_response = bedrock_agentcore.invoke_code_interpreter(
            codeInterpreterIdentifier='aws.codeinterpreter.v1',
            sessionId=session_id,
            name='executeAnalysis',
            arguments={
                'language': 'python',
                'code': analysis_code
            }
        )
        
        return execution_response
        
    except Exception as e:
        logger.error(f"Failed to execute analysis in session {session_id}: {str(e)}")
        raise

def store_analysis_results(object_key: str, session_id: str, execution_response: Dict[str, Any], request_id: str) -> str:
    """
    Store analysis results and metadata in S3
    
    Args:
        object_key: Original file key
        session_id: AgentCore session ID
        execution_response: Response from code execution
        request_id: Lambda request ID
    
    Returns:
        S3 key where results were stored
    """
    try:
        # Create results metadata
        timestamp = datetime.now().isoformat()
        results_key = f"analysis-results/{object_key.replace('.', '_').replace('/', '_')}_analysis_{int(time.time())}.json"
        
        result_metadata = {
            'analysis_metadata': {
                'source_file': object_key,
                'session_id': session_id,
                'analysis_timestamp': timestamp,
                'lambda_request_id': request_id,
                'execution_status': 'completed'
            },
            'execution_details': execution_response,
            'generated_timestamp': timestamp
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
                'analysis-timestamp': timestamp
            }
        )
        
        logger.info(f"Analysis results stored at: {results_key}")
        return results_key
        
    except Exception as e:
        logger.error(f"Failed to store analysis results: {str(e)}")
        raise

def cleanup_session(session_id: str) -> None:
    """
    Clean up AgentCore session resources
    
    Args:
        session_id: Session to clean up
    """
    try:
        bedrock_agentcore.stop_code_interpreter_session(
            codeInterpreterIdentifier='aws.codeinterpreter.v1',
            sessionId=session_id
        )
        logger.info(f"Successfully cleaned up session: {session_id}")
        
    except Exception as e:
        logger.warning(f"Failed to cleanup session {session_id}: {str(e)}")
        # Don't raise exception for cleanup failures
`),
    });

    // Configure S3 event notification to trigger Lambda function
    dataBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(orchestratorFunction),
      {
        prefix: 'datasets/', // Only trigger for files in datasets/ folder
      }
    );

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'DataAnalysisDashboard', {
      dashboardName: `DataAnalysisAutomation-${uniqueSuffix}`,
      defaultInterval: Duration.minutes(5),
    });

    // Lambda function metrics widget
    const lambdaMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Data Analysis Lambda Metrics',
      width: 12,
      height: 6,
      left: [
        orchestratorFunction.metricInvocations({
          label: 'Invocations',
          color: cloudwatch.Color.BLUE,
        }),
        orchestratorFunction.metricDuration({
          label: 'Duration (ms)',
          color: cloudwatch.Color.GREEN,
        }),
        orchestratorFunction.metricErrors({
          label: 'Errors',
          color: cloudwatch.Color.RED,
        }),
      ],
      leftYAxis: {
        label: 'Count / Duration (ms)',
        showUnits: true,
      },
    });

    // Lambda logs insights widget
    const logsInsightsWidget = new cloudwatch.LogQueryWidget({
      title: 'Recent Analysis Activities',
      width: 12,
      height: 6,
      logGroups: [lambdaLogGroup],
      queryLines: [
        'fields @timestamp, @message',
        'filter @message like /Processing file/',
        'sort @timestamp desc',
        'limit 20',
      ],
    });

    // S3 metrics widget
    const s3MetricsWidget = new cloudwatch.GraphWidget({
      title: 'S3 Storage Metrics',
      width: 12,
      height: 6,
      left: [
        dataBucket.metric('NumberOfObjects', {
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Input Files',
          color: cloudwatch.Color.ORANGE,
        }),
        resultsBucket.metric('NumberOfObjects', {
          statistic: cloudwatch.Statistic.AVERAGE,
          label: 'Result Files',
          color: cloudwatch.Color.PURPLE,
        }),
      ],
      leftYAxis: {
        label: 'Object Count',
        showUnits: true,
      },
    });

    // Add widgets to dashboard
    dashboard.addWidgets(lambdaMetricsWidget);
    dashboard.addWidgets(logsInsightsWidget);
    dashboard.addWidgets(s3MetricsWidget);

    // Create CloudWatch Alarms for monitoring
    const errorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `DataAnalysisLambdaErrors-${uniqueSuffix}`,
      alarmDescription: 'Alarm for Lambda function errors in data analysis workflow',
      metric: orchestratorFunction.metricErrors({
        period: Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const durationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `DataAnalysisLambdaDuration-${uniqueSuffix}`,
      alarmDescription: 'Alarm for Lambda function duration exceeding threshold',
      metric: orchestratorFunction.metricDuration({
        period: Duration.minutes(5),
      }),
      threshold: 240000, // 4 minutes (80% of 5-minute timeout)
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Stack Outputs for easy access to resources
    new CfnOutput(this, 'DataBucketName', {
      value: dataBucket.bucketName,
      description: 'S3 bucket for uploading datasets to trigger analysis',
      exportName: `${this.stackName}-DataBucket`,
    });

    new CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'S3 bucket containing analysis results',
      exportName: `${this.stackName}-ResultsBucket`,
    });

    new CfnOutput(this, 'LambdaFunctionName', {
      value: orchestratorFunction.functionName,
      description: 'Lambda function orchestrating data analysis',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard for monitoring data analysis workflow',
      exportName: `${this.stackName}-Dashboard`,
    });

    new CfnOutput(this, 'LogGroupName', {
      value: lambdaLogGroup.logGroupName,
      description: 'CloudWatch Log Group for Lambda function logs',
      exportName: `${this.stackName}-LogGroup`,
    });

    // Add metadata tags to all resources
    cdk.Tags.of(this).add('Project', 'AutomatedDataAnalysis');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Service', 'BedrockAgentCore');
  }
}

// CDK Application
const app = new cdk.App();

// Create the stack with appropriate configuration
new AutomatedDataAnalysisStack(app, 'AutomatedDataAnalysisStack', {
  description: 'Automated Data Analysis using AWS Bedrock AgentCore Runtime (uksb-1tupboc58)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'AutomatedDataAnalysis',
    Repository: 'aws-recipes',
    Service: 'BedrockAgentCore',
  },
});

// Synthesize the stack
app.synth();