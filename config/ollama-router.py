from flask import Flask, request, Response, stream_with_context, jsonify
import requests
import urllib3
import json
import os

# Tailscale TLS certs are not in the container's default CA store.
# Connections are already secured by Tailscale's ACLs, so we suppress the warning.
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

app = Flask(__name__)

GPU_URL = os.getenv("GPU_URL", "https://ollama-gpu.bombay-climb.ts.net")
CPU_URL = os.getenv("CPU_URL", "https://ollama-cpu.bombay-climb.ts.net")

BACKEND_TIMEOUT = 10

def merge_lists(list1, list2, key):
    seen = set()
    merged = []
    for item in list1 + list2:
        if item.get(key) and item[key] not in seen:
            seen.add(item[key])
            merged.append(item)
    return merged

@app.route('/health', methods=['GET'])
@app.route('/api/health', methods=['GET'])
def health():
    return jsonify({"status": True})

@app.route('/api/tags', methods=['GET'])
def get_tags():
    try:
        gpu_models = requests.get(f"{GPU_URL}/api/tags", timeout=BACKEND_TIMEOUT, verify=False).json().get('models', [])
    except Exception as e:
        app.logger.warning(f"GPU /api/tags failed: {e}")
        gpu_models = []
    try:
        cpu_models = requests.get(f"{CPU_URL}/api/tags", timeout=BACKEND_TIMEOUT, verify=False).json().get('models', [])
    except Exception as e:
        app.logger.warning(f"CPU /api/tags failed: {e}")
        cpu_models = []
    return jsonify({"models": merge_lists(gpu_models, cpu_models, 'name')})

@app.route('/api/ps', methods=['GET'])
def get_ps():
    try:
        gpu_models = requests.get(f"{GPU_URL}/api/ps", timeout=BACKEND_TIMEOUT, verify=False).json().get('models', [])
    except Exception as e:
        app.logger.warning(f"GPU /api/ps failed: {e}")
        gpu_models = []
    try:
        cpu_models = requests.get(f"{CPU_URL}/api/ps", timeout=BACKEND_TIMEOUT, verify=False).json().get('models', [])
    except Exception as e:
        app.logger.warning(f"CPU /api/ps failed: {e}")
        cpu_models = []
    return jsonify({"models": merge_lists(gpu_models, cpu_models, 'name')})

@app.route('/v1/models', methods=['GET'])
def get_v1_models():
    try:
        gpu_models = requests.get(f"{GPU_URL}/v1/models", timeout=BACKEND_TIMEOUT, verify=False).json().get('data', [])
    except Exception as e:
        app.logger.warning(f"GPU /v1/models failed: {e}")
        gpu_models = []
    try:
        cpu_models = requests.get(f"{CPU_URL}/v1/models", timeout=BACKEND_TIMEOUT, verify=False).json().get('data', [])
    except Exception as e:
        app.logger.warning(f"CPU /v1/models failed: {e}")
        cpu_models = []
    return jsonify({"object": "list", "data": merge_lists(gpu_models, cpu_models, 'id')})

@app.route('/', defaults={'path': ''}, methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'HEAD'])
@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'HEAD'])
def proxy(path):
    url = GPU_URL
    body = request.get_data()

    # Inspect payload to determine route based on -gpu / -cpu suffix in model name
    try:
        if body and request.is_json:
            data = json.loads(body)
            model_name = data.get('model', data.get('name', ''))
            if isinstance(model_name, str):
                if '-cpu' in model_name:
                    url = CPU_URL
                elif '-gpu' in model_name:
                    url = GPU_URL
    except Exception:
        pass

    target_url = f"{url}/{path}" if path else url
    app.logger.info(f"Proxying {request.method} {path} → {target_url}")

    resp = requests.request(
        method=request.method,
        url=target_url,
        headers={k: v for k, v in request.headers if k.lower() != 'host'},
        data=body,
        cookies=request.cookies,
        allow_redirects=False,
        stream=True,
        verify=False,
    )

    excluded_headers = ['content-encoding', 'content-length', 'transfer-encoding', 'connection']
    headers = [(k, v) for k, v in resp.raw.headers.items() if k.lower() not in excluded_headers]

    return Response(stream_with_context(resp.iter_content(chunk_size=1024)), resp.status_code, headers)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=11434, threaded=True)
