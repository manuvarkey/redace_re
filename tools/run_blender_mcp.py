"""Execute a source script through the running Blender MCP addon bridge."""
import socket,json,sys
from pathlib import Path
s=socket.create_connection(('127.0.0.1',9876),timeout=20);s.settimeout(600)
s.sendall(json.dumps({'type':'execute_code','params':{'code':'__file__ = '+repr(str(Path(sys.argv[1]).resolve()))+'\n'+Path(sys.argv[1]).read_text()}}).encode());buf=b''
while True:
 b=s.recv(65536)
 if not b:break
 buf+=b
 try:r=json.loads(buf);break
 except json.JSONDecodeError:pass
print(json.dumps(r));sys.exit(0 if r.get('status')=='success' else 1)
