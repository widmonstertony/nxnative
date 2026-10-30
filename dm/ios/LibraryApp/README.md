# 游戏库界面试用版

这是一个 iOS 16.1+ 的封面界面原型。它在设备上读取已安装的
`org.nxnative.*` 游戏应用，并通过本机 MCP 服务打开所选应用。
封面图只从用户本机已有的游戏包提取，放在被 Git 忽略的
`LocalCovers/` 目录；仓库中只包含游戏库自己的图标。

这个原型**还不是多游戏运行宿主**。不能因为封面出现、点击能打开
另一个应用，就删除原游戏应用或其存档。正式单 App 交付需要：

1. 在一个签名的 App 内为每款游戏选择正确的宿主配置及代码。
2. 按 title ID 隔离 RomFS、着色器、DLC、设置、日志和存档。
3. 迁移后逐款核对资源与存档哈希，并在 M2、A10X 上启动验证。
4. 验证完成后才能移除旧应用；任何失败都保留原应用和数据。

构建界面原型：

```sh
xcodegen generate
xcodebuild -project NXGameLibrary.xcodeproj -scheme NXGameLibrary \
  -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

原型源码、图标和操作说明可公开；游戏资源、存档和签名资料不能提交。
