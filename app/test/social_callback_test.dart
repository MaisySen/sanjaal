// Pure native-browser callback contract fixtures, not Auth0 or provider proof.
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjaal/api.dart';
void main(){
 test('expected native redirect and state return the decoded code',(){
  expect(socialCallbackCode('$socialRedirect?state=fixture-state&code=code%2Bvalue','fixture-state'),'code+value');
 });
 for(final callback in [
  '$socialRedirect?state=wrong&code=fixture',
  '$socialRedirect?code=fixture',
  '$socialRedirect?state=fixture-state',
  '$socialRedirect?state=fixture-state&code=',
  '$socialRedirect?state=fixture-state&code=%20',
  '$socialRedirect?state=fixture-state&state=fixture-state&code=fixture',
  '$socialRedirect?state=fixture-state&code=first&code=second',
  '$socialRedirect?state=fixture-state&code=fixture#fragment',
  '$socialScheme://different?state=fixture-state&code=fixture',
  'https://login-callback?state=fixture-state&code=fixture',
  '$socialRedirect/path?state=fixture-state&code=fixture',
  '$socialScheme://user@login-callback?state=fixture-state&code=fixture',
  '$socialScheme://login-callback:123?state=fixture-state&code=fixture',
  'not a callback',
  'http://[',
 ]){
  test('unexpected or ambiguous callback is rejected $callback',(){
   expect(()=>socialCallbackCode(callback,'fixture-state'),throwsA(isA<ApiError>()));
  });
 }
 test('provider rejection on expected callback remains an error not a code',(){
  expect(()=>socialCallbackCode('$socialRedirect?state=fixture-state&error=access_denied','fixture-state'),throwsA(isA<ApiError>().having((e)=>e.message,'message','access_denied')));
 });
 test('empty expected state cannot authorize a callback',(){
  expect(()=>socialCallbackCode('$socialRedirect?state=&code=fixture',''),throwsA(isA<ApiError>()));
 });
}
