#!/usr/bin/env python3
"""
Captures high-resolution screenshots of the Milestone 4 interactive dashboard
across key stages of the guided demonstration using headless Brave Browser.
"""

import json
import os
import subprocess
import time
import urllib.request
from http.server import HTTPServer

from demo_server import DemoEngine, DemoServerHandler


def capture_screenshots(output_dir: str = "results/milestone4_screenshots") -> None:
    os.makedirs(output_dir, exist_ok=True)
    port = 8092

    engine = DemoEngine(seed=42)
    DemoServerHandler.engine = engine
    server = HTTPServer(("127.0.0.1", port), DemoServerHandler)

    import threading
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    time.sleep(0.5)

    brave_path = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
    url = f"http://127.0.0.1:{port}"

    stages_to_capture = [
        (1, "01_stage1_stable_5g.png", "Stage 1: Stable Connectivity"),
        (3, "02_stage3_predictive_preparation.png", "Stage 3: Predictive Pre-Provisioning"),
        (5, "03_stage5_adaptive_recalculation.png", "Stage 5: Adaptive Recalculation under Shock"),
        (6, "04_stage6_outage_demand_draw.png", "Stage 6: Outage Payment Demand Draw"),
        (7, "05_stage7_recovery_benchmark.png", "Stage 7: Recovery & Strategy Comparison"),
    ]

    for stage_id, filename, desc in stages_to_capture:
        print(f"Capturing screenshot: {desc} -> {filename} ... ", end="", flush=True)
        # Advance engine to stage
        req = urllib.request.Request(
            f"{url}/api/guided_step",
            data=json.dumps({"stage_id": stage_id}).encode(),
            headers={"Content-Type": "application/json"}
        )
        urllib.request.urlopen(req)
        time.sleep(0.4)

        out_path = os.path.abspath(os.path.join(output_dir, filename))
        cmd = [
            brave_path,
            "--headless=new",
            "--disable-gpu",
            "--window-size=1440,960",
            f"--screenshot={out_path}",
            url,
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0 and os.path.exists(out_path):
            print(f"DONE ({os.path.getsize(out_path)} bytes)")
        else:
            print(f"FAILED (code {res.returncode}): {res.stderr.decode()}")

    server.shutdown()
    print(f"\nAll screenshots successfully saved to: {output_dir}")


if __name__ == "__main__":
    capture_screenshots()

