-- =====================================
-- Campaign Dashboard View
-- Real-time aggregated view of campaign performance with AI insights
-- =====================================

SELECT 
  -- Campaign identification and metadata
  c.campaign_id,
  c.campaign_name,
  c.channel,
  c.audience_segment,
  c.geo_location,
  c.device_type,
  
  -- Campaign performance metrics
  c.impressions,
  c.clicks,
  c.conversions,
  c.spend,
  c.revenue,
  c.ctr,
  c.conversion_rate,
  c.roas,
  
  -- Campaign timeline
  c.start_date,
  c.end_date,
  DATE_DIFF(COALESCE(c.end_date, CURRENT_DATE()), c.start_date, DAY) as campaign_duration_days,
  
  -- Customer interaction aggregations
  COUNT(DISTINCT i.customer_id) as unique_customers,
  COUNT(i.customer_id) as total_interactions,
  AVG(i.engagement_score) as avg_engagement_score,
  AVG(i.sentiment_score) as avg_sentiment_score,
  SUM(i.conversion_value) as total_conversion_value,
  AVG(i.customer_lifetime_value) as avg_customer_ltv,
  
  -- Interaction type breakdown
  COUNTIF(i.interaction_type = 'email_open') as email_opens,
  COUNTIF(i.interaction_type = 'click') as email_clicks,
  COUNTIF(i.interaction_type = 'purchase') as purchases,
  COUNTIF(i.interaction_type = 'website_visit') as website_visits,
  COUNTIF(i.interaction_type = 'social_share') as social_shares,
  
  -- AI insights summary
  COUNT(ai.insight_id) as total_ai_insights,
  COUNTIF(ai.insight_type = 'performance_anomaly') as performance_anomalies,
  COUNTIF(ai.insight_type = 'optimization_opportunity') as optimization_opportunities,
  COUNTIF(ai.insight_type = 'customer_behavior_change') as behavior_changes,
  COUNTIF(ai.priority_level = 'critical') as critical_insights,
  COUNTIF(ai.priority_level = 'high') as high_priority_insights,
  COUNTIF(ai.action_required = true) as insights_requiring_action,
  AVG(ai.confidence_score) as avg_insight_confidence,
  MAX(ai.generated_timestamp) as last_ai_analysis_timestamp,
  
  -- Performance calculations and trends
  SAFE_DIVIDE(c.clicks, c.impressions) * 100 as calculated_ctr,
  SAFE_DIVIDE(c.conversions, c.clicks) * 100 as calculated_conversion_rate,
  SAFE_DIVIDE(c.revenue, c.spend) as calculated_roas,
  SAFE_DIVIDE(c.revenue, c.conversions) as avg_order_value,
  SAFE_DIVIDE(c.spend, c.conversions) as cost_per_conversion,
  SAFE_DIVIDE(c.spend, c.clicks) as cost_per_click,
  
  -- Time-based performance metrics
  SAFE_DIVIDE(c.impressions, DATE_DIFF(COALESCE(c.end_date, CURRENT_DATE()), c.start_date, DAY)) as impressions_per_day,
  SAFE_DIVIDE(c.spend, DATE_DIFF(COALESCE(c.end_date, CURRENT_DATE()), c.start_date, DAY)) as spend_per_day,
  SAFE_DIVIDE(c.revenue, DATE_DIFF(COALESCE(c.end_date, CURRENT_DATE()), c.start_date, DAY)) as revenue_per_day,
  
  -- Engagement quality metrics
  CASE 
    WHEN AVG(i.engagement_score) >= 8 THEN 'High'
    WHEN AVG(i.engagement_score) >= 6 THEN 'Medium'
    WHEN AVG(i.engagement_score) >= 4 THEN 'Low'
    ELSE 'Very Low'
  END as engagement_quality,
  
  CASE 
    WHEN AVG(i.sentiment_score) >= 0.5 THEN 'Positive'
    WHEN AVG(i.sentiment_score) >= -0.2 THEN 'Neutral'
    ELSE 'Negative'
  END as overall_sentiment,
  
  -- Performance status indicators
  CASE 
    WHEN c.roas >= 4.0 THEN 'Excellent'
    WHEN c.roas >= 2.5 THEN 'Good'
    WHEN c.roas >= 1.5 THEN 'Fair'
    ELSE 'Poor'
  END as roas_performance,
  
  CASE 
    WHEN c.ctr >= 5.0 THEN 'Excellent'
    WHEN c.ctr >= 2.5 THEN 'Good'
    WHEN c.ctr >= 1.0 THEN 'Fair'
    ELSE 'Poor'
  END as ctr_performance,
  
  -- Data freshness indicators
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.timestamp, HOUR) as data_age_hours,
  CASE 
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.timestamp, HOUR) <= 1 THEN 'Real-time'
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.timestamp, HOUR) <= 24 THEN 'Recent'
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.timestamp, HOUR) <= 168 THEN 'This week'
    ELSE 'Older'
  END as data_freshness,
  
  -- Last update timestamp
  CURRENT_TIMESTAMP() as dashboard_last_updated

FROM 
  `${project_id}.${dataset_id}.campaign_performance` c
  
LEFT JOIN 
  `${project_id}.${dataset_id}.customer_interactions` i 
  ON c.campaign_id = i.campaign_id
  
LEFT JOIN 
  `${project_id}.${dataset_id}.ai_insights` ai 
  ON c.campaign_id = ai.campaign_id

WHERE 
  -- Focus on recent campaigns (last 90 days)
  c.start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  
GROUP BY 
  c.campaign_id,
  c.campaign_name,
  c.channel,
  c.audience_segment,
  c.geo_location,
  c.device_type,
  c.impressions,
  c.clicks,
  c.conversions,
  c.spend,
  c.revenue,
  c.ctr,
  c.conversion_rate,
  c.roas,
  c.start_date,
  c.end_date,
  c.timestamp

ORDER BY 
  c.start_date DESC,
  total_ai_insights DESC,
  c.revenue DESC