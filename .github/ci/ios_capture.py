# Disposable localhost-only CI screenshot bridge. No device/account writes.
import http.server,os,pathlib,json,subprocess,hmac,time
TOKEN=pathlib.Path('/tmp/ios-e2e/token.txt').read_text().strip()
OUT=pathlib.Path('build/screenshots');OUT.mkdir(parents=True,exist_ok=True)
NAMES={'ios_chat_before_send','ios_chat_server_confirmed','ios_rooms_loaded','ios_settings','ios_tab_home','ios_post_confirmed','ios_home','ios_tab_reels','ios_tab_chats','ios_tab_wallet','ios_tab_me','ios_native_avfoundation_poster','ios_post_test_text_input','ios_test_teardown'}
class Handler(http.server.BaseHTTPRequestHandler):
 def do_POST(self):
  name=self.path.removeprefix('/')
  if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+TOKEN) or name not in NAMES:
   self.send_error(403);return
  try:
   time.sleep(1)
   r=subprocess.run(['xcrun','simctl','io',os.environ['IOS_DEVICE'],'screenshot',str(OUT/('native-checkpoint-'+name+'.png'))],capture_output=True,timeout=15)
   self.send_response(200 if r.returncode==0 else 500);self.end_headers();self.wfile.write(json.dumps({'captured':r.returncode==0,'checkpoint':name}).encode())
  except Exception:
   self.send_error(500)
 def log_message(self,*args):pass
http.server.HTTPServer(('127.0.0.1',8002),Handler).serve_forever()
