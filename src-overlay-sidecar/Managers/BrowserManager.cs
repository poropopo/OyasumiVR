using CefSharp;
using overlay_sidecar.Browsers;
using Serilog;

namespace overlay_sidecar;

public class BrowserManager {
  public static BrowserManager Instance { get; } = new();
  private List<CachedBrowser> _browsers = new();
  private bool _disposed = false;

  private BrowserManager()
  {
  }

  public void PreInitializeBrowser(uint width, uint height)
  {
    FreeBrowser(GetBrowser("about:blank", width, height));
  }

  public OffscreenBrowser GetBrowser(string url, uint width, uint height)
  {
    lock (_browsers)
    {
      if (_disposed)
      {
        throw new ObjectDisposedException("BrowserManager is already disposed");
      }

      foreach (var cachedBrowser in _browsers)
      {
        if (cachedBrowser.IsFree && cachedBrowser.Width == width && cachedBrowser.Height == height)
        {
          cachedBrowser.IsFree = false;
          cachedBrowser.Browser.LoadUrl(url);
          return cachedBrowser.Browser;
        }
      }

      OffscreenBrowser browser = Program.GpuAccelerated ? new AcceleratedOffscreenBrowser(url, width, height) : new NonAcceleratedOffscreenBrowser(url, width, height);
      _browsers.Add(new CachedBrowser(browser, false, width, height));

      return browser;
    }
  }

  public void FreeBrowser(OffscreenBrowser browser)
  {
    lock (_browsers)
    {
      foreach (var cachedBrowser in _browsers)
      {
        if (cachedBrowser.Browser == browser)
        {
          cachedBrowser.Browser.JavascriptObjectRepository.UnRegisterAll();
          cachedBrowser.Browser.LoadHtml("");
          cachedBrowser.IsFree = true;
          return;
        }
      }
    }
  }

  public void DisposeAll()
  {
    lock (_browsers)
    {
      if (_disposed) return;
      _disposed = true;

      Log.Information($"Disposing {_browsers.Count} browser instances...");

      foreach (var cachedBrowser in _browsers)
      {
        try
        {
          cachedBrowser.Browser.Dispose();
        }
        catch (Exception e)
        {
          Log.Warning(e, "Error disposing browser instance");
        }
      }

      _browsers.Clear();
      Log.Information("All browser instances disposed.");
    }
  }

  class CachedBrowser {
    public OffscreenBrowser Browser;
    public bool IsFree;
    public uint Width;
    public uint Height;

    public CachedBrowser(OffscreenBrowser browser, bool isFree, uint width, uint height)
    {
      Browser = browser;
      IsFree = isFree;
      Width = width;
      Height = height;
    }
  }
}
