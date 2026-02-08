#!/usr/bin/env python3
"""
Data Reconciliation Dashboard
Streamlit interface for SOC validation and data quality checks.

Usage:
    streamlit run reconciliation_app.py
"""

import os
import sys
from datetime import datetime, timedelta
import pandas as pd
import streamlit as st
from dotenv import load_dotenv

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Load environment variables
load_dotenv()

# Set up BigQuery credentials before importing modules that use it
os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = os.getenv(
    'GOOGLE_APPLICATION_CREDENTIALS',
    'D:/Better_signal/hulken-fb56a345ac08.json'
)

# Import SOC checks and config
from soc_checks import SOCValidator, SOCResult
from config import PLATFORMS, THRESHOLDS, STATUS, BQ_PROJECT, BQ_DATASET

# ============================================================
# PAGE CONFIG
# ============================================================

st.set_page_config(
    page_title="Data Reconciliation Dashboard",
    page_icon="🔍",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ============================================================
# CUSTOM CSS
# ============================================================

st.markdown("""
<style>
    .status-pass {
        background-color: #d4edda;
        color: #155724;
        padding: 10px 15px;
        border-radius: 5px;
        border-left: 4px solid #28a745;
        margin: 5px 0;
    }
    .status-warning {
        background-color: #fff3cd;
        color: #856404;
        padding: 10px 15px;
        border-radius: 5px;
        border-left: 4px solid #ffc107;
        margin: 5px 0;
    }
    .status-critical {
        background-color: #f8d7da;
        color: #721c24;
        padding: 10px 15px;
        border-radius: 5px;
        border-left: 4px solid #dc3545;
        margin: 5px 0;
    }
    .status-error {
        background-color: #e2e3e5;
        color: #383d41;
        padding: 10px 15px;
        border-radius: 5px;
        border-left: 4px solid #6c757d;
        margin: 5px 0;
    }
    .metric-box {
        background-color: #f8f9fa;
        padding: 20px;
        border-radius: 10px;
        text-align: center;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .metric-value {
        font-size: 2.5em;
        font-weight: bold;
    }
    .metric-label {
        color: #6c757d;
        font-size: 0.9em;
    }
    .header-section {
        padding: 20px 0;
        border-bottom: 2px solid #e9ecef;
        margin-bottom: 20px;
    }
</style>
""", unsafe_allow_html=True)

# ============================================================
# HEADER
# ============================================================

st.title("Data Reconciliation Dashboard")
st.markdown("**SOC Validation and Data Quality Monitoring**")

# ============================================================
# SIDEBAR CONTROLS
# ============================================================

st.sidebar.header("Controls")

# Date Range
st.sidebar.subheader("Date Range")
default_start = datetime.now() - timedelta(days=30)
default_end = datetime.now()

col1, col2 = st.sidebar.columns(2)
with col1:
    start_date = st.date_input(
        "Start Date",
        value=default_start,
        key="start_date"
    )
with col2:
    end_date = st.date_input(
        "End Date",
        value=default_end,
        key="end_date"
    )

# Platform Selection
st.sidebar.subheader("Platforms")
platform_options = {
    "shopify": "Shopify",
    "facebook": "Facebook Ads",
    "tiktok": "TikTok Ads"
}

selected_platforms = []
for key, name in platform_options.items():
    if st.sidebar.checkbox(name, value=True, key=f"platform_{key}"):
        selected_platforms.append(key)

# Check Types
st.sidebar.subheader("Check Types")
check_types = {
    "price_format": "Price Format Validation",
    "duplicates": "Duplicate Detection",
    "null_rates": "NULL Rate Monitoring",
    "freshness": "Data Freshness",
    "record_count": "Record Count"
}

selected_checks = []
for key, name in check_types.items():
    if st.sidebar.checkbox(name, value=True, key=f"check_{key}"):
        selected_checks.append(key)

# Run Button
st.sidebar.markdown("---")
run_button = st.sidebar.button(
    "Run Reconciliation",
    type="primary",
    use_container_width=True
)

# ============================================================
# MAIN CONTENT
# ============================================================

def display_result(result: SOCResult):
    """Display a single SOC check result with appropriate styling."""
    status_lower = result.status.lower()

    if result.status == "PASS":
        st.markdown(f"""
        <div class="status-pass">
            <strong>[PASS]</strong> {result.check_name}<br/>
            <small>{result.message}</small>
        </div>
        """, unsafe_allow_html=True)
    elif result.status == "WARNING":
        st.markdown(f"""
        <div class="status-warning">
            <strong>[WARNING]</strong> {result.check_name}<br/>
            <small>{result.message}</small>
        </div>
        """, unsafe_allow_html=True)
    elif result.status == "CRITICAL":
        st.markdown(f"""
        <div class="status-critical">
            <strong>[CRITICAL]</strong> {result.check_name}<br/>
            <small>{result.message}</small>
        </div>
        """, unsafe_allow_html=True)
    else:  # ERROR
        st.markdown(f"""
        <div class="status-error">
            <strong>[ERROR]</strong> {result.check_name}<br/>
            <small>{result.message}</small>
        </div>
        """, unsafe_allow_html=True)

    # Show details in expander
    if result.details:
        with st.expander("View Details"):
            st.json(result.details)


def run_selected_checks(
    validator: SOCValidator,
    platforms: list,
    checks: list,
    start_date: str,
    end_date: str
) -> list:
    """Run only the selected checks for selected platforms."""
    results = []

    for platform in platforms:
        if "price_format" in checks:
            results.append(validator.check_price_format(platform, start_date, end_date))
        if "duplicates" in checks:
            results.append(validator.check_duplicates(platform, start_date, end_date))
        if "null_rates" in checks:
            results.append(validator.check_null_rates(platform, start_date, end_date))
        if "freshness" in checks:
            results.append(validator.check_data_freshness(platform))
        if "record_count" in checks:
            results.append(validator.check_record_count(platform, start_date, end_date))

    return results


# Show info when not running
if not run_button:
    st.info("Select date range, platforms, and check types, then click **Run Reconciliation** to begin.")

    # Show current configuration
    st.subheader("Current Configuration")

    col1, col2, col3 = st.columns(3)

    with col1:
        st.markdown("**BigQuery Project**")
        st.code(BQ_PROJECT)

    with col2:
        st.markdown("**Dataset**")
        st.code(BQ_DATASET)

    with col3:
        st.markdown("**Date Range**")
        st.code(f"{start_date} to {end_date}")

    # Show threshold configuration
    st.subheader("Alert Thresholds")

    threshold_df = pd.DataFrame([
        {"Check": "Record Count Diff", "Warning": f">{THRESHOLDS['record_count_diff']['warning']}%", "Critical": f">{THRESHOLDS['record_count_diff']['critical']}%"},
        {"Check": "Price Anomaly", "Warning": f">${THRESHOLDS['price_anomaly']['warning']:,}", "Critical": f">${THRESHOLDS['price_anomaly']['critical']:,}"},
        {"Check": "NULL Rate", "Warning": f">{THRESHOLDS['null_rate']['warning']}%", "Critical": f">{THRESHOLDS['null_rate']['critical']}%"},
        {"Check": "Sync Lag", "Warning": f">{THRESHOLDS['sync_lag']['warning']}h", "Critical": f">{THRESHOLDS['sync_lag']['critical']}h"},
        {"Check": "Duplicate Rate", "Warning": f">{THRESHOLDS['duplicate_rate']['warning']}%", "Critical": f">{THRESHOLDS['duplicate_rate']['critical']}%"},
    ])

    st.dataframe(threshold_df, use_container_width=True, hide_index=True)

# Run checks when button is clicked
if run_button:
    if not selected_platforms:
        st.error("Please select at least one platform.")
    elif not selected_checks:
        st.error("Please select at least one check type.")
    else:
        st.subheader("Running SOC Validation Checks...")

        # Progress bar
        progress_bar = st.progress(0)
        status_text = st.empty()

        # Initialize validator
        validator = SOCValidator()

        # Convert dates to strings
        start_str = start_date.strftime("%Y-%m-%d")
        end_str = end_date.strftime("%Y-%m-%d")

        # Run checks with progress updates
        total_checks = len(selected_platforms) * len(selected_checks)
        results = []
        check_count = 0

        for platform in selected_platforms:
            for check in selected_checks:
                check_count += 1
                progress = check_count / total_checks
                progress_bar.progress(progress)
                status_text.text(f"Running {check} for {platform}...")

                if check == "price_format":
                    results.append(validator.check_price_format(platform, start_str, end_str))
                elif check == "duplicates":
                    results.append(validator.check_duplicates(platform, start_str, end_str))
                elif check == "null_rates":
                    results.append(validator.check_null_rates(platform, start_str, end_str))
                elif check == "freshness":
                    results.append(validator.check_data_freshness(platform))
                elif check == "record_count":
                    results.append(validator.check_record_count(platform, start_str, end_str))

        progress_bar.progress(1.0)
        status_text.text("Complete!")

        # Store results in session state
        validator.results = results

        # Calculate summary
        summary = {
            "total": len(results),
            "passed": len([r for r in results if r.status == "PASS"]),
            "warnings": len([r for r in results if r.status == "WARNING"]),
            "critical": len([r for r in results if r.status == "CRITICAL"]),
            "errors": len([r for r in results if r.status == "ERROR"])
        }

        # ============================================================
        # SUMMARY METRICS
        # ============================================================

        st.markdown("---")
        st.subheader("Summary")

        col1, col2, col3, col4, col5 = st.columns(5)

        with col1:
            st.metric("Total Checks", summary["total"])
        with col2:
            st.metric("Passed", summary["passed"], delta=None)
        with col3:
            st.metric("Warnings", summary["warnings"], delta=None if summary["warnings"] == 0 else f"+{summary['warnings']}")
        with col4:
            st.metric("Critical", summary["critical"], delta=None if summary["critical"] == 0 else f"+{summary['critical']}")
        with col5:
            st.metric("Errors", summary["errors"], delta=None if summary["errors"] == 0 else f"+{summary['errors']}")

        # Overall status
        if summary["critical"] > 0:
            st.error("**Overall Status: CRITICAL** - Immediate attention required!")
        elif summary["warnings"] > 0:
            st.warning("**Overall Status: WARNING** - Some issues detected.")
        elif summary["errors"] > 0:
            st.info("**Overall Status: ERROR** - Some checks could not complete.")
        else:
            st.success("**Overall Status: PASS** - All checks passed!")

        # ============================================================
        # DETAILED RESULTS
        # ============================================================

        st.markdown("---")
        st.subheader("Detailed Results")

        # Group results by platform
        results_by_platform = {}
        for result in results:
            # Extract platform from check name
            platform = None
            for p in selected_platforms:
                if p in result.check_name.lower():
                    platform = p
                    break

            if platform:
                if platform not in results_by_platform:
                    results_by_platform[platform] = []
                results_by_platform[platform].append(result)

        # Display results in tabs
        if results_by_platform:
            tabs = st.tabs([platform_options.get(p, p) for p in results_by_platform.keys()])

            for tab, (platform, platform_results) in zip(tabs, results_by_platform.items()):
                with tab:
                    for result in platform_results:
                        display_result(result)

        # ============================================================
        # EXPORT OPTIONS
        # ============================================================

        st.markdown("---")
        st.subheader("Export Results")

        col1, col2 = st.columns(2)

        with col1:
            # Export as CSV
            results_df = pd.DataFrame([
                {
                    "Check Name": r.check_name,
                    "Status": r.status,
                    "Message": r.message,
                    "Details": str(r.details) if r.details else ""
                }
                for r in results
            ])

            csv_data = results_df.to_csv(index=False)
            st.download_button(
                label="Download CSV",
                data=csv_data,
                file_name=f"soc_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv",
                mime="text/csv",
                use_container_width=True
            )

        with col2:
            # Export as JSON
            import json
            json_data = json.dumps({
                "timestamp": datetime.now().isoformat(),
                "date_range": {"start": start_str, "end": end_str},
                "platforms": selected_platforms,
                "checks": selected_checks,
                "summary": summary,
                "results": [r.to_dict() for r in results]
            }, indent=2)

            st.download_button(
                label="Download JSON",
                data=json_data,
                file_name=f"soc_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json",
                mime="application/json",
                use_container_width=True
            )

# ============================================================
# FOOTER
# ============================================================

st.markdown("---")
st.markdown(
    f"<small>Data Reconciliation Dashboard | "
    f"BigQuery: {BQ_PROJECT}.{BQ_DATASET} | "
    f"Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</small>",
    unsafe_allow_html=True
)
