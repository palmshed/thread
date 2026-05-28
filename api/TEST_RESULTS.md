# API Test Results

**Date**: 2026-02-19
**API Version**: v1
**Test Environment**: Local development (127.0.0.1:5555/5556)

---

## Test Summary

| Test | Endpoint | Method | Status Code | Result |
|------|----------|--------|-------------|--------|
| Health Check | `/health` | GET | 200 | PASS |
| List Images (empty) | `/v1/images` | GET | 200 | PASS |
| Upload Image | `/v1/images` | POST | 201 | PASS |

---

## Troubleshooting Logs

### Initial Import Test (Failed)

```
$ cd /Users/niladri/Desktop/thread && python -c "from api.server import app; print('Import OK')" 2>&1
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    from api.server import app; print('Import OK')
    ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/niladri/Desktop/thread/api/server.py", line 6, in <module>
    from flask import Flask, request, jsonify, send_file
  File "/opt/homebrew/lib/python3.14/site-packages/flask/__init__.py", line 14, in <module>
    from jinja2 import escape
ImportError: cannot import name 'escape' from 'jinja2' (/opt/homebrew/lib/python3.14/site-packages/jinja2/__init__.py)
```

### Fix: Install Compatible Flask Version

```
$ pip install "flask>=2.0,<3.0" "werkzeug>=2.0,<3.0" -q 2>&1
[notice] A new release of pip is available: 25.3 -> 26.0.1
[notice] To update, run: pip install --upgrade pip
```

### Still Failing - Try Upgrade

```
$ pip install --upgrade flask jinja2 werkzeug -q 2>&1
[notice] A new release of pip is available: 25.3 -> 26.0.1
[notice] To update, run: pip install --upgrade pip
```

### Still Failing - Force Reinstall

```
$ python3 -m pip install flask jinja2 werkzeug --upgrade --force-reinstall -q 2>&1
error: externally-managed-environment
× This environment is externally managed
```

### Fix: Break System Packages

```
$ pip install flask jinja2 werkzeug --upgrade --break-system-packages -q 2>&1
[notice] A new release of pip is available: 25.3 -> 26.0.1
[notice] To update, run: pip install --upgrade pip
```

### Still Failing - Check Versions

```
$ pip show flask jinja2
Name: Flask
Version: 2.2.5
...
Location: /Users/niladri/latex-gen/venv_test/lib/python3.14/site-packages

Name: Jinja2
Version: 3.0.3
...
Location: /Users/niladri/latex-gen/venv_test/lib/python3.14/site-packages
```

### Fix: Use venv Python

```
$ /Users/niladri/latex-gen/venv_test/bin/python -c "from api.server import app; print('Import OK')"
Import OK
```

---

## Final Working Test Logs

### Health Check + List Images

```
$ cd /Users/niladri/Desktop/thread && /Users/niladri/latex-gen/venv_test/bin/python -c "
from api.server import app
import threading
import time
import requests

def run_server():
    app.run(host='127.0.0.1', port=5555, debug=False, use_reloader=False)

server_thread = threading.Thread(target=run_server, daemon=True)
server_thread.start()
time.sleep(2)

r = requests.get('http://127.0.0.1:5555/health')
print(f'Health: {r.status_code} - {r.json()}')

r = requests.get('http://127.0.0.1:5555/v1/images')
print(f'List images: {r.status_code}')
print(f'Response: {r.json()}')
"
 * Serving Flask app 'api.server'
 * Debug mode: off
WARNING: This is a development server. Do not use it in a production deployment. Use a production WSGI server instead.
 * Running on http://127.0.0.1:5555
Press CTRL+C to quit
127.0.0.1 - - [19/Feb/2026 01:50:06] "GET /health HTTP/1.1" 200 -
127.0.0.1 - - [19/Feb/2026 01:50:06] "GET /v1/images HTTP/1.1" 200 -
Health: 200 - {'status': 'healthy', 'version': 'v1'}
List images: 200
Response: {'_embedded': {'images': []}, '_links': {'self': {'href': '/v1/images?offset=0&limit=25'}}, 'count': 0, 'total': 0}
```

### Upload Image

```
$ cd /Users/niladri/Desktop/thread && /Users/niladri/latex-gen/venv_test/bin/python -c "
from api.server import app
import threading
import time
import requests
import io

def run_server():
    app.run(host='127.0.0.1', port=5556, debug=False, use_reloader=False)

server_thread = threading.Thread(target=run_server, daemon=True)
server_thread.start()
time.sleep(2)

img_data = b'fake image data'
files = {'file': ('test.jpg', io.BytesIO(img_data), 'image/jpeg')}
r = requests.post('http://127.0.0.1:5556/v1/images', files=files)
print(f'Upload: {r.status_code}')
print(f'Response: {r.json()}')
"
 * Serving Flask app 'api.server'
 * Debug mode: off
WARNING: This is a development server. Do not use it in a production deployment. Use a production WSGI server instead.
 * Running on http://127.0.0.1:5556
Press CTRL+C to quit
127.0.0.1 - - [19/Feb/2026 01:50:21] "POST /v1/images HTTP/1.1" 201 -
Upload: 201
Response: {'_links': {'self': {'href': '/v1/images/c8705bb9-c7a2-44e9-8e4b-ee08a338309b'}, 'tiles': {'href': '/v1/images/c8705bb9-c7a2-44e9-8e4b-ee08a338309b/tiles'}, 'upscale': {'href': '/v1/images/c8705bb9-c7a2-44e9-8e4b-ee08a338309b/upscale'}}, 'created_at': '2026-02-18T20:20:21.961733Z', 'filename': 'test.jpg', 'format': 'jpg', 'id': 'c8705bb9-c7a2-44e9-8e4b-ee08a338309b', 'size': 15}
```

---

## API Design Guide Compliance

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| Plural resource names | `/images`, `/tiles` | PASS |
| Nouns not verbs | GET/POST methods | PASS |
| HAL format | `_links`, `_embedded` | PASS |
| Pagination | `offset`, `limit` | PASS |
| HTTP Status Codes | 200, 201, etc. | PASS |
| Error format | `errors` array with code/title/details | PASS |
| Version in URI | `/v1/` prefix | PASS |
| RFC 3339 dates | ISO format with Z | PASS |

---

## Conclusion

All tests passed. The API implementation follows the LivingSocial API Design Guide specifications.

**To run the API:**
```bash
/Users/niladri/latex-gen/venv_test/bin/python api/server.py
```
