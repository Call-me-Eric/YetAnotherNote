# 开发者手册

这份手册说明**当前代码怎么工作**，以及**改它时哪些约束不能破**。产品想做成什么样见 [idea.md](../idea.md)，还没排进实现的阶段见 [schedule.md](../schedule.md)，用户视角见 [Readme.md](../Readme.md)。

下面每一条都对应当前仓库里的代码；函数名、常量名都是真的，可以直接搜。

## 1. 工程概况

Flutter 应用。包名 `yet_another_page`，组织标识 `dev.yetanotherpage`，macOS 的 bundle id 是 `dev.yetanotherpage.yetAnotherPage`，Android 的 namespace 与 applicationId 是 `dev.yetanotherpage.yet_another_page`。笔记目录后缀 `.yep`，当前磁盘格式版本 `formatVersion = 1`。

目标平台从第一天起就是 macOS、iOS、Android、Windows、Linux，界面只有一套。iOS 和 Android 的平台上还有笔要接，所以平板是笔的验收设备；电脑端用鼠标画，不单独打磨窗口和快捷键。

```text
lib/main.dart                       入口：接上侧键通道，打开库目录
lib/src/ids.dart                    newId()，UUID v4
lib/src/paper.dart                  格式版本、A4 尺寸、默认图层名
lib/src/ink/stroke.dart             笔画模型、采样、因果绘制、拟合、绘制
lib/src/ink/eraser.dart             工具枚举、两种橡皮的命中与裁切
lib/src/ink/text_box.dart           文字框模型
lib/src/input/stylus_side_button.dart  跨平台侧键接口与方法通道
lib/src/storage/atomic_file.dart    原子写
lib/src/storage/note_document.dart  清单、页、层、摘要、OpenNote
lib/src/storage/vault.dart          NoteLibrary 接口与 Vault 实现
lib/src/ui/library_page.dart        笔记库列表与打开笔记的过场
lib/src/ui/note_page.dart           笔记页面的状态、手势、撤销、文字框编排
lib/src/ui/page_canvas.dart         画布：InteractiveViewer、瓦片、实时墨迹
lib/src/ui/text_box_view.dart       文字框渲染与 Markdown 配置
lib/src/ui/markdown_math.dart       公式（LaTeX）渲染
lib/src/ui/layer_panel.dart         图层面板
lib/src/ui/tool_arc.dart            圆弧工具栏
lib/src/ui/title_dialog.dart        标题输入与确认对话框
ios/Runner/AppDelegate.swift        Apple Pencil 捏笔 → 侧键通道
test/                               笔画、橡皮、库、文字、界面
```

依赖故意保持很少：`path_provider`（找应用支持目录），以及文字渲染用的 `markdown_widget`、`markdown`、`flutter_math_fork`。没有状态管理库、没有数据库、没有第三方墨水/画布库。不要为了画笔引入 PencilKit 或别的墨水格式。

`analysis_options.yaml` 用 `flutter_lints`，并把 `build/`、`android/`、`ios/`、`windows/`、`macos/`、`linux/` 排除在分析之外。

常用命令：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

笔记库在应用支持目录下的 `vault/`（`lib/main.dart` 的 `_vaultDirectory`）。iOS 的调试包必须从 `flutter run` 启动，不能从主屏幕点开。

## 2. 数据与画布分开

页面、图层、笔画、文字框是**数据**（`note_document.dart`、`ink/*.dart`）；`page_canvas.dart` 只负责采集指针并绘制；`note_page.dart` 负责把两者接起来并持有界面状态。

分层可以参考 Saber，但**不使用**它的 `.sbn2`，也**不要把它的代码抄进仓库**（Saber 是 GPL-3.0，本仓库是 Apache-2.0）。

## 3. 标识、坐标、纸张

`newId()`（`lib/src/ids.dart`）用 `Random.secure()` 生成 UUID v4。笔记、页面、图层、笔画、文字框都用稳定 id，不靠「第几页」或列表下标认领内容。

坐标原点在页面左上角，y 向下，单位是 point（1/72 英寸）。新建页默认 A4 纵向：宽 595.28、高 841.89（`a4Width`、`a4Height`）。新建笔记带一页 A4 和一个空的墨水图层，层名 `defaultInkLayerName = '墨水'`。

一个对象属于它落笔或创建时所在的那一页。画出页面的部分由页面上的 `ClipRect` 裁掉。现在**没有**把笔画几何裁成页内片段再存盘——裁的是绘制，不是数据。

## 4. 磁盘格式

一份笔记是目录包，不是 zip。库根目录里另有一份 `device.json`，只存 `deviceId`；设备 id 属于这台设备，不属于任何笔记。

```text
vault/
  device.json
  标题.yep/
    manifest.json
    assets/                         预留，图片还没做
    pages/{pageId}/
      page.json
      {layerId}.json
      strokes/{strokeId}.json
```

目录名由标题生成：先去掉首尾空白、去掉结尾的 `.yep`、把 `\ / : * ? " < > |` 换成空格、压缩连续空白；结果为空或是 `.`、`..` 时用「未命名」。重名时依次试 `名字 2.yep`、`名字 3.yep`（`_uniqueDirectoryName`）。标题存在 manifest 里，改标题会改 manifest，并在需要时重命名目录。

`manifest.json`：

```json
{
  "id": "笔记 id",
  "title": "标题",
  "formatVersion": 1,
  "pageOrder": ["页 id，按阅读顺序"],
  "deletedPageIds": ["已删除但文件仍留在磁盘上的页 id"]
}
```

`page.json` 只放纸张和图层顺序，不放对象：

```json
{
  "width": 595.28,
  "height": 841.89,
  "layerOrder": ["从底到顶的图层 id"],
  "deletedLayerIds": []
}
```

`{layerId}.json` 是该层的对象队列。笔画不把点写进这个文件，只留引用；文字框因为还会被改，整份 JSON 留在图层里：

```json
{
  "id": "图层 id",
  "name": "墨水",
  "visible": true,
  "locked": false,
  "deletedObjectIds": ["墓碑"],
  "objects": [
    { "type": "strokeRef", "id": "笔画 id" },
    {
      "type": "text",
      "id": "文字框 id",
      "version": 1,
      "x": 0,
      "y": 0,
      "width": 200,
      "height": 80,
      "source": "# Markdown 原文"
    }
  ]
}
```

`strokes/{strokeId}.json` 是完整笔画，`type` 为 `stroke`。打开笔记时 `_expandStrokeRefs` 把 `strokeRef` 换回完整笔画，找不到对应文件就跳过这一项；图层文件里直接放着完整 `stroke` 的旧数据也读得进来。写回时 `_storedObject` 把笔画收成 `strokeRef`，文字框原样留下。

写入用 `writeAtomic`：先写 `路径.tmp` 并 flush，再 rename 覆盖目标；rename 失败且目标已存在时，先删目标再 rename。写到一半崩溃时原来的文件还在。新建笔记先写 `.{目录名}.partial`，写完再改名成正式目录。

笔画文件只写一次：`_spillStrokes` 看到 `strokes/{id}.json` 已存在就跳过。所以重命名之类的操作不会把每条笔画的点重写一遍（`renameNote` 也不会重读页面）。

> 目前没有格式迁移代码。要改字段，先加 `formatVersion` 分支，不要把 v1 的文件读坏。

## 5. `NoteLibrary` 与 `Vault`

`NoteLibrary` 是存储接口，真库是 `Vault`，测试里用内存实现。所有方法都接收并返回不可变的 `OpenNote`；**不要假设 `Vault` 会改你手里的旧对象**，调用方要把返回值赋回去。

| 方法 | 行为与边界 |
| --- | --- |
| `listSummaries` | 只读每个 `.yep` 的 `manifest.json`，按标题排序；坏目录（`FormatException`、`FileSystemException`）跳过。列表界面用它。 |
| `listNotes` | 打开整份笔记（含页面与笔画），给测试和需要页面内容的调用方用。 |
| `createNote(title)` | 新 id，一页 A4 + 一个空墨水层，经 `.partial` 目录落地。空标题存为「未命名」。 |
| `openNote(dir)` | 按 `pageOrder` 逐页读，跳过 `deletedPageIds` 里的页，展开笔画引用。 |
| `renameNote(note, title)` | 改 manifest 的标题；目标目录名已存在且与当前不同则抛 `NoteNameTaken`；需要时重命名目录。返回的 `pages` 是内存里那份，不重读磁盘。 |
| `insertPage(pageId, before)` | `emptyCopyOf` 复制纸张尺寸与图层结构（名字、可见、锁定），但换成**新的图层 id**、内容为空；先写页文件再改 `pageOrder`。 |
| `deletePage(pageId)` | 只剩一页时抛 `StateError('至少保留一页')`；否则把 id 放进 `deletedPageIds` 并从 `pageOrder` 移除，**页文件保留**。 |
| `deleteNote(note)` | 递归删掉整个 `.yep` 目录。 |
| `moveLayer` / `setLayerVisible` / `setLayerLocked` | `moveLayer` 越界时原样返回；改可见/锁定只重写该层文件，移动层会重写整页。 |
| `saveTextBox` | 同 id 已存在时 `version = 已有的 version + 1`，新框取 `max(version, 1)`。文字框整份存在图层文件里。 |
| `saveStroke` | 同 id 且已经 `finalized` 的笔画直接原样返回，不覆盖（抬笔后几何不再改）。 |
| `changeMarks` | 一次调用同时处理 `add`（新笔画）、`tombstone`（记删除）、`restore`（去掉删除标记）。 |

`PageFile.layers` 从底到顶。`PageFile.moveLayer` / `updateLayer` 都返回新的 `PageFile`，不改原来的列表。

## 6. 墓碑、撤销栈与写盘时机

删除不把对象从队列里抹掉，而是把 id 记进 `deletedObjectIds`。撤销一次删除时，`changeMarks` 的 `restore` 会把这个 id 从墓碑里拿掉。

`_NotePageState` 里有一份界面用的乐观隐藏集 `_hidden`：抬笔橡皮或删除时先把 id 放进去，等 `Vault` 返回新 `OpenNote` 后再清掉，这样界面不会闪回旧笔画。

撤销是线性的：一条 `_MarkEdit` 记 `pageId`、`layerId`、`added`（这次新增的笔画）、`tombstoned`（这次新记的墓碑）。`_commit` 把它压进 `_undoStack` 并清空重做栈；`_retint` 在撤销/重做时交换两边的角色（撤销 = 把 `added` 墓碑掉、把 `tombstoned` 恢复；重做反过来），再调用 `changeMarks`。

- 在笔记里换页**不清空**撤销栈；关掉 `NotePage` 时栈随 State 一起消失，再次打开后旧操作不能撤。
- 删除一页会顺手把该页在撤销栈、重做栈和 `_settled` 里的记录清掉。
- 所有写盘都挂在 `_saveChain` 这条 Future 链上串行执行，避免两次写互相覆盖。

写盘时机是「编辑发生时」，不是退出时：抬笔（`_persist`）、橡皮抬笔（`_commit`）、创建文字框（`_persistText`）、失焦提交、移动结束、改大小结束。关掉笔记只丢撤销栈，不把写入推迟。

## 7. 笔画

### 7.1 存什么

`StrokeObject`：`id`、`tool`（现在钢笔写 `"pen"`）、`color`（`0xAARRGGBB`，钢笔是 `penColor = 0xFF000000`）、`baseWidth`（`penBaseWidth = 3.0`）、`points`、`finalized`。

`StrokePoint`：`x`、`y`、相对起笔的 `time`（秒）、`width`、`height`、`opacity`、`pressure`，可选 `azimuth`、`altitude`。宽和高在采样时就算进点里，抬笔后不再改；渲染直接用这些值，不用新的粗细算法重算旧笔画。

### 7.2 谁能落笔，怎么采样

`drawsInk(kind)`：`stylus`、`invertedStylus`、`mouse` 落笔；`touch`（手指）不落笔，用来平移。文字工具下笔和鼠标也能平移，直到长按被识别成文字手势。

`sampleFromPointer` 从 `PointerEvent` 取采样：只有手写笔事件才读姿态，方位角用 `event.orientation`，高度角用 `π/2 - tilt`，压感按 `pressureMin`/`pressureMax` 归一化后 clamp 到 0..1。鼠标走 `mouseSample`，压感和透明度用固定值，没有姿态。

缺省值：没有压感用 `missingPressure = 0.5`，没有姿态时方位角与高度角为 `null`，透明度 `missingOpacity = 1.0`。

预测点、iOS 的合并触点、Android 的 historical 批次都**还没有**接进采样：Flutter 的 `PointerEvent` 来一个收一个。预测点无论如何都不要写进 `StrokeObject`。

iOS 上 Pencil 的悬停会以鼠标事件进来（系统把 hover 标成 mouse）。悬停只用来画光标，不产生笔画。

### 7.3 因果绘制

实时显示和存盘用的是同一套点。书写过程中 `appendCausalPoint` 逐点追加，抬笔时 `finishStroke` 把尾巴放出来。对一整串原始点再跑一遍就得到最终点列（`bakePenStroke`、`causalPaint`、`densifySamples`）。

已经画出去的点只追加，不回头改。`raw`（原始采样）和 `painted`（已画出的点）**不能是同一个列表**：`appendCausalPoint` 发现两者 `identical` 时会先复制 `painted`。已经因果绘制过的点不要再喂给 `pointsForPaint`，否则会再拟合一次。

lookahead：还没连上的点要等后面的样本才画，`_holdCount` 按相邻采样间隔决定等几个——间隔 ≥ 24 ms 等 4 个，≥ 14 ms 等 3 个，其余等 2 个。抬笔时 `finishStroke(hold: 1)` 把尾巴全放出来。

### 7.4 形状怎么拟合

拟合是**局部**二次曲线，不是整条笔画一次拟合。窗口是 `raw[index-1, index+2)`，x 和 y 分开做最小二乘：`p(t) = at² + bt + c`。`StrokeCursor` 里的 `_PolySums` 用滑动窗口加减样本，避免每个点都从头求和；缓存的多项式先用 `_polyFits`（平均误差 ≤ 8）判断还能不能用。

曲线端点钉在真实采样上：先算出曲线，再按参数把起点和终点的误差线性摊回去，所以画出来的曲线一定经过这两个采样点。

一条弦怎么处理，由 `_appendArc` 决定：

| 条件 | 结果 |
| --- | --- |
| 弦长 < 1.5（`minFitDistance`） | 直接收下终点，不拟合 |
| 弦长 < 8（`directJoinDistance`）且估计弓高 < 0.7 | 走直线，点距 `straightSpacing = 1.0` |
| 二次曲线中点偏离弦超过允许弓高 | 退回直线 |
| 其余 | 沿二次曲线采样；允许弓高 > 2 时用更密的 `tightSpacing = 0.4` |

允许弓高由转角估计（`_bulgeForTurn`）得到，乘 1.35 且至少为 1；转角太平或者接近掉头时估计为 0，短弦就会走直线。

### 7.5 宽和高

`_widthFromPrevious` 在采样时算：`width = baseWidth × (1.1 - 0.2 × pace) × (0.7 + 0.6 × pressure)`，其中 `pace = clamp(speed / 900, 0, 1)`，速度由相邻两点的距离与时间差得到；压感为 0 时按 `missingPressure` 处理。宽和高始终相等。

### 7.6 画出来

`paintStroke` 用圆头 `drawLine` 把相邻点连起来，线宽取两端宽度的平均值；只有一个点时画圆。`paintStrokeCover` 用更宽的圆头描同一条线（`pad` 外扩），给橡皮的遮盖与挖空用。`outlineOf` 把点列包成一条带粗细的闭合 `Path`。

### 7.7 现在只被测试用到的 API

`densifySamples`、`undrawnStrokes`、`outlineOf` 在生产代码里没有调用方，只被 `test/stroke_test.dart` 使用；常量 `curveWindow = 0.032` 目前没有任何引用。改动它们前先想清楚是删掉还是接进管线，不要留着一半的旧实现。

## 8. 画布与瓦片

`PageCanvas` 把所有页纵向排开，页间 `pageGap = 32`，四周 `Padding(48)`。外面是 `InteractiveViewer`：`constrained: false`、`panEnabled: false`、`scaleEnabled: true`、`minScale: 0.2`、`maxScale: 4`、`boundaryMargin: 800`。**平移是 `NotePage` 自己在变换矩阵上做的**，不交给 InteractiveViewer；捏合缩放仍由它负责。

每一页是 `_PageSheet`：白底、`ClipRect`，里面从下到上是「已提交墨迹 → 实时笔画 → 页码标签 → fade 层 → 橡皮预览框 → 文字框层 → 笔尖光标」。当前页边框用主色（宽 3），其他页用轮廓色（宽 1）。页左下角小字显示页 id，方便对文件。

`_CommittedInk` 把已提交的墨迹按 `_tileSize = 256` point 的瓦片光栅化：每块瓦片是一张 `ui.Image`，外包 `RepaintBoundary`，`FilterQuality.none`，按 1:1 贴上。像素尺寸是 `round(瓦片宽高 × devicePixelRatio × viewScale)`。

- `viewScale` 是 `NotePage._tileScale`，只有比例变化超过 **0.04** 才更新（`_settleScale`）。比例一变，瓦片代数 `_generation` 加一，旧图丢掉重画；捏合过程中不重切瓦片，旧图被拉大或缩小。
- `picture.toImage` 是异步的。抬笔后**不要**先清掉实时墨迹再等瓦片：实时层要留到对应瓦片落地（`_persist(publish: true)` 会在 `saveStroke` 返回后把 `_settled` 里的那条拿掉）。
- 橡皮打上去的 `InkPatch` 也先画进相关瓦片，`onApplied` 之后再收起补丁。`_dabbed` 标记让「擦掉一条笔画」不必整页重画；只有真正删掉笔画时（`removed` 非空）才清空瓦片重建。

`_LiveInk` 负责正在画的那条笔画，不每帧重画整页：把已经稳定的前缀冻成瓦片，末端保留约 **8** 个点做矢量尾巴，每多大约 **24** 个点再烘一批。换笔画或缩放比例变化超过 0.04 时清空重来。

`StrokeFade` 是对象橡皮的拖动预览：`_FadePainter` 用 `saveLayer` + `Color(0x99FFFFFF)` 的 `paintStrokeCover`（外扩 `_pad = 2`）把整条笔画洗淡，边缘和内部同一透明度。

## 9. 橡皮

`InkTool`：`pen`、`text`、`objectEraser`、`regionEraser`。橡皮半径 `eraserRadius = 14`。

**对象橡皮**：拖动时用 `_InkLocator`（格边长 `cell = 48`，只测橡皮附近的笔画）找出相交的笔画放进 `StrokeFade`；抬笔时把这些 id 一起墓碑，并用 `_punchStrokes` 先铺不透明白遮盖、再 `BlendMode.dstOut` 挖掉（外扩 3），然后清掉 fade。用的是已经在 fade 里的列表，不再全页重扫。

**区域橡皮**：拖动时每移动超过 1 point 就 `_punchEraser` 一次（`dstOut`，线宽 `(eraserRadius + 2) × 2`），立刻挖掉碰到的瓦片；抬笔时对当前层里所有未删除、未隐藏的笔画跑 `eraseRegion`：整条擦掉得到空列表，部分擦掉得到若干新 `StrokeObject`（**新 id**、`finalized: true`、点还是原来存下的宽高，只是少了被擦的那段），旧 id 全部墓碑。

`_editableStrokes` 把图层文件里的笔画和 `_settled`（刚抬笔、可能还没写回磁盘的笔画）合起来，按 id 去重。

对象橡皮的挖空会连笔画底下的墨迹一起挖掉；撤销只把这条笔画画回来，**底下被挖掉的墨迹不会自动补回**。撤销一条普通钢笔（只有被拿掉的 id、没有先前的挖空）会清空瓦片并重画剩余笔画。

当前可画图层是该页**最上面一层可见且未锁定**的图层（`_drawingLayer`）；隐藏或锁定的层不接收新笔画。

## 10. 手势与平移

`NotePage` 用 `TickerProviderStateMixin`，在 `PageCanvas` 外面套了一层 `Listener`（`behavior: translucent`），三个回调都在 `NotePage` 上：`_fingerDown` / `_fingerMove` / `_fingerUp`。

- 只有触摸、或者文字工具下的笔和鼠标参与平移（`_fingerDown` 里的 `pans`）。
- 单指平移。速度用相邻位移做指数混合（旧值 0.45、即时值 0.55）。抬笔时速度小于 80 不甩；Ticker 里每帧乘 `exp(-3.4 × dt)`，速度小于 12 停止。
- 第二根手指按下会把 `_multiTouch` 置上并清掉速度，两指平移**不甩**；`_multiTouch` 在最后一根手指抬起时清掉。
- 手指正在平移时如果笔落下，`_endMoving` 结束平移并把当前还没抬起的触摸指针放进 `_ignoredFingers`，这些手指要抬起之后才能再平移。
- 文字工具下，长按计时开始时 `onSuppressPan` 把该指针从平移里拿掉；按下后移动超过 10 point（`_textSlop`）且长按还没成立，就取消文字计时，这次手势继续当平移。
- `InteractiveViewer` 自己的双指缩放惯性保持 Flutter 默认，不要把 `interactionEndFrictionCoefficient` 改成 1。
- 进入笔记后只居中一次：视口中心对齐页面中心，四周留 48（`_scheduleCenter`，在首帧后执行）。

缩放按钮（`_zoom(1.2)` / `_zoom(1 / 1.2)`）和捏合结束走同一个 `_settleScale`。

## 11. 文字框

模型是 `TextBox`：`id`、`version`、`x`、`y`、`width`、`height`、`source`。`source` 是 Markdown 原文。文字框属于创建时所在的那一层，和笔画一样是图层里的对象。

**创建**：文字工具下按下约 380 ms（`_textHold`）后开始拖，预览先半透明，宽 ≥ 72（`_textMinWidth`）且高 ≥ 44（`_textMinHeight`）后变不透明；只有抬笔时尺寸够了才 `onTextCreate`。点一下空白不是创建，而是 `onTextBlur`（结束编辑、取消选中、收起焦点）。

**编辑**：短按已有文字框进入编辑，看到的是 `TextField` 里的源码；失焦后改用 `MarkdownBody` 渲染。渲染字号不随框缩放：正文 `textBodySize = 14`，h1 22、h2 18、h3 16，列表缩进用渲染器自己的 `ListConfig(marginLeft: 24)`。空源码显示灰色「文字」。编辑时有边框和半透明白底，退出编辑后没有。

**公式**：`markdown_math.dart` 按 `markdown_widget` 示例的写法，把 `$...$` 与 `$$...$$` 交给 `flutter_math_fork` 的 `Math.tex` 绘制，解析失败时回退成红色原文。不要去写只认 `\frac` 的解析器。

**选中、移动、改大小**：长按已有文字框，或在文字工具下悬停该框时按侧键，都会选中它。选中后可以拖动框体移动（位置 clamp 在页内），拖右下角外的方块改大小（`_TextFrame` 内先 clamp 到 64..2000 / 40..2000，`_resizeText` 再 clamp 到页面边界），框旁边出现「编辑」和「删除」菜单。删除走墓碑，因此在撤销栈上。离开文字工具会清掉正在编辑和选中的 id。

**草稿与顺序陷阱**：`onChanged` 把草稿放进 `_textDrafts`，**不为此 `setState`**。失焦提交必须先读 `TextEditingController.text`，再把 `widget.box.source` 写回 controller——顺序反了会把刚打的字用旧的空源码盖掉。`_persistText` 只有在这份保存的源码、宽、高仍然对得上当前草稿时才丢掉草稿，避免一次较晚的空保存把字抹掉。`_TextFrame` 用 `_committed` 标记防止焦点回调和 `didUpdateWidget` 各提交一次。

进入笔记时 `_editingTextId` 从 `null` 开始，并在首帧后 `unfocus`，所以不会有文字框自动进入编辑。

中文输入法的组字过程仍会进入文字框（日程第 8 阶段），文字编辑本身也没有独立的撤销栈；文字框的**删除**已经在墨迹撤销栈上。

## 12. 侧面按键与工具弧

侧面按键不是 Apple Pencil 专有功能。各平台只报告「侧面按键按下了」，**应用才决定做什么**。

Dart 接口是 `StylusSideButton`（`lib/src/input/stylus_side_button.dart`）：

- `addListener` / `removeListener`：界面注册。同时有多个监听者时只调用**最后注册**的那个——笔记页在库页面之上，所以打开笔记时由笔记页接收。
- `report(Offset? globalPosition)`：平台或测试调用，坐标是全局坐标，平台不知道就传 `null`。

原生走方法通道 `dev.yetanotherpage/stylus`，方法名 `sideButton`，参数是可含数字 `x`、`y` 的 Map；没有坐标就传空 Map 或不传。`main` 里 `stylusSideButton.attachPlatform()` 接上这个通道。

iOS 的适配在 `ios/Runner/AppDelegate.swift`：`ApplePencilSideButton` 在 `didInitializeImplicitFlutterEngine` 里注册通道，并在应用回到前台时重新挂到窗口上；`PencilSqueezeRelay` 用 iOS 17.5+ 的 `UIPencilInteraction`，只在捏笔阶段 `.ended` 时上报，有 `hoverPose` 就带上坐标。**不要在这里决定打开工具栏还是选中文字框。**

收到按键后：

- 笔记页：文字工具且正悬停在某个文字框上 → 选中该框；否则开/关圆弧工具栏。
- 库页面：正悬停在某条笔记上 → 打开重命名/删除菜单。

圆弧工具栏（`tool_arc.dart`）：半径 108 的上半弧，按钮 48，项为钢笔、文字、对象橡皮、区域橡皮、撤销、重做（key 分别是 `arc-pen`、`arc-text`、`arc-object-eraser`、`arc-region-eraser`、`arc-undo`、`arc-redo`）。轨道透明，只有图标圆和一条细线。撤销/重做不关闭圆弧，切换工具会关闭。

## 13. 悬停光标

非触摸的 hover 显示笔尖：钢笔是小点（白 4.5 / 黑 2.4），橡皮是白底黑边的圆圈，半径用 `eraserRadius`。文字工具不显示点也不显示圆，但仍把位置交给 `onTip` 和 `onTextHover`，供侧键选中文字框。按下绘画时笔尖位置继续更新。不要对悬停坐标做几何预测。

## 14. 图层与库界面

图层面板把 `page.layers` 倒过来画，让最上面的层出现在列表上方；每行可以隐藏、锁定、上移、下移，最上面和最下面的层对应的方向按钮置灰。顺序存在 `layerOrder` 里。隐藏的层不画；锁定的层不能当当前绘制层。目前只能隐藏、锁定、排序——批量加层和合并图层还没做（`deletedLayerIds` 字段已经在格式里占好位）。

库页面列出 `listSummaries` 的结果（副标题显示目录名），长按或「悬停 + 侧键」弹出「重命名」「删除」，右下角「新建笔记」。打开笔记先推一个 `_NoteGate`，显示「正在打开笔记」，等 `openNote` 完成后才构建 `NotePage`；新建笔记也走这道门，返回后重新列一遍。

> 写界面测试时，进度圈还在转的时候**不要** `pumpAndSettle`，会超时。`test/widget_test.dart` 在过场期间用显式的 `pump(Duration)`，等过场结束才 `pumpAndSettle`。

## 15. 测试

```bash
flutter test
```

- `test/vault_test.dart`：用真实临时目录（`Directory.systemTemp.createTemp`），是普通 `test()`，**不要**放进 `FakeAsync` 里等真实磁盘。覆盖设备 id、建/开/改名/删除、插页删页、图层可见性与顺序、抬笔后形状不变、墓碑与恢复、文字框版本号。
- `test/stroke_test.dart`：锁住采样、lookahead、拟合与宽度，包括鼠标固定值、因果点不回改、圆上的弦不塌成直线。
- `test/eraser_test.dart`：锁住命中与裁切——整条命中、整条擦空、部分擦掉留两段且宽高不变、新 id 与旧 id 不同。
- `test/text_box_test.dart`：界面测试，确认标题、列表、强调和 `$...$` 公式真的画出来（`find.byType(Math)`），且源码里的 `\frac`、`$` 不再出现在可读文本里。
- `test/widget_test.dart`：用内存库 `_MemoryLibrary` 走一遍新建/打开笔记，并用 `stylusSideButton.report` 确认侧键能开、能关、能选工具。

约定：

- `TextEditingController`、`FocusNode`、`ValueNotifier`、`Ticker` 必须在 State 里 `dispose`。
- `_MemoryLibrary implements NoteLibrary`，用不到的接口方法抛 `UnimplementedError`；`NoteLibrary` 新增方法时这里必须补上，否则测试编译不过。
- 库测试不依赖应用支持目录，也不依赖真实设备。

## 16. 改代码时不要破坏的事

- 抬笔后的笔画几何不再修改。新外观写成新 id，旧 id 墓碑。
- 预测点、合并触点的重复点，都不要写进 `StrokeObject`。
- `raw` 与 `painted` 不要共享同一个列表；实时笔画的 `shouldRepaint` 不要去比较一份还在被改的列表。
- 橡皮的补丁（`InkPatch`）和 fade（`StrokeFade`）都带 `pageId`，不要画到别的页上。
- 区域橡皮只重画碰到的瓦片，不要退化成整页重建。
- 抬笔后不要先清实时墨迹再等瓦片，实时层要留到瓦片落地。
- 单指才有惯性；两指平移不要甩。
- 文字失焦时先读 controller，再重置 controller；`_textDrafts` 的丢弃条件不能放宽。
- 最后一页不能删；删页和删对象都是墓碑，文件留在磁盘上。
- 写盘时机在编辑发生时，不要挪到退出时；所有写盘继续走 `_saveChain`。
- 笔画文件只写一次，`strokes/{id}.json` 不要被反复覆盖。
- 平台代码只调用 `sideButton` / `report`，不要在原生代码里决定界面行为。
- 不要把 PencilKit 用于存储或渲染。

## 17. 已知限制

这些是当前实现的边界，不是「下次顺手改掉」的行为：

- 荧光笔、套索、图片、PDF 导入、导出副本、`.yep` 导入导出、嵌套文件夹、局域网同步都还没做；`assets/` 只是预留目录。
- 中文组字过程仍会进入文字框源码；文字编辑没有单独的撤销栈。
- 长笔画上的圆仍可能有直线棱：被拒绝的弦和过短的弦变成直线之后不会再改，因为拟合只看附近的样本，看不到整圆。要改就改 `_appendArc`，不要在绘制时把已经存下的点整体重算。
- 对象橡皮挖空会挖掉底下的墨迹，撤销不能把它补回来。
- 文字框画在全部墨迹之上，不按图层与笔画交错。
- 双指移动没有我们自己的惯性；捏合的收尾动画是 `InteractiveViewer` 的。
- iOS 合并触点、Android historical 采样还没接进笔画。
- 页外的笔画是画的时候裁掉，不是存盘时裁成页内几何。
- 侧键目前只有 iOS 有原生实现；Android 的 `MainActivity` 还是空模板。
- macOS 的发布 entitlements 只有 `app-sandbox`（调试额外有 `allow-jit` 和 `network.server`），以后做局域网同步要补 `network.client`。

## 18. 给另一个平台接侧面按键

1. 在原生代码里收到笔的侧面按键，并且确认手势已经结束。
2. 平台能给指针位置就换成 Flutter 视图里的全局坐标；给不出就不传坐标，**不要编一个**。
3. 调用方法通道 `dev.yetanotherpage/stylus` 的 `sideButton`，参数 `{"x": ..., "y": ...}`。
4. 不要在原生代码里打开菜单或切换工具。笔记页和库页面已经在监听 `stylusSideButton`。

iOS 的对照实现是 `ApplePencilSideButton` 和 `PencilSqueezeRelay`（`ios/Runner/AppDelegate.swift`）。
