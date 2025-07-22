# Azure Function for Infrastructure Query Processing
# This function processes natural language queries from Azure Copilot Studio
# and converts them to KQL queries for Azure Monitor data retrieval

import logging
import json
import os
from datetime import datetime, timedelta
import azure.functions as func
from azure.monitor.query import LogsQueryClient
from azure.identity import DefaultAzureCredential

def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    Main function handler for processing infrastructure queries.
    
    This function receives natural language queries from Azure Copilot Studio,
    converts them to KQL statements, executes them against Log Analytics,
    and returns formatted responses suitable for conversational interfaces.
    """
    logging.info('Processing infrastructure query request from Copilot Studio')
    
    try:
        # Parse and validate request body
        req_body = req.get_json()
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Request body is required"}),
                mimetype="application/json",
                status_code=400
            )
        
        user_query = req_body.get('query', '').strip()
        if not user_query:
            return func.HttpResponse(
                json.dumps({"error": "Query parameter is required"}),
                mimetype="application/json",
                status_code=400
            )
        
        logging.info(f'Processing user query: {user_query}')
        
        # Initialize Azure Monitor client with managed identity
        credential = DefaultAzureCredential()
        client = LogsQueryClient(credential)
        
        # Convert natural language to KQL query
        kql_query = convert_to_kql(user_query)
        logging.info(f'Generated KQL query: {kql_query}')
        
        # Get workspace ID from environment variable
        workspace_id = os.environ.get('LOG_ANALYTICS_WORKSPACE_ID')
        if not workspace_id:
            raise ValueError("LOG_ANALYTICS_WORKSPACE_ID environment variable not set")
        
        # Execute query against Log Analytics workspace
        response = client.query_workspace(
            workspace_id=workspace_id,
            query=kql_query,
            timespan=timedelta(hours=1)
        )
        
        # Format response for chatbot consumption
        formatted_response = format_response(response, user_query)
        
        logging.info('Query processed successfully')
        return func.HttpResponse(
            json.dumps(formatted_response),
            mimetype="application/json",
            status_code=200
        )
        
    except Exception as e:
        error_msg = f"Error processing query: {str(e)}"
        logging.error(error_msg, exc_info=True)
        
        return func.HttpResponse(
            json.dumps({
                "error": "Failed to process your query. Please try again or rephrase your question.",
                "details": str(e) if os.environ.get('AZURE_FUNCTIONS_ENVIRONMENT') == 'Development' else None
            }),
            mimetype="application/json",
            status_code=500
        )

def convert_to_kql(user_query):
    """
    Convert natural language query to appropriate KQL statement.
    
    This function analyzes the user's natural language input and maps it
    to predefined KQL queries for common infrastructure monitoring scenarios.
    
    Args:
        user_query (str): Natural language query from the user
        
    Returns:
        str: KQL query string for execution against Log Analytics
    """
    query_lower = user_query.lower()
    
    # CPU-related queries
    if any(keyword in query_lower for keyword in ['cpu', 'processor', 'performance']):
        return """
        Perf
        | where CounterName == "% Processor Time"
        | where TimeGenerated > ago(1h)
        | summarize avg_cpu = avg(CounterValue), max_cpu = max(CounterValue) by Computer
        | order by avg_cpu desc
        | limit 10
        """
    
    # Memory-related queries
    elif any(keyword in query_lower for keyword in ['memory', 'ram', 'available memory']):
        return """
        Perf
        | where CounterName == "Available MBytes"
        | where TimeGenerated > ago(1h)
        | summarize avg_memory_mb = avg(CounterValue), min_memory_mb = min(CounterValue) by Computer
        | extend memory_gb = round(avg_memory_mb / 1024, 2)
        | order by avg_memory_mb asc
        | limit 10
        """
    
    # Disk space queries
    elif any(keyword in query_lower for keyword in ['disk', 'storage', 'free space', 'disk space']):
        return """
        Perf
        | where CounterName == "% Free Space"
        | where TimeGenerated > ago(1h)
        | summarize avg_free_space = avg(CounterValue), min_free_space = min(CounterValue) by Computer, InstanceName
        | where avg_free_space < 20  // Show systems with less than 20% free space
        | order by avg_free_space asc
        | limit 10
        """
    
    # Network-related queries
    elif any(keyword in query_lower for keyword in ['network', 'bandwidth', 'traffic']):
        return """
        Perf
        | where CounterName in ("Bytes Received/sec", "Bytes Sent/sec")
        | where TimeGenerated > ago(1h)
        | summarize avg_bytes = avg(CounterValue) by Computer, CounterName
        | extend avg_mbps = round(avg_bytes * 8 / 1000000, 2)
        | order by avg_mbps desc
        | limit 10
        """
    
    # Error and event queries
    elif any(keyword in query_lower for keyword in ['error', 'warning', 'alert', 'event']):
        return """
        Event
        | where TimeGenerated > ago(1h)
        | where EventLevelName in ("Error", "Warning")
        | summarize count() by Computer, EventLevelName, Source
        | order by count_ desc
        | limit 15
        """
    
    # Health and availability queries
    elif any(keyword in query_lower for keyword in ['health', 'status', 'online', 'offline', 'availability']):
        return """
        Heartbeat
        | where TimeGenerated > ago(1h)
        | summarize last_heartbeat = max(TimeGenerated) by Computer, OSType
        | extend status = case(
            last_heartbeat > ago(5m), "Online",
            last_heartbeat > ago(30m), "Recently Online",
            "Offline"
        )
        | order by last_heartbeat desc
        | limit 20
        """
    
    # Application-specific queries
    elif any(keyword in query_lower for keyword in ['application', 'app', 'service']):
        return """
        AppServiceHTTPLogs
        | where TimeGenerated > ago(1h)
        | summarize requests = count(), avg_response_time = avg(TimeTaken) by CsHost
        | order by requests desc
        | limit 10
        """
    
    # Default query for general system overview
    else:
        return """
        Heartbeat
        | where TimeGenerated > ago(1h)
        | summarize last_seen = max(TimeGenerated), heartbeat_count = count() by Computer, OSType
        | extend health_status = case(
            last_seen > ago(5m), "Healthy",
            last_seen > ago(30m), "Warning",
            "Critical"
        )
        | order by last_seen desc
        | limit 15
        """

def format_response(response, original_query):
    """
    Format Log Analytics response for conversational AI consumption.
    
    This function processes the raw query results and formats them into
    a user-friendly response suitable for display in chat interfaces.
    
    Args:
        response: Log Analytics query response object
        original_query (str): The original user query for context
        
    Returns:
        dict: Formatted response with message and data
    """
    if not response.tables or len(response.tables) == 0:
        return {
            "message": "No data found for your query. This could mean:\n• No matching resources in the timeframe\n• Resources may not be reporting data\n• Query parameters may need adjustment",
            "data": [],
            "query_info": {
                "original_query": original_query,
                "timeframe": "Last 1 hour",
                "status": "no_data"
            }
        }
    
    table = response.tables[0]
    results = []
    
    # Convert table rows to structured data
    for row in table.rows:
        result = {}
        for i, column in enumerate(table.columns):
            value = row[i]
            # Format datetime objects for better readability
            if isinstance(value, datetime):
                value = value.strftime("%Y-%m-%d %H:%M:%S UTC")
            result[column.name] = value
        results.append(result)
    
    # Generate contextual message based on query type and results
    message = generate_contextual_message(original_query, results)
    
    return {
        "message": message,
        "data": results[:10],  # Limit to top 10 results for readability
        "query_info": {
            "original_query": original_query,
            "timeframe": "Last 1 hour",
            "total_results": len(results),
            "status": "success"
        }
    }

def generate_contextual_message(query, results):
    """
    Generate a contextual response message based on the query type and results.
    
    Args:
        query (str): The original user query
        results (list): Query results from Log Analytics
        
    Returns:
        str: Contextual message for the user
    """
    query_lower = query.lower()
    result_count = len(results)
    
    if result_count == 0:
        return "No infrastructure data found for your query in the last hour."
    
    # CPU-related responses
    if 'cpu' in query_lower or 'processor' in query_lower:
        if result_count > 0:
            highest_cpu = max(results, key=lambda x: x.get('avg_cpu', 0))
            return f"Found CPU usage data for {result_count} systems. Highest average CPU usage: {highest_cpu.get('avg_cpu', 'N/A'):.1f}% on {highest_cpu.get('Computer', 'Unknown')}."
    
    # Memory-related responses
    elif 'memory' in query_lower or 'ram' in query_lower:
        if result_count > 0:
            lowest_memory = min(results, key=lambda x: x.get('avg_memory_mb', float('inf')))
            return f"Found memory data for {result_count} systems. Lowest available memory: {lowest_memory.get('memory_gb', 'N/A')} GB on {lowest_memory.get('Computer', 'Unknown')}."
    
    # Disk space responses
    elif 'disk' in query_lower or 'storage' in query_lower:
        if result_count > 0:
            critical_systems = [r for r in results if r.get('avg_free_space', 100) < 10]
            if critical_systems:
                return f"⚠️ Found {len(critical_systems)} systems with critically low disk space (< 10% free). Total systems analyzed: {result_count}."
            else:
                return f"Disk space analysis complete. {result_count} drives analyzed. No critical disk space issues detected."
    
    # Health status responses
    elif any(keyword in query_lower for keyword in ['health', 'status', 'online']):
        if result_count > 0:
            online_count = sum(1 for r in results if r.get('health_status') == 'Healthy' or r.get('status') == 'Online')
            return f"System health check complete. {online_count} of {result_count} systems are currently healthy and online."
    
    # Default response
    return f"Retrieved infrastructure data for {result_count} items matching your query."