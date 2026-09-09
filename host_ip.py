"""Print this computer's Wi-Fi IP for the phone app."""
import platform
import socket
import subprocess
import sys


def _mac_wifi() -> str | None:
    for iface in ("en0", "en1"):
        try:
            ip = subprocess.check_output(
                ["ipconfig", "getifaddr", iface],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            if ip:
                return ip
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    return None


def _linux_wifi() -> str | None:
    try:
        out = subprocess.check_output(
            ["hostname", "-I"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        for ip in out.split():
            if ip.startswith(("192.168.", "10.")):
                return ip
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return None


def _socket_ip() -> str | None:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        return None


def main() -> None:
    system = platform.system()
    ip = _mac_wifi() if system == "Darwin" else _linux_wifi() if system == "Linux" else None
    if not ip:
        ip = _socket_ip()
    if not ip:
        sys.exit(1)
    print(ip)


if __name__ == "__main__":
    main()
