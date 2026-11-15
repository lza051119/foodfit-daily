# 食动日记

原生 SwiftUI iPhone App，最低 iOS 17。记录饮食、消耗、每日体重和力量训练。点「设置 → 连接 Apple 健康」授权后，可以读取活动能量、静息能量和体能训练。活动与静息能量相加得到总消耗。选日期、重新进入前台或在饮食页下拉可刷新。

## 先装到自己的 iPhone

1. 在 Mac 解压 ZIP，打开 `FoodFit.xcodeproj`，顶部选择 `FoodFit` scheme。
2. 在 `Xcode → Settings → Accounts` 登录自己的 Apple 账户。在项目的 `TARGETS → FoodFit → Signing & Capabilities` 勾选 `Automatically manage signing`，为 `Team` 选择自己的团队。
3. 把 `Bundle Identifier` 改成自己团队可注册的唯一标识，例如以你自己的域名倒序开头，再加 `.foodfit`。项目已配置 HealthKit 和读取用途说明。检查 `Signing & Capabilities` 里有 `HealthKit`。
4. 用线接上 iPhone，解锁并点「信任」。在 Xcode 顶部把运行目标选成自己的 iPhone。若系统提示，去 iPhone「设置 → 隐私与安全性 → 开发者模式」开启，按提示重启并确认。
5. 点 Xcode 的 ▶ Run。出现 `Register Device` 时点注册。成功后，iPhone 主屏幕会出现「食动日记」。
6. 在 App 的「设置」连接 Apple 健康，按需允许读取活动能量、静息能量和体能训练。在饮食页核对日期和数据。可在「健康 → 头像 → App 与服务」检查授权。

自用真机调试可以先用 `Personal Team`。Apple 的 iOS 能力表列出了 HealthKit 支持，个人团队签出的自用描述文件通常 7 天到期。真机安装前也可选择 iPhone 模拟器检查界面。[真机运行与自动签名](https://developer.apple.com/documentation/xcode/building-and-running-an-app) · [开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) · [iOS 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios) · [个人团队限制](https://developer.apple.com/help/account/basics/about-your-developer-account)

### Provisioning Profile

`.mobileprovision` 绑定开发团队、App ID、签名证书、能力和允许安装的设备范围。上述自动签名会由 Xcode 创建开发描述文件并把它打进 App，备用 Mac 也可以完成。

如果所在团队使用手动签名，在 Apple Developer 的 `Certificates, Identifiers & Profiles` 注册显式 App ID 并开启 HealthKit，添加 iPhone 的 UDID，再创建 `iOS App Development` Profile。选择该 App ID、这台 Mac 上可用的 Apple Development 证书和测试设备。下载后双击安装到 Mac，在 Xcode 关闭自动签名并选择该描述文件。分发归档时选择对应的分发签名方式。[手动创建开发描述文件](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/) · [设置 HealthKit](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)

## 记录和每日长图

- 「饮食消耗」选日期，再点「当天体重」。体重可用斤或公斤，每日保留一条。身高在同页编辑，保存在本机。
- 点「记一餐」可以手填大卡，或选照片并用 DeepSeek 估算。只有餐类时也可以估算较宽的范围。完整提示词和连接测试都在「设置 → DeepSeek」。
- 「补录消耗」选「健身 → 摘要 → 活动圆环」里对应日期的详情截图。系统 Vision 在 iPhone 本机识别，保存前核对日期和活动、总消耗。
- 「每日总结」预览所选日期的长图，包含摄入、总消耗、热量差和运动记录。点「保存到照片」保存 PNG，或点「分享长图」，从 iOS 分享菜单选择微信等已安装的应用。
- 长图页面右上角的「AI 总结」会根据当天已记录的餐次与大卡、补录消耗和实际力量组次生成文字。保存的文字会放进长图。身高、体重、照片和 HealthKit 读数保留在本机，日总结的 AI 请求使用上述补录数据。
- DeepSeek API Key 保存在 iPhone 钥匙串。App 源码、工程和核心测试维护在 [GitHub 源码仓库](https://github.com/lza051119/foodfit-daily)。

## TestFlight 和 App Store

1. 用 Apple Developer Program 团队做分发签名。在 App Store Connect 创建 App 条目，选择和 Xcode 相同的 Bundle ID。安装符合 Apple 当前上传 SDK 要求的 Xcode。
2. 在 Xcode 选择 `Any iOS Device`，点 `Product → Archive`。Organizer 里点 `Distribute App → TestFlight & App Store`，按向导上传。如果只给团队内测，可以选择 TestFlight Internal Only。
3. 上传后的构建在 App Store Connect 的「TestFlight」里分配给测试组。自己的账号加入内部测试组后，可在 iPhone 的 TestFlight 下载。外部测试首个构建通常需要 Beta 审核。
4. 正式上架时填写 App 信息、截图、隐私政策、App Privacy、审核说明等，选择一个构建提交审核。App 的「隐私与数据」支持显示正式政策链接，在 Xcode 为目标添加用户自定义 Build Setting `FOODFIT_PRIVACY_POLICY_URL`，值设为你发布的 HTTPS 隐私政策地址。App Privacy 填报应按实际数据流和 DeepSeek 的处理方式核对。

[App Store Connect 分发流程](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases/) · [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) · [苹果当前上传要求](https://developer.apple.com/news/upcoming-requirements/) · [App Review 隐私要求](https://developer.apple.com/app-store/review/guidelines/#privacy)

## 验证

在 Mac 或带 Swift 的环境运行 `swift test`。要检查 iOS 编译途径，在 Mac 上运行：

```sh
xcodebuild -project FoodFit.xcodeproj -scheme FoodFit \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

真机验收时核对 Apple 健康能量与体能训练、健身截图识别、保存同日期的体重、DeepSeek 估算与日总结，以及保存长图到照片、从系统分享菜单转发。
