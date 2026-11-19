using System;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

// Native Windows stdin/argv fixture. No provider, network or credential access.
class FakeCodex {
    static void Main(string[] args) {
        if (Array.IndexOf(args, "--help") >= 0) {
            Console.WriteLine("--ignore-user-config --ignore-rules --ephemeral --output-schema --output-last-message");
            return;
        }
        if (Array.IndexOf(args, "login") >= 0) {
            Console.WriteLine("Logged in using fixture credentials");
            return;
        }
        var input = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8).ReadToEnd();
        if (Array.IndexOf(args, "web_search=live") >= 0)
            Console.WriteLine("{\"type\":\"item.completed\",\"item\":{\"id\":\"item_1\",\"type\":\"web_search\",\"query\":\"fixture\"}}");
        int index = Array.IndexOf(args, "--output-last-message");
        if (index >= 0) File.WriteAllText(args[index + 1], "{\"changes\":[],\"questions\":[]}", new UTF8Encoding(false));
        var log = Environment.GetEnvironmentVariable("POLOX_CODEX_ARGV_FIXTURE");
        if (!String.IsNullOrEmpty(log)) File.WriteAllText(log,
            new JavaScriptSerializer().Serialize(new { args = args, stdin = input }), new UTF8Encoding(false));
    }
}
