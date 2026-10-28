# XiaoFei Agent Windows companion (Python standard library, no pip needed)
# Connect ONLY on trusted home Wi-Fi. Start with start_windows.bat.
import json
import os
import secrets
import urllib.request
import urllib.error
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ROOT = Path(__file__).resolve().parent
ENVFILE = ROOT / ".env"
if ENVFILE.exists():
    for row in ENVFILE.read_text(encoding="utf-8-sig").splitlines():
        row = row.strip()
        if not row or row.startswith("#") or "=" not in row:
            continue
        key, value = row.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
CONFIG = {
    "deepseek": ("https://api.deepseek.com/v1/chat/completions", "deepseek-chat", "DEEPSEEK_API_KEY"),
    "qwen": ("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "qwen-plus", "DASHSCOPE_API_KEY"),
    "glm": ("https://open.bigmodel.cn/api/paas/v4/chat/completions", "glm-4-flash", "ZAI_API_KEY"),
    "kimi": ("https://api.moonshot.cn/v1/chat/completions", "moonshot-v1-8k", "KIMI_API_KEY"),
    "minimax": ("https://api.minimax.io/v1/chat/completions", "MiniMax-M2", "MINIMAX_API_KEY"),
    "openrouter": ("https://openrouter.ai/api/v1/chat/completions", "deepseek/deepseek-chat", "OPENROUTER_API_KEY"),
    "ollama": ("http://127.0.0.1:11434/v1/chat/completions", "qwen2.5:1.5b", ""),
}
provider = os.environ.get("LLM_PROVIDER", "demo").lower().strip()
if provider == "custom":
    endpoint = os.environ.get("LLM_BASE_URL", "").rstrip("/")
    endpoint = endpoint if endpoint.endswith("/chat/completions") else endpoint + "/chat/completions"
    model = os.environ.get("LLM_MODEL") or "custom-model"
    key = os.environ.get("LLM_API_KEY", "")
else:
    endpoint, default_model, key_env = CONFIG.get(provider, ("", "", ""))
    model = os.environ.get("LLM_MODEL") or default_model
    key = os.environ.get("LLM_API_KEY") or (os.environ.get(key_env, "") if key_env else "")
pair_path = ROOT / ".pair_code"
if pair_path.exists():
    pair = pair_path.read_text(encoding="utf-8").strip()
else:
    pair = secrets.token_urlsafe(18)
    pair_path.write_text(pair, encoding="utf-8")
history = []
def answer(message):
    if provider == "demo":
        return "这是演示回答。要连接国产 AI，请在 windows/.env 选择 LLM_PROVIDER 并填写相应 API Key。"
    if not endpoint or (not key and provider != "ollama"):
        raise ValueError("尚未配置有效的模型接口或密钥")
    messages = [{"role":"system", "content":"你是小斐，简洁实用的中文智能助手。"}]
    messages.extend(history[-12:])
    messages.append({"role": "user", "content": message})
    payload = json.dumps({"model":model, "messages":messages, "stream":False}, ensure_ascii=False).encode()
    headers = {"Content-Type": "application/json"}
    if key: headers["Authorization"] = "Bearer " + key
    request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=95) as response:
        data = json.loads(response.read(2_000_000).decode("utf-8"))
    result = data.get("choices", [{}])[0].get("message", {}).get("content", "")
    if not isinstance(result, str) or not result:
        raise ValueError("模型未返回文本回答")
    history.append({"role":"user", "content":message})
    history.append({"role":"assistant", "content":result})
    del history[:-24]
    return result
class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, data):
        raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    def authorized(self):
        return secrets.compare_digest(self.headers.get("X-Access-Token", ""), pair)
    def do_GET(self):
        if not self.authorized():
            return self.send_json(401, {"detail":"配对码错误"})
        if self.path == "/api/status":
            return self.send_json(200, {"llm":provider, "model":model})
        if self.path == "/api/history":
            return self.send_json(200, {"messages":history})
        return self.send_json(404, {"detail":"找不到接口"})
    def do_POST(self):
        if not self.authorized():
            return self.send_json(401, {"detail":"配对码错误"})
        if self.path != "/api/chat":
            return self.send_json(404, {"detail":"找不到接口"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            if n < 1 or n > 32768: raise ValueError("消息过长或为空")
            data = json.loads(self.rfile.read(n).decode("utf-8"))
            message = str(data.get("text", "")).strip()
            if not message: raise ValueError("请输入内容")
            reply = answer(message)
            return self.send_json(200, {"reply":reply})
        except urllib.error.HTTPError as ex:
            self.send_json(502, {"detail":"模型 API 错误 HTTP " + str(ex.code)})
        except Exception as ex:
            self.send_json(400, {"detail":str(ex)[:240]})
if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8765"))
    print("小斐 AI 服务端：端口", port, "配对码：", pair)
    print("注意：仅在可信家庭网络上启动。Windows 防火墙允许专用网络访问。")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
