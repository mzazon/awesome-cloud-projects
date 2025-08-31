"""
Vertex AI Agent implementation for intelligent resource optimization.
This agent provides natural language interface to asset optimization data.
"""

import json
import logging
from typing import Dict, List, Any, Optional

import vertexai
from vertexai import agent_engines
from google.cloud import bigquery
from google.cloud.exceptions import GoogleCloudError
import pandas as pd

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
PROJECT_ID = "${project_id}"
REGION = "${region}"
DATASET_NAME = "${dataset_name}"
STAGING_BUCKET = "gs://${bucket_name}"

# Model configuration
MODEL_NAME = "${model}"
TEMPERATURE = ${temperature}
MAX_TOKENS = ${max_tokens}


class OptimizationDataQuery:
    """Handles BigQuery operations for asset optimization data."""
    
    def __init__(self, project_id: str, dataset_name: str):
        self.project_id = project_id
        self.dataset_name = dataset_name
        self.client = bigquery.Client(project=project_id)
    
    def query_optimization_summary(self, limit: int = 10) -> str:
        """
        Query optimization data summary from BigQuery.
        
        Args:
            limit: Maximum number of results to return
            
        Returns:
            JSON string with optimization summary data
        """
        query = f"""
        SELECT 
            optimization_category,
            resource_count,
            avg_optimization_score,
            total_impact_score,
            category_recommendation,
            potential_savings_level
        FROM `{self.project_id}.{self.dataset_name}.cost_impact_summary`
        ORDER BY total_impact_score DESC
        LIMIT {limit}
        """
        
        try:
            results = self.client.query(query).to_dataframe()
            return results.to_json(orient='records', indent=2)
        except Exception as e:
            logger.error(f"Error querying optimization summary: {e}")
            return json.dumps({"error": f"Failed to query data: {str(e)}"})
    
    def query_high_priority_resources(self, score_threshold: int = 70, limit: int = 20) -> str:
        """
        Query high priority optimization opportunities.
        
        Args:
            score_threshold: Minimum optimization score for high priority
            limit: Maximum number of results to return
            
        Returns:
            JSON string with high priority resources
        """
        query = f"""
        SELECT 
            name,
            asset_type,
            optimization_category,
            optimization_score,
            optimization_recommendation,
            location,
            age_days,
            status
        FROM `{self.project_id}.{self.dataset_name}.resource_optimization_analysis`
        WHERE optimization_score >= {score_threshold}
        ORDER BY optimization_score DESC
        LIMIT {limit}
        """
        
        try:
            results = self.client.query(query).to_dataframe()
            return results.to_json(orient='records', indent=2)
        except Exception as e:
            logger.error(f"Error querying high priority resources: {e}")
            return json.dumps({"error": f"Failed to query data: {str(e)}"})
    
    def query_resource_statistics(self) -> str:
        """
        Query overall resource statistics.
        
        Returns:
            JSON string with resource statistics
        """
        query = f"""
        SELECT 
            COUNT(*) as total_resources,
            COUNT(CASE WHEN optimization_score > 70 THEN 1 END) as high_priority_count,
            COUNT(CASE WHEN optimization_score BETWEEN 40 AND 70 THEN 1 END) as medium_priority_count,
            COUNT(CASE WHEN optimization_score < 40 THEN 1 END) as low_priority_count,
            AVG(optimization_score) as avg_optimization_score,
            MIN(optimization_score) as min_score,
            MAX(optimization_score) as max_score,
            COUNT(DISTINCT optimization_category) as unique_categories,
            COUNT(DISTINCT location) as unique_locations
        FROM `{self.project_id}.{self.dataset_name}.resource_optimization_analysis`
        """
        
        try:
            results = self.client.query(query).to_dataframe()
            return results.to_json(orient='records', indent=2)
        except Exception as e:
            logger.error(f"Error querying resource statistics: {e}")
            return json.dumps({"error": f"Failed to query data: {str(e)}"})
    
    def query_category_breakdown(self, category: Optional[str] = None) -> str:
        """
        Query resources by optimization category.
        
        Args:
            category: Specific category to filter by (optional)
            
        Returns:
            JSON string with category breakdown
        """
        where_clause = f"WHERE optimization_category = '{category}'" if category else ""
        
        query = f"""
        SELECT 
            optimization_category,
            COUNT(*) as resource_count,
            AVG(optimization_score) as avg_score,
            MIN(age_days) as min_age_days,
            MAX(age_days) as max_age_days,
            COUNT(DISTINCT location) as locations_count,
            STRING_AGG(DISTINCT asset_type) as asset_types
        FROM `{self.project_id}.{self.dataset_name}.resource_optimization_analysis`
        {where_clause}
        GROUP BY optimization_category
        ORDER BY resource_count DESC
        """
        
        try:
            results = self.client.query(query).to_dataframe()
            return results.to_json(orient='records', indent=2)
        except Exception as e:
            logger.error(f"Error querying category breakdown: {e}")
            return json.dumps({"error": f"Failed to query data: {str(e)}"})


# Initialize BigQuery data query handler
data_query = OptimizationDataQuery(PROJECT_ID, DATASET_NAME)


def query_optimization_data(query_type: str = "summary", **kwargs) -> str:
    """
    Main function to query asset optimization data from BigQuery.
    This function is used as a tool by the Vertex AI agent.
    
    Args:
        query_type: Type of query to execute (summary, high_priority, statistics, category)
        **kwargs: Additional parameters for specific query types
    
    Returns:
        JSON string with query results
    """
    try:
        if query_type == "summary":
            limit = kwargs.get('limit', 10)
            return data_query.query_optimization_summary(limit)
        
        elif query_type == "high_priority":
            score_threshold = kwargs.get('score_threshold', 70)
            limit = kwargs.get('limit', 20)
            return data_query.query_high_priority_resources(score_threshold, limit)
        
        elif query_type == "statistics":
            return data_query.query_resource_statistics()
        
        elif query_type == "category":
            category = kwargs.get('category')
            return data_query.query_category_breakdown(category)
        
        else:
            # Default to statistics
            return data_query.query_resource_statistics()
    
    except Exception as e:
        logger.error(f"Error in query_optimization_data: {e}")
        return json.dumps({
            "error": f"Failed to query optimization data: {str(e)}",
            "query_type": query_type,
            "available_types": ["summary", "high_priority", "statistics", "category"]
        })


def analyze_cost_savings(optimization_category: str = None) -> str:
    """
    Analyze potential cost savings for optimization opportunities.
    
    Args:
        optimization_category: Specific category to analyze (optional)
    
    Returns:
        JSON string with cost savings analysis
    """
    try:
        where_clause = f"WHERE optimization_category = '{optimization_category}'" if optimization_category else ""
        
        query = f"""
        SELECT 
            optimization_category,
            COUNT(*) as resource_count,
            AVG(optimization_score) as avg_score,
            CASE optimization_category
                WHEN 'Idle Compute' THEN COUNT(*) * 50  -- Estimated $50/month per idle instance
                WHEN 'Unattached Storage' THEN COUNT(*) * 20  -- Estimated $20/month per unattached disk
                WHEN 'Idle Cluster' THEN COUNT(*) * 200  -- Estimated $200/month per idle cluster
                WHEN 'Suspended Database' THEN COUNT(*) * 100  -- Estimated $100/month per suspended DB
                ELSE COUNT(*) * 10  -- Default $10/month
            END as estimated_monthly_savings_usd,
            category_recommendation
        FROM `{PROJECT_ID}.{DATASET_NAME}.cost_impact_summary`
        {where_clause}
        GROUP BY optimization_category, category_recommendation
        ORDER BY estimated_monthly_savings_usd DESC
        """
        
        results = data_query.client.query(query).to_dataframe()
        return results.to_json(orient='records', indent=2)
    
    except Exception as e:
        logger.error(f"Error analyzing cost savings: {e}")
        return json.dumps({"error": f"Failed to analyze cost savings: {str(e)}"})


def get_optimization_recommendations(priority_level: str = "high") -> str:
    """
    Get specific optimization recommendations based on priority level.
    
    Args:
        priority_level: Priority level (high, medium, low)
    
    Returns:
        JSON string with optimization recommendations
    """
    try:
        if priority_level == "high":
            score_filter = "optimization_score >= 70"
        elif priority_level == "medium":
            score_filter = "optimization_score >= 40 AND optimization_score < 70"
        else:  # low
            score_filter = "optimization_score < 40"
        
        query = f"""
        SELECT 
            optimization_category,
            COUNT(*) as resource_count,
            optimization_recommendation,
            AVG(optimization_score) as avg_score,
            STRING_AGG(DISTINCT location) as locations
        FROM `{PROJECT_ID}.{DATASET_NAME}.resource_optimization_analysis`
        WHERE {score_filter}
        GROUP BY optimization_category, optimization_recommendation
        ORDER BY COUNT(*) DESC
        """
        
        results = data_query.client.query(query).to_dataframe()
        return results.to_json(orient='records', indent=2)
    
    except Exception as e:
        logger.error(f"Error getting recommendations: {e}")
        return json.dumps({"error": f"Failed to get recommendations: {str(e)}"})


# Initialize Vertex AI
try:
    vertexai.init(
        project=PROJECT_ID,
        location=REGION,
        staging_bucket=STAGING_BUCKET
    )
    logger.info(f"Vertex AI initialized for project {PROJECT_ID} in region {REGION}")
except Exception as e:
    logger.error(f"Failed to initialize Vertex AI: {e}")
    raise


# Create the optimization agent with BigQuery tools
agent = agent_engines.LangchainAgent(
    model=MODEL_NAME,
    tools=[
        query_optimization_data,
        analyze_cost_savings,
        get_optimization_recommendations
    ],
    model_kwargs={
        "temperature": TEMPERATURE,
        "max_output_tokens": MAX_TOKENS,
        "top_p": 0.95,
    },
    system_message="""
    You are an intelligent cloud resource optimization assistant powered by real-time Google Cloud asset inventory data. 
    Your role is to help users understand their cloud infrastructure, identify cost optimization opportunities, 
    and provide actionable recommendations for reducing cloud spend while maintaining performance.

    Key capabilities:
    1. Analyze cloud asset inventory data from BigQuery
    2. Identify idle, underutilized, or misconfigured resources
    3. Provide cost savings estimates and recommendations
    4. Explain optimization strategies in business terms
    5. Prioritize optimization opportunities by impact

    Guidelines:
    - Always query the latest data when answering questions
    - Provide specific, actionable recommendations
    - Include estimated cost savings when possible
    - Explain the business impact of optimizations
    - Use clear, non-technical language for business stakeholders
    - Ask clarifying questions when needed
    - Focus on the highest impact optimizations first

    Available data includes:
    - Cloud asset inventory with optimization scores
    - Resource utilization patterns and age
    - Cost impact summaries by category
    - Location and project distributions
    - Historical trends and patterns
    """
)

logger.info("Resource optimization agent created successfully")


# Example usage and testing functions
def test_agent_queries():
    """Test function to validate agent functionality."""
    test_queries = [
        "What are the top 5 cost optimization opportunities in my infrastructure?",
        "Show me all idle compute instances",
        "How much money could I save by optimizing high-priority resources?",
        "What are the most common optimization categories?",
        "Give me a summary of all resources with optimization scores above 70"
    ]
    
    for query in test_queries:
        try:
            logger.info(f"Testing query: {query}")
            response = agent.query(input=query)
            logger.info(f"Response: {response[:200]}...")  # Log first 200 chars
        except Exception as e:
            logger.error(f"Error testing query '{query}': {e}")


if __name__ == "__main__":
    # Run tests if executed directly
    test_agent_queries()