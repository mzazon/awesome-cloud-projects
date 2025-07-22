-- =====================================
-- Customer Lifetime Value (LTV) Prediction Model
-- BigQuery ML model for predicting customer lifetime value
-- =====================================

CREATE OR REPLACE MODEL `${project_id}.${dataset_id}.customer_ltv_model`
OPTIONS(
  model_type='linear_reg',
  input_label_cols=['customer_lifetime_value'],
  data_split_method='AUTO_SPLIT',
  data_split_eval_fraction=0.2,
  data_split_test_fraction=0.1,
  l1_reg=0.01,
  l2_reg=0.01,
  max_iterations=50,
  learn_rate_strategy='line_search',
  early_stop=true,
  min_rel_progress=0.005,
  ls_init_learn_rate=0.1,
  calculate_p_values=true,
  enable_global_explain=true
) AS

WITH customer_features AS (
  SELECT
    customer_id,
    
    -- Engagement metrics
    AVG(engagement_score) as avg_engagement_score,
    MAX(engagement_score) as max_engagement_score,
    MIN(engagement_score) as min_engagement_score,
    STDDEV(engagement_score) as engagement_score_variance,
    
    -- Sentiment analysis
    AVG(sentiment_score) as avg_sentiment_score,
    MAX(sentiment_score) as max_sentiment_score,
    MIN(sentiment_score) as min_sentiment_score,
    STDDEV(sentiment_score) as sentiment_score_variance,
    
    -- Interaction patterns
    COUNT(*) as total_interactions,
    COUNT(DISTINCT campaign_id) as campaigns_engaged,
    COUNT(DISTINCT DATE(interaction_timestamp)) as active_days,
    COUNT(DISTINCT EXTRACT(DAYOFWEEK FROM interaction_timestamp)) as active_weekdays,
    COUNT(DISTINCT EXTRACT(HOUR FROM interaction_timestamp)) as active_hours,
    
    -- Interaction type distribution
    COUNTIF(interaction_type = 'email_open') as email_opens,
    COUNTIF(interaction_type = 'click') as clicks,
    COUNTIF(interaction_type = 'purchase') as purchases,
    COUNTIF(interaction_type = 'website_visit') as website_visits,
    COUNTIF(interaction_type = 'social_share') as social_shares,
    
    -- Temporal features
    DATE_DIFF(CURRENT_DATE(), MIN(DATE(interaction_timestamp)), DAY) as days_since_first_interaction,
    DATE_DIFF(CURRENT_DATE(), MAX(DATE(interaction_timestamp)), DAY) as days_since_last_interaction,
    DATE_DIFF(MAX(DATE(interaction_timestamp)), MIN(DATE(interaction_timestamp)), DAY) + 1 as customer_lifespan_days,
    
    -- Time-based patterns
    EXTRACT(DAYOFWEEK FROM interaction_timestamp) as primary_day_of_week,
    EXTRACT(HOUR FROM interaction_timestamp) as primary_hour_of_day,
    
    -- Frequency metrics
    COUNT(*) / (DATE_DIFF(MAX(DATE(interaction_timestamp)), MIN(DATE(interaction_timestamp)), DAY) + 1) as interaction_frequency,
    
    -- Purchase behavior
    SUM(conversion_value) as total_conversion_value,
    AVG(conversion_value) as avg_conversion_value,
    MAX(conversion_value) as max_conversion_value,
    COUNTIF(conversion_value > 0) as conversion_count,
    SAFE_DIVIDE(COUNTIF(conversion_value > 0), COUNT(*)) as conversion_rate,
    
    -- Demographic and behavioral features
    demographic_segment,
    ARRAY_LENGTH(behavioral_tags) as behavioral_tag_count,
    
    -- Recency, Frequency, Monetary (RFM) features
    DATE_DIFF(CURRENT_DATE(), MAX(DATE(interaction_timestamp)), DAY) as recency_days,
    COUNT(*) as frequency_interactions,
    SUM(COALESCE(conversion_value, 0)) as monetary_value,
    
    -- Channel diversity
    COUNT(DISTINCT 
      CASE WHEN campaign_id IS NOT NULL 
      THEN (SELECT channel FROM `${project_id}.${dataset_id}.campaign_performance` cp WHERE cp.campaign_id = i.campaign_id LIMIT 1)
      END
    ) as channel_diversity,
    
    -- Target variable - Customer Lifetime Value
    AVG(customer_lifetime_value) as customer_lifetime_value
    
  FROM 
    `${project_id}.${dataset_id}.customer_interactions` i
  WHERE 
    -- Filter for customers with sufficient interaction history
    customer_lifetime_value IS NOT NULL
    AND customer_lifetime_value > 0
    AND interaction_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
    
  GROUP BY 
    customer_id,
    demographic_segment,
    EXTRACT(DAYOFWEEK FROM interaction_timestamp),
    EXTRACT(HOUR FROM interaction_timestamp)
    
  HAVING 
    -- Only include customers with meaningful interaction history
    total_interactions >= 3
    AND customer_lifespan_days >= 7
    AND total_conversion_value > 0
),

encoded_features AS (
  SELECT
    customer_id,
    
    -- Continuous features
    avg_engagement_score,
    max_engagement_score,
    min_engagement_score,
    engagement_score_variance,
    avg_sentiment_score,
    max_sentiment_score,
    min_sentiment_score,
    sentiment_score_variance,
    total_interactions,
    campaigns_engaged,
    active_days,
    active_weekdays,
    active_hours,
    email_opens,
    clicks,
    purchases,
    website_visits,
    social_shares,
    days_since_first_interaction,
    days_since_last_interaction,
    customer_lifespan_days,
    interaction_frequency,
    total_conversion_value,
    avg_conversion_value,
    max_conversion_value,
    conversion_count,
    conversion_rate,
    behavioral_tag_count,
    recency_days,
    frequency_interactions,
    monetary_value,
    channel_diversity,
    
    -- Categorical features encoded
    CASE 
      WHEN demographic_segment = 'millennials' THEN 1
      WHEN demographic_segment = 'gen_z' THEN 2
      WHEN demographic_segment = 'gen_x' THEN 3
      WHEN demographic_segment = 'baby_boomers' THEN 4
      ELSE 0
    END as demographic_segment_encoded,
    
    -- Time-based categorical features
    primary_day_of_week,
    primary_hour_of_day,
    
    -- RFM Score calculation
    CASE 
      WHEN recency_days <= 30 THEN 5
      WHEN recency_days <= 60 THEN 4
      WHEN recency_days <= 90 THEN 3
      WHEN recency_days <= 180 THEN 2
      ELSE 1
    END as recency_score,
    
    CASE 
      WHEN frequency_interactions >= 20 THEN 5
      WHEN frequency_interactions >= 10 THEN 4
      WHEN frequency_interactions >= 5 THEN 3
      WHEN frequency_interactions >= 2 THEN 2
      ELSE 1
    END as frequency_score,
    
    CASE 
      WHEN monetary_value >= 1000 THEN 5
      WHEN monetary_value >= 500 THEN 4
      WHEN monetary_value >= 100 THEN 3
      WHEN monetary_value >= 50 THEN 2
      ELSE 1
    END as monetary_score,
    
    -- Target variable
    customer_lifetime_value
    
  FROM customer_features
)

SELECT
  -- Feature engineering for better model performance
  avg_engagement_score,
  max_engagement_score,
  engagement_score_variance,
  avg_sentiment_score,
  sentiment_score_variance,
  total_interactions,
  campaigns_engaged,
  active_days,
  
  -- Interaction ratios
  SAFE_DIVIDE(clicks, email_opens) as click_to_open_ratio,
  SAFE_DIVIDE(purchases, clicks) as purchase_to_click_ratio,
  SAFE_DIVIDE(website_visits, total_interactions) as website_visit_ratio,
  SAFE_DIVIDE(social_shares, total_interactions) as social_share_ratio,
  
  -- Temporal features
  days_since_first_interaction,
  days_since_last_interaction,
  customer_lifespan_days,
  interaction_frequency,
  
  -- Purchase behavior
  total_conversion_value,
  avg_conversion_value,
  conversion_rate,
  
  -- Demographic encoding
  demographic_segment_encoded,
  
  -- Time patterns
  primary_day_of_week,
  primary_hour_of_day,
  
  -- RFM scores
  recency_score,
  frequency_score,
  monetary_score,
  recency_score * frequency_score * monetary_score as rfm_combined_score,
  
  -- Channel and behavioral diversity
  channel_diversity,
  behavioral_tag_count,
  
  -- Engagement intensity
  SAFE_DIVIDE(total_interactions, customer_lifespan_days) as daily_interaction_rate,
  SAFE_DIVIDE(total_conversion_value, total_interactions) as value_per_interaction,
  
  -- Target variable
  customer_lifetime_value

FROM encoded_features
WHERE 
  -- Data quality filters
  customer_lifetime_value BETWEEN 10 AND 50000  -- Remove outliers
  AND total_interactions BETWEEN 3 AND 1000     -- Remove edge cases
  AND customer_lifespan_days >= 7                -- Minimum engagement period