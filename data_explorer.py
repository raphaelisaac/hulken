#!/usr/bin/env python3
"""
Better Signal - Data Explorer Dashboard
Visual exploration of all BigQuery tables, schemas, and CSV export
Launch: streamlit run data_explorer.py
"""
import os
import streamlit as st
import pandas as pd
from google.cloud import bigquery

st.set_page_config(page_title="Better Signal - Data Explorer", layout="wide")

# Set credentials if not already configured
if not os.getenv('GOOGLE_APPLICATION_CREDENTIALS'):
    creds_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hulken-fb56a345ac08.json')
    if os.path.exists(creds_path):
        os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = creds_path

@st.cache_resource
def get_client():
    return bigquery.Client(project="hulken")

client = get_client()

# ============================================================
# SIDEBAR - Dataset & Table Selection
# ============================================================
st.sidebar.title("Better Signal")
st.sidebar.markdown("Data Explorer")

DATASETS = {
    "ads_data": "Shopify, Facebook, TikTok, UTM",
    "google_Ads": "Google Ads",
    "analytics_334792038": "Google Analytics 4 (EU)",
    "analytics_454869667": "Google Analytics 4 (US)",
    "analytics_454871405": "Google Analytics 4 (CA)",
}

selected_dataset = st.sidebar.selectbox(
    "Dataset",
    list(DATASETS.keys()),
    format_func=lambda x: f"{x} - {DATASETS[x]}"
)

# Get tables for selected dataset
@st.cache_data(ttl=300)
def get_tables(dataset_id):
    tables = list(client.list_tables(f"hulken.{dataset_id}"))
    result = []
    for t in tables:
        result.append({
            "table": t.table_id,
            "type": t.table_type,
        })
    return pd.DataFrame(result)

tables_df = get_tables(selected_dataset)

if tables_df.empty:
    st.warning(f"No tables in {selected_dataset}")
    st.stop()

selected_table = st.sidebar.selectbox(
    "Table",
    sorted(tables_df["table"].tolist())
)

# ============================================================
# TAB 1 - Schema
# ============================================================
tab_schema, tab_preview, tab_query, tab_overview = st.tabs([
    "Schema", "Preview", "Query + Export", "Overview"
])

# Get schema
@st.cache_data(ttl=300)
def get_schema(dataset_id, table_id):
    table = client.get_table(f"hulken.{dataset_id}.{table_id}")
    schema_rows = []
    for field in table.schema:
        schema_rows.append({
            "Column": field.name,
            "Type": field.field_type,
            "Mode": field.mode,
            "Description": field.description or "",
        })
    return pd.DataFrame(schema_rows), table.num_rows, table.num_bytes, table.modified

schema_df, num_rows, num_bytes, modified = get_schema(selected_dataset, selected_table)

with tab_schema:
    st.subheader(f"`{selected_dataset}.{selected_table}`")

    col1, col2, col3 = st.columns(3)
    col1.metric("Rows", f"{num_rows:,}" if num_rows else "?")
    col2.metric("Size", f"{(num_bytes or 0) / 1024 / 1024:.1f} MB")
    col3.metric("Last Modified", str(modified)[:19] if modified else "?")

    st.dataframe(schema_df, use_container_width=True, height=min(len(schema_df) * 38 + 50, 600))

# ============================================================
# TAB 2 - Preview (first 100 rows)
# ============================================================
with tab_preview:
    st.subheader(f"Preview: `{selected_table}` (100 rows)")

    @st.cache_data(ttl=120)
    def preview_table(dataset_id, table_id):
        query = f"SELECT * FROM `hulken.{dataset_id}.{table_id}` LIMIT 100"
        return client.query(query).to_dataframe()

    try:
        preview_df = preview_table(selected_dataset, selected_table)
        st.dataframe(preview_df, use_container_width=True, height=500)

        # CSV export for preview
        csv = preview_df.to_csv(index=False)
        st.download_button(
            label="Download Preview as CSV",
            data=csv,
            file_name=f"{selected_table}_preview.csv",
            mime="text/csv"
        )
    except Exception as e:
        st.error(f"Error: {e}")

# ============================================================
# TAB 3 - Custom Query + CSV Export
# ============================================================
with tab_query:
    st.subheader("Custom Query")

    default_query = f"SELECT *\nFROM `hulken.{selected_dataset}.{selected_table}`\nLIMIT 1000"

    query_text = st.text_area("SQL", value=default_query, height=150)

    col_run, col_limit = st.columns([1, 3])
    max_rows = col_limit.number_input("Max rows", value=1000, min_value=1, max_value=100000, step=1000)

    if col_run.button("Run Query", type="primary"):
        with st.spinner("Running..."):
            try:
                result_df = client.query(query_text).to_dataframe()
                if len(result_df) > max_rows:
                    result_df = result_df.head(max_rows)
                    st.warning(f"Results truncated to {max_rows:,} rows")

                st.success(f"{len(result_df):,} rows returned")
                st.dataframe(result_df, use_container_width=True, height=500)

                # CSV export
                csv = result_df.to_csv(index=False)
                st.download_button(
                    label=f"Download CSV ({len(result_df):,} rows)",
                    data=csv,
                    file_name="query_result.csv",
                    mime="text/csv"
                )

                # Store in session for later
                st.session_state["last_result"] = result_df
            except Exception as e:
                st.error(f"Query Error: {e}")

    # Quick queries
    st.markdown("---")
    st.markdown("**Quick Queries (click to load):**")

    quick_queries = {
        "Daily Revenue (30 days)": """SELECT DATE(created_at) AS date,
  COUNT(*) AS orders,
  ROUND(SUM(total_price), 2) AS revenue
FROM `hulken.ads_data.shopify_live_orders_clean`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY date ORDER BY date DESC""",

        "Facebook Spend by Campaign (deduped)": """SELECT campaign_name,
  ROUND(SUM(CAST(spend AS FLOAT64)), 2) AS spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks
FROM `hulken.ads_data.facebook_insights`
WHERE date_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY campaign_name ORDER BY spend DESC""",

        "TikTok Daily Spend": """SELECT report_date AS date,
  ROUND(SUM(spend), 2) AS spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks
FROM `hulken.ads_data.tiktok_ads_reports_daily`
WHERE report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY date ORDER BY date DESC""",

        "UTM Attribution - Revenue by Source": """SELECT first_utm_source,
  COUNT(*) AS orders,
  ROUND(SUM(total_price), 2) AS revenue
FROM `hulken.ads_data.shopify_utm`
WHERE DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND first_utm_source IS NOT NULL
GROUP BY first_utm_source ORDER BY revenue DESC""",

        "Data Freshness Check": """SELECT 'facebook_ads' AS source, MAX(date_start) AS latest, DATE_DIFF(CURRENT_DATE(), MAX(date_start), DAY) AS days_behind
FROM `hulken.ads_data.facebook_insights`
UNION ALL
SELECT 'tiktok_ads', MAX(report_date), DATE_DIFF(CURRENT_DATE(), MAX(report_date), DAY)
FROM `hulken.ads_data.tiktok_ads_reports_daily`
UNION ALL
SELECT 'shopify_orders', MAX(DATE(created_at)), DATE_DIFF(CURRENT_DATE(), MAX(DATE(created_at)), DAY)
FROM `hulken.ads_data.shopify_live_orders_clean`
UNION ALL
SELECT 'shopify_utm', MAX(DATE(created_at)), DATE_DIFF(CURRENT_DATE(), MAX(DATE(created_at)), DAY)
FROM `hulken.ads_data.shopify_utm`
ORDER BY source""",

        "Google Ads Daily Spend": """SELECT _DATA_DATE AS date,
  ROUND(SUM(metrics_cost_micros) / 1e6, 2) AS spend_usd,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_clicks) AS clicks
FROM `hulken.google_Ads.ads_CampaignBasicStats_4354001000`
WHERE _DATA_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY date ORDER BY date DESC""",
    }

    for name, sql in quick_queries.items():
        with st.expander(name):
            st.code(sql, language="sql")

# ============================================================
# TAB 4 - Overview (all tables summary)
# ============================================================
with tab_overview:
    st.subheader(f"All Tables in `{selected_dataset}`")

    @st.cache_data(ttl=300)
    def get_overview(dataset_id):
        query = f"""
        SELECT table_name,
               row_count,
               ROUND(size_bytes / 1024 / 1024, 1) AS size_mb,
               TIMESTAMP_MILLIS(last_modified_time) AS last_modified
        FROM `hulken.{dataset_id}.__TABLES__`
        ORDER BY row_count DESC
        """
        return client.query(query).to_dataframe()

    try:
        overview_df = get_overview(selected_dataset)
        st.dataframe(overview_df, use_container_width=True, height=600)

        total_rows = overview_df["row_count"].sum()
        total_size = overview_df["size_mb"].sum()
        st.markdown(f"**Total: {len(overview_df)} tables | {total_rows:,.0f} rows | {total_size:,.1f} MB**")
    except Exception as e:
        st.error(f"Error: {e}")
