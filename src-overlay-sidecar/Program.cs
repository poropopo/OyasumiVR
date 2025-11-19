// See https://aka.ms/new-console-template for more information

using System.Diagnostics;
using CefSharp;
using CefSharp.OffScreen;
using Serilog;

namespace overlay_sidecar;

public static class Program {
  public static bool GpuAccelerated = true;
  public static SidecarMode Mode = SidecarMode.Release;
  private static bool _isShuttingDown = false;
  private static readonly object _shutdownLock = new object();

  public static void Main(string[] args)
  {
    LogConfigurator.Init();
    var coreGrpcPort = (int)Globals.CORE_GRPC_DEV_PORT;
    var mainProcessId = 0;

    // Parse args
    if (args.Length > 0 && args[0] == "dev")
    {
      Mode = SidecarMode.Dev;
    }

    Log.Information("Starting OyasumiVR overlay sidecar in " + (Mode == SidecarMode.Dev ? "dev" : "release") +
                      " mode.");

    if (Mode == SidecarMode.Release)
    {
      if (args.Length < 1 || !int.TryParse(args[0], out coreGrpcPort))
      {
        Log.Error("Usage: oyasumivr-overlay-sidecar.exe <core grpc port> <core process id>");
        return;
      }

      if (args.Length < 2 || !int.TryParse(args[1], out mainProcessId))
      {
        Log.Error("Usage: oyasumivr-overlay-sidecar.exe <core grpc port> <core process id>");
        return;
      }
    }

    if (args.Any(arg => arg == "--disable-gpu-acceleration"))
    {
      Log.Information("Launching with GPU acceleration disabled");
      GpuAccelerated = false;
    }

    // Register shutdown handler
    AppDomain.CurrentDomain.ProcessExit += OnProcessExit;

    // Initialize
    WatchMainProcess(mainProcessId);
    InitCef();
    IpcManager.Instance.Init(coreGrpcPort);
    OvrManager.Instance.Init();
  }

  private static void InitCef()
  {
    var settings = new CefSettings();
    if (InReleaseMode())
    {
      settings.LogSeverity = LogSeverity.Disable;
      var cefDebugLogPath = Path.Combine(Path.GetDirectoryName(Environment.ProcessPath)!, @"debug.log");
      if (File.Exists(cefDebugLogPath)) File.Delete(cefDebugLogPath);
    }

    Cef.Initialize(settings);
  }

  private static void WatchMainProcess(int mainPid)
  {
    if (InDevMode()) return;
    Process? mainProcess = null;
    try
    {
      mainProcess = Process.GetProcessById(mainPid);
    }
    catch (ArgumentException)
    {
      Log.Error("Could not find main process to watch (pid=" + mainPid + "). Stopping overlay sidecar.");
      Shutdown();
      Environment.Exit(1);
      return;
    }

    new Thread(() =>
    {
      while (true)
      {
        if (mainProcess.HasExited)
        {
          Log.Information("Main process has exited. Stopping overlay sidecar.");
          Shutdown();
          Environment.Exit(0);
          return;
        }

        Thread.Sleep(1000);
      }
    }).Start();
  }

  private static void OnProcessExit(object? sender, EventArgs e)
  {
    Shutdown();
  }

  private static void Shutdown()
  {
    lock (_shutdownLock)
    {
      if (_isShuttingDown)
        return;
      
      _isShuttingDown = true;
      Log.Information("Starting cleanup process...");

      try
      {
        // Dispose all cached browsers
        BrowserManager.Instance.DisposeAllBrowsers();
        
        // Shutdown CEF
        if (Cef.IsInitialized)
        {
          Log.Information("Shutting down CefSharp...");
          Cef.Shutdown();
          Log.Information("CefSharp shutdown complete.");
        }
      }
      catch (Exception ex)
      {
        Log.Error(ex, "Error during shutdown");
      }
    }
  }

  public static bool InDevMode()
  {
    return Mode == SidecarMode.Dev;
  }

  public static bool InReleaseMode()
  {
    return Mode == SidecarMode.Release;
  }

  public enum SidecarMode {
    Release,
    Dev
  }
}
