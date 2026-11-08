#!/usr/bin/env python3
"""
Milestone 4 Interactive Demonstration Server:
Predictive Adaptive Offline Provisioning Demonstrator.

Zero third-party dependencies: Built on standard Python http.server.
Serves the judge-facing dashboard and live REST APIs backed by the
actual simulation engine and mathematical optimization algorithms.
"""

import argparse
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

from src.demo_engine import DemoEngine


class DemoServerHandler(BaseHTTPRequestHandler):
    """HTTP Request Handler dispatching REST API calls to the live DemoEngine."""

    engine: DemoEngine = None  # Class-level injection

    def _set_headers(self, status: int = 200, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.end_headers()

    def do_OPTIONS(self) -> None:
        self._set_headers(200)

    def do_GET(self) -> None:
        parsed_url = urlparse(self.path)
        path = parsed_url.path

        if path in ["/", "/index.html"]:
            static_dir = os.path.join(os.path.dirname(__file__), "static")
            html_path = os.path.join(static_dir, "index.html")
            if os.path.exists(html_path):
                with open(html_path, "r", encoding="utf-8") as f:
                    content = f.read()
                self._set_headers(200, "text/html; charset=utf-8")
                self.wfile.write(content.encode("utf-8"))
            else:
                self._set_headers(404, "text/plain")
                self.wfile.write(b"Dashboard HTML not found in static/index.html")
            return

        if path == "/api/status":
            state = self.engine.get_full_state()
            self._set_headers(200, "application/json")
            self.wfile.write(json.dumps(state).encode("utf-8"))
            return

        if path == "/api/compare":
            records = self.engine.run_live_comparison_benchmark(epochs=30)
            self._set_headers(200, "application/json")
            self.wfile.write(json.dumps({"comparison": records}).encode("utf-8"))
            return

        # 404 fallback
        self._set_headers(404, "application/json")
        self.wfile.write(json.dumps({"error": f"Path not found: {path}"}).encode("utf-8"))

    def do_POST(self) -> None:
        parsed_url = urlparse(self.path)
        path = parsed_url.path

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode("utf-8") if content_length > 0 else "{}"
        try:
            payload = json.loads(body) if body else {}
        except Exception:
            payload = {}

        if path == "/api/scenario":
            scenario_id = int(payload.get("scenario_id", 1))
            wallet_balance = payload.get("wallet_balance", payload.get("available_balance"))
            wb = float(wallet_balance) if wallet_balance is not None else None
            try:
                state = self.engine.apply_scenario(scenario_id, wallet_balance=wb)
                self._set_headers(200, "application/json")
                self.wfile.write(json.dumps(state).encode("utf-8"))
            except Exception as e:
                self._set_headers(400, "application/json")
                self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))
            return

        if path == "/api/wallet_balance":
            bal = float(payload.get("available_balance", payload.get("wallet_balance", 122.0)))
            state = self.engine.set_wallet_balance(bal)
            self._set_headers(200, "application/json")
            self.wfile.write(json.dumps(state).encode("utf-8"))
            return

        if path == "/api/guided_step":
            stage_id = payload.get("stage_id", 1)
            try:
                state = self.engine.execute_guided_stage(int(stage_id))
                self._set_headers(200, "application/json")
                self.wfile.write(json.dumps(state).encode("utf-8"))
            except Exception as e:
                self._set_headers(400, "application/json")
                self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))
            return

        if path == "/api/manual_telemetry":
            outage_p = float(payload.get("outage_prob", 0.08))
            duration_h = float(payload.get("duration_hours", 0.5))
            is_shock = bool(payload.get("is_shock", False))
            signal_dbm = int(payload.get("signal_dbm", -85))

            state = self.engine.apply_manual_network_condition(
                outage_prob=outage_p,
                duration_hours=duration_h,
                is_shock=is_shock,
                signal_dbm=signal_dbm,
            )
            self._set_headers(200, "application/json")
            self.wfile.write(json.dumps(state).encode("utf-8"))
            return

        if path == "/api/reset":
            self.engine.reset_to_baseline()
            state = self.engine.get_full_state()
            self._set_headers(200, "application/json")
            self.wfile.write(json.dumps(state).encode("utf-8"))
            return

        self._set_headers(404, "application/json")
        self.wfile.write(json.dumps({"error": f"API endpoint not found: {path}"}).encode("utf-8"))

    def log_message(self, format: str, *args) -> None:
        # Keep server console clean unless an error occurs
        if args and str(args[1]) in ["404", "500"]:
            super().log_message(format, *args)


def find_available_port(start_port: int = 8050, max_attempts: int = 20) -> int:
    """Finds an unbound TCP port for the local server."""
    for port in range(start_port, start_port + max_attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    return start_port


def run_server(port: int = 8050) -> None:
    HTTPServer.allow_reuse_address = True
    assigned_port = find_available_port(port)
    engine = DemoEngine(seed=42)
    DemoServerHandler.engine = engine

    server_address = ("127.0.0.1", assigned_port)
    httpd = HTTPServer(server_address, DemoServerHandler)

    print("=" * 80)
    print(" UPIMesh Research — Milestone 4 Demonstrator")
    print(" Predictive Adaptive Offline Provisioning Dashboard")
    print("=" * 80)
    print(f" -> Local Dashboard URL: http://localhost:{assigned_port}")
    print(f" -> Status API:          http://localhost:{assigned_port}/api/status")
    print(" -> Press Ctrl+C to terminate.")
    print("=" * 80)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nDemonstrator server shut down successfully.")
        httpd.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Milestone 4 Demonstrator Web Server")
    parser.add_argument("--port", type=int, default=8050, help="HTTP port (default: 8050)")
    args = parser.parse_args()

    run_server(port=args.port)

