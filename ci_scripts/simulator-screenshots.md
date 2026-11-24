# 模拟器截图与后续 UI 测试

## 目前能做什么

`simulator-screenshots.sh` 在指定的 iOS 模拟器上安装传入的模拟器版 `.app`，启动并通过 `simctl io screenshot` 捕获屏幕。它还临时编译并安装独立的 UIKit 宿主，在**安全输入框**上调出系统键盘，收到 `keyboardDidShow`、输入框为第一响应者且键盘框覆盖一定屏幕面积后，再截取屏幕。这旨在拍摄真实系统键盘画面，不是 Hamster 键盘，也不代表普通文本框的键盘布局；面积检查是启发式检查，不能代替实际看图。Apple 文档说明，安全文本输入时系统会以系统键盘替换第三方键盘：[Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)。

输出文件：

- `01-main-app-launch-unverified.png`：启动后固定等待的截图。脚本只检查进程仍在，并不验证 App 处于前台、数据加载完成或目标页面可见；可能拍到启动屏、权限弹窗或其他画面，必须人工检查或由未来的 UI 测试断言。
- `02-system-keyboard-secure.png`：独立宿主安全输入框的系统键盘截图。键盘显示通知是就绪信号，不是屏幕像素、键盘布局或截图内容的断言；仍须人工检查。没有收到就绪信号会报错，不会生成该图片。

脚本本身**没有实现**自定义键盘启用、选择、截图、中文输入、候选词或提交内容的测试。也没有运行 XCTest 或自动验证主 App 内容。运行成功只表示脚本的启动、通知和截屏步骤通过，不代表产品 UI 测试通过。任何截图不得作为自动断言通过的证据，除非另有真实 UI 测试结果。

## 运行前提

需要 macOS、已选中的完整 Xcode、iOS Simulator SDK 和所需 simulator runtime、`xcrun`、`swiftc`、`codesign`、`python3`，及一个包含对应模拟器架构的模拟器版 `Hamster.app`。运行时和设备型号必须在实际 Mac 上确认；此环境为 Linux，没有 Xcode 或 iOS 模拟器，**尚未在 macOS 编译或运行此脚本和宿主，也未取得任何真实截图**。特别是不能在这里确认 iOS 26.2 / iPhone 16 Pro Max runtime、设备或依赖二进制的可用性，也不能保证该组合下 helper 或项目可成功构建。

检查选中的 Xcode、runtime 和设备：

```bash
xcodebuild -version
xcrun simctl list runtimes
xcrun simctl list devicetypes | grep 'iPhone 16 Pro Max'
xcrun simctl list devices available
```

若 runtime 不存在，可在 Xcode 的 Settings → Components 安装。Apple 也记录了 `xcodebuild -downloadPlatform` 和指定版本的方法：[Downloading and installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。安装选项及硬件架构支持以实际 Xcode 输出为准。

仓库的 `Frameworks/` 当前只有 `.gitkeep`，`Resources/SharedSupport/` 未包含构建需要的 `SharedSupport.zip` 和 `rime-ice.zip`。仓库文档的准备命令如下；它们会下载网络依赖、生成本地文件并修改临时目录，须在合适的 macOS 构建环境由执行者检查后运行，本次并未运行：

```bash
make framework
make schema
```

`make framework` 当前使用 LibrimeKit 2.4.2，而 `ci_post_clone.sh` 使用 2.3.0；不要假定两者等价。还需检查下载的每个 `.xcframework` 包含目标模拟器平台及架构；设备版 arm64 不等于模拟器版 arm64。`make schema` 也依赖网络及本机可运行的构建工具。现有工作流生成的是 `iphoneos` archive，不是本脚本需要的 simulator `.app`。

以下仅为待验证的本地构建示例，可能因依赖、Xcode 版本、签名或架构而失败：

```bash
# 从上述列表中手动选定真实 UDID；不要使用设备名称代替 UDID。
UDID='替换为模拟器 UDID'
DD=/tmp/hamster-derived-data
xcodebuild -project Hamster.xcodeproj -scheme Hamster -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO build
APP="$DD/Build/Products/Debug-iphonesimulator/Hamster.app"
```

确定输入 `.app` 对应选中的 runtime 与 CPU 架构，并在不同 Xcode 和 App Groups 签名条件下检查可安装性。脚本验证 `CFBundleSupportedPlatforms`、可执行文件架构与实际 simulator 架构，但这些检查不能证明 App 能运行。

## 截图命令

在已准备模拟器版 `.app` 后，运行：

```bash
ci_scripts/simulator-screenshots.sh \
  --udid "$UDID" \
  --app "$APP" \
  --output /tmp/hamster-shots-unique-run \
  --require-device 'iPhone 16 Pro Max' \
  --require-device-type 'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max' \
  --require-ios 26.2
```

`--require-device` 匹配设备当前名称，可因改名而失败；`--require-device-type` 才校验型号标识。runtime 比较的是 `simctl` runtime identifier，不是从截图识别操作系统。请先用上述 `simctl` 命令核对实际标识。可按机器需要设置 `--main-wait`（默认 8 秒）与 `--keyboard-timeout`（默认 30 秒）；这些等待不代替 UI 测试。

如系统键盘超时，在 Simulator 的键盘菜单断开硬件键盘连接并启用软件键盘，重试时使用新输出目录。启动权限提示、模拟器语言、深浅色、上次保留的数据和窗口状态都会影响截图。脚本不会擦除 simulator，且安装会保留已有 App 数据；它会启动指定设备、安装/更新并重新启动主 App，还会安装名为 `dev.hamster.simulatorscreenshot.keyboardhost` 的宿主，运行结束后该宿主和模拟器数据仍会保留。不要在有重要状态或敏感数据的模拟器上运行。它不会关闭设备、自动清除 App 数据、修改系统设置或卸载宿主。

两张固定名称的图片若已存在，脚本拒绝覆盖；如果执行途中失败，已完成的前序截图可能保留，必须结合日志判断，不应把部分结果当成整个流程成功。截图文件只由真实 `simctl io screenshot` 生成。

## 扩展接口和建议测试设计

额外执行 `--extra-hook /absolute/path/to/executable`，脚本在默认两张截图后调用它并传入环境变量：`SIMULATOR_UDID`、`APP_PATH`、`APP_BUNDLE_ID`、`SCREENSHOT_OUTPUT_DIR`、`MAIN_APP_SCREENSHOT`、`SYSTEM_KEYBOARD_SCREENSHOT`。hook 没有位置参数；退出码非 0 会使脚本失败。hook 需要自行启动正确的宿主、证明界面已就绪、断言键盘身份和输入结果，再生成独立命名的真实截图；不能只看默认截图或直接伪造成功。默认宿主使用安全输入框，**不能用于激活第三方键盘**，后续需新增或改造成独立的非安全输入测试宿主。

工程目前有 `Hamster` 和 `HamsterKeyboard` 两个共享 scheme，项目中只有 `Hamster`、`HamsterKeyboard` 和 `SbxlmKeyboard` 三个 target；两个扩展随主 App 嵌入。两个 scheme 的 TestAction 分别引用 `HamsterTests` 和 `HamsterAppTests`，但它们的 target ID 不在当前 `project.pbxproj` 内；`Packages/*/Tests` 中的包级单元测试不能替代设备 UI 测试。是否以及如何修复 scheme，必须在真实 Xcode 中验证。

后续如获得项目改动授权，建议新增共享的 UI-testing target 和 scheme，清理失效的 TestAction 引用，并在相应界面和键盘按键增加稳定的 accessibility identifier。主 App 当前首页控制器加载 `输入法设置`，其 `viewDidAppear` 异步加载 App 数据，因此 UI 测试应等待明确的首页与数据就绪标识，而不是依赖固定 sleep。建议固定语言、外观、设备尺寸与隔离测试数据；记录 simulator runtime、机型、App 构建版本和测试结果。

针对自制键盘，使用新建的**非安全**输入测试宿主并为输入框提供 accessibility identifier；在模拟器设置中由执行者手动启用，或由真实 XCUI 测试驱动设置页完成启用（系统设置页的自动化兼容性需要在目标 runtime 验证）。仅在测试需求明确时处理“允许完全访问”及其确认弹窗。通过地球键选择指定扩展后，断言扩展独有的可访问性标识/按键存在，输入固定序列、检查候选词、提交文本并验证宿主输入框内容；截图以 `XCUIScreen` 附件或 `simctl` 截取实际屏幕，必要时分别覆盖两个扩展。设置页操作、键盘切换、候选词状态和文本提交都需要明确断言；若相应元素不可访问则应明确报错或标记未实现，不得用截图文件存在代替通过。

本次没有修改 Xcode 工程或现有 Swift 文件，没有创建 UI test target，没有运行 CI、提交或推送。
