// Synthetic search and retained callbacks only. No live account lookup.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanjaal/search_page.dart';
import 'package:sanjaal/profile_pages.dart';
import 'package:sanjaal/feed_page.dart' show HashtagPage;
import 'upload_center_test.dart' as h;
void main(){
 for(final result in ['person','tag']){
  testWidgets('retained $result result cannot open into replacement login',(t)async{
   await h.fixture(t,(s,c)async{
    await t.pumpWidget(MaterialApp(home:SearchPage(session:s)));
    await t.enterText(find.byType(TextField),'fixture');await t.pump(const Duration(milliseconds:400));await h.flush(t);
    final old=t.widget<ListTile>(find.widgetWithText(ListTile,result=='person'?'@friend':'#music')).onTap!;
    await s.login('same','fixture');await h.flush(t);old();await h.flush(t);
    expect(find.byType(UserProfilePage),findsNothing);expect(find.byType(HashtagPage),findsNothing);
   },respond:(_)async=>h.json({'users':[{'public_id':'friend-id','username':'friend','name':'Friend'}],'hashtags':['music']}));
  });
 }
 for(final result in ['person','tag']){
  testWidgets('current $result callback opens correct destination only once',(t)async{
   await h.fixture(t,(s,c)async{
    await t.pumpWidget(MaterialApp(home:SearchPage(session:s)));
    await t.enterText(find.byType(TextField),'fixture');await t.pump(const Duration(milliseconds:400));await h.flush(t);
    final open=t.widget<ListTile>(find.widgetWithText(ListTile,result=='person'?'@friend':'#music')).onTap!;
    open();open();await h.flush(t);
    if(result=='person'){
     expect(find.byType(UserProfilePage),findsOneWidget);expect(t.widget<UserProfilePage>(find.byType(UserProfilePage)).username,'friend');
    }else{
     expect(find.byType(HashtagPage),findsOneWidget);expect(t.widget<HashtagPage>(find.byType(HashtagPage)).tag,'music');
    }
    await t.pageBack();await h.flush(t);await t.pumpAndSettle();
    open();await h.flush(t);expect(find.byType(result=='person'?UserProfilePage:HashtagPage),findsOneWidget);
   },respond:(r)async{
    if(r.url.path.endsWith('/users/search'))return h.json({'users':[{'public_id':'friend-id','username':'friend','name':'Friend'}],'hashtags':['music']});
    if(r.url.path.endsWith('/users/friend'))return h.json({'user':{'public_id':'friend-id','username':'friend','name':'Friend'}});
    return h.json({'data':[],'next_cursor':null});
   });
  });
 }
 testWidgets('editing query invalidates retained result before next debounce',(t)async{
  await h.fixture(t,(s,c)async{
   await t.pumpWidget(MaterialApp(home:SearchPage(session:s)));
   await t.enterText(find.byType(TextField),'old');await t.pump(const Duration(milliseconds:400));await h.flush(t);
   final old=t.widget<ListTile>(find.widgetWithText(ListTile,'@friend')).onTap!;
   await t.enterText(find.byType(TextField),'new');old();await h.flush(t);
   expect(find.byType(UserProfilePage),findsNothing);
   await t.pumpWidget(const SizedBox());
  },respond:(_)async=>h.json({'users':[{'public_id':'friend-id','username':'friend','name':'Friend'}],'hashtags':[]}));
 });
}
