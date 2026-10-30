// JRA-VAN Data Lab(JV-Link)からデータを取り出して、1レコード1行(Shift-JIS のまま)でファイルに書く。
// JV-Link は32bitのCOMなので x86 でビルドする(build.sh)。
//   jvget.exe open <dataspec> <fromtime yyyymmddhhmmss> <option 1通常/2今週/3,4セットアップ> <出力> [レコード種別,...]
//   jvget.exe rt <dataspec> <キーを1行1つ書いたファイル> <出力>        速報系(時系列オッズ 0B41 など)
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Collections.Generic;

class JvGet
{
    static Encoding sjis = Encoding.GetEncoding(932);
    static Encoding cp1252 = Encoding.GetEncoding(1252);
    // JV-Link が Shift-JIS を cp1252 として文字にして返すことがある(PC収集から動いたとき。2026-10-27〜の RACE が化けていた)。
    // 日本語(U+3000 以上)が無く、U+0080 以上の文字があるときは cp1252 で元のバイトに戻す
    static byte[] Bytes(string s)
    {
        bool jp = false, latin = false;
        foreach (char ch in s) { if (ch >= 0x3000) { jp = true; break; } if (ch >= 0x80) latin = true; }
        return (!jp && latin) ? cp1252.GetBytes(s) : sjis.GetBytes(s);
    }

    [STAThread]
    static int Main(string[] a)
    {
        if (a.Length < 4) { Console.Error.WriteLine("usage: open|rt ..."); return 2; }
        dynamic jv = Activator.CreateInstance(Type.GetTypeFromProgID("JVDTLab.JVLink"));
        // セットアップの確認ダイアログ用に親ウィンドウを渡す(無いとセットアップが -2 / -301 で止まる)
        var form = new System.Windows.Forms.Form();
        form.Text = "JRA-VAN 取り込み"; form.ShowInTaskbar = true;
        jv.ParentHWnd = (int)form.Handle;
        int r = jv.JVInit("UNKNOWN");
        if (r != 0) { Console.Error.WriteLine("JVInit " + r); return 1; }
        try
        {
            if (a[0] == "open") return Open(jv, a);
            if (a[0] == "rt") return Rt(jv, a);
            return 2;
        }
        finally { jv.JVClose(); }
    }

    static int Open(dynamic jv, string[] a)
    {
        HashSet<string> want = null;
        if (a.Length > 5) want = new HashSet<string>(a[5].Split(','));
        int rc = 0, dc = 0; string ts = "";
        int r = jv.JVOpen(a[1], a[2], int.Parse(a[3]), ref rc, ref dc, out ts);
        Console.Error.WriteLine("JVOpen " + a[1] + " = " + r + " ファイル " + rc + " ダウンロード " + dc + " 最終 " + ts);
        if (r == -1) return 0;  // 該当データなし
        if (r != 0) return 1;
        using (var w = new FileStream(a[4], FileMode.Append))
        {
            long n = 0, kept = 0;
            while (true)
            {
                string buf = ""; string fn = "";
                int x = jv.JVRead(out buf, 110000, out fn);
                if (x == 0) break;
                if (x == -1) continue;               // ファイルの切り替わり
                if (x == -3) { Thread.Sleep(200); continue; }  // ダウンロード中
                if (x < 0) { Console.Error.WriteLine("JVRead " + x + " " + fn); return 1; }
                n++;
                if (want != null && !want.Contains(buf.Substring(0, 2))) continue;
                byte[] b = Bytes(buf.TrimEnd('\r', '\n', '\0'));
                w.Write(b, 0, b.Length); w.WriteByte(10);
                kept++;
                if (n % 200000 == 0) Console.Error.WriteLine(n + " 件");
            }
            Console.Error.WriteLine("読んだ " + n + " 件 / 書いた " + kept + " 件");
        }
        return 0;
    }

    static int Rt(dynamic jv, string[] a)
    {
        string[] keys = File.ReadAllLines(a[2]);
        int ok = 0, none = 0;
        using (var w = new FileStream(a[3], FileMode.Append))
        {
            foreach (string k0 in keys)
            {
                string k = k0.Trim();
                if (k.Length == 0) continue;
                int r = jv.JVRTOpen(a[1], k);
                if (r != 0) { none++; if (r != -1) Console.Error.WriteLine("JVRTOpen " + k + " = " + r); jv.JVClose(); continue; }
                while (true)
                {
                    string buf = ""; string fn = "";
                    int x = jv.JVRead(out buf, 110000, out fn);
                    if (x == 0) break;
                    if (x == -1) continue;
                    if (x == -3) { Thread.Sleep(100); continue; }
                    if (x < 0) { Console.Error.WriteLine("JVRead " + x + " " + k); break; }
                    byte[] b = Bytes(buf.TrimEnd('\r', '\n', '\0'));
                    w.Write(b, 0, b.Length); w.WriteByte(10);
                }
                jv.JVClose();
                ok++;
            }
        }
        Console.Error.WriteLine("取れた " + ok + " / 無し " + none);
        return 0;
    }
}
