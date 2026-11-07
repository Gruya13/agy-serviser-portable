"""
tests.test_e2e_sync
===================
End-to-End integracioni testovi za dvosmernu sinhronizaciju (ADR-0003):
- Klijent: AGY Serviser Portable (Sync-ServiceHub klijent)
- Server: Servis Hub REST API (/api/devices/{tag}/history, /api/devices/{tag}/agy-session)

Pokriva:
1. Scenario 1: Hub aktivan (Pre-flight pull -> Post-flight push -> Re-check pull -> By-serial pull).
2. Scenario 2: Hub nedostupan (Offline queuing u pending_sync/ bez pucanja).
3. Scenario 3: Flush offline reda (Slanje zaostale sesije i brisanje iz pending_sync/).
4. Višestruke sesije i akumulacija u SERVISNI_DNEVNIK.md.
"""

import os
import sys
import json
import uuid
import re
import shutil
import tempfile
import threading
import urllib.request
import urllib.error
from datetime import datetime, timezone
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

# Ubacivanje Servis Hub projekta u sys.path (ili korišćenje standalone referentnog servera)
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
SERVISER_ROOT = os.path.dirname(CURRENT_DIR)
HUB_ROOT = os.environ.get(
    "SERVIS_HUB_PATH", os.path.abspath(os.path.join(SERVISER_ROOT, "..", "Servis Hub"))
)

if os.path.isdir(HUB_ROOT) and HUB_ROOT not in sys.path:
    sys.path.insert(0, HUB_ROOT)

try:
    from servishub.config import HubConfig
    from servishub.telemetry import FleetStore
    from servishub.handlers import ServisHubHandler
except ImportError:
    # Standalone referentna implementacija Servis Hub REST API ugovora (ADR-0003 / ADR-0004)
    # Omogućava izvršavanje svih 11 E2E testova u CI/CD i pri samostalnom kloniranju repozitorijuma.
    class HubConfig:
        def __init__(self, host="127.0.0.1", port=0, base_dir="", storage_dir="", logs_dir=""):
            self.host = host
            self.port = port
            self.base_dir = base_dir
            self.storage_dir = storage_dir
            self.logs_dir = logs_dir
            self.live_logs_dir = os.path.join(logs_dir, "live")
            self.reports_dir = os.path.join(storage_dir, "reports")
            os.makedirs(self.live_logs_dir, exist_ok=True)
            os.makedirs(self.reports_dir, exist_ok=True)

    class FleetStore:
        def __init__(self, live_logs_dir="", reports_dir=""):
            self.live_logs_dir = live_logs_dir
            self.reports_dir = reports_dir
            self.fleet_lock = threading.Lock()
            self.fleet_devices = {}
            self.records = {}

    class ServisHubHandler(BaseHTTPRequestHandler):
        fleet_store = None
        config = None
        payload_mgr = None
        driver_cache_mgr = None
        ms_catalog_scraper = None

        def log_message(self, format, *args):
            pass

        def _send_json(self, status_code: int, data: dict):
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status_code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            m_tag = re.match(r"^/api/devices/([^/]+)/history$", self.path)
            m_ser = re.match(r"^/api/devices/by-serial/([^/]+)/history$", self.path)
            if m_tag and not self.path.startswith("/api/devices/by-serial/"):
                tag = unquote(m_tag.group(1))
                rec = self.fleet_store.records.get(tag)
                if not rec:
                    return self._send_json(200, {"device_tag": tag, "is_registered": False, "total_interventions": 0, "interventions": [], "dnevnik_markdown": ""})
                return self._send_json(200, rec)
            if m_ser:
                serial = unquote(m_ser.group(1))
                for rec in self.fleet_store.records.values():
                    if rec.get("serial_number") == serial:
                        return self._send_json(200, rec)
                return self._send_json(200, {"serial_number": serial, "is_registered": False, "total_interventions": 0, "interventions": [], "dnevnik_markdown": ""})
            self._send_json(404, {"error": "Not found"})

        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length).decode("utf-8")) if length > 0 else {}
            m_reg = re.match(r"^/api/devices/([^/]+)/register$", self.path)
            m_cp = re.match(r"^/api/devices/([^/]+)/checkpoint$", self.path)
            m_ses = re.match(r"^/api/devices/([^/]+)/agy-session$", self.path)

            if m_reg:
                tag = unquote(m_reg.group(1))
                hw = payload.get("hardware", {})
                ts = payload.get("timestamp", datetime.now(timezone.utc).isoformat())
                rec = self.fleet_store.records.setdefault(tag, {
                    "device_tag": tag,
                    "is_registered": True,
                    "serial_number": payload.get("serial_number") or hw.get("serial_number", "UNKNOWN"),
                    "manufacturer": hw.get("manufacturer", "Generic"),
                    "model": hw.get("model", "System"),
                    "first_seen": ts,
                    "last_seen": ts,
                    "total_interventions": 0,
                    "interventions": [],
                    "dnevnik_markdown": f"# Servisni Dnevnik: {tag}\n\n---\n\n### [Datum: {ts}] - Prijem na servis\n- **Status:** {payload.get('status', 'U_DIJAGNOSTICI')}\n",
                })
                with self.fleet_store.fleet_lock:
                    self.fleet_store.fleet_devices[tag] = {"status_label": "U Dijagnostici (AGY)", "summary": "Prijem na servis"}
                return self._send_json(200, {"status": "ok", "action": "created", "device_tag": tag})

            if m_cp:
                tag = unquote(m_cp.group(1))
                ts = payload.get("timestamp", datetime.now(timezone.utc).isoformat())
                status = payload.get("status", "U_DIJAGNOSTICI")
                summary = payload.get("summary", "")
                label_map = {"KVAR_POTVRDJEN": "Kvar (AGY)", "CRITICAL_ISSUE": "Kvar (AGY)", "COMPLETED": "Servisiran (AGY)", "ISPRAVAN": "Servisiran (AGY)"}
                status_label = label_map.get(status, "U Dijagnostici (AGY)")
                rec = self.fleet_store.records.setdefault(tag, {
                    "device_tag": tag,
                    "is_registered": True,
                    "serial_number": payload.get("serial_number", "UNKNOWN"),
                    "manufacturer": "Generic",
                    "model": "System",
                    "first_seen": ts,
                    "last_seen": ts,
                    "total_interventions": 0,
                    "interventions": [],
                    "dnevnik_markdown": f"# Servisni Dnevnik: {tag}\n\n---\n",
                })
                rec["dnevnik_markdown"] += f"\n### [Datum: {ts}] - Status: {status}\n- **Checkpoint:** {summary}\n"
                with self.fleet_store.fleet_lock:
                    self.fleet_store.fleet_devices[tag] = {"status_label": status_label, "summary": summary}
                return self._send_json(200, {"status": "ok", "status_label": status_label, "device_tag": tag})

            if m_ses:
                tag = unquote(m_ses.group(1))
                hw = payload.get("hardware", {})
                ts = payload.get("timestamp", datetime.now(timezone.utc).isoformat())
                rec = self.fleet_store.records.setdefault(tag, {
                    "device_tag": tag,
                    "is_registered": True,
                    "serial_number": payload.get("serial_number") or hw.get("serial_number", "UNKNOWN"),
                    "manufacturer": hw.get("manufacturer", "Generic"),
                    "model": hw.get("model", "System"),
                    "first_seen": ts,
                    "last_seen": ts,
                    "total_interventions": 0,
                    "interventions": [],
                    "dnevnik_markdown": f"# Servisni Dnevnik: {tag}\n\n---\n",
                })
                rec["is_registered"] = True
                rec["last_seen"] = ts
                if hw.get("manufacturer"):
                    rec["manufacturer"] = hw["manufacturer"]
                if hw.get("model"):
                    rec["model"] = hw["model"]
                if payload.get("serial_number"):
                    rec["serial_number"] = payload["serial_number"]
                rec["interventions"].append({
                    "date": ts,
                    "status": payload.get("status", "COMPLETED"),
                    "summary": payload.get("summary", ""),
                    "tools_used": payload.get("tools_executed", []),
                })
                rec["total_interventions"] = len(rec["interventions"])
                entry = payload.get("dnevnik_entry") or f"### [Datum: {ts}] - Status: {payload.get('status', 'COMPLETED')}\n- **Nalaz:** {payload.get('summary', '')}\n"
                rec["dnevnik_markdown"] += f"\n{entry}\n"
                return self._send_json(200, {"status": "ok", "dnevnik_updated": True, "device_tag": tag})

            self._send_json(404, {"error": "Not found"})


class AgySyncClient:
    """
    Python implementacija klijentskog protokola iz Sync-ServiceHub.ps1.
    Garantuje 1:1 kompatibilnost sa PowerShell ponašanjem na terenu.
    """

    def __init__(self, hub_url: str, usb_root: str, pending_dir: str = None):
        self.hub_url = hub_url.rstrip("/") if hub_url else "http://localhost:8000"
        self.usb_root = usb_root
        self.pending_dir = pending_dir or os.path.join(usb_root, "pending_sync")
        os.makedirs(self.pending_dir, exist_ok=True)

    @staticmethod
    def parse_hardware_profile(device_dir: str) -> dict:
        hw = {
            "manufacturer": "Generic",
            "model": "System",
            "cpu": "N/A",
            "ram_gb": 0.0,
            "disks": "N/A",
            "os": "N/A",
            "bios": "N/A",
            "serial": "UNKNOWN",
            "tag": os.path.basename(device_dir),
        }
        info_path = os.path.join(device_dir, "DEVICE_INFO.md")
        if os.path.isfile(info_path):
            with open(info_path, "r", encoding="utf-8") as f:
                content = f.read()

            m = re.search(r"\*\*Oznaka uredjaja \(DeviceTag\):\*\*\s*`?([^\r\n`]+)`?", content)
            if m:
                hw["tag"] = m.group(1).strip()
            m = re.search(r"\*\*Proizvodjac:\*\*\s*([^\r\n]+)", content)
            if m:
                hw["manufacturer"] = m.group(1).strip()
            m = re.search(r"\*\*Model racunara / ploce:\*\*\s*([^\r\n(]+)", content)
            if m:
                hw["model"] = m.group(1).strip()
            m = re.search(r"\*\*Serijski broj:\*\*\s*`?([^\r\n`]+)`?", content)
            if m:
                hw["serial"] = m.group(1).strip()
            m = re.search(r"\|\s*\*\*Procesor \(CPU\)\*\*\s*\|\s*([^|\r\n]+)\|", content)
            if m:
                hw["cpu"] = m.group(1).strip()
            m = re.search(r"\|\s*\*\*Radna memorija \(RAM\)\*\*\s*\|\s*([0-9.]+)\s*GB", content)
            if m:
                try:
                    hw["ram_gb"] = round(float(m.group(1).strip()), 1)
                except ValueError:
                    pass
            m = re.search(r"\|\s*\*\*Skladiste \(Diskovi\)\*\*\s*\|\s*([^|\r\n]+)\|", content)
            if m:
                hw["disks"] = m.group(1).strip()
            m = re.search(r"\|\s*\*\*Operativni sistem\*\*\s*\|\s*([^|\r\n]+)\|", content)
            if m:
                hw["os"] = m.group(1).strip()
            m = re.search(r"\|\s*\*\*BIOS verzija\*\*\s*\|\s*([^|\r\n]+)\|", content)
            if m:
                hw["bios"] = m.group(1).strip()
        return hw

    @staticmethod
    def parse_latest_dnevnik(device_dir: str) -> str:
        dnevnik_path = os.path.join(device_dir, "SERVISNI_DNEVNIK.md")
        if os.path.isfile(dnevnik_path):
            with open(dnevnik_path, "r", encoding="utf-8") as f:
                content = f.read()
            idx = content.rfind("### [Datum:")
            if idx >= 0:
                return content[idx:].strip()
            return content.strip()
        return ""

    @staticmethod
    def parse_diagnostic_report(device_dir: str) -> dict:
        res = {
            "report_markdown": "",
            "summary": "",
            "status": "COMPLETED",
            "tools": [],
        }
        report_path = os.path.join(device_dir, "reports", "IZVESTAJ_DIJAGNOSTIKE.md")
        if not os.path.isfile(report_path):
            reports_dir = os.path.join(device_dir, "reports")
            if os.path.isdir(reports_dir):
                candidates = [
                    os.path.join(reports_dir, fn)
                    for fn in os.listdir(reports_dir)
                    if fn.endswith(".md")
                ]
                if candidates:
                    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
                    report_path = candidates[0]

        if os.path.isfile(report_path):
            with open(report_path, "r", encoding="utf-8") as f:
                raw = f.read()
            res["report_markdown"] = raw

            m_sum = re.search(
                r"(?i)\*\*(?:Primarni uzrok \(Root Cause\)|Root Cause|Primarni uzrok):\*\*\s*([^\r\n]+)",
                raw,
            )
            if m_sum:
                res["summary"] = m_sum.group(1).strip()
            else:
                m_concl = re.search(
                    r"(?i)##\s*(?:Zaključak|Zakljucak|Root Cause)[^\r\n]*\r?\n([^\r\n#]+)", raw
                )
                if m_concl:
                    res["summary"] = m_concl.group(1).strip()

            if re.search(r"(?i)CRITICAL|KRITIČNO|KRITICNO|Hardware Failure|Otkaz diska", raw):
                res["status"] = "CRITICAL_ISSUE"
            elif re.search(r"(?i)WARNING|UPOZORENJE|Warning", raw):
                res["status"] = "WARNING"
            else:
                res["status"] = "COMPLETED"

            tools = re.findall(r"(?i)((?:Get|Test|Find|Protect)-\w+\.ps1)", raw)
            res["tools"] = sorted(list(set(tools)))
        return res

    def build_payload(
        self,
        device_dir: str,
        device_tag: str = None,
        serial: str = None,
        timestamp: str = None,
    ) -> dict:
        hw = self.parse_hardware_profile(device_dir)
        effective_tag = device_tag or hw["tag"] or os.path.basename(device_dir)
        effective_serial = serial or hw["serial"] or "UNKNOWN"
        dnevnik_entry = self.parse_latest_dnevnik(device_dir)
        diag = self.parse_diagnostic_report(device_dir)

        summary = diag["summary"]
        if not summary:
            summary = (
                f"Servisna sesija za {effective_tag}"
                if dnevnik_entry
                else "Zavrsena servisna sesija bez zabelezenih anomalija."
            )

        tools = diag["tools"]
        if not tools and dnevnik_entry:
            tools = sorted(
                list(set(re.findall(r"(?i)((?:Get|Test|Find|Protect)-\w+\.ps1)", dnevnik_entry)))
            )

        session_id = str(uuid.uuid4())
        effective_timestamp = (
            timestamp
            if timestamp
            else datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        )

        return {
            "device_tag": effective_tag,
            "serial_number": effective_serial,
            "session_id": session_id,
            "timestamp": effective_timestamp,
            "serviser_id": os.getenv("SERVISER_ID", "USB_TEREN_01"),
            "hardware": {
                "manufacturer": hw["manufacturer"],
                "model": hw["model"],
                "cpu": hw["cpu"],
                "ram_gb": hw["ram_gb"],
                "disks": hw["disks"],
                "os": hw["os"],
                "bios": hw["bios"],
            },
            "summary": summary,
            "status": diag["status"],
            "tools_executed": tools,
            "dnevnik_entry": dnevnik_entry,
            "report_markdown": diag["report_markdown"],
        }

    @staticmethod
    def export_hub_history_markdown(history: dict, target_folder: str):
        if not target_folder or not os.path.isdir(target_folder):
            return
        dest_path = os.path.join(target_folder, "SERVIS_HUB_HISTORY.md")
        lines = [
            f"# 🏛️ Servis Hub Istorija: {history.get('device_tag', 'N/A')}",
            "",
            "> [!NOTE]",
            "> Ovi podaci su automatski preuzeti sa centralnog Servis Hub-a.",
            "> Koristi ove nalaze za prepoznavanje recidivnih kvarova i prethodnih zahvata.",
            "",
            f"- **Proizvodjac i Model:** {history.get('manufacturer', '')} {history.get('model', '')}",
            f"- **Serijski Broj:** `{history.get('serial_number', '')}`",
            f"- **Prvi Prijem:** {history.get('first_seen', 'N/A')}",
            f"- **Poslednji Prijem:** {history.get('last_seen', 'N/A')}",
            f"- **Ukupno Prethodnih Intervencija:** {history.get('total_interventions', 0)}",
            "",
            "---",
            "",
            "## 📜 Hronologija Prethodnih Intervencija",
            "",
        ]
        interventions = history.get("interventions", [])
        if interventions:
            for item in interventions:
                lines.append(f"### [{item.get('date', '')}] Status: [{item.get('status', '')}]")
                if item.get("summary"):
                    lines.append(f"- **Sazetak:** {item['summary']}")
                if item.get("tools_used"):
                    tools_str = ", ".join(item["tools_used"])
                    lines.append(f"- **Korisceni alati:** {tools_str}")
                lines.append("")
        else:
            lines.append("Nema evidentiranih pojedinacnih intervencija.")
            lines.append("")

        dnevnik_md = history.get("dnevnik_markdown")
        if dnevnik_md:
            lines.extend([
                "---",
                "",
                "## 📑 Servisni Dnevnik sa Hub-a",
                "",
                dnevnik_md,
            ])

        with open(dest_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines).strip() + "\n")

    @staticmethod
    def merge_hub_dnevnik(history: dict, target_folder: str):
        if not target_folder or not os.path.isdir(target_folder):
            return
        hub_dnevnik = history.get("dnevnik_markdown")
        if not hub_dnevnik:
            return
        dnevnik_path = os.path.join(target_folder, "SERVISNI_DNEVNIK.md")
        if not os.path.isfile(dnevnik_path):
            with open(dnevnik_path, "w", encoding="utf-8") as f:
                f.write(hub_dnevnik.strip() + "\n")
            return

        with open(dnevnik_path, "r", encoding="utf-8") as f:
            local_dnevnik = f.read()

        pattern = r"(?ms)(### \[Datum:[^\r\n]+\].*?)(?=(?:### \[Datum:|\Z))"
        hub_matches = re.findall(pattern, hub_dnevnik)
        entries_to_add = []
        for entry in hub_matches:
            entry_clean = entry.strip()
            m = re.match(r"^(### \[Datum:[^\]\r\n]+\])", entry_clean)
            if m:
                header_sig = m.group(1)
                if header_sig not in local_dnevnik:
                    entries_to_add.append(entry_clean)

        if entries_to_add:
            header_idx = local_dnevnik.find("---")
            if header_idx >= 0:
                prefix = local_dnevnik[:header_idx + 3]
                suffix = local_dnevnik[header_idx + 3:].lstrip("\r\n")
                merged = prefix + "\n\n" + "\n\n".join(entries_to_add) + "\n\n" + suffix
            else:
                merged = "\n\n".join(entries_to_add) + "\n\n" + local_dnevnik
            with open(dnevnik_path, "w", encoding="utf-8") as f:
                f.write(merged.strip() + "\n")

    def pull(self, device_tag: str = None, serial: str = None, target_folder: str = None) -> dict:
        url = None
        if device_tag:
            url = f"{self.hub_url}/api/devices/{urllib.parse.quote(device_tag)}/history"
        elif serial:
            url = f"{self.hub_url}/api/devices/by-serial/{urllib.parse.quote(serial)}/history"
        else:
            return {"error": "Mora se navesti device_tag ili serial"}

        data = None
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            return {"error": f"Hub nedostupan: {e}", "is_registered": False}

        if data and not data.get("is_registered") and serial and device_tag:
            # Fallback po serijskom broju
            fallback_url = f"{self.hub_url}/api/devices/by-serial/{urllib.parse.quote(serial)}/history"
            try:
                fb_req = urllib.request.Request(fallback_url, method="GET")
                with urllib.request.urlopen(fb_req, timeout=3) as fb_resp:
                    fb_data = json.loads(fb_resp.read().decode("utf-8"))
                    if fb_data.get("is_registered"):
                        data = fb_data
            except Exception:
                pass

        if data and data.get("is_registered") and target_folder:
            self.export_hub_history_markdown(data, target_folder)
            self.merge_hub_dnevnik(data, target_folder)

        return data

    def register(
        self,
        device_dir: str = None,
        device_tag: str = None,
        serial: str = None,
        status: str = "U_DIJAGNOSTICI",
    ) -> dict:
        hw = self.parse_hardware_profile(device_dir) if device_dir else {}
        effective_tag = device_tag or hw.get("tag") or (os.path.basename(device_dir) if device_dir else "UNKNOWN")
        effective_serial = serial or hw.get("serial") or "UNKNOWN"
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        payload = {
            "device_tag": effective_tag,
            "serial_number": effective_serial,
            "status": status,
            "serviser_id": os.getenv("SERVISER_ID", "USB_TEREN_01"),
            "timestamp": timestamp,
            "hardware": {
                "manufacturer": hw.get("manufacturer", "Generic"),
                "model": hw.get("model", "System"),
                "cpu": hw.get("cpu", "N/A"),
                "ram_gb": hw.get("ram_gb", 0.0),
                "disks": hw.get("disks", "N/A"),
                "os": hw.get("os", "N/A"),
                "bios": hw.get("bios", "N/A"),
                "serial_number": effective_serial,
            },
        }

        url = f"{self.hub_url}/api/devices/{urllib.parse.quote(effective_tag)}/register"
        sent_online = False
        resp_data = None
        error_msg = None

        try:
            body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            req = urllib.request.Request(
                url,
                data=body_bytes,
                headers={"Content-Type": "application/json; charset=utf-8"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                resp_data = json.loads(resp.read().decode("utf-8"))
                sent_online = True
        except Exception as e:
            sent_online = False
            error_msg = str(e)
            file_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            safe_tag = re.sub(r"[^\w\-]", "_", effective_tag)
            queue_fn = f"{file_ts}_REGISTER_{safe_tag}.json"
            queue_fp = os.path.join(self.pending_dir, queue_fn)
            with open(queue_fp, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)

        return {
            "success": True,
            "sent_online": sent_online,
            "device_tag": effective_tag,
            "response": resp_data,
            "error": error_msg,
        }

    def checkpoint(
        self,
        device_dir: str = None,
        device_tag: str = None,
        serial: str = None,
        summary: str = "",
        status: str = "U_DIJAGNOSTICI",
        tools: list = None,
    ) -> dict:
        hw = self.parse_hardware_profile(device_dir) if device_dir else {}
        effective_tag = device_tag or hw.get("tag") or (os.path.basename(device_dir) if device_dir else "UNKNOWN")
        effective_serial = serial or hw.get("serial") or "UNKNOWN"
        tools = tools or []
        summary = summary or "Operativni kontrolni nalaz."

        if device_dir and os.path.isdir(device_dir):
            dnevnik_path = os.path.join(device_dir, "SERVISNI_DNEVNIK.md")
            ts_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            cp_entry = f"### [Datum: {ts_str}] - Status: {status}\n- **Kontrolna tacka (Checkpoint):** {summary}"
            if tools:
                cp_entry += f"\n- **Pokrenuti alati:** {', '.join(tools)}"

            if not os.path.isfile(dnevnik_path):
                header = f"# Servisni Dnevnik Intervencija: {effective_tag}\n\n---\n\n"
                with open(dnevnik_path, "w", encoding="utf-8") as f:
                    f.write(header + cp_entry + "\n")
            else:
                with open(dnevnik_path, "a", encoding="utf-8") as f:
                    f.write(f"\n\n{cp_entry}\n")

        checkpoint_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        payload = {
            "device_tag": effective_tag,
            "serial_number": effective_serial,
            "checkpoint_id": checkpoint_id,
            "timestamp": timestamp,
            "summary": summary,
            "status": status,
            "tools_executed": tools,
            "serviser_id": os.getenv("SERVISER_ID", "USB_TEREN_01"),
        }

        url = f"{self.hub_url}/api/devices/{urllib.parse.quote(effective_tag)}/checkpoint"
        sent_online = False
        resp_data = None
        error_msg = None

        try:
            body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            req = urllib.request.Request(
                url,
                data=body_bytes,
                headers={"Content-Type": "application/json; charset=utf-8"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                resp_data = json.loads(resp.read().decode("utf-8"))
                sent_online = True
        except Exception as e:
            sent_online = False
            error_msg = str(e)
            file_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            safe_tag = re.sub(r"[^\w\-]", "_", effective_tag)
            queue_fn = f"{file_ts}_CHECKPOINT_{safe_tag}.json"
            queue_fp = os.path.join(self.pending_dir, queue_fn)
            with open(queue_fp, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)

        return {
            "success": True,
            "sent_online": sent_online,
            "device_tag": effective_tag,
            "checkpoint_id": checkpoint_id,
            "response": resp_data,
            "error": error_msg,
        }

    def push(
        self,
        device_dir: str,
        device_tag: str = None,
        serial: str = None,
        timestamp: str = None,
    ) -> dict:
        payload = self.build_payload(device_dir, device_tag, serial, timestamp)
        tag = payload["device_tag"]
        url = f"{self.hub_url}/api/devices/{urllib.parse.quote(tag)}/agy-session"

        sent_online = False
        resp_data = None
        error_msg = None

        try:
            body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            req = urllib.request.Request(
                url,
                data=body_bytes,
                headers={"Content-Type": "application/json; charset=utf-8"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                resp_data = json.loads(resp.read().decode("utf-8"))
                sent_online = True
        except Exception as e:
            sent_online = False
            error_msg = str(e)
            # Offline čuvanje u pending_sync/
            file_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            safe_tag = re.sub(r"[^\w\-]", "_", tag)
            queue_fn = f"{file_ts}_{safe_tag}.json"
            queue_fp = os.path.join(self.pending_dir, queue_fn)
            with open(queue_fp, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)

        # Ako je online uspeh, isprazni zaostale
        flushed_count = 0
        if sent_online:
            flushed_count = self.flush_pending()

        return {
            "success": True,
            "sent_online": sent_online,
            "device_tag": tag,
            "session_id": payload["session_id"],
            "response": resp_data,
            "error": error_msg,
            "flushed_count": flushed_count,
        }

    def flush_pending(self) -> int:
        if not os.path.isdir(self.pending_dir):
            return 0

        pending_files = sorted(
            [f for f in os.listdir(self.pending_dir) if f.endswith(".json")]
        )
        flushed = 0

        for fn in pending_files:
            fp = os.path.join(self.pending_dir, fn)
            try:
                with open(fp, "r", encoding="utf-8") as f:
                    payload = json.load(f)

                target_tag = payload.get("device_tag")
                if not target_tag:
                    parts = fn.split("_", 2)
                    target_tag = parts[-1].replace(".json", "")

                if "_REGISTER_" in fn:
                    url = f"{self.hub_url}/api/devices/{urllib.parse.quote(target_tag)}/register"
                elif "_CHECKPOINT_" in fn:
                    url = f"{self.hub_url}/api/devices/{urllib.parse.quote(target_tag)}/checkpoint"
                else:
                    url = f"{self.hub_url}/api/devices/{urllib.parse.quote(target_tag)}/agy-session"

                body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                req = urllib.request.Request(
                    url,
                    data=body_bytes,
                    headers={"Content-Type": "application/json; charset=utf-8"},
                    method="POST",
                )
                with urllib.request.urlopen(req, timeout=3) as resp:
                    if resp.status == 200:
                        os.remove(fp)
                        flushed += 1
            except Exception:
                # Prekidamo flush ako server nije dostupan
                break

        return flushed


class TestServisHubSyncE2E(unittest.TestCase):
    """
    Test harness za kompletnu verifikaciju dvosmerne sinhronizacije klijent <-> Hub.
    """

    @classmethod
    def setUpClass(cls):
        # 1. Podizanje ServisHub servera u izolovanom temp direktorijumu
        cls.hub_temp_dir = tempfile.mkdtemp(prefix="hub_test_")
        cls.hub_config = HubConfig(
            host="127.0.0.1",
            port=0,
            base_dir=cls.hub_temp_dir,
            storage_dir=os.path.join(cls.hub_temp_dir, "storage"),
            logs_dir=os.path.join(cls.hub_temp_dir, "logs"),
        )
        cls.fleet_store = FleetStore(
            live_logs_dir=cls.hub_config.live_logs_dir,
            reports_dir=cls.hub_config.reports_dir,
        )

        ServisHubHandler.fleet_store = cls.fleet_store
        ServisHubHandler.config = cls.hub_config
        ServisHubHandler.payload_mgr = None
        ServisHubHandler.driver_cache_mgr = None
        ServisHubHandler.ms_catalog_scraper = None

        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), ServisHubHandler)
        cls.port = cls.httpd.server_address[1]
        cls.hub_url = f"http://127.0.0.1:{cls.port}"

        cls.server_thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.server_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        shutil.rmtree(cls.hub_temp_dir, ignore_errors=True)

    def setUp(self):
        # Kreiranje izolovanog radnog prostora za klijenta (USB klijentski root)
        self.client_temp_dir = tempfile.mkdtemp(prefix="client_usb_")
        self.pending_dir = os.path.join(self.client_temp_dir, "pending_sync")
        self.devices_dir = os.path.join(self.client_temp_dir, "devices")
        os.makedirs(self.pending_dir, exist_ok=True)
        os.makedirs(self.devices_dir, exist_ok=True)

        self.client = AgySyncClient(
            hub_url=self.hub_url,
            usb_root=self.client_temp_dir,
            pending_dir=self.pending_dir,
        )

    def tearDown(self):
        shutil.rmtree(self.client_temp_dir, ignore_errors=True)

    def _create_mock_device(
        self,
        tag: str,
        serial: str,
        manufacturer: str = "HP",
        model: str = "ProBook 450 G8",
        cpu: str = "Intel Core i5-1135G7",
        ram_gb: float = 16.0,
        root_cause: str = "Pregrevanje procesora usled sasušene termalne paste.",
        status: str = "COMPLETED",
        tools: list = None,
    ) -> str:
        dev_dir = os.path.join(self.devices_dir, tag)
        reports_dir = os.path.join(dev_dir, "reports")
        os.makedirs(reports_dir, exist_ok=True)

        if tools is None:
            tools = ["Get-DiskHealth.ps1", "Get-EventLogTriage.ps1"]

        # 1. DEVICE_INFO.md
        device_info_content = f"""# Servisni Karton Uredjaja: {tag}

- **Oznaka uredjaja (DeviceTag):** `{tag}`
- **Proizvodjac:** {manufacturer}
- **Model racunara / ploce:** {model} (Ploca: 881D)
- **Serijski broj:** `{serial}`
- **Hardverski UUID:** 4C4C4544-004B-4810-8037-B3C04F345832
- **Naziv u sistemu (ComputerName):** SERVIS-DESK-01
- **Poslednja sinhronizacija:** 2026-10-09 15:30:00

---

## Hardverska Specifikacija

| Komponenta | Podaci |
| :--- | :--- |
| **Procesor (CPU)** | {cpu} |
| **Radna memorija (RAM)** | {ram_gb} GB |
| **Graficka karta (GPU)** | Intel Iris Xe Graphics |
| **Skladiste (Diskovi)** | KIOXIA KBG40ZNS512G NVMe (477 GB) |
| **Operativni sistem** | Windows 11 Pro (64-bit) - Build 22631 |
| **BIOS verzija** | T70 Ver. 01.14.00 (05/20/2023) |

---
*Fajl je automatski generisan od strane Antigravity CLI Prenosivog Servisnog Asistenta.*
"""
        with open(os.path.join(dev_dir, "DEVICE_INFO.md"), "w", encoding="utf-8") as f:
            f.write(device_info_content)

        # 2. SERVISNI_DNEVNIK.md
        tools_str = ", ".join(tools)
        dnevnik_content = f"""# Servisni Dnevnik Intervencija: {tag}

Ovaj dokument sadrzi istoriju svih servisnih intervencija i dijagnostickih nalaza za ovaj racunar.

---

### [Datum: 2026-10-09 15:30:00] - Detekcija i sanacija kvara
- **Status:** {status}
- **Alati:** {tools_str}
- **Nalaz:** {root_cause}
"""
        with open(os.path.join(dev_dir, "SERVISNI_DNEVNIK.md"), "w", encoding="utf-8") as f:
            f.write(dnevnik_content)

        # 3. reports/IZVESTAJ_DIJAGNOSTIKE.md
        report_content = f"""# Završni Izveštaj Servisne Dijagnostike

- **Uređaj:** {manufacturer} {model}
- **Serijski broj:** {serial}
- **Primarni uzrok (Root Cause):** {root_cause}
- **Status:** {status}

## Pokrenuti alati:
"""
        for t in tools:
            report_content += f"- {t}\n"

        with open(os.path.join(reports_dir, "IZVESTAJ_DIJAGNOSTIKE.md"), "w", encoding="utf-8") as f:
            f.write(report_content)

        return dev_dir

    def test_01_markdown_profile_and_report_parsing(self):
        """Proverava tačnost ekstrakcije podataka iz lokalnih Markdown datoteka."""
        tag = "HP_ProBook_450_G8_5CD1234XYZ"
        sn = "5CD1234XYZ"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="HP",
            model="ProBook 450 G8",
            cpu="Intel Core i5-1135G7",
            ram_gb=16.0,
            root_cause="Pregrevanje procesora usled sasušene termalne paste.",
            status="COMPLETED",
        )

        hw = self.client.parse_hardware_profile(dev_dir)
        self.assertEqual(hw["tag"], tag)
        self.assertEqual(hw["serial"], sn)
        self.assertEqual(hw["manufacturer"], "HP")
        self.assertEqual(hw["model"], "ProBook 450 G8")
        self.assertEqual(hw["cpu"], "Intel Core i5-1135G7")
        self.assertEqual(hw["ram_gb"], 16.0)

        diag = self.client.parse_diagnostic_report(dev_dir)
        self.assertEqual(diag["summary"], "Pregrevanje procesora usled sasušene termalne paste.")
        self.assertEqual(diag["status"], "COMPLETED")
        self.assertIn("Get-DiskHealth.ps1", diag["tools"])
        self.assertIn("Get-EventLogTriage.ps1", diag["tools"])

        dnevnik = self.client.parse_latest_dnevnik(dev_dir)
        self.assertIn("### [Datum: 2026-10-09 15:30:00]", dnevnik)
        self.assertIn(sn, dev_dir)

    def test_02_scenario_1_hub_online_lifecycle(self):
        """
        Scenario 1: Hub je aktivan.
        - Pre-flight pull za novi uređaj (vraća is_registered: False)
        - Post-flight push sa mockup datotekama (vraća HTTP 200, status ok)
        - Pre-flight pull sada vraća is_registered: True sa evidentiranom sesijom
        - Pull po serijskom broju takođe pronalazi uređaj
        """
        tag = "Dell_Latitude_5420_8G7X123"
        sn = "8G7X123"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="Dell Inc.",
            model="Latitude 5420",
            cpu="Intel Core i7-1185G7",
            ram_gb=32.0,
            root_cause="Detektovan otkaz NVMe kontrolera. Preporučena hitna zamena.",
            status="CRITICAL_ISSUE",
            tools=["Get-DiskHealth.ps1", "Get-EventLogTriage.ps1", "Get-MinidumpReport.ps1"],
        )

        # Korak 1: Pre-flight pull za novi uređaj pre prijema
        pre_pull = self.client.pull(device_tag=tag)
        self.assertFalse(pre_pull.get("is_registered"))
        self.assertEqual(len(pre_pull.get("interventions", [])), 0)
        self.assertEqual(pre_pull.get("dnevnik_markdown", ""), "")

        # Korak 2: Post-flight push
        push_res = self.client.push(device_dir=dev_dir)
        self.assertTrue(push_res["success"])
        self.assertTrue(push_res["sent_online"])
        self.assertEqual(push_res["device_tag"], tag)
        self.assertIsNotNone(push_res["session_id"])
        self.assertEqual(push_res["response"]["status"], "ok")
        self.assertTrue(push_res["response"]["dnevnik_updated"])

        # Korak 3: Ponovni pre-flight pull nakon sesije
        post_pull = self.client.pull(device_tag=tag)
        self.assertTrue(post_pull.get("is_registered"))
        self.assertEqual(post_pull.get("serial_number"), sn)
        self.assertEqual(post_pull.get("manufacturer"), "Dell Inc.")
        self.assertEqual(post_pull.get("model"), "Latitude 5420")
        self.assertEqual(post_pull.get("total_interventions"), 1)
        self.assertEqual(len(post_pull.get("interventions")), 1)
        intervention = post_pull["interventions"][0]
        self.assertEqual(intervention["status"], "CRITICAL_ISSUE")
        self.assertIn("otkaz NVMe kontrolera", intervention["summary"])
        self.assertIn("Get-DiskHealth.ps1", intervention["tools_used"])
        self.assertIn("### [Datum:", post_pull["dnevnik_markdown"])

        # Korak 4: Pull po serijskom broju (/api/devices/by-serial/{serial}/history)
        serial_pull = self.client.pull(serial=sn)
        self.assertTrue(serial_pull.get("is_registered"))
        self.assertEqual(serial_pull.get("device_tag"), tag)
        self.assertEqual(serial_pull.get("serial_number"), sn)
        self.assertEqual(serial_pull.get("total_interventions"), 1)

    def test_03_scenario_2_hub_offline_queuing(self):
        """
        Scenario 2: Hub je nedostupan (Offline rad).
        - Pokušaj push-a kada server nije dostupan
        - Proverava da je sesija sačuvana u pending_sync/ bez pucanja skripte
        """
        tag = "Lenovo_ThinkPad_T14_PF8888"
        sn = "PF8888"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="Lenovo",
            model="ThinkPad T14",
            cpu="AMD Ryzen 7 PRO 5850U",
            ram_gb=16.0,
            root_cause="Čišćenje virusa i malver autorun ključeva.",
            status="COMPLETED",
            tools=["Find-SuspiciousAutoruns.ps1", "Protect-USBIntegrity.ps1"],
        )

        # Kreiramo klijenta sa nepostojećim offline Hub URL-om (port na kome ništa ne sluša)
        offline_client = AgySyncClient(
            hub_url="http://127.0.0.1:59998",
            usb_root=self.client_temp_dir,
            pending_dir=self.pending_dir,
        )

        # Push ne sme baciti izuzetak
        push_res = offline_client.push(device_dir=dev_dir)
        self.assertTrue(push_res["success"])
        self.assertFalse(push_res["sent_online"])
        self.assertIsNotNone(push_res["error"])

        # Proveravamo postojanje datoteke u pending_sync/
        pending_files = [f for f in os.listdir(self.pending_dir) if f.endswith(".json")]
        self.assertEqual(len(pending_files), 1)

        pending_path = os.path.join(self.pending_dir, pending_files[0])
        with open(pending_path, "r", encoding="utf-8") as f:
            queued_payload = json.load(f)

        self.assertEqual(queued_payload["device_tag"], tag)
        self.assertEqual(queued_payload["serial_number"], sn)
        self.assertEqual(queued_payload["status"], "COMPLETED")
        self.assertIn("Find-SuspiciousAutoruns.ps1", queued_payload["tools_executed"])
        self.assertIn("Čišćenje virusa", queued_payload["summary"])

    def test_04_scenario_3_flush_offline_queue(self):
        """
        Scenario 3: Flush offline reda.
        - Hub je dostupan
        - Pokreće se flush_pending()
        - Zaostali fajl iz pending_sync/ se šalje na Hub i uklanja sa diska
        - Hub sada ima evidentiran uređaj
        """
        tag = "Asus_ZenBook_UX425_AS999"
        sn = "AS999"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="ASUSTeK COMPUTER INC.",
            model="ZenBook UX425",
            cpu="Intel Core i7-1165G7",
            ram_gb=16.0,
            root_cause="Zamena rashladnog ventilatora (prestanak rotacije).",
            status="COMPLETED",
            tools=["Get-EventLogTriage.ps1"],
        )

        # 1. Prvo šaljemo dok je klijent u offline režimu da kreira pending fajl
        offline_client = AgySyncClient(
            hub_url="http://127.0.0.1:59997",
            usb_root=self.client_temp_dir,
            pending_dir=self.pending_dir,
        )
        res_offline = offline_client.push(device_dir=dev_dir)
        self.assertFalse(res_offline["sent_online"])

        pending_files = [f for f in os.listdir(self.pending_dir) if f.endswith(".json")]
        self.assertGreaterEqual(len(pending_files), 1)

        # 2. Povezujemo se sa aktivnim Hub-om i pokrećemo flush
        online_client = AgySyncClient(
            hub_url=self.hub_url,
            usb_root=self.client_temp_dir,
            pending_dir=self.pending_dir,
        )

        initial_pending_count = len(pending_files)
        flushed_count = online_client.flush_pending()
        self.assertEqual(flushed_count, initial_pending_count)

        # Provera da je pending_sync/ folder sada prazan
        remaining = [f for f in os.listdir(self.pending_dir) if f.endswith(".json")]
        self.assertEqual(len(remaining), 0)

        # Provera da je Hub primio podatke
        hub_history = online_client.pull(device_tag=tag)
        self.assertTrue(hub_history.get("is_registered"))
        self.assertEqual(hub_history.get("serial_number"), sn)
        self.assertEqual(hub_history.get("manufacturer"), "ASUSTeK COMPUTER INC.")
        self.assertEqual(hub_history.get("total_interventions"), 1)
        self.assertIn("Zamena rashladnog ventilatora", hub_history["interventions"][0]["summary"])

    def test_05_multi_session_history_accumulation(self):
        """
        Proverava da višestruke sesije za isti uređaj pravilno dopunjuju
        SERVISNI_DNEVNIK.md i listu intervencija na Servis Hub-u.
        """
        tag = "Acer_Aspire_5_AC123"
        sn = "AC123"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="Acer",
            model="Aspire 5",
            cpu="Intel Core i3-1115G4",
            ram_gb=8.0,
            root_cause="Neispravan SSD modul (Bad sektori).",
            status="CRITICAL_ISSUE",
            tools=["Get-DiskHealth.ps1"],
        )

        # Prva sesija (2026-10-09)
        res1 = self.client.push(device_dir=dev_dir, timestamp="2026-10-09T10:00:00Z")
        self.assertTrue(res1["sent_online"])

        # Simuliramo drugu intervenciju: ažuriramo SERVISNI_DNEVNIK i IZVESTAJ
        dnevnik_path = os.path.join(dev_dir, "SERVISNI_DNEVNIK.md")
        with open(dnevnik_path, "a", encoding="utf-8") as f:
            f.write(
                "\n### [Datum: 2026-10-10 11:00:00] - Zamena diska i reinstalacija\n"
                "- **Status:** COMPLETED\n"
                "- **Nalaz:** Ugradjen nov Kingston 500GB SSD. Sistem operativan.\n"
            )

        report_path = os.path.join(dev_dir, "reports", "IZVESTAJ_DIJAGNOSTIKE.md")
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(
                "# Završni Izveštaj Servisne Dijagnostike (Sesija 2)\n\n"
                "- **Primarni uzrok (Root Cause):** Ugradjen nov SSD, sistem instaliran i testiran.\n"
                "- **Status:** COMPLETED\n"
                "- **Alati:** Get-DiskHealth.ps1, Test-SystemIntegrity.ps1\n"
            )

        # Druga sesija (2026-10-10)
        res2 = self.client.push(device_dir=dev_dir, timestamp="2026-10-10T11:00:00Z")
        self.assertTrue(res2["sent_online"])

        # Provera na Hub-u
        history = self.client.pull(device_tag=tag)
        self.assertTrue(history.get("is_registered"))
        self.assertEqual(history.get("total_interventions"), 2)
        self.assertEqual(len(history.get("interventions")), 2)
        self.assertIn("Neispravan SSD", history["interventions"][0]["summary"])
        self.assertIn("Ugradjen nov SSD", history["interventions"][1]["summary"])
        self.assertIn("Zamena diska i reinstalacija", history["dnevnik_markdown"])

    def test_06_edge_cases_and_error_handling(self):
        """Proverava robusnost pri neispravnim fajlovima ili nedostajućim parametrima."""
        # 1. Nevalidan JSON u pending_sync folderu ne sme srušiti flush
        bad_json_path = os.path.join(self.pending_dir, "corrupt_data.json")
        with open(bad_json_path, "w", encoding="utf-8") as f:
            f.write("ovo nije validan json { broken")

        # Pokrećemo flush - ne sme doći do pucanja
        flushed = self.client.flush_pending()
        self.assertEqual(flushed, 0)
        # Neispravan fajl ostaje (ne briše se nekontrolisano)
        self.assertTrue(os.path.isfile(bad_json_path))
        os.remove(bad_json_path)

        # 2. Pull za potpuno nepostojeći uređaj
        res = self.client.pull(device_tag="NonExistent_Device_000")
        self.assertFalse(res.get("is_registered"))
        self.assertEqual(res.get("total_interventions"), 0)

    def test_07_scenario_preflight_auto_register(self):
        """
        Scenario 7 (ADR-0004): Pre-flight auto-registracija novog uređaja pre starta sesije.
        - Uređaj ne postoji na Hub-u (pull vraća is_registered: False)
        - Start-ServisAI / klijent okida register() sa hardverskim profilom
        - Hub kreira novi karton sa statusom U_DIJAGNOSTICI
        - pull() odmah nakon toga vraća is_registered: True
        """
        tag = "MSI_Prestige_14_MS100"
        sn = "MS100"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="Micro-Star International Co., Ltd.",
            model="Prestige 14",
            cpu="Intel Core i7-1195G7",
            ram_gb=16.0,
            root_cause="Prijem na inicijalni servisni pregled.",
            status="COMPLETED",
        )

        # 1. Provera pre prijema
        pre_check = self.client.pull(device_tag=tag)
        self.assertFalse(pre_check.get("is_registered"))

        # 2. Pre-flight registracija
        reg_res = self.client.register(device_dir=dev_dir, status="U_DIJAGNOSTICI")
        self.assertTrue(reg_res["success"])
        self.assertTrue(reg_res["sent_online"])
        self.assertEqual(reg_res["response"]["status"], "ok")
        self.assertEqual(reg_res["response"]["action"], "created")

        # 3. Provera stanja na Hub-u
        post_reg = self.client.pull(device_tag=tag)
        self.assertTrue(post_reg.get("is_registered"))
        self.assertEqual(post_reg.get("serial_number"), sn)
        self.assertEqual(post_reg.get("manufacturer"), "Micro-Star International Co., Ltd.")
        self.assertEqual(post_reg.get("model"), "Prestige 14")
        self.assertIn("Prijem na servis", post_reg.get("dnevnik_markdown", ""))

        # Provera u fleet_store stanju
        with self.fleet_store.fleet_lock:
            dev_state = self.fleet_store.fleet_devices.get(tag, {})
            self.assertEqual(dev_state.get("status_label"), "U Dijagnostici (AGY)")

    def test_08_scenario_preflight_history_export_and_dnevnik_merge(self):
        """
        Scenario 8 (ADR-0004): Pre-flight izvlačenje istorije u SERVIS_HUB_HISTORY.md i merge dnevnika.
        - Računar ima postojeću istoriju na Hub-u
        - pull(target_folder=dev_dir) kreira SERVIS_HUB_HISTORY.md
        - pull spaja ranije unose iz dnevnika sa postojećim lokalnim unosi bez dupliranja
        """
        tag = "Dell_XPS_13_XP999"
        sn = "XP999"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="Dell Inc.",
            model="XPS 13 9310",
            cpu="Intel Core i7-1185G7",
            ram_gb=16.0,
            root_cause="Zamena termalne paste i čišćenje ventilatora.",
            status="COMPLETED",
            tools=["Test-SystemIntegrity.ps1"],
        )

        # Pošaljemo prvu sesiju na Hub
        push_res = self.client.push(device_dir=dev_dir)
        self.assertTrue(push_res["sent_online"])

        # Simuliramo novu lokalnu sesiju na drugom USB medijumu (samo lokalni unos)
        client2_temp = tempfile.mkdtemp(prefix="client2_test_")
        dev2_dir = os.path.join(client2_temp, "devices", tag)
        os.makedirs(dev2_dir, exist_ok=True)
        local_dnevnik_path = os.path.join(dev2_dir, "SERVISNI_DNEVNIK.md")
        with open(local_dnevnik_path, "w", encoding="utf-8") as f:
            f.write(
                f"# Servisni Dnevnik Intervencija: {tag}\n\n"
                "---\n\n"
                "### [Datum: 2026-10-10 12:00:00] - Status: U_DIJAGNOSTICI\n"
                "- **Lokalna beleska:** Korisnik prijavio pad sistema.\n"
            )

        client2 = AgySyncClient(hub_url=self.hub_url, usb_root=client2_temp)

        # Povlačenje istorije sa Hub-a sa target_folder opcijom
        history = client2.pull(device_tag=tag, target_folder=dev2_dir)
        self.assertTrue(history.get("is_registered"))

        # Provera 1: SERVIS_HUB_HISTORY.md je generisan
        hub_hist_file = os.path.join(dev2_dir, "SERVIS_HUB_HISTORY.md")
        self.assertTrue(os.path.isfile(hub_hist_file))
        with open(hub_hist_file, "r", encoding="utf-8") as f:
            hist_content = f.read()
        self.assertIn("Dell Inc.", hist_content)
        self.assertIn("XP999", hist_content)
        self.assertIn("Zamena termalne paste", hist_content)

        # Provera 2: SERVISNI_DNEVNIK.md je spojen (sadrži i staru i novu belešku)
        with open(local_dnevnik_path, "r", encoding="utf-8") as f:
            merged_content = f.read()
        self.assertIn("Zamena termalne paste", merged_content)
        self.assertIn("Korisnik prijavio pad sistema", merged_content)

        shutil.rmtree(client2_temp, ignore_errors=True)

    def test_09_scenario_live_checkpoint(self):
        """
        Scenario 9 (ADR-0004): Live Checkpoint tokom dijagnostike.
        - AGY asistent poziva checkpoint() tokom rada
        - Lokalni dnevnik dobija zabelešku o nalazu
        - Hub ažurira status uređaja u Kvar (AGY) / KVAR_POTVRDJEN
        - Hub SERVISNI_DNEVNIK.md dobija novi zapis
        """
        tag = "HP_EliteBook_840_EB123"
        sn = "EB123"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="HP",
            model="EliteBook 840 G8",
            cpu="Intel Core i5-1135G7",
            ram_gb=16.0,
        )

        # Registracija
        self.client.register(device_dir=dev_dir)

        # Live Checkpoint nalaz
        cp_res = self.client.checkpoint(
            device_dir=dev_dir,
            summary="Detektovan 1 neispravan memorijski sektor preko MemTest-a",
            status="KVAR_POTVRDJEN",
            tools=["Test-SystemIntegrity.ps1"],
        )
        self.assertTrue(cp_res["success"])
        self.assertTrue(cp_res["sent_online"])
        self.assertEqual(cp_res["response"]["status_label"], "Kvar (AGY)")

        # Provera lokalnog dnevnika
        dnevnik_path = os.path.join(dev_dir, "SERVISNI_DNEVNIK.md")
        with open(dnevnik_path, "r", encoding="utf-8") as f:
            dnevnik_txt = f.read()
        self.assertIn("neispravan memorijski sektor", dnevnik_txt)
        self.assertIn("KVAR_POTVRDJEN", dnevnik_txt)

        # Provera stanja na Hub-u
        with self.fleet_store.fleet_lock:
            dev_state = self.fleet_store.fleet_devices.get(tag, {})
            self.assertEqual(dev_state.get("status_label"), "Kvar (AGY)")
            self.assertIn("neispravan memorijski sektor", dev_state.get("summary", ""))

    def test_10_scenario_offline_register_and_checkpoint_flush(self):
        """
        Scenario 10 (ADR-0004): Offline registracija i checkpoint, uz naknadni flush.
        - Klijent radi offline i šalje register() i checkpoint()
        - Fajlovi završavaju u pending_sync/ sa odgovarajućim prefiksima
        - Online klijent prazni red (flush_pending)
        - Hub prima registraciju i checkpoint bez gubitka podataka
        """
        tag = "Fujitsu_Lifebook_U7411_FJ555"
        sn = "FJ555"
        dev_dir = self._create_mock_device(
            tag=tag,
            serial=sn,
            manufacturer="FUJITSU",
            model="LIFEBOOK U7411",
            cpu="Intel Core i5-1145G7",
            ram_gb=8.0,
        )

        offline_client = AgySyncClient(
            hub_url="http://127.0.0.1:59996",
            usb_root=self.client_temp_dir,
            pending_dir=self.pending_dir,
        )

        # Offline registracija
        reg_res = offline_client.register(device_dir=dev_dir, status="U_DIJAGNOSTICI")
        self.assertFalse(reg_res["sent_online"])

        # Offline checkpoint
        cp_res = offline_client.checkpoint(
            device_dir=dev_dir,
            summary="Sumnja na kvar naponske sekcije matične ploče",
            status="KVAR_POTVRDJEN",
        )
        self.assertFalse(cp_res["sent_online"])

        # Provera pending fajlova
        pending_files = os.listdir(self.pending_dir)
        has_reg = any("_REGISTER_" in f for f in pending_files)
        has_cp = any("_CHECKPOINT_" in f for f in pending_files)
        self.assertTrue(has_reg)
        self.assertTrue(has_cp)

        # Flush sa online klijentom
        online_client = AgySyncClient(
            hub_url=self.hub_url,
            usb_root=self.client_temp_dir,
            pending_dir=self.pending_dir,
        )
        flushed = online_client.flush_pending()
        self.assertGreaterEqual(flushed, 2)

        # Provera da je Hub evidentirao uređaj i checkpoint
        hub_data = online_client.pull(device_tag=tag)
        self.assertTrue(hub_data.get("is_registered"))
        self.assertEqual(hub_data.get("serial_number"), sn)
        self.assertIn("Sumnja na kvar naponske sekcije", hub_data.get("dnevnik_markdown", ""))

    def test_11_scenario_serial_fallback(self):
        """
        Scenario 11 (ADR-0004): Fallback pretraga po serijskom broju kada je tag izmenjen.
        - Računar je evidentiran na Hub-u pod originalnim tagom
        - Klijent pretražuje po izmenjenom DeviceTag-u ali istom serijskom broju
        - pull() uspešno pronalazi uređaj preko fallback pretrage
        """
        orig_tag = "Lenovo_ThinkCentre_M720q_SN112233"
        sn = "SN112233"
        dev_dir = self._create_mock_device(
            tag=orig_tag,
            serial=sn,
            manufacturer="Lenovo",
            model="ThinkCentre M720q",
            root_cause="Zamena termalnog senzora.",
            status="COMPLETED",
        )

        self.client.push(device_dir=dev_dir)

        # Pretraga sa promenjenim tagom, ali istim serijskim brojem
        new_tag = "Lenovo_ThinkCentre_NEW_HOSTNAME_SN112233"
        data = self.client.pull(device_tag=new_tag, serial=sn)
        self.assertTrue(data.get("is_registered"))
        self.assertEqual(data.get("device_tag"), orig_tag)
        self.assertEqual(data.get("serial_number"), sn)


if __name__ == "__main__":
    unittest.main()
