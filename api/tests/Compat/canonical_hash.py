import hashlib,json,sys
b=open(sys.argv[1],'rb').read()
try: b=json.dumps(json.loads(b),sort_keys=True,separators=(',',':')).encode()
except (ValueError,UnicodeDecodeError): pass
print(hashlib.sha256(b).hexdigest())
