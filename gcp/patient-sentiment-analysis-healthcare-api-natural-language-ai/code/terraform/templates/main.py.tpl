import json
import base64
import logging
from google.cloud import language_v1
from google.cloud import bigquery
from google.cloud import healthcare_v1
import functions_framework

# Initialize clients
language_client = language_v1.LanguageServiceClient()
bq_client = bigquery.Client()
healthcare_client = healthcare_v1.FhirServiceClient()

@functions_framework.cloud_event
def process_fhir_sentiment(cloud_event):
    """Process FHIR events and perform sentiment analysis."""
    
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(cloud_event.data["message"]["data"])
        event_data = json.loads(pubsub_message.decode())
        
        logging.info(f"Processing FHIR event: {event_data}")
        
        # Extract FHIR resource information
        resource_name = event_data.get("name", "")
        event_type = event_data.get("eventType", "")
        
        if "Observation" in resource_name and event_type in ["CREATED", "UPDATED"]:
            # Fetch FHIR resource
            response = healthcare_client.get_fhir_resource(name=resource_name)
            fhir_resource = json.loads(response.data.decode())
            
            # Extract text content from FHIR observation
            text_content = extract_text_from_observation(fhir_resource)
            
            if text_content:
                # Perform sentiment analysis
                sentiment_result = analyze_sentiment(text_content)
                
                # Store results in BigQuery
                store_sentiment_results(fhir_resource, text_content, sentiment_result)
                
                logging.info(f"Sentiment analysis completed for {resource_name}")
        
    except Exception as e:
        logging.error(f"Error processing FHIR event: {str(e)}")

def extract_text_from_observation(fhir_resource):
    """Extract text content from FHIR Observation resource."""
    text_content = ""
    
    # Extract from valueString
    if "valueString" in fhir_resource:
        text_content += fhir_resource["valueString"] + " "
    
    # Extract from note field
    if "note" in fhir_resource:
        for note in fhir_resource["note"]:
            if "text" in note:
                text_content += note["text"] + " "
    
    # Extract from component values
    if "component" in fhir_resource:
        for component in fhir_resource["component"]:
            if "valueString" in component:
                text_content += component["valueString"] + " "
    
    return text_content.strip()

def analyze_sentiment(text_content):
    """Analyze sentiment using Natural Language AI."""
    document = language_v1.Document(
        content=text_content,
        type_=language_v1.Document.Type.PLAIN_TEXT
    )
    
    response = language_client.analyze_sentiment(
        request={"document": document}
    )
    
    sentiment = response.document_sentiment
    
    # Determine overall sentiment category
    if sentiment.score > 0.25:
        overall_sentiment = "POSITIVE"
    elif sentiment.score < -0.25:
        overall_sentiment = "NEGATIVE"
    else:
        overall_sentiment = "NEUTRAL"
    
    return {
        "score": sentiment.score,
        "magnitude": sentiment.magnitude,
        "overall_sentiment": overall_sentiment
    }

def store_sentiment_results(fhir_resource, text_content, sentiment_result):
    """Store sentiment analysis results in BigQuery."""
    import os
    from datetime import datetime
    
    project_id = "${project_id}"
    dataset_id = "${bigquery_dataset}"
    table_id = "${bigquery_table}"
    
    table_ref = bq_client.dataset(dataset_id).table(table_id)
    table = bq_client.get_table(table_ref)
    
    # Extract patient ID and observation ID
    patient_id = fhir_resource.get("subject", {}).get("reference", "").replace("Patient/", "")
    observation_id = fhir_resource.get("id", "unknown")
    
    row = {
        "patient_id": patient_id,
        "observation_id": observation_id,
        "text_content": text_content,
        "sentiment_score": sentiment_result["score"],
        "magnitude": sentiment_result["magnitude"],
        "overall_sentiment": sentiment_result["overall_sentiment"],
        "processing_timestamp": datetime.utcnow().isoformat(),
        "fhir_resource_type": "Observation"
    }
    
    errors = bq_client.insert_rows_json(table, [row])
    if errors:
        logging.error(f"BigQuery insert errors: {errors}")
    else:
        logging.info("Sentiment results stored in BigQuery")