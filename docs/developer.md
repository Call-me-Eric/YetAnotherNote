# 开发者手册

这份手册说明当前代码怎么工作，以及改它时哪些约束不能破。产品想做成什么样见 [idea.md](../idea.md)。还没排进实现的阶段见 [schedule.md](../schedule.md)。用户怎么打开应用见 [Readme.md](../Readme.md)。

应用名是 YetAnotherPage，包名 `yet_another_page`，组织标识 `dev.yetanotherpage`。笔记目录后缀是 `.yep`。格式版本是 `formatVersion = 1`（`lib/src/paper.dart`）。

## 1. 工程

Flutter 工程，目标从第一天就包括 macOS、iOS、Android、Windows、Linux。界面只有一套。电脑端用鼠标画，不单独做窗口和快捷键。

```text
lib/main.dart                 入口，笔记库目录
lib/src/ids.dart              UUID v4
lib/src/paper.dart            格式版本、A4、默认图层名
lib/src/ink/stroke.dart       笔画模型、采样、拟合、绘制
lib/src/ink/eraser.dart       工具枚举、两种橡皮的命中与裁切
lib/src/ink/text_box.dart     文字框模型
lib/src/input/stylus_side_button.dart
lib/src/storage/             原子写、清单、Vault
lib/src/ui/                  笔记库、画布、文字、图层、工具弧
ios/Runner/AppDelegate.swift  Apple Pencil 侧面按键适配
test/                        笔画、橡皮、库、文字、界面
```

依赖只有 Flutter SDK、`path_provider`，以及文字渲染用的 `markdown_widget`、`markdown`、`flutter_math_fork`。不要为了画笔再引入 PencilKit 或别的墨水格式。

数据与画布分开。页面、图层、笔画、文字框是数据；`page_canvas.dart` 只采集指针并绘制。可以参考 Saber 的这个分层，不要使用它的 `.sbn2`，也不要把它的代码抄进仓库。Saber 是 GPL-3.0。

运行：

```bash
flutter pub get
flutter test
flutter run
```

笔记库在应用支持目录下的 `vault/`（`lib/main.dart` 的 `_vaultDirectory`）。iOS 调试包要从 `flutter run` 启动，不能从主屏幕点开。签名团队在 Xcode 里配置。

## 2. 标识、坐标、纸张

`newId()` 生成 UUID v4。页面、图层、笔画、文字框都用稳定 id，不靠“第几页”或列表下标认领内容。

坐标原点在页面左上角，y 向下，单位是 point（1/72 英寸）。新建页是 A4 纵向：宽 595.28，高 841.89。

一条对象属于落笔或创建时所在的那一页。画出页面的部分由页面 `ClipRect` 裁掉，不能跨页。现在还没有把笔画几何裁成页内片段再存盘；裁的是绘制。

## 3. 磁盘格式

一份笔记是目录包，不是 zip。库根目录里还有一份 `device.json`，只含 `deviceId`。设备 id 不属于任何笔记，同步时用它区分设备。

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

目录名由标题生成，后缀 `.yep`。重名时加后缀，保证目录名唯一。标题存在 manifest 里，改标题会改 manifest，并在需要时重命名目录。`renameNote` 返回内存中的页面，不会把每个笔画文件再读一遍。

`manifest.json`：

```json
{
  "id": "笔记 id",
  "title": "标题",
  "formatVersion": 1,
  "pageOrder": ["页 id，按阅读顺序"],
  "deletedPageIds": ["已删除但仍留在磁盘上的页 id"]
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

`{layerId}.json` 是该层对象队列。笔画不把点写进这个文件，只留引用。文字框因为还会改，整份 JSON 留在图层里。

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
      "source": ""
    }
  ]
}
```

`strokes/{strokeId}.json` 是完整笔画，`type` 为 `stroke`。打开笔记时 `_expandStrokeRefs` 把 `strokeRef` 换回内存里的完整笔画。图层文件里已经是完整 `stroke` 的旧数据也能读。写回时 `_storedObject` 把笔画收成 `strokeRef`，文字框原样留下。

写入用 `writeAtomic`：先写 `路径.tmp` 并 flush，再 rename 盖住目标。写到一半崩溃时，原来的文件还在。新建笔记先写到 `.{目录名}.partial`，成功后再改成正式目录。

`NoteLibrary` 是存储接口。真库是 `Vault`。测试里的 `_MemoryLibrary` 必须把接口上的每个方法都实现，用不到的抛 `UnimplementedError`。

列表界面用 `listSummaries`，只读 `manifest.json`。`listNotes` 会打开整份笔记，留给测试和需要页面内容的调用。

删除最后一页会抛 `StateError`，文案是「至少保留一页」。删除页只把 id 放进 `deletedPageIds` 并从 `pageOrder` 去掉，页文件保留。删除笔记是删掉整个 `.yep` 目录。

## 4. 墓碑

删除不把对象从队列里抹掉。被删的 id 记入 `deletedObjectIds`。撤销一次删除时，`changeMarks` 的 `restore` 会把这个 id 从墓碑里拿掉。

笔画文件一旦写过就不再改（`_spillStrokes` 看到文件已存在就跳过）。区域橡皮不是改旧文件，而是把旧 id 墓碑掉，把剩下的片段写成新 id。对象橡皮只墓碑，不产生新笔画。

页面删除也是墓碑，见上一节。图层的 `deletedLayerIds` 字段已经在格式里，批量加层和合并图层还没做。

## 5. 内存里的笔记

`OpenNote` 持有目录名、manifest、以及已经展开笔画引用的 `pages`。`PageFile.layers` 从底到顶。界面上的图层面板把这个列表倒过来画，让上面的图层出现在列表上方。

`NotePage` 自己留着 `_note`。保存函数返回新的 `OpenNote`，调用方把它赋回去。不要假设 `Vault` 会改你手里的旧对象。

编辑发生时就写盘：笔画抬笔、橡皮抬笔、文字框创建、失焦、移动结束、缩放结束。关掉笔记只丢掉撤销栈，不把写入推迟到退出。

## 6. 笔画

### 6.1 存什么

`StrokeObject`：`id`、`tool`（现在钢笔写 `"pen"`）、`color`（`0xAARRGGBB`，钢笔是黑）、`baseWidth`（3）、`points`、`finalized`。

`StrokePoint`：`x`、`y`、相对起笔的 `time`（秒）、`width`、`height`、`opacity`、`pressure`，以及可选的 `azimuth`、`altitude`。宽和高在采样时就算进点里。抬笔后这条笔画的几何不再改，渲染直接用这些点，不用新的粗细算法重算旧笔画。

预测点不进模型，也不进文件。现在没有读取 iOS 合并触点，也没有读取 Android 的 historical batch。Flutter 的 `PointerEvent` 来一个点就收一个点。

没有压感时用 `missingPressure = 0.5`。没有姿态时方位角和高度角为 null。透明度缺省是 1。

### 6.2 谁可以落笔

`drawsInk`：`stylus`、`invertedStylus`、`mouse` 落笔。手指不落笔，用来平移。文字工具下，笔和鼠标也可以平移，直到长按被识别成文字手势。

`sampleFromPointer` 从 `PointerEvent` 取压感。只有手写笔事件才读 `orientation` 和 `tilt`：方位角用 `orientation`，高度角用 `π/2 - tilt`。鼠标走 `mouseSample`，压感和透明度用固定值，没有姿态。

iOS 上 Pencil 的悬停会以鼠标事件进来（系统把 hover 标成 mouse）。悬停只用来画光标，不产生笔画。

### 6.3 拟合

实时和存盘用同一套点。`appendCausalPoint` 在书写过程中追加，`finishStroke` 在抬笔时把尾巴刷出来。`bakePenStroke` / `causalPaint` 是对一整串原始点再跑一遍，得到最终点列。

已经画过的点只追加，不回头改。`raw` 和 `painted` 不能是同一个列表。`appendCausalPoint` 发现两者 `identical` 时会复制 `painted`。实时笔画上不要再对已经因果绘制过的点调用 `pointsForPaint`，否则会再拟合一次。

拟合是局部二次曲线，不是整条笔画的一次拟合。窗口是 `raw[index-1, index+2)`，x 和 y 分开做最小二乘：`p(t) = at² + bt + c`。`StrokeCursor` 里的 `_PolySums` 用滑动窗口加减样本，避免每个点都从头求和。

端点钉在真实采样上：曲线先算出来，再按参数把起点和终点的误差线性摊回去，所以曲线一定经过这两个采样点。

一条弦怎么处理，由 `_appendArc` 决定：

| 条件 | 结果 |
| --- | --- |
| 弦长 &lt; 1.5（`minFitDistance`） | 直接收下终点，不做拟合 |
| 弦长 &lt; 8（`directJoinDistance`）且估计弓高 &lt; 0.7 | 直线，点距 `straightSpacing = 1` |
| 二次曲线中点偏离弦超过允许弓高 | 退回直线 |
| 其余 | 沿二次曲线采样。允许弓高 &gt; 2 时用更密的 `tightSpacing = 0.4`，否则仍是 1 |

允许弓高来自转角估计，再乘 1.35，并且至少为 1。转角太平或接近掉头时，估计弓高为 0，短弦就会走直线。

lookahead：还没连上的点要等后面的样本再画。相邻采样间隔 &lt; 14 ms 等 2 个，&lt; 24 ms 等 3 个，更慢等 4 个。抬笔时 `finishStroke(hold: 1)` 把尾巴放出。

长笔画上的圆仍可能有棱，是因为被拒绝的弦和过短的弦变成直线之后不会再改。拟合只看见附近三个样本，看不见整圆。改这个行为要改 `_appendArc`，不要在绘制时把已经存下的点重算一遍。

`paintStroke` 用圆头 `drawLines` 把点连起来。`paintStrokeCover` 用更宽的圆头描同一条线，给橡皮的遮盖和挖空用。

## 7. 绘制与瓦片

`PageCanvas` 把各页纵向排开。`InteractiveViewer` 的 `panEnabled` 是 false，`scaleEnabled` 是 true，缩放范围 0.2 到 4。平移是 `NotePage` 自己在变换矩阵上做的，不交给 InteractiveViewer。

已提交的墨迹按 256 point 的瓦片画。每块瓦片是一张 `ui.Image`，外包 `RepaintBoundary`，`FilterQuality.none`，按 1:1 贴上。像素尺寸是 `round(瓦片宽高 × devicePixelRatio × viewScale)`。

`viewScale` 是 InteractiveViewer 的缩放。捏合过程中不重切瓦片，旧图被拉大或缩小。`onInteractionEnd` 以及缩放按钮结束时，如果比例变化超过 0.04，`_settleScale` 才更新 `viewScale`。比例一变，瓦片代数加一，旧图丢掉，按新分辨率重画。没画完的笔画先用矢量盖住空隙。

`picture.toImage` 是异步的。抬笔后不要先清掉实时墨迹再等瓦片；实时层要留到对应瓦片落地。区域橡皮打上去的 `InkPatch` 也是先画进相关瓦片，`onApplied` 之后再收起补丁。

正在画的长笔画不每帧重画整页。`_LiveInk` 把已经稳定的前缀冻成瓦片：保留末端约 8 个点做矢量尾巴，每多大约 24 个点再烘一批。尾巴仍然是矢量。

对象橡皮接触到的笔画放进 `StrokeFade`。拖动时用 `saveLayer` 加 `Color(0x99FFFFFF)` 的 `paintStrokeCover`（外扩 2）把整条笔画洗淡，边缘和内部同一透明度。抬笔时先铺不透明白遮盖，再 `BlendMode.dstOut` 挖掉（外扩 3），然后清掉 fade。区域橡皮不画拖尾，碰到瓦片就立刻 dstOut。

橡皮擦只处理 `pageId` 匹配的那一页。命中用 `_InkLocator`，格子 48 point，只测附近笔画。`strokeHitsEraser` 可以带 `near`，格子外的点和线段直接跳过。

瓦片是按图层对象光栅化的。文字框画在各层墨迹之上，按图层顺序叠，没有和上层笔画交错。所以上层笔画不会盖住下层文字框。

## 8. 橡皮和撤销

`InkTool`：`pen`、`text`、`objectEraser`、`regionEraser`。橡皮半径 `eraserRadius = 14`。

对象橡皮：与橡皮路径相交的整条笔画进入 fade，抬笔时这些 id 墓碑。用的是已经在 fade 里的列表，不再全页重扫。

区域橡皮：`eraseRegion` 把被擦到的采样切掉。整条擦掉得到空列表。部分擦掉得到若干新 `StrokeObject`，新 id，`finalized: true`，点还是原来的宽高，只是少了被擦的那段。旧 id 墓碑。

`NotePage._commit` 把一次修改压进线性撤销栈，并清空重做栈。一条 `_MarkEdit` 记录 `pageId`、`layerId`、`added`（新出现的笔画）和 `tombstoned`（新墓碑）。撤销交换这两边，再调用 `changeMarks`。换页不清栈。关闭笔记页面时栈随 State 一起消失。再次打开后，上次的操作不能撤。

撤销一次删除会去掉对应墓碑。区域橡皮的撤销会恢复旧笔画并去掉新片段。对象橡皮的 dstOut 会挖掉笔画底下的墨迹；撤销只把这条笔画重画出来，底下被挖掉的墨迹不会自动补回。撤销一条普通钢笔（只有被拿掉的 id，没有先前的挖空）会清掉瓦片并重画剩余笔画。

当前可画图层是该页最上面一层可见且未锁定的图层。锁定或隐藏的层不接收新笔画。

## 9. 手势

`NotePage` 用 `TickerProviderStateMixin`。

单指触摸平移。速度用相邻位移做指数混合。抬笔时速度大于 80 才开始惯性；Ticker 里每帧乘 `exp(-3.4 * dt)`，速度小于 12 停止。两指会把 `_multiTouch` 置上，抬笔时清掉速度，不甩出去。InteractiveViewer 自己的双指缩放惯性保持 Flutter 默认，不要把 `interactionEndFrictionCoefficient` 改成 1，那会让动画更长。

手指正在平移时如果笔落下，`_endMoving` 结束平移，并把当前还没抬起的触摸指针放进 `_ignoredFingers`。这些手指要抬起之后才能再平移。

文字工具下，笔和鼠标也可以平移。文字长按计时开始时 `onSuppressPan` 把该指针从平移里拿掉。按下后移动超过 10 point（`_textSlop`）且长按还没成立，取消文字计时，这次手势继续当平移。

进入笔记后，第一页居中一次：视口中心对齐页面中心，四周留 48。

缩放按钮和捏合结束走同一个 `_settleScale`。

## 10. 文字框

文字框属于创建时所在的图层。模型是 `TextBox`：`id`、`version`、`x`、`y`、`width`、`height`、`source`。`source` 是 Markdown 原文。

创建：文字工具里按下约 380 ms，再向右下拖。预览先半透明，宽至少 72 且高至少 44 后变为不透明。只在抬笔并且尺寸够了才 `onTextCreate`。点一下空白不是创建。

编辑：短按已有文字框进入编辑，显示 `TextField` 里的源码。失焦后 `MarkdownBody` 用 `markdown_widget` 的 `MarkdownBlock` 渲染，字号不随框缩放。正文 14，一级标题 22，二级 18，三级 16。列表缩进用渲染器自己的固定缩进。空源码显示灰色「文字」。编辑时有边框，退出编辑后没有边框。

公式按这个渲染器的写法，放在 `$` 和 `$` 之间，由 `flutter_math_fork` 的 `Math.tex` 绘制。`lib/src/ui/markdown_math.dart` 是该库示例里的 LaTeX 语法，不要再写一套只认 `\frac` 的解析器。

选中：长按已有文字框，或在文字工具里悬停该框时按下侧面按键。可以拖动框体移动，拖右下角外的方块改大小。旁边菜单是「编辑」和「删除」。删除走墓碑，因此在撤销栈上。离开文字工具会清掉正在编辑的 id 和选中 id。

失焦提交必须先读 `TextEditingController.text`，再把 `widget.box.source` 写回 controller。顺序反了会把刚打的字用旧的空源码盖掉。`onChanged` 把草稿放进 `_textDrafts`，不为此 `setState`。`_persistText` 只有在这次保存的源码、宽、高仍然对得上草稿时才丢掉草稿，避免一次较晚的空保存把字抹掉。

点空白（不是长按，也不是超过 10 point 的滑动）调用 `onTextBlur`：结束编辑、取消选中、`FocusManager` 收起焦点。进入笔记时 `_editingTextId` 从 null 开始，并在首帧后 unfocus，所以不会有文字框自动进入编辑。

中文输入法的组字过程，以及文字编辑本身的撤销，还没做。那是日程第 8 阶段。文字框的删除已经在墨迹撤销栈上。

## 11. 侧面按键

侧面按键不是 Apple Pencil 专有功能。各平台只报告“侧面按键按下了”，应用决定做什么。

Dart 接口是 `StylusSideButton`（`lib/src/input/stylus_side_button.dart`）：

- `addListener` / `removeListener`：界面注册。同时有多个监听时，只调用最后注册的那个。笔记页在库页面之上，所以打开笔记时由笔记页接收。
- `report(Offset? globalPosition)`：平台或测试调用。坐标是全局坐标，平台不知道时传 null。

原生走方法通道 `dev.yetanotherpage/stylus`，方法名 `sideButton`。参数是 Map，可含数字 `x`、`y`。没有坐标就传空 Map 或省略。`main` 里 `stylusSideButton.attachPlatform()` 接上这个通道。

iOS 适配在 `ios/Runner/AppDelegate.swift` 的 `ApplePencilSideButton`。iOS 17.5 及以上用 `UIPencilInteraction`，只在捏笔阶段 `.ended` 时上报。悬停位置有就带上，没有就不带。不要在这里决定打开工具栏还是选中文字框。

另一个平台的笔有侧面按键时，在该平台的原生代码里对同一通道调用 `sideButton`。也可以在 Dart 里直接 `stylusSideButton.report`。不要再写一个 Pencil 专用的 Dart API。

笔记页收到按键后：文字工具且悬停在某个文字框上，则选中该框；否则切换圆弧工具栏。库页面收到按键后：若悬停在某条笔记上，打开重命名和删除菜单。

圆弧工具栏（`tool_arc.dart`）项为钢笔、文字、对象橡皮、区域橡皮、撤销、重做。撤销和重做不关闭圆弧；切换工具会关闭。轨道透明，只有图标圆和一条细线。半径 108，上半弧。

## 12. 悬停光标

非触摸的 hover 显示笔尖。钢笔是小点，橡皮是白底黑边的圆，半径用 `eraserRadius`。文字工具不显示点，也不显示圆，但仍把位置交给 `onTip` 和 `onTextHover`，供侧面按键选中文字框。按下绘画时笔尖位置继续更新。不要对悬停坐标再做几何预测。

## 13. 图层与笔记库界面

图层面板可以隐藏、锁定、上移、下移。顺序存在 `layerOrder`。隐藏的图层不画。锁定的图层不能当当前绘制层。

库页面：长按一条笔记出现「重命名」「删除」。悬停加侧面按键也打开这个菜单。打开笔记先进入 `_NoteGate`，显示「正在打开笔记」，`openNote` 完成后再构建 `NotePage`。新建笔记同样走这道门。不要在进度圈还在转时 `pumpAndSettle`。

## 14. 测试

```bash
flutter test
```

`test/vault_test.dart` 用临时目录，是普通 `test()`，不要放进 `FakeAsync` 里等真实磁盘。`test/stroke_test.dart` 锁拟合和采样。`test/eraser_test.dart` 锁命中和裁切。`test/text_box_test.dart` 是界面测试，确认标题、列表、强调和 `$...$` 公式真的画出来。`test/widget_test.dart` 用内存库，并确认侧面按键能打开和关掉工具弧。

`TextEditingController` 必须在 State 里 dispose。内存库新增 `NoteLibrary` 方法时要补上，否则测试编译不过。

## 15. 改代码时不要破坏的事

- 抬笔后的笔画几何不再修改。新外观写成新 id，旧 id 墓碑。
- 预测点、合并触点的重复点，都不要写进 `StrokeObject`。
- `raw` 与 `painted` 不要共享同一个列表。实时笔画的 `shouldRepaint` 不要去比较一份还在被改的列表。
- 橡皮擦的补丁和 fade 带 `pageId`，不要画到其他页。
- 区域橡皮只重画碰到的瓦片。
- 单指才有惯性。两指平移不要甩。
- 文字失焦时先读 controller，再重置 controller。
- 最后一页不能删。删页是墓碑，文件留下。
- 侧面按键的平台代码只调用 `sideButton` / `report`。
- 不要把 PencilKit 用于存储或渲染。

## 16. 已知限制

这些是当前实现的边界，不是下一处小改动要偷偷改掉的行为。

- 荧光笔、套索、图片、PDF、导出、文件夹嵌套、局域网同步都还没做。
- 中文组字过程仍会进入文本框。文字编辑没有单独的撤销栈。
- 长笔画上的圆可能有直线棱，原因见第 6.3 节。
- 对象橡皮挖空时会挖掉底下的墨迹，撤销不能把底下补回来。
- 文字框画在全部墨迹之上，不按图层和笔画交错。
- 双指移动没有我们自己的惯性。捏合的收尾动画是 InteractiveViewer 的。
- iOS 合并触点和 Android historical 点还没接进采样。
- 页外的笔画是画的时候裁掉，不是存盘时裁成页内几何。

## 17. 加一个平台的侧面按键

1. 在该平台收到笔的侧面按键，并且手势已经结束。
2. 若平台能提供当时的指针位置，换成 Flutter 视图里的全局坐标。
3. 调用方法通道 `dev.yetanotherpage/stylus` 的 `sideButton`，参数 `{"x": ..., "y": ...}`。没有坐标就不要编一个。
4. 不要在原生代码里打开菜单或切换工具。笔记页和库页面已经监听 `stylusSideButton`。

iOS 的对照实现是 `ApplePencilSideButton` 和 `PencilSqueezeRelay`。
