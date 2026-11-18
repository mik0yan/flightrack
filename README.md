# SkyLens 天际

基于 adsb.fi 的原生 iPad 航班跟踪应用。地图按查询中心显示周围飞机；AR 根据设备位置、相机姿态和飞机报告的位置，将航班标签投影到相机视野中。点击标签或航班列表可查看航班与飞机资料。

支持 iPadOS / iOS 17 及以上，使用 SwiftUI、MapKit、RealityKit 和 ARKit，无第三方运行时依赖。界面以 iPad 分栏布局为主，也适配 iPhone。

## 运行

1. 用 Xcode 打开 `SkyLens.xcodeproj`，选择 `SkyLens` Scheme。
2. 在 `Signing & Capabilities` 中启用自动签名，选择 `xiaonewmi@gmail.com` 对应团队 `52AJW92F8Y`；Debug / Release 均使用 Bundle Identifier `com.xiaonewmi.skylens`。
3. 选择真实 iPad，运行应用。
4. 首次打开以经度 **120.264387**、纬度 **30.17284** 为手动查询中心，查询半径为 **50 公里**。
5. 在设置中选择“使用我的位置”，允许定位后切换到“AR 视野”，再允许相机权限。缓慢移动 iPad，等待方向校准。

地图与详情可在模拟器运行。AR 相机必须使用支持 ARKit 世界跟踪的真实设备。没有本地接收数据时，可在设置中开启“演示模式”体验地图和详情；演示模式不进入 AR。

## 已实现功能

| 功能 | 行为 |
|---|---|
| 周边查询 | 20、50、100 公里；手动坐标或设备当前位置 |
| 持续跟踪 | 前台每 10 秒刷新，可关闭自动刷新或手动刷新 |
| 航班列表 | 按距离排序，搜索呼号、注册号、机型与 ICAO 地址，筛选空中飞机 |
| 地图 | 查询范围、飞机方位图标、选中标记、数据快照与位置年龄 |
| AR | 朝向投影、标签避让、点击查看详情、相机与跟踪状态提示 |
| 航班详情 | 呼号、关联航班号、航空公司、出发与目的机场，以及位置、速度、高度、航迹角 |
| 飞机详情 | 注册号、机型、制造商、ICAO 地址、注册所有者、注册国家及数据源照片链接 |
| 数据状态 | 空结果、网络失败、缺失资料、过期位置、定位精度不足与演示数据均有对应提示 |

## 数据接口

位置使用 [adsb.fi 官方开放数据](https://github.com/adsbfi/opendata) 的 v3 接口：

```text
GET https://opendata.adsb.fi/api/v3/lat/{纬度}/lon/{经度}/dist/{海里}
```

50 公里请求 27 海里，收到数据后再次按实际距离裁剪到 50 公里。客户端控制请求间隔至少 1 秒，后台停止轮询；不需要 API Key。

飞机档案与呼号关联航线使用 [adsbdb](https://www.adsbdb.com/)：

```text
GET https://api.adsbdb.com/v0/aircraft/{ICAO地址}?callsign={呼号}
```

仅在用户选择飞机时查询。飞机档案未知时可继续查询呼号关联航线；资料在内存中缓存 1 小时，最多 128 条，不建立本地航线数据库。

adsb.fi 公共接口适用于个人非商业用途，应用保留可见来源链接。商用或公开发行前，应按其官方说明确认适用的数据许可。adsbdb 航线是参考资料，不代表实时计划航线，不能确认起降时间、延误或当前目的地。

## AR 位置计算与限制

1. 将观察者与飞机的 WGS84 经纬度、高度转换为 ECEF，再转换为观察者的东、北、天局部坐标，计入地球曲率。
2. ARKit 使用 `gravityAndHeading` 对齐方向。AR 世界坐标的 +x 为东、+y 为上、+z 为南。
3. 用 RealityKit 的相机姿态和 ARKit 的相机投影计算屏幕位置，使用固定距离的方向点，避免直接渲染数十公里远的物体产生裁剪与精度问题。
4. 每次查询更新地理方向，屏幕投影随相机持续更新。最多处理 24 架有效飞机，优先显示选中飞机与较近飞机。

AR 使用设备当前位置，不接受远程手动中心。设备位置须在 30 秒内更新，水平精度须在 100 米内；Wi-Fi iPad 的定位可能达不到此条件。位置年龄未知、超过 60 秒、地面状态或高度缺失的飞机不显示 AR 标签。地图保留旧记录，并将过期或时效未知的标记显示为灰色。

飞机高度优先采用几何高度，缺失时采用气压高度。设备海拔缺失时采用 0 米并显示提示；气压高度与设备定位海拔的基准不同，AR 仰角可能有偏差。标签表示接收到的地理方向，应用不通过图像识别飞机，也不推算未知位置。方向精度还受磁场干扰、接收延迟和设备定位影响。

官方实现参考：[ARKit 方向对齐](https://developer.apple.com/documentation/arkit/arconfiguration/worldalignment-swift.enum/gravityandheading)。

## 隐私

- 查询中心与半径发送给 adsb.fi；选择飞机时，ICAO 地址与呼号发送给 adsbdb。
- 相机画面仅在设备内用于 AR 显示，不上传或保存。
- 地图由 Apple 地图提供；照片通过数据源外部链接打开。
- 无用户账户、分析 SDK、后台定位或持久化飞行记录。

## 工程结构

```text
FlightTrack/App/       应用入口、查询状态与设备定位
FlightTrack/Core/      数据模型、接口客户端、地理计算、演示数据
FlightTrack/AR/        RealityKit 相机与 AR 标签投影
FlightTrack/Views/     分栏、地图、详情、设置与显示样式
FlightTrack/Resources/ 权限说明、颜色与应用图标
Tests/                接口解析、请求约束与地理计算测试
Tools/                工程与原始矢量图标生成脚本
```

新增或删除 Swift 文件后，运行 `python3 Tools/generate_project.py` 更新工程。脚本保留已有 Debug / Release 的签名团队和 Bundle ID；已有工程无法解析时会中止，避免清空签名设置。图标已包含在仓库，重绘图标时可运行 `python3 Tools/generate_icon.py`（仅重绘脚本需要 Pillow）。

## 验证

2026-10-04 的验证结果：

- Xcode 27.0：iOS 真机与模拟器目标均完整编译通过，最低部署版本为 iOS 17。
- 核心测试：12 项通过，0 失败。
- 实际 Swift 客户端：成功查询默认坐标 50 公里范围，并解码返回飞机的实时位置、飞机档案与呼号关联航线。
- 当前开发环境没有已安装的模拟器运行时，也没有 iPad；尚未完成界面运行和真实相机、罗盘验证。

2026-10-05 切换签名前的真机验证结果：

- 连接设备为 Kumi（iPhone 15 Plus，iOS 27.0）。使用 Personal Team 签名编译，描述文件包含该设备，签名校验、安装与启动均成功。
- 实机应用成功查询默认坐标周围 50 公里的实时航班，并持续刷新；测试期间观察到 CCA1743、CSN3758、CES6421，以及零架飞机时的覆盖提示。
- CCA1743 详情成功取得参考航线 CA1743 / HGH → XIY，以及 B-6677、Airbus A320-232、Air China 等飞机资料；详情可滚动查看。
- 横屏侧栏改为单一滚动区域，已在实机观察到实时航班、6 架演示航班与可滚动访问的来源信息。AR 准备页也已修复横屏裁切，重新编译、安装后确认正文、启用按钮与底部说明完整显示。
- AR 相机与跟踪实测尚待用户确认将设备当前位置发送给 adsb.fi；标签朝向、罗盘精度及 iPad 布局仍需对应设备与室外实测。

后续统一使用 `xiaonewmi@gmail.com` 对应团队 `52AJW92F8Y` 自动签名，Debug / Release 均使用 `com.xiaonewmi.skylens`。旧 Bundle ID `com.kuanmi.skylens` 无法在该团队注册，因此改用新 Bundle ID 避免跨团队冲突。新配置已编译成功，构建日志确认使用该邮箱的开发证书；签名校验通过，描述文件包含 Kumi，已从设备独立读回确认安装。当前手机锁屏，新签名版本的启动验证待解锁后完成。

核心逻辑通过 Swift Package 测试：

```sh
swift test
```

覆盖接口字段缺失、数值与字符串混合、高度地面状态、半径裁剪、毫秒时间戳、并发限流、详情降级与缓存、WGS84 方位与地球曲率、演示数据标识。

无需签名的编译命令：

```sh
xcodebuild -project SkyLens.xcodeproj -scheme SkyLens \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build

xcodebuild -project SkyLens.xcodeproj -scheme SkyLens \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build
```

真机验收应检查：定位与相机允许/拒绝后的流程；横竖屏和 iPad 分屏；抬头对准已知方向的飞机；切换查询中心与半径；后台恢复；网络失败、零架飞机与过期数据。编译和核心测试无法替代相机朝向与罗盘的实机验证。
