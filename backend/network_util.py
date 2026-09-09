import socket


def lan_ip() -> str | None:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        return None


def phone_api_url(port: int = 8000) -> str | None:
    ip = lan_ip()
    if not ip:
        return None
    return f"http://{ip}:{port}/api"
