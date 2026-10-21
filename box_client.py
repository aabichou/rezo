"""Minimal client for the ZLT X31 (Ooredoo 5G box) web API.

Every call is a JSON POST to /cgi-bin/http.cgi with a numeric `cmd`.
Reads use method "GET" in the body; writes use "POST" plus the login token.

    BOX_PASSWORD=... python3 box_client.py            # one snapshot as JSON
"""
import hashlib
import json
import os
import ssl
import urllib.request

BASE = os.environ.get("BOX_URL", "https://192.168.100.1")
USER = os.environ.get("BOX_USER", "admin")
PASSWORD = os.environ.get("BOX_PASSWORD", "")

# Read-only commands that are useful for monitoring.
CMD = {
    "NEXT_LOGIN_TIME": 232,   # returns the login token (no auth)
    "LOGIN": 100,
    "LOGOUT": 101,
    "SYS_STATUS": 113,        # no auth: network type, signal level, battery, wifi switches
    "ROUTER_INFO": 133,       # no auth: RSRP/RSRQ/SINR, cell, WAN IP, byte counters
    "INIT_INFO": 1008,        # no auth: branding/theme
    "DEVICE_NAME": 104,       # uptime, keepalive the UI fires after each write
    "DEVICE_INFO": 1001,      # cpu, memory, temperature, versions, IMEI/ICCID
    "WAN_INFO": 1002,         # full radio + WAN detail, session/monthly traffic
    "GLOBE_STATUS": 1003,
    "LOOP_INFO": 1005,        # what the UI polls: status flags, battery, sms_unread
    "WIFI_INFO": 1006,        # needs type="0" (2.4G) or "1" (5G)
    "MOUNT_INFO": 1007,
    "DEVICE_LIST": 1000,      # DHCP leases + per-band wifi clients with RSSI/rate
    "DHCP_CLIENTS": 223,
    "WIFI24_CLIENTS": 224,
    "WIFI5_CLIENTS": 225,
    "BATTERY_GRAPH": 1014,    # ~22 samples: capacity + battery temp
    "CPU_GRAPH": 1015,        # 5-min CPU usage samples, ~24h
    "TEMP_GRAPH": 1016,       # ~22 samples: device temperature
    "FLOW_INFO": 18,          # LAN-side rx/tx bytes + packets
    "LAN_INFO": 208,
    "NETWORK_MODE": 218,
    "TRAFFIC_LIMIT": 337,
    "SIM_STATUS": 134,
    "VERSION": 43,
    "SYS_LOG": 17,            # plain text, not JSON
}

# cmd 256 values this board accepts (display_mode "1E").
NETWORK_MODES = {
    "1E": "Auto (5G SA+NSA/4G/3G)",
    "1C": "5G (SA+NSA)/4G",
    "10": "5G SA only",
    "C": "5G NSA only",
    "6": "4G/3G",
    "4": "4G only",
    "2": "3G only",
}

_CTX = ssl._create_unverified_context()  # box uses a self-signed cert


class AuthError(Exception):
    pass


class Box:
    def __init__(self, base=BASE, user=USER, password=PASSWORD, timeout=20):
        self.url = base.rstrip("/") + "/cgi-bin/http.cgi"
        self.user, self.password, self.timeout = user, password, timeout
        self.session_id = ""
        self.token = ""

    def _post(self, body):
        req = urllib.request.Request(
            self.url,
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json;charset=UTF-8"},
            method="POST",
        )
        with urllib.request.urlopen(req, context=_CTX, timeout=self.timeout) as r:
            raw = r.read().decode("utf-8", "replace")
        try:
            return json.loads(raw)
        except ValueError:
            return {"_raw": raw}

    def login(self):
        # passwd = sha256(token + plaintext). The box allows ONE session:
        # logging in here logs out any open browser tab, and vice versa.
        tok = self._post({"cmd": CMD["NEXT_LOGIN_TIME"], "method": "GET", "sessionId": ""})["token"]
        r = self._post({
            "cmd": CMD["LOGIN"], "method": "POST", "sessionId": "",
            "username": self.user,
            "passwd": hashlib.sha256((tok + self.password).encode()).hexdigest(),
            "token": tok, "isAutoUpgrade": "0",
        })
        if not r.get("success"):
            raise AuthError(r)
        self.session_id, self.token = r["sessionId"], tok
        return r

    def get(self, cmd, retry=True, **params):
        cmd = CMD.get(cmd, cmd)
        r = self._post({"cmd": cmd, "method": "GET", "sessionId": self.session_id, **params})
        if retry and r.get("message") in ("NO_AUTH", "LOGIN_TIMEOUT"):
            self.login()
            return self.get(cmd, retry=False, **params)
        return r

    def post(self, cmd, retry=True, **params):
        cmd = CMD.get(cmd, cmd)
        r = self._post({"cmd": cmd, "method": "POST", "sessionId": self.session_id,
                        "token": self.token, **params})
        if retry and r.get("message") in ("NO_AUTH", "LOGIN_TIMEOUT"):
            self.login()
            return self.post(cmd, retry=False, **params)
        return r

    def set_network_mode(self, mode):
        # Any write here re-attaches the modem (~10 s outage, new WAN IP),
        # even when the value doesn't change.
        if mode not in NETWORK_MODES:
            raise ValueError(f"unknown mode {mode!r}, pick one of {list(NETWORK_MODES)}")
        return self.post(256, networkMode=mode)

    def logout(self):
        self._post({"cmd": CMD["LOGOUT"], "method": "POST",
                    "sessionId": self.session_id, "token": self.token})


def _kb(s):
    return int(s.replace("kB", "").strip())


def snapshot(box):
    """One normalized reading, ready to push to a TSDB or render."""
    dev, wan, loop = box.get("DEVICE_INFO"), box.get("WAN_INFO"), box.get("LOOP_INFO")
    clients = box.get("DEVICE_LIST")
    mem = [_kb(x) for x in dev["memory"].split(",")]
    return {
        "time": dev["systime"],
        "uptime_s": int(dev["uptime"]),
        "cpu_pct": float(dev["cpu_usage"]),
        "load": [float(x) for x in dev["cpuload"].split(",")],
        "mem_total_kb": mem[0],
        "mem_used_kb": mem[0] - mem[1] - mem[2],
        "temp_c": int(dev["device_temperature"]),
        "battery_pct": int(loop["battery_capacity"] or 0),
        "charging": loop["battery_charge_status"] == "1",
        "network": wan["network_type_str"],
        "operator": wan["network_operator"],
        "signal_bars": int(wan["signal_lvl"]),
        "lte": {
            "rsrp": wan["RSRP"], "rsrq": wan["RSRQ"], "sinr": wan["SINR"], "rssi": wan["RSSI"],
            "bands": wan["currentband"], "bw_mhz": wan["bandwidth"], "pci": wan["PCI"],
            "earfcn": wan["FREQ"], "cqi": wan["CQI"],
        },
        "nr": {
            "rsrp": wan["RSRP_5G"], "rsrq": wan["RSRQ_5G"], "sinr": wan["SINR_5G"],
            "band": wan["currentband_5g"], "bw_mhz": wan["bandwidth_5g"], "pci": wan["PCI_5G"],
            "arfcn": wan["FREQ_5G"], "cqi": wan["CQI_5G"],
        },
        "cell_id": wan["CELL_ID"], "enodeb": wan["ENODEBID"], "tac": wan["tac_4g"],
        "wan_ip": wan["wan_ip"], "wan_ipv6": wan["wan_ipv6_ip"],
        # MB with 2 decimals; diff two readings to get throughput.
        "session_dl_mb": float(wan["flow_dl"]), "session_ul_mb": float(wan["flow_ul"]),
        "month_total_mb": float(wan["mon_total_flow"]),
        "connected_s": int(wan["data_connect_time"] or 0),
        "clients": len(clients.get("dhcp_list_info", [])),
        "wifi_clients": clients.get("wlan24g_wifi_info", []) + clients.get("wlan5g_wifi_info", []),
    }


if __name__ == "__main__":
    print(json.dumps(snapshot(Box()), indent=1))
