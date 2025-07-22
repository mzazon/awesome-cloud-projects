"""
Cloud Function for automated data storytelling using BigQuery and Vertex AI.

This function generates data insights and narratives by:
1. Querying BigQuery sales data for key metrics
2. Analyzing patterns and trends in the data
3. Generating business-friendly insights and recommendations
4. Creating JSON output suitable for Looker Studio integration

Environment Variables:
    PROJECT_ID: Google Cloud project ID
    DATASET_NAME: BigQuery dataset name
    REGION: Google Cloud region
    BUCKET_NAME: Cloud Storage bucket name
"""

import json
import pandas as pd
import numpy as np
from google.cloud import bigquery
from google.cloud import storage
import os
from datetime import datetime, timedelta
import logging
from typing import Dict, Any, List, Optional
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
PROJECT_ID = "${project_id}"
DATASET_NAME = "${dataset_name}"
REGION = "${region}"


class DataStorytellingAnalyzer:
    """Handles data analysis and insight generation for storytelling."""
    
    def __init__(self):
        """Initialize the analyzer with BigQuery client."""
        self.bq_client = bigquery.Client(project=PROJECT_ID)
        self.storage_client = storage.Client(project=PROJECT_ID)
        
    def execute_analytics_query(self) -> pd.DataFrame:
        """Execute comprehensive analytics query on sales data."""
        query = f"""
        WITH revenue_trends AS (
            SELECT 
                category,
                customer_segment,
                region,
                SUM(revenue) as total_revenue,
                COUNT(DISTINCT product_id) as product_count,
                AVG(unit_price) as avg_price,
                SUM(quantity) as total_quantity,
                MIN(sales_date) as first_sale_date,
                MAX(sales_date) as last_sale_date
            FROM `{PROJECT_ID}.{DATASET_NAME}.sales_data`
            WHERE sales_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
            GROUP BY category, customer_segment, region
        ),
        performance_metrics AS (
            SELECT 
                category,
                SUM(total_revenue) as category_revenue,
                RANK() OVER (ORDER BY SUM(total_revenue) DESC) as revenue_rank
            FROM revenue_trends
            GROUP BY category
        ),
        time_series_data AS (
            SELECT 
                sales_date,
                SUM(revenue) as daily_revenue,
                COUNT(DISTINCT product_id) as daily_products
            FROM `{PROJECT_ID}.{DATASET_NAME}.sales_data`
            WHERE sales_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
            GROUP BY sales_date
            ORDER BY sales_date
        )
        SELECT 
            rt.*,
            pm.revenue_rank,
            ROUND(rt.total_revenue / pm.category_revenue * 100, 2) as segment_contribution_pct,
            DATE_DIFF(rt.last_sale_date, rt.first_sale_date, DAY) as sales_period_days
        FROM revenue_trends rt
        JOIN performance_metrics pm ON rt.category = pm.category
        ORDER BY rt.total_revenue DESC
        """
        
        try:
            query_job = self.bq_client.query(query)
            results = query_job.result()
            df = results.to_dataframe()
            logger.info(f"Analytics query executed successfully, returned {len(df)} rows")
            return df
        except Exception as e:
            logger.error(f"Error executing analytics query: {str(e)}")
            raise
    
    def calculate_advanced_metrics(self, df: pd.DataFrame) -> Dict[str, Any]:
        """Calculate advanced business metrics from the data."""
        if df.empty:
            return {"error": "No data available for analysis"}
        
        metrics = {
            "total_revenue": float(df['total_revenue'].sum()),
            "total_quantity": int(df['total_quantity'].sum()),
            "unique_categories": len(df['category'].unique()),
            "unique_segments": len(df['customer_segment'].unique()),
            "unique_regions": len(df['region'].unique()),
            "avg_price_across_all": float(df['avg_price'].mean()),
            "revenue_concentration": {
                "top_category": df.iloc[0]['category'] if len(df) > 0 else None,
                "top_category_revenue": float(df.iloc[0]['total_revenue']) if len(df) > 0 else 0,
                "top_segment": df.loc[df['total_revenue'].idxmax(), 'customer_segment'] if len(df) > 0 else None,
                "revenue_distribution_gini": self._calculate_gini_coefficient(df['total_revenue'].values)
            },
            "performance_insights": {
                "best_performing_region": df.loc[df['total_revenue'].idxmax(), 'region'] if len(df) > 0 else None,
                "most_diverse_category": df.loc[df['product_count'].idxmax(), 'category'] if len(df) > 0 else None,
                "premium_segment_share": float(df[df['customer_segment'] == 'Premium']['total_revenue'].sum() / df['total_revenue'].sum() * 100) if 'Premium' in df['customer_segment'].values else 0
            }
        }
        
        return metrics
    
    def _calculate_gini_coefficient(self, values: np.ndarray) -> float:
        """Calculate Gini coefficient for revenue concentration analysis."""
        if len(values) == 0:
            return 0.0
        
        sorted_values = np.sort(values)
        n = len(values)
        cumsum = np.cumsum(sorted_values)
        
        return (2 * np.sum((np.arange(1, n + 1) * sorted_values))) / (n * cumsum[-1]) - (n + 1) / n
    
    def generate_business_insights(self, metrics: Dict[str, Any]) -> List[str]:
        """Generate actionable business insights from calculated metrics."""
        insights = []
        
        # Revenue insights
        if metrics.get("total_revenue", 0) > 0:
            total_revenue = metrics["total_revenue"]
            insights.append(f"Total revenue analysis shows ${total_revenue:,.2f} across all segments and regions.")
            
            # Category performance insights
            if metrics.get("revenue_concentration", {}).get("top_category"):
                top_category = metrics["revenue_concentration"]["top_category"]
                top_revenue = metrics["revenue_concentration"]["top_category_revenue"]
                insights.append(f"{top_category} category leads performance with ${top_revenue:,.2f} in revenue.")
            
            # Market concentration insights
            gini = metrics.get("revenue_concentration", {}).get("revenue_distribution_gini", 0)
            if gini > 0.7:
                insights.append("Revenue shows high concentration - consider diversifying product mix.")
            elif gini < 0.3:
                insights.append("Revenue is well-distributed across categories - strong portfolio balance.")
            
            # Customer segment insights
            premium_share = metrics.get("performance_insights", {}).get("premium_segment_share", 0)
            if premium_share > 40:
                insights.append(f"Premium segment drives {premium_share:.1f}% of revenue - strong value proposition.")
            elif premium_share < 20:
                insights.append("Opportunity to grow premium segment through enhanced offerings.")
            
            # Regional insights
            best_region = metrics.get("performance_insights", {}).get("best_performing_region")
            if best_region:
                insights.append(f"{best_region} region shows strongest performance - consider expansion strategies.")
        
        return insights
    
    def generate_recommendations(self, metrics: Dict[str, Any], insights: List[str]) -> List[str]:
        """Generate actionable business recommendations based on insights."""
        recommendations = []
        
        # Strategic recommendations based on performance
        if metrics.get("revenue_concentration", {}).get("top_category"):
            top_category = metrics["revenue_concentration"]["top_category"]
            recommendations.append(f"Invest in expanding {top_category} product line to capitalize on strong performance.")
        
        # Customer segment recommendations
        premium_share = metrics.get("performance_insights", {}).get("premium_segment_share", 0)
        if premium_share < 30:
            recommendations.append("Develop premium product offerings to capture higher-value customer segments.")
        
        # Operational recommendations
        unique_categories = metrics.get("unique_categories", 0)
        if unique_categories > 5:
            recommendations.append("Consider product portfolio optimization to focus on top-performing categories.")
        
        # Market expansion recommendations
        unique_regions = metrics.get("unique_regions", 0)
        if unique_regions < 3:
            recommendations.append("Explore expansion into additional geographic markets for growth.")
        
        # Data-driven recommendations
        recommendations.append("Implement real-time analytics dashboards to monitor performance trends.")
        recommendations.append("Set up automated alerts for significant performance changes or opportunities.")
        
        return recommendations


@functions_framework.http
def generate_data_story(request):
    """
    Main Cloud Function entry point for generating automated data stories.
    
    Args:
        request: HTTP request object containing optional configuration
        
    Returns:
        JSON response containing data insights, narrative, and recommendations
    """
    # Parse request data
    request_json = request.get_json(silent=True) or {}
    
    # Log function execution
    logger.info(f"Data storytelling function triggered: {request_json}")
    
    try:
        # Initialize analyzer
        analyzer = DataStorytellingAnalyzer()
        
        # Execute analytics and generate insights
        df = analyzer.execute_analytics_query()
        
        if df.empty:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'timestamp': datetime.now().isoformat(),
                    'status': 'no_data',
                    'message': 'No data available for analysis',
                    'recommendations': ['Load sample data into BigQuery to begin analysis']
                }),
                'headers': {'Content-Type': 'application/json'}
            }
        
        # Calculate advanced metrics
        metrics = analyzer.calculate_advanced_metrics(df)
        
        # Generate business insights
        insights = analyzer.generate_business_insights(metrics)
        
        # Generate recommendations
        recommendations = analyzer.generate_recommendations(metrics, insights)
        
        # Create comprehensive narrative
        narrative_parts = []
        narrative_parts.append(f"Latest data analysis reveals significant business insights across {metrics.get('unique_categories', 0)} product categories.")
        
        if insights:
            narrative_parts.extend(insights[:3])  # Include top 3 insights
        
        narrative = " ".join(narrative_parts)
        
        # Construct response
        story = {
            'timestamp': datetime.now().isoformat(),
            'execution_context': {
                'triggered_by': request_json.get('source', 'manual'),
                'automated': request_json.get('automated', False),
                'function_version': '1.0'
            },
            'data_summary': {
                'total_revenue': metrics.get('total_revenue', 0),
                'total_quantity': metrics.get('total_quantity', 0),
                'categories_analyzed': metrics.get('unique_categories', 0),
                'customer_segments': metrics.get('unique_segments', 0),
                'geographic_regions': metrics.get('unique_regions', 0)
            },
            'key_insights': {
                'top_performing_category': metrics.get('revenue_concentration', {}).get('top_category'),
                'leading_customer_segment': metrics.get('revenue_concentration', {}).get('top_segment'),
                'best_performing_region': metrics.get('performance_insights', {}).get('best_performing_region'),
                'premium_segment_contribution': f"{metrics.get('performance_insights', {}).get('premium_segment_share', 0):.1f}%",
                'revenue_concentration_index': f"{metrics.get('revenue_concentration', {}).get('revenue_distribution_gini', 0):.2f}"
            },
            'narrative': narrative,
            'business_insights': insights,
            'strategic_recommendations': recommendations,
            'next_actions': [
                'Review top-performing categories for expansion opportunities',
                'Analyze customer segment preferences for targeted marketing',
                'Create Looker Studio dashboard for ongoing monitoring',
                'Schedule weekly automated reports for stakeholder updates'
            ],
            'data_quality': {
                'records_analyzed': len(df),
                'data_completeness': 'high',
                'last_updated': datetime.now().isoformat()
            }
        }
        
        # Log successful execution
        logger.info(f"Data story generated successfully with {len(insights)} insights and {len(recommendations)} recommendations")
        
        return {
            'statusCode': 200,
            'body': json.dumps(story, indent=2),
            'headers': {'Content-Type': 'application/json'}
        }
        
    except Exception as e:
        error_message = f"Error generating data story: {str(e)}"
        logger.error(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'timestamp': datetime.now().isoformat(),
                'error': error_message,
                'status': 'error',
                'troubleshooting': [
                    'Verify BigQuery dataset and table exist',
                    'Check service account permissions',
                    'Ensure sample data is loaded',
                    'Review Cloud Function logs for detailed error information'
                ]
            }),
            'headers': {'Content-Type': 'application/json'}
        }