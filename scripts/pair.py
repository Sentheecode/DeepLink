#!/usr/bin/env python3
"""DeepLink 配对工具 — 扫码自动配置 Hermes 连接"""
import qrcode
import os
import re
import socket
import sys
import secrets


def get_lan_ip() -> str:
    """获取本机局域网 IP 地址"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # 不实际发送数据，只是获取路由信息
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


def get_or_generate_session_key() -> str:
    """从 ~/.hermes/.env 读取 API_SERVER_KEY，若没有则生成一个临时会话密钥"""
    env_path = os.path.expanduser("~/.hermes/.env")
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                m = re.match(r'^API_SERVER_KEY=(.+)$', line.strip())
                if m:
                    key = m.group(1).strip().strip('"').strip("'")
                    if key:
                        return key
    # 无有效密钥时生成临时会话密钥
    return secrets.token_urlsafe(32)


def main():
    lan_ip = get_lan_ip()
    port = "8642"
    url = f"http://{lan_ip}:{port}"
    api_key = get_or_generate_session_key()

    deep_link = f"deepseekbalance://configure?url={url}&key={api_key}"

    print("=" * 58)
    print("   DeepLink 配对二维码")
    print("=" * 58)

    # 生成二维码
    qr = qrcode.QRCode(
        version=2,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        border=2,
        box_size=2,
    )
    qr.add_data(deep_link)
    qr.print_ascii(invert=True)

    print()
    print(f"  URL: {url}")
    print(f"  Key: {api_key}")
    print()
    print(f"  用 iPhone 的 DeepLink App 扫描此码即可自动配置")
    print(f"  (Center → 拍照 → 扫描二维码)")
    print()
    print(f"  注意：未设置 API_SERVER_KEY 时将生成临时密钥")
    print()


if __name__ == "__main__":
    main()
