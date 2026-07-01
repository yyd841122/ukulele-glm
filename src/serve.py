"""带 no-cache 头的 HTTP 服务器。

用法：python serve.py [port]
默认端口 8080。

发送 Cache-Control: no-store，避免 main.dart.js 被 HTTP 缓存。
"""
import http.server
import socketserver
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)


if __name__ == '__main__':
    with socketserver.TCPServer(('', PORT), NoCacheHandler) as httpd:
        print(f'服务启动: http://localhost:{PORT} (no-cache)')
        httpd.serve_forever()
