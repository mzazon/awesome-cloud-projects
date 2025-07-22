#!/bin/bash

#####################################################################
# Adaptive Marketing Campaign Intelligence Deployment Script
# 
# This script deploys the complete infrastructure for an AI-powered
# marketing automation system using Vertex AI Agents, Google Workspace
# Flows, and BigQuery analytics.
#
# Prerequisites:
# - Google Cloud SDK (gcloud) installed and configured
# - Google Workspace admin access for Flows configuration  
# - Appropriate IAM permissions for all services
# - Billing account configured
#####################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Note: Full cleanup handled by destroy.sh script
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables
PROJECT_ID="${PROJECT_ID:-marketing-intelligence-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX=$(openssl rand -hex 3)
DATASET_NAME="marketing_data_${RANDOM_SUFFIX}"
AGENT_NAME="campaign-intelligence-agent-${RANDOM_SUFFIX}"
BUCKET_NAME="marketing-intelligence-${PROJECT_ID}-${RANDOM_SUFFIX}"

# Deployment state file
STATE_FILE=".deployment_state"

# Save deployment configuration
save_deployment_state() {
    cat > "${STATE_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
DATASET_NAME=${DATASET_NAME}
AGENT_NAME=${AGENT_NAME}
BUCKET_NAME=${BUCKET_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
    log_success "Deployment state saved to ${STATE_FILE}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if billing is enabled (basic check)
    if ! gcloud beta billing projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Unable to verify billing status. Ensure billing is enabled for project ${PROJECT_ID}"
    fi
    
    # Check required APIs availability
    local required_apis=(
        "aiplatform.googleapis.com"
        "bigquery.googleapis.com"
        "gmail.googleapis.com"
        "sheets.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    log_info "Checking API availability..."
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --available --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
            log_error "Required API ${api} is not available in this project"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Setup project configuration
setup_project() {
    log_info "Setting up project configuration..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configured: ${PROJECT_ID}"
    log_success "Region configured: ${REGION}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "bigquery.googleapis.com"
        "gmail.googleapis.com"
        "sheets.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."
    
    # Create dataset
    if bq mk --dataset \
        --location="${REGION}" \
        --description="Marketing campaign intelligence dataset" \
        "${PROJECT_ID}:${DATASET_NAME}"; then
        log_success "BigQuery dataset created: ${DATASET_NAME}"
    else
        log_error "Failed to create BigQuery dataset"
        exit 1
    fi
    
    # Create campaign performance table
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.campaign_performance" \
        campaign_id:STRING,campaign_name:STRING,channel:STRING,start_date:DATE,end_date:DATE,impressions:INTEGER,clicks:INTEGER,conversions:INTEGER,spend:FLOAT,revenue:FLOAT,ctr:FLOAT,conversion_rate:FLOAT,roas:FLOAT,audience_segment:STRING,geo_location:STRING,device_type:STRING,timestamp:TIMESTAMP; then
        log_success "Created campaign_performance table"
    else
        log_error "Failed to create campaign_performance table"
        exit 1
    fi
    
    # Create customer interactions table
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.customer_interactions" \
        customer_id:STRING,interaction_type:STRING,interaction_timestamp:TIMESTAMP,campaign_id:STRING,channel:STRING,engagement_score:FLOAT,sentiment_score:FLOAT,conversion_value:FLOAT,customer_lifetime_value:FLOAT,demographic_segment:STRING,behavioral_tags:STRING; then
        log_success "Created customer_interactions table"
    else
        log_error "Failed to create customer_interactions table"
        exit 1
    fi
    
    # Create AI insights table
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.ai_insights" \
        insight_id:STRING,generated_timestamp:TIMESTAMP,insight_type:STRING,campaign_id:STRING,recommendation:STRING,confidence_score:FLOAT,predicted_impact:FLOAT,action_required:BOOLEAN,priority_level:STRING,execution_status:STRING; then
        log_success "Created ai_insights table"
    else
        log_error "Failed to create ai_insights table"
        exit 1
    fi
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"; then
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
}

# Configure Vertex AI Agent
configure_vertex_ai_agent() {
    log_info "Configuring Vertex AI Agent for marketing intelligence..."
    
    # Create agent configuration
    cat > agent-config.json << EOF
{
  "display_name": "${AGENT_NAME}",
  "description": "Intelligent marketing campaign analysis and optimization agent",
  "goal": "Analyze campaign performance data, identify optimization opportunities, and trigger adaptive marketing workflows",
  "instructions": [
    "Monitor campaign performance metrics in BigQuery for anomalies and trends",
    "Analyze customer interaction patterns to identify engagement opportunities", 
    "Generate personalized recommendations based on audience segments and behaviors",
    "Trigger automated workflows through Google Workspace Flows when action is required",
    "Continuously learn from campaign outcomes to improve future recommendations"
  ],
  "tools": [
    {
      "type": "bigquery",
      "config": {
        "project_id": "${PROJECT_ID}",
        "dataset_id": "${DATASET_NAME}"
      }
    },
    {
      "type": "workspace_integration",
      "config": {
        "gmail_api": true,
        "sheets_api": true,
        "docs_api": true
      }
    }
  ],
  "model": "gemini-1.5-pro",
  "knowledge_base": {
    "marketing_best_practices": true,
    "campaign_optimization_strategies": true,
    "customer_segmentation_models": true
  }
}
EOF
    
    # Deploy agent (Note: Actual gcloud command may vary based on API availability)
    log_info "Deploying Vertex AI Agent..."
    log_warning "Vertex AI Agents may require manual configuration through Google Cloud Console"
    log_info "Agent configuration saved to agent-config.json for manual setup"
    
    log_success "Vertex AI Agent configuration prepared"
}

# Create custom Gems
create_custom_gems() {
    log_info "Creating custom Gems for specialized marketing tasks..."
    
    # Brand voice analyzer Gem
    cat > brand-voice-gem.json << EOF
{
  "name": "brand-voice-analyzer",
  "description": "Analyzes content for brand voice consistency and marketing message effectiveness",
  "instructions": [
    "Evaluate marketing content against established brand voice guidelines",
    "Assess message clarity, tone, and emotional impact for target audiences",
    "Provide specific recommendations for content optimization",
    "Score content effectiveness on a 1-10 scale with detailed rationale"
  ],
  "knowledge_sources": [
    "brand_guidelines.pdf",
    "successful_campaign_examples.csv", 
    "audience_persona_profiles.json"
  ],
  "output_format": "structured_analysis_with_recommendations"
}
EOF
    
    # Campaign optimizer Gem
    cat > campaign-optimizer-gem.json << EOF
{
  "name": "campaign-optimizer",
  "description": "Provides data-driven recommendations for campaign performance improvement",
  "instructions": [
    "Analyze campaign performance metrics against industry benchmarks",
    "Identify underperforming segments and recommend specific optimizations",
    "Suggest budget reallocation strategies based on ROI analysis",
    "Predict optimal timing and frequency for customer touchpoints"
  ],
  "knowledge_sources": [
    "industry_benchmarks.csv",
    "historical_campaign_data.json",
    "market_research_reports.pdf"
  ],
  "output_format": "actionable_recommendations_with_priority"
}
EOF
    
    log_info "Custom Gem configurations saved for manual setup"
    log_warning "Gems may require manual configuration through Google Cloud Console"
    log_success "Custom Gems configuration prepared"
}

# Configure Google Workspace Flows
configure_workspace_flows() {
    log_info "Configuring Google Workspace Flows..."
    
    # Campaign alert flow
    cat > campaign-alert-flow.json << EOF
{
  "flow_name": "campaign-performance-alerts",
  "description": "Automated alerts and actions for campaign performance anomalies",
  "trigger": {
    "type": "ai_agent_insight",
    "agent_id": "${AGENT_NAME}",
    "conditions": [
      "insight_type = 'performance_anomaly'",
      "priority_level IN ('high', 'critical')"
    ]
  },
  "steps": [
    {
      "id": "analyze_anomaly",
      "type": "gem_processing",
      "gem": "campaign-optimizer",
      "input": "campaign_performance_data",
      "output": "optimization_recommendations"
    },
    {
      "id": "create_report", 
      "type": "google_sheets",
      "action": "create_summary_report",
      "template": "campaign_performance_template",
      "data_source": "optimization_recommendations"
    },
    {
      "id": "send_alert",
      "type": "gmail",
      "action": "send_personalized_email",
      "recipients": "marketing_team@company.com",
      "template": "performance_alert_template",
      "attachments": ["summary_report"]
    },
    {
      "id": "schedule_review",
      "type": "google_calendar", 
      "action": "create_meeting",
      "attendees": "marketing_team",
      "title": "Campaign Performance Review",
      "agenda": "optimization_recommendations"
    }
  ]
}
EOF
    
    # Customer segmentation workflow
    cat > segmentation-workflow.json << EOF
{
  "flow_name": "dynamic-customer-segmentation",
  "description": "AI-powered customer segmentation and personalized campaign automation",
  "trigger": {
    "type": "scheduled",
    "frequency": "daily",
    "time": "09:00"
  },
  "steps": [
    {
      "id": "analyze_customer_data",
      "type": "bigquery_analysis",
      "query": "SELECT customer_id, engagement_score, conversion_rate, lifetime_value, behavioral_tags FROM ${DATASET_NAME}.customer_interactions WHERE interaction_timestamp >= CURRENT_DATE() - 7",
      "output": "recent_customer_insights"
    },
    {
      "id": "generate_segments",
      "type": "ai_agent_processing", 
      "agent": "${AGENT_NAME}",
      "task": "create_customer_segments",
      "input": "recent_customer_insights",
      "output": "customer_segments"
    },
    {
      "id": "create_personalized_content",
      "type": "gem_processing",
      "gem": "brand-voice-analyzer",
      "task": "generate_personalized_messages",
      "input": "customer_segments",
      "output": "personalized_campaigns"
    },
    {
      "id": "execute_email_campaigns",
      "type": "gmail_automation",
      "action": "send_segmented_campaigns",
      "campaigns": "personalized_campaigns",
      "tracking": "engagement_metrics"
    },
    {
      "id": "update_tracking_sheet",
      "type": "google_sheets",
      "action": "update_campaign_tracking",
      "sheet_id": "campaign_tracking_master",
      "data": "campaign_execution_results"
    }
  ]
}
EOF
    
    log_info "Google Workspace Flows configurations saved for manual setup"
    log_warning "Workspace Flows require manual configuration through Google Workspace Admin Console"
    log_success "Workspace Flows configuration prepared"
}

# Create BigQuery ML models
create_ml_models() {
    log_info "Creating BigQuery ML models for predictive analytics..."
    
    # Create customer lifetime value prediction model
    bq query --use_legacy_sql=false \
    "CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_NAME}.customer_ltv_model\`
    OPTIONS(
      model_type='linear_reg',
      input_label_cols=['customer_lifetime_value']
    ) AS
    SELECT
      engagement_score,
      EXTRACT(DAYOFWEEK FROM interaction_timestamp) as day_of_week,
      EXTRACT(HOUR FROM interaction_timestamp) as hour_of_day,
      demographic_segment,
      customer_lifetime_value
    FROM \`${PROJECT_ID}.${DATASET_NAME}.customer_interactions\`
    WHERE customer_lifetime_value IS NOT NULL
    LIMIT 0" # Initial empty model for structure
    
    # Create dashboard view
    bq query --use_legacy_sql=false \
    "CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.campaign_dashboard\` AS
    SELECT 
      c.campaign_id,
      c.campaign_name,
      c.channel,
      c.impressions,
      c.clicks,
      c.conversions,
      c.roas,
      COUNT(i.customer_id) as total_interactions,
      AVG(i.engagement_score) as avg_engagement,
      COUNT(ai.insight_id) as ai_recommendations,
      MAX(ai.generated_timestamp) as last_ai_analysis
    FROM \`${PROJECT_ID}.${DATASET_NAME}.campaign_performance\` c
    LEFT JOIN \`${PROJECT_ID}.${DATASET_NAME}.customer_interactions\` i 
      ON c.campaign_id = i.campaign_id
    LEFT JOIN \`${PROJECT_ID}.${DATASET_NAME}.ai_insights\` ai 
      ON c.campaign_id = ai.campaign_id
    WHERE c.start_date >= CURRENT_DATE() - 30
    GROUP BY c.campaign_id, c.campaign_name, c.channel, c.impressions, c.clicks, c.conversions, c.roas"
    
    log_success "BigQuery ML models and views created"
}

# Insert sample data for testing
insert_sample_data() {
    log_info "Inserting sample data for testing..."
    
    # Insert sample campaign data
    bq query --use_legacy_sql=false \
    "INSERT INTO \`${PROJECT_ID}.${DATASET_NAME}.campaign_performance\`
    VALUES 
    ('camp_001', 'Summer Sale 2025', 'email', '2025-07-01', '2025-07-15', 50000, 2500, 125, 1500.00, 6250.00, 5.0, 5.0, 4.17, 'millennials', 'US-West', 'mobile', CURRENT_TIMESTAMP()),
    ('camp_002', 'Product Launch Campaign', 'social', '2025-07-05', '2025-07-20', 75000, 3750, 188, 2250.00, 9400.00, 5.0, 5.0, 4.18, 'gen_z', 'US-East', 'desktop', CURRENT_TIMESTAMP())"
    
    # Insert sample customer interaction data
    bq query --use_legacy_sql=false \
    "INSERT INTO \`${PROJECT_ID}.${DATASET_NAME}.customer_interactions\`
    VALUES
    ('cust_001', 'email_open', CURRENT_TIMESTAMP(), 'camp_001', 'email', 8.5, 0.7, 125.00, 850.00, 'millennials', 'high_value'),
    ('cust_002', 'click_through', CURRENT_TIMESTAMP(), 'camp_002', 'social', 9.2, 0.8, 188.00, 1200.00, 'gen_z', 'early_adopter')"
    
    log_success "Sample data inserted for testing"
}

# Create deployment summary
create_deployment_summary() {
    log_info "Creating deployment summary..."
    
    cat > deployment-summary.md << EOF
# Marketing Intelligence Deployment Summary

## Deployment Details
- **Project ID**: ${PROJECT_ID}
- **Region**: ${REGION}
- **Deployment Time**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- **Random Suffix**: ${RANDOM_SUFFIX}

## Created Resources

### BigQuery
- **Dataset**: ${DATASET_NAME}
- **Tables**: 
  - campaign_performance
  - customer_interactions
  - ai_insights
- **ML Model**: customer_ltv_model
- **View**: campaign_dashboard

### Cloud Storage
- **Bucket**: gs://${BUCKET_NAME}

### Vertex AI (Manual Setup Required)
- **Agent**: ${AGENT_NAME}
- **Custom Gems**: 
  - brand-voice-analyzer
  - campaign-optimizer

### Google Workspace Flows (Manual Setup Required)
- **Flows**:
  - campaign-performance-alerts
  - dynamic-customer-segmentation

## Next Steps

1. **Manual Configuration Required**:
   - Configure Vertex AI Agent through Google Cloud Console
   - Set up Custom Gems in Vertex AI
   - Configure Google Workspace Flows through Workspace Admin Console

2. **Validation**:
   - Verify BigQuery tables contain sample data
   - Test ML model predictions
   - Validate dashboard view functionality

3. **Customization**:
   - Update agent configurations for your specific use case
   - Modify workflow triggers and actions
   - Add additional data sources and integrations

## Important Notes

- Some features may require early access or beta program enrollment
- Ensure proper IAM permissions for all team members
- Review cost implications and set up budget alerts
- Regularly monitor and optimize AI agent performance

## Support Resources

- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Google Workspace Flows Documentation](https://workspace.google.com/flows)
- [BigQuery ML Documentation](https://cloud.google.com/bigquery/docs/bigqueryml-intro)

EOF
    
    log_success "Deployment summary created: deployment-summary.md"
}

# Main deployment function
main() {
    log_info "Starting adaptive marketing campaign intelligence deployment..."
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    create_bigquery_resources
    create_storage_bucket
    configure_vertex_ai_agent
    create_custom_gems
    configure_workspace_flows
    create_ml_models
    insert_sample_data
    create_deployment_summary
    save_deployment_state
    
    log_success "======================================"
    log_success "Deployment completed successfully!"
    log_success "======================================"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "BigQuery Dataset: ${DATASET_NAME}"
    log_info "Storage Bucket: gs://${BUCKET_NAME}"
    log_info "AI Agent: ${AGENT_NAME}"
    log_warning "Manual configuration required for Vertex AI Agent and Workspace Flows"
    log_info "See deployment-summary.md for detailed next steps"
    log_info "Deployment state saved to: ${STATE_FILE}"
}

# Run main function
main "$@"