Có nhé — EA MT5 gửi noti Telegram rất ổn bằng Telegram Bot API (qua WebRequest).
Tóm tắt cách làm + code mẫu mình đưa sẵn để bạn copy:

Bước 1: Tạo bot & lấy token, chat_id

Chat với @BotFather → /newbot → lấy BOT_TOKEN.

Mở chat với bot của bạn, gõ một tin bất kỳ.

Truy cập https://api.telegram.org/bot<BOT_TOKEN>/getUpdates → lấy chat.id (cá nhân là số dương; group/channel là số âm).
Muốn gửi vào group/channel thì add bot vào group (set admin nếu là channel).

Bước 2: Cho phép MT5 gọi WebRequest

MT5 → Tools → Options → Expert Advisors → tick Allow WebRequest… → thêm URL:
https://api.telegram.org
(Nếu quên bước này, WebRequest sẽ báo lỗi 4014).

Bước 3: Dán code vào EA
// ==== Inputs ====
input string InpTgBotToken = "123456:ABCDEF..."; // BotFather token
input string InpTgChatId   = "123456789";        // chat.id hoặc group id (-100...)

// ==== Helper: URL-encode UTF-8 ngắn gọn ====
string URLEncode(const string s) {
   static uchar map[];
   if(ArraySize(map)==0){ ArrayResize(map,256); for(int i=0;i<256;i++) map[i]=(uchar)i; }
   string out=""; uchar bytes[]; StringToCharArray(s,bytes,0,WHOLE_ARRAY,CP_UTF8);
   for(int i=0;i<ArraySize(bytes)-1;i++){
      uchar c = bytes[i];
      bool safe = (c>='0' && c<='9') || (c>='A' && c<='Z') || (c>='a' && c<='z') || c=='-'||c=='_'||c=='.'||c=='~';
      if(safe) out += (string)CharToString((ushort)c);
      else out += StringFormat("%%%02X", (int)c);
   }
   return out;
}

// ==== Send text ====
bool TgSend(const string text, bool html=true) {
   string url = "https://api.telegram.org/bot"+InpTgBotToken+"/sendMessage";
   string payload = StringFormat("chat_id=%s&text=%s&disable_web_page_preview=true&parse_mode=%s",
                                 InpTgChatId, URLEncode(text), html ? "HTML" : "MarkdownV2");

   char data[]; StringToCharArray(payload,data,0,WHOLE_ARRAY,CP_UTF8);
   char result[]; string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   int status = WebRequest("POST", url, headers, 10000, data, result, NULL);
   if(status==200) return true;
   PrintFormat("Telegram error status=%d lastError=%d response=%s",
               status, GetLastError(), CharArrayToString(result));
   return false;
}

// ==== Gợi ý dùng trong EA ====
// Ví dụ: báo Hard SL, trail, TP...
void NotifyHardSL(double dd){
   TgSend(StringFormat("⚠️ <b>HARD SL</b> hit: DD=%.2f USD. All positions closed. Cooldown 30m.", dd));
}
void NotifyTrail(double pnl,double lock){
   TgSend(StringFormat("🏁 Basket trail: PnL=%.2f USD, locked=%.2f USD", pnl, lock));
}
void NotifyTP(string sym,double usd){
   TgSend(StringFormat("✅ %s TP hit: +%.2f USD", sym, usd));
}