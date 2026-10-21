# BoxBar

A macOS menu bar app for the **ZLT X31** 5G router, sold by Ooredoo as the "Ooredoo 5G" box. It shows signal, network type and battery in the menu bar. Click it for the full picture: LTE and 5G signal quality, bands, live throughput, data used, CPU, temperature, connected Wi-Fi clients and a network-mode switch (for example, 4G only to save battery).

```
▂▄▆ 4G+ 72%
```

The repo also contains a small Python client (`box_client.py`) and a map of the box's web API (`docs/api-reference.html`), in case you want to build your own dashboard.

> Not affiliated with Ooredoo or ZLT. Use at your own risk.

## Compatibility

Tested on a ZLT X31C running firmware 1.0.0.24 (config X31-TN0303, Ooredoo Tunisia). Other ZLT boxes that use the same web UI may work: it posts JSON to `/cgi-bin/http.cgi`, and its login page saves `username_sunsea` in your browser storage. If you try one, please open an issue with the model and firmware.

BoxBar needs macOS 14 or later.

## Install

Build from source. You need Xcode or the Xcode command line tools (`xcode-select --install`).

```sh
git clone <this repo>
cd <repo>/BoxBar
./build.sh                       # produces BoxBar.app
mv BoxBar.app /Applications/
open /Applications/BoxBar.app
```

### First run

1. If macOS asks whether BoxBar may access devices on your local network, allow it. Without that permission BoxBar can't reach the box.
2. Click the menu bar icon. BoxBar finds the box by itself and shows something like "Found ZLT X31 at 192.168.100.1". Enter the admin password and click **Connect**. Signal and battery show up even before you log in.
3. BoxBar tries the login once. If it works, the password goes into your macOS Keychain; it is never written to disk anywhere else. A wrong password shows an error straight away instead of being retried, because the box locks the account after 3 failed attempts.

To find the box, BoxBar checks your network's router address, then a few common box addresses (`192.168.100.1`, `192.168.0.1`, `192.168.1.1`, `192.168.8.1`, `192.168.10.1`). It looks for a device that answers the box's API. If the box changes address later, BoxBar finds it again. To pin an address or change the username, open **Advanced** in the setup form, under the gear icon.

### Can't see the icon?

- Menu bar managers such as **Ice** and **Bartender** put new icons in their hidden section. Move BoxBar to the visible section in their settings.
- On MacBooks with a notch, a crowded menu bar can hide icons behind the notch. ⌘-drag other icons out of the menu bar to make room.

## How it works

The box's web UI talks to one endpoint: JSON `POST`s to `https://<box>/cgi-bin/http.cgi`, each with a numeric `cmd`. Login sends `sha256(token + password)`, where the token comes from `cmd 232`. See [docs/api-reference.html](docs/api-reference.html) for the full map.

- **Every 15 s, no login:** `cmd 113` and `cmd 133` return network type, signal (RSRP, RSRQ, SINR), bands, cell, WAN IP and battery.
- **Every 30 s, with login:** `cmd 1002`, `1001`, `1000` and `256` return traffic counters, CPU, temperature, memory, Wi-Fi clients and network mode.
- **On demand:** `cmd 256` changes the network mode. This is the only setting BoxBar changes, and only when you pick a mode from its menu. Changing it reconnects the modem, so expect about 10 seconds offline and a new WAN IP.

### The box allows one login at a time

A new login immediately ends the previous session. While detailed stats are on, BoxBar and the box's web UI take turns:

- If BoxBar sees that someone else logged in, it pauses detailed stats for 5 minutes instead of taking the session back.
- The panel's **Open web UI** button pauses BoxBar for 10 minutes.
- If you mostly want signal and battery, turn off detailed stats. That part needs no login.

## Security notes

- The box uses a self-signed HTTPS certificate. BoxBar accepts it for the configured box address only; every other host gets normal certificate checks.
- The admin password is stored in the macOS Keychain, one item per box address.
- Be aware that the box answers `cmd 133` **without a password**, including the SIM's IMSI and ICCID, the modem's IMEI and the WAN IP. Anyone on your Wi-Fi can read them. BoxBar doesn't cause this, but it's worth knowing before you share your Wi-Fi.

## Troubleshooting

```sh
/Applications/BoxBar.app/Contents/MacOS/BoxBar --check
```

This polls the box for 8 seconds using your saved settings and prints everything the panel would show. It doesn't print the password.

## Python client

```sh
BOX_PASSWORD=... python3 box_client.py          # one JSON snapshot
```

`BOX_URL` and `BOX_USER` override the defaults (`https://192.168.100.1`, `admin`). Use `Box().get(cmd)`, `Box().post(cmd, **params)` and `Box().set_network_mode("4")` from your own scripts.

## License

MIT
