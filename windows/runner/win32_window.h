#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| of |size|, placed on the primary
  // monitor's work area: centred in it, or at its top-left corner when the
  // window is larger than it, since a window whose title bar is off the screen
  // has nothing left to drag. Window sizes are given to the OS in physical
  // pixels, hence to ensure a consistent size this function scales the inputted
  // width and height as appropriate for that monitor — unless |scale_size| is
  // false, which is what a size that is already in physical pixels needs, such
  // as the size the app recorded in its last run. When |maximized| is true
  // the window is created in that state, and Show shows it in that state too,
  // since ShowWindow would otherwise restore it to the size given here — which
  // is what a record that says maximized asks for. The window is invisible
  // until |Show| is called. Returns true if the window was created
  // successfully.
  bool Create(const std::wstring& title, const Size& size,
             bool scale_size = true, bool maximized = false);

  // Show the current window. Returns true if the window was successfully shown.
  // A window created maximized is shown maximized, because ShowWindow with
  // SW_SHOWNORMAL restores a maximized window to the size Create was given,
  // which is not what a record that says maximized asks for.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // Whether the window was created maximized, which Show needs: showing a
  // window in the maximized state with SW_SHOWNORMAL restores it.
  bool maximized_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
