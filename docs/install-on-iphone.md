# 食动日记 iPhone 安装手册

这份手册给协助安装的人。准备一台装有 Xcode 的 Mac、一根数据线，以及使用者的 iPhone。食动日记需要 iOS 17 或更新版本，自用可以选免费的 Personal Team 签名。

## 1. 确认 Xcode 能识别 iPhone

- 手机和 Mac 在一起时，用数据线连接。解锁 iPhone，手机弹出「信任此电脑」时点「信任」，Mac 弹出连接许可时点「允许」。
- 如果用的是远程 Mac，先按租用方的说明把使用者自己的 iPhone 通过 USB 转发给这台 Mac。在 Xcode 的 **Window → Device Hub** 中确认能看到手机，旧版菜单叫 **Devices and Simulators**。

[Apple 真机连接说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) · [远程 Mac 的 USB 转发示例](https://support.macincloud.com/support/solutions/articles/8000007775-how-do-i-connect-my-physical-iphone-or-usb-device-to-the-server-)

## 2. 下载工程并设置签名

1. 在 Mac 上[下载 GitHub 源码 ZIP](https://github.com/lza051119/foodfit-daily/archive/refs/heads/main.zip)。解压并双击 `FoodFit.xcodeproj`。Xcode 提示安装 iOS 支持组件时，等它装完。
2. 在 **Xcode → Settings → Apple Accounts** 添加 Apple 账户，旧版菜单叫 **Accounts**。覆盖安装 AltServer 版时，用当时签名的同一个账户。由 iPhone 使用者本人在 Xcode 里登录并完成双重认证。
3. 在 Xcode 左侧点蓝色的 **FoodFit** 工程图标，再点中间 **TARGETS** 下的 **FoodFit**。打开 **Signing & Capabilities**，勾选 **Automatically manage signing**，在 **Team** 中选使用者的 **Personal Team**，确认页面上有 **HealthKit**。

### 填写 Bundle Identifier

食动日记的 AltServer 安装使用 `com.foodfit.journal.` 加签名团队 ID 作为应用标识。覆盖安装时要和原 App 的标识一致。选好 Team 后，在解压出来的工程目录里打开 Mac 的「终端」，运行以下命令取得完整值。

```sh
xcodebuild -project FoodFit.xcodeproj -scheme FoodFit -configuration Debug \
  -destination 'generic/platform=iOS' -showBuildSettings |
  awk '$1 == "DEVELOPMENT_TEAM" && $2 == "=" && length($3) == 10 && !printed {
    print "com.foodfit.journal." $3
    printed = 1
  }'
```

把输出整行填入 **Signing & Capabilities → Bundle Identifier**。首次安装也可以用这个标识。如果此前用过自定义标识，填原来的值。命令没有输出时，先确认 Team 已选好，并且终端所在文件夹包含 `FoodFit.xcodeproj`。

[Apple 个人团队说明](https://developer.apple.com/help/account/basics/about-your-developer-account) · [Apple HealthKit 自动签名说明](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)

## 3. 装到 iPhone

1. 在 Xcode 顶栏选择 **FoodFit** 和 Connected 设备列表中这台 **iPhone** 的名称。出现 **Register Device** 时，点它。
2. 点左上角的 **▶ Run**，或者按 **⌘R**。如果 Xcode 要求开启开发者模式，在 iPhone 进入「设置 → 隐私与安全性 → 开发者模式」，开启后按提示重启并再次确认，再回 Xcode 点运行。
3. 等 Xcode 完成签名和安装。iPhone 上看到「食动日记」并能打开，就完成了安装。

如果无法选中手机，回到第一步确认设备连接。如果 Xcode 报签名或描述文件错误，记下完整报错，并检查 `Signing & Capabilities` 的 Team、Bundle Identifier 和 HealthKit。

[Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

## 4. 在 iPhone 上验收 Apple 健康

1. 打开「食动日记 → 设置 → 连接 Apple 健康」。使用者在 iOS 授权页允许读取**活动能量、静息能量和体能训练**。
2. 回到「饮食与消耗」，选健康 App 里已有记录的一天并下拉刷新。用没有手动补录消耗的日期检查是否出现「Apple 健康」来源和对应运动记录。

Personal Team 的开发描述文件有效期是 7 天。续签时，用同一 Apple 账户和 Bundle Identifier 再点一次 Xcode 的 **▶ Run**。[Apple 个人团队限制](https://developer.apple.com/help/account/basics/about-your-developer-account)
