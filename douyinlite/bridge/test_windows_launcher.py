"""No network or browser required. Validate Windows companion safety and configuration."""
import importlib.util
from pathlib import Path
import tempfile


MODULE = Path(__file__).with_name("windows_launcher.py")
spec = importlib.util.spec_from_file_location("douyin_windows_launcher", MODULE)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


def test_secret_generated_once_and_not_default():
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / ".bridge-key"
        key = launcher.load_secret(path)
        assert len(key) == 48 and all(char in "0123456789abcdef" for char in key)
        assert launcher.load_secret(path) == key


def test_reject_unsafe_stored_secret():
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / ".bridge-key"
        path.write_text("demo-secret\n", encoding="ascii")
        try:
            launcher.load_secret(path)
        except ValueError:
            pass
        else:
            raise AssertionError("Unsafe stored key accepted")


def test_tunnel_address_only_from_cloudflare_https():
    assert launcher.tunnel_address(["2026 INFO https://smiling-forest.trycloudflare.com is ready"]) == (
        "https://smiling-forest.trycloudflare.com")
    assert launcher.tunnel_address(["http://smiling-forest.trycloudflare.com"]) is None
    assert launcher.tunnel_address(["https://example.net"]) is None
    assert launcher.tunnel_address(["https://trycloudflare.com.attacker.net"]) is None


def test_windows_launcher_uses_real_browser_and_private_tunnel():
    code = MODULE.read_text(encoding="utf-8")
    assert 'env["HEADLESS"] = "false"' in code
    assert 'env["BROWSER_PROFILE"]' in code
    assert 'secrets.token_hex(24)' in code
    assert '"--host", "127.0.0.1"' in code
    assert 'cloudflared-windows-amd64.exe' in code
    assert '"/api/feed"' not in code or 'api/feed' in code
    assert 'print("   私有密钥:' in code
