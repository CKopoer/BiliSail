import 'dart:convert';

final class PassportCaptchaProof {
  const PassportCaptchaProof(this.challenge, this.validate, this.seccode);
  final String challenge, validate, seccode;
}

enum PassportCaptchaEventKind {
  success,
  cancelled,
  configurationUnavailable,
  loadFailed,
}

final class PassportCaptchaEvent {
  const PassportCaptchaEvent(this.kind, {this.proof});
  final PassportCaptchaEventKind kind;
  final PassportCaptchaProof? proof;
}

final class PassportCaptchaException implements Exception {
  const PassportCaptchaException({this.configurationUnavailable = false});
  final bool configurationUnavailable;
}

PassportCaptchaEvent? parsePassportCaptchaEvent(String message) {
  if (message.length > 16384) return null;
  try {
    final Object? value = jsonDecode(message);
    if (value is! Map<String, Object?>) return null;
    switch (value['type']) {
      case 'success':
        final proof = parsePassportCaptchaProof(jsonEncode(value['proof']));
        return proof == null
            ? const PassportCaptchaEvent(PassportCaptchaEventKind.loadFailed)
            : PassportCaptchaEvent(
                PassportCaptchaEventKind.success,
                proof: proof,
              );
      case 'cancelled':
        return const PassportCaptchaEvent(PassportCaptchaEventKind.cancelled);
      case 'error':
        return PassportCaptchaEvent(
          value['code'] == 'configuration_unavailable'
              ? PassportCaptchaEventKind.configurationUnavailable
              : PassportCaptchaEventKind.loadFailed,
        );
    }
  } on FormatException {
    return null;
  }
  return null;
}

PassportCaptchaProof? parsePassportCaptchaProof(String message) {
  if (message.length > 16384) return null;
  try {
    final Object? data = jsonDecode(message);
    if (data is! Map<String, Object?>) return null;
    final challenge = data['geetest_challenge'],
        validate = data['geetest_validate'],
        seccode = data['geetest_seccode'];
    bool valid(Object? value) =>
        value is String &&
        value.isNotEmpty &&
        value.length <= 4096 &&
        !RegExp(r'[\r\n\x00]').hasMatch(value);
    if (valid(challenge) && valid(validate) && valid(seccode)) {
      return PassportCaptchaProof(
        challenge as String,
        validate as String,
        seccode as String,
      );
    }
  } on FormatException {
    return null;
  }
  return null;
}

bool passportCaptchaPageAllowsNavigation(String url, String html) {
  if (url == 'about:blank') return true;
  // WebView2 exposes NavigateToString as a data URL to its navigation delegate.
  // Permit only our own document, never an arbitrary data page with the bridge.
  if (!url.startsWith('data:') || url.length > html.length * 6 + 256) {
    return false;
  }
  try {
    final data = Uri.parse(url).data;
    return data != null &&
        data.mimeType == 'text/html' &&
        data.contentAsString(encoding: utf8) == html;
  } on FormatException {
    return false;
  }
}

String passportCaptchaHtml(String gt, String challenge) {
  String js(String value) => jsonEncode(value).replaceAll('<', r'\u003c');
  // Use the provider's supported numeric geetest_<timestamp> JSONP callback form.
  final callback = 'geetest_${DateTime.now().millisecondsSinceEpoch}';
  final configurationUrl = Uri.https('api.geetest.com', '/gettype.php', {
    'gt': gt,
    'callback': callback,
  });
  return '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src https: data: blob:; script-src https: 'unsafe-inline' 'unsafe-eval'; style-src https: 'unsafe-inline'; connect-src https:;">
</head><body><p id="status">正在加载验证码…</p><button id="retry" style="display:none" onclick="verify()">重新验证</button>
<script>
var libraryLoaded=false,configuration=null,captcha=null,settled=false;
function emit(event){
  if(settled)return;
  settled=true;
  window.BiliSailCaptcha.postMessage(JSON.stringify(event));
}
function fail(code){emit({type:'error',code:code||'load_failed'});}
function verify(){if(captcha&&!settled)captcha.verify();}
function initialize(){
  if(!libraryLoaded||!configuration||captcha||settled)return;
  try{
    var options=Object.assign({},configuration,{gt:${js(gt)},challenge:${js(challenge)},
      offline:false,new_captcha:true,product:'bind',width:'100%',https:true,protocol:'https://',lang:'zh-cn'});
    captcha=window.Geetest(options);
    captcha.onSuccess(function(){
      var proof=captcha.getValidate();
      if(proof)emit({type:'success',proof:proof});else fail('invalid_result');
    });
    captcha.onError(function(){fail('load_failed');});
    captcha.onClose(function(){emit({type:'cancelled'});});
    captcha.onReady(function(){
      document.getElementById('status').textContent='请完成人机验证';
      document.getElementById('retry').style.display='inline-block';
      verify();
    });
  }catch(e){fail('load_failed');}
}
function BiliSailCaptchaConfiguration(response){
  if(!response||response.status!=='success'||!response.data){
    fail(response&&response.error_code==='error_34'?'configuration_unavailable':'load_failed');
    return;
  }
  configuration=response.data;
  initialize();
}
function libraryReady(){libraryLoaded=true;initialize();}
window[${js(callback)}]=BiliSailCaptchaConfiguration;
</script><script src="https://static.geetest.com/static/js/fullpage.0.0.0.js" onload="libraryReady()" onerror="fail('load_failed')"></script>
<script src="${htmlEscape.convert(configurationUrl.toString())}" onerror="fail('load_failed')"></script>
</body></html>''';
}
