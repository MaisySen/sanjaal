import unittest,io,json,importlib.util
from pathlib import Path
s=importlib.util.spec_from_file_location('apple',Path(__file__).with_name('apple_readonly.py'));a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
class Read(unittest.TestCase):
 def client(self,pages):
  self.calls=[]
  def open_(req,timeout):
   self.calls.append(req);return io.BytesIO(json.dumps(pages.pop(0)).encode())
  return a.AppleReadOnly('fixture-only-not-a-token',open_)
 def test_readonly_and_scoped(self):
  c=self.client([{'data':[{'id':'1'}],'links':{}}]);r=c.builds();self.assertTrue(r['complete']);self.assertEqual(self.calls[0].get_method(),'GET');self.assertTrue(self.calls[0].full_url.startswith(a.ORIGIN+'/v1/apps/'+a.APP+'/builds?'))
 def test_wrong_app(self):
  with self.assertRaises(ValueError):self.client([]).collection('/v1/apps/other/builds')
 def test_pagination_external(self):
  c=self.client([{'data':[],'links':{'next':'https://evil.invalid/v1/apps/'+a.APP+'/builds'}}])
  with self.assertRaises(ValueError):c.builds()
  self.assertEqual(len(self.calls),1)
 def test_changed_path(self):
  c=self.client([{'data':[],'links':{'next':a.ORIGIN+'/v1/users'}}])
  with self.assertRaises(ValueError):c.builds()
  self.assertEqual(len(self.calls),1)
 def test_loop(self):
  url=a.ORIGIN+'/v1/apps/'+a.APP+'/builds?limit=200';c=self.client([{'data':[],'links':{'next':url}}])
  with self.assertRaises(ValueError):c.builds()
 def test_groups_not_claimed_complete_audience(self):
  c=self.client([{'data':[],'links':{}}]);self.assertFalse(c.audience_groups()['complete_groups_and_testers'])
 def test_empty_jwt(self):
  with self.assertRaises(ValueError):a.AppleReadOnly('')
if __name__=='__main__':unittest.main()
