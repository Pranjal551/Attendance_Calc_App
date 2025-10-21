
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvw;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  // CONFIG: schedule window & end-of-class reminder toggle
  static const int kScheduleDaysAhead = 30;
  static const bool kScheduleEndReminder = true; // set false to disable

  /// Check if Firebase is available on this platform
  static bool get _isFirebaseSupported {
    // Firebase is not properly configured for Windows/Linux/macOS desktop
    // Only use it on mobile platforms
    try {
      return (Platform.isAndroid || Platform.isIOS);
    } catch (e) {
      // If Platform is not available (web), return false
      return false;
    }
  }

  static Future<void> initCrossPlatform() async {
    // Initialize Firebase only on supported platforms
    if (_isFirebaseSupported) {
      try {
        await Firebase.initializeApp();
      } catch (e) {
        debugPrint('Firebase initialization failed: $e');
        // Continue without Firebase - local notifications will still work
      }
    }

    // Timezone: IST
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    // Cross-platform initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _fln.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );

    // Android 13+ runtime permission & channel creation
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'timetable_channel',
      'Timetable',
      description: 'Notifications for scheduled lectures/labs',
      importance: Importance.max,
      playSound: true,
    );
    await android?.createNotificationChannel(channel);

    // iOS permission request
    final ios = _fln.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // payload format: subject|typeIndex
  static Future<void> _onResponse(NotificationResponse r) async {
    final payload = r.payload ?? '';
    final parts = payload.split('|');
    if (parts.length != 2) return;
    final subject = parts[0];
    final typeIndex = int.tryParse(parts[1]);
    final present = r.actionId == 'PRESENT';
    if (typeIndex == null) return;

    AttendanceHomeState.onNotificationMarkAttendance?.call(
      subject,
      typeIndex,
      present,
    );
  }

  static String _subtitleForType(int typeIndex) {
    switch (typeIndex) {
      case 0:
        return 'Lecture starts now';
      case 1:
        return 'Tutorial starts now';
      case 2:
        return 'Lab starts now';
      default:
        return 'Class starts now';
    }
  }

  /// Schedules one-off notifications for the next N days based on provided entries.
  static Future<void> scheduleDaily(List<TimetableEntrySimple> entries) async {
    await _fln.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    int id = 1000;

    for (int d = 0; d < kScheduleDaysAhead; d++) {
      final date = now.add(Duration(days: d));
      // Skip Saturday as per requirement
      if (date.weekday == DateTime.saturday) continue;

      final todays = entries.where((e) => e.weekday == date.weekday).toList();
      for (final e in todays) {
        final start = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          e.start.hour,
          e.start.minute,
        );

        await _fln.zonedSchedule(
          id++,
          e.subject,
          _subtitleForType(e.typeIndex),
          start,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'timetable_channel',
              'Timetable',
              importance: Importance.max,
              priority: Priority.high,
              actions: const [
                AndroidNotificationAction('PRESENT', 'Present'),
                AndroidNotificationAction('ABSENT', 'Absent'),
              ],
            ),
          ),
          payload: '${e.subject}|${e.typeIndex}',
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );

        if (kScheduleEndReminder) {
          final end = start.add(Duration(minutes: e.durationMinutes + 2));
          await _fln.zonedSchedule(
            id++,
            '${e.subject} — mark attendance',
            'Did you attend? Tap Present/Absent',
            end,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'timetable_channel',
                'Timetable',
                importance: Importance.high,
                priority: Priority.high,
                actions: const [
                  AndroidNotificationAction('PRESENT', 'Present'),
                  AndroidNotificationAction('ABSENT', 'Absent'),
                ],
              ),
            ),
            payload: '${e.subject}|${e.typeIndex}',
            androidAllowWhileIdle: true,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    }
  }
}

/// ======================
/// ORIGINAL APP STRUCTURE
/// ======================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initCrossPlatform(); // Cross-platform init
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AttendanceHome(),
    );
  }
}

class OnlineCheckPage extends StatefulWidget {
  final Uri url;
  final String username;
  final String password;

  const OnlineCheckPage({super.key, required this.url, required this.username, required this.password});

  @override
  State<OnlineCheckPage> createState() => _OnlineCheckPageState();
}

class _OnlineCheckPageState extends State<OnlineCheckPage> {
  late final WebViewController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            if (!_loaded) {
              _loaded = true;
              await _autofillCreds(submit: false);
              // After first load, try navigating to Attendance once logged in
              Future.delayed(const Duration(seconds: 1), _gotoAttendanceAndFill);
            }
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  String _escapeJs(String s) => s.replaceAll('\\', r'\\').replaceAll("'", r"\'");

  Future<void> _autofillCreds({bool submit = false}) async {
    final u = _escapeJs(widget.username);
    final p = _escapeJs(widget.password);
    final base = """
      (function(){
        function setVal(el, val){
          try{ el.focus(); el.value=val; el.setAttribute('value', val);
            el.dispatchEvent(new Event('input',{bubbles:true}));
            el.dispatchEvent(new Event('change',{bubbles:true}));
            el.dispatchEvent(new KeyboardEvent('keyup',{bubbles:true,key:'a'}));
            return true;
          }catch(e){ return false; }
        }
        function findUser(){
          var sels=['#j_username','#logonuidfield','#userid','#username','#USERNAME','#sap-user','input[name=j_username]','input[name=username]','input[name=userid]','input[name=USER]','input[id*=user]','input[name*=user]','input[placeholder*="User"]','input[placeholder*="ID"]','input[type=email]'];
          for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el) return el; }
          var inputs=document.querySelectorAll('input');
          for(var i=0;i<inputs.length;i++){
            var el=inputs[i]; var n=(el.name||'').toLowerCase(); var id=(el.id||'').toLowerCase(); var ph=(el.placeholder||'').toLowerCase(); var t=(el.type||'').toLowerCase();
            if(t==='text'||t==='email'||t==='tel'){
              if(n.includes('user')||n.includes('uid')||n.includes('login')||id.includes('user')||id.includes('uid')||id.includes('login')||ph.includes('user')||ph.includes('id')||ph.includes('email')) return el;
            }
          }
          return null;
        }
        function findPass(){
          var sels=['#j_password','#logonpassfield','#password','#sap-password','input[name=j_password]','input[name=password]','input[id*=pass]'];
          for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el && (el.type||'').toLowerCase()==='password') return el; }
          var inputs=document.querySelectorAll('input[type=password], input[id*=pass], input[name*=pass]');
          if(inputs.length>0) return inputs[0];
          return null;
        }
        function clickLogin(){
          var sels=['#logonButton','button[type=submit]','input[type=submit]','button[id*=logon]','button[name*=logon]','button[id*=login]','button[name*=login]'];
          for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el){ el.click(); return true; }}
          var forms=document.querySelectorAll('form'); if(forms.length>0){ forms[0].submit(); return true; }
          return false;
        }
        function focusCaptcha(){ var cap=document.querySelector('#captcha, input[name=captcha], #logonCaptcha, input[id*=captcha], input[name*=captcha]'); if(cap){ cap.focus(); return true; } return false; }
        function focusLoginPanel(){
          var u=findUser(), p=findPass(); if(!u||!p) return false;
          var c=u; var steps=0; while(c && steps<6 && !c.contains(p)){ c=c.parentElement; steps++; }
          if(!c) c=u.parentElement;
          try{
            // Hide everything else so only login area is visible
            var topKids=[].slice.call(document.body.children);
            topKids.forEach(function(el){ if(!c.contains(el)) el.style.display='none'; });
          }catch(e){}
          try{ c.scrollIntoView({block:'center'}); }catch(e){}
          try{ document.body.style.background='white'; document.body.style.zoom='1.2'; }catch(e){}
          return true;
        }
        function selectByTextLike(sel, txt){ txt=(txt||'').toLowerCase(); var opts=sel ? sel.options : null; if(!opts) return false; for(var i=0;i<opts.length;i++){ var t=(opts[i].textContent||'').toLowerCase(); if(t.includes(txt)){ sel.value=opts[i].value; sel.dispatchEvent(new Event('change',{bubbles:true})); return true; } } return false; }
        function findByLabelTextContains(text){ text=text.toLowerCase(); var labels=document.querySelectorAll('label'); for(var i=0;i<labels.length;i++){ var L=labels[i]; var t=(L.textContent||'').toLowerCase(); if(t.includes(text)){ var f=L.getAttribute('for'); if(f){ var el=document.getElementById(f); if(el) return el; } var next=L.parentElement && L.parentElement.querySelector('input,select'); if(next) return next; } } return null; }
        function setDateInput(el, val){ if(!el) return false; el.value=val; el.setAttribute('value', val); el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true})); return true; }
        function fmt(d){ var dd=('0'+d.getDate()).slice(-2); var mm=('0'+(d.getMonth()+1)).slice(-2); var yyyy=d.getFullYear(); return dd+'.'+mm+'.'+yyyy; }

        window.__af_clickLogin = clickLogin; // exposed for toolbar action
        window.__af_fillAttendance = function(){
          // Try to click the Attendance tab if visible
          var links=document.querySelectorAll('a, button');
          for(var i=0;i<links.length;i++){
            var t=(links[i].innerText||'').trim().toLowerCase();
            if(t.includes('attendance display for students')){ links[i].click(); break; }
          }
          // Try to fill the form (works when on the report page)
          var selects=document.querySelectorAll('select');
          if(selects && selects.length){
            // Heuristic: first three selects are Academic Year, Term, Detail
            selectByTextLike(selects[0], '2025-2026');
            if(selects.length>1) selectByTextLike(selects[1], 'semester i');
            if(selects.length>2) selectByTextLike(selects[2], 'detail report');
          }
          var start = findByLabelTextContains('start date') || document.querySelector('input[id*="start" i],input[name*="start" i]');
          var end   = findByLabelTextContains('end date')   || document.querySelector('input[id*="end" i],input[name*="end" i]');
          var today = fmt(new Date());
          if(end) setDateInput(end, today);
          return 'filled';
        };
        window.__af_submitAttendance = function(){
          var btns=document.querySelectorAll('button,input[type=button],input[type=submit]');
          for(var i=0;i<btns.length;i++){
            var t=(btns[i].innerText||btns[i].value||'').toLowerCase();
            if(t.includes('submit')){ btns[i].click(); return true; }
          }
          return false;
        };
        // Autofill user/pass and focus login area
        var tries=0; var timer=setInterval(function(){
          tries++;
          var u=findUser(), p=findPass();
          if(u && p){ setVal(u, '__USER__'); setVal(p,'__PASS__'); focusCaptcha(); focusLoginPanel(); clearInterval(timer); }
          if(tries>50){ clearInterval(timer); }
        }, 100);
        return 'started';
      })();
    """.replaceAll('__USER__', u).replaceAll('__PASS__', p);
    try {
      await _controller.runJavaScriptReturningResult(base);
      if (submit) {
        final submitJs = """
          (function(){ if(window.__af_clickLogin){ return window.__af_clickLogin(); } return false; })();
        """;
        await _controller.runJavaScriptReturningResult(submitJs);
      }
    } catch (_) {}
  }

  Future<void> _gotoAttendanceAndFill() async {
    const js = """
      (function(){ if(window.__af_fillAttendance){ return window.__af_fillAttendance(); } return 'no-func'; })();
    """;
    try { await _controller.runJavaScriptReturningResult(js); } catch (_) {}
  }

  Future<void> _submitAttendance() async {
    const js = """
      (function(){ if(window.__af_submitAttendance){ return window.__af_submitAttendance(); } return 'no-func'; })();
    """;
    try { await _controller.runJavaScriptReturningResult(js); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Online Check'),
        actions: [
          IconButton(
            tooltip: 'Autofill credentials',
            onPressed: () => _autofillCreds(submit: false),
            icon: const Icon(Icons.key),
          ),
          IconButton(
            tooltip: 'Autofill and submit',
            onPressed: () => _autofillCreds(submit: true),
            icon: const Icon(Icons.login),
          ),
          IconButton(
            tooltip: 'Go to Attendance & fill',
            onPressed: _gotoAttendanceAndFill,
            icon: const Icon(Icons.assignment),
          ),
          IconButton(
            tooltip: 'Submit form',
            onPressed: _submitAttendance,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('Tip: Type the captcha shown on the site, then tap the Login icon above.', textAlign: TextAlign.center),
      ),
    );
  }
}

// Windows-specific implementation using webview_windows
// Uses the same autofill JS but via executeScript

class OnlineCheckPageWindows extends StatefulWidget {
  final Uri url;
  final String username;
  final String password;
  const OnlineCheckPageWindows({super.key, required this.url, required this.username, required this.password});

  @override
  State<OnlineCheckPageWindows> createState() => _OnlineCheckPageWindowsState();
}

// ==============================
// Hidden automation (Mobile)
// ==============================
class OnlineFetchPdfPage extends StatefulWidget {
  final Uri url;
  final String username;
  final String password;
  const OnlineFetchPdfPage({super.key, required this.url, required this.username, required this.password});

  @override
  State<OnlineFetchPdfPage> createState() => _OnlineFetchPdfPageState();
}

class _OnlineFetchPdfPageState extends State<OnlineFetchPdfPage> {
  late final WebViewController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('PDF', onMessageReceived: (msg) async {
        try {
          final b64 = msg.message;
          final bytes = base64Decode(b64);
          if (!mounted) return;
          Navigator.of(context).pop(bytes);
        } catch (_) {}
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            if (!_started) {
              _started = true;
              await _injectAutomation();
            }
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  String _escapeJs(String s) => s.replaceAll('\\', r'\\').replaceAll("'", r"\'");

  Future<void> _injectAutomation() async {
    final u = _escapeJs(widget.username);
    final p = _escapeJs(widget.password);
    final js = _automationJs(u, p);
    try { await _controller.runJavaScriptReturningResult(js); } catch (_) {}
  }

  String _automationJs(String user, String pass) {
    return """
      (function(){
        // Utils
        function arrayBufferToBase64(buffer){ var binary=''; var bytes=new Uint8Array(buffer); var len=bytes.byteLength; for(var i=0;i<len;i++){ binary+=String.fromCharCode(bytes[i]); } return btoa(binary); }
        function postPDF(b64){ try{ PDF.postMessage(b64); }catch(e){} }
        // Hook creators
        (function(){ if(window.__af_hooks) return; window.__af_hooks=true;
          const ofetch = window.fetch; window.fetch = async function(){ const res = await ofetch.apply(this, arguments); try{ const ct = (res.headers.get('content-type')||'').toLowerCase(); if(ct.includes('pdf')){ const buf = await res.clone().arrayBuffer(); postPDF(arrayBufferToBase64(buf)); } }catch(e){} return res; };
          const oopen = window.open; window.open = function(url){ try{ fetch(url,{credentials:'include'}).then(r=>r.arrayBuffer()).then(b=>postPDF(arrayBufferToBase64(b))); }catch(e){} return null; };
        })();

        // Login helpers
        function setVal(el, val){ try{ el.focus(); el.value=val; el.setAttribute('value', val); el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true})); return true; }catch(e){ return false; } }
        function findUser(){ var sels=['#j_username','#logonuidfield','#userid','#username','#sap-user','input[name=j_username]','input[name=username]','input[name=userid]','input[id*=user]','input[name*=user]','input[type=email]']; for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el) return el; } var inputs=document.querySelectorAll('input'); for(var i=0;i<inputs.length;i++){ var el=inputs[i]; var t=(el.type||'').toLowerCase(); var n=(el.name||'').toLowerCase(); var id=(el.id||'').toLowerCase(); if(t==='text'||t==='email'){ if(n.includes('user')||id.includes('user')||n.includes('uid')||id.includes('uid')||n.includes('login')||id.includes('login')) return el; } } return null; }
        function findPass(){ var sels=['#j_password','#logonpassfield','#password','#sap-password','input[name=j_password]','input[name=password]','input[id*=pass]']; for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el && (el.type||'').toLowerCase()==='password') return el; } var inputs=document.querySelectorAll('input[type=password], input[id*=pass], input[name*=pass]'); if(inputs.length>0) return inputs[0]; return null; }
  function clickLogin(){ var sels=['#logonButton','button[type=submit]','input[type=submit]','button[id*=logon]','button[name*=logon]','button[id*=login]','button[name*=login]']; for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el){ el.click(); return true; } } var forms=document.querySelectorAll('form'); if(forms.length>0){ forms[0].submit(); return true; } return false; }
        function focusCaptcha(){ var cap=document.querySelector('#captcha, input[name=captcha], #logonCaptcha, input[id*=captcha], input[name*=captcha]'); if(cap){ cap.focus(); return true; } return false; }

        function selectByTextLike(sel, txt){ if(!sel) return false; txt=(txt||'').toLowerCase(); var opts=sel.options||[]; for(var i=0;i<opts.length;i++){ var t=(opts[i].textContent||'').toLowerCase(); if(t.includes(txt)){ sel.value=opts[i].value; sel.dispatchEvent(new Event('change',{bubbles:true})); return true; } } return false; }
        function findByLabelTextContains(text){ text=(text||'').toLowerCase(); var labels=document.querySelectorAll('label'); for(var i=0;i<labels.length;i++){ var L=labels[i]; var t=(L.textContent||'').toLowerCase(); if(t.includes(text)){ var f=L.getAttribute('for'); if(f){ var el=document.getElementById(f); if(el) return el; } var next=L.parentElement && L.parentElement.querySelector('input,select'); if(next) return next; } } return null; }
        function setDateInput(el, val){ if(!el) return false; el.value=val; el.setAttribute('value', val); el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true})); return true; }
        function fmt(d){ var dd=('0'+d.getDate()).slice(-2); var mm=('0'+(d.getMonth()+1)).slice(-2); var yyyy=d.getFullYear(); return dd+'.'+mm+'.'+yyyy; }

        // Autofill login; user will type captcha and tap Login icon from the app bar
        var tries=0; var loginTimer=setInterval(function(){ tries++; var u=findUser(), p=findPass(); if(u&&p){ setVal(u,'""" + user + """'); setVal(p,'""" + pass + """'); focusCaptcha(); } if(tries>50){ clearInterval(loginTimer); } }, 120);

        // Expose actions so Flutter toolbar buttons can control the flow
        window.__af_loginNow = clickLogin;
        window.__af_goAttendanceAndFill = function(){
          var links=document.querySelectorAll('a, button');
          for(var i=0;i<links.length;i++){ var t=(links[i].innerText||'').trim().toLowerCase(); if(t.includes('attendance display for students')){ links[i].click(); break; } }
          setTimeout(fillAndSubmit, 800);
          return true;
        };

  // After login, we can either auto-detect or user can trigger via toolbar
  function goAttendance(){ var links=document.querySelectorAll('a, button'); for(var i=0;i<links.length;i++){ var t=(links[i].innerText||'').trim().toLowerCase(); if(t.includes('attendance display for students')){ links[i].click(); return true; } } return false; }
  function closeDialogs(){ try{ var btns=document.querySelectorAll('button, input[type=button], input[type=submit], a'); var keys=['ok','yes','proceed','confirm']; for(var i=0;i<btns.length;i++){ var txt=(btns[i].innerText||btns[i].value||'').toLowerCase(); for(var k=0;k<keys.length;k++){ if(txt.includes(keys[k])){ var node=btns[i]; var depth=0; var isDialog=false; while(node && depth<6){ var role=(node.getAttribute && node.getAttribute('role'))||''; var al=(node.getAttribute && node.getAttribute('aria-label'))||''; var ll=(node.getAttribute && node.getAttribute('aria-labelledby'))||''; var it=(node.innerText||'').toLowerCase(); if((role||'').toLowerCase()==='dialog' || it.includes('re-confirmation') || (al||'').toLowerCase().includes('confirm') || (ll||'').toLowerCase().includes('confirm')){ isDialog=true; break; } node=node.parentElement; depth++; }
            if(isDialog){ try{ btns[i].click(); }catch(e){} }
          }
        }
      }
    }catch(e){}
  }
  var at=0; var attTimer=setInterval(function(){ at++; try{ closeDialogs(); }catch(e){} if(goAttendance()){ clearInterval(attTimer); setTimeout(fillAndSubmit, 1200); } if(at>240){ clearInterval(attTimer);} }, 500);

        function fillAndSubmit(){
          var selects=document.querySelectorAll('select');
          if(selects && selects.length){ selectByTextLike(selects[0],'2025-2026'); if(selects.length>1) selectByTextLike(selects[1],'semester i'); if(selects.length>2) selectByTextLike(selects[2],'detail report'); }
          var end = findByLabelTextContains('end date') || document.querySelector('input[id*="end" i],input[name*="end" i]');
          setDateInput(end, fmt(new Date()));
          var btns=document.querySelectorAll('button,input[type=button],input[type=submit]');
          for(var i=0;i<btns.length;i++){ var t=(btns[i].innerText||btns[i].value||'').toLowerCase(); if(t.includes('submit')){ btns[i].click(); return; } }
        }

        return 'ok';
      })();
    """;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to portal'),
        actions: [
          IconButton(
            tooltip: 'Autofill user/pass',
            icon: const Icon(Icons.key),
            onPressed: () => _controller.runJavaScriptReturningResult('(function(){return 1;})();'), // already autofilled via script
          ),
          IconButton(
            tooltip: 'Login (after captcha)',
            icon: const Icon(Icons.login),
            onPressed: () async { try { await _controller.runJavaScriptReturningResult('(function(){return window.__af_loginNow && window.__af_loginNow();})();'); } catch (_) {} },
          ),
          IconButton(
            tooltip: 'Go to Attendance & Fill',
            icon: const Icon(Icons.assignment),
            onPressed: () async { try { await _controller.runJavaScriptReturningResult('(function(){return window.__af_goAttendanceAndFill && window.__af_goAttendanceAndFill();})();'); } catch (_) {} },
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('Type the captcha on the page, then tap the Login icon. The app will fetch and parse your attendance automatically.'),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

// ==============================
// Hidden automation (Windows)
// ==============================
class OnlineFetchPdfPageWindows extends StatefulWidget {
  final Uri url;
  final String username;
  final String password;
  const OnlineFetchPdfPageWindows({super.key, required this.url, required this.username, required this.password});

  @override
  State<OnlineFetchPdfPageWindows> createState() => _OnlineFetchPdfPageWindowsState();
}

class _OnlineFetchPdfPageWindowsState extends State<OnlineFetchPdfPageWindows> {
  final _controller = wvw.WebviewController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    () async {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(wvw.WebviewPopupWindowPolicy.deny);
      _controller.webMessage.listen((message) async {
        try {
          // Expect a base64 string for PDF
          final String b64 = message;
          final bytes = base64Decode(b64);
          if (!mounted) return;
          Navigator.of(context).pop(bytes);
        } catch (_) {}
      });
      _controller.url.listen((_) async {
        if (_ready) {
          await _injectAutomation();
        }
      });
      await _controller.loadUrl(widget.url.toString());
      setState(() { _ready = true; });
      await _injectAutomation();
    }();
  }

  String _escapeJs(String s) => s.replaceAll('\\', r'\\').replaceAll("'", r"\'");

  Future<void> _injectAutomation() async {
    final u = _escapeJs(widget.username);
    final p = _escapeJs(widget.password);
    final js = _automationJs(u, p);
    try { await _controller.executeScript(js); } catch (_) {}
  }

  String _automationJs(String user, String pass) {
    return """
      (function(){
        function arrayBufferToBase64(buffer){ var binary=''; var bytes=new Uint8Array(buffer); var len=bytes.byteLength; for(var i=0;i<len;i++){ binary+=String.fromCharCode(bytes[i]); } return btoa(binary); }
        function postPDF(b64){ try{ window.chrome.webview.postMessage(b64); }catch(e){} }
        (function(){ if(window.__af_hooks) return; window.__af_hooks=true;
          const ofetch = window.fetch; window.fetch = async function(){ const res = await ofetch.apply(this, arguments); try{ const ct=(res.headers.get('content-type')||'').toLowerCase(); if(ct.includes('pdf')){ const buf=await res.clone().arrayBuffer(); postPDF(arrayBufferToBase64(buf)); } }catch(e){} return res; };
          const oopen = window.open; window.open = function(url){ try{ fetch(url,{credentials:'include'}).then(r=>r.arrayBuffer()).then(b=>postPDF(arrayBufferToBase64(b))); }catch(e){} return null; };
        })();

        function setVal(el, val){ try{ el.focus(); el.value=val; el.setAttribute('value', val); el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true})); return true; }catch(e){ return false; } }
        function findUser(){ var sels=['#j_username','#logonuidfield','#userid','#username','#sap-user','input[name=j_username]','input[name=username]','input[name=userid]','input[id*=user]','input[name*=user]','input[type=email]']; for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el) return el; } var inputs=document.querySelectorAll('input'); for(var i=0;i<inputs.length;i++){ var el=inputs[i]; var t=(el.type||'').toLowerCase(); var n=(el.name||'').toLowerCase(); var id=(el.id||'').toLowerCase(); if(t==='text'||t==='email'){ if(n.includes('user')||id.includes('user')||n.includes('uid')||id.includes('uid')||n.includes('login')||id.includes('login')) return el; } } return null; }
        function findPass(){ var sels=['#j_password','#logonpassfield','#password','#sap-password','input[name=j_password]','input[name=password]','input[id*=pass]']; for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el && (el.type||'').toLowerCase()==='password') return el; } var inputs=document.querySelectorAll('input[type=password], input[id*=pass], input[name*=pass]'); if(inputs.length>0) return inputs[0]; return null; }
        function clickLogin(){ var sels=['#logonButton','button[type=submit]','input[type=submit]','button[id*=logon]','button[name*=logon]','button[id*=login]','button[name*=login]']; for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el){ el.click(); return true; } } var forms=document.querySelectorAll('form'); if(forms.length>0){ forms[0].submit(); return true; } return false; }
        function focusCaptcha(){ var cap=document.querySelector('#captcha, input[name=captcha], #logonCaptcha, input[id*=captcha], input[name*=captcha]'); if(cap){ cap.focus(); return true; } return false; }
        function selectByTextLike(sel, txt){ if(!sel) return false; txt=(txt||'').toLowerCase(); var opts=sel.options||[]; for(var i=0;i<opts.length;i++){ var t=(opts[i].textContent||'').toLowerCase(); if(t.includes(txt)){ sel.value=opts[i].value; sel.dispatchEvent(new Event('change',{bubbles:true})); return true; } } return false; }
        function findByLabelTextContains(text){ text=(text||'').toLowerCase(); var labels=document.querySelectorAll('label'); for(var i=0;i<labels.length;i++){ var L=labels[i]; var t=(L.textContent||'').toLowerCase(); if(t.includes(text)){ var f=L.getAttribute('for'); if(f){ var el=document.getElementById(f); if(el) return el; } var next=L.parentElement && L.parentElement.querySelector('input,select'); if(next) return next; } } return null; }
        function setDateInput(el, val){ if(!el) return false; el.value=val; el.setAttribute('value', val); el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true})); return true; }
        function fmt(d){ var dd=('0'+d.getDate()).slice(-2); var mm=('0'+(d.getMonth()+1)).slice(-2); var yyyy=d.getFullYear(); return dd+'.'+mm+'.'+yyyy; }

        // Autofill only; user taps Login from toolbar after captcha
        var tries=0; var loginTimer=setInterval(function(){ tries++; var u=findUser(), p=findPass(); if(u&&p){ setVal(u,'""" + user + """'); setVal(p,'""" + pass + """'); focusCaptcha(); } if(tries>50){ clearInterval(loginTimer); } }, 120);
        window.__af_loginNow = clickLogin;
        window.__af_goAttendanceAndFill = function(){ var links=document.querySelectorAll('a, button'); for(var i=0;i<links.length;i++){ var t=(links[i].innerText||'').trim().toLowerCase(); if(t.includes('attendance display for students')){ links[i].click(); break; } } setTimeout(fillAndSubmit, 800); return true; };

  function goAttendance(){ var links=document.querySelectorAll('a, button'); for(var i=0;i<links.length;i++){ var t=(links[i].innerText||'').trim().toLowerCase(); if(t.includes('attendance display for students')){ links[i].click(); return true; } } return false; }
  function closeDialogs(){ try{ var btns=document.querySelectorAll('button, input[type=button], input[type=submit], a'); var keys=['ok','yes','proceed','confirm']; for(var i=0;i<btns.length;i++){ var txt=(btns[i].innerText||btns[i].value||'').toLowerCase(); for(var k=0;k<keys.length;k++){ if(txt.includes(keys[k])){ var node=btns[i]; var depth=0; var isDialog=false; while(node && depth<6){ var role=(node.getAttribute && node.getAttribute('role'))||''; var al=(node.getAttribute && node.getAttribute('aria-label'))||''; var ll=(node.getAttribute && node.getAttribute('aria-labelledby'))||''; var it=(node.innerText||'').toLowerCase(); if((role||'').toLowerCase()==='dialog' || it.includes('re-confirmation') || (al||'').toLowerCase().includes('confirm') || (ll||'').toLowerCase().includes('confirm')){ isDialog=true; break; } node=node.parentElement; depth++; } if(isDialog){ try{ btns[i].click(); }catch(e){} } } } } }catch(e){} }
  var at=0; var attTimer=setInterval(function(){ at++; try{ closeDialogs(); }catch(e){} if(goAttendance()){ clearInterval(attTimer); setTimeout(fillAndSubmit, 1200); } if(at>240){ clearInterval(attTimer);} }, 500);

        function fillAndSubmit(){
          var selects=document.querySelectorAll('select');
          if(selects && selects.length){ selectByTextLike(selects[0],'2025-2026'); if(selects.length>1) selectByTextLike(selects[1],'semester i'); if(selects.length>2) selectByTextLike(selects[2],'detail report'); }
          var end = findByLabelTextContains('end date') || document.querySelector('input[id*="end" i],input[name*="end" i]');
          setDateInput(end, fmt(new Date()));
          var btns=document.querySelectorAll('button,input[type=button],input[type=submit]');
          for(var i=0;i<btns.length;i++){ var t=(btns[i].innerText||btns[i].value||'').toLowerCase(); if(t.includes('submit')){ btns[i].click(); return; } }
        }
        return 'ok';
      })();
    """;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to portal'),
        actions: [
          IconButton(
            tooltip: 'Login (after captcha)',
            icon: const Icon(Icons.login),
            onPressed: () async { try { await _controller.executeScript('(function(){return window.__af_loginNow && window.__af_loginNow();})();'); } catch (_) {} },
          ),
          IconButton(
            tooltip: 'Go to Attendance & Fill',
            icon: const Icon(Icons.assignment),
            onPressed: () async { try { await _controller.executeScript('(function(){return window.__af_goAttendanceAndFill && window.__af_goAttendanceAndFill();})();'); } catch (_) {} },
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('Type the captcha on the page, then tap the Login icon. The app will fetch and parse your attendance automatically.'),
          ),
          Expanded(child: wvw.Webview(_controller)),
        ],
      ),
    );
  }
}

class _OnlineCheckPageWindowsState extends State<OnlineCheckPageWindows> {
  final _controller = wvw.WebviewController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    () async {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(wvw.WebviewPopupWindowPolicy.deny);
      _controller.url.listen((event) async {
        // attempt autofill when page changes
        if (_ready) {
          await _autofillCreds(submit: false);
          // Also try to reach and fill Attendance page after navigation
          await _gotoAttendanceAndFill();
        }
      });
      await _controller.loadUrl(widget.url.toString());
      setState(() { _ready = true; });
      await _autofillCreds(submit: false);
    }();
  }

  String _escapeJs(String s) => s.replaceAll('\\', r'\\').replaceAll("'", r"\'");

  Future<void> _autofillCreds({bool submit=false}) async {
    if (!_ready) return;
    final u = _escapeJs(widget.username);
    final p = _escapeJs(widget.password);
    final base = """
      (function(){
        function setVal(el, val){
          try{ el.focus(); el.value=val; el.setAttribute('value', val);
            el.dispatchEvent(new Event('input',{bubbles:true}));
            el.dispatchEvent(new Event('change',{bubbles:true}));
            el.dispatchEvent(new KeyboardEvent('keyup',{bubbles:true,key:'a'}));
            return true;
          }catch(e){ return false; }
        }
        function findUser(){
          var sels=['#j_username','#logonuidfield','#userid','#username','#USERNAME','#sap-user','input[name=j_username]','input[name=username]','input[name=userid]','input[name=USER]','input[id*=user]','input[name*=user]','input[placeholder*="User"]','input[placeholder*="ID"]','input[type=email]'];
          for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el) return el; }
          var inputs=document.querySelectorAll('input');
          for(var i=0;i<inputs.length;i++){
            var el=inputs[i]; var n=(el.name||'').toLowerCase(); var id=(el.id||'').toLowerCase(); var ph=(el.placeholder||'').toLowerCase(); var t=(el.type||'').toLowerCase();
            if(t==='text'||t==='email'||t==='tel'){
              if(n.includes('user')||n.includes('uid')||n.includes('login')||id.includes('user')||id.includes('uid')||id.includes('login')||ph.includes('user')||ph.includes('id')||ph.includes('email')) return el;
            }
          }
          return null;
        }
        function findPass(){
          var sels=['#j_password','#logonpassfield','#password','#sap-password','input[name=j_password]','input[name=password]','input[id*=pass]'];
          for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el && (el.type||'').toLowerCase()==='password') return el; }
          var inputs=document.querySelectorAll('input[type=password], input[id*=pass], input[name*=pass]');
          if(inputs.length>0) return inputs[0];
          return null;
        }
        function clickLogin(){
          var sels=['#logonButton','button[type=submit]','input[type=submit]','button[id*=logon]','button[name*=logon]','button[id*=login]','button[name*=login]'];
          for(var i=0;i<sels.length;i++){ var el=document.querySelector(sels[i]); if(el){ el.click(); return true; }}
          var forms=document.querySelectorAll('form'); if(forms.length>0){ forms[0].submit(); return true; }
          return false;
        }
        function focusCaptcha(){ var cap=document.querySelector('#captcha, input[name=captcha], #logonCaptcha, input[id*=captcha], input[name*=captcha]'); if(cap){ cap.focus(); return true; } return false; }
        window.__af_clickLogin = clickLogin;
        var tries=0; var timer=setInterval(function(){
          tries++;
          var u=findUser(), p=findPass();
          if(u && p){ setVal(u, '__USER__'); setVal(p,'__PASS__'); focusCaptcha(); clearInterval(timer); }
          if(tries>50){ clearInterval(timer); }
        }, 100);
        return 'started';
      })();
    """.replaceAll('__USER__', u).replaceAll('__PASS__', p);
    try {
      await _controller.executeScript(base);
      if (submit) {
        final submitJs = """
          (function(){ if(window.__af_clickLogin){ return window.__af_clickLogin(); } return false; })();
        """;
        await _controller.executeScript(submitJs);
      }
    } catch(_) {}
  }

  Future<void> _gotoAttendanceAndFill() async {
    const js = """
      (function(){ if(window.__af_fillAttendance){ return window.__af_fillAttendance(); } return 'no-func'; })();
    """;
    try { await _controller.executeScript(js); } catch (_) {}
  }

  Future<void> _submitAttendance() async {
    const js = """
      (function(){ if(window.__af_submitAttendance){ return window.__af_submitAttendance(); } return 'no-func'; })();
    """;
    try { await _controller.executeScript(js); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Online Check (Windows)'),
        actions: [
          IconButton(onPressed: ()=>_autofillCreds(submit:false), icon: const Icon(Icons.key)),
          IconButton(onPressed: ()=>_autofillCreds(submit:true), icon: const Icon(Icons.login)),
          IconButton(onPressed: _gotoAttendanceAndFill, tooltip: 'Go to Attendance & fill', icon: const Icon(Icons.assignment)),
          IconButton(onPressed: _submitAttendance, tooltip: 'Submit form', icon: const Icon(Icons.send)),
        ],
      ),
      body: _ready ? wvw.Webview(_controller) : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('Enter the captcha shown on the site, then tap Login.', textAlign: TextAlign.center),
      ),
    );
  }
}

class AttendanceHome extends StatefulWidget {
  const AttendanceHome({super.key});

  @override
  State<AttendanceHome> createState() => AttendanceHomeState();
}

class AttendanceHomeState extends State<AttendanceHome>
    with SingleTickerProviderStateMixin {
  // Expose a static callback for NotificationService to update counters
  static void Function(String subject, int typeIndex, bool present)?
      onNotificationMarkAttendance;

  String? fileName;
  static const double threshold = 80.0; // fixed target
  bool isLoading = false;
  double? overallPercentage;
  int? totalClasses, attendedClasses, missable;
  Map<String, List<String>> subjectData = {};

  // Simple counters updated by notifications (kept in-memory)
  final Map<String, SubjectCounters> counters = {};

  // Group selection (C1/C2)
  String? group; // null until chosen

  late AnimationController _controller;

  /// Fixed totals for missable calculation
  final Map<String, int> fixedTotals = {
    "Calculus": 60,
    "Physics": 75,
    "Computational Thinking for Problem Solving": 75,
    "Elements of Biology": 45,
    "Engineering Graphics and Design": 45,
    "Engineering Ethics": 15,
    "Indian Knowledge System": 15,
    "Environmental Studies": 15,
    "Essential Electronic Practices": 30,
  };

  /// Ask user for username and password (captcha typed in site later)
  Future<(String,String)?> _askCredentials(BuildContext context) async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final res = await showDialog<(String,String)?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter portal credentials'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: userCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v)=> (v==null||v.isEmpty)?'Required':null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v)=> (v==null||v.isEmpty)?'Required':null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: ()=> Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: (){
              if(formKey.currentState!.validate()){
                Navigator.pop(context, (userCtrl.text.trim(), passCtrl.text));
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return res;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    // Wire notification callback to update local counters
    onNotificationMarkAttendance = (subject, typeIndex, present) {
      final type = SessionType.values[typeIndex];
      final normalized = normalizeSubject(subject);
      counters.putIfAbsent(normalized, () => SubjectCounters(normalized));
      counters[normalized]!.increment(type, present: present);
      _recomputeFromCounters();
    };
  }

  // Removed old duplicate prompt method (was pushing the mobile WebView on Windows)

  @override
  void dispose() {
    _controller.dispose();
    if (onNotificationMarkAttendance == onNotificationMarkAttendance) {
      onNotificationMarkAttendance = null;
    }
    super.dispose();
  }

  String normalizeSubject(String raw) {
    String subject = raw
        .replaceAll(
            RegExp(r'(T4|P4|U4|C1|CE|Sem I|Div C|Batch \d+)',
                caseSensitive: false),
            '')
        .trim();

    if (subject.toUpperCase().contains("COMPUTATIONAL THINKING")) {
      return "Computational Thinking for Problem Solving";
    } else if (subject.toUpperCase().contains("BIOLOGY")) {
      return "Elements of Biology";
    } else if (subject.toUpperCase().contains("GRAPHICS")) {
      return "Engineering Graphics and Design";
    } else if (subject.toUpperCase().contains("ELECTRONIC")) {
      return "Essential Electronic Practices";
    } else if (subject.toUpperCase().contains("ENGINEERING ETHICS")) {
      return "Engineering Ethics";
    } else if (subject.toUpperCase().contains("INDIAN KNOWLEDGE")) {
      return "Indian Knowledge System";
    } else if (subject.toUpperCase().contains("ENVIRONMENTAL")) {
      return "Environmental Studies";
    } else if (subject.toUpperCase().contains("PHYSICS")) {
      return "Physics";
    } else if (subject.toUpperCase().contains("CALCULUS")) {
      return "Calculus";
    }
    return subject;
  }

  Future<void> processPdf() async {
    setState(() => isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        fileName = result.files.single.name;
        await _parseAttendancePdfBytes(result.files.single.bytes!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading PDF: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _parseAttendancePdfBytes(Uint8List bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String text = PdfTextExtractor(document).extractText();
      document.dispose();

      text = text.replaceAll('\n', ' ');
      final rowPattern = RegExp(
        r'(.+?)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}(?::\d{2})?\s[AP]M\s+\d{1,2}:\d{2}(?::\d{2})?\s[AP]M\s+(P|A)',
        caseSensitive: false,
      );

      Map<String, Map<String, Map<String, int>>> counts = {};

      for (final match in rowPattern.allMatches(text)) {
        String rawSubject = match.group(1)!.trim();
        String status = match.group(3)!.trim().toUpperCase();

        String subject = normalizeSubject(rawSubject);

        String type;
        final upper = rawSubject.toUpperCase();
        if (upper.contains('U4')) {
          type = 'Tutorial';
        } else if (upper.contains('P4') || upper.contains('BATCH')) {
          type = 'Practical';
        } else {
          type = 'Theory';
        }

        counts.putIfAbsent(subject, () => {
              'Theory': {'T': 0, 'P': 0},
              'Tutorial': {'T': 0, 'P': 0},
              'Practical': {'T': 0, 'P': 0},
            });

        counts[subject]![type]!['T'] =
            (counts[subject]![type]!['T'] ?? 0) + 1;
        if (status == 'P') {
          counts[subject]![type]!['P'] =
              (counts[subject]![type]!['P'] ?? 0) + 1;
        }
      }

      subjectData.clear();
      int total = 0, attended = 0;
      counts.forEach((subject, data) {
        int subTotal = (data['Theory']!['T'] ?? 0) +
            (data['Tutorial']!['T'] ?? 0) +
            (data['Practical']!['T'] ?? 0);
        int subAttended = (data['Theory']!['P'] ?? 0) +
            (data['Tutorial']!['P'] ?? 0) +
            (data['Practical']!['P'] ?? 0);
        total += subTotal;
        attended += subAttended;

        int fixedTotal = fixedTotals[subject] ?? subTotal;
        int allowedAbsences = (0.2 * fixedTotal).floor();
        int missed = subTotal - subAttended;
        int canMiss = (allowedAbsences - missed);
        if (canMiss < 0) canMiss = 0;

        int classesRemaining = (fixedTotal - subTotal);
        if (classesRemaining < 0) classesRemaining = 0;

        List<String> details = [];
        if ((data['Theory']!['T'] ?? 0) > 0) {
          details.add(
              'Theory: ${data['Theory']!['P'] ?? 0}/${data['Theory']!['T'] ?? 0}');
        }
        if ((data['Tutorial']!['T'] ?? 0) > 0) {
          details.add(
              'Tutorial: ${data['Tutorial']!['P'] ?? 0}/${data['Tutorial']!['T'] ?? 0}');
        }
        if ((data['Practical']!['T'] ?? 0) > 0) {
          details.add(
              'Practical: ${data['Practical']!['P'] ?? 0}/${data['Practical']!['T'] ?? 0}');
        }

        details.add('Total: $subAttended/$subTotal');
        details.add('You can miss: $canMiss classes');
        details.add('Classes Remaining: $classesRemaining');

        subjectData[subject] = details;

        // Seed counters from parsed data (so notifications continue from here)
        counters.putIfAbsent(subject, () => SubjectCounters(subject));
        final c = counters[subject]!;
        c.theoryTotal = data['Theory']!['T'] ?? c.theoryTotal;
        c.theoryAttended = data['Theory']!['P'] ?? c.theoryAttended;
        c.tutorialTotal = data['Tutorial']!['T'] ?? c.tutorialTotal;
        c.tutorialAttended = data['Tutorial']!['P'] ?? c.tutorialAttended;
        c.practicalTotal = data['Practical']!['T'] ?? c.practicalTotal;
        c.practicalAttended = data['Practical']!['P'] ?? c.practicalAttended;
      });

      // Overall metrics & daily missable (current trajectory)
      final overall = total == 0 ? 0.0 : (attended / total) * 100.0;
      final canMissOverall =
          classesYouCanSkip(attended: attended, total: total, thresholdPct: threshold);

      setState(() {
        totalClasses = total;
        attendedClasses = attended;
        overallPercentage = overall;
        missable = canMissOverall > 0 ? canMissOverall : 0;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing PDF: $e')),
      );
    }
  }

  void _recomputeFromCounters() {
    int total = 0, attended = 0;
    subjectData.clear();

    for (final entry in counters.entries) {
      final subject = entry.key;
      final c = entry.value;
      final subTotal = c.totalAll();
      final subAttended = c.attendedAll();
      total += subTotal;
      attended += subAttended;

      final fixedTotal = fixedTotals[subject] ?? subTotal;
      final allowedAbsences = (0.2 * fixedTotal).floor();
      final missed = subTotal - subAttended;
      final canMiss = math.max(0, allowedAbsences - missed);
      final classesRemaining = math.max(0, fixedTotal - subTotal);

      final details = <String>[];
      if (c.theoryTotal > 0) {
        details.add('Theory: ${c.theoryAttended}/${c.theoryTotal}');
      }
      if (c.tutorialTotal > 0) {
        details.add('Tutorial: ${c.tutorialAttended}/${c.tutorialTotal}');
      }
      if (c.practicalTotal > 0) {
        details.add('Practical: ${c.practicalAttended}/${c.practicalTotal}');
      }
      details
        ..add('Total: $subAttended/$subTotal')
        ..add('You can miss: $canMiss classes')
        ..add('Classes Remaining: $classesRemaining');

      subjectData[subject] = details;
    }

    final overall = total == 0 ? 0.0 : (attended / total) * 100.0;
    final canMissOverall =
        classesYouCanSkip(attended: attended, total: total, thresholdPct: threshold);

    setState(() {
      totalClasses = total;
      attendedClasses = attended;
      overallPercentage = overall;
      missable = canMissOverall > 0 ? canMissOverall : 0;
    });
  }

  // == Attendance math helpers ==
  int classesYouCanSkip({
    required int attended,
    required int total,
    required double thresholdPct,
  }) {
    final p = thresholdPct / 100.0;
    if (total <= 0 || p <= 0) return 0;
    final k = (attended / p - total).floor(); // k ≤ attended/p - total
    return k > 0 ? k : 0;
  }

  // == Timetable + scheduling ==
  Future<void> _chooseGroupAndSchedule() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Your Group (Div-C)'),
        content: const Text('Choose your lab/tutorial group'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'C1'), child: const Text('C1')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'C2'), child: const Text('C2')),
        ],
      ),
    );
    if (chosen == null) return;

    setState(() => group = chosen);

    final entries = buildDivCTimetable(group: chosen);
    await NotificationService.scheduleDaily(entries);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Scheduled daily notifications for $chosen.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: overallPercentage == null
            ? Stack(
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: DiagonalLinesPainter(_controller.value),
                        child: Container(color: Colors.blue[700]),
                      );
                    },
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Attendance Tracker',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: isLoading ? null : processPdf,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(isLoading ? 'Processing...' : 'Select Attendance PDF'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _chooseGroupAndSchedule,
                          icon: const Icon(Icons.group),
                          label: Text(group == null ? 'Choose Group (C1/C2) & Schedule' : 'Re-select Group & Re-schedule'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final creds = await _askCredentials(context);
                            if (creds == null) return;
                            if (!mounted) return;
                            final url = Uri.parse('https://sdc-sppap1.svkm.ac.in:50001/irj/portal');
                            Uint8List? pdfBytes;
                            if (Platform.isWindows) {
                              pdfBytes = await Navigator.of(context).push<Uint8List>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => OnlineFetchPdfPageWindows(
                                    url: url,
                                    username: creds.$1,
                                    password: creds.$2,
                                  ),
                                ),
                              );
                            } else {
                              pdfBytes = await Navigator.of(context).push<Uint8List>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => OnlineFetchPdfPage(
                                    url: url,
                                    username: creds.$1,
                                    password: creds.$2,
                                  ),
                                ),
                              );
                            }
                            if (pdfBytes != null) {
                              setState(() => isLoading = true);
                              await _parseAttendancePdfBytes(pdfBytes);
                              setState(() => isLoading = false);
                            }
                          },
                          icon: const Icon(Icons.public),
                          label: const Text('Check Online'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Text(
                              'Overall Attendance: ${overallPercentage!.toStringAsFixed(2)}%',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            LinearPercentIndicator(
                              lineHeight: 10,
                              percent: (overallPercentage! / 100).clamp(0.0, 1.0),
                              backgroundColor: Colors.grey[300],
                              progressColor: overallPercentage! >= threshold ? Colors.green : Colors.red,
                              animation: true,
                            ),
                            const SizedBox(height: 12),
                            Text('Total Classes: $totalClasses'),
                            Text('Attended: $attendedClasses'),
                            const SizedBox(height: 12),
                            const Row(
                              children: [
                                Text('Target: 80%'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: subjectData.entries.map((entry) {
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 3,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  ...entry.value.map((line) {
                                    if (line.startsWith('You can miss')) {
                                      return Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.green, width: 1),
                                        ),
                                        child: Text(
                                          line,
                                          style: TextStyle(
                                            color: Colors.green[800],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    } else if (line.startsWith('Classes Remaining')) {
                                      return Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue, width: 1),
                                        ),
                                        child: Text(
                                          line,
                                          style: TextStyle(
                                            color: Colors.blue[800],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    } else {
                                      return Text(line);
                                    }
                                  }),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isLoading ? null : () async {
                        setState(() {
                          fileName = null;
                          overallPercentage = null;
                          totalClasses = null;
                          attendedClasses = null;
                          missable = null;
                          subjectData.clear();
                        });
                        await processPdf();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(isLoading ? 'Processing...' : 'Upload Another PDF'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Painter (unchanged except minor efficiency)
class DiagonalLinesPainter extends CustomPainter {
  final double progress;
  DiagonalLinesPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.3)
      ..strokeWidth = 2;

    const double spacing = 40;
    final double offset = progress * spacing * 2;

    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
        Offset(i + offset, 0),
        Offset(i - size.height + offset, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DiagonalLinesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// ============================================
/// SUPPORTING TYPES FOR COUNTERS & TIMETABLE
/// ============================================

enum SessionType { theory, tutorial, practical }

class SubjectCounters {
  final String subject;
  int theoryTotal;
  int theoryAttended;
  int tutorialTotal;
  int tutorialAttended;
  int practicalTotal;
  int practicalAttended;

  SubjectCounters(this.subject)
      : theoryTotal = 0,
        theoryAttended = 0,
        tutorialTotal = 0,
        tutorialAttended = 0,
        practicalTotal = 0,
        practicalAttended = 0;

  void increment(SessionType type, {required bool present}) {
    switch (type) {
      case SessionType.theory:
        theoryTotal += 1;
        if (present) theoryAttended += 1;
        break;
      case SessionType.tutorial:
        tutorialTotal += 1;
        if (present) tutorialAttended += 1;
        break;
      case SessionType.practical:
        practicalTotal += 1;
        if (present) practicalAttended += 1;
        break;
    }
  }

  int totalAll() => theoryTotal + tutorialTotal + practicalTotal;
  int attendedAll() => theoryAttended + tutorialAttended + practicalAttended;
}

// Simple timetable entry used only for scheduling (Android)
class TimetableEntrySimple {
  final int weekday; // DateTime.weekday (1=Mon..7=Sun)
  final TimeOfDay start;
  final int durationMinutes; // 60 (lecture) / 120 (lab)
  final String subject;
  final int typeIndex; // 0 theory, 1 tutorial, 2 practical
  TimetableEntrySimple({
    required this.weekday,
    required this.start,
    required this.durationMinutes,
    required this.subject,
    required this.typeIndex,
  });
}

// Period start times (Div-C)
const p1 = TimeOfDay(hour: 9, minute: 15);
const p2 = TimeOfDay(hour: 10, minute: 15);
const p3 = TimeOfDay(hour: 11, minute: 15);
// P4 (Lunch): 12:15–1:00 (no schedule)
const p5 = TimeOfDay(hour: 13, minute: 0);
const p6 = TimeOfDay(hour: 14, minute: 0);
const p7 = TimeOfDay(hour: 15, minute: 0);

// Build Div-C timetable with confirmed mapping (theory common; tutorials/labs per group)
List<TimetableEntrySimple> buildDivCTimetable({required String group}) {
  final isC1 = group.trim().toUpperCase() == 'C1';
  final entries = <TimetableEntrySimple>[];

  // Monday (weekday=1)
  entries.addAll([
    TimetableEntrySimple(
      weekday: DateTime.monday,
      start: p1,
      durationMinutes: 60,
      subject: isC1 ? 'Calculus Tutorial' : 'Elements of Biology Tutorial',
      typeIndex: 1,
    ),
    TimetableEntrySimple(
      weekday: DateTime.monday,
      start: p2,
      durationMinutes: 60,
      subject: 'Engineering Graphics and Design',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.monday,
      start: p3,
      durationMinutes: 60,
      subject: 'Physics',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.monday,
      start: p5,
      durationMinutes: 60,
      subject: 'Elements of Biology',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.monday,
      start: p6,
      durationMinutes: 120, // P6–P7
      subject: isC1 ? 'Computational Thinking for Problem Solving Lab' : 'Physics Lab',
      typeIndex: 2,
    ),
  ]);

  // Tuesday (weekday=2)
  entries.addAll([
    TimetableEntrySimple(
      weekday: DateTime.tuesday,
      start: p1,
      durationMinutes: 120, // P1–P2
      subject: isC1 ? 'Engineering Graphics and Design Lab' : 'Essential Electronic Practices Lab',
      typeIndex: 2,
    ),
    TimetableEntrySimple(
      weekday: DateTime.tuesday,
      start: p3,
      durationMinutes: 60,
      subject: 'Library',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.tuesday,
      start: p5,
      durationMinutes: 60,
      subject: isC1 ? 'Elements of Biology Tutorial' : 'Calculus Tutorial',
      typeIndex: 1,
    ),
    TimetableEntrySimple(
      weekday: DateTime.tuesday,
      start: p6,
      durationMinutes: 60,
      subject: 'Computational Thinking for Problem Solving',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.tuesday,
      start: p7,
      durationMinutes: 60,
      subject: 'Physics',
      typeIndex: 0,
    ),
  ]);

  // Wednesday (weekday=3)
  entries.addAll([
    TimetableEntrySimple(
      weekday: DateTime.wednesday,
      start: p1,
      durationMinutes: 60,
      subject: 'Essential Electronic Practices',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.wednesday,
      start: p2,
      durationMinutes: 60,
      subject: 'Calculus',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.wednesday,
      start: p3,
      durationMinutes: 60,
      subject: 'Elements of Biology',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.wednesday,
      start: p5,
      durationMinutes: 60,
      subject: 'Computational Thinking for Problem Solving',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.wednesday,
      start: p6,
      durationMinutes: 60,
      subject: 'Physics',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.wednesday,
      start: p7,
      durationMinutes: 60,
      subject: 'Library',
      typeIndex: 0,
    ),
  ]);

  // Thursday (weekday=4)
  entries.addAll([
    TimetableEntrySimple(
      weekday: DateTime.thursday,
      start: p1,
      durationMinutes: 60,
      subject: 'Calculus',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.thursday,
      start: p2,
      durationMinutes: 60,
      subject: 'Library',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.thursday,
      start: p3,
      durationMinutes: 60,
      subject: 'Library',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.thursday,
      start: p5,
      durationMinutes: 60,
      subject: 'Computational Thinking for Problem Solving',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.thursday,
      start: p6,
      durationMinutes: 120, // P6–P7
      subject: isC1 ? 'Physics Lab' : 'Computational Thinking for Problem Solving Lab',
      typeIndex: 2,
    ),
  ]);

  // Friday (weekday=5)
  entries.addAll([
    TimetableEntrySimple(
      weekday: DateTime.friday,
      start: p1,
      durationMinutes: 60,
      subject: 'Environmental Studies',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.friday,
      start: p2,
      durationMinutes: 120, // P2–P3
      subject: isC1 ? 'Essential Electronic Practices Lab' : 'Engineering Graphics and Design Lab',
      typeIndex: 2,
    ),
    TimetableEntrySimple(
      weekday: DateTime.friday,
      start: p5,
      durationMinutes: 60,
      subject: 'Library',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.friday,
      start: p6,
      durationMinutes: 60,
      subject: 'Calculus',
      typeIndex: 0,
    ),
    TimetableEntrySimple(
      weekday: DateTime.friday,
      start: p7,
      durationMinutes: 60,
      subject: 'Indian Knowledge System',
      typeIndex: 0,
    ),
  ]);

  // Saturday intentionally omitted
  return entries;
}
