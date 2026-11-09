using System;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Win32;

[assembly: AssemblyTitle("TeklaClaudeMcp - Tekla 2020 model + drawing tools")]
[assembly: AssemblyVersion("2.0.0.0")]
[assembly: AssemblyFileVersion("2.0.0.0")]

namespace TeklaClaudeMcp
{
    /// <summary>
    /// MCP server (stdio) cho Tekla Structures 2020 SP14 tren may pc-whvn00026.
    /// Stdout danh rieng cho giao thuc MCP; log di qua stderr.
    /// </summary>
    internal static class Program
    {
        private static int Main(string[] args)
        {
            // DLL Tekla in thong bao (vd "Connection failed...") bang Console.WriteLine. Stdout danh rieng
            // cho giao thuc MCP (transport ghi thang vao luong stdout goc), nen chuyen Console.Out sang stderr.
            Console.SetOut(Console.Error);

            TeklaEnvironment.Init();

            var builder = Host.CreateApplicationBuilder(args);
            builder.Logging.ClearProviders();
            builder.Logging.AddConsole(o => o.LogToStandardErrorThreshold = LogLevel.Trace);

            builder.Services
                .AddMcpServer((Action<ModelContextProtocol.Server.McpServerOptions>)null)
                .WithStdioServerTransport()
                .WithToolsFromAssembly(typeof(DrawingTools).Assembly, null);

            builder.Build().RunAsync().GetAwaiter().GetResult();
            return 0;
        }
    }

    /// <summary>
    /// Tim thu muc cai Tekla 2020 va cho phep nap DLL native/phu thuoc tu do.
    /// </summary>
    internal static class TeklaEnvironment
    {
        // Duong dan du phong tren may nay (Tekla dang chay tu C:\TeklaStructures\2020.0).
        private static readonly string[] FallbackInstallDirs =
        {
            @"C:\TeklaStructures\2020.0",
            @"D:\Tekla Structure\2020.0",
            @"D:\TeklaStructures\2020.0"
        };

        public static string InstallDir { get; private set; }
        public static string BinDir => Path.Combine(InstallDir, "nt", "bin");
        public static string PluginsDir => Path.Combine(BinDir, "plugins");

        public static void Init()
        {
            // Tekla 2020 Open API dat ten kenh IPC theo SESSIONNAME. Tien trinh do Claude desktop
            // khoi chay co the thieu bien nay -> GetConnectionStatus() tra false. Dat mac dinh "Console".
            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("SESSIONNAME")))
                Environment.SetEnvironmentVariable("SESSIONNAME", "Console");

            InstallDir = ReadInstallDirFromRegistry();
            if (InstallDir == null)
            {
                foreach (var dir in FallbackInstallDirs)
                {
                    if (Directory.Exists(Path.Combine(dir, "nt", "bin"))) { InstallDir = dir; break; }
                }
            }
            if (InstallDir == null) InstallDir = FallbackInstallDirs[0];

            var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            Environment.SetEnvironmentVariable("PATH", BinDir + ";" + PluginsDir + ";" + path);

            AppDomain.CurrentDomain.AssemblyResolve += ResolveFromTekla;
        }

        private static string ReadInstallDirFromRegistry()
        {
            const string key = @"SOFTWARE\Tekla\Structures\2020.0\setup";
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                foreach (var hive in new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
                {
                    try
                    {
                        using (var baseKey = RegistryKey.OpenBaseKey(hive, view))
                        using (var k = baseKey.OpenSubKey(key))
                        {
                            var v = k?.GetValue("InstallDir") as string;
                            if (!string.IsNullOrWhiteSpace(v) && Directory.Exists(v)) return v;
                        }
                    }
                    catch { /* thu cach khac */ }
                }
            }
            return null;
        }

        private static Assembly ResolveFromTekla(object sender, ResolveEventArgs e)
        {
            var name = new AssemblyName(e.Name).Name + ".dll";
            foreach (var dir in new[] { BinDir, PluginsDir })
            {
                var candidate = Path.Combine(dir, name);
                if (File.Exists(candidate))
                {
                    try { return Assembly.LoadFrom(candidate); } catch { /* bo qua */ }
                }
            }
            return null;
        }
    }
}
