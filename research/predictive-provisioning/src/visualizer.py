"""
Pure Python zero-dependency vector graphics (SVG) chart generator and HTML report builder.
Generates publication-quality charts and an interactive summary dashboard.
"""

import os
from typing import Dict, List
from .models import BenchmarkSummary, EpochResult


class ResultsVisualizer:
    """
    Renders simulation results into crisp standalone SVG vector images
    and an interactive standalone HTML report.
    """

    # UPIMesh Dark Glass Theme Colors
    COLOR_BG = "#0d1117"
    COLOR_CARD = "#161b22"
    COLOR_BORDER = "#30363d"
    COLOR_TEXT = "#c9d1d9"
    COLOR_TEXT_MUTED = "#8b949e"
    COLOR_GRID = "#21262d"

    # Strategy Colors
    STRATEGY_COLORS = {
        "Fixed-₹500": "#f59e0b",          # Amber / Gold
        "Demand-Only": "#ef4444",         # Crimson Red
        "Proposed-JointOpt": "#3b82f6",    # Blue (Milestone 1)
        "Uncertainty-Aware": "#10b981",    # Emerald Green (Milestone 2)
    }

    def __init__(self, output_dir: str):
        self.output_dir = output_dir
        self.charts_dir = os.path.join(output_dir, "charts")
        os.makedirs(self.charts_dir, exist_ok=True)

    def generate_all_visualizations(
        self,
        summaries: List[BenchmarkSummary],
        epoch_results: List[EpochResult],
    ) -> Dict[str, str]:
        """Generates all SVG charts and the HTML report, returning generated file paths."""
        chart_paths = {}

        # 1. Bar Chart: Success Rate vs Locked Funds across Scenarios
        bar_chart_path = os.path.join(self.charts_dir, "benchmark_metrics.svg")
        self._render_grouped_bar_chart(summaries, bar_chart_path)
        chart_paths["benchmark_metrics"] = bar_chart_path

        # 2. Scatter Plot: Trade-off Frontier (Locked Funds vs Success Rate)
        frontier_path = os.path.join(self.charts_dir, "trade_off_frontier.svg")
        self._render_tradeoff_frontier(summaries, frontier_path)
        chart_paths["trade_off_frontier"] = frontier_path

        # 3. HTML Dashboard
        html_path = os.path.join(self.output_dir, "report.html")
        self._render_html_report(summaries, html_path)
        chart_paths["html_report"] = html_path

        return chart_paths

    def _render_grouped_bar_chart(self, summaries: List[BenchmarkSummary], output_path: str) -> None:
        """Renders grouped bar chart of Success Rate (%) and Average Locked Funds (₹)."""
        scenarios = sorted(list(set(s.outage_scenario for s in summaries)))
        strategies = sorted(list(set(s.strategy for s in summaries)))

        width = 860
        height = 480
        margin_left = 80
        margin_right = 40
        margin_top = 70
        margin_bottom = 100

        plot_w = width - margin_left - margin_right
        plot_h = height - margin_top - margin_bottom

        # Group metrics
        svg_parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" style="background-color: {self.COLOR_BG}; font-family: -apple-system, BlinkMacSystemFont, sans-serif;">',
            f'<rect width="{width}" height="{height}" fill="{self.COLOR_BG}" />',
            # Title
            f'<text x="{margin_left}" y="32" fill="{self.COLOR_TEXT}" font-size="18" font-weight="bold">Offline Payment Success Rate vs Locked Funds by Scenario</text>',
            f'<text x="{margin_left}" y="52" fill="{self.COLOR_TEXT_MUTED}" font-size="12">Comparison of Proposed Joint Optimization against Fixed and Demand-Only Baselines</text>',
        ]

        # Horizontal Gridlines for Success Rate (0% to 100%)
        for pct in [0, 25, 50, 75, 100]:
            y = margin_top + plot_h - (pct / 100.0) * plot_h
            svg_parts.append(f'<line x1="{margin_left}" y1="{y}" x2="{margin_left + plot_w}" y2="{y}" stroke="{self.COLOR_GRID}" stroke-width="1" />')
            svg_parts.append(f'<text x="{margin_left - 10}" y="{y + 4}" fill="{self.COLOR_TEXT_MUTED}" font-size="11" text-anchor="end">{pct}%</text>')

        # Draw Grouped Bars
        group_width = plot_w / max(1, len(scenarios))
        bar_w = (group_width * 0.7) / max(1, len(strategies))

        for sc_idx, sc_name in enumerate(scenarios):
            sc_x = margin_left + sc_idx * group_width

            # Group Label (shortened)
            short_name = sc_name.replace(" Commute", "").replace(" Weak Signal", "").replace(" Travel Shift", "")
            svg_parts.append(
                f'<text x="{sc_x + group_width * 0.4}" y="{margin_top + plot_h + 24}" fill="{self.COLOR_TEXT}" font-size="11" text-anchor="middle" font-weight="500">{short_name}</text>'
            )

            for st_idx, st_name in enumerate(strategies):
                match = next((s for s in summaries if s.outage_scenario == sc_name and s.strategy == st_name), None)
                if match:
                    val = match.offline_success_rate
                    bar_h = (val / 100.0) * plot_h
                    bx = sc_x + (group_width * 0.15) + st_idx * bar_w
                    by = margin_top + plot_h - bar_h
                    color = self.STRATEGY_COLORS.get(st_name, "#3b82f6")

                    svg_parts.append(
                        f'<rect x="{bx}" y="{by}" width="{bar_w - 4}" height="{bar_h}" rx="3" fill="{color}" opacity="0.9">'
                        f'<title>{st_name}: {val:.1f}% success, ₹{match.average_locked_funds:.0f} locked</title>'
                        f'</rect>'
                    )
                    # Label on top of bar if height permits
                    if bar_h > 20:
                        svg_parts.append(
                            f'<text x="{bx + (bar_w - 4) / 2}" y="{by - 6}" fill="{color}" font-size="9" text-anchor="middle" font-weight="bold">{val:.0f}%</text>'
                        )

        # Legend at bottom
        legend_y = height - 25
        leg_x = margin_left + 10
        for st_name, col in self.STRATEGY_COLORS.items():
            svg_parts.append(f'<rect x="{leg_x}" y="{legend_y - 10}" width="14" height="14" rx="3" fill="{col}" />')
            svg_parts.append(f'<text x="{leg_x + 18}" y="{legend_y + 1}" fill="{self.COLOR_TEXT}" font-size="11">{st_name}</text>')
            leg_x += 175

        svg_parts.append('</svg>')

        with open(output_path, "w", encoding="utf-8") as f:
            f.write("\n".join(svg_parts))

    def _render_tradeoff_frontier(self, summaries: List[BenchmarkSummary], output_path: str) -> None:
        """Renders 2D trade-off scatter plot: Average Locked Funds (X) vs Offline Success Rate (Y)."""
        width = 720
        height = 460
        margin_left = 80
        margin_right = 50
        margin_top = 70
        margin_bottom = 70

        plot_w = width - margin_left - margin_right
        plot_h = height - margin_top - margin_bottom

        max_x = max([s.average_locked_funds for s in summaries] + [600.0]) * 1.15
        max_y = 100.0

        svg_parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" style="background-color: {self.COLOR_BG}; font-family: -apple-system, BlinkMacSystemFont, sans-serif;">',
            f'<rect width="{width}" height="{height}" fill="{self.COLOR_BG}" />',
            # Title
            f'<text x="{margin_left}" y="32" fill="{self.COLOR_TEXT}" font-size="18" font-weight="bold">Efficiency Frontier: Locked Funds vs Offline Success Rate</text>',
            f'<text x="{margin_left}" y="52" fill="{self.COLOR_TEXT_MUTED}" font-size="12">Top-left indicates optimal trade-off (high offline success with minimal idle locked escrow)</text>',
        ]

        # Axes & Gridlines
        for pct in [20, 40, 60, 80, 100]:
            y = margin_top + plot_h - (pct / max_y) * plot_h
            svg_parts.append(f'<line x1="{margin_left}" y1="{y}" x2="{margin_left + plot_w}" y2="{y}" stroke="{self.COLOR_GRID}" stroke-width="1" />')
            svg_parts.append(f'<text x="{margin_left - 10}" y="{y + 4}" fill="{self.COLOR_TEXT_MUTED}" font-size="11" text-anchor="end">{pct}%</text>')

        for x_val in range(0, int(max_x), 150):
            x = margin_left + (x_val / max_x) * plot_w
            svg_parts.append(f'<line x1="{x}" y1="{margin_top}" x2="{x}" y2="{margin_top + plot_h}" stroke="{self.COLOR_GRID}" stroke-width="1" />')
            svg_parts.append(f'<text x="{x}" y="{margin_top + plot_h + 20}" fill="{self.COLOR_TEXT_MUTED}" font-size="11" text-anchor="middle">₹{x_val}</text>')

        # Axis Titles
        svg_parts.append(f'<text x="{margin_left + plot_w / 2}" y="{height - 20}" fill="{self.COLOR_TEXT_MUTED}" font-size="12" text-anchor="middle">Average Locked Reserve in Escrow (INR)</text>')
        svg_parts.append(f'<text x="20" y="{margin_top + plot_h / 2}" fill="{self.COLOR_TEXT_MUTED}" font-size="12" text-anchor="middle" transform="rotate(-90 20 {margin_top + plot_h / 2})">Offline Success Rate (%)</text>')

        # Plot Data Points
        for s in summaries:
            col = self.STRATEGY_COLORS.get(s.strategy, "#3b82f6")
            cx = margin_left + (s.average_locked_funds / max_x) * plot_w
            cy = margin_top + plot_h - (s.offline_success_rate / max_y) * plot_h

            svg_parts.append(
                f'<circle cx="{cx}" cy="{cy}" r="7" fill="{col}" stroke="#ffffff" stroke-width="1.5" opacity="0.85">'
                f'<title>{s.strategy} ({s.outage_scenario}): {s.offline_success_rate:.1f}% success, ₹{s.average_locked_funds:.0f} locked</title>'
                f'</circle>'
            )

        # Legend
        leg_x = margin_left + 30
        leg_y = margin_top + 20
        for st_name, col in self.STRATEGY_COLORS.items():
            svg_parts.append(f'<circle cx="{leg_x}" cy="{leg_y}" r="5" fill="{col}" />')
            svg_parts.append(f'<text x="{leg_x + 12}" y="{leg_y + 4}" fill="{self.COLOR_TEXT}" font-size="11">{st_name}</text>')
            leg_x += 160

        svg_parts.append('</svg>')

        with open(output_path, "w", encoding="utf-8") as f:
            f.write("\n".join(svg_parts))

    def _render_html_report(self, summaries: List[BenchmarkSummary], output_path: str) -> None:
        """Generates a standalone responsive HTML dashboard embedding tables and charts."""
        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UPIMesh Predictive Provisioning Benchmark Report</title>
    <style>
        :root {{
            --bg-canvas: #0a0e14;
            --bg-card: #161b22;
            --border: #30363d;
            --text-main: #f0f6fc;
            --text-dim: #8b949e;
            --gold: #f59e0b;
            --green: #10b981;
            --red: #ef4444;
        }}
        body {{
            background: var(--bg-canvas);
            color: var(--text-main);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 32px;
            line-height: 1.5;
        }}
        .container {{
            max-width: 1100px;
            margin: 0 auto;
        }}
        header {{
            border-bottom: 1px solid var(--border);
            padding-bottom: 20px;
            margin-bottom: 30px;
        }}
        h1 {{
            margin: 0 0 8px 0;
            font-size: 26px;
            color: var(--gold);
        }}
        .badge {{
            display: inline-block;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: bold;
            background: rgba(245, 158, 11, 0.15);
            color: var(--gold);
            margin-right: 6px;
        }}
        .card {{
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 24px;
            margin-bottom: 28px;
        }}
        .chart-grid {{
            display: grid;
            grid-template-columns: 1fr;
            gap: 24px;
            margin-bottom: 28px;
        }}
        @media (min-width: 900px) {{
            .chart-grid {{
                grid-template-columns: 1fr 1fr;
            }}
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }}
        th, td {{
            padding: 10px 12px;
            text-align: left;
            border-bottom: 1px solid var(--border);
        }}
        th {{
            color: var(--text-dim);
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.8px;
        }}
        tr:hover td {{
            background: rgba(255, 255, 255, 0.02);
        }}
        .num {{
            text-align: right;
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        }}
        .tag-uncertainty {{
            color: var(--green);
            font-weight: bold;
        }}
        .tag-joint {{
            color: #3b82f6;
            font-weight: bold;
        }}
        .tag-fixed {{
            color: var(--gold);
            font-weight: 500;
        }}
        .tag-demand {{
            color: var(--red);
            font-weight: 500;
        }}
        img.vector-chart {{
            width: 100%;
            height: auto;
            border-radius: 8px;
            display: block;
        }}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <span class="badge">RESEARCH MODULE</span>
            <span class="badge">UPIMESH CORE</span>
            <h1>Predictive Offline Payment Provisioning — Benchmark Report</h1>
            <p style="color: var(--text-dim); margin: 4px 0 0 0; font-size: 14px;">
                Experimental evaluation of Joint Optimization allowance provisioning against Fixed and Demand-Only baselines across non-stationary connectivity regimes.
            </p>
        </header>

        <div class="card">
            <h3 style="margin-top: 0; color: var(--gold);">Optimization Formulation</h3>
            <p style="font-size: 13px; color: var(--text-dim);">
                Minimizes total expected cost: <code>J(R) = c_lock &times; R &times; H + p_out &times; c_short &times; E[max(D_T - R, 0)] + c_exposure &times; Risk(R)</code><br>
                Subject to banking hard invariant: <code>0 &le; R &le; min(available_balance, maximum_allowance)</code>.
            </p>
        </div>

        <div class="chart-grid">
            <div class="card" style="padding: 16px;">
                <img src="charts/benchmark_metrics.svg" alt="Benchmark Metrics" class="vector-chart">
            </div>
            <div class="card" style="padding: 16px;">
                <img src="charts/trade_off_frontier.svg" alt="Trade-off Frontier" class="vector-chart">
            </div>
        </div>

        <div class="card">
            <h3 style="margin-top: 0;">Comprehensive Scenario Evaluation Table</h3>
            <table>
                <thead>
                    <tr>
                        <th>Scenario</th>
                        <th>Strategy</th>
                        <th class="num">Success Rate</th>
                        <th class="num">Shortage Rate</th>
                        <th class="num">Avg Locked (₹)</th>
                        <th class="num">Avg Unused (₹)</th>
                        <th class="num">Avg Shortage (₹)</th>
                        <th class="num">Demand MAE</th>
                    </tr>
                </thead>
                <tbody>
"""
        for s in summaries:
            if "Uncertainty" in s.strategy:
                strat_cls = "tag-uncertainty"
            elif "Joint" in s.strategy:
                strat_cls = "tag-joint"
            elif "Fixed" in s.strategy:
                strat_cls = "tag-fixed"
            else:
                strat_cls = "tag-demand"
            
            std_str = f" &plusmn; {s.success_rate_std:.1f}" if s.success_rate_std > 0 else ""
            html += f"""
                    <tr>
                        <td><strong>{s.outage_scenario}</strong></td>
                        <td class="{strat_cls}">{s.strategy}</td>
                        <td class="num">{s.offline_success_rate:.1f}%{std_str}</td>
                        <td class="num">{s.insufficient_reserve_rate:.1f}%</td>
                        <td class="num">₹{s.average_locked_funds:.2f}</td>
                        <td class="num">₹{s.average_unused_funds:.2f}</td>
                        <td class="num">₹{s.average_shortage_amount:.2f}</td>
                        <td class="num">₹{s.demand_mae:.2f}</td>
                    </tr>
"""
        html += """
                </tbody>
            </table>
        </div>
    </div>
</body>
</html>
"""
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(html)

