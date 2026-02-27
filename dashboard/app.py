"""
Three tabs:
  1. Business Insights   — revenue, top medications, pharmacy performance
  2. Pipeline Health     — run history, row counts, success rates
  3. Data Quality        — quality issues detected and fixed by ETL

Run: streamlit run dashboard/app.py
"""

import os
from sqlalchemy import create_engine
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="PharmaFlow Analytics",
    page_icon="🌿",
    layout="wide",
    initial_sidebar_state="auto",
)

st.markdown("""
<style>

/* --- FORCE SIDEBAR WIDTH --- */
section[data-testid="stSidebar"] {
    min-width: 280px !important;
    max-width: 280px !important;
    width: 280px !important;
}

/* --- REMOVE COLLAPSE BUTTON COMPLETELY --- */
button[kind="header"] {
    display: none !important;
}

/* --- REMOVE TOOLTIP --- */
div[data-baseweb="tooltip"] {
    display: none !important;
}

/* --- PREVENT COLLAPSED STATE SHIFT --- */
[data-testid="collapsedControl"] {
    display: none !important;
}

section[data-testid="stSidebar"][aria-expanded="false"] {
    transform: none !important;
}

/* --- ENSURE MAIN CONTENT DOESN’T SHIFT --- */
.main {
    margin-left: 280px !important;
}

</style>
""", unsafe_allow_html=True)

# ---------------------------------------------------------------------------
# Palette & Theme
# ---------------------------------------------------------------------------
COLORS = {
    "forest":      "#1B4332",
    "hunter":      "#2D6A4F",
    "fern":        "#40916C",
    "sage":        "#74C69D",
    "mint":        "#B7E4C7",
    "mist":        "#D8F3DC",
    "parchment":   "#F8F4EF",
    "cream":       "#EEE8E0",
    "teal":        "#0D6E8A",
    "teal_light":  "#48A9C5",
    "ink":         "#1A2E1F",
    "charcoal":    "#3D4F42",
    "gold":        "#C9A84C",
}

CHART_COLORS = [
    COLORS["forest"], COLORS["teal"], COLORS["fern"],
    COLORS["hunter"], COLORS["teal_light"], COLORS["sage"],
    COLORS["gold"], COLORS["mint"],
]

AXIS_STYLE = dict(
    gridcolor="rgba(183, 228, 199, 0.33)",
    linecolor=COLORS["mint"],
    tickfont=dict(size=11),
)

# ---------------------------------------------------------------------------
# Custom CSS — the apothecary aesthetic
# ---------------------------------------------------------------------------
st.markdown(f"""
<style>
@import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,600;0,700;1,400&family=DM+Sans:wght@300;400;500;600&display=swap');

html, body, [class*="css"] {{
    font-family: 'DM Sans', sans-serif;
    background-color: {COLORS["parchment"]};
    color: {COLORS["ink"]};
}}
#MainMenu, footer, header {{ visibility: hidden; }}
.block-container {{ padding-top: 1.5rem; padding-bottom: 2rem; }}

[data-testid="stSidebar"] {{
    background: linear-gradient(180deg, {COLORS["forest"]} 0%, {COLORS["hunter"]} 60%, {COLORS["ink"]} 100%);
    border-right: 1px solid {COLORS["fern"]}44;
}}
[data-testid="stSidebar"] * {{
    color: {COLORS["mist"]} !important;
    font-family: 'DM Sans', sans-serif !important;
}}
[data-testid="stSidebar"] .stRadio label {{
    font-size: 0.9rem;
    letter-spacing: 0.02em;
    padding: 0.3rem 0;
}}
[data-testid="stSidebar"] hr {{ border-color: {COLORS["fern"]}55; }}

.pf-header {{
    background: linear-gradient(135deg, {COLORS["forest"]} 0%, {COLORS["hunter"]} 50%, {COLORS["fern"]}BB 100%);
    border-radius: 12px;
    padding: 2rem 2.5rem;
    margin-bottom: 1.5rem;
    position: relative;
    overflow: hidden;
}}
.pf-header::before {{
    content: '';
    position: absolute;
    top: -40%; right: -10%;
    width: 400px; height: 400px;
    background: radial-gradient({COLORS["fern"]}33 0%, transparent 70%);
    border-radius: 50%;
}}
.pf-header h1 {{
    font-family: 'Cormorant Garamond', serif;
    font-size: 2.4rem; font-weight: 700;
    color: {COLORS["mist"]}; margin: 0;
    letter-spacing: 0.02em;
}}
.pf-header p {{
    font-family: 'DM Sans', sans-serif;
    color: {COLORS["sage"]};
    margin: 0.3rem 0 0 0;
    font-size: 0.95rem; font-weight: 300;
    letter-spacing: 0.05em;
}}

.kpi-card {{
    background: {COLORS["cream"]};
    border: 1px solid {COLORS["mint"]}88;
    border-radius: 10px;
    padding: 1.2rem 1.4rem;
    position: relative; overflow: hidden;
}}
.kpi-card::after {{
    content: '';
    position: absolute;
    top: 0; left: 0;
    width: 4px; height: 100%;
    background: linear-gradient({COLORS["fern"]}, {COLORS["teal"]});
    border-radius: 10px 0 0 10px;
}}
.kpi-label {{
    font-size: 0.72rem; font-weight: 600;
    letter-spacing: 0.1em; text-transform: uppercase;
    color: {COLORS["charcoal"]}; margin-bottom: 0.4rem;
}}
.kpi-value {{
    font-family: 'Cormorant Garamond', serif;
    font-size: 2rem; font-weight: 700;
    color: {COLORS["forest"]}; line-height: 1;
}}
.kpi-delta {{
    font-size: 0.78rem; color: {COLORS["fern"]};
    margin-top: 0.3rem; font-weight: 500;
}}

.section-title {{
    font-family: 'Cormorant Garamond', serif;
    font-size: 1.5rem; font-weight: 600;
    color: {COLORS["forest"]};
    margin: 1.5rem 0 0.8rem 0;
    padding-bottom: 0.4rem;
    border-bottom: 1px solid {COLORS["mint"]};
    letter-spacing: 0.02em;
}}

.alert-critical {{
    background: #FFF0E8;
    border-left: 3px solid #C0392B;
    border-radius: 4px; padding: 0.5rem 0.8rem;
    font-size: 0.85rem; color: #7B241C;
}}
.alert-warning {{
    background: #FEFCE8;
    border-left: 3px solid {COLORS["gold"]};
    border-radius: 4px; padding: 0.5rem 0.8rem;
    font-size: 0.85rem; color: #7D6608;
}}
.alert-ok {{
    background: {COLORS["mist"]};
    border-left: 3px solid {COLORS["fern"]};
    border-radius: 4px; padding: 0.5rem 0.8rem;
    font-size: 0.85rem; color: {COLORS["forest"]};
}}

.stTabs [data-baseweb="tab-list"] {{
    background: {COLORS["cream"]};
    border-radius: 8px; padding: 4px; gap: 4px;
    border: 1px solid {COLORS["mint"]}66;
}}
.stTabs [data-baseweb="tab"] {{
    border-radius: 6px;
    font-family: 'DM Sans', sans-serif;
    font-weight: 500; font-size: 0.88rem;
    letter-spacing: 0.03em;
    color: {COLORS["charcoal"]};
    padding: 0.5rem 1.2rem;
}}
.stTabs [aria-selected="true"] {{
    background: {COLORS["forest"]} !important;
    color: {COLORS["mist"]} !important;
}}

.stDataFrame {{
    border: 1px solid {COLORS["mint"]}66;
    border-radius: 8px; overflow: hidden;
}}
.pf-divider {{
    border: none;
    border-top: 1px solid {COLORS["mint"]}66;
    margin: 1.5rem 0;
}}
[data-testid="stRadio"] div[role="radiogroup"] label div[data-testid="stMarkdownContainer"] p {{
    font-size: 0.88rem;
}}
div[data-baseweb="tooltip"] {{ display: none !important; }}
</style>
""", unsafe_allow_html=True)


# ---------------------------------------------------------------------------
# Database connection
# ---------------------------------------------------------------------------
def get_engine():
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise ValueError("DATABASE_URL is not set")
    return create_engine(database_url, pool_pre_ping=True)


@st.cache_data(ttl=300)
def query(sql: str) -> pd.DataFrame:
    engine = get_engine()
    with engine.connect() as conn:
        return pd.read_sql(sql, conn)


def fmt_currency(value) -> str:
    if pd.isna(value):
        return "R 0"
    return f"R {value:,.0f}"


def fmt_number(value) -> str:
    if pd.isna(value):
        return "0"
    return f"{value:,.0f}"


# ---------------------------------------------------------------------------
# Plotly chart defaults
# ---------------------------------------------------------------------------
def chart_layout(fig, title: str = "", height: int = 380, has_axes: bool = True):
    """Apply consistent PharmaFlow styling to a Plotly figure."""
    if title:
        fig.update_layout(title_text=title)
        fig.update_layout(title_font_family="Cormorant Garamond")
        fig.update_layout(title_font_size=18)
        fig.update_layout(title_font_color=COLORS["forest"])
    fig.update_layout(
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        font=dict(family="DM Sans", color=COLORS["charcoal"], size=12),
        height=height,
        margin=dict(l=20, r=20, t=50 if title else 20, b=20),
        legend=dict(bgcolor="rgba(0,0,0,0)", font=dict(size=11)),
    )
    if has_axes:
        fig.update_xaxes(**AXIS_STYLE)
        fig.update_yaxes(**AXIS_STYLE)
    return fig


# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------
with st.sidebar:
    st.markdown("""
    <div style='text-align:center; padding: 1.2rem 0 1rem 0;'>
        <div style='font-size: 2.2rem;'>🌿</div>
        <div style='font-family: Cormorant Garamond, serif; font-size: 1.3rem; font-weight: 700; letter-spacing: 0.05em;'>PharmaFlow</div>
        <div style='font-size: 0.72rem; letter-spacing: 0.12em; opacity: 0.7; text-transform: uppercase; margin-top: 2px;'>Analytics Platform</div>
    </div>
    <hr/>
    """, unsafe_allow_html=True)

    st.markdown("<div style='font-size:0.72rem; letter-spacing:0.1em; text-transform:uppercase; opacity:0.6; margin-bottom:0.5rem;'>Navigation</div>", unsafe_allow_html=True)

    page = st.radio(
        "Navigation",
        ["Business Insights", "Pipeline Health", "Data Quality"],
        label_visibility="collapsed",
    )

    st.markdown("<hr/>", unsafe_allow_html=True)

    try:
        kpi = query("SELECT * FROM dwh.v_business_kpis LIMIT 1")
        if not kpi.empty:
            data_from = pd.to_datetime(kpi['data_from'].iloc[0]).strftime('%d %b %Y')
            data_to   = pd.to_datetime(kpi['data_to'].iloc[0]).strftime('%d %b %Y')
            st.markdown(f"""
            <div style='font-size:0.72rem; letter-spacing:0.08em; text-transform:uppercase; opacity:0.6; margin-bottom:0.6rem;'>Data Range</div>
            <div style='font-size:0.85rem; opacity:0.9;'>{data_from}</div>
            <div style='font-size:0.72rem; opacity:0.5; margin: 2px 0;'>to</div>
            <div style='font-size:0.85rem; opacity:0.9;'>{data_to}</div>
            """, unsafe_allow_html=True)
    except Exception:
        st.markdown("<div style='font-size:0.8rem; opacity:0.6;'>⚠ DB not connected</div>", unsafe_allow_html=True)

    st.markdown("<hr/>", unsafe_allow_html=True)
    st.markdown(f"<div style='font-size:0.7rem; opacity:0.45; text-align:center;'>Last refreshed<br/>{datetime.now().strftime('%H:%M · %d %b %Y')}</div>", unsafe_allow_html=True)


# ---------------------------------------------------------------------------
# Page header
# ---------------------------------------------------------------------------
tab_label = page.strip()
st.markdown(f"""
<div class="pf-header">
    <h1>PharmaFlow Analytics</h1>
    <p>JOHANNESBURG PHARMACY GROUP &nbsp;·&nbsp; {tab_label.upper()}</p>
</div>
""", unsafe_allow_html=True)


# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
try:
    kpi_df            = query("SELECT * FROM dwh.v_business_kpis LIMIT 1")
    pharmacy_df       = query("SELECT * FROM dwh.v_revenue_by_pharmacy")
    medications_df    = query("SELECT * FROM dwh.v_top_medications LIMIT 20")
    growth_df         = query("SELECT * FROM dwh.v_warehouse_growth ORDER BY snapshot_date")
    stock_alerts_df   = query("SELECT * FROM dwh.v_stock_alerts")
    
    pipeline_sum_df   = query("SELECT * FROM dwh.v_pipeline_summary LIMIT 1")
    pipeline_daily_df = query("SELECT * FROM dwh.v_pipeline_daily ORDER BY run_date DESC LIMIT 30")
    pipeline_runs_df  = query("SELECT * FROM dwh.pipeline_runs ORDER BY started_at DESC LIMIT 20")
    
    dq_summary_df     = query("SELECT * FROM dwh.v_data_quality_summary ORDER BY run_date DESC, dataset")
    dq_trend_df       = query("SELECT * FROM dwh.v_quality_trend ORDER BY run_date")
    dq_log_df         = query("""
                            SELECT run_date, dataset, check_name, check_category,
                                rows_checked, rows_failed, failure_rate_pct,
                                severity, details
                            FROM dwh.data_quality_log
                            ORDER BY run_date DESC, severity DESC, dataset
                        """)
    db_connected = True

except Exception as e:
    st.error(f"Database connection failed: {e}")
    st.write("Debug info:", str(e))
    st.stop()


# ===========================================================================
# TAB 1: BUSINESS INSIGHTS
# ===========================================================================
if "Business Insights" in page:

    kpi = kpi_df.iloc[0] if not kpi_df.empty else {}

    c1, c2, c3, c4, c5 = st.columns(5)
    with c1:
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Total Revenue</div>
            <div class="kpi-value">{fmt_currency(kpi.get('total_revenue'))}</div>
            <div class="kpi-delta">↑ All time</div>
        </div>""", unsafe_allow_html=True)
    with c2:
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Total Profit</div>
            <div class="kpi-value">{fmt_currency(kpi.get('total_profit'))}</div>
            <div class="kpi-delta">↑ Gross margin</div>
        </div>""", unsafe_allow_html=True)
    with c3:
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Prescriptions</div>
            <div class="kpi-value">{fmt_number(kpi.get('total_prescriptions'))}</div>
            <div class="kpi-delta">↑ Total dispensed</div>
        </div>""", unsafe_allow_html=True)
    with c4:
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Unique Patients</div>
            <div class="kpi-value">{fmt_number(kpi.get('unique_patients'))}</div>
            <div class="kpi-delta">↑ Registered</div>
        </div>""", unsafe_allow_html=True)
    with c5:
        medical_aid_pct = kpi.get('medical_aid_pct', 0)
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Medical Aid Mix</div>
            <div class="kpi-value">{medical_aid_pct:.1f}%</div>
            <div class="kpi-delta">↑ of transactions</div>
        </div>""", unsafe_allow_html=True)

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    col1, col2 = st.columns([1, 1.4])

    with col1:
        st.markdown("<div class='section-title'>Revenue by Pharmacy</div>", unsafe_allow_html=True)
        if not pharmacy_df.empty:
            fig = go.Figure(go.Bar(
                x=pharmacy_df['total_revenue'],
                y=pharmacy_df['location_name'],
                orientation='h',
                marker=dict(
                    color=pharmacy_df['total_revenue'],
                    colorscale=[[0, COLORS["sage"]], [0.5, COLORS["fern"]], [1, COLORS["forest"]]],
                    showscale=False,
                ),
                text=pharmacy_df['total_revenue'].apply(lambda x: f"R {x/1e6:.2f}M"),
                textposition='outside',
                textfont=dict(size=11, color=COLORS["charcoal"]),
                hovertemplate="<b>%{y}</b><br>Revenue: R %{x:,.0f}<extra></extra>",
            ))
            chart_layout(fig, height=320, has_axes=True)
            fig.update_layout(yaxis=dict(categoryorder='total ascending'))
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.markdown("<div class='section-title'>Cumulative Revenue Trend</div>", unsafe_allow_html=True)

        if not growth_df.empty:

            # ---- DATA CLEANING ----
            growth_df = growth_df.copy()
            growth_df['snapshot_date'] = pd.to_datetime(
                growth_df['snapshot_date'], errors='coerce'
            )
            growth_df['cumulative_revenue'] = pd.to_numeric(
                growth_df['cumulative_revenue'], errors='coerce'
            )
            growth_df['daily_revenue'] = pd.to_numeric(
                growth_df['daily_revenue'], errors='coerce'
            )

            growth_df = growth_df.dropna(
                subset=['snapshot_date', 'cumulative_revenue']
            )

            # ---- CREATE FIGURE ----
            fig = go.Figure()

            fig.add_trace(go.Scatter(
                x=growth_df['snapshot_date'],
                y=growth_df['cumulative_revenue'],
                fill='tozeroy',
                fillcolor="rgba(64, 145, 108, 0.13)",
                line=dict(color=COLORS["fern"], width=2.5),
                name='Cumulative Revenue',
                hovertemplate="<b>%{x}</b><br>R %{y:,.0f}<extra></extra>",
            ))

            chart_layout(fig, height=300, has_axes=True)
            fig.update_layout(showlegend=False)

            st.plotly_chart(fig, use_container_width=True)

        else:
            st.info("No revenue growth data available.")

            fig.add_trace(go.Bar(
                x=growth_df['snapshot_date'],
                y=growth_df['daily_revenue'],
                name='Daily Revenue',
                marker_color="rgba(13, 110, 138, 0.40)",
                yaxis='y2',
                hovertemplate="<b>%{x}</b><br>Daily: R %{y:,.0f}<extra></extra>",
            ))
            chart_layout(fig, height=320, has_axes=True)
            fig.update_layout(
                yaxis2=dict(overlaying='y', side='right', showgrid=False,
                            tickfont=dict(size=10), tickformat=',.0f'),
                legend=dict(orientation='h', y=1.05, x=0),
                hovermode='x unified',
            )
            st.plotly_chart(fig, use_container_width=True)

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    col1, col2 = st.columns([1.6, 1])

    with col1:
        st.markdown("<div class='section-title'>Top 15 Medications by Prescription Volume</div>", unsafe_allow_html=True)
        if not medications_df.empty:
            top15 = medications_df.head(15).sort_values('prescription_count')
            fig = go.Figure(go.Bar(
                x=top15['prescription_count'],
                y=top15['medication_name'],
                orientation='h',
                marker=dict(
                    color=top15['prescription_count'],
                    colorscale=[[0, COLORS["mint"]], [0.5, COLORS["teal_light"]], [1, COLORS["teal"]]],
                    showscale=False,
                ),
                text=top15['prescription_count'],
                textposition='outside',
                textfont=dict(size=10),
                customdata=top15[['therapeutic_class', 'total_revenue']].values,
                hovertemplate="<b>%{y}</b><br>Prescriptions: %{x}<br>Class: %{customdata[0]}<br>Revenue: R %{customdata[1]:,.0f}<extra></extra>",
            ))
            chart_layout(fig, height=440, has_axes=True)
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.markdown("<div class='section-title'>Payment Method Split</div>", unsafe_allow_html=True)
        if not kpi_df.empty:
            kpi = kpi_df.iloc[0]
            fig = go.Figure(go.Pie(
                labels=['Medical Aid', 'Cash'],
                values=[kpi.get('medical_aid_count', 0), kpi.get('cash_count', 0)],
                hole=0.6,
                marker=dict(colors=[COLORS["forest"], COLORS["teal"]]),
                textinfo='label+percent',
                textfont=dict(size=12, family="DM Sans"),
                hovertemplate="<b>%{label}</b><br>%{value:,} transactions<br>%{percent}<extra></extra>",
            ))
            chart_layout(fig, height=260, has_axes=False)
            fig.update_layout(
                showlegend=False,
                annotations=[dict(
                    text=f"{fmt_number(kpi.get('total_prescriptions'))}<br><span style='font-size:10px'>total</span>",
                    x=0.5, y=0.5,
                    font=dict(size=18, family="Cormorant Garamond", color=COLORS["forest"]),
                    showarrow=False,
                )]
            )
            st.plotly_chart(fig, use_container_width=True)

        st.markdown("<div class='section-title'>Profit Margin by Pharmacy</div>", unsafe_allow_html=True)
        if not pharmacy_df.empty:
            fig = go.Figure(go.Bar(
                x=pharmacy_df['location_name'],
                y=pharmacy_df['profit_margin_pct'],
                marker=dict(
                    color=pharmacy_df['profit_margin_pct'],
                    colorscale=[[0, COLORS["mint"]], [1, COLORS["forest"]]],
                    showscale=False,
                ),
                text=pharmacy_df['profit_margin_pct'].apply(lambda x: f"{x:.1f}%"),
                textposition='outside',
                hovertemplate="<b>%{x}</b><br>Margin: %{y:.1f}%<extra></extra>",
            ))
            chart_layout(fig, height=200, has_axes=True)
            fig.update_xaxes(tickangle=-20, tickfont=dict(size=9))
            st.plotly_chart(fig, use_container_width=True)

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    st.markdown("<div class='section-title'>Stock Alerts</div>", unsafe_allow_html=True)
    if stock_alerts_df.empty:
        st.markdown("<div class='alert-ok'>✓ All stock levels are within normal thresholds.</div>", unsafe_allow_html=True)
    else:
        c1, c2 = st.columns([1, 2])
        with c1:
            counts = stock_alerts_df['stock_status_code'].value_counts()
            for status, count in counts.items():
                cls   = "alert-critical" if status == "OUT" else "alert-warning"
                label = "OUT OF STOCK" if status == "OUT" else "LOW STOCK" if status == "LOW" else "NEAR EXPIRY"
                st.markdown(f"<div class='{cls}' style='margin-bottom:0.5rem;'><b>{label}</b> — {count} item(s)</div>", unsafe_allow_html=True)
        with c2:
            st.dataframe(
                stock_alerts_df[['location_name', 'medication_name', 'stock_status_code', 'quantity_on_hand', 'reorder_point']].rename(columns={
                    'location_name': 'Pharmacy', 'medication_name': 'Medication',
                    'stock_status_code': 'Status', 'quantity_on_hand': 'On Hand', 'reorder_point': 'Reorder Point',
                }),
                use_container_width=True, hide_index=True,
            )


# ===========================================================================
# TAB 2: PIPELINE HEALTH
# ===========================================================================
elif "Pipeline Health" in page:

    # -----------------------------------------------------------------------
    # SAFETY: Ensure DataFrames exist
    # -----------------------------------------------------------------------
    pipeline_sum_df = pipeline_sum_df if 'pipeline_sum_df' in locals() else pd.DataFrame()
    pipeline_daily_df = pipeline_daily_df if 'pipeline_daily_df' in locals() else pd.DataFrame()
    growth_df = growth_df if 'growth_df' in locals() else pd.DataFrame()
    pipeline_runs_df = pipeline_runs_df if 'pipeline_runs_df' in locals() else pd.DataFrame()

    # -----------------------------------------------------------------------
    # KPI SECTION
    # -----------------------------------------------------------------------
    ps = pipeline_sum_df.iloc[0] if not pipeline_sum_df.empty else {}

    c1, c2, c3, c4 = st.columns(4)

    with c1:
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Total Runs</div>
            <div class="kpi-value">{fmt_number(ps.get('total_runs'))}</div>
            <div class="kpi-delta">Pipeline executions</div>
        </div>""", unsafe_allow_html=True)

    with c2:
        rate = float(ps.get('success_rate_pct') or 0)
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Success Rate</div>
            <div class="kpi-value">{rate:.1f}%</div>
            <div class="kpi-delta">↑ Reliability</div>
        </div>""", unsafe_allow_html=True)

    with c3:
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Rows Loaded</div>
            <div class="kpi-value">{fmt_number(ps.get('total_rows_loaded'))}</div>
            <div class="kpi-delta">↑ Total records</div>
        </div>""", unsafe_allow_html=True)

    with c4:
        avg_dur = ps.get('avg_duration_seconds')
        dur_str = f"{float(avg_dur):.0f}s" if avg_dur else "—"
        st.markdown(f"""<div class="kpi-card">
            <div class="kpi-label">Avg Duration</div>
            <div class="kpi-value">{dur_str}</div>
            <div class="kpi-delta">Per run</div>
        </div>""", unsafe_allow_html=True)

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    # -----------------------------------------------------------------------
    # DAILY ROWS LOADED (BAR CHART)
    # -----------------------------------------------------------------------
    col1, col2 = st.columns(2)

    with col1:
        st.markdown("<div class='section-title'>Daily Rows Loaded</div>", unsafe_allow_html=True)

        if not pipeline_daily_df.empty:

            pipeline_daily_df = pipeline_daily_df.copy()
            pipeline_daily_df['run_date'] = pd.to_datetime(
                pipeline_daily_df['run_date'], errors='coerce'
            )
            pipeline_daily_df['rows_loaded'] = pd.to_numeric(
                pipeline_daily_df['rows_loaded'], errors='coerce'
            )
            pipeline_daily_df['rows_skipped'] = pd.to_numeric(
                pipeline_daily_df['rows_skipped'], errors='coerce'
            )

            pipeline_daily_df = pipeline_daily_df.dropna(
                subset=['run_date', 'rows_loaded', 'rows_skipped']
            )

            fig = go.Figure()

            fig.add_trace(go.Bar(
                x=pipeline_daily_df['run_date'],
                y=pipeline_daily_df['rows_loaded'],
                name='Loaded',
                marker_color=COLORS["fern"],
                hovertemplate="<b>%{x}</b><br>Loaded: %{y:,}<extra></extra>",
            ))

            fig.add_trace(go.Bar(
                x=pipeline_daily_df['run_date'],
                y=pipeline_daily_df['rows_skipped'],
                name='Skipped',
                marker_color=COLORS["sage"],
                hovertemplate="<b>%{x}</b><br>Skipped: %{y:,}<extra></extra>",
            ))

            chart_layout(fig, height=320, has_axes=True)
            fig.update_layout(barmode='stack', legend=dict(orientation='h', y=1.1))
            st.plotly_chart(fig, use_container_width=True)

        else:
            st.info("No daily pipeline data available.")

    # -----------------------------------------------------------------------
    # RUN STATUS DISTRIBUTION (PIE)
    # -----------------------------------------------------------------------
    with col2:
        st.markdown("<div class='section-title'>Run Status Distribution</div>", unsafe_allow_html=True)

        if not pipeline_sum_df.empty:

            fig = go.Figure(go.Pie(
                labels=['Success', 'Failed', 'Partial'],
                values=[
                    int(ps.get('successful_runs') or 0),
                    int(ps.get('failed_runs') or 0),
                    int(ps.get('partial_runs') or 0),
                ],
                hole=0.55,
                marker=dict(colors=[COLORS["fern"], "#C0392B", COLORS["gold"]]),
                textinfo='label+percent',
                textfont=dict(size=12),
                hovertemplate="<b>%{label}</b><br>%{value} runs (%{percent})<extra></extra>",
            ))

            chart_layout(fig, height=320, has_axes=False)
            fig.update_layout(showlegend=False)
            st.plotly_chart(fig, use_container_width=True)

        else:
            st.info("No pipeline summary data available.")

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    # -----------------------------------------------------------------------
    # CUMULATIVE GROWTH
    # -----------------------------------------------------------------------
    st.markdown("<div class='section-title'>Cumulative Records Loaded into Warehouse</div>", unsafe_allow_html=True)

    if not growth_df.empty:

        growth_df = growth_df.copy()

        growth_df['snapshot_date'] = pd.to_datetime(
            growth_df['snapshot_date'], errors='coerce'
        )
        growth_df['cumulative_prescriptions'] = pd.to_numeric(
            growth_df['cumulative_prescriptions'], errors='coerce'
        )

        growth_df = growth_df.dropna(
            subset=['snapshot_date', 'cumulative_prescriptions']
        )

        fig = go.Figure()

        fig.add_trace(go.Scatter(
            x=growth_df['snapshot_date'],
            y=growth_df['cumulative_prescriptions'],
            fill='tozeroy',
            fillcolor="rgba(27, 67, 50, 0.15)",
            line=dict(color=COLORS["forest"], width=2.5),
            name='Cumulative Prescriptions',
            hovertemplate="<b>%{x}</b><br>Total: %{y:,}<extra></extra>",
        ))

        chart_layout(fig, height=280, has_axes=True)
        fig.update_layout(showlegend=False)
        st.plotly_chart(fig, use_container_width=True)

    else:
        st.info("No cumulative growth data available.")

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    # -----------------------------------------------------------------------
    # RECENT PIPELINE RUNS TABLE
    # -----------------------------------------------------------------------
    st.markdown("<div class='section-title'>Recent Pipeline Runs</div>", unsafe_allow_html=True)

    if not pipeline_runs_df.empty:

        display_df = pipeline_runs_df[[
            'run_id', 'run_date', 'stage', 'rows_loaded',
            'rows_skipped', 'rows_failed', 'status',
            'duration_seconds', 'started_at'
        ]].rename(columns={
            'run_id': 'ID',
            'run_date': 'Date',
            'stage': 'Stage',
            'rows_loaded': 'Loaded',
            'rows_skipped': 'Skipped',
            'rows_failed': 'Failed',
            'status': 'Status',
            'duration_seconds': 'Duration (s)',
            'started_at': 'Started At',
        })

        st.dataframe(display_df, use_container_width=True, hide_index=True)

    else:
        st.markdown(
            "<div class='alert-warning'>No pipeline runs recorded yet. Run the ETL pipeline to populate this table.</div>",
            unsafe_allow_html=True
        )

# ===========================================================================
# TAB 3: DATA QUALITY
# ===========================================================================
elif "Data Quality" in page:

    if not dq_summary_df.empty:
        total_checked = dq_summary_df['total_rows_checked'].sum()
        total_failed  = dq_summary_df['total_rows_failed'].sum()
        total_pass    = total_checked - total_failed
        pass_rate     = round(total_pass * 100 / total_checked, 1) if total_checked > 0 else 0
        warnings      = dq_summary_df['warnings'].sum()
        critical      = dq_summary_df['critical_issues'].sum()

        c1, c2, c3, c4 = st.columns(4)
        with c1:
            st.markdown(f"""<div class="kpi-card">
                <div class="kpi-label">Rows Checked</div>
                <div class="kpi-value">{fmt_number(total_checked)}</div>
                <div class="kpi-delta">Across all datasets</div>
            </div>""", unsafe_allow_html=True)
        with c2:
            st.markdown(f"""<div class="kpi-card">
                <div class="kpi-label">Pass Rate</div>
                <div class="kpi-value">{pass_rate}%</div>
                <div class="kpi-delta">After ETL cleaning</div>
            </div>""", unsafe_allow_html=True)
        with c3:
            st.markdown(f"""<div class="kpi-card">
                <div class="kpi-label">Warnings</div>
                <div class="kpi-value">{fmt_number(warnings)}</div>
                <div class="kpi-delta">Issues detected & fixed</div>
            </div>""", unsafe_allow_html=True)
        with c4:
            st.markdown(f"""<div class="kpi-card">
                <div class="kpi-label">Critical Issues</div>
                <div class="kpi-value">{fmt_number(critical)}</div>
                <div class="kpi-delta">Requiring attention</div>
            </div>""", unsafe_allow_html=True)

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    col1, col2 = st.columns(2)

    with col1:
        st.markdown("<div class='section-title'>Issues by Dataset</div>", unsafe_allow_html=True)
        if not dq_summary_df.empty:
            fig = go.Figure()
            datasets = dq_summary_df['dataset'].unique()
            for i, dataset in enumerate(datasets):
                d = dq_summary_df[dq_summary_df['dataset'] == dataset]
                fig.add_trace(go.Bar(
                    name=dataset.capitalize(),
                    x=d['run_date'].astype(str),
                    y=d['total_rows_failed'],
                    marker_color=CHART_COLORS[i % len(CHART_COLORS)],
                    hovertemplate=f"<b>{dataset}</b><br>Failed: %{{y}}<extra></extra>",
                ))
            chart_layout(fig, height=320, has_axes=True)
            fig.update_layout(barmode='group', legend=dict(orientation='h', y=1.1))
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.markdown("<div class='section-title'>Failure Rate by Dataset</div>", unsafe_allow_html=True)
        if not dq_summary_df.empty:
            latest = (
                dq_summary_df
                .sort_values("run_date", ascending=False)
                .groupby('dataset')
                .first()
                .reset_index()
            )
            fig = go.Figure(go.Bar(
                x=latest['dataset'],
                y=latest['overall_failure_rate_pct'],
                marker=dict(
                    color=latest['overall_failure_rate_pct'],
                    colorscale=[[0, COLORS["mint"]], [0.5, COLORS["gold"]], [1, "#C0392B"]],
                    showscale=True,
                    colorbar=dict(title="Fail %", thickness=12),
                ),
                text=latest['overall_failure_rate_pct'].apply(lambda x: f"{x:.1f}%"),
                textposition='outside',
                hovertemplate="<b>%{x}</b><br>Failure rate: %{y:.2f}%<extra></extra>",
            ))
            chart_layout(fig, height=320, has_axes=True)
            fig.update_yaxes(title_text="Failure Rate (%)")
            st.plotly_chart(fig, use_container_width=True)

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    st.markdown("<div class='section-title'>Quality Issue Log</div>", unsafe_allow_html=True)
    if not dq_log_df.empty:
        st.dataframe(dq_log_df, use_container_width=True, hide_index=True)

    if not dq_log_df.empty:
        def severity_badge(sev):
            if sev == 'CRITICAL':
                return f"🔴 {sev}"
            elif sev == 'WARNING':
                return f"🟡 {sev}"
            return f"🟢 {sev}"

        dq_log_df['severity'] = dq_log_df['severity'].apply(severity_badge)
        st.dataframe(
            dq_log_df.rename(columns={
                'run_date': 'Date', 'dataset': 'Dataset', 'check_name': 'Check',
                'check_category': 'Category', 'rows_checked': 'Checked',
                'rows_failed': 'Failed', 'failure_rate_pct': 'Fail %',
                'severity': 'Severity', 'details': 'Details',
            }),
            use_container_width=True,
            hide_index=True,
        )

    st.markdown("<hr class='pf-divider'/>", unsafe_allow_html=True)

    st.markdown("<div class='section-title'>What the ETL Pipeline Fixed</div>", unsafe_allow_html=True)
    fixes = [
        ("Prescription duplicates",    "5% of records had duplicate prescription numbers — removed during deduplication"),
        ("Currency format errors",     "R prefix in total_amount fields — stripped and cast to numeric"),
        ("Outlier quantities",         "Zero, negative, or >365 day quantities — filtered as invalid"),
        ("Negative inventory",         "Negative quantity_on_hand values — corrected to 0"),
        ("Pharmacy ID typos",          "Trailing 'X' characters in pharmacy_id — stripped"),
        ("Invalid email formats",      "'AT' used instead of '@' in email addresses — corrected"),
        ("Inconsistent date formats",  "DD/MM/YYYY mixed with YYYY-MM-DD — normalised to ISO"),
        ("Missing medication records", "3 medication records missing required fields — excluded from load"),
    ]
    col1, col2 = st.columns(2)
    for i, (issue, fix) in enumerate(fixes):
        with (col1 if i % 2 == 0 else col2):
            st.markdown(f"""
            <div class="alert-ok" style="margin-bottom:0.5rem;">
                <b>✓ {issue}</b><br>
                <span style="font-size:0.82rem;">{fix}</span>
            </div>""", unsafe_allow_html=True)

# ===========================================================================
# FOOTER
# ===========================================================================
st.markdown(f"""
<hr style="margin-top: 60px; margin-bottom: 10px; border: 0.5px solid {COLORS["mint"]};">

<div style='text-align: center; font-size: 13px; color: {COLORS["charcoal"]}; padding-bottom: 10px;'>
    <b>PharmaFlow Warehouse Analytics</b><br>
    by Boikanyo Maswi © 2026
</div>
""", unsafe_allow_html=True)