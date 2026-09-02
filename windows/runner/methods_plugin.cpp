#include "methods_plugin.h"

#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "../rust.h"

namespace {

// Keeps detached worker results from racing Flutter engine/plugin teardown.
class InvokeLifetime {
 public:
  bool begin() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!alive_) {
      return false;
    }
    ++active_;
    return true;
  }

  void finish() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (active_ > 0) {
      --active_;
    }
    if (active_ == 0) {
      condition_.notify_all();
    }
  }

  template <typename Callback>
  bool with_alive(Callback&& callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!alive_) {
      return false;
    }
    callback();
    return true;
  }

  void shutdown() {
    std::unique_lock<std::mutex> lock(mutex_);
    alive_ = false;
    // Rust requests have bounded network timeouts. Wait briefly for fast
    // workers, then late workers observe alive_=false and release their
    // MethodResult without touching the destroyed engine.
    condition_.wait_for(lock, std::chrono::seconds(2), [this] {
      return active_ == 0;
    });
  }

 private:
  std::mutex mutex_;
  std::condition_variable condition_;
  bool alive_ = true;
  size_t active_ = 0;
};

void InvokeThread(
    std::string params,
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    const std::shared_ptr<InvokeLifetime>& lifetime) {
  char* result_chars = invoke_ffi(params.c_str());
  if (result_chars == nullptr) {
    lifetime->with_alive([&] {
      result->Error("ffi_error", "invoke_ffi returned null");
    });
    lifetime->finish();
    return;
  }

  const std::string response(result_chars);
  free_str_ffi(result_chars);
  lifetime->with_alive([&] {
    result->Success(flutter::EncodableValue(response));
  });
  lifetime->finish();
}

class MethodsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  MethodsPlugin();
  ~MethodsPlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::shared_ptr<InvokeLifetime> lifetime_;
};

void MethodsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "methods",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<MethodsPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

MethodsPlugin::MethodsPlugin() : lifetime_(std::make_shared<InvokeLifetime>()) {}

MethodsPlugin::~MethodsPlugin() {
  lifetime_->shutdown();
}

void MethodsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("invoke") == 0) {
    const auto* arguments = std::get_if<std::string>(method_call.arguments());
    if (arguments == nullptr) {
      result->Error("invalid_arguments", "invoke expects a string");
      return;
    }
    if (!lifetime_->begin()) {
      result->Error("engine_shutdown", "methods plugin is shutting down");
      return;
    }
    auto result_shared =
        std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            std::move(result));
    try {
      std::thread t(InvokeThread, *arguments, result_shared, lifetime_);
      t.detach();
    } catch (...) {
      lifetime_->finish();
      result_shared->Error("thread_error", "failed to start invoke worker");
    }
    return;
  }
  result->NotImplemented();
}

}  // namespace

void MethodsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  MethodsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
