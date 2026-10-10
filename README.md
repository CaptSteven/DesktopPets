# DesktopPets

中文 | [English](README.en.md)

一个小巧的 macOS 桌宠：一个无边框、始终置顶的角色，会在屏幕底部来回散步，可以用鼠标拖着走，还会弹气泡说话。

## 快速开始

```sh
./Scripts/make-placeholder-skin.sh   # 生成一个占位角色（已经有自己的素材就跳过）
./Scripts/pack-skins.sh              # 把散帧打包成 sprite sheet + GIF 预览
swift run DesktopPets                # 运行
```

## 操作方式

| 操作 | 效果 |
| --- | --- |
| **左键点击** | 在鼠标位置打开菜单：说话开关、切换语言、重新载入、回到默认位置、退出 || **左键拖动** | 把宠物拽到别处；松手后会落回屏幕内并记住位置 |
| **右键点击** | 弹出**皮肤列表**，切换模型 / 版本 |
| **菜单栏图标**（🐾） | 上面全部内容，永远可达 |

菜单语言在没设置过时跟随系统语言（`zh*` → 中文，其他 → 英文），切换后会被记住。语言开关在
左键菜单里（以及菜单栏图标里），右键让给了皮肤切换。

**切换语言会同时切换菜单和宠物说的话** —— 中英各有一套台词文件，见下文。

### 为什么菜单栏上还有一个图标

宠物身上的所有操作都挂在一个**需要点中的精灵**上，那是单点故障：如果宠物被挡住、跑到屏幕外、
或者收不到点击，你就没有任何办法退出它。菜单栏图标不依赖宠物窗口，是 `.accessory` 应用的
标准配置，专门用来堵死"关不掉"这种情况。

### 菜单是自绘的，不会抢焦点

菜单面板用的是 `.nonactivatingPanel`：它能接收点击，但**不会把你当前的 app 顶下去**。所以
菜单打开时你在别的程序里打字不会被打断。

代价是**按 Esc 关不掉菜单**（收键盘事件需要成为 key window，而那就意味着抢焦点）。关闭方式：
选中某一项、点到面板外面、或者 30 秒无操作自动关闭。

## 排查"点不动宠物"

## 排查"点不动宠物"

整个宠物窗口都接收点击，不再逐像素判定，所以"点不动"基本只有两种可能，日志都能看出来：

```sh
log stream --predicate 'subsystem == "com.desktoppets.DesktopPets"'
```

- **日志里没有 `mouseDown`** → 点击根本没送到窗口。通常是别的东西盖在上面（比如自动隐藏的 Dock 滑出来），或者宠物被拖到了另一块屏幕。
- **有 `mouseDown` 但没有反应** → 事件到了，是处理逻辑的问题，把日志贴出来即可。

`mouseDown at (x, y)` 里的坐标是**窗口内坐标**，可以拿来确认点在了精灵的哪个位置。

### 曾经的一个坑（已修）

之前是**逐像素**判定：30Hz 轮询光标下的 alpha，透明处就穿透。结果是"能不能点中宠物"取决于**美术**和**当前帧**：

| `guitarist` 状态 | 不透明占比 | 窗口中心 alpha |
| --- | --- | --- |
| idle | 16% | 255 |
| walk | 17% | 255 |
| **sleep** | **12%** | **0** |

宠物 **30 秒无交互就会睡着**，而睡姿只有 12% 不透明、且窗口正中心是空的。睡眠状态又**只有点击才能唤醒**——于是"点中心 → 穿透 → 永远醒不过来"，表现就是"显示一会儿之后就没法点击、也没法拖动了"。

现在整个窗口都可点，宠物永远抓得住。代价是窗口四角的空白也会吃掉点击，但窗口只有精灵那么大（这里是 128pt），影响很小。

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

## 多个模型 / 多个版本怎么放

### 唯一的规则

程序扫描 `Resources/Skins/`，**只有真正包含 `skin.json` 的目录才算一个皮肤**（顶层，或顶层目录的下一层）。

这一条规则就是"分组目录"能存在的原因：一个没有 `skin.json` 的目录不会被当成皮肤，可以随便用来分类。

### 四种常见摆法

**1. 只有一个角色** —— 菜单里出现 `mypet`

```
Resources/Skins/
  mypet/
    skin.json
    src/idle/000.png ...
```

**2. 多个不同角色（平级）** —— 菜单里出现 `bird`、`cat`、`dog`（按字母序）

```
Resources/Skins/
  cat/   { skin.json, src/ }
  dog/   { skin.json, src/ }
  bird/  { skin.json, src/ }
```

**3. 同一个角色的多个版本（分组）** —— 菜单里出现 `cat/v1`、`cat/v2`

```
Resources/Skins/
  cat/
    v1/            { skin.json, src/ }
    v2/            { skin.json, src/ }
    reference/     ← 没有 skin.json，不会被当成皮肤
      turnaround.png
```

**4. 既是皮肤、又是分组** —— 菜单里出现 `cat`、`cat/v1`、`cat/v2`

```
Resources/Skins/
  cat/
    skin.json      ← cat 本身也是一个可直接使用的皮肤
    src/
    v1/  { skin.json, src/ }
    v2/  { skin.json, src/ }
```

### 需要知道的几条

- **只往下找一层。** `cat/v1/final/` 不会被发现 —— 故意的，否则菜单里的名字会长到没法读。
- **`build/` 和 `preview/` 永远被排除**，即使里面有 `skin.json`（打包器就会往 `build/` 里写一个），也不会被当成皮肤。
- **菜单里显示的就是目录路径**（`cat/v1`），不是 `skin.json` 里的 `name` 字段。名字即路径，不用两边对账。
- **每个皮肤可以有各自的 `frameSize` 和 `scale`**。切换时窗口会按新皮肤重算大小，不需要改代码。
- **删皮肤就是删目录**，然后在菜单里选一次"重新载入皮肤与台词"。

### 怎么切换

**在宠物身上点右键** → 弹出皮肤列表，当前那个带勾。选一个就切换，不用重启。

切换会重新读取皮肤、帧和台词，并按新皮肤调整窗口大小；宠物当前的位置会保留。菜单栏的 🐾 图标里也有同一份皮肤列表。

### 仓库里自带两个示例

| 标识 | 位置 | 说明 |
| --- | --- | --- |
| `placeholder` | `Resources/Skins/placeholder/` | 顶层皮肤，橘色 |
| `placeholder/grey` | `Resources/Skins/placeholder/grey/` | 同一角色的**嵌套变体**，灰色 |

两者构图完全一样，只有配色不同 —— 这样你右键切换时一眼就能看出生效了。跑 `Scripts/make-placeholder-skin.sh` 会重新生成它们。

加载器会强制检查以下规则：

- **文件名排序就是播放顺序**，所以要用零填充（`000.png`，不是 `0.png`）。
- **同一套皮肤内所有帧尺寸必须一致**，并与 `skin.json` 里的 `frameSize` 相同。
- **帧必须有透明背景。** 为了好看，也为了不在宠物周围留出一块实心色块。
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

### 台词文件（中英各一套）

```
Resources/Phrases/
  zh.json     中文台词
  en.json     英文台词
```

**文件名就是语言代码**，宠物说什么话由菜单语言决定 —— 切成英文，菜单和台词一起变。（否则会出现"英文菜单 + 宠物说中文"的割裂。）

每个文件是「分类 → 台词数组」的扁平对象：

```json
{
  "click": ["Hey, stop poking me!"],
  "idle":  ["Nice weather today."],
  "drag":  ["Put me down!"],
  "sleep": ["Zzz..."]
}
```

- 分类缺失 → 退回 `idle`
- **少了某个语言文件** → 那个语言下宠物不说话，程序照常运行
- **文件写坏了** → 宠物闭嘴并在日志里报错，不会崩
- 加第三种语言：给 `AppLanguage` 加一个 case、`MenuStrings` 加一份文案，再放一个 `<代码>.json` 即可

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

- **整个宠物窗口都接收点击**，不做逐像素穿透（原因见上文"曾经的一个坑"）。所以宠物周围那一圈空白也会吃掉点击，不再传给下层窗口。
- **菜单面板打开时会挂一个全局鼠标监听**（只监听鼠标，不需要辅助功能权限），用来在点到别处时关闭面板；不打开菜单时则完全不挂。
- **菜单不能用 Esc 关闭**，原因见上文（`.nonactivatingPanel` 不抢焦点）。
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

- **开机自启**（`Sources/DesktopPets/Launcher/` 目前是空目录）和设置面板（`Settings/`）。目前菜单 + 皮肤列表够用。
- 同时养多只宠物，以及窗口避让。
