import json
import pandas as pd
from google.cloud import bigquery
from google.cloud import aiplatform
from google.cloud import storage
import functions_framework
from datetime import datetime, timedelta
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
bq_client = bigquery.Client()
storage_client = storage.Client()

@functions_framework.http
def analyze_content(request):
    """
    Analyze content performance and generate optimization recommendations using Gemini AI.
    
    This Cloud Function integrates BigQuery analytics with Vertex AI Gemini to:
    - Query content performance data from BigQuery
    - Analyze patterns using Gemini ${gemini_model}
    - Generate actionable optimization recommendations
    - Store results in Cloud Storage
    
    Args:
        request: HTTP request object (Flask request)
        
    Returns:
        JSON response with analysis status and results location
    """
    
    # Get environment variables
    project_id = os.environ.get('GCP_PROJECT')
    dataset_name = os.environ.get('DATASET_NAME')
    bucket_name = os.environ.get('BUCKET_NAME')
    table_name = os.environ.get('TABLE_NAME', 'performance_data')
    gemini_model = os.environ.get('GEMINI_MODEL', '${gemini_model}')
    
    # Validate required environment variables
    if not all([project_id, dataset_name, bucket_name]):
        logger.error("Missing required environment variables")
        return {
            'status': 'error',
            'message': 'Missing required environment variables: GCP_PROJECT, DATASET_NAME, BUCKET_NAME'
        }, 400
    
    try:
        logger.info(f"Starting content analysis for project: {project_id}")
        
        # Query recent content performance data from BigQuery
        query = f"""
        SELECT 
            content_id,
            title,
            content_type,
            page_views,
            engagement_rate,
            conversion_rate,
            time_on_page,
            social_shares,
            content_score,
            publish_date
        FROM `{project_id}.{dataset_name}.{table_name}`
        WHERE publish_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        ORDER BY content_score DESC
        LIMIT 50
        """
        
        logger.info("Executing BigQuery query for content data")
        query_job = bq_client.query(query)
        results = query_job.result()
        
        # Convert BigQuery results to DataFrame for analysis
        data = []
        for row in results:
            data.append({
                'content_id': row.content_id,
                'title': row.title,
                'content_type': row.content_type,
                'page_views': row.page_views or 0,
                'engagement_rate': row.engagement_rate or 0.0,
                'conversion_rate': row.conversion_rate or 0.0,
                'time_on_page': row.time_on_page or 0.0,
                'social_shares': row.social_shares or 0,
                'content_score': row.content_score or 0.0,
                'publish_date': row.publish_date.isoformat() if row.publish_date else None
            })
        
        df = pd.DataFrame(data)
        
        if df.empty:
            logger.warning("No content data found for analysis")
            return {
                'status': 'no_data',
                'message': 'No content data found for the last 30 days'
            }
        
        logger.info(f"Analyzing {len(df)} content items")
        
        # Prepare data summary for Gemini analysis
        content_summary = df.to_string(index=False, max_rows=20)
        
        # Calculate additional insights
        top_performers = df.nlargest(5, 'content_score')
        avg_metrics = {
            'avg_page_views': df['page_views'].mean(),
            'avg_engagement_rate': df['engagement_rate'].mean(),
            'avg_conversion_rate': df['conversion_rate'].mean(),
            'avg_content_score': df['content_score'].mean()
        }
        
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location='us-central1')
        
        # Create comprehensive Gemini prompt for content analysis
        prompt = f"""
        Analyze the following content performance data and provide detailed optimization recommendations:
        
        CONTENT PERFORMANCE DATA:
        {content_summary}
        
        SUMMARY METRICS:
        - Average Page Views: {avg_metrics['avg_page_views']:.2f}
        - Average Engagement Rate: {avg_metrics['avg_engagement_rate']:.2f}
        - Average Conversion Rate: {avg_metrics['avg_conversion_rate']:.2f}
        - Average Content Score: {avg_metrics['avg_content_score']:.2f}
        
        Please provide a comprehensive analysis including:
        
        1. TOP PERFORMING CONTENT CHARACTERISTICS:
           - Identify the top 3 characteristics of highest-performing content
           - Analyze patterns in content types, engagement metrics, and performance scores
           
        2. CONTENT OPTIMIZATION RECOMMENDATIONS:
           - Specific recommendations for underperforming content pieces
           - Actionable strategies to improve engagement and conversion rates
           
        3. CONTENT STRATEGY INSIGHTS:
           - Recommended content types to focus on
           - Optimal content characteristics for better performance
           
        4. KEY PERFORMANCE INDICATORS:
           - Most important metrics to monitor for content success
           - Benchmarks for different content types
           
        5. CONTENT VARIATIONS SUGGESTIONS:
           - Specific variations to test for top-performing content
           - A/B testing recommendations
        
        Format your response as structured JSON with clear sections and actionable recommendations.
        """
        
        # Generate content analysis with Gemini
        logger.info(f"Generating analysis with {gemini_model}")
        from vertexai.generative_models import GenerativeModel
        
        model = GenerativeModel(gemini_model)
        response = model.generate_content(prompt)
        
        # Prepare comprehensive analysis results
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        blob_name = f'analysis_results/content_analysis_{timestamp}.json'
        
        analysis_result = {
            'analysis_metadata': {
                'timestamp': timestamp,
                'gemini_model': gemini_model,
                'data_analyzed': len(df),
                'analysis_period': '30 days',
                'project_id': project_id
            },
            'summary_metrics': avg_metrics,
            'top_performers': top_performers.to_dict('records'),
            'gemini_analysis': response.text,
            'data_sample': df.head(10).to_dict('records'),
            'content_type_breakdown': df['content_type'].value_counts().to_dict()
        }
        
        # Store analysis results in Cloud Storage
        logger.info("Storing analysis results in Cloud Storage")
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        blob.upload_from_string(
            json.dumps(analysis_result, indent=2),
            content_type='application/json'
        )
        
        logger.info("Content analysis completed successfully")
        
        return {
            'status': 'success',
            'analysis_file': f'gs://{bucket_name}/{blob_name}',
            'content_analyzed': len(df),
            'top_performer_score': float(top_performers.iloc[0]['content_score']) if not top_performers.empty else 0,
            'recommendations_available': True,
            'analysis_timestamp': timestamp,
            'gemini_model_used': gemini_model,
            'summary_url': f'https://console.cloud.google.com/storage/browser/{bucket_name}/analysis_results?project={project_id}'
        }
        
    except Exception as e:
        logger.error(f"Error during content analysis: {str(e)}", exc_info=True)
        return {
            'status': 'error',
            'message': str(e),
            'error_type': type(e).__name__
        }, 500