# Test the email template generation function with a sample request
curl -X POST "${function_url}" \
  -H "Content-Type: application/json" \
  -d '{
    "campaign_type": "newsletter",
    "subject_theme": "quarterly product updates", 
    "custom_context": "announcing new AI features and customer success stories"
  }' | jq '.'