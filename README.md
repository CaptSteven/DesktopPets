# DesktopPets

中文 | [English](README.en.md)

一个小巧的 macOS 桌宠：一个无边框、始终置顶的角色，会在屏幕底部来回散步，可以用鼠标拖着走，还会弹气泡说话。

## 快速开始

```sh
./Scripts/make-placeholder-skin.sh   # 生成一个占位角色（已经有自己的素材就跳过）
./Scripts/pack-skins.sh              # 把散帧打包成 sprite sheet + GIF 预览
swift run DesktopPets                # 运行
```

在宠物身上点右键，可以打开 **Speak**、**Reload Skin and Phrases**、**Reset Position**、**Quit**。

打包成可双击的 `.app`：

```sh
./Scripts/build-app.sh               # 产出 dist/DesktopPets.app
```

## 换用你自己的素材

新建目录 `Resources/Skins/<皮肤名>/`，结构如下：

```
Resources/Skins/mypet/
  skin.json                        # 手写：fps、loop、scale、anchor、点击透明度阈值
  src/                             # 逐帧图片，每个动作一个子目录
    idle/000.png 001.png 002.png 003.png
    walk/000.png ... 005.png
    drag/000.png ... 003.png
    sleep/000.png ... 003.png
    click/000.png ... 005.png      # click 是唯一不循环的动作
  build/                           # 打包器生成，不要手动改
  preview/                         # 打包器生成的 GIF，用来肉眼检查节奏
```

加载器会强制检查以下规则：

- **文件名排序就是播放顺序**，所以要用零填充（`000.png`，不是 `0.png`）。
- **同一套皮肤内所有帧尺寸必须一致**，并与 `skin.json` 里的 `frameSize` 相同。
- **帧必须有透明背景。** 透明像素正是"点击穿透到下层窗口"的依据。
- `idle` 和 `walk` 是必需的。`drag`、`sleep`、`click` 可选；缺哪个，宠物在那个动作上就退回用 `idle`。
- **不认识的动作名会直接报错**，所以把 `sleep` 拼成 `sllep` 会立刻失败，而不是默默什么都不发生。
- 想彻底跳过某个动作，要同时删掉 `skin.json` 里的条目**和**它的 `src/` 目录。打包器比 App 更严格，要求每个声明的动作都得有帧。

`skin.json` 示例：

```json
{
  "name": "mypet",
  "frameSize": { "width": 64, "height": 64 },
  "scale": 2,
  "anchor": "bottomCenter",
  "hitAlphaThreshold": 16,
  "states": {
    "idle":  { "fps": 6,  "loop": true },
    "walk":  { "fps": 10, "loop": true },
    "drag":  { "fps": 8,  "loop": true },
    "sleep": { "fps": 3,  "loop": true },
    "click": { "fps": 12, "loop": false }
  }
}
```

- `scale` 是显示倍率：64×64 的帧在 `scale: 2` 时画成 128×128 点，所以建议按 2 倍图来画，Retina 屏上才清晰。
- `anchor` 指精灵上的哪个点跟着鼠标走、并被记住位置（`bottomCenter` 就是"脚底"）。
- `hitAlphaThreshold` 是像素 alpha 达到多少才算"可点击"。

`row` 和 `frames` **不需要手写** —— 打包器会补上，并写入 `build/skin.json`。

### 台词文件

`Resources/Phrases/*.json` 是一个「分类 → 台词数组」的扁平对象。多个文件会合并，所以你可以随意增加：

```json
{
  "click": ["哎呀，别戳我～"],
  "idle":  ["今天天气不错。"],
  "drag":  ["放我下来！"],
  "sleep": ["Zzz……"]
}
```

分类缺失时会退回 `idle`；文件写坏了只会让宠物闭嘴，不会让程序崩溃。

## 命令一览

| 命令 | 作用 |
| --- | --- |
| `swift run DesktopPets` | 从源码运行，素材取自仓库里的 `Resources/`。 |
| `./Scripts/test.sh` | 跑单元测试。 |
| `./Scripts/make-placeholder-skin.sh` | 重新生成占位皮肤。 |
| `./Scripts/pack-skins.sh [皮肤名 ...]` | 把散帧打包成 sheet 和 GIF 预览。 |
| `./Scripts/build-app.sh` | 构建并 ad-hoc 签名 `dist/DesktopPets.app`。 |
| `swift run DesktopPets --verify-skin` | 无界面自检：加载皮肤和台词，打印摘要后退出。 |

`--verify-skin` 是不开窗口就检查新素材的最快方式，它同时也是 `build-app.sh` 对打包产物跑的冒烟测试。

`pack-skins.sh` 会把刚写出的 sheet 重新读回来，逐帧和源 PNG 做**逐字节**比对。因为行列或上下翻转算错时，sheet 看起来依然是"一副正常的图" —— 只有比像素才是诚实的检查。

## 代码结构

```
Sources/
  DesktopPetsCore/     纯逻辑：清单解析、布局、行走、动画计时、状态机、选台词、配置、素材查找。
                       不依赖 AppKit，所以不用窗口服务器就能全部单元测试。
  DesktopPets/         AppKit 外壳：窗口、精灵绘制、鼠标处理、气泡。
  SkinPacker/          构建期美术工具，不会打进 bundle。
Resources/             运行时内容，打包时整体拷进 .app
Packaging/Info.plist   bundle 元数据（LSUIElement，所以没有 Dock 图标）
```

`Resources/` 是**故意不**声明成 SPM bundle resources 的。它属于运行时内容：加一套皮肤永远不用改 `Package.swift`，`build-app.sh` 也能整个目录原样拷贝。`AssetLocator` 分三级查找它 —— `DESKTOPPETS_RESOURCES` 覆盖、`.app` 里的 `Bundle.main.resourceURL`、以及 `swift run` 时的源码树。

## 已知限制

- **点击穿透是轮询的，不是事件驱动的。** 驱动动画的那个 30Hz tick 顺便采样光标下的 sprite alpha，然后切换 `ignoresMouseEvents`。这样避开了全局事件监听器的权限与焦点麻烦，代价是点击开始穿透前最多有约 33ms 延迟。真要在意的话，`MousePassthrough` 是唯一需要改的地方。
- **App 是 ad-hoc 签名的。** 只能在构建它的这台机器上跑。拷到别人机器上会被 Gatekeeper 拦；要分发得配开发者证书和 `notarytool`。
- **最低系统版本是 macOS 14**，因为工具链自带的 Swift Testing 框架是按 14.0 构建的。
- **跑测试需要手动传插件路径。** 当激活的开发者目录是 CommandLineTools 时，SwiftPM 不会为 Swift Testing 的宏插件传 `-plugin-path`，`@Test` 会报 "plugin for module 'TestingMacros' not found"。`Package.swift` 和 `Scripts/test.sh` 都会推导并传入该路径；如果裸跑 `swift test` 出问题，用脚本。

### 写测试时的一个坑

Swift Testing 会**分别**捕获比较表达式的两侧。用一个 `CGFloat` 去比一个*复合*表达式时：

```swift
#expect(clamped.y == -200 + 1080 - 64)   // 结果是 false，尽管两边都是 816
```

右侧会被推断成 `Int`，于是数值相等却判为不等。裸字面量没问题。请始终和**有明确类型的值**比较：

```swift
let expected: CGFloat = 816
#expect(clamped.y == expected)
```

## 还没做的部分

- **开机自启**（`Sources/DesktopPets/Launcher/` 目前是空目录）和设置面板（`Settings/`）。目前右键菜单够用。
- 同时养多只宠物，以及窗口避让。
