#!/usr/bin/env python3
"""
SOC Configuration - Alert Thresholds and Settings
For Data Reconciliation System
"""

# ============================================================
# ALERT THRESHOLDS
# ============================================================

THRESHOLDS = {
    # Record count difference between source and BigQuery
    "record_count_diff": {
        "warning": 1.0,   # > 1% difference
        "critical": 5.0,  # > 5% difference
    },

    # Price anomaly detection (prices that may be in cents)
    "price_anomaly": {
        "warning": 10000,    # > $10,000 single order
        "critical": 100000,  # > $100,000 single order
        "median_threshold": 1000,  # If median > $1000, likely cents error
    },

    # Null rate monitoring
    "null_rate": {
        "warning": 5.0,   # > 5% null rate
        "critical": 20.0, # > 20% null rate
    },

    # Sync lag (hours since last record)
    "sync_lag": {
        "warning": 1,   # > 1 hour
        "critical": 6,  # > 6 hours
    },

    # Duplicate rate
    "duplicate_rate": {
        "warning": 0.1,  # > 0.1% duplicates
        "critical": 1.0, # > 1% duplicates
    },

    # Spend difference (for ad platforms)
    "spend_diff": {
        "warning": 1.0,   # > 1% difference
        "critical": 5.0,  # > 5% difference
    },
}

# ============================================================
# BIGQUERY SETTINGS
# ============================================================

BQ_PROJECT = "hulken"
BQ_DATASET = "ads_data"

# Table names
TABLES = {
    "shopify_orders": f"{BQ_PROJECT}.{BQ_DATASET}.shopify_orders",
    "shopify_utm": f"{BQ_PROJECT}.{BQ_DATASET}.shopify_utm",
    "facebook_ads": f"{BQ_PROJECT}.{BQ_DATASET}.facebook_ads_insights",
    "tiktok_ads": f"{BQ_PROJECT}.{BQ_DATASET}.tiktokads_reports_daily",
}

# ============================================================
# PLATFORMS CONFIGURATION
# ============================================================

PLATFORMS = {
    "shopify": {
        "name": "Shopify",
        "enabled": True,
        "tables": ["shopify_orders", "shopify_utm"],
        "primary_key": "orderId",
        "price_field": "totalPrice",
        "date_field": "createdAt",
    },
    "facebook": {
        "name": "Facebook Ads",
        "enabled": True,
        "tables": ["facebook_ads"],
        "primary_key": "ad_id",
        "spend_field": "spend",
        "date_field": "date_start",
    },
    "tiktok": {
        "name": "TikTok Ads",
        "enabled": True,
        "tables": ["tiktok_ads"],
        "primary_key": "ad_id",
        "spend_field": "metrics.spend",
        "date_field": "stat_time_day",
    },
}

# ============================================================
# SOC CHECK CATEGORIES
# ============================================================

SOC_CHECKS = {
    "data_completeness": {
        "name": "Data Completeness",
        "description": "Verify record counts and coverage",
        "checks": [
            "record_count_comparison",
            "missing_records_detection",
            "date_range_coverage",
        ],
    },
    "data_format": {
        "name": "Data Format Validation",
        "description": "Validate data formats and units",
        "checks": [
            "price_format_validation",
            "currency_consistency",
            "date_format_validation",
            "id_format_validation",
        ],
    },
    "data_integrity": {
        "name": "Data Integrity",
        "description": "Check for duplicates and null values",
        "checks": [
            "duplicate_detection",
            "null_rate_monitoring",
            "referential_integrity",
            "sum_validation",
        ],
    },
    "data_freshness": {
        "name": "Data Freshness",
        "description": "Monitor sync status and data timeliness",
        "checks": [
            "sync_lag_detection",
            "missing_recent_data",
            "last_sync_timestamp",
        ],
    },
}

# ============================================================
# STATUS DEFINITIONS
# ============================================================

STATUS = {
    "PASS": {"color": "green", "icon": "check_circle", "priority": 0},
    "WARNING": {"color": "orange", "icon": "warning", "priority": 1},
    "CRITICAL": {"color": "red", "icon": "error", "priority": 2},
    "ERROR": {"color": "gray", "icon": "help", "priority": 3},
}

# ============================================================
# REPORT SETTINGS
# ============================================================

REPORT_SETTINGS = {
    "output_dir": "D:/Better_signal/data_validation/reports",
    "date_format": "%Y-%m-%d",
    "datetime_format": "%Y-%m-%d %H:%M:%S",
}
