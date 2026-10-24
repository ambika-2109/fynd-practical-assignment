#!/usr/bin/env python3
"""End-to-end readiness, WAF behavior, and Wazuh event-delivery verifier."""

from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from typing import Any


def build_marker() -> str:
    return f"fyndlab-{uuid.uuid4().hex}"


def marker_url(app_url: str, marker: str) -> str:
    query = urllib.parse.urlencode({"lab_marker": marker})
    return f"{app_url.rstrip('/')}?{query}"


def event_contains_marker(event: dict[str, Any], marker: str) -> bool:
    """Search serialized event fields so minor Wazuh decoder variations are tolerated."""
    return marker in json.dumps(event, sort_keys=True)


def http_request(
    url: str,
    *,
    timeout: float,
    method: str = "GET",
    body: bytes | None = None,
    username: str | None = None,
    password: str | None = None,
    insecure_tls: bool = False,
) -> tuple[int, bytes]:
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if username is not None and password is not None:
        token = base64.b64encode(f"{username}:{password}".encode()).decode()
        headers["Authorization"] = f"Basic {token}"
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    context = None
    if url.startswith("https://") and insecure_tls:
        import ssl

        context = ssl._create_unverified_context()  # Wazuh's lab-generated certificate is self-signed.
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=context) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def wait_until(label: str, timeout: float, check: Any) -> None:
    deadline = time.monotonic() + timeout
    last_error = "not ready"
    while time.monotonic() < deadline:
        try:
            if check():
                print(f"PASS: {label}")
                return
        except Exception as error:  # Network readiness failures are retried until the deadline.
            last_error = str(error)
        time.sleep(5)
    raise RuntimeError(f"Timed out waiting for {label}: {last_error}")


def main() -> int:
    app_url = os.environ.get("LAB_APP_URL", "").strip()
    indexer_url = os.environ.get("LAB_INDEXER_URL", "").strip().rstrip("/")
    username = os.environ.get("LAB_INDEXER_USER", "admin")
    password = os.environ.get("LAB_INDEXER_PASSWORD", "")
    readiness_timeout = float(os.environ.get("LAB_READINESS_TIMEOUT", "900"))
    delivery_timeout = float(os.environ.get("LAB_DELIVERY_TIMEOUT", "300"))
    if not app_url or not indexer_url or not password:
        print("Set LAB_APP_URL, LAB_INDEXER_URL, and LAB_INDEXER_PASSWORD.", file=sys.stderr)
        return 2

    marker = build_marker()
    try:
        wait_until(
            "Juice Shop/WAF HTTP readiness",
            readiness_timeout,
            lambda: 200 <= http_request(app_url, timeout=8)[0] < 400,
        )
        wait_until(
            "authenticated Wazuh Indexer readiness",
            readiness_timeout,
            lambda: http_request(
                f"{indexer_url}/_cluster/health?wait_for_status=yellow&timeout=5s",
                timeout=8,
                username=username,
                password=password,
                insecure_tls=True,
            )[0]
            == 200,
        )

        allowed_status, _ = http_request(marker_url(app_url, marker), timeout=15)
        if not 200 <= allowed_status < 400:
            raise RuntimeError(f"Allowed WAF request returned HTTP {allowed_status}, expected 2xx/3xx")
        print("PASS: normal request allowed by WAF")

        blocked_url = f"{app_url.rstrip('/')}?{urllib.parse.urlencode({'lab_block': '1'})}"
        blocked_status, _ = http_request(blocked_url, timeout=15)
        if blocked_status != 403:
            raise RuntimeError(f"Deterministic WAF request returned HTTP {blocked_status}, expected 403")
        print("PASS: deterministic WAF rule returned HTTP 403")

        query = json.dumps(
            {
                "size": 100,
                "query": {"match_phrase": {"full_log": marker}},
                "sort": [{"@timestamp": {"order": "desc"}}],
            }
        ).encode()

        def marker_arrived() -> bool:
            status, response = http_request(
                f"{indexer_url}/wazuh-alerts-*/_search",
                timeout=12,
                method="POST",
                body=query,
                username=username,
                password=password,
                insecure_tls=True,
            )
            if status != 200:
                raise RuntimeError(f"Indexer search returned HTTP {status}: {response[:160]!r}")
            payload = json.loads(response)
            events = payload.get("hits", {}).get("hits", [])
            return any(event_contains_marker(hit, marker) for hit in events)

        wait_until("fresh request marker searchable in Wazuh alerts", delivery_timeout, marker_arrived)
        print(f"Verified marker: {marker}")
        return 0
    except Exception as error:
        print(f"VERIFICATION FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())